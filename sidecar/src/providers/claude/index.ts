// The Claude provider (NOTES.md -> S02): the only place Claude-specific names
// may appear in the sidecar. It launches the user's own, unmodified `claude`
// in a terminal and never reads, stores or passes on Claude credentials.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import type { Provider, ProviderSession, SessionHost } from '../../provider.ts'
import { CommandError } from '../../provider.ts'
import type { HistoryMessage, Project, SessionEvent, StoredSession } from '../../protocol.ts'
import { cleanEnv, STORE_CLIENT_VARIABLES } from '../../launch/env.ts'
import { openTerminal, TerminalError } from '../../launch/terminal.ts'
import { writeSessionFile } from '../../launch/launcher.ts'
import { selfCommand } from '../../launch/self.ts'
import type { Log } from '../../log.ts'
import { stderrLog } from '../../log.ts'
import { CLAUDE_SESSION_MARKER_PREFIXES, CLAUDE_SESSION_MARKERS } from './env.ts'
import { ClaudeNotFound, findClaude, type FoundClaude } from './find.ts'
import { BRIDGE_SERVER_NAME } from './bridge.ts'
import { BridgeServer, type BridgeLink } from './bridge-server.ts'
import { HookServer, type HookLink, type HookPayload } from './hook-server.ts'
import { TranscriptFollower, type TranscriptSignal } from './transcript.ts'
import { findStored, listStored, projectsDir, readHistory } from './store.ts'
import {
  HookTranslator, hookSettings, MAIN, QUESTION_TOOL, questionReply, type RelayedPermission,
} from './hooks.ts'

/**
 * How long a launched session may take to come up (the user answering the
 * startup prompts in its terminal). After that it's treated as gone: if the
 * user chose Exit at a startup prompt, nothing else would tell us.
 */
export const STARTUP_TIMEOUT_MS = 15 * 60 * 1000

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

export interface ClaudeOptions {
  log?: Log
  /** How to start this sidecar in another mode; tests and dev tools override it. */
  selfCommand?: (mode: string, ...args: string[]) => string[]
  /** A claude executable chosen by hand (a user setting, later). */
  claudePath?: string
  /** A terminal id to try first (a user setting, later). */
  terminal?: string
  /** For tests: replaces opening a real terminal. */
  openTerminal?: typeof openTerminal
  /** For tests: replaces finding claude. */
  findClaude?: () => Promise<FoundClaude>
  /** For tests: a shorter startup timeout. */
  startupTimeoutMs?: number
  /** For tests: Claude Code's projects folder (stored sessions). */
  projectsDir?: string
  /** For tests: how long a world message waits for its first hook. */
  hooksCheckMs?: number
}

/** Everything the launched claude and our side share for one session. */
interface Launch {
  runDir: string
  nativeId: string
}

export class ClaudeProvider implements Provider {
  readonly id = 'claude'
  readonly name = 'Claude Code'
  private readonly opts: ClaudeOptions
  private readonly log: Log
  private readonly runDirs = new Set<string>()
  /** Sessions running now, by Claude's session id: not listed, not resumed twice. */
  private readonly live = new Set<string>()
  private bridges: BridgeServer | null = null
  private hooks: HookServer | null = null

  constructor(opts: ClaudeOptions = {}) {
    this.opts = opts
    this.log = opts.log ?? stderrLog
  }

  /** Variables removed from every launched process's environment. */
  static readonly UNSET_ENV = {
    names: [...CLAUDE_SESSION_MARKERS, ...STORE_CLIENT_VARIABLES],
    prefixes: [...CLAUDE_SESSION_MARKER_PREFIXES],
  }

  async create(host: SessionHost, options: { project: Project; prompt?: string }): Promise<ProviderSession> {
    const name = options.project.name ?? path.basename(options.project.path)
    return this.start(host, {
      project: options.project, name, nativeId: crypto.randomUUID(), resume: false, history: [],
      ...(options.prompt ? { prompt: options.prompt } : {}),
    })
  }

  /**
   * Resumes a stored session (S04): `claude --resume <id>` in its project
   * folder, with our hooks and channel like a new one. Its chat so far comes
   * from the transcript.
   */
  async resume(host: SessionHost, nativeId: string): Promise<ProviderSession> {
    if (this.live.has(nativeId)) throw new CommandError('provider_error', 'That session is already open.')
    const stored = findStored(nativeId, this.opts.projectsDir ?? projectsDir())
    if (!stored) throw new CommandError('provider_error', 'That session wasn\'t found. Claude Code may have deleted it.')
    if (!fs.statSync(stored.project.path, { throwIfNoEntry: false })?.isDirectory()) {
      throw new CommandError('provider_error', `Its project folder no longer exists: ${stored.project.path}`)
    }
    return this.start(host, {
      project: stored.project, name: stored.title ?? path.basename(stored.project.path),
      nativeId, resume: true, history: readHistory(stored.file),
    })
  }

  /** Terminal sessions in Claude Code's store, newest first; the ones running here are left out. */
  async listStored(project?: string): Promise<StoredSession[]> {
    return listStored({
      dir: this.opts.projectsDir ?? projectsDir(),
      ...(project ? { project } : {}),
      exclude: this.live,
    }).map(({ file: _file, ...s }) => s)
  }

  private async start(host: SessionHost, o: {
    project: Project; name: string; nativeId: string; resume: boolean; history: HistoryMessage[]; prompt?: string
  }): Promise<ProviderSession> {
    const found = await this.find()
    const bridges = await this.bridgeServer()
    const hooks = await this.hookServer()
    const launch = this.prepare(o.nativeId)
    this.live.add(o.nativeId)
    const session = new ClaudeSession(host, launch, o.project, o.name, this.log,
      () => { this.forget(launch.runDir); this.live.delete(o.nativeId) },
      this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS, o.history, o.prompt, this.opts.hooksCheckMs ?? HOOKS_CHECK_MS)
    session.link = bridges.register(session.bridgeHandlers())
    session.hookLink = hooks.register({ onHook: (p, gone) => session.onHook(p, gone) })
    const settings = this.writeSettings(launch, hooks.url, session.hookLink.token)
    const mcpConfig = this.writeMcpConfig(launch, bridges.port, session.link.token)
    const args = [
      // A resumed session keeps its id and name.
      ...(o.resume ? ['--resume', o.nativeId] : ['--session-id', o.nativeId, '--name', o.name]),
      // Our hooks for this session only; the user's settings files are never edited.
      '--settings', settings,
      '--mcp-config', mcpConfig,
      // Custom channels need this while channels are a research preview;
      // Claude Code asks the user to confirm it in the terminal.
      '--dangerously-load-development-channels', `server:${BRIDGE_SERVER_NAME}`,
    ]
    try {
      await this.launch(launch, found.path, args, o.project.path, o.name)
    } catch (e) {
      session.dispose()
      throw e
    }
    this.log.info(`launched claude ${found.version} for session ${host.id}${o.resume ? ' (resumed)' : ''}`)
    session.startWaiting()
    return session
  }

  async shutdown(): Promise<void> {
    await this.bridges?.close()
    this.bridges = null
    await this.hooks?.close()
    this.hooks = null
    for (const dir of this.runDirs) fs.rmSync(dir, { recursive: true, force: true })
    this.runDirs.clear()
  }

  private async bridgeServer(): Promise<BridgeServer> {
    if (!this.bridges) this.bridges = new BridgeServer(this.log)
    await this.bridges.start()
    return this.bridges
  }

  private async hookServer(): Promise<HookServer> {
    if (!this.hooks) this.hooks = new HookServer(this.log)
    await this.hooks.start()
    return this.hooks
  }

  private forget(runDir: string) {
    fs.rmSync(runDir, { recursive: true, force: true })
    this.runDirs.delete(runDir)
  }

  /** The session's hooks, posting to our hook server with the session's token. */
  private writeSettings(launch: Launch, url: string, token: string): string {
    const file = path.join(launch.runDir, 'settings.json')
    fs.writeFileSync(file, JSON.stringify(hookSettings(url, token)), { mode: 0o600 })
    return file
  }

  /**
   * The MCP config that makes Claude Code start our bridge: this executable
   * in bridge mode, with the link's port and token in the bridge's own
   * environment (not Claude's: the bridge is Claude Code's child, so
   * commands Claude runs never see it).
   */
  private writeMcpConfig(launch: Launch, port: number, token: string): string {
    const [command, ...args] = (this.opts.selfCommand ?? selfCommand)('bridge', 'claude')
    const file = path.join(launch.runDir, 'mcp.json')
    fs.writeFileSync(file, JSON.stringify({
      mcpServers: {
        [BRIDGE_SERVER_NAME]: { command, args, env: { BRIDGE_PORT: String(port), BRIDGE_TOKEN: token } },
      },
    }), { mode: 0o600 })
    return file
  }

  private async find(): Promise<FoundClaude> {
    try {
      if (this.opts.findClaude) return await this.opts.findClaude()
      return await findClaude({
        env: process.env,
        cleanEnv: cleanEnv(process.env, ClaudeProvider.UNSET_ENV),
        ...(this.opts.claudePath ? { override: this.opts.claudePath } : {}),
      })
    } catch (e) {
      if (e instanceof ClaudeNotFound) throw new CommandError('provider_error', e.message)
      throw e
    }
  }

  /** A private folder for this session's launch file, settings and bridge config. */
  private prepare(nativeId: string): Launch {
    const runDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sidecar-session-'))
    fs.chmodSync(runDir, 0o700)
    this.runDirs.add(runDir)
    return { runDir, nativeId }
  }

  private async launch(launch: Launch, claude: string, args: string[], cwd: string, name: string) {
    const file = path.join(launch.runDir, 'launch.json')
    writeSessionFile(file, { command: claude, args, cwd, unsetEnv: ClaudeProvider.UNSET_ENV })
    const argv = (this.opts.selfCommand ?? selfCommand)('launch', file)
    const open = this.opts.openTerminal ?? openTerminal
    try {
      const used = await open(
        { argv, title: `Claude Code - ${name}`.replace(/[;"]/g, ' '), runDir: launch.runDir },
        { ...(this.opts.terminal ? { preferred: this.opts.terminal } : {}) },
      )
      this.log.info(`opened ${used}`)
    } catch (e) {
      this.forget(launch.runDir)
      if (e instanceof TerminalError) {
        throw new CommandError('provider_error', 'No terminal window could be opened to run Claude Code.')
      }
      throw e
    }
  }
}

class ClaudeSession implements ProviderSession {
  readonly host: SessionHost
  readonly launch: Launch
  link: BridgeLink | null = null
  hookLink: HookLink | null = null
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
      native_id: this.launch.nativeId,
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
    this.hooksSeen = true
    // Hooks only fire once Claude Code is past its startup dialogs, so a
    // hook arriving before the bridge's ready also means the session is up.
    if (this.startupTimer) this.onReady()
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
    if (!this.link?.send({ type: 'chat', text })) {
      throw new CommandError('provider_error', 'The session is not connected.')
    }
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
    // The channel's verdict carries no message (open question: send a note
    // as a chat message after a deny?). Refuse rather than drop the user's words.
    if (note) throw new CommandError('not_supported', 'notes with a permission answer are not supported yet')
    if (!this.link?.send({ type: 'verdict', request_id: permission, behavior: decision })) {
      throw new CommandError('provider_error', 'The session is not connected.')
    }
    this.emitAll(this.translator.permissionAnswered(permission, decision))
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
    this.emitAll(this.translator.questionAnswered(question))
  }

  /**
   * Stop from the world: the busy agents stop at their next tool call (the
   * current reply or command finishes first). Pending permission prompts
   * and questions are declined, or they'd block the stop; that never
   * allows anything.
   */
  async interrupt(): Promise<void> {
    for (const a of this.translator.busyAgents()) this.stopping.add(a)
    for (const permission of this.translator.pendingPermissions()) {
      if (this.link?.send({ type: 'verdict', request_id: permission, behavior: 'deny' })) {
        this.emitAll(this.translator.permissionAnswered(permission, 'deny'))
      }
    }
    for (const question of [...this.held.keys()]) {
      this.release(question, questionReply({}, { response: STOP_REASON }))
      this.emitAll(this.translator.questionAnswered(question))
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
