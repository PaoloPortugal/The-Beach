// The session registry: one entry per session (one island). It owns each
// session's state and seq counter, so snapshots always match the events sent.
// Providers report through a SessionHost; every event is checked against the
// schema and against the session's state before it goes out.
import crypto from 'node:crypto'
import {
  checkMessage, EVENT_CAPABILITY, EXTENSION_TYPE,
  type EndReason, type Id, type Session, type SessionEvent,
} from './protocol.ts'
import type { Provider, ProviderSession, SessionHost, SessionIntro } from './provider.ts'
import type { Log } from './log.ts'
import { withRepo } from './repo.ts'

export type Outgoing = Record<string, unknown> & { type: string }

export interface Entry {
  readonly id: Id
  readonly provider: Provider
  readonly host: SessionHost
  /** Set once the provider's create/resume resolves. */
  control: ProviderSession | null
  /** Null until announced. */
  state: Session | null
  ended: boolean
  /**
   * While a command for this session is being answered, its events wait, so
   * the reply always comes first ("... follows" in the schema). A count,
   * since commands can overlap.
   */
  holding: number
  held: Outgoing[]
}

export class Registry {
  readonly providers: ReadonlyMap<string, Provider>
  private readonly sessions = new Map<Id, Entry>()
  private sink: (msg: Outgoing) => void = () => {}
  private readonly log: Log

  constructor(providers: Provider[], log: Log) {
    this.providers = new Map(providers.map((p) => [p.id, p]))
    this.log = log
  }

  /** Where events go (the connected Godot client, if any). */
  setSink(sink: (msg: Outgoing) => void): void {
    this.sink = sink
  }

  get(id: Id): Entry | undefined {
    return this.sessions.get(id)
  }

  /** Every session that is up, for snapshots. Copies, safe to send. */
  snapshots(): Session[] {
    return [...this.sessions.values()]
      .filter((e) => e.state !== null)
      .map((e) => structuredClone(e.state!))
  }

  snapshot(id: Id): Session | null {
    const s = this.sessions.get(id)?.state
    return s ? structuredClone(s) : null
  }

  /** A new, not-yet-announced session. Starts with one hold (for its create command). */
  open(provider: Provider): Entry {
    const id = crypto.randomUUID()
    const entry: Entry = {
      id, provider, control: null, state: null, ended: false, holding: 1, held: [],
      host: null as unknown as SessionHost,
    }
    ;(entry as { host: SessionHost }).host = this.makeHost(entry)
    this.sessions.set(id, entry)
    return entry
  }

  /** Holds the session's events until the matching release(). */
  hold(entry: Entry): void {
    entry.holding += 1
  }

  /** Ends one hold; when none are left, sends what was held, in order. */
  release(entry: Entry): void {
    entry.holding = Math.max(0, entry.holding - 1)
    if (entry.holding > 0) return
    const held = entry.held.splice(0)
    for (const msg of held) this.sink(msg)
  }

  /** Forgets a session that never came up (its create failed). */
  discard(entry: Entry): void {
    if (entry.state === null) {
      entry.ended = true
      this.sessions.delete(entry.id)
    } else {
      entry.host.end('error')
    }
  }

  private send(entry: Entry, msg: Outgoing): void {
    if (entry.holding > 0) entry.held.push(msg)
    else this.sink(msg)
  }

  private makeHost(entry: Entry): SessionHost {
    return {
      id: entry.id,
      get ended() { return entry.ended },
      announce: (intro) => this.announce(entry, intro),
      emit: (event) => this.emit(entry, event),
      end: (reason) => this.end(entry, reason),
    }
  }

  private announce(entry: Entry, intro: SessionIntro): void {
    if (entry.ended) return
    if (entry.state !== null) throw new Error('session announced twice')
    const orchestrators = intro.agents.filter((a) => a.role === 'orchestrator')
    if (orchestrators.length !== 1 || intro.agents[0]?.role !== 'orchestrator') {
      throw new Error('a session needs exactly one orchestrator, listed first')
    }
    const state: Session = {
      session: entry.id,
      seq: 1,
      provider: entry.provider.id,
      native_id: intro.native_id,
      origin: 'app',
      project: withRepo(intro.project),
      title: intro.title,
      started_at: new Date().toISOString(),
      capabilities: structuredClone(intro.capabilities),
      extensions: [...intro.extensions],
      agents: structuredClone(intro.agents),
      permissions: [],
      ...('questions' in intro.capabilities ? { questions: [] } : {}),
      ...('permission_modes' in intro.capabilities ? { mode: intro.mode ?? null } : {}),
      ...('plans' in intro.capabilities ? { plans: [] } : {}),
      notices: [],
    }
    const msg = { type: 'session.created', session: state }
    const checked = checkMessage(msg)
    if (!checked.ok) throw new Error(`invalid session: ${checked.message}`)
    entry.state = state
    this.send(entry, structuredClone(msg))
  }

  private emit(entry: Entry, event: SessionEvent): boolean {
    const s = entry.state
    const refuse = (why: string) => {
      this.log.warn(`dropped ${event.type} for session ${entry.id}: ${why}`)
      return false
    }
    if (entry.ended) return refuse('session has ended')
    if (s === null) return refuse('session not announced yet')

    const capability = EVENT_CAPABILITY[event.type]
    if (capability !== undefined && !(capability in s.capabilities)) {
      return refuse(`capability ${capability} not declared`)
    }
    const ext = EXTENSION_TYPE.exec(event.type)
    if (ext && !s.extensions.includes(ext[1]!)) return refuse(`extension ${ext[1]} not declared`)

    // A mode change is the permission_modes capability's; native_id and
    // title in the same event still go out.
    if (event.type === 'session.updated' && event.mode !== undefined && !('permission_modes' in s.capabilities)) {
      const { mode: _, ...rest } = event
      if (Object.keys(rest).length === 1) return refuse('capability permission_modes not declared')
      event = rest
    }
    if (event.type === 'message.started' && event.kind === 'plan' && !('plans' in s.capabilities)) {
      return refuse('capability plans not declared')
    }

    event = stamp(event)
    const { type, ...rest } = event
    const msg: Outgoing = { type, session: entry.id, seq: s.seq + 1, ...rest }
    const checked = checkMessage(msg)
    if (!checked.ok) return refuse(`fails the schema: ${checked.message}`)

    const problem = applyEvent(s, event)
    if (problem) return refuse(problem)

    s.seq += 1
    this.send(entry, structuredClone(msg))
    return true
  }

  private end(entry: Entry, reason: EndReason): void {
    if (entry.ended) return
    entry.ended = true
    this.sessions.delete(entry.id)
    const seq = (entry.state?.seq ?? 0) + 1
    // Also sent for a session that never came up, so Godot can drop a
    // "starting" placeholder for the id it got in the create reply.
    this.send(entry, { type: 'session.ended', session: entry.id, seq, reason })
  }
}

/**
 * Notes when a permission or question was asked, so the wait can be timed.
 * The sidecar's clock decides, not the provider's: a provider's own value is
 * replaced. Kept in the snapshot, so it survives Godot reconnecting.
 */
function stamp(e: SessionEvent): SessionEvent {
  const asked_at = new Date().toISOString()
  if (e.type === 'permission.requested') return { ...e, permission: { ...e.permission, asked_at } }
  if (e.type === 'question.asked') return { ...e, question: { ...e.question, asked_at } }
  if (e.type === 'plan.asked') return { ...e, plan: { ...e.plan, asked_at } }
  return e
}

/**
 * Updates the session state for one event. Returns why the event doesn't fit
 * the state (and changes nothing), or null. Keeps snapshots and events in
 * agreement, and keeps provider bugs from reaching Godot as nonsense.
 */
function applyEvent(s: Session, e: SessionEvent): string | null {
  const agent = (id: Id) => s.agents.find((a) => a.agent === id)
  switch (e.type) {
    case 'agent.spawned': {
      if (agent(e.agent.agent)) return `agent ${e.agent.agent} already exists`
      if (e.agent.role !== 'subagent') return 'only subagents can spawn'
      if (e.agent.parent === null || !agent(e.agent.parent)) return 'unknown parent'
      if (!stateFits('subagent', e.agent.state)) return `a subagent can't be ${e.agent.state}`
      s.agents.push(structuredClone(e.agent))
      return null
    }
    case 'agent.state_changed': {
      const a = agent(e.agent)
      if (!a) return `unknown agent ${e.agent}`
      if (!stateFits(a.role, e.state)) return `an ${a.role} can't be ${e.state}`
      a.state = e.state
      a.reason = e.reason
      return null
    }
    case 'message.started':
    case 'tool.started':
      return agent(e.agent) ? null : `unknown agent ${e.agent}`
    case 'permission.requested': {
      if (!agent(e.permission.agent)) return `unknown agent ${e.permission.agent}`
      if (s.permissions.some((p) => p.permission === e.permission.permission)) return 'permission already pending'
      s.permissions.push(structuredClone(e.permission))
      return null
    }
    case 'permission.resolved': {
      const i = s.permissions.findIndex((p) => p.permission === e.permission)
      if (i < 0) return `no pending permission ${e.permission}`
      s.permissions.splice(i, 1)
      return null
    }
    case 'question.asked': {
      const qs = (s.questions ??= [])
      if (!agent(e.question.agent)) return `unknown agent ${e.question.agent}`
      if (qs.some((q) => q.question === e.question.question)) return 'question already pending'
      qs.push(structuredClone(e.question))
      return null
    }
    case 'session.notice': {
      const i = s.notices.findIndex((n) => n.code === e.notice.code)
      if (i >= 0 && s.notices[i]!.message === e.notice.message) return 'notice already shown'
      if (i >= 0) s.notices[i] = { ...e.notice }
      else s.notices.push({ ...e.notice })
      return null
    }
    case 'session.updated': {
      // Only what changed goes out; nothing changed, nothing goes out.
      const changed = (e.native_id !== undefined && e.native_id !== s.native_id) ||
        (e.title !== undefined && e.title !== s.title) ||
        (e.mode !== undefined && e.mode !== s.mode)
      if (!changed) return 'nothing changed'
      if (e.native_id !== undefined) s.native_id = e.native_id
      if (e.title !== undefined) s.title = e.title
      if (e.mode !== undefined) s.mode = e.mode
      return null
    }
    case 'plan.asked': {
      const plans = (s.plans ??= [])
      if (!agent(e.plan.agent)) return `unknown agent ${e.plan.agent}`
      if (plans.some((p) => p.plan === e.plan.plan)) return 'plan already pending'
      plans.push(structuredClone(e.plan))
      return null
    }
    case 'plan.resolved': {
      const plans = s.plans ?? []
      const i = plans.findIndex((p) => p.plan === e.plan)
      if (i < 0) return `no pending plan ${e.plan}`
      plans.splice(i, 1)
      return null
    }

    case 'question.resolved': {
      const qs = s.questions ?? []
      const i = qs.findIndex((q) => q.question === e.question)
      if (i < 0) return `no pending question ${e.question}`
      qs.splice(i, 1)
      return null
    }
    default:
      // message.delta / message.completed / tool.finished and extensions
      // don't change the snapshot.
      return null
  }
}

function stateFits(role: 'orchestrator' | 'subagent', state: string): boolean {
  if (state === 'idle') return role === 'orchestrator'
  if (state === 'done') return role === 'subagent'
  return true
}
