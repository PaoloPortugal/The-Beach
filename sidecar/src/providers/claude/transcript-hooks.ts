// A session whose hooks can't reach the game (S07's limited mode: taken
// back after a restart, its hook port taken while the game was closed),
// seen from its transcript alone: each entry read as the hooks it stands
// for, so the HookTranslator turns it into the usual events, a moment late.
// Replies come whole (no streaming); a user's message, tool calls and
// subagents as they're written; the turn's end from Claude Code's
// `turn_duration` entry (2.1.296). Esc and a terminal "No" are the
// follower's own signals (transcript.ts). The format isn't a documented
// interface (NOTES.md -> Watch items): anything unrecognised is skipped.
import type { HookPayload } from './hook-server.ts'
import { parseHandback, parseTaskNotification, unwrapChannel } from './hooks.ts'
import { LOCAL_COMMAND } from './store.ts'

/** A hook to translate, or a call refused before it ran (closed as denied). */
export type Fed = { hook: HookPayload } | { denied: string }

/**
 * How Claude Code 2.1.296 writes a subagent's hand-back to the orchestrator
 * (an isMeta user entry); the hook's prompt is what follows.
 */
const HANDBACK_PREFIX = /^Another Claude session sent a message:\n(?=<agent-message )/

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)
const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

export class TranscriptHooks {
  /** Text blocks seen per API message: one message is written as several entries. */
  private readonly texts = new Map<string, number>()
  /** Foreground subagents by the Agent call that started them: done when it returns. */
  private readonly foreground = new Map<string, string>()
  /** An API error ended the turn: its turn_duration doesn't make the orchestrator idle. */
  private failed = false

  /** The hooks one entry stands for; `agent` for a subagent's own file. */
  entry(e: Record<string, unknown>, agent?: string): Fed[] {
    const out: Fed[] = []
    const of = agent ? { agent_id: agent } : {}
    if (e.type === 'system' && !agent) {
      if (e.subtype === 'turn_duration') {
        if (!this.failed) out.push({ hook: { hook_event_name: 'Stop' } })
        this.failed = false
      }
      return out
    }
    // The main file's sidechain entries belong to subagents, read from their own files.
    if (!agent && e.isSidechain === true) return out
    const content = (e.message as { content?: unknown } | undefined)?.content
    if (e.type === 'assistant') {
      if (e.isApiErrorMessage === true) {
        if (!agent) {
          this.failed = true
          out.push({ hook: { hook_event_name: 'StopFailure', error: str(e.error) ?? 'unknown' } })
        }
        return out
      }
      const id = str((e.message as { id?: unknown } | undefined)?.id)
      if (!Array.isArray(content)) return out
      for (const c of content) {
        if (!isObject(c)) continue
        if (c.type === 'text' && typeof c.text === 'string' && c.text.trim() && id) {
          const n = (this.texts.get(id) ?? 0) + 1
          this.texts.set(id, n)
          out.push({ hook: { hook_event_name: 'MessageDisplay', message_id: n === 1 ? id : `${id}:${n}`, message_text: c.text, ...of } })
        } else if (c.type === 'tool_use' && typeof c.id === 'string' && typeof c.name === 'string') {
          out.push({ hook: { hook_event_name: 'PreToolUse', tool_use_id: c.id, tool_name: c.name, tool_input: isObject(c.input) ? c.input : {}, ...of } })
        }
      }
      return out
    }
    if (e.type !== 'user') return out
    const results = Array.isArray(content) ? content.filter((c) => isObject(c) && c.type === 'tool_result') as Record<string, unknown>[] : []
    if (results.length === 0) {
      const prompt = agent ? null : promptIn(e, content)
      if (prompt !== null) out.push({ hook: { hook_event_name: 'UserPromptSubmit', prompt, ...(typeof e.uuid === 'string' ? { prompt_id: e.uuid } : {}) } })
      return out
    }
    // A "No" in the terminal is the follower's `rejected` signal.
    if (e.toolDenialKind === 'user-rejected' || e.toolUseResult === 'User rejected tool use') return out
    for (const c of results) {
      const call = str(c.tool_use_id)
      if (!call) continue
      if (typeof e.toolDenialKind === 'string') out.push({ denied: call })
      else if (c.is_error === true) out.push({ hook: { hook_event_name: 'PostToolUseFailure', tool_use_id: call, error: resultText(c.content), ...of } })
      else out.push({ hook: { hook_event_name: 'PostToolUse', tool_use_id: call, ...of } })
      const sub = this.foreground.get(call)
      if (sub !== undefined) {
        this.foreground.delete(call)
        out.push({ hook: { hook_event_name: 'SubagentStop', agent_id: sub } })
      }
    }
    return out
  }

  /**
   * A subagent's file appeared: SubagentStart, tied to the Agent call that
   * started it. A foreground one is done when that call returns; a
   * background one when its task notification comes (the translator's).
   */
  subagent(agent: string, type: string | null, toolUseId: string | null, background: boolean): Fed[] {
    if (toolUseId && !background) this.foreground.set(toolUseId, agent)
    return [{ hook: { hook_event_name: 'SubagentStart', agent_id: agent, ...(type ? { agent_type: type } : {}), ...(toolUseId ? { spawned_by: toolUseId } : {}) } }]
  }
}

/**
 * The prompt a main-conversation user entry stands for, or null: what the
 * user said (typed, or from the world through the channel), a background
 * task's notification or a subagent's hand-back (the translator tells
 * those apart); not Claude Code's own context, slash commands, or the
 * interruption marker.
 */
function promptIn(e: Record<string, unknown>, content: unknown): string | null {
  if (e.isCompactSummary === true) return null
  let text: string
  if (typeof content === 'string') text = content
  else if (Array.isArray(content)) {
    const texts = content.filter((c) => isObject(c) && c.type === 'text' && typeof c.text === 'string').map((c) => c.text as string)
    if (texts.length === 0) return null
    text = texts.join('\n')
  } else return null
  const t = text.trim().replace(HANDBACK_PREFIX, '')
  if (parseTaskNotification(t) || parseHandback(t)) return t
  if (/^\[Request interrupted by user/.test(t) || LOCAL_COMMAND.test(t)) return null
  // Claude Code's injected context is marked meta; a world message is too
  // (it comes through our channel), and stays.
  if (e.isMeta === true && unwrapChannel(t) === t) return null
  return t
}

function resultText(content: unknown): string {
  if (typeof content === 'string') return content
  if (!Array.isArray(content)) return ''
  return content.filter((c) => isObject(c) && c.type === 'text' && typeof c.text === 'string').map((c) => c.text as string).join('\n')
}
