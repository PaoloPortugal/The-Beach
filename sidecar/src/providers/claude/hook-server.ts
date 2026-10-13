// The sidecar's endpoint for Claude Code's HTTP hooks (NOTES.md -> S02 ->
// Seeing the session). Every launched session posts its hooks here with its
// own token (NOTES.md -> Security rules: loopback only, every request
// authenticated, browsers refused). Claude Code treats any failure (non-2xx,
// no connection, timeout) as "no decision" and carries on with its own
// prompts, so a problem here never allows anything.
import http from 'node:http'
import crypto from 'node:crypto'
import type { Log } from '../../log.ts'

export const HOOK_PATH = '/hook'
/**
 * Where the status line relay posts Claude Code's status line input
 * (C08), with the session's hook token. Answered at once, with nothing.
 */
export const STATUS_PATH = '/status'
/** Largest hook body accepted. Tool inputs can be whole files (Write). */
export const MAX_HOOK_BODY = 16 * 1024 * 1024

export type HookPayload = Record<string, unknown> & { hook_event_name: string }

export interface HookHandlers {
  /**
   * One hook from this session. The returned object, if any, is sent back
   * as the hook's JSON output; nothing means an empty 200 (no decision).
   * A handler may hold the hook open (a question waiting for the user);
   * `gone` fires if Claude Code stops waiting first (timeout, exit).
   */
  onHook(payload: HookPayload, gone: AbortSignal): Record<string, unknown> | void | Promise<Record<string, unknown> | void>
  /** One status line input from this session (C08): a JSON object, untrusted. */
  onStatus?(payload: Record<string, unknown>): void
}

export interface HookLink {
  readonly token: string
  unregister(): void
}

export class HookServer {
  private readonly server = http.createServer((req, res) => void this.handle(req, res))
  private readonly slots = new Map<string, HookHandlers>()
  private readonly log: Log
  port = 0

  constructor(log: Log) {
    this.log = log
  }

  /**
   * Listens on `preferred` (the port kept from earlier starts, which
   * sessions still running post their hooks to; NOTES.md -> S07), or on any
   * free port when there's none or it's taken.
   */
  async start(preferred?: number): Promise<number> {
    if (this.port) return this.port
    if (preferred !== undefined) {
      try {
        await this.listen(preferred)
      } catch (e) {
        this.log.warn(`the kept hook port ${preferred} is taken (${(e as NodeJS.ErrnoException).code ?? 'error'}); using another`)
        await this.listen(0)
      }
    } else {
      await this.listen(0)
    }
    this.port = (this.server.address() as { port: number }).port
    return this.port
  }

  private listen(port: number): Promise<void> {
    return new Promise((resolve, reject) => {
      const failed = (e: Error) => reject(e)
      this.server.once('error', failed)
      this.server.listen(port, '127.0.0.1', () => {
        this.server.off('error', failed)
        resolve()
      })
    })
  }

  /** The URL hooks post to. */
  get url(): string {
    return `http://127.0.0.1:${this.port}${HOOK_PATH}`
  }

  /** The URL the status line relay posts to (C08). */
  get statusUrl(): string {
    return `http://127.0.0.1:${this.port}${STATUS_PATH}`
  }

  /** A new session's token; valid until unregistered. */
  register(handlers: HookHandlers): HookLink {
    return this.adopt(crypto.randomBytes(32).toString('hex'), handlers)!
  }

  /**
   * A token issued by an earlier sidecar, from a running session's record
   * (S07): its hooks carry it until Claude Code exits. Null if it isn't the
   * shape we issue, or is already in use.
   */
  adopt(token: string, handlers: HookHandlers): HookLink | null {
    if (!/^[0-9a-f]{64}$/.test(token) || this.slots.has(token)) return null
    this.slots.set(token, handlers)
    return { token, unregister: () => { if (this.slots.get(token) === handlers) this.slots.delete(token) } }
  }

  close(): Promise<void> {
    this.slots.clear()
    this.server.closeAllConnections()
    return new Promise((resolve) => this.server.close(() => resolve()))
  }

  private async handle(req: http.IncomingMessage, res: http.ServerResponse) {
    const reply = (code: number, body?: Record<string, unknown>) => {
      if (res.headersSent) return
      // Refused before reading: drain the body so the answer isn't lost to a
      // reset, and don't keep the connection for another request.
      if (!req.readableEnded) req.resume()
      res.writeHead(code, {
        ...(body ? { 'content-type': 'application/json' } : {}),
        ...(code === 200 ? {} : { connection: 'close' }),
      })
      res.end(body ? JSON.stringify(body) : '')
    }
    // Browsers always send Origin; Claude Code doesn't. A Host other than
    // our own address means DNS rebinding.
    if (req.headers.origin !== undefined || req.headers.host !== `127.0.0.1:${this.port}`) return reply(403)
    if (req.method !== 'POST' || (req.url !== HOOK_PATH && req.url !== STATUS_PATH)) return reply(404)
    const handlers = this.find(req.headers.authorization)
    if (!handlers) {
      this.log.warn('refused a hook request: bad token')
      return reply(401)
    }

    let body: string
    try { body = await readBody(req) } catch { return reply(413) }
    let payload: unknown
    try { payload = JSON.parse(body) } catch { return reply(400) }
    if (req.url === STATUS_PATH) {
      if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return reply(400)
      try { handlers.onStatus?.(payload as Record<string, unknown>) } catch (e) {
        this.log.error(`status line input failed: ${e instanceof Error ? e.message : String(e)}`)
      }
      return reply(200)
    }
    if (typeof payload !== 'object' || payload === null || typeof (payload as HookPayload).hook_event_name !== 'string') {
      return reply(400)
    }
    const gone = new AbortController()
    res.on('close', () => { if (!res.writableEnded) gone.abort() })
    try {
      const out = await handlers.onHook(payload as HookPayload, gone.signal)
      reply(200, out ?? undefined)
    } catch (e) {
      // Never a decision: Claude Code falls back to its own behaviour.
      this.log.error(`hook ${(payload as HookPayload).hook_event_name} failed: ${e instanceof Error ? e.message : String(e)}`)
      reply(500)
    }
  }

  private find(auth: string | undefined): HookHandlers | null {
    const m = /^Bearer ([0-9a-f]{64})$/.exec(auth ?? '')
    if (!m) return null
    // Constant-time comparison against each registered token.
    const given = Buffer.from(m[1]!)
    for (const [t, handlers] of this.slots) {
      const b = Buffer.from(t)
      if (b.length === given.length && crypto.timingSafeEqual(b, given)) return handlers
    }
    return null
  }
}

function readBody(req: http.IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    let size = 0
    req.on('data', (c: Buffer) => {
      size += c.length
      if (size > MAX_HOOK_BODY) { reject(new Error('too large')); req.destroy(); return }
      chunks.push(c)
    })
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    req.on('error', reject)
  })
}
