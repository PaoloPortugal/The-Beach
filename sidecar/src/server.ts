// The WebSocket server Godot connects to (NOTES.md -> S01, Security rules).
// Loopback only; every connection must carry the startup token; anything a
// browser could send (an Origin header) is refused. One client at a time: a
// new authenticated connection replaces the old one (Godot reconnecting).
import http from 'node:http'
import crypto from 'node:crypto'
import type { Duplex } from 'node:stream'
import { WebSocketServer, WebSocket, type RawData } from 'ws'
import { checkCommand, PROTOCOL_VERSION } from './protocol.ts'
import { runCommand } from './commands.ts'
import type { Entry, Outgoing, Registry } from './registry.ts'
import type { Log } from './log.ts'

export const HOST = '127.0.0.1'
/** Largest message accepted from Godot. Chat text is the only big field. */
export const MAX_INCOMING = 4 * 1024 * 1024

export interface ServerOptions {
  registry: Registry
  token: string
  log: Log
  /** 0 picks a free port. */
  port?: number
}

export interface RunningServer {
  port: number
  close(): Promise<void>
}

export function tokenMatches(header: string | undefined, token: string): boolean {
  if (typeof header !== 'string') return false
  const expected = Buffer.from(`Bearer ${token}`)
  const given = Buffer.from(header)
  return given.length === expected.length && crypto.timingSafeEqual(given, expected)
}

export async function startServer(opts: ServerOptions): Promise<RunningServer> {
  const { registry, token, log } = opts
  const wss = new WebSocketServer({ noServer: true, maxPayload: MAX_INCOMING, perMessageDeflate: false })
  let client: WebSocket | null = null
  let port = 0

  const http_ = http.createServer((_req, res) => {
    // Only WebSocket upgrades are served.
    res.writeHead(426, { connection: 'close' })
    res.end()
  })

  const refuse = (socket: Duplex, status: string, why: string) => {
    log.warn(`refused a connection: ${why}`)
    socket.end(`HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`)
    socket.destroy()
  }

  http_.on('upgrade', (req, socket, head) => {
    socket.on('error', () => {})
    // Browsers always send Origin; Godot's client never does (checked in its
    // source and against a live Godot). Any Origin means a web page.
    if (req.headers.origin !== undefined) return refuse(socket, '403 Forbidden', 'has an Origin header')
    // Guards against DNS rebinding, on top of the Origin check.
    if (req.headers.host !== `${HOST}:${port}`) return refuse(socket, '403 Forbidden', 'wrong Host')
    if (req.method !== 'GET' || req.url !== '/') return refuse(socket, '404 Not Found', 'wrong path')
    if (!tokenMatches(req.headers.authorization, token)) return refuse(socket, '401 Unauthorized', 'bad token')
    wss.handleUpgrade(req, socket, head, (ws) => accept(ws))
  })

  const send = (ws: WebSocket, msg: Outgoing) => {
    if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg))
  }

  registry.setSink((msg) => { if (client) send(client, msg) })

  const sendSnapshot = (entry: Entry) => {
    const s = registry.snapshot(entry.id)
    if (s && client) send(client, { type: 'session.snapshot', session: s })
  }

  function accept(ws: WebSocket) {
    if (client) {
      log.info('a new client replaced the old one')
      client.close(4000, 'replaced')
    }
    client = ws
    log.info('client connected')
    // Sent in one go, so no event can land between hello and sync.completed.
    send(ws, {
      type: 'hello',
      protocol: PROTOCOL_VERSION,
      providers: [...registry.providers.values()].map((p) => {
        const notices = registry.providerNotices(p.id)
        return {
          provider: p.id, name: p.name, ...(p.launchOptions ? { launch_options: structuredClone(p.launchOptions) } : {}),
          ...(p.capabilities ? { capabilities: structuredClone(p.capabilities) } : {}),
          ...(notices.length > 0 ? { notices } : {}),
        }
      }),
    })
    for (const s of registry.snapshots()) send(ws, { type: 'session.snapshot', session: s })
    send(ws, { type: 'sync.completed' })

    ws.on('message', (data: RawData, isBinary: boolean) => {
      if (ws !== client) return // replaced: its late commands are ignored
      if (isBinary) return send(ws, { type: 'error', code: 'invalid_message', message: 'binary messages are not used' })
      void handle(ws, data.toString())
    })
    ws.on('close', () => {
      if (client === ws) {
        client = null
        log.info('client disconnected')
      }
    })
    ws.on('error', (e) => log.warn(`client socket error: ${e.message}`))
  }

  async function handle(ws: WebSocket, text: string) {
    let parsed: unknown
    try { parsed = JSON.parse(text) } catch {
      return send(ws, { type: 'error', code: 'invalid_message', message: 'not valid JSON' })
    }
    const rawId = (parsed as { id?: unknown } | null)?.id
    const id = typeof rawId === 'string' && rawId.length > 0 ? rawId : undefined
    const checked = checkCommand(parsed)
    if (!checked.ok) {
      return send(ws, { type: 'error', ...(id ? { id } : {}), code: 'invalid_message', message: checked.message })
    }
    const cmd = checked.value
    if (id === undefined) {
      // Only extension commands can lack an id in the schema; replies need one.
      return send(ws, { type: 'error', code: 'invalid_message', message: 'commands need an id' })
    }
    const outcome = await runCommand(registry, cmd, sendSnapshot, log)
    if (outcome.ok) send(ws, { type: 'ok', id, ...(outcome.result ? { result: outcome.result } : {}) })
    else send(ws, { type: 'error', id, code: outcome.code, message: outcome.message })
    outcome.after()
  }

  await new Promise<void>((resolve, reject) => {
    http_.once('error', reject)
    http_.listen(opts.port ?? 0, HOST, () => resolve())
  })
  port = (http_.address() as { port: number }).port

  return {
    port,
    close: () => new Promise<void>((resolve) => {
      for (const ws of wss.clients) ws.terminate()
      wss.close()
      http_.closeAllConnections()
      http_.close(() => resolve())
    }),
  }
}
