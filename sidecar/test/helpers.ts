// Test helpers: an in-process server and a client that checks every message
// it receives against the protocol schema.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import http from 'node:http'
import crypto from 'node:crypto'
import assert from 'node:assert/strict'
import { WebSocket } from 'ws'
import { startServer, type RunningServer } from '../src/server.ts'
import { Registry } from '../src/registry.ts'
import { checkMessage } from '../src/protocol.ts'
import { readBridgeFile } from '../src/providers/claude/bridge.ts'
import type { Log } from '../src/log.ts'
import type { Provider } from '../src/provider.ts'

export type Msg = Record<string, unknown> & { type: string }

/**
 * A fresh folder for a provider's run folders (ClaudeOptions.sessionsDir):
 * no test touches the user's real app data folder (NOTES.md -> S07).
 */
export function tempSessionsDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'sessions-'))
}

/** Where a launched session's bridge would connect: its bridge file, named in its MCP config's env. */
export function bridgeOf(env: { BRIDGE_FILE?: string }): { port: number; token: string } {
  const where = readBridgeFile(env.BRIDGE_FILE ?? '')
  assert.ok(where, 'the session has a usable bridge file')
  return where
}

export class RecordingLog implements Log {
  lines: string[] = []
  info(m: string) { this.lines.push(`info ${m}`) }
  warn(m: string) { this.lines.push(`warn ${m}`) }
  error(m: string) { this.lines.push(`error ${m}`) }
}

export interface TestServer extends RunningServer {
  token: string
  registry: Registry
  log: RecordingLog
}

export async function testServer(providers: Provider[] = []): Promise<TestServer> {
  const token = crypto.randomBytes(32).toString('hex')
  const log = new RecordingLog()
  const registry = new Registry(providers, log)
  const server = await startServer({ registry, token, log })
  return { ...server, token, registry, log }
}

export class Client {
  readonly ws: WebSocket
  readonly received: Msg[] = []
  private readonly waiters: (() => void)[] = []
  private nextId = 0
  /** Messages that failed the schema. Tests assert this stays empty. */
  readonly invalid: { msg: unknown; why: string }[] = []

  constructor(ws: WebSocket) {
    this.ws = ws
    ws.on('message', (data) => {
      const msg = JSON.parse(data.toString()) as Msg
      const checked = checkMessage(msg)
      if (!checked.ok) this.invalid.push({ msg, why: checked.message })
      this.received.push(msg)
      for (const w of this.waiters.splice(0)) w()
    })
  }

  /** Waits for the next unread message matching `pred`, and consumes everything up to it. */
  async next(pred: string | ((m: Msg) => boolean), timeoutMs = 2000): Promise<Msg> {
    const match = typeof pred === 'string' ? (m: Msg) => m.type === pred : pred
    const deadline = Date.now() + timeoutMs
    for (;;) {
      const i = this.received.findIndex(match)
      if (i >= 0) return this.received.splice(0, i + 1)[i]!
      const left = deadline - Date.now()
      if (left <= 0) {
        throw new Error(`timed out waiting for ${typeof pred === 'string' ? pred : 'a message'}; ` +
          `unread: ${JSON.stringify(this.received.map((m) => m.type))}`)
      }
      await new Promise<void>((resolve) => {
        const t = setTimeout(resolve, left)
        this.waiters.push(() => { clearTimeout(t); resolve() })
      })
    }
  }

  /** Reads the connect sequence: hello, snapshots, sync.completed. */
  async sync(): Promise<{ hello: Msg; snapshots: Msg[] }> {
    const hello = await this.next('hello')
    const snapshots: Msg[] = []
    for (;;) {
      const m = await this.next(() => true)
      if (m.type === 'sync.completed') return { hello, snapshots }
      assert.equal(m.type, 'session.snapshot', 'only snapshots between hello and sync.completed')
      snapshots.push(m)
    }
  }

  send(msg: unknown): void {
    this.ws.send(typeof msg === 'string' ? msg : JSON.stringify(msg))
  }

  /** Sends a command with a fresh id and resolves with its ok/error reply. */
  async command(cmd: Record<string, unknown>): Promise<Msg> {
    const id = `c${++this.nextId}`
    this.send({ ...cmd, id })
    return this.next((m) => (m.type === 'ok' || m.type === 'error') && m.id === id)
  }

  /** Resolves once nothing new has arrived for `ms`. Returns the unread messages. */
  async quiet(ms = 150): Promise<Msg[]> {
    let count = -1
    while (count !== this.received.length) {
      count = this.received.length
      await new Promise((r) => setTimeout(r, ms))
    }
    return [...this.received]
  }

  close(): Promise<void> {
    return new Promise((resolve) => {
      if (this.ws.readyState === WebSocket.CLOSED) return resolve()
      this.ws.once('close', () => resolve())
      this.ws.close()
    })
  }
}

export function connect(port: number, token: string, headers: Record<string, string> = {}): Promise<Client> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/`, {
      headers: { authorization: `Bearer ${token}`, ...headers },
    })
    const client = new Client(ws)
    ws.once('open', () => resolve(client))
    ws.once('error', reject)
    ws.once('unexpected-response', (_req, res) => reject(new Error(`status ${res.statusCode}`)))
  })
}

/**
 * A raw upgrade request, so tests control every header (the ws client adds
 * its own). Resolves with the HTTP status the server answered.
 */
export function rawUpgrade(
  port: number, headers: Record<string, string | undefined>, opts: { path?: string; method?: string } = {},
): Promise<number> {
  return new Promise((resolve, reject) => {
    const h: Record<string, string> = {
      connection: 'Upgrade', upgrade: 'websocket',
      'sec-websocket-version': '13', 'sec-websocket-key': crypto.randomBytes(16).toString('base64'),
      host: `127.0.0.1:${port}`,
    }
    for (const [k, v] of Object.entries(headers)) {
      if (v === undefined) delete h[k]
      else h[k] = v
    }
    const req = http.request({
      host: '127.0.0.1', port, path: opts.path ?? '/', method: opts.method ?? 'GET', headers: h,
      setHost: false,
    })
    req.on('upgrade', (res, socket) => { socket.destroy(); resolve(res.statusCode ?? 0) })
    req.on('response', (res) => { res.resume(); resolve(res.statusCode ?? 0) })
    req.on('error', reject)
    req.end()
  })
}
