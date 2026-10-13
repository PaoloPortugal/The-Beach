// One running Claude session (NOTES.md -> S02): what its hooks, bridge and
// transcript say, turned into the session's events, and the world's answers,
// stops and messages sent back. The provider (index.ts) launches it.
import fs from 'node:fs'
import path from 'node:path'
import type { ProviderSession, SessionHost } from '../../provider.ts'
import { CommandError } from '../../provider.ts'
import type { Choice, History, Project, SessionEvent } from '../../protocol.ts'
import { effortChoice, modelChoice } from './launch-options.ts'
import { HistoryLog } from '../../history.ts'
import type { Log } from '../../log.ts'
import type { BridgeLink } from './bridge-server.ts'
import type { HookLink, HookPayload } from './hook-server.ts'
import { TranscriptFollower, type TranscriptSignal } from './transcript.ts'
import { TranscriptHooks, type Fed } from './transcript-hooks.ts'
import {
  HookTranslator, MAIN, PLAN_TOOL, QUESTION_TOOL, permissionReply, questionReply, unwrapChannel, type RelayedPermission,
} from './hooks.ts'
import { hasReply, NO_TITLES, pickTitle, readConversation, readTitles, type Conversation, type Titles } from './store.ts'
import { statusFiguresIn, UsageCounter } from './usage.ts'
import { launcherGone } from '../../launch/launcher.ts'

/**
 * How long a relayed permission prompt waits for its tool call's
 * PreToolUse and PermissionRequest hooks, which come on other connections
 * (PreToolUse about 100 ms before the relay, PermissionRequest a few ms
 * after it, in the S02 spike). It's shown as soon as both came; after this
 * long, with what's known by then: without its options (C05), or without
 * a tool call, as the orchestrator's. Generous, since a hook later than
 * this means a prompt shown without the options the terminal has, while a
 * hook that never comes (hooks blocked) only delays the card by this much.
 */
export const PERMISSION_MATCH_MS = 1000

/**
 * How long after the first reply ends the transcript must exist. With
 * saving on it's written live (it exists by the Stop hook); with
 * CLAUDE_CODE_SKIP_PROMPT_HISTORY the hooks still name a path, but nothing
 * is ever written there (probed with 2.1.284, 2026-09-29).
 */
export const TRANSCRIPT_CHECK_MS = 1000

/** The notice when Claude Code isn't saving transcripts (user's wording, NOTES.md -> S02). */
export const TRANSCRIPTS_OFF = {
  code: 'transcripts_off',
  message: 'Transcript saving is off in Claude Code, so some features may not work as intended. Turning it on is recommended.',
}

export { HISTORY_MAX } from '../../history.ts'

/**
 * A world message sent while the orchestrator is idle makes Claude Code fire
 * UserPromptSubmit at once (well under a second in the spike). If no hook at
 * all arrives within this long, hooks aren't reaching us: most likely the
 * user's settings allow only other HTTP hook URLs (allowedHttpHookUrls,
 * possibly company-managed). Chat still works through the channel.
 */
export const HOOKS_CHECK_MS = 10_000

/** The notice when hooks don't arrive (English fallback; Godot shows its own text). */
export const HOOKS_UNAVAILABLE = {
  code: 'hooks_unavailable',
  message: 'Claude Code isn\'t sending this session\'s activity to the world (a setting such as allowedHttpHookUrls may be blocking it). Chat still works; answer prompts and questions in the terminal.',
}

/** How often a starting session checks that its launcher still runs. */
export const LAUNCHER_CHECK_MS = 1000

/**
 * Until the bridge connects, Claude Code is showing its startup dialogs (the
 * development-channel confirmation at every launch; NOTES.md -> S02 ->
 * Starting up), so the world says so. Sent in the create/resume reply.
 */
export const CONFIRM_IN_TERMINAL = {
  code: 'confirm_in_terminal',
  message: 'Confirm in the Claude Code terminal to start this session.',
}

/** The notice when /clear starts a new conversation in the session (the chat window is cleared with it). */
export const CONVERSATION_CLEARED = {
  code: 'conversation_cleared',
  message: 'A new conversation started in this session (/clear). The earlier one can be brought back with /resume in the terminal.',
}

/** The notice when /resume in the terminal switches the session to an earlier conversation. */
export const CONVERSATION_RESUMED = {
  code: 'conversation_resumed',
  message: 'This session switched to an earlier conversation (/resume). The chat now shows that conversation.',
}

/** The notice when the conversation moved to another Claude Code session (user's wording, 2026-10-01). */
export const CONVERSATION_MOVED = {
  code: 'conversation_moved',
  message: 'This conversation moved to another Claude Code session. Continue it in the terminal; the world can no longer send to it.',
}

/**
 * The notice for a session taken over after a restart whose hooks can't
 * reach the game any more (their port was taken while it was closed;
 * NOTES.md -> S07). The user's wording, 2026-10-13: deliberately general,
 * so it never goes out of date; what works is in NOTES and the guide.
 */
export const REATTACHED_LIMITED = {
  code: 'reattached_limited',
  message: 'This session started before the game restarted, so some features may not work fully.',
}

/** Why the world can't stop a session in the limited mode: the stop lands through its hooks. */
export const LIMITED_STOP_ERROR = 'This session can only be stopped in its terminal (Esc).'

/** Why the world can't send to a conversation that moved. */
export const MOVED_ERROR = 'This conversation moved to another Claude Code session; continue it in the terminal.'
/** Why the world can't send while the bridge isn't connected. */
export const UNREACHABLE_ERROR = 'The world can\'t reach this conversation right now (its channel to Claude Code is closed); use the terminal.'

/** Claude Code's session ids are UUIDs. */
const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** What a stopped tool call tells Claude, and what the terminal shows. */
export const STOP_REASON = 'The user stopped this from the app.'

/** What Claude is told when the world sends a plan back without a note (C07). */
export const KEEP_PLANNING = 'The user wants to keep planning. Ask them what to change.'

/** Why the world can't answer a prompt with an option when its hook isn't held (C05). */
export const NO_OPTION_ERROR = 'This prompt can\'t be answered that way right now. Answer Yes or No, or answer in the terminal.'

/**
 * The PreToolUse reply that stops a tool call and the agent's turn.
 * `continue: false` alone still let the call run (spike run 1), so it's
 * denied too.
 */
const STOP_REPLY = {
  continue: false, stopReason: STOP_REASON,
  hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'deny', permissionDecisionReason: STOP_REASON },
}

/** Everything the launched claude and our side share for one session. */
export interface Launch {
  runDir: string
  nativeId: string
}

export class ClaudeSession implements ProviderSession {
  readonly startupNotice = CONFIRM_IN_TERMINAL
  readonly host: SessionHost
  readonly launch: Launch
  link: BridgeLink | null = null
  hookLink: HookLink | null = null
  /**
   * Claude's id for the conversation the world follows (native_id). It
   * changes when /clear starts a new conversation in the same process.
   */
  nativeId: string
  /** Called when nativeId changes, so the provider knows which ids are live. */
  onNativeId: ((from: string, to: string) => void) | null = null
  /** The conversation went on in this other session, out of the world's reach. */
  private movedTo: string | null = null
  /** The project's transcript folder, from the first hook: a new conversation must be in the same one. */
  private transcriptDir: string | null = null
  private readonly project: Project
  /** What the conversation the world follows is called so far, and the title last announced. */
  private titles: Titles
  private shownTitle: string | null = null
  private readonly log: Log
  private readonly cleanup: () => void
  private readonly startupTimeoutMs: number
  private launchedAt = 0
  private startupTimer: NodeJS.Timeout | null = null
  private launcherCheck: NodeJS.Timeout | null = null
  private disposed = false
  private readonly translator: HookTranslator
  /** Fills in what hooks miss: Esc and a "No" in the terminal. */
  private readonly transcript = new TranscriptFollower((s) => this.onTranscript(s))
  /**
   * The chat so far, as the world saw it through the hooks: every message
   * since launch, so the same whether transcripts are on or off.
   */
  private readonly chat: HistoryLog
  /**
   * Taken back with its hooks out of reach (S07's limited mode): seen from
   * its transcript alone, read as the hooks it stands for.
   */
  private limited: TranscriptHooks | null = null
  /** Whether any hook has arrived yet. */
  private hooksSeen = false
  /** Checking that hooks arrive (once, after the first world message sent while idle). */
  private hooksCheck: NodeJS.Timeout | null = null
  private hooksChecked = false
  private readonly hooksCheckMs: number
  /** Whether the transcript has been checked for (once, after the first reply). */
  private transcriptChecked = false
  /**
   * A stop from the world: the agents that were busy when it was asked,
   * each stopped at its next tool call. One that goes idle or finishes on
   * its own first is dropped, so a later turn is never stopped by it.
   */
  private readonly stopping = new Set<string>()
  /**
   * Agents already stopped. Calls they had already issued in the same batch
   * still arrive (seen with claude -p, 2.1.284) and are stopped too, until a
   * new turn starts.
   */
  private readonly halted = new Set<string>()
  /** Held question hooks, by question id: call with the hook's reply (none = no decision). */
  private readonly held = new Map<string, (reply?: Record<string, unknown>) => void>()
  /** Held plan hooks, by plan id (C07). */
  private readonly heldPlans = new Map<string, (reply?: Record<string, unknown>) => void>()
  /**
   * Held hooks of prompts with options, by tool call (C05). Only an allow
   * with an option answers one; any other answer comes through the relay
   * or the terminal, and the hook is let go when the call ends.
   */
  private readonly heldPrompts = new Map<string, (reply?: Record<string, unknown>) => void>()
  /**
   * Relayed prompts waiting for their tool call's hooks, by request id
   * (see PERMISSION_MATCH_MS); tried again after each of those hooks.
   */
  private readonly waitingRelays = new Map<string, { relay: RelayedPermission; timer: NodeJS.Timeout }>()

  /** A first message to send once the session is up (session.create's prompt). */
  private prompt: string | null
  /** Token usage of the conversation the world follows (C08). */
  private readonly usage = new UsageCounter()
  /**
   * The session's model and effort level (C12), null until known; sent once
   * up, then on change. The model from SessionStart, the status line and
   * PostModelSwitch, as the terminal shows it, not from the transcript: a
   * reply's model can differ
   * (plan mode upgrades Haiku to Sonnet for its turns, checked on 2.1.296).
   */
  private model: Choice | null = null
  private effort: Choice | null = null
  /** The usage last sent, so only changes go out. */
  private usageSent = 'null'

  constructor(host: SessionHost, launch: Launch, project: Project, titles: Titles, log: Log,
    cleanup: () => void, startupTimeoutMs: number, history: History = { messages: [], tools: [] }, prompt?: string,
    hooksCheckMs = HOOKS_CHECK_MS, usage?: UsageCounter) {
    this.host = host
    this.launch = launch
    this.nativeId = launch.nativeId
    this.project = project
    this.titles = { ...titles }
    this.log = log
    this.cleanup = cleanup
    this.startupTimeoutMs = startupTimeoutMs
    this.translator = new HookTranslator(project.path)
    this.chat = new HistoryLog(history)
    this.prompt = prompt ?? null
    this.hooksCheckMs = hooksCheckMs
    if (usage) this.usage.load(usage)
  }

  bridgeHandlers() {
    return {
      onReady: () => {
        this.onReady()
        // A session taken over after a restart (already up): its bridge is
        // back, and its closing now says when Claude Code exits.
        if (!this.startupTimer) this.stopLauncherCheck()
        this.flushPrompt()
      },
      onPermissionRequest: (p: RelayedPermission) => this.onPermissionRequest(p),
      onClose: () => this.onGone('the bridge closed'),
    }
  }

  /** Called once the terminal is open: the user now answers the startup prompts. */
  startWaiting() {
    this.launchedAt = Date.now()
    this.startupTimer = setTimeout(() => this.onGone('it never came up'), this.startupTimeoutMs)
    this.startupTimer.unref()
    // Claude Code exiting at a startup prompt (folder trust declined, the
    // channel refused) or its terminal closed: nothing else would tell us.
    this.launcherCheck = setInterval(() => {
      if (launcherGone(this.launch.runDir)) this.onGone('it closed before it came up')
    }, LAUNCHER_CHECK_MS)
    this.launcherCheck.unref()
  }

  private onReady() {
    if (this.disposed || this.host.ended) return
    if (!this.startupTimer) return
    clearTimeout(this.startupTimer)
    this.startupTimer = null
    this.stopLauncherCheck()
    // Timing for NOTES.md -> S02 -> Starting up (checkpoint 1 measurements).
    this.log.info(`session ${this.host.id} came up ${Date.now() - this.launchedAt} ms after launch`)
    this.announce()
    // A resumed conversation's usage so far.
    this.sendUsage()
    this.flushPrompt()
  }

  private announce(startedAt?: string) {
    const { state, reason } = this.translator.mainState()
    this.host.announce({
      native_id: this.nativeId,
      project: this.project,
      title: this.shownTitle = pickTitle(this.titles),
      // A stop from the world lands at the next tool call (NOTES.md -> S02).
      // Without hooks there are no questions, plans, mode or stop (S07).
      capabilities: this.limited ? { usage: {}, model_info: {} } : {
        questions: {}, interrupt: { immediate: false }, permission_modes: {}, plans: {}, usage: {}, model_info: {},
      },
      extensions: [],
      model: this.model,
      effort: this.effort,
      agents: [{ agent: MAIN, role: 'orchestrator', parent: null, name: 'Claude', state, reason }],
      ...(startedAt ? { started_at: startedAt } : {}),
    })
  }

  /**
   * Takes over a session an earlier sidecar launched, still running (S07):
   * announced at once in the state Claude Code reports (`claude agents
   * --json`) until the next hook says otherwise, its transcript followed
   * from now on, and its launcher watched until the bridge reconnects (from
   * then on the bridge closing says Claude Code exited). `limited`: its
   * hooks go to a port the game no longer has (taken while it was closed),
   * so it runs with less, and says so; no hooks check either. It is then
   * seen from its transcript alone: a busy session stays working until its
   * transcript shows the turn's end.
   */
  restored(o: { state: 'working' | 'waiting' | 'idle'; reason: string | null; startedAt: string; transcript: string | null; limited: boolean }) {
    this.translator.assume(o.state, o.reason)
    if (o.limited) {
      this.hooksChecked = true
      this.limited = new TranscriptHooks()
      this.translator.withoutPromptHooks()
      this.transcript.followAll()
    }
    if (o.transcript) {
      this.transcriptDir = path.dirname(o.transcript)
      this.transcript.follow(o.transcript)
    }
    this.announce(o.startedAt)
    this.sendUsage()
    if (o.limited) this.host.emit({ type: 'session.notice', notice: REATTACHED_LIMITED })
    this.launcherCheck = setInterval(() => {
      if (launcherGone(this.launch.runDir)) this.onGone('its terminal closed')
    }, LAUNCHER_CHECK_MS)
    this.launcherCheck.unref()
  }

  /** The world's first message, sent once the session is up and its bridge connected. */
  private flushPrompt() {
    if (this.prompt && !this.startupTimer && this.link?.send({ type: 'chat', text: this.prompt })) this.prompt = null
  }

  /**
   * One hook from this session's Claude Code. Reports only, except a
   * question, whose hook is held until the user answers in either place.
   */
  onHook(p: HookPayload, gone: AbortSignal): Record<string, unknown> | void | Promise<Record<string, unknown> | void> {
    if (this.disposed || this.host.ended) return
    // Comes through the relay (a command hook), not as one of the HTTP
    // hooks the checks below are about.
    if (p.hook_event_name === 'SessionStart') return this.sessionStarted(p)
    // Limited (S07): its HTTP hooks go to the program on its old port, never
    // here, so one that comes here with its token is that program's: dropped.
    if (this.limited) return
    // Can come at startup (a resume restoring the model), before the
    // session is up: it says nothing about that.
    if (p.hook_event_name === 'PostModelSwitch') return this.noteModel(modelChoice(p.to_model))
    this.hooksSeen = true
    // Hooks only fire once Claude Code is past its startup dialogs, so a
    // hook arriving before the bridge's ready also means the session is up.
    if (this.startupTimer) this.onReady()
    if (!this.ownConversation(p)) return
    this.transcript.follow(p.transcript_path)
    if (p.hook_event_name === 'Stop' && !this.transcriptChecked) this.checkTranscript(p.transcript_path)
    this.emitAll(this.translator.noteMode(p))
    // The orchestrator's effort level (a subagent may run at its own).
    if (p.agent_id === undefined) this.noteEffort(effortChoice((p.effort as { level?: unknown } | undefined)?.level))
    if (p.hook_event_name === 'PermissionRequest') {
      if (p.tool_name === QUESTION_TOOL) return this.holdQuestion(p, gone)
      if (p.tool_name === PLAN_TOOL) return this.holdPlan(p, gone)
      const held = this.holdPrompt(p, gone)
      this.retryRelays()
      return held
    }
    // A new turn: agents stopped in the last one may work again.
    if (p.hook_event_name === 'UserPromptSubmit') this.halted.clear()
    const agent = this.translator.agentOf(p)
    const call = p.hook_event_name === 'PreToolUse' && agent !== null
    // Another call from the same batch as a stopped one: stopped too, and
    // not shown (it never runs, and the agent's stop is already shown).
    if (call && this.halted.has(agent)) return STOP_REPLY
    this.emitAll(this.translator.translate(p))
    let reply: Record<string, unknown> | undefined
    if (call && this.stopping.has(agent)) {
      this.stopping.delete(agent)
      this.halted.add(agent)
      reply = STOP_REPLY
      this.emitAll(this.translator.stopped(p))
    }
    for (const a of [...this.stopping]) if (!this.translator.isBusy(a)) this.stopping.delete(a)
    if (p.hook_event_name === 'PreToolUse') this.retryRelays()
    return reply
  }

  /**
   * SessionStart, relayed: Claude Code says at once that /clear started a
   * new conversation or /resume switched to an earlier one, with its id and
   * transcript (NOTES.md -> S02 -> Following the conversation). Our own
   * launch (startup, or --resume with the same id) and compaction change
   * nothing; the settings only ask for clear and resume anyway.
   */
  private sessionStarted(p: HookPayload): void {
    // The model (C12), when Claude Code includes it: the process's, whichever
    // conversation started. A launch's --model fires no PostModelSwitch.
    this.noteModel(modelChoice(p.model))
    const source = p.source
    if (source !== 'clear' && source !== 'resume') return
    // Not up yet: nothing to switch (the fallback below still would).
    if (this.startupTimer || p.session_id === this.nativeId || !this.acceptNew(p)) return
    const file = p.transcript_path as string
    // /resume: the resumed conversation's chat, all of it (no prompt has
    // woken it yet). /clear: an empty chat.
    this.switchTo(p.session_id as string, file, source === 'resume' ? readConversation(file) : null)
    this.transcript.follow(file)
  }

  /**
   * Whether a hook belongs to the conversation the world follows. A hook
   * from another conversation of this session (our settings, so our token)
   * is either /clear or /resume, a new or an earlier conversation in the
   * same process, which the world follows (same project, same island;
   * user's decisions), or a conversation that moved elsewhere (agent view,
   * which we turn off), which it can't: those hooks are ignored, so the
   * terminal handles everything. SessionStart normally reports the switch
   * first; if its relay failed, the new conversation's first hook does.
   */
  private ownConversation(p: HookPayload): boolean {
    const id = p.session_id
    const file = p.transcript_path
    if (id === undefined || id === this.nativeId) {
      if (this.transcriptDir === null && typeof file === 'string' && path.isAbsolute(file)) this.transcriptDir = path.dirname(file)
      return true
    }
    if (!this.acceptNew(p)) return false
    // The fallback: a transcript with a reply from Claude is an earlier
    // conversation (/resume); one /clear started has none yet.
    this.switchTo(id as string, file as string, hasReply(file as string) ? earlierChat(file as string, p) : null)
    return true
  }

  /**
   * Whether a hook from another conversation of this session is one the
   * world can follow: not moved away, a real session id, and a transcript
   * in this project's folder.
   */
  private acceptNew(p: HookPayload): boolean {
    const id = p.session_id
    const file = p.transcript_path
    // A move writes continued-in to our transcript before the new session
    // starts; read it now in case the next poll hasn't come yet.
    this.transcript.poll()
    if (this.movedTo !== null || typeof id !== 'string' || !SESSION_ID.test(id)) return false
    // Limited (S07): the program on its old port has its token too, so a
    // switch is followed only to the project's own folder, known by then.
    if (this.limited && this.transcriptDir === null) {
      this.log.warn(`session ${this.host.id}: ignored a switch of conversation (limited, its folder unknown)`)
      return false
    }
    // A transcript in another folder isn't this project's (never seen).
    if (typeof file !== 'string' || !path.isAbsolute(file) ||
        (this.transcriptDir !== null && path.dirname(file) !== this.transcriptDir)) {
      this.log.warn(`session ${this.host.id}: ignored a hook from another project's conversation`)
      return false
    }
    return true
  }

  /**
   * The world now follows conversation `id`. `resumed` is its chat and
   * usage after /resume, which become the history and the counts; null
   * after /clear, when the history empties and the counts start over, so
   * the world's chat window clears too (user's decisions, 2026-10-01; the
   * old conversation stays resumable).
   */
  private switchTo(id: string, file: string, resumed: Conversation | null) {
    const from = this.nativeId
    this.nativeId = id
    this.transcriptDir ??= path.dirname(file)
    if (resumed) this.usage.load(resumed.usage)
    else this.usage.reset()
    if (resumed) {
      this.chat.replace(resumed.history)
      this.log.info(`session ${this.host.id}: it switched to an earlier conversation (/resume)`)
    } else {
      this.chat.replace({ messages: [], tools: [] })
      this.log.info(`session ${this.host.id}: a new conversation started in it (/clear)`)
    }
    // Its own name: an earlier conversation's from its transcript, none yet for a new one.
    this.titles = resumed ? readTitles(file) : { ...NO_TITLES }
    const title = pickTitle(this.titles)
    const renamed = title !== this.shownTitle
    this.shownTitle = title
    // After the history: the world reloads it on session.updated.
    this.host.emit({ type: 'session.updated', native_id: id, ...(renamed ? { title } : {}) })
    this.host.emit({ type: 'session.notice', notice: resumed ? CONVERSATION_RESUMED : CONVERSATION_CLEARED })
    this.sendUsage()
    this.onNativeId?.(from, id)
  }

  /** The conversation went on in another session (a continued-in in its transcript). */
  private onMoved(to: string) {
    if (this.movedTo !== null || to === this.nativeId) return
    this.movedTo = to
    this.log.info(`session ${this.host.id}: its conversation moved to another Claude Code session`)
    this.host.emit({ type: 'session.notice', notice: CONVERSATION_MOVED })
  }

  /** Throws unless the world can send to the conversation it follows. */
  private reachable(): BridgeLink {
    if (this.movedTo !== null) throw new CommandError('provider_error', MOVED_ERROR)
    if (!this.link?.connected) throw new CommandError('provider_error', UNREACHABLE_ERROR)
    return this.link
  }

  private holdQuestion(p: HookPayload, gone: AbortSignal): void | Promise<Record<string, unknown> | void> {
    const asked = this.translator.questionAsked(p)
    if (!asked) return
    return new Promise((resolve) => {
      this.held.set(asked.question, resolve)
      // Claude Code stopped waiting (the terminal's answer comes as a
      // PostToolUse first, which releases the hook itself).
      gone.addEventListener('abort', () => {
        if (this.held.delete(asked.question)) this.emitAll(this.translator.questionGone(asked.question))
      })
      this.emitAll(asked.events)
    })
  }

  private holdPlan(p: HookPayload, gone: AbortSignal): void | Promise<Record<string, unknown> | void> {
    const asked = this.translator.planAsked(p)
    if (!asked) return
    return new Promise((resolve) => {
      this.heldPlans.set(asked.plan, resolve)
      // Answered in the terminal, the held hook stays open (spike,
      // 2026-10-03): its PostToolUse (or the transcript) resolves the plan
      // and lets go of the hook. This is only Claude Code exiting.
      gone.addEventListener('abort', () => {
        if (this.heldPlans.delete(asked.plan)) this.emitAll(this.translator.planGone(asked.plan))
      })
      this.emitAll(asked.events)
    })
  }

  /**
   * Any other prompt's hook brings its options (C05). Held while it has
   * some, in case the world allows it one of those ways; else answered at
   * once with no decision, so the terminal asks as usual.
   */
  private holdPrompt(p: HookPayload, gone: AbortSignal): void | Promise<Record<string, unknown> | void> {
    const call = this.translator.promptHooked(p)
    if (!call || this.heldPrompts.has(call)) return
    return new Promise((resolve) => {
      this.heldPrompts.set(call, resolve)
      gone.addEventListener('abort', () => { this.heldPrompts.delete(call) })
    })
  }

  /** Tells the world if Claude Code isn't saving this session's transcript. */
  private checkTranscript(file: unknown) {
    if (typeof file !== 'string') return
    this.transcriptChecked = true
    const t = setTimeout(() => {
      if (this.disposed || this.host.ended || fs.existsSync(file)) return
      this.log.info(`session ${this.host.id}: no transcript is being saved`)
      this.host.emit({ type: 'session.notice', notice: TRANSCRIPTS_OFF })
    }, TRANSCRIPT_CHECK_MS)
    t.unref()
  }

  private onTranscript(s: TranscriptSignal) {
    if (this.disposed || this.host.ended) return
    if (s.kind === 'continued') return this.onMoved(s.sessionId)
    if (s.kind === 'title') return this.retitle({ ...this.titles, ...s.titles })
    if (s.kind === 'usage') {
      if (this.usage.add(s.call)) this.sendUsage()
      return
    }
    if (s.kind === 'entry' || s.kind === 'subagent') {
      if (!this.limited) return
      const fed = s.kind === 'entry' ? this.limited.entry(s.entry, s.agent) : this.limited.subagent(s.agent, s.type, s.toolUseId, s.background)
      return this.feed(fed)
    }
    this.emitAll(s.kind === 'rejected' ? this.translator.rejectedInTerminal(s.toolUseId) : this.translator.interruptedByUser())
  }

  /** The limited mode's hooks, read from the transcript: reports only, nothing to answer or hold. */
  private feed(fed: Fed[]) {
    for (const f of fed) {
      if ('denied' in f) {
        this.emitAll(this.translator.rejectedInTerminal(f.denied))
        continue
      }
      const p = f.hook
      this.emitAll(this.translator.translate(p))
      // A relayed prompt waiting for its call can be shown now.
      if (p.hook_event_name === 'PreToolUse') this.retryRelays()
    }
  }

  /**
   * Claude Code shows a permission prompt, relayed by the bridge. Shown
   * once its tool call's hooks came, which may be before or after it.
   */
  private onPermissionRequest(p: RelayedPermission) {
    if (this.disposed || this.host.ended || this.waitingRelays.has(p.request_id)) return
    const events = this.translator.permissionRequested(p)
    if (events) return this.emitAll(events)
    const timer = setTimeout(() => {
      this.waitingRelays.delete(p.request_id)
      if (!this.disposed && !this.host.ended) this.emitAll(this.translator.permissionRequested(p, true) ?? [])
    }, PERMISSION_MATCH_MS)
    timer.unref()
    this.waitingRelays.set(p.request_id, { relay: p, timer })
  }

  /** Shows the waiting relayed prompts whose tool call's hooks have now come. */
  private retryRelays() {
    for (const [id, { relay, timer }] of [...this.waitingRelays]) {
      const events = this.translator.permissionRequested(relay)
      if (!events) continue
      clearTimeout(timer)
      this.waitingRelays.delete(id)
      this.emitAll(events)
    }
  }

  /**
   * Claude Code's status line input (C08), relayed: the context window's
   * size and fill, and the account's usage limits. Untrusted, and only
   * taken for the conversation the world follows, once the session is up.
   */
  onStatus(p: Record<string, unknown>): void {
    if (this.disposed || this.host.ended || this.startupTimer) return
    const figures = statusFiguresIn(p)
    if (figures.sessionId !== this.nativeId) return
    if (this.usage.status(figures)) this.sendUsage()
    this.noteModel(modelChoice((p.model as { id?: unknown } | undefined)?.id))
    this.noteEffort(effortChoice((p.effort as { level?: unknown } | undefined)?.level))
  }

  /** A model from any source (C12): kept, and sent if the session is up and it changed. */
  private noteModel(model: Choice | null): void {
    if (this.disposed || this.host.ended || !model || model.id === this.model?.id) return
    this.model = model
    if (!this.startupTimer) this.host.emit({ type: 'session.updated', model })
  }

  private noteEffort(effort: Choice | null): void {
    if (this.disposed || this.host.ended || !effort || effort.id === this.effort?.id) return
    this.effort = effort
    if (!this.startupTimer) this.host.emit({ type: 'session.updated', effort })
  }

  /** Sends the usage figures if they changed since last sent. */
  private sendUsage() {
    if (this.startupTimer) return
    const usage = this.usage.get()
    const json = JSON.stringify(usage)
    if (!usage || json === this.usageSent) return
    if (this.host.emit({ type: 'usage.updated', usage })) {
      this.usageSent = json
      this.chat.remember({ type: 'usage.updated', usage })
    }
  }

  private emitAll(events: SessionEvent[]) {
    let turn = false
    for (const event of events) {
      // The user's message starts a new turn (C08); Claude Code's injected
      // prompts aren't user messages, so they stay in the turn.
      if (event.type === 'message.started' && event.role === 'user' && event.agent === MAIN) {
        this.usage.newTurn(event.message)
        turn = true
      }
      if (this.host.emit(event)) this.remember(event)
      // Answered or dismissed in the terminal: let go of the held hook
      // (Claude Code no longer waits on it; NOTES.md -> S02).
      if (event.type === 'question.resolved' && event.by === 'external') this.release(event.question)
      if (event.type === 'plan.resolved' && event.by === 'external') this.releasePlan(event.plan)
      // The call ended (ran, denied or stopped): its prompt's hook is moot.
      if (event.type === 'tool.finished') this.releasePrompt(event.tool_call)
    }
    // After the message is complete, so the history can note its turn's tokens.
    if (turn) this.sendUsage()
  }

  /** New titles; the world hears when the one shown changes (only once the session is up). */
  private retitle(titles: Titles) {
    this.titles = titles
    const title = pickTitle(titles)
    if (title === this.shownTitle || this.startupTimer) return
    this.shownTitle = title
    this.host.emit({ type: 'session.updated', title })
  }

  /** Keeps completed chat messages and tool calls for session.get_history. */
  private remember(event: SessionEvent) {
    const m = this.chat.remember(event)
    if (m?.role === 'user' && m.agent === MAIN && !this.titles.prompt) this.retitle({ ...this.titles, prompt: m.text })
  }

  private release(question: string, reply?: Record<string, unknown>) {
    const resolve = this.held.get(question)
    this.held.delete(question)
    resolve?.(reply)
  }

  private releasePlan(plan: string, reply?: Record<string, unknown>) {
    const resolve = this.heldPlans.get(plan)
    this.heldPlans.delete(plan)
    resolve?.(reply)
  }

  private releasePrompt(toolCall: string, reply?: Record<string, unknown>) {
    const resolve = this.heldPrompts.get(toolCall)
    this.heldPrompts.delete(toolCall)
    resolve?.(reply)
  }

  private stopLauncherCheck() {
    if (this.launcherCheck) clearInterval(this.launcherCheck)
    this.launcherCheck = null
  }

  /** Claude Code exited, or never came up. */
  private onGone(why: string) {
    if (this.disposed) return
    this.log.info(`session ${this.host.id} is gone: ${why}`)
    this.dispose()
    this.host.end('exited')
  }

  dispose() {
    if (this.disposed) return
    this.disposed = true
    if (this.startupTimer) clearTimeout(this.startupTimer)
    this.stopLauncherCheck()
    if (this.hooksCheck) clearTimeout(this.hooksCheck)
    for (const { timer } of this.waitingRelays.values()) clearTimeout(timer)
    this.waitingRelays.clear()
    this.link?.unregister()
    this.hookLink?.unregister()
    this.transcript.stop()
    for (const q of [...this.held.keys()]) this.release(q)
    for (const q of [...this.heldPlans.keys()]) this.releasePlan(q)
    for (const q of [...this.heldPrompts.keys()]) this.releasePrompt(q)
    this.cleanup()
  }

  async sendMessage(text: string): Promise<void> {
    if (!this.reachable().send({ type: 'chat', text })) throw new CommandError('provider_error', UNREACHABLE_ERROR)
    if (!this.hooksSeen && !this.hooksChecked && !this.translator.busy()) {
      this.hooksChecked = true
      this.hooksCheck = setTimeout(() => {
        if (this.disposed || this.host.ended || this.hooksSeen) return
        this.log.warn(`session ${this.host.id}: no hooks arrived after a world message`)
        this.host.emit({ type: 'session.notice', notice: HOOKS_UNAVAILABLE })
      }, this.hooksCheckMs)
      this.hooksCheck.unref()
    }
  }
  /**
   * The user answered a prompt in the world. The verdict goes down the
   * bridge and closes the terminal's dialog; nothing is allowed any other
   * way (NOTES.md -> Security rules). An allow with an option (C05)
   * answers the prompt's held hook instead, with the option's updates
   * (Claude Code's own suggestions, or the switch to auto mode); Claude
   * Code then closes the terminal's dialog and the relayed prompt itself
   * (spike, 2026-10-03).
   */
  async respondPermission(permission: string, decision: 'allow' | 'deny', note?: string, option?: string): Promise<void> {
    const link = this.reachable()
    if (option !== undefined) {
      const chosen = this.translator.promptOption(permission, option)
      if (!chosen || !this.heldPrompts.has(chosen.toolCall)) throw new CommandError('provider_error', NO_OPTION_ERROR)
      this.releasePrompt(chosen.toolCall, permissionReply({ behavior: 'allow', updatedInput: chosen.input, updates: chosen.updates }))
    } else if (!link.send({ type: 'verdict', request_id: permission, behavior: decision })) {
      throw new CommandError('provider_error', UNREACHABLE_ERROR)
    }
    this.emitAll(this.translator.permissionAnswered(permission, decision))
    // The channel's verdict carries no message, so a note follows it as the
    // user's next chat message (it's their own words; Claude reads it once
    // the answered call is done or denied).
    if (note?.trim()) link.send({ type: 'chat', text: note })
  }
  /** The user answered a question in the world: the held hook gets the answer. */
  async answerQuestion(question: string, answer: { answers: string[][] } | { response: string }): Promise<void> {
    const input = this.translator.questionInput(question)
    if (!input || !this.held.has(question)) {
      throw new CommandError('provider_error', 'The question is no longer waiting for an answer.')
    }
    let reply: Record<string, unknown>
    try { reply = questionReply(input, answer) } catch (e) {
      throw new CommandError('invalid_message', (e as Error).message)
    }
    this.release(question, reply)
    this.emitAll(this.translator.questionAnswered(question, 'response' in answer))
  }

  /**
   * The user answered a plan in the world: the held hook gets the answer.
   * Approving echoes the plan back (without it Claude Code ignores the
   * reply; spike, 2026-10-03) and switches to the chosen mode; sending it
   * back denies the call with the user's note, and Claude plans again.
   */
  async answerPlan(plan: string, answer: { approve: true; mode: string } | { approve: false; note?: string }): Promise<void> {
    const input = this.translator.planInput(plan)
    if (!input || !this.heldPlans.has(plan)) {
      throw new CommandError('provider_error', 'The plan is no longer waiting for an answer.')
    }
    this.releasePlan(plan, answer.approve
      ? permissionReply({ behavior: 'allow', updatedInput: input, mode: answer.mode })
      : permissionReply({ behavior: 'deny', message: answer.note?.trim() || KEEP_PLANNING }))
    this.emitAll(this.translator.planAnswered(plan, answer.approve))
  }

  /**
   * Stop from the world: the busy agents stop at their next tool call (the
   * current reply or command finishes first). Pending permission prompts
   * and questions are declined, or they'd block the stop; that never
   * allows anything.
   */
  async interrupt(): Promise<void> {
    // The stop lands through this conversation's hooks, which a moved one no longer sends.
    if (this.movedTo !== null) throw new CommandError('provider_error', MOVED_ERROR)
    if (this.limited) throw new CommandError('not_supported', LIMITED_STOP_ERROR)
    for (const a of this.translator.busyAgents()) this.stopping.add(a)
    // Prompts still waiting for their hooks are shown now, to be declined with the rest.
    for (const [id, { relay, timer }] of [...this.waitingRelays]) {
      clearTimeout(timer)
      this.waitingRelays.delete(id)
      this.emitAll(this.translator.permissionRequested(relay, true) ?? [])
    }
    for (const permission of this.translator.pendingPermissions()) {
      if (this.link?.send({ type: 'verdict', request_id: permission, behavior: 'deny' })) {
        this.emitAll(this.translator.permissionAnswered(permission, 'deny'))
      }
    }
    for (const question of [...this.held.keys()]) {
      this.release(question, questionReply({}, { response: STOP_REASON }))
      this.emitAll(this.translator.questionAnswered(question, true))
    }
    for (const plan of [...this.heldPlans.keys()]) {
      this.releasePlan(plan, permissionReply({ behavior: 'deny', message: STOP_REASON }))
      this.emitAll(this.translator.planAnswered(plan, false))
    }

  }

  async end(): Promise<void> {
    // No documented way to close Claude Code from outside (S05 decides).
    throw new CommandError('not_supported', 'end the session with /exit in its terminal')
  }
  /** The chat and tool calls so far, oldest first. */
  async getHistory(): Promise<History> {
    return this.chat.get()
  }
}

/**
 * The chat already in a conversation's transcript when the world first
 * hears from it, without the prompt that woke it (that one arrives as a
 * live message), and its usage. Empty for a new conversation, or without
 * a transcript.
 */
function earlierChat(file: string, p: HookPayload): Conversation {
  const read = readConversation(file)
  const history = read.history
  const chat = history.messages
  const last = chat.at(-1)
  if (p.hook_event_name === 'UserPromptSubmit' && typeof p.prompt === 'string' &&
      last?.role === 'user' && last.text === unwrapChannel(p.prompt.trim())) {
    chat.pop()
    // Nothing ran after it yet; anything tied to it would be orphaned.
    history.tools = history.tools.filter((t) => t.after !== last.message)
  }
  return read
}
