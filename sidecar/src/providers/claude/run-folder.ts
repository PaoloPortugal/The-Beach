// What a session's run folder records so a later sidecar can find the
// session again (NOTES.md -> S07): `session.json` (Claude's session id, the
// project, the hook port and token it was launched with), and the kept hook
// port in the folder above the run folders. Run folders are untrusted
// input: every field is checked on read, and a record that fails any check
// is not used.
import fs from 'node:fs'
import path from 'node:path'
import type { Project } from '../../protocol.ts'

export const RUN_RECORD_VERSION = 1
export const RUN_RECORD_FILE = 'session.json'
export const HOOK_PORT_FILE = 'hook-port.json'
/**
 * The process id of the sidecar holding the session now. Another game
 * running at the same time (or a test's sidecar) leaves a folder alone
 * while its holder is alive, so it never takes over a session that is held.
 */
export const HOLDER_FILE = 'holder.pid'
/** Run folders' names: `session-` and mkdtemp's six characters. Nothing else in the folder is touched. */
export const RUN_DIR_NAME = /^session-[A-Za-z0-9]{6}$/

export interface RunRecord {
  version: typeof RUN_RECORD_VERSION
  /** Claude's session id (a UUID); rewritten when /clear or /resume switches it. */
  native_id: string
  project: Project
  /** The port the session's hooks post to, fixed at launch. */
  hook_port: number
  /** The token they carry, fixed at launch too. */
  hook_token: string
  started_at: string
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const TOKEN = /^[0-9a-f]{64}$/

export function isPort(v: unknown): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= 1 && v <= 65535
}

/** Writes the run folder's record, readable only by this user. */
export function writeRunRecord(runDir: string, r: Omit<RunRecord, 'version'>): void {
  const body: RunRecord = { version: RUN_RECORD_VERSION, ...r }
  fs.writeFileSync(path.join(runDir, RUN_RECORD_FILE), JSON.stringify(body), { mode: 0o600 })
}

/** The run folder's record, or null when it's missing, damaged or fails a check. */
export function readRunRecord(runDir: string): RunRecord | null {
  let r: Partial<Record<keyof RunRecord, unknown>>
  try { r = JSON.parse(fs.readFileSync(path.join(runDir, RUN_RECORD_FILE), 'utf8')) } catch { return null }
  if (typeof r !== 'object' || r === null) return null
  if (r.version !== RUN_RECORD_VERSION) return null
  if (typeof r.native_id !== 'string' || !UUID.test(r.native_id)) return null
  if (!isPort(r.hook_port)) return null
  if (typeof r.hook_token !== 'string' || !TOKEN.test(r.hook_token)) return null
  if (typeof r.started_at !== 'string' || Number.isNaN(Date.parse(r.started_at))) return null
  const p = r.project as Partial<Project> | null
  if (typeof p !== 'object' || p === null || typeof p.path !== 'string' || !path.isAbsolute(p.path)) return null
  if (p.name !== undefined && typeof p.name !== 'string') return null
  return {
    version: RUN_RECORD_VERSION, native_id: r.native_id, hook_port: r.hook_port, hook_token: r.hook_token,
    started_at: new Date(r.started_at).toISOString(), project: { path: p.path, ...(p.name !== undefined ? { name: p.name } : {}) },
  }
}

/** The kept hook port, or null when none (or nothing valid) is kept. */
export function readHookPort(dir: string): number | null {
  try {
    const port = (JSON.parse(fs.readFileSync(path.join(dir, HOOK_PORT_FILE), 'utf8')) as { port?: unknown }).port
    return isPort(port) ? port : null
  } catch {
    return null
  }
}

export function writeHookPort(dir: string, port: number): void {
  fs.writeFileSync(path.join(dir, HOOK_PORT_FILE), JSON.stringify({ port }), { mode: 0o600 })
}

/** Marks this sidecar as the one holding the session in `runDir`. */
export function writeHolder(runDir: string): void {
  fs.writeFileSync(path.join(runDir, HOLDER_FILE), String(process.pid), { mode: 0o600 })
}
