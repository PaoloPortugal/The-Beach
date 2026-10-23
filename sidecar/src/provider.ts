// The generic provider interface. A provider translates one AI tool into the
// protocol's generic vocabulary (NOTES.md -> Multi-provider rules). The core
// never names a specific tool; providers never touch the WebSocket.
import type {
  Agent, Choice, EndReason, ErrorCode, ExtensionCommand, History, Id, Launch, LaunchOptions, Notice, Project,
  SessionEvent, StoredSession,
} from './protocol.ts'

/** Thrown by a provider to fail a command with a specific protocol error code. */
export class CommandError extends Error {
  readonly code: ErrorCode
  constructor(code: ErrorCode, message: string) {
    super(message)
    this.code = code
  }
}

/** What a session looks like when it comes up (becomes session.created). */
export interface SessionIntro {
  native_id: string | null
  project: Project
  title: string | null
  capabilities: Record<string, Record<string, unknown>>
  extensions: string[]
  /** The world only watches it (S07). */
  read_only?: true
  /** Started outside the app, watched only (S08); `app` otherwise. */
  origin?: 'external'
  /** permission_modes: the current mode, if already known. */
  mode?: string | null
  /** model_info: the model and effort level, if already known. */
  model?: Choice | null
  effort?: Choice | null
  /** Orchestrator first. */
  agents: Agent[]
  /** When it started, for a session that started before this sidecar did (restore); now otherwise. */
  started_at?: string
}

/**
 * Takes over one running session found by a provider's restore: makes its
 * host, whose announce sends session.snapshot (it's no new session), and
 * keeps the control `make` returns for the world's commands. `created`:
 * announced as session.created instead (its island rises: S08, outside
 * sessions shown again after being turned off).
 */
export type Adopt = (make: (host: SessionHost) => ProviderSession, o?: { created?: boolean }) => void

/** The registry's side of one session, handed to the provider that runs it. */
export interface SessionHost {
  readonly id: Id
  /** The session is up: sends session.created. Events are refused before this. */
  announce(intro: SessionIntro): void
  /** Sends one session event. Returns false if it was refused (logged). */
  emit(event: SessionEvent): boolean
  /** The session is over: sends session.ended and forgets it. Safe to call twice. */
  end(reason: EndReason): void
  readonly ended: boolean
}

/** A running session, as the provider controls it. */
export interface ProviderSession {
  /**
   * What the world should tell the user while the session is starting (it
   * may need them somewhere else first), sent in the create/resume reply.
   */
  readonly startupNotice?: Notice
  sendMessage(text: string): Promise<void>
  /** `option`: allow this way, one of the permission's options. */
  respondPermission(permission: Id, decision: 'allow' | 'deny', note?: string, option?: Id): Promise<void>
  /** `plans` capability. */
  answerPlan?(plan: Id, answer: { approve: true; mode: string } | { approve: false; note?: string }): Promise<void>
  /** `questions` capability. */
  answerQuestion?(question: Id, answer: { answers: string[][] } | { response: string }): Promise<void>
  /** `interrupt` capability. */
  interrupt?(): Promise<void>
  /** Ends the session; the provider calls host.end('user') once it has. */
  end(): Promise<void>
  /** The chat and tool calls so far (session.get_history's result). */
  getHistory(): Promise<History>
  /** Commands in this provider's extension namespace. Resolves to the ok result. */
  extension?(command: ExtensionCommand): Promise<Record<string, unknown> | void>
}

export interface Provider {
  /** Protocol key and extension namespace, e.g. a lowercase tool name. */
  readonly id: string
  /** Display name. */
  readonly name: string
  /** What sessions can be started or resumed with (hello's launch_options); none: nothing to pick. */
  readonly launchOptions?: LaunchOptions
  /**
   * Capabilities of the provider itself (hello's capabilities), keyed by
   * name, each with its config: e.g. outside_sessions (S08).
   */
  readonly capabilities?: Record<string, Record<string, unknown>>
  /**
   * Start a new session. Resolves once it's launched, not once it's up
   * (announce). `launch`: ids from launchOptions, already checked.
   */
  create(host: SessionHost, options: { project: Project; prompt?: string; launch?: Launch }): Promise<ProviderSession>
  resume(host: SessionHost, nativeId: string, launch?: Launch): Promise<ProviderSession>
  listStored(project?: string): Promise<StoredSession[]>
  /**
   * At start, before anything else: the sessions this provider launched
   * before the sidecar last stopped and still running, each handed to
   * `adopt` (NOTES.md -> S07), and, with outside_sessions, the ones started
   * outside the app (S08), which it may keep adopting later. `notice` sends
   * a provider notice (provider.notice; kept for hello). Resolves once it
   * has looked. Optional: a provider without it has nothing to take back.
   */
  restore?(adopt: Adopt, notice?: (notice: Notice) => void): Promise<void>
  /** Whether the app's window has focus (client.set_focus): it may check on things less often without. */
  setFocused?(focused: boolean): void
  /**
   * Whether sessions started outside the app get islands (outside_sessions;
   * client.set_outside_sessions, or serve --no-outside-sessions before
   * restore). Off ends them (reason user) and stops looking; on looks at
   * once, the ones found announced as session.created.
   */
  setOutsideSessions?(on: boolean): void
  /** The sidecar is exiting. Running sessions keep running on their own. */
  shutdown(): Promise<void>
}
