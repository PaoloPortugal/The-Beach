// The relay: the mode of the sidecar executable that a provider's CLI runs
// as a command hook (`<sidecar> relay <relay file>`), for hook events that
// can't be posted over HTTP by the CLI itself (Claude Code's SessionStart;
// NOTES.md -> S02 -> Following the conversation). It reads the hook's JSON
// from stdin and posts it to the sidecar's hook endpoint with the session's
// token, both from the relay file (readable only by this user; the token
// never goes on a command line). Generic: the provider writes the file.
//
// It must never get in the CLI's way: it prints nothing to stdout (a
// SessionStart hook's stdout becomes Claude's context), gives up after a
// short time, and always exits 0, whatever happens.
import fs from 'node:fs'
import http from 'node:http'
import type { Readable } from 'node:stream'

export const RELAY_FILE_VERSION = 1
/** How long the whole relay may take: reading stdin and posting. */
export const RELAY_TIMEOUT_MS = 2000
/** Largest hook input forwarded (SessionStart's is a few hundred bytes). */
const MAX_INPUT = 1024 * 1024

export interface RelayFile {
  version: typeof RELAY_FILE_VERSION
  /** The hook endpoint, on loopback. */
  url: string
  /** The session's hook token. */
  token: string
}

/** Writes a relay file readable only by this user. */
export function writeRelayFile(file: string, r: Omit<RelayFile, 'version'>): void {
  const body: RelayFile = { version: RELAY_FILE_VERSION, ...r }
  fs.writeFileSync(file, JSON.stringify(body), { mode: 0o600 })
}

/** Reads and checks a relay file; null if it's missing or wrong. Only loopback HTTP is accepted. */
export function readRelayFile(file: string): RelayFile | null {
  let r: Partial<RelayFile>
  try { r = JSON.parse(fs.readFileSync(file, 'utf8')) as Partial<RelayFile> } catch { return null }
  if (r.version !== RELAY_FILE_VERSION || typeof r.url !== 'string' || typeof r.token !== 'string') return null
  if (!/^[0-9a-f]{64}$/.test(r.token)) return null
  let u: URL
  try { u = new URL(r.url) } catch { return null }
  if (u.protocol !== 'http:' || u.hostname !== '127.0.0.1' || !u.port) return null
  return r as RelayFile
}

function readInput(input: Readable, signal: AbortSignal): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    let size = 0
    const fail = (e: Error) => { input.removeAllListeners('data'); reject(e) }
    signal.addEventListener('abort', () => fail(new Error('timed out reading the hook input')), { once: true })
    input.on('data', (c: Buffer | string) => {
      const b = typeof c === 'string' ? Buffer.from(c) : c
      size += b.length
      if (size > MAX_INPUT) return fail(new Error('hook input too large'))
      chunks.push(b)
    })
    input.on('end', () => resolve(Buffer.concat(chunks)))
    input.on('error', fail)
  })
}

function post(r: RelayFile, body: Buffer, signal: AbortSignal): Promise<number> {
  return new Promise((resolve, reject) => {
    const req = http.request(r.url, {
      method: 'POST', signal,
      headers: { authorization: `Bearer ${r.token}`, 'content-type': 'application/json', 'content-length': body.length },
    }, (res) => { res.resume(); res.on('end', () => resolve(res.statusCode ?? 0)) })
    req.on('error', reject)
    req.end(body)
  })
}

/**
 * Runs the relay mode. Never throws and never writes to stdout; problems
 * go to `log` (stderr, which Claude Code only shows in debug output),
 * without the hook's content. The caller exits 0.
 */
export async function runRelay(args: string[], input: Readable, log: (m: string) => void,
  timeoutMs = RELAY_TIMEOUT_MS): Promise<void> {
  const timer = new AbortController()
  const t = setTimeout(() => timer.abort(), timeoutMs)
  try {
    const r = args.length === 1 ? readRelayFile(args[0]!) : null
    if (!r) return log('relay: no usable relay file')
    const body = await readInput(input, timer.signal)
    const status = await post(r, body, timer.signal)
    if (status !== 200) log(`relay: the sidecar answered ${status}`)
  } catch (e) {
    log(`relay: ${e instanceof Error ? e.message : String(e)}`)
  } finally {
    clearTimeout(t)
  }
}
