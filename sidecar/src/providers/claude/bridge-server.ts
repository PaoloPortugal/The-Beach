// The sidecar's end of the channel bridge link: a loopback TCP server that
// each session's bridge connects to with that session's token (NOTES.md ->
// Security rules: loopback only, every connection authenticated). One line
// of JSON per message; see bridge.ts for the messages.
import net from 'node:net'
import crypto from 'node:crypto'
import { MAX_LINE, REQUEST_ID, type FromSidecar } from './bridge.ts'
import type { Log } from '../../log.ts'

/** How long a new connection has to present its token. */
export const HELLO_TIMEOUT_MS = 5000

export interface BridgeHandlers {
  /** The session's Claude Code finished its MCP handshake: the session is up. */
  onReady(): void
  onPermissionRequest(p: { request_id: string; tool_name: string; description: string; input_preview: string }): void
  /** The bridge went away (Claude Code exited, or the link broke). */
  onClose(): void
}

export interface BridgeLink {
  readonly token: string
  /** Sent back in welcome: proves to the bridge that this is the sidecar that wrote its file. */
  readonly proof: string
  /** Sends to the bridge. False if it isn't connected. */
  send(msg: FromSidecar): boolean
  readonly connected: boolean
  unregister(): void
}

interface Slot { handlers: BridgeHandlers; socket: net.Socket | null; used: boolean; proof: string }

export class BridgeServer {
  private readonly server = net.createServer((s) => this.accept(s))
  private readonly slots = new Map<string, Slot>()
  private readonly log: Log
  port = 0

  constructor(log: Log) {
    this.log = log
  }

  async start(): Promise<number> {
    if (this.port) return this.port
    await new Promise<void>((resolve, reject) => {
      this.server.once('error', reject)
      this.server.listen(0, '127.0.0.1', () => resolve())
    })
    this.port = (this.server.address() as net.AddressInfo).port
    return this.port
  }

  /** A new session's token. Each token admits one connection, once. */
  register(handlers: BridgeHandlers): BridgeLink {
    const token = crypto.randomBytes(32).toString('hex')
    const proof = crypto.randomBytes(32).toString('hex')
    const slot: Slot = { handlers, socket: null, used: false, proof }
    this.slots.set(token, slot)
    return {
      token,
      proof,
      get connected() { return slot.socket !== null && !slot.socket.destroyed },
      send: (msg) => {
        if (!slot.socket || slot.socket.destroyed) return false
        slot.socket.write(JSON.stringify(msg) + '\n')
        return true
      },
      unregister: () => {
        this.slots.delete(token)
        slot.socket?.destroy()
      },
    }
  }

  close(): Promise<void> {
    for (const slot of this.slots.values()) slot.socket?.destroy()
    this.slots.clear()
    return new Promise((resolve) => this.server.close(() => resolve()))
  }

  private accept(sock: net.Socket) {
    sock.setEncoding('utf8')
    sock.on('error', () => {})
    let slot: Slot | null = null
    let buf = ''
    const timer = setTimeout(() => { if (!slot) sock.destroy() }, HELLO_TIMEOUT_MS)

    sock.on('data', (chunk: string) => {
      buf += chunk
      if (buf.length > MAX_LINE) { this.log.warn('bridge sent an overlong line; dropped it'); sock.destroy(); return }
      let i
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i)
        buf = buf.slice(i + 1)
        let m: Record<string, unknown>
        try { m = JSON.parse(line) } catch { sock.destroy(); return }
        if (!slot) {
          const found = m.type === 'hello' && typeof m.token === 'string' ? this.find(m.token) : null
          if (!found || found.used) {
            this.log.warn('refused a bridge connection: bad or reused token')
            sock.destroy()
            return
          }
          clearTimeout(timer)
          found.used = true
          found.socket = sock
          slot = found
          // The bridge checks the proof, knows its token is spent, and says ready.
          sock.write(JSON.stringify({ type: 'welcome', proof: found.proof } satisfies FromSidecar) + '\n')
          continue
        }
        this.handle(slot, m)
      }
    })
    sock.on('close', () => {
      clearTimeout(timer)
      if (slot && slot.socket === sock) {
        slot.socket = null
        slot.handlers.onClose()
      }
    })
  }

  private find(token: string): Slot | null {
    // Constant-time comparison against each registered token.
    const given = Buffer.from(token)
    for (const [t, slot] of this.slots) {
      const b = Buffer.from(t)
      if (b.length === given.length && crypto.timingSafeEqual(b, given)) return slot
    }
    return null
  }

  private handle(slot: Slot, m: Record<string, unknown>) {
    if (m.type === 'ready') slot.handlers.onReady()
    else if (m.type === 'permission_request' && typeof m.request_id === 'string' && REQUEST_ID.test(m.request_id)) {
      slot.handlers.onPermissionRequest({
        request_id: m.request_id,
        tool_name: String(m.tool_name ?? ''),
        description: String(m.description ?? ''),
        input_preview: String(m.input_preview ?? ''),
      })
    }
  }
}
