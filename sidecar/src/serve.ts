// The sidecar's server mode (NOTES.md -> S01).
//
// Godot starts this with an argument array and a pipe. Contract:
// - stdout carries exactly one line, the handshake:
//   {"type":"ready","protocol":1,"port":<port>,"token":"<hex>"}
//   Godot then connects to ws://127.0.0.1:<port>/ with
//   "Authorization: Bearer <token>". Nothing else is ever written to stdout.
// - stderr carries logs (never session content).
// - When stdin closes (Godot quit or crashed, on any OS), the sidecar exits.
//   Launched sessions keep running on their own.
import crypto from 'node:crypto'
import { startServer } from './server.ts'
import { Registry } from './registry.ts'
import { stderrLog, type Log } from './log.ts'
import { PROTOCOL_VERSION } from './protocol.ts'
import type { Provider } from './provider.ts'

/** How long shutdown may take before the process exits anyway. */
const SHUTDOWN_GRACE_MS = 3000

/**
 * How long the ready line waits for providers to find the sessions still
 * running from before (S07): asking Claude Code takes about a second, at
 * most 5 s, plus finding it. One found later still comes, as a snapshot.
 */
export const RESTORE_WAIT_MS = 8000

/**
 * Lets each provider take back its sessions still running (S07), before the
 * server listens: the kept hook port is taken first thing. Never fails the
 * start; waits at most `waitMs`.
 */
export async function restoreSessions(registry: Registry, providers: Provider[], log: Log, waitMs = RESTORE_WAIT_MS): Promise<void> {
  const all = Promise.all(providers.map(async (p) => {
    if (!p.restore) return
    try {
      await p.restore((make, o) => registry.adopt(p, make, o), (notice) => registry.providerNotice(p.id, notice))
    } catch (e) {
      log.error(`${p.id}: couldn't look for running sessions: ${e instanceof Error ? e.message : String(e)}`)
    }
  }))
  let timer: NodeJS.Timeout | undefined
  const late = new Promise<void>((resolve) => { timer = setTimeout(() => { log.warn('still looking for running sessions; starting anyway'); resolve() }, waitMs) })
  await Promise.race([all, late])
  clearTimeout(timer)
}

/** How Godot started it: `outsideSessions` false is `serve --no-outside-sessions` (the player's setting, S08). */
export interface ServeOptions { outsideSessions?: boolean }

/** `serve`'s arguments (main.ts): only `--no-outside-sessions`; anything else is refused. */
export function serveOptions(args: string[]): ServeOptions {
  const flags = new Set(args)
  flags.delete('--no-outside-sessions')
  if (flags.size > 0) throw new Error(`unexpected arguments: ${[...flags].join(' ')}`)
  return { outsideSessions: !args.includes('--no-outside-sessions') }
}

/**
 * Before listening: the player's setting first, so with outside sessions off
 * none is shown at start and `claude` isn't asked for them; then the restore.
 */
export async function prepare(registry: Registry, providers: Provider[], log: Log, o: ServeOptions): Promise<void> {
  if (o.outsideSessions === false) for (const p of providers) p.setOutsideSessions?.(false)
  await restoreSessions(registry, providers, log)
}

export async function serve(providers: Provider[], log: Log = stderrLog, o: ServeOptions = {}): Promise<void> {
  const token = crypto.randomBytes(32).toString('hex')
  const registry = new Registry(providers, log)
  await prepare(registry, providers, log, o)
  const server = await startServer({ registry, token, log })

  let stopping = false
  const stop = async (why: string) => {
    if (stopping) return
    stopping = true
    log.info(`stopping: ${why}`)
    setTimeout(() => process.exit(0), SHUTDOWN_GRACE_MS).unref()
    await Promise.allSettled([server.close(), ...providers.map((p) => p.shutdown())])
    process.exit(0)
  }

  // Exit with the parent. 'end' covers a clean close, 'close' and 'error'
  // cover the pipe breaking; ignored or closed stdin means nobody owns us.
  process.stdin.on('end', () => void stop('stdin closed'))
  process.stdin.on('close', () => void stop('stdin closed'))
  process.stdin.on('error', () => void stop('stdin error'))
  process.stdin.resume()
  process.on('SIGINT', () => void stop('interrupted'))
  process.on('SIGTERM', () => void stop('terminated'))

  process.stdout.write(JSON.stringify({ type: 'ready', protocol: PROTOCOL_VERSION, port: server.port, token }) + '\n')
  log.info(`listening on 127.0.0.1:${server.port}`)
}
