// The generic provider interface. A provider translates one AI tool into the
// protocol's generic vocabulary (NOTES.md -> Multi-provider rules). The core
// never names a specific tool; providers never touch the WebSocket.
import type {
  Agent, EndReason, ErrorCode, ExtensionCommand, History, Id, Notice, Project,
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
  /** Orchestrator first. */
  agents: Agent[]
}

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
  respondPermission(permission: Id, decision: 'allow' | 'deny', note?: string): Promise<void>
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
  /** Start a new session. Resolves once it's launched, not once it's up (announce). */
  create(host: SessionHost, options: { project: Project; prompt?: string }): Promise<ProviderSession>
  resume(host: SessionHost, nativeId: string): Promise<ProviderSession>
  listStored(project?: string): Promise<StoredSession[]>
  /** The sidecar is exiting. Running sessions keep running on their own. */
  shutdown(): Promise<void>
}
