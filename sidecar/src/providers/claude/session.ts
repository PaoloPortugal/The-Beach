// One running Claude session (NOTES.md -> S02): what its hooks, bridge and
// transcript say, turned into the session's events, and the world's answers,
// stops and messages sent back. The provider (index.ts) launches it.
import fs from 'node:fs'
import path from 'node:path'
import type { ProviderSession, SessionHost } from '../../provider.ts'
import { CommandError } from '../../provider.ts'
import type { HistoryMessage, Project, SessionEvent } from '../../protocol.ts'
import type { Log } from '../../log.ts'
import type { BridgeLink } from './bridge-server.ts'
import type { HookLink, HookPayload } from './hook-server.ts'
import { TranscriptFollower, type TranscriptSignal } from './transcript.ts'
import { HookTranslator, MAIN, QUESTION_TOOL, questionReply, unwrapChannel, type RelayedPermission } from './hooks.ts'
import { hasReply, readHistory } from './store.ts'

/**
 * How long a relayed permission prompt waits for its tool call's
 * PreToolUse, which comes on another connection (about 100 ms earlier in
 * the S02 spike). After that it's shown without one, as the orchestrator's.
 */
export const PERMISSION_MATCH_MS = 300

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

/**
 * Most chat messages kept for history (oldest dropped first). In memory
 * only, never on disk (NOTES.md -> Security rules -> Private by default).
 */
export const HISTORY_MAX = 5000

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

/** Why the world can't send to a conversation that moved. */
export const MOVED_ERROR = 'This conversation moved to another Claude Code session; continue it in the terminal.'
/** Why the world can't send while the bridge isn't connected. */
export const UNREACHABLE_ERROR = 'The world can\'t reach this conversation right now (its channel to Claude Code is closed); use the terminal.'

/** Claude Code's session ids are UUIDs. */
const SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** What a stopped tool call tells Claude, and what the terminal shows. */
export const STOP_REASON = 'The user stopped this from the app.'

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
  private readonly name: string
  private readonly log: Log
  private readonly cleanup: () => void
  private readonly startupTimeoutMs: number
  private launchedAt = 0
  private startupTimer: NodeJS.Timeout | null = null
  private disposed = false
  private readonly translator: HookTranslator
  /** Fills in what hooks miss: Esc and a "No" in the terminal. */
  private readonly transcript = new TranscriptFollower((s) => this.onTranscript(s))
  /**
   * The chat so far, as the world saw it through the hooks: every message
   * since launch, so the same whether transcripts are on or off.
   */
  private readonly history: HistoryMessage[] = []
  /** Messages started but not yet completed: who and when. */
  private readonly starting = new Map<string, { agent: string; role: 'user' | 'assistant'; at: string }>()
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

  /** A first message to send once the session is up (session.create's prompt). */
  private prompt: string | null

  constructor(host: SessionHost, launch: Launch, project: Project, name: string, log: Log,
    cleanup: () => void, startupTimeoutMs: number, history: HistoryMessage[] = [], prompt?: string,
    hooksCheckMs = HOOKS_CHECK_MS) {
    this.host = host
    this.launch = launch
    this.nativeId = launch.nativeId
    this.project = project
    this.name = name
    this.log = log
    this.cleanup = cleanup
    this.startupTimeoutMs = startupTimeoutMs
    this.translator = new HookTranslator(project.path)
    this.history.push(...history)
    this.prompt = prompt ?? null
    this.hooksCheckMs = hooksCheckMs
  }

  bridgeHandlers() {
    return {
      onReady: () => { this.onReady(); this.flushPrompt() },
      onPermissionRequest: (p: RelayedPermission) => this.onPermissionRequest(p),
      onClose: () => this.onGone('the bridge closed'),
    }
  }

  /** Called once the terminal is open: the user now answers the startup prompts. */
  startWaiting() {
    this.launchedAt = Date.now()
    this.startupTimer = setTimeout(() => this.onGone('it never came up'), this.startupTimeoutMs)
    this.startupTimer.unref()
  }

  private onReady() {
    if (this.disposed || this.host.ended) return
    if (!this.startupTimer) return
    clearTimeout(this.startupTimer)
    this.startupTimer = null
    // Timing for NOTES.md -> S02 -> Starting up (checkpoint 1 measurements).
    this.log.info(`session ${this.host.id} came up ${Date.now() - this.launchedAt} ms after launch`)
    this.host.announce({
      native_id: this.nativeId,
      project: this.project,
      title: this.name,
      // A stop from the world lands at the next tool call (NOTES.md -> S02).
      capabilities: { questions: {}, interrupt: { immediate: false } },
      extensions: [],
      agents: [{ agent: MAIN, role: 'orchestrator', parent: null, name: 'Claude', state: 'idle', reason: null }],
    })
    this.flushPrompt()
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
    this.hooksSeen = true
    // Hooks only fire once Claude Code is past its startup dialogs, so a
    // hook arriving before the bridge's ready also means the session is up.
    if (this.startupTimer) this.onReady()
    if (!this.ownConversation(p)) return
    this.transcript.follow(p.transcript_path)
    if (p.hook_event_name === 'Stop' && !this.transcriptChecked) this.checkTranscript(p.transcript_path)
    if (p.hook_event_name === 'PermissionRequest') {
      return p.tool_name === QUESTION_TOOL ? this.holdQuestion(p, gone) : undefined
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
    const source = p.source
    if (source !== 'clear' && source !== 'resume') return
    // Not up yet: nothing to switch (the fallback below still would).
    if (this.startupTimer || p.session_id === this.nativeId || !this.acceptNew(p)) return
    const file = p.transcript_path as string
    // /resume: the resumed conversation's chat, all of it (no prompt has
    // woken it yet). /clear: an empty chat.
    this.switchTo(p.session_id as string, file, source === 'resume' ? readHistory(file) : null)
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
    // A transcript in another folder isn't this project's (never seen).
    if (typeof file !== 'string' || !path.isAbsolute(file) ||
        (this.transcriptDir !== null && path.dirname(file) !== this.transcriptDir)) {
      this.log.warn(`session ${this.host.id}: ignored a hook from another project's conversation`)
      return false
    }
    return true
  }

  /**
   * The world now follows conversation `id`. `resumed` is its chat after
   * /resume, which becomes the history; null after /clear, when the
   * history empties, so the world's chat window clears too (user's
   * decisions, 2026-10-01; the old conversation stays resumable).
   */
  private switchTo(id: string, file: string, resumed: HistoryMessage[] | null) {
    const from = this.nativeId
    this.nativeId = id
    this.transcriptDir ??= path.dirname(file)
    if (resumed) {
      this.history.splice(0, this.history.length, ...resumed.slice(-HISTORY_MAX))
      this.log.info(`session ${this.host.id}: it switched to an earlier conversation (/resume)`)
    } else {
      this.history.length = 0
      this.log.info(`session ${this.host.id}: a new conversation started in it (/clear)`)
    }
    // After the history: the world reloads it on session.updated.
    this.host.emit({ type: 'session.updated', native_id: id })
    this.host.emit({ type: 'session.notice', notice: resumed ? CONVERSATION_RESUMED : CONVERSATION_CLEARED })
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
    this.emitAll(s.kind === 'rejected' ? this.translator.rejectedInTerminal(s.toolUseId) : this.translator.interruptedByUser())
  }

  /** Claude Code shows a permission prompt, relayed by the bridge. */
  private onPermissionRequest(p: RelayedPermission) {
    if (this.disposed || this.host.ended) return
    const events = this.translator.permissionRequested(p)
    if (events) return this.emitAll(events)
    const t = setTimeout(() => {
      if (!this.disposed && !this.host.ended) this.emitAll(this.translator.permissionRequested(p, true) ?? [])
    }, PERMISSION_MATCH_MS)
    t.unref()
  }

  private emitAll(events: SessionEvent[]) {
    for (const event of events) {
      if (this.host.emit(event)) this.remember(event)
      // Answered or dismissed in the terminal: let go of the held hook
      // (Claude Code no longer waits on it; NOTES.md -> S02).
      if (event.type === 'question.resolved' && event.by === 'external') this.release(event.question)
    }
  }

  /** Keeps completed chat messages for session.get_history. */
  private remember(event: SessionEvent) {
    if (event.type === 'message.started') {
      this.starting.set(event.message, { agent: event.agent, role: event.role, at: new Date().toISOString() })
    } else if (event.type === 'message.completed') {
      const started = this.starting.get(event.message)
      if (!started) return
      this.starting.delete(event.message)
      this.history.push({ message: event.message, ...started, text: event.text })
      if (this.history.length > HISTORY_MAX) this.history.splice(0, this.history.length - HISTORY_MAX)
    }
  }

  private release(question: string, reply?: Record<string, unknown>) {
    const resolve = this.held.get(question)
    this.held.delete(question)
    resolve?.(reply)
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
    if (this.hooksCheck) clearTimeout(this.hooksCheck)
    this.link?.unregister()
    this.hookLink?.unregister()
    this.transcript.stop()
    for (const q of [...this.held.keys()]) this.release(q)
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
   * way (NOTES.md -> Security rules).
   */
  async respondPermission(permission: string, decision: 'allow' | 'deny', note?: string): Promise<void> {
    const link = this.reachable()
    if (!link.send({ type: 'verdict', request_id: permission, behavior: decision })) {
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
   * Stop from the world: the busy agents stop at their next tool call (the
   * current reply or command finishes first). Pending permission prompts
   * and questions are declined, or they'd block the stop; that never
   * allows anything.
   */
  async interrupt(): Promise<void> {
    // The stop lands through this conversation's hooks, which a moved one no longer sends.
    if (this.movedTo !== null) throw new CommandError('provider_error', MOVED_ERROR)
    for (const a of this.translator.busyAgents()) this.stopping.add(a)
    for (const permission of this.translator.pendingPermissions()) {
      if (this.link?.send({ type: 'verdict', request_id: permission, behavior: 'deny' })) {
        this.emitAll(this.translator.permissionAnswered(permission, 'deny'))
      }
    }
    for (const question of [...this.held.keys()]) {
      this.release(question, questionReply({}, { response: STOP_REASON }))
      this.emitAll(this.translator.questionAnswered(question, true))
    }
  }

  async end(): Promise<void> {
    // No documented way to close Claude Code from outside (S05 decides).
    throw new CommandError('not_supported', 'end the session with /exit in its terminal')
  }
  /** The chat so far, oldest first. */
  async getHistory(): Promise<HistoryMessage[]> {
    return structuredClone(this.history)
  }
}

/**
 * The chat already in a conversation's transcript when the world first
 * hears from it, without the prompt that woke it (that one arrives as a
 * live message). Empty for a new conversation, or without a transcript.
 */
function earlierChat(file: string, p: HookPayload): HistoryMessage[] {
  const chat = readHistory(file)
  const last = chat.at(-1)
  if (p.hook_event_name === 'UserPromptSubmit' && typeof p.prompt === 'string' &&
      last?.role === 'user' && last.text === unwrapChannel(p.prompt.trim())) chat.pop()
  return chat
}
