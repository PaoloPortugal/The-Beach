// Token usage for one Claude conversation (NOTES.md -> C08). Two sources:
// the transcript, where every assistant entry carries its API call's
// `message.usage`, and Claude Code's status line input (through our
// `statusline` relay), for how full the context window is and the
// account's usage limits. Neither format is ours: anything we don't
// recognise is skipped, and the figures are only ever shown, never acted on.
import type { Id, Usage, UsageLimit } from '../../protocol.ts'

/** One API call's tokens, from a transcript entry. */
export interface CallUsage {
  /** The API message id: one call is written as several entries with the same id and usage. */
  id: string
  input: number
  output: number
  cacheRead: number
  cacheWrite: number
}

const count = (v: unknown): number =>
  typeof v === 'number' && Number.isFinite(v) && v >= 0 ? Math.floor(v) : 0

/**
 * The API call an assistant entry of the main conversation reports, or
 * null. Subagents' entries (`isSidechain`) aren't counted: only the
 * orchestrator's tokens for now (user's decision).
 */
export function callUsageIn(e: Record<string, unknown>): CallUsage | null {
  if (e.type !== 'assistant' || e.isSidechain === true) return null
  const msg = e.message as { id?: unknown; usage?: unknown } | undefined
  if (typeof msg !== 'object' || msg === null || typeof msg.id !== 'string' || !msg.id) return null
  const u = msg.usage
  if (typeof u !== 'object' || u === null) return null
  const r = u as Record<string, unknown>
  return {
    id: msg.id,
    input: count(r.input_tokens),
    output: count(r.output_tokens),
    cacheRead: count(r.cache_read_input_tokens),
    cacheWrite: count(r.cache_creation_input_tokens),
  }
}

/** What one status line call says (only the fields we use). */
export interface StatusFigures {
  /** The conversation it's about. */
  sessionId: string | null
  /** Null: the input had no context_window. `tokens` null without current_usage. */
  context: { tokens: number | null; percent: number | null; window: number | null } | null
  /** Null: the input had no rate_limits (not known yet, or not a subscriber). */
  limits: Usage['limits'] | null
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : null)

/** Epoch seconds as an ISO timestamp, or null if it isn't a sensible time. */
function epoch(v: unknown): string | null {
  const s = num(v)
  if (s === null || s > 1e11) return null
  return new Date(s * 1000).toISOString()
}

function limitIn(v: unknown): UsageLimit | null {
  if (typeof v !== 'object' || v === null) return null
  const r = v as Record<string, unknown>
  const used = num(r.used_percentage)
  const resets = epoch(r.resets_at)
  return used === null || resets === null ? null : { used_percent: used, resets_at: resets }
}

/**
 * The figures in one status line input (code.claude.com/docs/en/statusline):
 * `session_id`, `context_window` (`used_percentage`, `context_window_size`,
 * `current_usage`) and `rate_limits` (`five_hour`, `seven_day`:
 * `used_percentage`, and `resets_at` in epoch seconds). Everything else in
 * it (cost, model, paths, ...) is ignored.
 */
export function statusFiguresIn(p: Record<string, unknown>): StatusFigures {
  const sessionId = typeof p.session_id === 'string' ? p.session_id : null
  let context: StatusFigures['context'] = null
  const cw = p.context_window
  if (typeof cw === 'object' && cw !== null) {
    const c = cw as Record<string, unknown>
    const size = num(c.context_window_size)
    const window = size !== null && size >= 1 ? Math.floor(size) : null
    const cu = c.current_usage
    let tokens: number | null = null
    if (typeof cu === 'object' && cu !== null) {
      // Claude Code's own formula for its context %: input only.
      const u = cu as Record<string, unknown>
      tokens = count(u.input_tokens) + count(u.cache_creation_input_tokens) + count(u.cache_read_input_tokens)
    }
    context = { tokens, percent: num(c.used_percentage), window }
  }
  let limits: StatusFigures['limits'] = null
  const rl = p.rate_limits
  if (typeof rl === 'object' && rl !== null) {
    const r = rl as Record<string, unknown>
    const five = limitIn(r.five_hour)
    const seven = limitIn(r.seven_day)
    limits = { ...(five ? { five_hour: five } : {}), ...(seven ? { seven_day: seven } : {}) }
  }
  return { sessionId, context, limits }
}

/**
 * One conversation's counts. Totals add up every call once (by its message
 * id); the context is the latest call's input, cache reads and cache
 * writes (Claude Code's formula); a turn runs from one user message to the
 * next and counts output tokens, thinking included. Prompts Claude Code
 * injects (a subagent's report, a task notice) aren't user messages, so
 * their calls count toward the turn they come in.
 */
export class UsageCounter {
  private readonly seen = new Set<string>()
  private tokens = { input: 0, output: 0, cache_read: 0, cache_write: 0 }
  private context: Usage['context'] = null
  private turn: Usage['turn'] = { message: null, output_tokens: 0 }
  private limits: Usage['limits'] = {}
  /** Whether there is anything to show yet (the snapshot's usage is null until then). */
  private counted = false

  /** Counts one call; false if it was already counted. */
  add(call: CallUsage): boolean {
    if (this.seen.has(call.id)) return false
    this.seen.add(call.id)
    this.counted = true
    this.tokens.input += call.input
    this.tokens.output += call.output
    this.tokens.cache_read += call.cacheRead
    this.tokens.cache_write += call.cacheWrite
    const fill = call.input + call.cacheRead + call.cacheWrite
    const window = this.context?.window ?? null
    // The status line's % was for an earlier call: worked out again for
    // this one, the same way Claude Code does.
    const percent = window !== null && this.context?.percent != null ? Math.min(100, Math.round((fill / window) * 100)) : null
    this.context = { tokens: fill, percent, window }
    this.turn.output_tokens += call.output
    return true
  }

  /** A user message starts a new turn. */
  newTurn(message: Id): void {
    this.turn = { message, output_tokens: 0 }
    this.counted = true
  }

  /** The status line's figures for this conversation. False if nothing changed. */
  status(f: StatusFigures): boolean {
    const before = JSON.stringify(this.get())
    if (f.context) {
      const tokens = f.context.tokens ?? this.context?.tokens ?? null
      if (tokens !== null) {
        this.context = { tokens, percent: f.context.percent, window: f.context.window }
        this.counted = true
      }
    }
    // The account's limits; an input without them (not known yet) keeps the last.
    if (f.limits) {
      this.limits = f.limits
      this.counted = true
    }
    return JSON.stringify(this.get()) !== before
  }

  /** A new conversation (/clear): counts start over; the account's limits stay. */
  reset(): void {
    this.seen.clear()
    this.tokens = { input: 0, output: 0, cache_read: 0, cache_write: 0 }
    this.context = null
    this.turn = { message: null, output_tokens: 0 }
    this.counted = Object.keys(this.limits).length > 0
  }

  /** Starts from a conversation read from its transcript (/resume), keeping the account's limits. */
  load(read: UsageCounter): void {
    const limits = this.limits
    this.reset()
    for (const id of read.seen) this.seen.add(id)
    this.tokens = { ...read.tokens }
    this.context = read.context ? { ...read.context } : null
    this.turn = { ...read.turn }
    this.limits = limits
    this.counted = read.counted || Object.keys(limits).length > 0
  }

  /** The current figures, or null before there's anything to show. */
  get(): Usage | null {
    if (!this.counted) return null
    return structuredClone({ tokens: this.tokens, context: this.context, turn: this.turn, limits: this.limits })
  }
}
