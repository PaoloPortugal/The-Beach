// Sessions running anywhere on this machine (NOTES.md -> S04 -> Sessions
// running elsewhere): `claude agents --json`, the documented way to read
// session state from outside Claude Code. Stored sessions that are still
// running in some terminal (one the game started before a restart, or one
// the user started) aren't offered for resuming, or the conversation would
// run twice.
import { execFile } from 'node:child_process'

/** How long `claude agents --json` may take (about 0.8 s measured). */
export const RUNNING_TIMEOUT_MS = 5000
/** Its output is a small JSON array; anything bigger is refused. */
export const RUNNING_MAX_OUTPUT = 4 * 1024 * 1024

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/**
 * The session ids in `claude agents --json` output whose process is alive
 * (the entry has a `pid`). Background sessions whose process has exited are
 * listed too, without one: those aren't running. Anything that isn't the
 * documented shape gives nothing. Exported for tests.
 */
export function parseRunning(out: string): Set<string> {
  return new Set(parseAgents(out).map((a) => a.sessionId))
}

/** One live session from `claude agents --json`: its id (lowercase), process and state. */
export interface AgentEntry {
  sessionId: string
  pid: number
  /** `busy`, `waiting` or `idle`; anything else (a newer value) is kept as is. */
  status: string
}

/**
 * The entries of `claude agents --json` whose process is alive (a numeric
 * `pid`) with a UUID `sessionId`. Exported for tests.
 */
export function parseAgents(out: string): AgentEntry[] {
  let list: unknown
  try { list = JSON.parse(out) } catch { return [] }
  if (!Array.isArray(list)) return []
  const entries: AgentEntry[] = []
  for (const e of list) {
    if (typeof e !== 'object' || e === null) continue
    const { pid, sessionId, status } = e as { pid?: unknown; sessionId?: unknown; status?: unknown }
    if (typeof pid !== 'number' || !Number.isInteger(pid) || pid <= 0) continue
    if (typeof sessionId !== 'string' || !UUID.test(sessionId)) continue
    entries.push({ sessionId: sessionId.toLowerCase(), pid, status: typeof status === 'string' ? status : '' })
  }
  return entries
}

/** `agents`: the entries themselves (S07 matches them by process id); absent when a test gives ids only. */
export type Running = { ids: Set<string>; agents?: AgentEntry[] } | { none: string }

/**
 * Asks Claude Code which sessions are running: an argument array, no shell,
 * the clean environment launches get. Fails soft: when agent view is off
 * (the command refuses), the command is missing, slow or prints something
 * else, the answer is `none` with the reason, and nothing is left out.
 */
export function runningSessions(
  claude: string, env: Record<string, string>,
  limits: { timeoutMs?: number; maxOutput?: number } = {},
): Promise<Running> {
  return new Promise((resolve) => {
    try {
      execFile(claude, ['agents', '--json'], {
        env, timeout: limits.timeoutMs ?? RUNNING_TIMEOUT_MS, maxBuffer: limits.maxOutput ?? RUNNING_MAX_OUTPUT,
        windowsHide: true, shell: false,
      }, (err, stdout, stderr) => {
        if (err) {
          resolve({ none: (String(stderr).trim().split(/\r?\n/)[0] || err.message).slice(0, 200) })
          return
        }
        const trimmed = String(stdout).trim()
        if (!trimmed.startsWith('[')) {
          resolve({ none: 'claude agents --json printed no list' })
          return
        }
        const agents = parseAgents(trimmed)
        resolve({ ids: new Set(agents.map((a) => a.sessionId)), agents })
      })
    } catch (e) {
      // Thrown at once rather than reported (e.g. EINVAL for a .cmd on Windows).
      resolve({ none: String(e instanceof Error ? e.message : e).slice(0, 200) })
    }
  })
}
