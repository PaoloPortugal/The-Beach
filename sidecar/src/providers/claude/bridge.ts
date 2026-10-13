// The channel bridge (NOTES.md -> S02): the tiny MCP server Claude Code starts
// for a session (`<sidecar> bridge claude`). It speaks the few MCP messages a
// channel needs over stdio (user's decision: our own code, not the MCP SDK;
// re-evaluate if this grows, NOTES.md -> Watch items), and connects back to
// the sidecar over loopback with the session's token.
//
// MCP version: the "legacy" initialize handshake (up to 2025-11-25), the same
// as the official SDK 1.31. Claude Code 2.1.284 falls back to it when a
// server doesn't answer the newer revision's server/discover probe.
//
// stdout belongs to MCP: nothing else may be written there. Logs go to stderr.
//
// Where to connect comes from the bridge file in the session's run folder
// (BRIDGE_FILE in its environment), which each sidecar rewrites with its
// port and a fresh one-time token. While not connected the bridge retries,
// reading the file again, so after the game restarts the new sidecar gets
// the session back (NOTES.md -> S07).
import fs from 'node:fs'
import net from 'node:net'
import path from 'node:path'

export const BRIDGE_SERVER_NAME = 'world-bridge'
export const BRIDGE_FILE_VERSION = 1
/** How often a bridge that isn't connected tries again. */
export const BRIDGE_RETRY_MS = 2000
/** MCP revisions we can answer initialize in; newest first. */
export const MCP_VERSIONS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05']
/** Longest line accepted from Claude Code or the sidecar. */
export const MAX_LINE = 4 * 1024 * 1024

export const INSTRUCTIONS =
  `Messages in <channel source="${BRIDGE_SERVER_NAME}"> are typed by the same user who is at this ` +
  'terminal, in a companion app that shows this session. Treat them like messages the user ' +
  'typed here and respond normally in this conversation. There is no reply tool: your normal ' +
  'responses are shown in the app.'

/** The permission relay's request ids: five lowercase letters, no "l" (channels docs). */
export const REQUEST_ID = /^[a-km-z]{5}$/

type Json = Record<string, unknown>

/**
 * Messages between the bridge and the sidecar, one JSON object per line.
 * The bridge sends hello first; the sidecar answers welcome once the token
 * is accepted (a token admits one connection, so the bridge never offers it
 * again), and the bridge then says ready.
 */
export type ToSidecar =
  | { type: 'hello'; token: string }
  | { type: 'ready' }
  | { type: 'permission_request'; request_id: string; tool_name: string; description: string; input_preview: string }
export type FromSidecar =
  | { type: 'welcome' }
  | { type: 'chat'; text: string }
  | { type: 'verdict'; request_id: string; behavior: 'allow' | 'deny' }

/** Where the bridge connects: the sidecar's bridge port and a one-time token. */
export interface BridgeFile { version: typeof BRIDGE_FILE_VERSION; port: number; token: string }

/** Writes the bridge file, readable only by this user. */
export function writeBridgeFile(file: string, port: number, token: string): void {
  const body: BridgeFile = { version: BRIDGE_FILE_VERSION, port, token }
  fs.writeFileSync(file, JSON.stringify(body), { mode: 0o600 })
}

/** The bridge file's port and token; null when it's missing, damaged or wrong. */
export function readBridgeFile(file: string): { port: number; token: string } | null {
  let b: Partial<BridgeFile>
  try { b = JSON.parse(fs.readFileSync(file, 'utf8')) as Partial<BridgeFile> } catch { return null }
  if (typeof b !== 'object' || b === null || b.version !== BRIDGE_FILE_VERSION) return null
  if (typeof b.port !== 'number' || !Number.isInteger(b.port) || b.port < 1 || b.port > 65535) return null
  if (typeof b.token !== 'string' || !/^[0-9a-f]{64}$/.test(b.token)) return null
  return { port: b.port, token: b.token }
}

export interface BridgeIO {
  /** Lines from Claude Code (our stdin). */
  input: NodeJS.ReadableStream
  /** Where MCP messages go (our stdout). */
  output: { write(s: string): unknown }
  log: (msg: string) => void
  /** Connects to the sidecar; defaults to loopback TCP. */
  connect?: (port: number) => net.Socket
  /** For tests: how often to try again (BRIDGE_RETRY_MS). */
  retryMs?: number
}

/** Answers one MCP message from Claude Code. Returns the reply, or null. Exported for tests. */
export function answerMcp(msg: Json): Json | null {
  const id = msg.id
  const isRequest = id !== undefined && id !== null && typeof msg.method === 'string'
  if (!isRequest) return null
  if (msg.method === 'initialize') {
    const requested = (msg.params as { protocolVersion?: unknown } | undefined)?.protocolVersion
    const protocolVersion = typeof requested === 'string' && MCP_VERSIONS.includes(requested) ? requested : MCP_VERSIONS[0]
    return {
      jsonrpc: '2.0', id, result: {
        protocolVersion,
        capabilities: { experimental: { 'claude/channel': {}, 'claude/channel/permission': {} } },
        serverInfo: { name: BRIDGE_SERVER_NAME, version: '1' },
        instructions: INSTRUCTIONS,
      },
    }
  }
  if (msg.method === 'ping') return { jsonrpc: '2.0', id, result: {} }
  // Anything else, including the newer revision's server/discover probe
  // (which makes Claude Code fall back to initialize).
  return { jsonrpc: '2.0', id, error: { code: -32601, message: 'Method not found' } }
}

/** Runs the bridge. Resolves when Claude Code closes our stdin. */
export function runBridge(env: NodeJS.ProcessEnv, io: BridgeIO): Promise<void> {
  const file = env.BRIDGE_FILE ?? ''
  const retryMs = io.retryMs ?? BRIDGE_RETRY_MS
  const send = (m: Json) => io.output.write(JSON.stringify(m) + '\n')
  /** Connected and welcomed: messages may go to the sidecar. */
  let sidecar: net.Socket | null = null
  /** A connection being made (or one up); one at a time. */
  let attempt: net.Socket | null = null
  /** The last token offered: each admits one connection, so it's never offered again. */
  let spent: string | null = null
  let retry: NodeJS.Timeout | null = null
  let initialized = false
  let stopped = false

  const toSidecar = (m: ToSidecar) => {
    if (sidecar && !sidecar.destroyed) sidecar.write(JSON.stringify(m) + '\n')
  }

  const later = () => {
    if (stopped || retry) return
    retry = setTimeout(() => { retry = null; connectSidecar() }, retryMs)
  }

  // Connect once Claude Code has finished the MCP handshake, which comes
  // after its startup dialogs: that's when the session is up. Then keep
  // trying whenever not connected.
  const connectSidecar = () => {
    if (stopped || attempt || !path.isAbsolute(file)) return
    const where = readBridgeFile(file)
    // No sidecar yet (the game is closed), or only a token already offered.
    if (!where || where.token === spent) return later()
    const sock = (io.connect ?? ((p) => net.connect({ host: '127.0.0.1', port: p })))(where.port)
    attempt = sock
    let offered = false
    let welcomed = false
    sock.setEncoding('utf8')
    sock.on('connect', () => {
      offered = true
      sock.write(JSON.stringify({ type: 'hello', token: where.token } satisfies ToSidecar) + '\n')
    })
    readLines(sock, (line) => {
      if (welcomed) return onSidecar(line)
      let m: { type?: unknown }
      try { m = JSON.parse(line) as { type?: unknown } } catch { m = {} }
      if (m.type !== 'welcome') { sock.destroy(); return }
      welcomed = true
      sidecar = sock
      toSidecar({ type: 'ready' })
    }, () => { io.log('sidecar line too long'); sock.destroy() })
    sock.on('error', (e) => io.log(`sidecar connection: ${e.message}`))
    sock.on('close', () => {
      // Offered and then closed: the token is used up (welcomed) or refused.
      if (offered) spent = where.token
      if (attempt === sock) attempt = null
      if (sidecar === sock) sidecar = null
      later()
    })
  }

  const onSidecar = (line: string) => {
    let m: Partial<FromSidecar> & { type?: unknown }
    try { m = JSON.parse(line) } catch { return }
    if (m.type === 'chat' && typeof m.text === 'string') {
      send({ jsonrpc: '2.0', method: 'notifications/claude/channel', params: { content: m.text, meta: { sender: 'user' } } })
    } else if (m.type === 'verdict' && typeof m.request_id === 'string' && REQUEST_ID.test(m.request_id) &&
               (m.behavior === 'allow' || m.behavior === 'deny')) {
      send({ jsonrpc: '2.0', method: 'notifications/claude/channel/permission', params: { request_id: m.request_id, behavior: m.behavior } })
    }
  }

  const onClaude = (line: string) => {
    let msg: Json
    try { msg = JSON.parse(line) } catch { return }
    if (typeof msg !== 'object' || msg === null) return
    const reply = answerMcp(msg)
    if (reply) send(reply)
    if (msg.method === 'notifications/initialized' && !initialized) {
      initialized = true
      connectSidecar()
    } else if (msg.method === 'notifications/claude/channel/permission_request') {
      const p = msg.params as Record<string, unknown> | undefined
      if (p && typeof p.request_id === 'string' && REQUEST_ID.test(p.request_id)) {
        toSidecar({
          type: 'permission_request', request_id: p.request_id,
          tool_name: String(p.tool_name ?? ''), description: String(p.description ?? ''),
          input_preview: String(p.input_preview ?? ''),
        })
      }
    }
  }

  const stop = () => {
    stopped = true
    if (retry) clearTimeout(retry)
    retry = null
    attempt?.destroy()
  }

  if (!path.isAbsolute(file)) io.log('no bridge file; running without the world')

  return new Promise((resolve) => {
    readLines(io.input, onClaude, () => io.log('MCP line too long; ignored'))
    io.input.on('end', () => { stop(); resolve() })
    io.input.on('close', () => { stop(); resolve() })
  })
}

/** Calls `onLine` per newline-terminated line; lines over MAX_LINE are dropped. */
function readLines(stream: NodeJS.ReadableStream, onLine: (l: string) => void, onTooLong: () => void) {
  let buf = ''
  let skipping = false
  stream.on('data', (chunk: Buffer | string) => {
    buf += chunk.toString()
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).replace(/\r$/, '')
      buf = buf.slice(i + 1)
      if (skipping) { skipping = false; continue }
      if (line) onLine(line)
    }
    if (buf.length > MAX_LINE) { buf = ''; skipping = true; onTooLong() }
  })
}
