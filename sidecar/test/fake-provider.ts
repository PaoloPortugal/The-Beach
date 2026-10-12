// A scriptable provider for tests and for developing the Godot side before a
// real provider runs. Never shipped: the bundle only includes src/.
import type { Provider, ProviderSession, SessionHost, SessionIntro } from '../src/provider.ts'
import type { Choice, History, Id, Launch, LaunchOptions, Project, StoredSession } from '../src/protocol.ts'

export interface FakeOptions {
  id?: string
  capabilities?: SessionIntro['capabilities']
  extensions?: string[]
  /** Announce inside create() (before the ok reply is sent). Default true. */
  announceOnCreate?: boolean
  /** create() rejects with this. */
  failCreate?: Error
  /** What sessions can be started with (hello's launch_options). */
  launchOptions?: LaunchOptions
}

export type Call = { method: string; session: Id; args: unknown[] }

export class FakeSession implements ProviderSession {
  readonly host: SessionHost
  readonly project: Project
  private readonly provider: FakeProvider
  history: History = { messages: [], tools: [] }
  /** What announce() reports; defaults to `native-<session id>` and "fake session" (null: no title). */
  nativeId?: string
  title?: string | null
  /** permission_modes: the mode announce() reports, if set. */
  mode?: string | null
  /** model_info: what announce() reports, if set. */
  model?: Choice | null
  effort?: Choice | null
  answerQuestion?: ProviderSession['answerQuestion']
  answerPlan?: ProviderSession['answerPlan']
  interrupt?: ProviderSession['interrupt']
  extension?: ProviderSession['extension']

  constructor(provider: FakeProvider, host: SessionHost, project: Project) {
    this.provider = provider
    this.host = host
    this.project = project
    const caps = provider.options.capabilities ?? {}
    if ('questions' in caps) this.answerQuestion = async (...args) => this.record('answerQuestion', args)
    if ('plans' in caps) this.answerPlan = async (...args) => this.record('answerPlan', args)
    if ('interrupt' in caps) this.interrupt = async () => this.record('interrupt', [])
    if ((provider.options.extensions ?? []).length > 0) {
      this.extension = async (cmd) => { this.record('extension', [cmd]); return { echoed: cmd.type } }
    }
  }

  announce(): void {
    this.host.announce({
      native_id: this.nativeId ?? `native-${this.host.id}`,
      project: this.project,
      title: this.title === undefined ? 'fake session' : this.title,
      capabilities: this.provider.options.capabilities ?? {},
      extensions: this.provider.options.extensions ?? [],
      ...(this.mode !== undefined ? { mode: this.mode } : {}),
      ...(this.model !== undefined ? { model: this.model } : {}),
      ...(this.effort !== undefined ? { effort: this.effort } : {}),
      agents: [{ agent: 'main', role: 'orchestrator', parent: null, name: 'Orchestrator', state: 'idle', reason: null }],
    })
  }

  private record(method: string, args: unknown[]) {
    this.provider.calls.push({ method, session: this.host.id, args })
    const fail = this.provider.failNext
    if (fail) {
      this.provider.failNext = null
      throw fail
    }
  }

  async sendMessage(text: string) { this.record('sendMessage', [text]) }
  async respondPermission(permission: Id, decision: 'allow' | 'deny', note?: string, option?: Id) {
    this.record('respondPermission', option === undefined ? [permission, decision, note] : [permission, decision, note, option])
  }
  async end() {
    this.record('end', [])
    this.host.end('user')
  }
  async getHistory() {
    this.record('getHistory', [])
    return this.history
  }
}

export class FakeProvider implements Provider {
  readonly id: string
  readonly name = 'Fake'
  readonly options: FakeOptions
  readonly sessions: FakeSession[] = []
  readonly calls: Call[] = []
  failNext: Error | null = null
  stored: StoredSession[] = []
  shutdownCalled = false
  readonly launchOptions?: LaunchOptions
  /** Each create's and resume's launch choices, in order. */
  readonly launches: (Launch | undefined)[] = []

  constructor(options: FakeOptions = {}) {
    this.options = options
    this.id = options.id ?? 'fake'
    if (options.launchOptions) this.launchOptions = options.launchOptions
  }

  async create(host: SessionHost, options: { project: Project; prompt?: string; launch?: Launch }) {
    this.launches.push(options.launch)
    if (this.options.failCreate) throw this.options.failCreate
    const s = new FakeSession(this, host, options.project)
    this.sessions.push(s)
    if (this.options.announceOnCreate ?? true) s.announce()
    return s
  }

  async resume(host: SessionHost, nativeId: string, launch?: Launch) {
    this.launches.push(launch)
    const s = new FakeSession(this, host, { path: process.cwd(), name: nativeId })
    this.sessions.push(s)
    if (this.options.announceOnCreate ?? true) s.announce()
    return s
  }

  async listStored(project?: string) {
    return project ? this.stored.filter((s) => s.project.path === project) : this.stored
  }

  async shutdown() { this.shutdownCalled = true }
}
