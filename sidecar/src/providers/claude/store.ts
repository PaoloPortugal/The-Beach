// Claude Code's stored sessions (NOTES.md -> S04): transcripts under
// <config dir>/projects/<project slug>/<session id>.jsonl, read-only. Used to
// list sessions that can be resumed and to show a resumed session's chat.
// The line format isn't a documented interface (NOTES.md -> Watch items):
// anything unrecognised is skipped, and a file that can't be read is left
// out of the list.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import type { History, HistoryMessage, HistoryTool, StoredSession } from '../../protocol.ts'
import { jsonBytes } from '../../history.ts'
import { clip, firstLine, INPUT_MAX, MAIN, parseHandback, parseTaskNotification, PLAN_TOOL, summarizeTool, unwrapChannel } from './hooks.ts'
import { callUsageIn, UsageCounter } from './usage.ts'

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
/**
 * Most bytes read for one history: the main transcript and its subagents'
 * together (read synchronously, so this bounds the stall). A main
 * transcript larger than this isn't read; a subagent's that doesn't fit
 * what's left is skipped.
 */
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

/** [peek] without blocking: listing reads up to 200 files (NOTES.md -> S04). */
async function peekAsync(file: string, size: number): Promise<{ head: string; tail: string }> {
  const fh = await fs.promises.open(file, 'r')
  try {
    const read = async (at: number, n: number) => {
      const buf = Buffer.alloc(n)
      const { bytesRead } = await fh.read(buf, 0, n, at)
      return buf.subarray(0, bytesRead).toString('utf8')
    }
    const head = await read(0, Math.min(PEEK, size))
    const tail = size > PEEK ? await read(size - PEEK, PEEK) : ''
    return { head, tail }
  } finally { await fh.close() }
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
  let st: fs.Stats
  try { st = fs.statSync(file) } catch { return null }
  return describeAs(file, st) ?? null
}

/**
 * Listings kept between calls (NOTES.md -> S04): each transcript's
 * description, reused while its size and modification time stay the same,
 * so listing again only reads the folders and the files' times. The menu
 * asks each time its Resume page opens.
 */
export class StoredCache {
  private readonly entries = new Map<string, { size: number; mtimeMs: number; info: StoredInfo | null }>()
  /** Files described by reading them, since this cache was made (for tests). */
  reads = 0

  private readonly read: (file: string, st: fs.Stats) => Promise<StoredInfo | null | undefined>

  /** [read] describes one file; undefined if it couldn't be read (tests stand in a failing one). */
  constructor(read = describeAsync) { this.read = read }

  get size(): number { return this.entries.size }

  async describe(file: string, st: fs.Stats): Promise<StoredInfo | null> {
    const kept = this.entries.get(file)
    if (kept && kept.size === st.size && kept.mtimeMs === st.mtimeMs) return kept.info
    this.reads++
    const info = await this.read(file, st)
    // A file that couldn't be read (e.g. locked mid-write) is tried again next time.
    if (info === undefined) this.entries.delete(file)
    else this.entries.set(file, { size: st.size, mtimeMs: st.mtimeMs, info })
    return info ?? null
  }

  /** Forgets the files not in [files]: deleted since, or no longer listed. */
  keepOnly(files: Set<string>): void {
    for (const file of this.entries.keys()) if (!files.has(file)) this.entries.delete(file)
  }
}

/** [describe] with the file's stats; undefined if it couldn't be read. */
export function describeAs(file: string, st: fs.Stats): StoredInfo | null | undefined {
  if (!listable(file, st)) return null
  let read: { head: string; tail: string }
  try { read = peek(file, st.size) } catch { return undefined }
  return describeRead(file, st, read)
}

/** [describeAs] without blocking, for listing. */
export async function describeAsync(file: string, st: fs.Stats): Promise<StoredInfo | null | undefined> {
  if (!listable(file, st)) return null
  let read: { head: string; tail: string }
  try { read = await peekAsync(file, st.size) } catch { return undefined }
  return describeRead(file, st, read)
}

function listable(file: string, st: fs.Stats): boolean {
  return UUID.test(path.basename(file, '.jsonl')) && st.isFile() && st.size > 0
}

function describeRead(file: string, st: fs.Stats, { head, tail }: { head: string; tail: string }): StoredInfo | null {
  const id = path.basename(file, '.jsonl')
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

/**
 * Resumable sessions, newest first, optionally only one project's. With
 * [cache], files unchanged since an earlier listing aren't read again.
 * Reads without blocking, so the sidecar handles everything else
 * meanwhile (NOTES.md -> S04).
 */
export async function listStored(opts: { dir?: string; project?: string; exclude?: Set<string>; cache?: StoredCache } = {}): Promise<StoredInfo[]> {
  const dir = opts.dir ?? projectsDir()
  let slugs: string[]
  try { slugs = await fs.promises.readdir(dir) } catch { return [] }
  // Newest files first, so only the ones that will be listed are read.
  const files: { file: string; st: fs.Stats }[] = []
  for (const slug of slugs) {
    let names: string[]
    try { names = await fs.promises.readdir(path.join(dir, slug)) } catch { continue }
    const found = await Promise.all(names
      .filter((name) => name.endsWith('.jsonl') && !opts.exclude?.has(name.slice(0, -6)))
      .map(async (name) => {
        const file = path.join(dir, slug, name)
        try { return { file, st: await fs.promises.stat(file) } } catch { return null }
      }))
    for (const f of found) if (f) files.push(f)
  }
  files.sort((a, b) => b.st.mtimeMs - a.st.mtimeMs)
  const out: StoredInfo[] = []
  const seen = new Set<string>()
  for (const { file, st } of files) {
    seen.add(file)
    const info = opts.cache ? await opts.cache.describe(file, st) : await describeAsync(file, st) ?? null
    if (!info || (opts.project && !samePath(info.project.path, opts.project))) continue
    out.push(info)
    if (out.length >= LIST_MAX) break
  }
  opts.cache?.keepOnly(seen)
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
 * message); thinking and injected context are left out. And its tool calls
 * (C04): the main conversation's, then each subagent's from its own
 * transcript (`<id>/subagents/agent-*.jsonl`), tied to the Agent call that
 * started it by the `.meta.json` beside it. Empty if the file can't be read.
 * Reads at most `budget` bytes in all (HISTORY_MAX_BYTES).
 */
export function readHistory(file: string, budget = HISTORY_MAX_BYTES): History {
  return readConversation(file, budget).history
}

/** A conversation read from its transcript: its history, and its token usage (C08). */
export interface Conversation {
  history: History
  /** Its totals, latest context and last turn; each user message has its turn's `turn_tokens`. */
  usage: UsageCounter
}

/**
 * readHistory, plus the conversation's token usage (C08): each API call
 * counted once, subagents' left out, and each user message's turn (up to
 * the next one) in its `turn_tokens`.
 */
export function readConversation(file: string, budget = HISTORY_MAX_BYTES): Conversation {
  const usage = new UsageCounter()
  let text: string
  try {
    const size = fs.statSync(file).size
    if (size > budget) return { history: { messages: [], tools: [] }, usage }
    budget -= size
    text = fs.readFileSync(file, 'utf8')
  } catch { return { history: { messages: [], tools: [] }, usage } }
  /** The user message whose turn is being counted. */
  let turn: HistoryMessage | null = null
  const out: HistoryMessage[] = []
  const byId = new Map<string, HistoryMessage>()
  const tools = new ToolReader()
  const plans = new Set<string>()
  for (const e of lines(text, false)) {
    const at = typeof e.timestamp === 'string' ? e.timestamp : new Date(0).toISOString()
    const said = userText(e)
    if (said !== null) {
      turn = { message: typeof e.uuid === 'string' ? e.uuid : `u${out.length}`, agent: 'main', role: 'user', text: said, at }
      out.push(turn)
      usage.newTurn(turn.message)
      continue
    }
    if (e.isSidechain === true) continue
    const call = callUsageIn(e)
    if (call && usage.add(call) && turn) turn.turn_tokens = (turn.turn_tokens ?? 0) + call.output
    const msg = e.message as { id?: unknown; content?: unknown } | undefined
    if (e.type === 'assistant' && msg && typeof msg.id === 'string' && Array.isArray(msg.content)) {
      const texts = msg.content.filter((c) => c?.type === 'text' && typeof c.text === 'string').map((c) => c.text as string)
      // One API message is written as several entries, one per content block.
      const known = byId.get(msg.id)
      if (known) known.text += texts.join('')
      else if (texts.length > 0) {
        const h: HistoryMessage = { message: msg.id, agent: 'main', role: 'assistant', text: texts.join(''), at }
        byId.set(msg.id, h)
        out.push(h)
      }
    }
    // A plan presented for approval: its own message, before its call, with
    // the id the live one has (C07).
    if (e.type === 'assistant' && msg && Array.isArray(msg.content)) {
      for (const c of msg.content) {
        const plan = c?.type === 'tool_use' && c.name === PLAN_TOOL && typeof c.id === 'string' ? c.input?.plan : undefined
        if (typeof plan === 'string' && plan.trim() && !plans.has(c.id)) {
          plans.add(c.id)
          out.push({ message: `${c.id}:plan`, agent: 'main', role: 'assistant', kind: 'plan', text: plan, at })
        }
      }
    }
    // After the text: a call comes after what was said before it.
    tools.read(e, MAIN, out.at(-1)?.message ?? null)
  }
  readSubagents(file, tools, budget)
  return { history: { messages: out, tools: tools.list }, usage }
}

/** Tool calls from transcript entries: a tool_use starts one, its tool_result ends it. */
class ToolReader {
  readonly list: HistoryTool[] = []
  private readonly byId = new Map<string, HistoryTool>()

  read(e: Record<string, unknown>, agent: string, after: string | null, within?: string) {
    const content = (e.message as { content?: unknown } | undefined)?.content
    if (!Array.isArray(content)) return
    const cwd = typeof e.cwd === 'string' ? e.cwd : ''
    for (const c of content) {
      if (e.type === 'assistant' && c?.type === 'tool_use' && typeof c.id === 'string' && typeof c.name === 'string') {
        if (this.byId.has(c.id)) continue
        const input = c.input !== null && typeof c.input === 'object' && !Array.isArray(c.input) ? c.input as Record<string, unknown> : {}
        const t: HistoryTool = {
          tool_call: c.id, agent, tool: c.name, summary: summarizeTool(c.name, input, cwd),
          ...(jsonBytes(input) <= INPUT_MAX ? { input } : {}),
          // Ended with the transcript (Claude Code closed mid-call), unless a result follows.
          status: 'error', result: 'No result was recorded.', after, ...(within ? { within } : {}),
        }
        this.byId.set(c.id, t)
        this.list.push(t)
      } else if (e.type === 'user' && c?.type === 'tool_result' && typeof c.tool_use_id === 'string') {
        const t = this.byId.get(c.tool_use_id)
        if (!t) continue
        delete t.result
        // toolDenialKind (undocumented, seen as user-rejected, permission-rule,
        // automode-blocked...) marks a call that was refused, not one that failed.
        if (typeof e.toolDenialKind === 'string') t.status = 'denied'
        else if (c.is_error === true) {
          t.status = 'error'
          const why = clip(firstLine(resultText(c.content)))
          if (why) t.result = why
        } else t.status = 'ok'
      }
    }
  }
}

function resultText(content: unknown): string {
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  return content.filter((c) => c?.type === 'text' && typeof c.text === 'string').map((c) => c.text as string).join('\n')
}

/**
 * Each subagent's tool calls, inside the call that started it. Files are
 * read in name order while they fit in `budget` bytes; one that doesn't
 * is skipped, with its calls.
 */
function readSubagents(file: string, tools: ToolReader, budget: number) {
  const dir = path.join(path.dirname(file), path.basename(file, '.jsonl'), 'subagents')
  let names: string[]
  try { names = fs.readdirSync(dir) } catch { return }
  for (const name of names.sort()) {
    const m = /^agent-([A-Za-z0-9_-]+)\.jsonl$/.exec(name)
    if (!m) continue
    let within: string | undefined
    try {
      const meta = JSON.parse(fs.readFileSync(path.join(dir, `agent-${m[1]}.meta.json`), 'utf8')) as { toolUseId?: unknown }
      if (typeof meta.toolUseId === 'string') within = meta.toolUseId
    } catch { /* no meta: listed without a parent call */ }
    let text: string
    try {
      const size = fs.statSync(path.join(dir, name)).size
      if (size > budget) continue
      budget -= size
      text = fs.readFileSync(path.join(dir, name), 'utf8')
    } catch { continue }
    for (const e of lines(text, false)) tools.read(e, m[1]!, null, within)
  }
}
