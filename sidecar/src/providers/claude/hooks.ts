// Claude Code's hooks (NOTES.md -> S02 -> Seeing the session): the settings
// that make a launched session post them to us, and their translation into
// the generic protocol. Payload shapes are the ones Claude Code 2.1.284 sent
// in the S02 spike, which differ from the hooks docs in places
// (MessageDisplay); every field is treated as optional and checked.
import path from 'node:path'
import crypto from 'node:crypto'
import type { Agent, Id, Permission, SessionEvent, State } from '../../protocol.ts'
import type { HookPayload } from './hook-server.ts'
import { BRIDGE_SERVER_NAME } from './bridge.ts'

/** The orchestrator's agent id. Subagents use Claude Code's agent_id. */
export const MAIN = 'main'

/** Hooks that only report: short, so a hung sidecar costs little. */
const REPORT_TIMEOUT_S = 5
/** MessageDisplay holds up the text on screen; answered instantly anyway. */
const DISPLAY_TIMEOUT_S = 2

/** Hook events we translate. SessionStart can't be an HTTP hook. */
export const REPORTED_HOOKS = [
  'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure',
  'SubagentStart', 'SubagentStop', 'Notification', 'Stop', 'StopFailure',
] as const

/** The `--settings` JSON for one session: every hook posts to `url` with its token. */
export function hookSettings(url: string, token: string): { hooks: Record<string, unknown> } {
  const hook = (timeout: number) => [{
    hooks: [{ type: 'http', url, timeout, headers: { Authorization: `Bearer ${token}` } }],
  }]
  const hooks: Record<string, unknown> = { MessageDisplay: hook(DISPLAY_TIMEOUT_S) }
  for (const name of REPORTED_HOOKS) hooks[name] = hook(REPORT_TIMEOUT_S)
  return { hooks }
}

/** Longest tool summary, in characters. */
const SUMMARY_MAX = 120
/** Tool inputs larger than this (as JSON) aren't forwarded; the summary still is. */
const INPUT_MAX = 64 * 1024

const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)

interface OpenTool {
  agent: Id
  tool: string
  input: Record<string, unknown>
  summary: string
  /** Whether the input is small enough to forward. */
  small: boolean
  /** The request_id of its pending permission prompt, if any. */
  permission: Id | null
}

interface PendingPermission { agent: Id; toolCall: Id | null }

/** A permission prompt as the channel relays it (NOTES.md -> S02). */
export interface RelayedPermission {
  request_id: string
  tool_name: string
  description: string
  input_preview: string
}

/**
 * Turns one session's hooks into generic events. Keeps just enough state to
 * do that: agent states (to send only changes), open tool calls, messages
 * being streamed, and Agent tool calls waiting for their subagent.
 */
export class HookTranslator {
  private readonly cwd: string
  private readonly states = new Map<Id, State>([[MAIN, 'idle']])
  private readonly reasons = new Map<Id, string | null>([[MAIN, null]])
  private readonly openTools = new Map<Id, OpenTool>()
  /** Pending permission prompts by request_id. */
  private readonly permissions = new Map<Id, PendingPermission>()
  private readonly streaming = new Map<Id, string>()
  private readonly userMessages = new Set<Id>()
  /** Agent tool calls, oldest first, each waiting for its SubagentStart. */
  private readonly spawning: { caller: Id; type: string; task: string }[] = []

  constructor(cwd: string) {
    this.cwd = cwd
  }

  /** The events for one hook, in order. */
  translate(p: HookPayload): SessionEvent[] {
    const out: SessionEvent[] = []
    switch (p.hook_event_name) {
      case 'UserPromptSubmit': this.userPrompt(p, out); break
      case 'MessageDisplay': this.display(p, out); break
      case 'PreToolUse': this.toolStarted(p, out); break
      case 'PostToolUse': this.toolFinished(p, 'ok', out); break
      case 'PostToolUseFailure': this.toolFinished(p, 'error', out); break
      case 'SubagentStart': this.subagentStarted(p, out); break
      case 'SubagentStop': {
        const agent = str(p.agent_id)
        if (agent && this.states.has(agent)) {
          this.dropPermissions(agent, out)
          this.setState(agent, 'done', null, out)
        }
        break
      }
      case 'Notification': this.notification(p, out); break
      case 'Stop':
        this.finishMessages(out)
        this.dropPermissions(MAIN, out)
        this.setState(MAIN, 'idle', null, out)
        break
      case 'StopFailure':
        this.finishMessages(out)
        this.dropPermissions(MAIN, out)
        this.setState(MAIN, 'error', str(p.error_type) ?? 'unknown', out)
        break
    }
    return out
  }

  /**
   * The hook's agent: the orchestrator when there's no agent_id, a known
   * subagent, or null for an agent never seen starting (Claude Code's
   * internal helpers, which we ignore).
   */
  private agentOf(p: HookPayload): Id | null {
    const id = str(p.agent_id)
    if (!id) return MAIN
    return this.states.has(id) ? id : null
  }

  private setState(agent: Id, state: State, reason: string | null, out: SessionEvent[]) {
    if (this.states.get(agent) === state && this.reasons.get(agent) === reason) return
    this.states.set(agent, state)
    this.reasons.set(agent, reason)
    out.push({ type: 'agent.state_changed', agent, state, reason })
  }

  private userPrompt(p: HookPayload, out: SessionEvent[]) {
    const prompt = str(p.prompt) ?? ''
    const task = parseTaskNotification(prompt)
    const handback = parseHandback(prompt)
    if (handback) {
      // Not the user either: a subagent's final report, which Claude Code
      // hands to the orchestrator as a prompt (2.1.284).
      if (this.states.has(handback) && this.states.get(handback) !== 'done') this.setState(handback, 'done', null, out)
    } else if (task) {
      // Not the user: Claude Code tells the orchestrator a background task
      // ended. A subagent stopped from the terminal gets no SubagentStop,
      // only this.
      if (this.states.has(task.id) && this.states.get(task.id) !== 'done') {
        if (task.status === 'completed') this.setState(task.id, 'done', null, out)
        else this.setState(task.id, 'error', task.status ?? 'stopped', out)
      }
    } else {
      // The user typed while the orchestrator's prompt was pending: it was
      // answered "No" in the terminal, which fires no hook (NOTES.md -> S02).
      // The transcript shows that sooner; this is the fallback. A subagent's
      // prompt may still be open, so only the orchestrator's go.
      this.dropPermissions(MAIN, out)
      // prompt_id stays the same for prompts Claude Code injects later in the
      // turn, so it can't always name the message.
      const id = str(p.prompt_id)
      const message = id && !this.userMessages.has(id) ? id : crypto.randomUUID()
      this.userMessages.add(message)
      out.push({ type: 'message.started', message, agent: MAIN, role: 'user' })
      out.push({ type: 'message.completed', message, text: unwrapChannel(prompt) })
    }
    this.setState(MAIN, 'working', null, out)
  }

  private display(p: HookPayload, out: SessionEvent[]) {
    const agent = this.agentOf(p)
    const message = str(p.message_id)
    if (!agent || !message) return
    // 2.1.284 sends batches of whole lines (`delta`, `index`, `final`); the
    // docs describe one `message_text`. Accept both.
    const delta = str(p.delta)
    const text = delta ?? str(p.message_text) ?? ''
    const final = delta === undefined || p.final === true
    const sofar = this.streaming.get(message)
    if (sofar === undefined) out.push({ type: 'message.started', message, agent, role: 'assistant' })
    const full = (sofar ?? '') + text
    if (final) {
      this.streaming.delete(message)
      out.push({ type: 'message.completed', message, text: full })
    } else {
      this.streaming.set(message, full)
      if (text) out.push({ type: 'message.delta', message, text })
    }
  }

  /** Completes messages whose final batch never came (the turn ended). */
  private finishMessages(out: SessionEvent[]) {
    for (const [message, text] of this.streaming) out.push({ type: 'message.completed', message, text })
    this.streaming.clear()
  }

  private toolStarted(p: HookPayload, out: SessionEvent[]) {
    const agent = this.agentOf(p)
    const id = str(p.tool_use_id)
    const tool = str(p.tool_name)
    if (!agent || !id || !tool || this.openTools.has(id)) return
    const input = isObject(p.tool_input) ? p.tool_input : {}
    if (tool === 'Agent' || tool === 'Task') {
      this.spawning.push({ caller: agent, type: str(input.subagent_type) ?? '', task: str(input.description) ?? '' })
    }
    this.setState(agent, 'working', null, out)
    const summary = summarizeTool(tool, input, this.cwd)
    const small = JSON.stringify(input).length <= INPUT_MAX
    this.openTools.set(id, { agent, tool, input, summary, small, permission: null })
    out.push({ type: 'tool.started', tool_call: id, agent, tool, summary, ...(small ? { input } : {}) })
  }

  private toolFinished(p: HookPayload, status: 'ok' | 'error', out: SessionEvent[]) {
    const id = str(p.tool_use_id)
    const call = id ? this.openTools.get(id) : undefined
    if (!id || !call) return
    this.openTools.delete(id)
    // It ran, so a prompt it had was allowed, in the terminal.
    if (call.permission) this.resolvePermission(call.permission, 'allow', 'external', out, true)
    const error = status === 'error' ? str(p.error) : undefined
    out.push({ type: 'tool.finished', tool_call: id, status, ...(error ? { summary: clip(firstLine(error)) } : {}) })
  }

  /**
   * A permission prompt, as the channel relays it (it has no tool_use_id
   * or agent). It belongs to an open tool call of the same tool whose
   * PreToolUse came just before: the one whose input matches the preview,
   * else the newest without a prompt. Returns null if there's no such call
   * yet and `force` is false (the caller waits briefly for its PreToolUse);
   * with `force`, a prompt with no call is the orchestrator's.
   */
  permissionRequested(r: RelayedPermission, force = false): SessionEvent[] | null {
    if (this.permissions.has(r.request_id)) return []
    const candidates = [...this.openTools.entries()].filter(([, c]) => c.tool === r.tool_name && !c.permission)
    const exact = candidates.filter(([, c]) => previewMatches(r.input_preview, c.input))
    const pick = (exact.length > 0 ? exact : candidates).at(-1)
    if (!pick && !force) return null
    const out: SessionEvent[] = []
    let permission: Permission
    if (pick) {
      const [id, call] = pick
      call.permission = r.request_id
      permission = { permission: r.request_id, agent: call.agent, tool: call.tool, summary: call.summary, ...(call.small ? { input: call.input } : {}) }
      this.permissions.set(r.request_id, { agent: call.agent, toolCall: id })
    } else {
      const input = parseObject(r.input_preview)
      permission = {
        permission: r.request_id, agent: MAIN, tool: r.tool_name,
        summary: input ? summarizeTool(r.tool_name, input, this.cwd) : clip(r.description || r.tool_name),
        ...(input && JSON.stringify(input).length <= INPUT_MAX ? { input } : {}),
      }
      this.permissions.set(r.request_id, { agent: MAIN, toolCall: null })
    }
    out.push({ type: 'permission.requested', permission })
    this.setState(permission.agent, 'waiting', 'permission', out)
    return out
  }

  /** The user answered a prompt in the world (the verdict went down the bridge). */
  permissionAnswered(requestId: Id, decision: 'allow' | 'deny'): SessionEvent[] {
    const out: SessionEvent[] = []
    const p = this.permissions.get(requestId)
    if (!p) return out
    this.resolvePermission(requestId, decision, 'app', out, true)
    return out
  }

  /**
   * Clears a prompt. A denied call never runs and gets no hook of its own,
   * so it's closed here. With `resume`, an agent no longer waiting on any
   * prompt goes back to working.
   */
  private resolvePermission(requestId: Id, decision: 'allow' | 'deny', by: 'app' | 'external', out: SessionEvent[], resume: boolean) {
    const p = this.permissions.get(requestId)
    if (!p) return
    this.permissions.delete(requestId)
    const call = p.toolCall ? this.openTools.get(p.toolCall) : undefined
    if (call) call.permission = null
    out.push({ type: 'permission.resolved', permission: requestId, decision, by })
    if (decision === 'deny' && p.toolCall && this.openTools.delete(p.toolCall)) {
      out.push({ type: 'tool.finished', tool_call: p.toolCall, status: 'denied' })
    }
    if (!resume) return
    const stillWaiting = [...this.permissions.values()].some((q) => q.agent === p.agent)
    if (!stillWaiting && this.states.get(p.agent) === 'waiting' && this.reasons.get(p.agent) === 'permission') {
      this.setState(p.agent, 'working', null, out)
    }
  }

  /**
   * The agent moved on while its prompts were pending, so they were
   * answered "No" in the terminal (the only answer that fires no hook).
   * Their tool calls never ran. The caller sets the agent's new state.
   */
  private dropPermissions(agent: Id, out: SessionEvent[]) {
    for (const [id, p] of [...this.permissions]) {
      if (p.agent === agent) this.resolvePermission(id, 'deny', 'external', out, false)
    }
  }

  private subagentStarted(p: HookPayload, out: SessionEvent[]) {
    const agent = str(p.agent_id)
    if (!agent || this.states.has(agent)) return
    const type = str(p.agent_type) ?? ''
    // SubagentStart doesn't name the parent: take the oldest Agent call for
    // this agent type (or the oldest at all). Exact one at a time; with
    // parallel spawns of one type the tasks may pair up in the wrong order.
    let i = this.spawning.findIndex((s) => s.type === type)
    if (i < 0) i = this.spawning.length > 0 ? 0 : -1
    const call = i >= 0 ? this.spawning.splice(i, 1)[0]! : null
    const parent = call && this.states.has(call.caller) ? call.caller : MAIN
    const a: Agent = {
      agent, role: 'subagent', parent, state: 'working', reason: null,
      ...(type ? { name: type } : {}),
      ...(call?.task ? { task: call.task } : {}),
    }
    this.states.set(agent, 'working')
    this.reasons.set(agent, null)
    out.push({ type: 'agent.spawned', agent: a })
  }

  private notification(p: HookPayload, out: SessionEvent[]) {
    const agent = this.agentOf(p)
    if (!agent) return
    switch (p.notification_type) {
      // Claude Code waits on the user in the terminal for something other
      // than a permission (one of the user's MCP servers asks, or an agent
      // needs input).
      case 'elicitation_dialog':
      case 'elicitation_url_dialog':
      case 'agent_needs_input':
        this.setState(agent, 'waiting', 'input', out)
        break
      case 'elicitation_complete':
      case 'elicitation_response':
        if (this.states.get(agent) === 'waiting') this.setState(agent, 'working', null, out)
        break
      // permission_prompt comes with the permission relay; idle_prompt only
      // repeats that the turn is over.
    }
  }
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function parseObject(s: string): Record<string, unknown> | null {
  try {
    const v: unknown = JSON.parse(s)
    return isObject(v) ? v : null
  } catch { return null }
}

/**
 * Whether the relay's input preview shows this input. The preview is JSON,
 * spaced differently and possibly cut short, so compare without whitespace
 * (both sides alike) and allow a cut-off end.
 */
export function previewMatches(preview: string, input: Record<string, unknown>): boolean {
  const squash = (s: string) => s.replace(/\s+/g, '')
  const full = squash(JSON.stringify(input))
  const parsed = parseObject(preview)
  if (parsed) return squash(JSON.stringify(parsed)) === full
  const p = squash(preview).replace(/(\.\.\.|…)$/, '')
  return p.length >= 8 && full.startsWith(p)
}

/** A message from the world arrives wrapped in our channel's tag; show only the text. */
export function unwrapChannel(prompt: string): string {
  const m = /^<channel(\s[^>]*)>\n?([\s\S]*?)\n?<\/channel>$/.exec(prompt.trim())
  const source = m ? /\ssource="([^"]*)"/.exec(m[1]!)?.[1] : undefined
  return source === BRIDGE_SERVER_NAME ? m![2]! : prompt
}

/** The parts of a `<task-notification>` prompt we use, or null if it isn't one. */
export function parseTaskNotification(prompt: string): { id: string; status: string | null } | null {
  if (!prompt.startsWith('<task-notification>')) return null
  const id = /<task-id>([^<]+)<\/task-id>/.exec(prompt)?.[1]
  if (!id) return null
  return { id, status: /<status>([^<]+)<\/status>/.exec(prompt)?.[1] ?? null }
}

/** The subagent whose report a `<agent-message>` hand-back prompt carries, or null. */
export function parseHandback(prompt: string): string | null {
  const m = /^<agent-message from="([^"]+)">\n\[Subagent hand-back\]/.exec(prompt)
  return m ? m[1]! : null
}

function firstLine(s: string): string {
  return s.trim().split(/\r?\n/, 1)[0] ?? ''
}

function clip(s: string): string {
  return s.length > SUMMARY_MAX ? s.slice(0, SUMMARY_MAX - 1) + '…' : s
}

/** A path as the user thinks of it: relative to the project when inside it. */
function shortPath(p: string, cwd: string): string {
  const rel = path.relative(cwd, p)
  return rel && !rel.startsWith('..') && !path.isAbsolute(rel) ? rel : p
}

/** One readable line for a tool call, e.g. "Run: npm install". */
export function summarizeTool(tool: string, input: Record<string, unknown>, cwd: string): string {
  const file = str(input.file_path) ?? str(input.notebook_path)
  const at = file ? shortPath(file, cwd) : ''
  let s: string
  switch (tool) {
    case 'Bash':
    case 'PowerShell': s = `Run: ${firstLine(str(input.command) ?? '')}`; break
    case 'Read': s = `Read ${at}`; break
    case 'Write': s = `Write ${at}`; break
    case 'Edit':
    case 'MultiEdit':
    case 'NotebookEdit': s = `Edit ${at}`; break
    case 'Glob': s = `Find ${str(input.pattern) ?? 'files'}`; break
    case 'Grep': s = `Search for ${str(input.pattern) ?? ''}`; break
    case 'WebFetch': s = `Fetch ${str(input.url) ?? ''}`; break
    case 'WebSearch': s = `Search the web: ${str(input.query) ?? ''}`; break
    case 'Agent':
    case 'Task': s = `Start an agent: ${str(input.description) ?? ''}`; break
    case 'TodoWrite': s = 'Update the to-do list'; break
    case 'AskUserQuestion': s = 'Ask the user'; break
    case 'SubagentHandback': s = 'Report back'; break
    default: {
      // MCP tools are mcp__<server>__<tool>.
      const mcp = /^mcp__(.+?)__(.+)$/.exec(tool)
      s = mcp ? `${mcp[1]}: ${mcp[2]}` : tool
    }
  }
  return clip(s.trim())
}
