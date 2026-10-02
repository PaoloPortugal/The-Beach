// Claude Code's stored sessions (NOTES.md -> S04): transcripts under
// <config dir>/projects/<project slug>/<session id>.jsonl, read-only. Used to
// list sessions that can be resumed and to show a resumed session's chat.
// The line format isn't a documented interface (NOTES.md -> Watch items):
// anything unrecognised is skipped, and a file that can't be read is left
// out of the list.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import type { HistoryMessage, StoredSession } from '../../protocol.ts'
import { unwrapChannel, parseHandback, parseTaskNotification } from './hooks.ts'

/**
 * Where a session was started, from the transcript's `entrypoint`. Only
 * terminal sessions are listed: the Claude desktop app and IDE extensions
 * keep their own session lists (NOTES.md -> Deliberate limitations; open
 * question for the user whether to include them).
 */
export const LISTED_ENTRYPOINTS = new Set(['cli'])
/** How much of each file's start and end is read to describe it. */
const PEEK = 64 * 1024
/** The newest this many sessions are listed. */
export const LIST_MAX = 200
/** A transcript larger than this isn't read for history (too slow for the world to wait on). */
const HISTORY_MAX_BYTES = 64 * 1024 * 1024

/**
 * Slash commands run in the terminal (/clear, /resume, /model ...) and
 * their output, which Claude Code writes as user entries (not always
 * isMeta; 2.1.285): `<command-name>/clear</command-name>`, then a system
 * local_command entry, after an isMeta `<local-command-caveat>`. Not chat.
 */
const LOCAL_COMMAND = /^<(command-name|command-message|command-args|local-command-stdout|local-command-stderr|local-command-caveat)>/

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/** Claude Code's projects folder, following CLAUDE_CONFIG_DIR like Claude Code does. */
export function projectsDir(env: NodeJS.ProcessEnv = process.env): string {
  return path.join(env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude'), 'projects')
}

export interface StoredInfo extends StoredSession {
  /** The transcript file. */
  file: string
}

function peek(file: string, size: number): { head: string; tail: string } {
  const fd = fs.openSync(file, 'r')
  try {
    const read = (at: number, n: number) => {
      const buf = Buffer.alloc(n)
      return buf.subarray(0, fs.readSync(fd, buf, 0, n, at)).toString('utf8')
    }
    const head = read(0, Math.min(PEEK, size))
    const tail = size > PEEK ? read(size - PEEK, PEEK) : ''
    return { head, tail }
  } finally { fs.closeSync(fd) }
}

/**
 * What a conversation can be called (NOTES.md -> S02 -> Titles): the name
 * it was given (`custom-title`: --name or /rename), the title Claude Code
 * generated for it (`ai-title`), and its first user message.
 */
export interface Titles { custom: string | null; ai: string | null; prompt: string | null }

export const NO_TITLES: Titles = { custom: null, ai: null, prompt: null }

/** The title shown, in Claude Code's own order; null if there's nothing yet. */
export function pickTitle(t: Titles): string | null {
  const line = t.prompt?.trim().split('\n', 1)[0]!.trim().slice(0, 80) || null
  return t.custom || t.ai || line
}

/** The title entries of one transcript line (custom-title, ai-title), or null. */
export function titleIn(e: Record<string, unknown>): Partial<Titles> | null {
  if (e.type === 'custom-title' && typeof e.customTitle === 'string') return { custom: e.customTitle }
  if (e.type === 'ai-title' && typeof e.aiTitle === 'string') return { ai: e.aiTitle }
  return null
}

/** A conversation's titles, from its transcript's first and last 64 KiB. */
export function readTitles(file: string): Titles {
  let head: string, tail: string
  try { ({ head, tail } = peek(file, fs.statSync(file).size)) } catch { return { ...NO_TITLES } }
  return titlesIn(lines(head, false), tail ? lines(tail, true) : [])
}

function titlesIn(first: Record<string, unknown>[], last: Record<string, unknown>[]): Titles {
  const out: Titles = { ...NO_TITLES }
  for (const e of first) {
    out.prompt ??= userText(e)
    if (out.prompt) break
  }
  // Claude Code writes them again later on; the newest wins.
  for (const e of [...first, ...last]) Object.assign(out, titleIn(e))
  return out
}

/** Whole JSON lines of a chunk (a cut-off first or last line is dropped). */
function lines(chunk: string, cutStart: boolean): Record<string, unknown>[] {
  const parts = chunk.split('\n')
  if (cutStart) parts.shift()
  const out: Record<string, unknown>[] = []
  for (const l of parts) {
    try {
      const v: unknown = JSON.parse(l)
      if (typeof v === 'object' && v !== null) out.push(v as Record<string, unknown>)
    } catch { /* cut off, or not JSON */ }
  }
  return out
}

/** The text a user entry shows, or null if it isn't something the user said. */
function userText(e: Record<string, unknown>): string | null {
  if (e.type !== 'user' || e.isSidechain === true || e.isCompactSummary === true) return null
  const content = (e.message as { content?: unknown } | undefined)?.content
  let text: string | null = null
  if (typeof content === 'string') text = content
  else if (Array.isArray(content)) {
    const texts = content.filter((c) => c?.type === 'text' && typeof c.text === 'string').map((c) => c.text as string)
    if (texts.length === 0 || content.some((c) => c?.type === 'tool_result')) return null
    text = texts.join('\n')
  }
  if (text === null) return null
  const t = text.trim()
  if (parseTaskNotification(t) || parseHandback(t) || /^\[Request interrupted by user/.test(t) || LOCAL_COMMAND.test(t)) return null
  const unwrapped = unwrapChannel(t)
  // Claude Code's own injected context is marked meta; a world message is
  // too, but it's the user's (it arrives through our channel).
  if (e.isMeta === true && unwrapped === t) return null
  return unwrapped
}

/** Describes one transcript, or null if it isn't a listable session. */
export function describe(file: string): StoredInfo | null {
  const id = path.basename(file, '.jsonl')
  if (!UUID.test(id)) return null
  let st: fs.Stats
  try { st = fs.statSync(file) } catch { return null }
  if (!st.isFile() || st.size === 0) return null
  let head: string, tail: string
  try { ({ head, tail } = peek(file, st.size)) } catch { return null }
  const first = lines(head, false)
  const last = tail ? lines(tail, true) : []
  let cwd: string | null = null
  let entrypoint: string | null = null
  for (const e of first) {
    if (!cwd && typeof e.cwd === 'string') cwd = e.cwd
    if (!entrypoint && typeof e.entrypoint === 'string') entrypoint = e.entrypoint
  }
  if (!cwd || !entrypoint || !LISTED_ENTRYPOINTS.has(entrypoint)) return null
  const title = pickTitle(titlesIn(first, last))
  if (!title) return null // nothing was ever said: nothing to resume
  return {
    provider: 'claude', native_id: id, project: { path: cwd }, title,
    updated_at: st.mtime.toISOString(), file,
  }
}

function samePath(a: string, b: string): boolean {
  const norm = (p: string) => path.resolve(p).replace(/[\\/]+$/, '')
  return process.platform === 'win32' ? norm(a).toLowerCase() === norm(b).toLowerCase() : norm(a) === norm(b)
}

/** Resumable sessions, newest first, optionally only one project's. */
export function listStored(opts: { dir?: string; project?: string; exclude?: Set<string> } = {}): StoredInfo[] {
  const dir = opts.dir ?? projectsDir()
  let slugs: string[]
  try { slugs = fs.readdirSync(dir) } catch { return [] }
  // Newest files first, so only the ones that will be listed are read.
  const files: { file: string; mtime: number }[] = []
  for (const slug of slugs) {
    let names: string[]
    try { names = fs.readdirSync(path.join(dir, slug)) } catch { continue }
    for (const name of names) {
      if (!name.endsWith('.jsonl') || opts.exclude?.has(name.slice(0, -6))) continue
      const file = path.join(dir, slug, name)
      const mtime = fs.statSync(file, { throwIfNoEntry: false })?.mtimeMs
      if (mtime !== undefined) files.push({ file, mtime })
    }
  }
  files.sort((a, b) => b.mtime - a.mtime)
  const out: StoredInfo[] = []
  for (const { file } of files) {
    const info = describe(file)
    if (!info || (opts.project && !samePath(info.project.path, opts.project))) continue
    out.push(info)
    if (out.length >= LIST_MAX) break
  }
  return out
}

/** Finds one stored session by id, wherever its project is. */
export function findStored(nativeId: string, dir = projectsDir()): StoredInfo | null {
  if (!UUID.test(nativeId)) return null
  let slugs: string[]
  try { slugs = fs.readdirSync(dir) } catch { return null }
  for (const slug of slugs) {
    const file = path.join(dir, slug, `${nativeId}.jsonl`)
    if (fs.existsSync(file)) return describe(file)
  }
  return null
}

/**
 * Whether a transcript holds a reply from Claude (an assistant entry of the
 * main conversation): an earlier conversation, not one /clear just started.
 * False if the file can't be read.
 */
export function hasReply(file: string): boolean {
  let text: string
  try {
    if (fs.statSync(file).size > HISTORY_MAX_BYTES) return true
    text = fs.readFileSync(file, 'utf8')
  } catch { return false }
  return lines(text, false).some((e) => e.type === 'assistant' && e.isSidechain !== true)
}

/**
 * A stored session's chat, oldest first: what the user said (typed or from
 * the world) and Claude's replies (the text parts of each assistant
 * message). Tool calls, thinking, subagents and injected context are left
 * out. Empty if the file can't be read.
 */
export function readHistory(file: string): HistoryMessage[] {
  let text: string
  try {
    if (fs.statSync(file).size > HISTORY_MAX_BYTES) return []
    text = fs.readFileSync(file, 'utf8')
  } catch { return [] }
  const out: HistoryMessage[] = []
  const byId = new Map<string, HistoryMessage>()
  for (const e of lines(text, false)) {
    const at = typeof e.timestamp === 'string' ? e.timestamp : new Date(0).toISOString()
    const said = userText(e)
    if (said !== null) {
      out.push({ message: typeof e.uuid === 'string' ? e.uuid : `u${out.length}`, agent: 'main', role: 'user', text: said, at })
      continue
    }
    if (e.type !== 'assistant' || e.isSidechain === true) continue
    const msg = e.message as { id?: unknown; content?: unknown } | undefined
    if (!msg || typeof msg.id !== 'string' || !Array.isArray(msg.content)) continue
    const texts = msg.content.filter((c) => c?.type === 'text' && typeof c.text === 'string').map((c) => c.text as string)
    if (texts.length === 0) continue
    // One API message is written as several entries, one per content block.
    const known = byId.get(msg.id)
    if (known) known.text += texts.join('')
    else {
      const h: HistoryMessage = { message: msg.id, agent: 'main', role: 'assistant', text: texts.join(''), at }
      byId.set(msg.id, h)
      out.push(h)
    }
  }
  return out
}
