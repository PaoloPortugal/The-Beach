// Claude Code's hooks (NOTES.md -> S02 -> Seeing the session): the settings
// that make a launched session post them to us, and their translation into
// the generic protocol. Payload shapes are the ones Claude Code 2.1.284 sent
// in the S02 spike, which differ from the hooks docs in places
// (MessageDisplay); every field is treated as optional and checked.
import path from 'node:path'
import crypto from 'node:crypto'
import type { Agent, Id, Permission, QuestionItem, Reasoned, SessionEvent, State } from '../../protocol.ts'
import { jsonBytes } from '../../history.ts'
import type { HookPayload } from './hook-server.ts'
import { BRIDGE_SERVER_NAME } from './bridge.ts'
import { promptOptions, type PermissionUpdate, type PromptOption } from './prompt-options.ts'

/** The orchestrator's agent id. Subagents use Claude Code's agent_id. */
export const MAIN = 'main'

/**
 * StopFailure's errors that only the user can sort out, in Claude Code's
 * own terminal (NOTES.md -> S06): the account can't be used. We never
 * handle a login; the notice says what to do there. Each maps to the
 * notice's English text and its reason, which Godot words (C16 step 6),
 * with the provider's own words in its details.
 */
export const SIGN_IN_ERRORS: Readonly<Record<string, Reasoned & { message: string }>> = {
  authentication_failed: {
    message: 'Claude Code needs you to sign in again: run /login in its terminal.',
    reason: 'signed_out', details: { command: '/login' },
  },
  oauth_org_not_allowed: {
    message: "Your organization doesn't allow this account in Claude Code: run /login in its terminal to sign in with another.",
    reason: 'org_not_allowed', details: { command: '/login' },
  },
  cloud_credential_error: {
    message: "Claude Code couldn't load your cloud provider's credentials: check its terminal.",
    reason: 'cloud_credentials',
  },
  account_on_hold: {
    message: "Your Claude account is on hold: check Claude Code's terminal.",
    reason: 'account_on_hold', details: { account: 'Claude' },
  },
  billing_error: {
    message: 'Claude Code reports a billing problem with your account: check its terminal.',
    reason: 'billing',
  },
}

/** The notice's code (generic: every tool has logins). */
export const SIGN_IN_NEEDED = 'sign_in_needed'

/**
 * StopFailure's other errors, passed on as the generic `error` reason
 * (Protocol -> state_reason). Any type Claude Code adds later is `unknown`,
 * so no Claude-only name reaches the protocol.
 */
export const STOP_REASONS: ReadonlySet<string> = new Set([
  'rate_limit', 'overloaded', 'server_error', 'invalid_request', 'model_not_found', 'max_output_tokens',
])

/** Hooks that only report: short, so a hung sidecar costs little. */
const REPORT_TIMEOUT_S = 5
/** MessageDisplay holds up the text on screen; answered instantly anyway. */
const DISPLAY_TIMEOUT_S = 2
/**
 * A question is held open until the user answers in either place. If this
 * runs out, the terminal's question simply stays (NOTES.md -> S02).
 */
const QUESTION_TIMEOUT_S = 24 * 60 * 60
/** Claude Code's clarifying-question tool. */
export const QUESTION_TOOL = 'AskUserQuestion'
/** The tool Claude calls to present its plan for approval (C07). */
export const PLAN_TOOL = 'ExitPlanMode'
/**
 * The tools whose prompts can switch to auto mode, as the terminal's
 * "Yes, and switch to auto mode" (C06; seen on Bash in the spike,
 * 2026-10-03).
 */
export const AUTO_SWITCH_TOOLS: readonly string[] = ['Bash']
/** The modes a Bash prompt offers the auto switch in (Manual, Accept edits). */
const AUTO_SWITCH_FROM: readonly string[] = ['default', 'acceptEdits']

/** Hook events we translate (SessionStart can't be an HTTP hook; see hookSettings). */
export const REPORTED_HOOKS = [
  'UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'PostToolUseFailure',
  'SubagentStart', 'SubagentStop', 'Notification', 'Stop', 'StopFailure',
  // C12: the model, changed by /model, a fallback or a resume.
  'PostModelSwitch',
] as const

/**
 * SessionStart's timeout. After /resume inside a session, Claude Code
 * waits for SessionStart hooks before switching, so it's short; the relay
 * gives up after 2 s itself.
 */
const SESSION_START_TIMEOUT_S = 5

/**
 * The `--settings` JSON for one session: every hook posts to `url` with its
 * token, and agent view is off (user's decision, 2026-10-01). Agent view
 * (Left at an empty prompt, /bg, /fork) moves the conversation into a
 * background session: a new process under Claude Code's supervisor, with
 * a new session id and without our channel flag, so the world could no
 * longer talk to it (NOTES.md -> S02 -> Launch).
 *
 * SessionStart allows only command (and MCP tool) hooks, so it runs `relay`,
 * our own executable in relay mode, in exec form (`command` plus `args`:
 * spawned directly, no shell), which posts it to the same endpoint. Only
 * for /clear and /resume: the world follows those (NOTES.md -> S02 ->
 * Following the conversation).
 */
export function hookSettings(url: string, token: string, relay: string[], statusLine?: { type: 'command'; command: string }):
  { hooks: Record<string, unknown>; disableAgentView: true; statusLine?: { type: 'command'; command: string } } {
  const hook = (timeout: number) => [{
    hooks: [{ type: 'http', url, timeout, headers: { Authorization: `Bearer ${token}` } }],
  }]
  const hooks: Record<string, unknown> = { MessageDisplay: hook(DISPLAY_TIMEOUT_S) }
  for (const name of REPORTED_HOOKS) hooks[name] = hook(REPORT_TIMEOUT_S)
  // Every prompt: questions and plans are held until the user answers in
  // either place (the terminal still shows them); other prompts bring
  // their options (C05), and are held only while they have some. A plain
  // Yes or No still goes through the channel's relay.
  hooks.PermissionRequest = [{ matcher: '*', hooks: hook(QUESTION_TIMEOUT_S)[0]!.hooks }]
  const [command, ...args] = relay
  if (!command) throw new Error('no relay command')
  hooks.SessionStart = [{
    matcher: '^(clear|resume)$',
    hooks: [{ type: 'command', command, args, timeout: SESSION_START_TIMEOUT_S }],
  }]
  // C08: our status line relay, when the session has one (see statusline.ts).
  return { hooks, disableAgentView: true, ...(statusLine ? { statusLine } : {}) }
}

/** Longest tool summary, in characters. */
const SUMMARY_MAX = 120
/** Tool inputs larger than this (UTF-8 bytes as JSON) aren't forwarded; the summary still is. */
export const INPUT_MAX = 64 * 1024

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
  /** Its pending question, if it's a question. */
  question: Id | null
  /** Its pending plan, if it's a plan. */
  plan: Id | null
  /** Its prompt's options, from its PermissionRequest hook (C05); null until that came. */
  options: PromptOption[] | null
}

interface PendingQuestion { agent: Id; toolCall: Id | null; input: Record<string, unknown> }

interface PendingPlan { agent: Id; toolCall: Id | null; input: Record<string, unknown> }

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
  private readonly questions = new Map<Id, PendingQuestion>()
  private readonly plans = new Map<Id, PendingPlan>()
  /** The permission mode, from the orchestrator's hooks (C06); null until one says. */
  private mode: string | null = null
  /**
   * Whether this session has been in auto mode. Claude Code starts in auto
   * when it's available (2.1.283+), so this is how we know it can be
   * offered (user's rule, 2026-10-03).
   */
  private autoSeen = false
  private readonly streaming = new Map<Id, string>()
  private readonly userMessages = new Set<Id>()
  /** Agent tool calls, oldest first, each waiting for its SubagentStart. */
  private readonly spawning: { call: Id; caller: Id; type: string; task: string }[] = []
  /** Each subagent's Agent call, for its own calls' `within` (C04). */
  private readonly spawnedBy = new Map<Id, Id>()

  /** The sign_in_needed notice's message while it is up (S06). */
  private signInNeeded: string | null = null

  constructor(cwd: string) {
    this.cwd = cwd
  }

  /**
   * The orchestrator's state when the world takes over a session already
   * running (S07), known from outside the hooks; no events (the session is
   * announced in it).
   */
  assume(state: State, reason: string | null): void {
    this.states.set(MAIN, state)
    this.reasons.set(MAIN, reason)
  }

  /**
   * Read-only (S07): Claude Code's own status for the orchestrator (`claude
   * agents`), for what its transcript can't show: that it waits on the user
   * in the terminal (a prompt, a question), and that it stopped waiting.
   */
  outsideStatus(status: string): SessionEvent[] {
    const out: SessionEvent[] = []
    const { state, reason } = this.mainState()
    if (status === 'waiting' && state === 'working') this.setState(MAIN, 'waiting', 'input', out)
    else if (state === 'waiting' && reason === 'input' && status === 'busy') this.setState(MAIN, 'working', null, out)
    else if (state === 'waiting' && reason === 'input' && status === 'idle') this.setState(MAIN, 'idle', null, out)
    return out
  }

  /** The orchestrator's state and reason now. */
  mainState(): { state: State; reason: string | null } {
    return { state: this.states.get(MAIN) ?? 'idle', reason: this.reasons.get(MAIN) ?? null }
  }

  /**
   * The mode an orchestrator hook reports (every hook but MessageDisplay
   * and Notification carries it; a Shift+Tab shows with the next one).
   * A subagent's hooks are left out: the session's mode is the
   * orchestrator's.
   */
  noteMode(p: HookPayload): SessionEvent[] {
    const mode = str(p.permission_mode)
    if (!mode || p.agent_id !== undefined || mode === this.mode) return []
    this.mode = mode
    if (mode === 'auto') this.autoSeen = true
    return [{ type: 'session.updated', mode }]
  }

  /** The modes approving a plan can switch to, in the terminal's order. */
  planModes(): string[] {
    return [this.autoSeen ? 'auto' : 'acceptEdits', 'default']
  }

  /**
   * The modes a prompt for this tool can switch to (the terminal's "Yes,
   * and switch to auto mode"), given the mode it was asked in.
   */
  switchModes(tool: string, mode: string | null = this.mode): string[] {
    return this.autoSeen && AUTO_SWITCH_TOOLS.includes(tool) && mode !== null && AUTO_SWITCH_FROM.includes(mode)
      ? ['auto'] : []
  }

  /** The events for one hook, in order. */
  translate(p: HookPayload): SessionEvent[] {
    const out: SessionEvent[] = []
    switch (p.hook_event_name) {
      case 'UserPromptSubmit': this.userPrompt(p, out); break
      case 'MessageDisplay': this.display(p, out); break
      case 'PreToolUse': this.signedIn(out); this.toolStarted(p, out); break
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
        this.signedIn(out)
        this.finishMessages(out)
        this.dropPermissions(MAIN, out)
        this.setState(MAIN, 'idle', null, out)
        break
      case 'StopFailure': {
        this.finishMessages(out)
        this.dropPermissions(MAIN, out)
        // `error`, the error type (checked live on 2.1.294; dev log
        // 2026-10-08-s06-sign-in). An account problem waits on the user in
        // the terminal; anything else stops the turn with its reason.
        const error = str(p.error) ?? 'unknown'
        const signIn = Object.hasOwn(SIGN_IN_ERRORS, error) ? SIGN_IN_ERRORS[error] : undefined
        if (signIn !== undefined) {
          // Failing again the same way keeps the notice that is up.
          if (this.signInNeeded !== signIn.message) out.push({ type: 'session.notice', notice: { code: SIGN_IN_NEEDED, ...signIn } })
          this.signInNeeded = signIn.message
          this.setState(MAIN, 'waiting', 'sign_in', out)
        } else {
          this.setState(MAIN, 'error', STOP_REASONS.has(error) ? error : 'unknown', out)
        }
        break
      }
    }
    return out
  }

  /**
   * The transcript shows a "No" in the terminal for this call (no hook
   * fires for it): its prompt is denied there and the call never runs.
   */
  rejectedInTerminal(toolUseId: Id): SessionEvent[] {
    const out: SessionEvent[] = []
    const call = this.openTools.get(toolUseId)
    if (!call) return out
    if (call.permission) this.resolvePermission(call.permission, 'deny', 'external', out, false)
    if (call.question) this.resolveQuestion(call.question, 'external', out, false)
    if (call.plan) this.resolvePlan(call.plan, 'rejected', 'external', out, false)
    this.closeTool(toolUseId, 'denied', out)
    return out
  }

  /**
   * The transcript shows the orchestrator's turn interrupted from the
   * terminal (Esc, or after a "No"); no hook fires. Its prompts were
   * dismissed, a running command was stopped, and it's the user's move.
   */
  interruptedByUser(): SessionEvent[] {
    const out: SessionEvent[] = []
    if (!this.isBusy(MAIN)) return out
    this.finishMessages(out)
    this.dropPermissions(MAIN, out)
    for (const [id, call] of [...this.openTools]) {
      if (call.agent === MAIN) this.closeTool(id, 'error', out, 'Interrupted')
    }
    this.setState(MAIN, 'idle', null, out)
    return out
  }

  /** Whether any agent is working or waiting (something a stop would end). */
  busy(): boolean {
    for (const state of this.states.values()) if (state === 'working' || state === 'waiting') return true
    return false
  }

  /** The agents working or waiting. */
  busyAgents(): Id[] {
    return [...this.states.keys()].filter((a) => this.isBusy(a))
  }

  /** Whether this agent is working or waiting. */
  isBusy(agent: Id): boolean {
    const state = this.states.get(agent)
    return state === 'working' || state === 'waiting'
  }

  /** Pending permission prompts (request ids), oldest first. */
  pendingPermissions(): Id[] {
    return [...this.permissions.keys()]
  }

  /**
   * The sidecar stopped this PreToolUse's call (after translate() saw it):
   * the call never runs, and the agent's turn ends with no hook of its own,
   * so the states are set here. The orchestrator is then idle (the user's
   * move); a subagent is interrupted (error), and the orchestrator is told.
   */
  stopped(p: HookPayload): SessionEvent[] {
    const out: SessionEvent[] = []
    const agent = this.agentOf(p)
    const id = str(p.tool_use_id)
    if (!agent) return out
    if (id) this.closeTool(id, 'denied', out)
    this.dropPermissions(agent, out)
    if (agent === MAIN) {
      this.finishMessages(out)
      this.setState(MAIN, 'idle', null, out)
    } else {
      this.setState(agent, 'error', 'interrupted', out)
    }
    return out
  }

  /**
   * The hook's agent: the orchestrator when there's no agent_id, a known
   * subagent, or null for an agent never seen starting (Claude Code's
   * internal helpers, which we ignore).
   */
  agentOf(p: HookPayload): Id | null {
    const id = str(p.agent_id)
    if (!id) return MAIN
    return this.states.has(id) ? id : null
  }

  /**
   * The account works again: Claude Code says the user signed in, or an
   * API call went through (a tool call, a turn ending well). The notice
   * goes; an orchestrator still waiting to sign in is idle.
   */
  private signedIn(out: SessionEvent[]) {
    if (this.signInNeeded === null) return
    this.signInNeeded = null
    out.push({ type: 'session.notice_cleared', code: SIGN_IN_NEEDED })
    if (this.states.get(MAIN) === 'waiting' && this.reasons.get(MAIN) === 'sign_in') this.setState(MAIN, 'idle', null, out)
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
      this.spawning.push({ call: id, caller: agent, type: str(input.subagent_type) ?? '', task: str(input.description) ?? '' })
    }
    this.setState(agent, 'working', null, out)
    // The plan, as its own message before the call that presents it (C07):
    // the chat keeps it as a record, whatever the answer.
    const plan = tool === PLAN_TOOL ? str(input.plan) : undefined
    if (plan?.trim()) {
      const message = `${id}:plan`
      out.push({ type: 'message.started', message, agent, role: 'assistant', kind: 'plan' })
      out.push({ type: 'message.completed', message, text: plan })
    }
    const summary = summarizeTool(tool, input, this.cwd)
    const small = jsonBytes(input) <= INPUT_MAX
    this.openTools.set(id, { agent, tool, input, summary, small, permission: null, question: null, plan: null, options: null })
    const within = this.spawnedBy.get(agent)
    out.push({ type: 'tool.started', tool_call: id, agent, tool, summary, ...(small ? { input } : {}), ...(within ? { within } : {}) })
  }

  private toolFinished(p: HookPayload, status: 'ok' | 'error', out: SessionEvent[]) {
    const id = str(p.tool_use_id)
    const call = id ? this.openTools.get(id) : undefined
    if (!id || !call) return
    // It ran, so a prompt it had was allowed, and a question answered, in the terminal.
    if (call.permission) this.resolvePermission(call.permission, 'allow', 'external', out, true)
    if (call.question) this.resolveQuestion(call.question, 'external', out, true)
    // A plan: it went ahead, so it was approved there; a failure, it didn't.
    if (call.plan) this.resolvePlan(call.plan, status === 'ok' ? 'approved' : 'rejected', 'external', out, true)
    const error = status === 'error' ? str(p.error) : undefined
    this.closeTool(id, status, out, error ? clip(firstLine(error)) : undefined)
  }

  /**
   * Ends an open tool call. An Agent call that ends before its subagent
   * started (denied, failed, stopped) no longer waits for one.
   */
  private closeTool(id: Id, status: 'ok' | 'error' | 'denied', out: SessionEvent[], summary?: string) {
    if (!this.openTools.delete(id)) return
    if (status !== 'ok') {
      const i = this.spawning.findIndex((s) => s.call === id)
      if (i >= 0) this.spawning.splice(i, 1)
    }
    out.push({ type: 'tool.finished', tool_call: id, status, ...(summary ? { summary } : {}) })
  }

  /**
   * A permission prompt, as the channel relays it (it has no tool_use_id
   * or agent). It belongs to an open tool call of the same tool whose
   * PreToolUse came just before and whose input matches the preview: only
   * that one, so the card always shows what a Yes approves (another call
   * of the same tool may be open, or its own not read yet). Returns null
   * if there's no such call yet and `force` is false (the caller waits
   * briefly for its PreToolUse); with `force`, a prompt with no call is
   * the orchestrator's, shown from the preview itself.
   */
  permissionRequested(r: RelayedPermission, force = false): SessionEvent[] | null {
    if (this.permissions.has(r.request_id)) return []
    const matches = [...this.openTools.entries()]
      .filter(([, c]) => c.tool === r.tool_name && !c.permission && previewMatches(r.input_preview, c.input))
    // Calls with different inputs that all fit a cut-short preview: which one it is can't be told.
    const one = new Set(matches.map(([, c]) => JSON.stringify(c.input))).size <= 1
    const pick = one ? matches.at(-1) : undefined
    // Its options come with its PermissionRequest hook; wait for that too.
    if ((!pick || pick[1].options === null) && !force) return null
    const out: SessionEvent[] = []
    let permission: Permission
    if (pick) {
      const [id, call] = pick
      call.permission = r.request_id
      // The fields Godot shows; the updates never leave the sidecar.
      const options = (call.options ?? []).map(({ option, label, kind, parts }) =>
        ({ option, label, ...(kind ? { kind } : {}), ...(parts ? { parts } : {}) }))
      permission = {
        permission: r.request_id, agent: call.agent, tool: call.tool, summary: call.summary,
        ...(call.small ? { input: call.input } : {}), ...(options.length > 0 ? { options } : {}),
      }
      this.permissions.set(r.request_id, { agent: call.agent, toolCall: id })
    } else {
      const input = parseObject(r.input_preview)
      permission = {
        permission: r.request_id, agent: MAIN, tool: r.tool_name,
        summary: input ? summarizeTool(r.tool_name, input, this.cwd) : clip(r.description || r.tool_name),
        ...(input && jsonBytes(input) <= INPUT_MAX ? { input } : {}),
      }
      this.permissions.set(r.request_id, { agent: MAIN, toolCall: null })
    }
    out.push({ type: 'permission.requested', permission })
    this.setState(permission.agent, 'waiting', 'permission', out)
    return out
  }

  /**
   * A prompt's PermissionRequest hook (not a question's or a plan's): its
   * options (C05) go on its open tool call: the same agent's newest of
   * that tool with the same input whose hook hasn't come yet. Returns that
   * call if the prompt has options (then the hook is held, so choosing one
   * can answer it), else null. A prompt the world was already shown
   * without them (its hook came too late) keeps none.
   */
  promptHooked(p: HookPayload): Id | null {
    const tool = str(p.tool_name)
    const agent = this.agentOf(p)
    if (!tool || !agent) return null
    const input = isObject(p.tool_input) ? p.tool_input : {}
    const json = JSON.stringify(input)
    const found = [...this.openTools.entries()]
      .filter(([, c]) => c.agent === agent && c.tool === tool && c.options === null && JSON.stringify(c.input) === json).at(-1)
    if (!found) return null
    const [id, call] = found
    if (call.permission) {
      call.options = []
      return null
    }
    const auto = this.switchModes(tool, str(p.permission_mode) ?? this.mode).length > 0
    call.options = promptOptions(tool, input, p.permission_suggestions, auto, this.cwd)
    return call.options.length > 0 ? id : null
  }

  /** A pending prompt's option: its tool call, input and the updates choosing it applies; null if it has none such. */
  promptOption(requestId: Id, option: Id): { toolCall: Id; input: Record<string, unknown>; updates: PermissionUpdate[] } | null {
    const toolCall = this.permissions.get(requestId)?.toolCall
    const call = toolCall ? this.openTools.get(toolCall) : undefined
    const chosen = call?.options?.find((o) => o.option === option)
    return toolCall && call && chosen ? { toolCall, input: call.input, updates: chosen.updates } : null
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
    if (decision === 'deny' && p.toolCall) this.closeTool(p.toolCall, 'denied', out)
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
    // A question the agent moved on from was answered or dismissed (Esc) there.
    for (const [id, q] of [...this.questions]) {
      if (q.agent === agent) this.resolveQuestion(id, 'external', out, false)
    }
    // A plan the same way: sent back there (Esc, or the user typed).
    for (const [id, q] of [...this.plans]) {
      if (q.agent === agent) this.resolvePlan(id, 'rejected', 'external', out, false)
    }
  }

  /**
   * A plan to approve (the held PermissionRequest for ExitPlanMode, C07).
   * Returns its id and events, or null if it can't be shown (then the hook
   * is answered at once and the plan stays in the terminal only).
   */
  planAsked(p: HookPayload): { plan: Id; events: SessionEvent[] } | null {
    const hookAgent = this.agentOf(p)
    const input = isObject(p.tool_input) ? p.tool_input : null
    const text = input ? str(input.plan) : undefined
    if (!hookAgent || !input || text === undefined) return null
    // Its PreToolUse came first, with the tool_use_id: the newest open plan
    // call, preferably the same agent's.
    const open = [...this.openTools.entries()].filter(([, c]) => c.tool === PLAN_TOOL && !c.plan)
    const [toolCall, call] = open.filter(([, c]) => c.agent === hookAgent).at(-1) ?? open.at(-1) ?? [null, null]
    const agent = call?.agent ?? hookAgent
    const plan = toolCall && !this.plans.has(toolCall) ? toolCall : crypto.randomUUID()
    if (call) call.plan = plan
    this.plans.set(plan, { agent, toolCall, input })
    const events: SessionEvent[] = [{ type: 'plan.asked', plan: { plan, agent, text, modes: this.planModes() } }]
    this.setState(agent, 'waiting', 'plan', events)
    return { plan, events }
  }

  /** The input the plan was presented with (echoed back when approving). */
  planInput(plan: Id): Record<string, unknown> | null {
    return this.plans.get(plan)?.input ?? null
  }

  /** Plans waiting for approval. */
  pendingPlans(): Id[] {
    return [...this.plans.keys()]
  }

  /**
   * Answered in the world (the held hook was answered). Sent back, the
   * call was denied, and Claude Code sends no hook for it (spike,
   * 2026-10-03), so it's closed here.
   */
  planAnswered(plan: Id, approved: boolean): SessionEvent[] {
    const out: SessionEvent[] = []
    const call = this.plans.get(plan)?.toolCall
    this.resolvePlan(plan, approved ? 'approved' : 'rejected', 'app', out, true)
    if (!approved && call) this.closeTool(call, 'denied', out)
    return out
  }

  /** Claude Code stopped waiting on the held hook (it exited, or the hook timed out). */
  planGone(plan: Id): SessionEvent[] {
    const out: SessionEvent[] = []
    this.resolvePlan(plan, 'rejected', 'external', out, true)
    return out
  }

  private resolvePlan(plan: Id, decision: 'approved' | 'rejected', by: 'app' | 'external', out: SessionEvent[], resume: boolean) {
    const q = this.plans.get(plan)
    if (!q) return
    this.plans.delete(plan)
    const call = q.toolCall ? this.openTools.get(q.toolCall) : undefined
    if (call) call.plan = null
    out.push({ type: 'plan.resolved', plan, decision, by })
    const stillWaiting = [...this.plans.values()].some((x) => x.agent === q.agent)
    if (resume && !stillWaiting && this.states.get(q.agent) === 'waiting' && this.reasons.get(q.agent) === 'plan') {
      this.setState(q.agent, 'working', null, out)
    }
  }

  /**
   * A clarifying question (the held PermissionRequest for AskUserQuestion).
   * Returns its id and events, or null if it can't be shown (then the hook
   * is answered at once and the question stays in the terminal only).
   */
  questionAsked(p: HookPayload): { question: Id; events: SessionEvent[] } | null {
    const hookAgent = this.agentOf(p)
    const input = isObject(p.tool_input) ? p.tool_input : null
    const items = input ? questionItems(input) : null
    if (!hookAgent || !input || !items) return null
    // Its PreToolUse came first, with the tool_use_id and the agent (in
    // case this hook doesn't name a subagent): the newest open question
    // call, preferably the same agent's.
    const open = [...this.openTools.entries()].filter(([, c]) => c.tool === QUESTION_TOOL && !c.question)
    const [toolCall, call] = open.filter(([, c]) => c.agent === hookAgent).at(-1) ?? open.at(-1) ?? [null, null]
    const agent = call?.agent ?? hookAgent
    const question = toolCall && !this.questions.has(toolCall) ? toolCall : crypto.randomUUID()
    if (call) call.question = question
    this.questions.set(question, { agent, toolCall, input })
    const events: SessionEvent[] = [{ type: 'question.asked', question: { question, agent, items } }]
    this.setState(agent, 'waiting', 'question', events)
    return { question, events }
  }

  /** The input the question was asked with (for the answer's reply). */
  questionInput(question: Id): Record<string, unknown> | null {
    return this.questions.get(question)?.input ?? null
  }

  /**
   * Answered in the world (the held hook was answered). With `denied` (a
   * free reply, or declined by a stop) the question's tool call was denied,
   * and Claude Code sends no hook for it (seen at checkpoint 2), so it's
   * closed here.
   */
  questionAnswered(question: Id, denied = false): SessionEvent[] {
    const out: SessionEvent[] = []
    const call = this.questions.get(question)?.toolCall
    this.resolveQuestion(question, 'app', out, true)
    if (denied && call) this.closeTool(call, 'denied', out)
    return out
  }

  /** Claude Code stopped waiting on the held hook (answered or dismissed there, or timed out). */
  questionGone(question: Id): SessionEvent[] {
    const out: SessionEvent[] = []
    this.resolveQuestion(question, 'external', out, true)
    return out
  }

  private resolveQuestion(question: Id, by: 'app' | 'external', out: SessionEvent[], resume: boolean) {
    const q = this.questions.get(question)
    if (!q) return
    this.questions.delete(question)
    const call = q.toolCall ? this.openTools.get(q.toolCall) : undefined
    if (call) call.question = null
    out.push({ type: 'question.resolved', question, by })
    const stillWaiting = [...this.questions.values()].some((x) => x.agent === q.agent)
    if (resume && !stillWaiting && this.states.get(q.agent) === 'waiting' && this.reasons.get(q.agent) === 'question') {
      this.setState(q.agent, 'working', null, out)
    }
  }

  private subagentStarted(p: HookPayload, out: SessionEvent[]) {
    const agent = str(p.agent_id)
    if (!agent || this.states.has(agent)) return
    const type = str(p.agent_type) ?? ''
    // SubagentStart doesn't name the parent: take the oldest Agent call for
    // this agent type (or the oldest at all). Exact one at a time; with
    // parallel spawns of one type the tasks may pair up in the wrong order.
    // Read from the transcript (S07's read-only mode), the call is known.
    const by = str(p.spawned_by)
    let i = by ? this.spawning.findIndex((s) => s.call === by) : -1
    if (i < 0) i = this.spawning.findIndex((s) => s.type === type)
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
    if (call) this.spawnedBy.set(agent, call.call)
    out.push({ type: 'agent.spawned', agent: a })
  }

  private notification(p: HookPayload, out: SessionEvent[]) {
    const agent = this.agentOf(p)
    if (!agent) return
    switch (p.notification_type) {
      // Signed in again (/login in the terminal; from the docs, not yet seen live).
      case 'auth_success':
        this.signedIn(out)
        break
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

/** AskUserQuestion's input as protocol items, or null if it isn't one. */
export function questionItems(input: Record<string, unknown>): QuestionItem[] | null {
  const qs = input.questions
  if (!Array.isArray(qs) || qs.length === 0) return null
  const items: QuestionItem[] = []
  for (const q of qs) {
    if (!isObject(q) || typeof q.question !== 'string' || !Array.isArray(q.options)) return null
    const options: QuestionItem['options'] = []
    for (const o of q.options) {
      if (!isObject(o) || typeof o.label !== 'string') return null
      options.push({ label: o.label, ...(typeof o.description === 'string' ? { description: o.description } : {}) })
    }
    items.push({
      text: q.question, options, multi_select: q.multiSelect === true,
      ...(typeof q.header === 'string' ? { header: q.header } : {}),
    })
  }
  return items
}

/**
 * The held hook's reply for an answer from the world. Answers: allow with
 * the input plus `answers` keyed by question text (verified in the spike;
 * several labels of a multi-select joined by ", ", unverified). A free
 * response instead: deny with the user's words as the message (unverified).
 * Throws on answers that don't fit the questions.
 */
export function questionReply(input: Record<string, unknown>, answer: { answers: string[][] } | { response: string }): Record<string, unknown> {
  const decision = (d: Record<string, unknown>) => ({ hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: d } })
  if ('response' in answer) return decision({ behavior: 'deny', message: answer.response })
  const items = questionItems(input) ?? []
  if (answer.answers.length !== items.length || answer.answers.some((a) => a.length === 0)) {
    throw new Error('one answer per question is needed')
  }
  const answers: Record<string, string> = {}
  items.forEach((item, i) => { answers[item.text] = answer.answers[i]!.join(', ') })
  return decision({ behavior: 'allow', updatedInput: { ...input, answers } })
}

/**
 * A held PermissionRequest's reply (C05, C06, C07): allow, echoing the
 * input (Claude Code ignores an allow without it for plans; spike,
 * 2026-10-03), optionally with updates to apply: a plan's mode switch (for
 * this session only), or a prompt option's, which are Claude Code's own
 * suggestions sent back unchanged (prompt-options.ts). Or deny with a
 * message Claude reads.
 */
export function permissionReply(
  d: { behavior: 'allow'; updatedInput: Record<string, unknown>; mode?: string; updates?: PermissionUpdate[] } | { behavior: 'deny'; message: string },
): Record<string, unknown> {
  const updates = d.behavior === 'allow'
    ? [...(d.mode ? [{ type: 'setMode', mode: d.mode, destination: 'session' }] : []), ...(d.updates ?? [])]
    : []
  const decision = d.behavior === 'allow'
    ? { behavior: 'allow', updatedInput: d.updatedInput, ...(updates.length > 0 ? { updatedPermissions: updates } : {}) }
    : { behavior: 'deny', message: d.message }
  return { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision } }
}

function parseObject(s: string): Record<string, unknown> | null {

  try {
    const v: unknown = JSON.parse(s)
    return isObject(v) ? v : null
  } catch { return null }
}

/**
 * Whether the relay's input preview shows this input. A whole preview must
 * be the same input exactly; one cut short (JSON spaced differently, its
 * end cut off) must be a prefix of it, compared without whitespace.
 */
export function previewMatches(preview: string, input: Record<string, unknown>): boolean {
  // A whole preview: the same input exactly (spacing inside strings counts).
  const parsed = parseObject(preview)
  if (parsed) return JSON.stringify(parsed) === JSON.stringify(input)
  // Cut short: a prefix, compared without whitespace (its spacing differs).
  const squash = (s: string) => s.replace(/\s+/g, '')
  const p = squash(preview).replace(/(\.\.\.|…)$/, '')
  return p.length >= 8 && squash(JSON.stringify(input)).startsWith(p)
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

export function firstLine(s: string): string {
  return s.trim().split(/\r?\n/, 1)[0] ?? ''
}

export function clip(s: string): string {
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
    case 'ExitPlanMode': s = 'Present the plan'; break
    case 'EnterPlanMode': s = 'Switch to plan mode'; break

    case 'SubagentHandback': s = 'Report back'; break
    default: {
      // MCP tools are mcp__<server>__<tool>.
      const mcp = /^mcp__(.+?)__(.+)$/.exec(tool)
      s = mcp ? `${mcp[1]}: ${mcp[2]}` : tool
    }
  }
  return clip(s.trim())
}
