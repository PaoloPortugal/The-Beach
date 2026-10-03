// A session's history as the world saw it through its events: completed chat
// messages and tool calls (C04), for session.get_history. Generic: any
// provider can keep one by passing it the events it emits. In memory only,
// never on disk (NOTES.md -> Security rules -> Private by default).
import type { History, HistoryMessage, HistoryTool, Id, SessionEvent } from './protocol.ts'

/** Most messages, and most tool calls, kept (oldest dropped first). */
export const HISTORY_MAX = 5000

export class HistoryLog {
  readonly messages: HistoryMessage[] = []
  readonly tools: HistoryTool[] = []
  /** Messages started but not yet completed: who and when. */
  private readonly starting = new Map<Id, Omit<HistoryMessage, 'message' | 'text'>>()
  /** The latest message started, for a tool call's `after`. */
  private last: Id | null = null

  constructor(start: History = { messages: [], tools: [] }) {
    this.replace(start)
  }

  /**
   * Takes in one event the provider emitted (and the registry accepted).
   * Returns the message it completed, if any.
   */
  remember(event: SessionEvent): HistoryMessage | null {
    switch (event.type) {
      case 'message.started':
        this.starting.set(event.message, { agent: event.agent, role: event.role, at: new Date().toISOString() })
        this.last = event.message
        return null
      case 'message.completed': {
        const started = this.starting.get(event.message)
        if (!started) return null
        this.starting.delete(event.message)
        const m: HistoryMessage = { message: event.message, ...started, text: event.text }
        this.messages.push(m)
        trim(this.messages)
        return m
      }
      case 'tool.started':
        this.tools.push({
          tool_call: event.tool_call, agent: event.agent, tool: event.tool, summary: event.summary,
          ...(event.input ? { input: event.input } : {}),
          status: 'running', after: this.last,
          ...(event.within ? { within: event.within } : {}),
        })
        trim(this.tools)
        return null
      case 'tool.finished': {
        const t = this.tools.findLast((x) => x.tool_call === event.tool_call)
        if (t) {
          t.status = event.status
          if (event.summary) t.result = event.summary
        }
        return null
      }
      default:
        return null
    }
  }

  /** Starts over from `history` (a resumed conversation's, or empty after /clear). */
  replace(history: History): void {
    this.messages.splice(0, this.messages.length, ...history.messages.slice(-HISTORY_MAX))
    this.tools.splice(0, this.tools.length, ...history.tools.slice(-HISTORY_MAX))
    this.last = this.messages.at(-1)?.message ?? null
  }

  /** A copy, safe to send. */
  get(): History {
    return structuredClone({ messages: this.messages, tools: this.tools })
  }
}

function trim(list: unknown[]) {
  if (list.length > HISTORY_MAX) list.splice(0, list.length - HISTORY_MAX)
}
