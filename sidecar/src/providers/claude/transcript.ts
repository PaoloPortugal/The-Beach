// Following a session's transcript (NOTES.md -> S02 -> Filling the gaps):
// read-only, for what hooks miss. Esc and a "No" in the terminal fire no
// hook, but Claude Code writes them to the transcript within the same
// second; so is a conversation moving to another session. The line format isn't a documented interface, so this only ever
// updates status, and everything still works (later) without it: no
// transcript (saving is off), a missing file, or lines we don't recognise.
// A session taken back with its hooks out of reach (S07's limited mode) is
// seen from here alone: followAll.
import fs from 'node:fs'
import path from 'node:path'
import { StringDecoder } from 'node:string_decoder'
import { titleIn, type Titles } from './store.ts'
import { callUsageIn, type CallUsage } from './usage.ts'

/** How often the file is checked for new lines. */
export const POLL_MS = 250
/** Longest line kept; longer ones (big tool results) are skipped unread. */
const MAX_LINE = 4 * 1024 * 1024

/** What the transcript tells us that hooks don't. */
export type TranscriptSignal =
  /** A permission prompt answered "No" in the terminal; the call never ran. */
  | { kind: 'rejected'; toolUseId: string }
  /** The orchestrator's turn was interrupted (Esc, or after a "No"). */
  | { kind: 'interrupted' }
  /**
   * The conversation went on in another session (`continued-in`, seen
   * when agent view moved it to a background session; 2.1.285).
   */
  | { kind: 'continued'; sessionId: string }
  /** A name for the conversation: /rename (custom) or Claude Code's own (ai). */
  | { kind: 'title'; titles: Partial<Titles> }
  /** An API call of the main conversation and its tokens (C08); repeated once per entry of the call. */
  | { kind: 'usage'; call: CallUsage }
  /**
   * Only with followAll (S07's limited mode): every entry, the main
   * conversation's, or with `agent` a subagent's from its own file.
   */
  | { kind: 'entry'; entry: Record<string, unknown>; agent?: string }
  /** Only with followAll: a subagent started (its file appeared), with what its `.meta.json` says. */
  | { kind: 'subagent'; agent: string; type: string | null; toolUseId: string | null; background: boolean }

/** Claude Code's session ids are UUIDs. */
const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const INTERRUPTED = /^\[Request interrupted by user( for tool use)?\]$/

/** The signals in one transcript line (2.1.284's format; continued-in from 2.1.285; usage, 2.1.289). Exported for tests. */
export function signalsIn(line: string): TranscriptSignal[] {
  let e: Record<string, unknown>
  try { e = JSON.parse(line) } catch { return [] }
  if (typeof e === 'object' && e !== null && e.type === 'continued-in') {
    const id = e.continuedInSessionId
    return typeof id === 'string' && SESSION_ID.test(id) ? [{ kind: 'continued', sessionId: id }] : []
  }
  if (typeof e !== 'object' || e === null) return []
  const titles = titleIn(e)
  if (titles) return [{ kind: 'title', titles }]
  const call = callUsageIn(e)
  if (call) return [{ kind: 'usage', call }]
  // Subagents' own entries (their transcripts are separate files anyway).
  if (e.type !== 'user' || e.isSidechain === true) return []
  const content = (e.message as { content?: unknown } | undefined)?.content
  const out: TranscriptSignal[] = []
  if (typeof content === 'string') {
    if (INTERRUPTED.test(content.trim())) out.push({ kind: 'interrupted' })
    return out
  }
  if (!Array.isArray(content)) return out
  const rejected = e.toolUseResult === 'User rejected tool use' || e.toolDenialKind === 'user-rejected'
  for (const c of content as Record<string, unknown>[]) {
    if (c?.type === 'tool_result' && c.is_error === true && rejected && typeof c.tool_use_id === 'string') {
      out.push({ kind: 'rejected', toolUseId: c.tool_use_id })
    } else if (c?.type === 'text' && typeof c.text === 'string' && INTERRUPTED.test(c.text.trim())) {
      out.push({ kind: 'interrupted' })
    }
  }
  return out
}

/**
 * One JSONL file read as it grows: whole lines only, a character split
 * across two reads kept whole, a line longer than MAX_LINE skipped unread.
 */
class LineReader {
  readonly file: string
  private offset: number
  private partial = ''
  private readonly decoder = new StringDecoder('utf8')
  private skipping = false

  /** From the file's current end (what's there is the past), or from its start. */
  constructor(file: string, fromEnd: boolean) {
    this.file = file
    this.offset = fromEnd ? fs.statSync(file, { throwIfNoEntry: false })?.size ?? 0 : 0
  }

  /** Each line added since the last look. */
  read(onLine: (line: string) => void): void {
    const size = fs.statSync(this.file, { throwIfNoEntry: false })?.size
    if (size === undefined) return          // not written (yet, or ever: saving is off)
    if (size < this.offset) {
      // Rewritten shorter: what's in it now is the past, not news.
      this.offset = size
      this.partial = ''
      return
    }
    if (size === this.offset) return
    try {
      const fd = fs.openSync(this.file, 'r')
      let text: string
      try {
        const buf = Buffer.alloc(Math.min(size - this.offset, 8 * 1024 * 1024))
        const n = fs.readSync(fd, buf, 0, buf.length, this.offset)
        this.offset += n
        text = this.decoder.write(buf.subarray(0, n))
      } finally { fs.closeSync(fd) }
      this.take(text, onLine)
    } catch { /* unreadable right now; try again next time */ }
  }

  private take(text: string, onLine: (line: string) => void) {
    this.partial += text
    let i
    while ((i = this.partial.indexOf('\n')) >= 0) {
      const line = this.partial.slice(0, i)
      this.partial = this.partial.slice(i + 1)
      if (this.skipping) { this.skipping = false; continue }
      onLine(line)
    }
    if (this.partial.length > MAX_LINE) { this.partial = ''; this.skipping = true }
  }
}

/** A subagent's transcript file name: `agent-<agent id>.jsonl`. */
const SUBAGENT_FILE = /^agent-([A-Za-z0-9_-]{1,64})\.jsonl$/
/** Polls a new subagent's file waits for its `.meta.json` before starting without it. */
const META_WAIT_POLLS = 8

interface Subagent { reader: LineReader | null; polls: number }

/**
 * Follows one transcript file from its current end. The path comes from
 * the session's own hooks (authenticated); it changes when the user runs
 * /clear, and the follower moves to the new file.
 *
 * With [followAll] (a session whose hooks can't reach the game, S07) it
 * also hands over every entry, and follows the subagents started from now
 * on in their own files (`<id>/subagents/agent-*.jsonl`), so the session
 * can be seen from the transcript alone.
 */
export class TranscriptFollower {
  private main: LineReader | null = null
  private timer: NodeJS.Timeout | null = null
  private reading = false
  private everything = false
  /** Subagent files by agent id; null reader: there before we looked (the past), never read. */
  private readonly subagents = new Map<string, Subagent>()
  private readonly onSignal: (s: TranscriptSignal) => void

  constructor(onSignal: (s: TranscriptSignal) => void) {
    this.onSignal = onSignal
  }

  /** Hand over every entry and follow subagents too (from the next file followed). */
  followAll(): void {
    this.everything = true
  }

  /** The transcript a hook named. Starts (or moves) following it, from its end. */
  follow(file: unknown): void {
    if (typeof file !== 'string' || !path.isAbsolute(file) || path.extname(file) !== '.jsonl') return
    if (file === this.main?.file) return
    this.main = new LineReader(file, true)
    this.subagents.clear()
    if (this.everything) for (const id of this.subagentFiles()) this.subagents.set(id, { reader: null, polls: -1 })
    if (!this.timer) {
      this.timer = setInterval(() => this.poll(), POLL_MS)
      this.timer.unref()
    }
  }

  /** Reads what was added since the last look. Exported behaviour for tests. */
  poll(): void {
    if (!this.main || this.reading) return
    this.reading = true
    try {
      const main = this.main
      main.read((line) => this.line(line, main))
      if (this.everything && this.main === main) this.pollSubagents()
    } finally {
      this.reading = false
    }
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.main = null
    this.subagents.clear()
  }

  private line(line: string, from: LineReader) {
    // A signal may switch the follower to another file: the rest is that one's past.
    if (this.main !== from) return
    if (this.everything) {
      const entry = parseEntry(line)
      if (entry) this.onSignal({ kind: 'entry', entry })
    }
    for (const s of signalsIn(line)) this.onSignal(s)
  }

  private subagentsDir(): string | null {
    if (!this.main) return null
    const file = this.main.file
    return path.join(path.dirname(file), path.basename(file, '.jsonl'), 'subagents')
  }

  private subagentFiles(): string[] {
    const dir = this.subagentsDir()
    let names: string[]
    try { names = dir ? fs.readdirSync(dir) : [] } catch { return [] }
    return names.map((n) => SUBAGENT_FILE.exec(n)?.[1]).filter((id): id is string => id !== undefined).sort()
  }

  /**
   * New subagent files: each announced once its `.meta.json` (its type and
   * the call that started it) is there, or after META_WAIT_POLLS without
   * it, then read from its start. Then what each one added.
   */
  private pollSubagents() {
    const dir = this.subagentsDir()!
    const main = this.main
    for (const id of this.subagentFiles()) {
      let sub = this.subagents.get(id)
      if (!sub) this.subagents.set(id, sub = { reader: null, polls: 0 })
      if (sub.reader || sub.polls < 0) continue
      const meta = readMeta(path.join(dir, `agent-${id}.meta.json`))
      if (!meta && ++sub.polls < META_WAIT_POLLS) continue
      sub.reader = new LineReader(path.join(dir, `agent-${id}.jsonl`), false)
      this.onSignal({ kind: 'subagent', agent: id, type: meta?.type ?? null, toolUseId: meta?.toolUseId ?? null, background: meta?.background ?? false })
    }
    for (const [agent, sub] of this.subagents) {
      if (this.main !== main) return
      sub.reader?.read((line) => {
        const entry = this.main === main ? parseEntry(line) : null
        if (entry) this.onSignal({ kind: 'entry', entry, agent })
      })
    }
  }
}

function parseEntry(line: string): Record<string, unknown> | null {
  try {
    const v: unknown = JSON.parse(line)
    return typeof v === 'object' && v !== null && !Array.isArray(v) ? v as Record<string, unknown> : null
  } catch { return null }
}

/** What a subagent's `.meta.json` says (written by Claude Code beside its transcript; seen on 2.1.296). */
function readMeta(file: string): { type: string | null; toolUseId: string | null; background: boolean } | null {
  try {
    const m = JSON.parse(fs.readFileSync(file, 'utf8')) as Record<string, unknown>
    if (typeof m !== 'object' || m === null) return null
    return {
      type: typeof m.agentType === 'string' ? m.agentType : null,
      toolUseId: typeof m.toolUseId === 'string' ? m.toolUseId : null,
      background: m.requestShape === 'background',
    }
  } catch { return null }
}
