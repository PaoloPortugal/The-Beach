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
import { TEST_SESSIONS_DIR } from './launch/app-data.ts'

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

/**
 * How Godot started it (the player's settings): `outsideSessions` false is
 * `serve --no-outside-sessions` (S08); `programPaths`, by provider, the
 * programs set by hand, `--program-path <provider>=<path>` (S02).
 */
export interface ServeOptions {
  outsideSessions?: boolean
  programPaths?: Record<string, string>
  /**
   * False: no look for the providers' programs at start (serve() under a
   * Godot suite, TEST_SESSIONS_DIR set: a suite never runs the real
   * program). Default true.
   */
  lookAtStart?: boolean
}

const PROGRAM_PATH = /^([a-z][a-z0-9_]*)=(.+)$/s

/**
 * `serve`'s arguments (main.ts): `--no-outside-sessions` and
 * `--program-path <provider>=<path>`, once per provider; anything else is
 * refused.
 */
export function serveOptions(args: string[]): ServeOptions {
  let outsideSessions = true
  const programPaths: Record<string, string> = {}
  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!
    if (arg === '--no-outside-sessions') {
      outsideSessions = false
      continue
    }
    if (arg === '--program-path') {
      const m = PROGRAM_PATH.exec(args[++i] ?? '')
      if (!m) throw new Error('--program-path needs <provider>=<path>')
      if (m[1]! in programPaths) throw new Error(`--program-path given twice for ${m[1]}`)
      programPaths[m[1]!] = m[2]!
      continue
    }
    throw new Error(`unexpected arguments: ${arg}`)
  }
  return { outsideSessions, ...(Object.keys(programPaths).length > 0 ? { programPaths } : {}) }
}

/**
 * Before listening: the player's settings first, so with outside sessions off
 * none is shown at start and `claude` isn't asked for them, and a program set
 * by hand is the one the restore uses (checked: one that fails is kept and
 * reported not found; a provider unknown or without program_path is skipped,
 * so an old setting never stops the start). Then the restore.
 */
export async function prepare(registry: Registry, providers: Provider[], log: Log, o: ServeOptions): Promise<void> {
  if (o.outsideSessions === false) for (const p of providers) p.setOutsideSessions?.(false)
  for (const [id, file] of Object.entries(o.programPaths ?? {})) {
    const p = registry.providers.get(id)
    if (!p?.setProgramPath || !('program_path' in (p.capabilities ?? {}))) {
      log.warn(`--program-path: no provider ${JSON.stringify(id)} with program_path; ignored`)
      continue
    }
    try {
      await p.setProgramPath(file, true)
    } catch (e) {
      log.error(`${id}: couldn't use the program set by hand: ${e instanceof Error ? e.message : String(e)}`)
    }
  }
  // Every other program_path provider looks at once, in the background, so
  // the game knows before a session is asked for (hello's program, or
  // provider.program once it's found); the restore shares that look.
  if (o.lookAtStart === false) log.info('a test run: programs not looked for at start')
  for (const p of o.lookAtStart === false ? [] : providers) {
    if (!p.findProgram || !('program_path' in (p.capabilities ?? {})) || registry.providerProgramOf(p.id)) continue
    p.findProgram().catch((e) => log.error(`${p.id}: couldn't look for its program: ${e instanceof Error ? e.message : String(e)}`))
  }
  await restoreSessions(registry, providers, log)
}

export async function serve(providers: Provider[], log: Log = stderrLog, o: ServeOptions = {}): Promise<void> {
  const token = crypto.randomBytes(32).toString('hex')
  const registry = new Registry(providers, log)
  await prepare(registry, providers, log, { lookAtStart: !process.env[TEST_SESSIONS_DIR], ...o })
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
