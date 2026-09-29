// Following a session's transcript (NOTES.md -> S02 -> Filling the gaps):
// read-only, for what hooks miss. Esc and a "No" in the terminal fire no
// hook, but Claude Code writes them to the transcript within the same
// second. The line format isn't a documented interface, so this only ever
// updates status, and everything still works (later) without it: no
// transcript (saving is off), a missing file, or lines we don't recognise.
import fs from 'node:fs'
import path from 'node:path'
import { StringDecoder } from 'node:string_decoder'

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

const INTERRUPTED = /^\[Request interrupted by user( for tool use)?\]$/

/** The signals in one transcript line (2.1.284's format). Exported for tests. */
export function signalsIn(line: string): TranscriptSignal[] {
  let e: Record<string, unknown>
  try { e = JSON.parse(line) } catch { return [] }
  // Subagents' own entries (their transcripts are separate files anyway).
  if (typeof e !== 'object' || e === null || e.type !== 'user' || e.isSidechain === true) return []
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
 * Follows one transcript file from its current end. The path comes from
 * the session's own hooks (authenticated); it changes when the user runs
 * /clear, and the follower moves to the new file.
 */
export class TranscriptFollower {
  private file: string | null = null
  private offset = 0
  private partial = ''
  /** Keeps a character split across two reads whole. */
  private decoder = new StringDecoder('utf8')
  private skipping = false
  private timer: NodeJS.Timeout | null = null
  private reading = false
  private readonly onSignal: (s: TranscriptSignal) => void

  constructor(onSignal: (s: TranscriptSignal) => void) {
    this.onSignal = onSignal
  }

  /** The transcript a hook named. Starts (or moves) following it, from its end. */
  follow(file: unknown): void {
    if (typeof file !== 'string' || !path.isAbsolute(file) || path.extname(file) !== '.jsonl') return
    if (file === this.file) return
    this.file = file
    // Only what happens from now on: earlier lines are about the past.
    this.offset = fs.statSync(file, { throwIfNoEntry: false })?.size ?? 0
    this.partial = ''
    this.decoder = new StringDecoder('utf8')
    this.skipping = false
    if (!this.timer) {
      this.timer = setInterval(() => this.poll(), POLL_MS)
      this.timer.unref()
    }
  }

  /** Reads what was added since the last look. Exported behaviour for tests. */
  poll(): void {
    if (!this.file || this.reading) return
    const size = fs.statSync(this.file, { throwIfNoEntry: false })?.size
    if (size === undefined) return          // not written (yet, or ever: saving is off)
    if (size < this.offset) this.offset = 0 // replaced
    if (size === this.offset) return
    this.reading = true
    try {
      const fd = fs.openSync(this.file, 'r')
      try {
        const buf = Buffer.alloc(Math.min(size - this.offset, 8 * 1024 * 1024))
        const n = fs.readSync(fd, buf, 0, buf.length, this.offset)
        this.offset += n
        this.take(this.decoder.write(buf.subarray(0, n)))
      } finally { fs.closeSync(fd) }
    } catch { /* unreadable right now; try again next time */ } finally {
      this.reading = false
    }
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.file = null
  }

  private take(text: string) {
    this.partial += text
    let i
    while ((i = this.partial.indexOf('\n')) >= 0) {
      const line = this.partial.slice(0, i)
      this.partial = this.partial.slice(i + 1)
      if (this.skipping) { this.skipping = false; continue }
      for (const s of signalsIn(line)) this.onSignal(s)
    }
    if (this.partial.length > MAX_LINE) { this.partial = ''; this.skipping = true }
  }
}
