// Protocol v1 types and validation. protocol/events.schema.json is the rule:
// every command from Godot and every event to Godot is checked against it.
// See NOTES.md -> Protocol.
import { Ajv2020 } from 'ajv/dist/2020.js'
import schema from '../../protocol/events.schema.json' with { type: 'json' }

export const PROTOCOL_VERSION = 1

// ---- shapes (mirror the schema's $defs; tests check events against the schema) ----

export type Id = string
export type State = 'working' | 'waiting' | 'idle' | 'done' | 'error'

/** `repo`: set by the sidecar on sessions; see repo.ts. */
export interface Project { path: string; name?: string; repo?: string }

export interface Agent {
  agent: Id
  role: 'orchestrator' | 'subagent'
  parent: Id | null
  name?: string
  task?: string
  state: State
  reason: string | null
}

/** A way to allow beyond a plain allow; `label` is the provider's words, shown as is. */
export interface PermissionOption { option: Id; label: string }

export interface Permission {
  permission: Id
  agent: Id
  tool: string
  summary: string
  input?: Record<string, unknown>
  /** Other ways to allow, in the provider's own order (C05). */
  options?: PermissionOption[]
  /** Set by the registry; see stamp() there. */
  asked_at?: string
}

/** A plan waiting for approval (plans capability). `asked_at`: set by the registry. */
export interface Plan { plan: Id; agent: Id; text: string; modes: string[]; asked_at?: string }

export type MessageKind = 'plan'

export interface QuestionItem {
  text: string
  header?: string
  options: { label: string; description?: string }[]
  multi_select: boolean
}

/** `asked_at`: set by the registry; see stamp() there. */
export interface Question { question: Id; agent: Id; asked_at?: string; items: QuestionItem[] }

export interface Notice { code: string; message: string }

/**
 * The program a provider with program_path found (hello's program,
 * provider.program): its path and version, or why there's none. S02.
 */
export type Program =
  | { path: string; version: string; set_by_hand: boolean }
  | { path: null; set_by_hand: boolean; message: string }

/** One value the user can pick or see: the provider's id and its words for it. */
export interface Choice { id: string; label: string }

/** What a session can be started or resumed with, each list in the provider's order (launch_options). */
export interface LaunchOptions { model?: Choice[]; effort?: Choice[]; mode?: Choice[] }

/** The user's launch choices: ids from the provider's lists; one left out is the provider's default. */
export interface Launch { model?: string; effort?: string; mode?: string }

/**
 * One of the account's usage limits (usage capability). `id` is stable per
 * provider (Claude: five_hour, seven_day); `label` is the provider's own
 * words for it ("5-hour", "Weekly"), shown as plain text.
 */
export interface UsageLimit { id: string; label: string; used_percent: number; resets_at: string }

/** A session's token usage (usage capability), the whole current figures. See NOTES.md -> C08. */
export interface Usage {
  tokens: { input: number; output: number; cache_read: number; cache_write: number }
  /** After the latest call; null until the first. `percent` and `window` are null when the provider doesn't say. */
  context: { tokens: number; percent: number | null; window: number | null } | null
  /** The turn going on or last finished: the user message that started it, and its output tokens. */
  turn: { message: Id | null; output_tokens: number }
  /** In the provider's order, each id once; empty while none are known. */
  limits: UsageLimit[]
}

export interface Session {
  session: Id
  seq: number
  provider: string
  native_id: string | null
  origin: 'app' | 'external'
  project: Project
  title: string | null
  started_at: string
  /** The world only watches it: no chat, answers or stop from the world (S07). Absent otherwise. */
  read_only?: true
  capabilities: Record<string, Record<string, unknown>>
  extensions: string[]
  agents: Agent[]
  permissions: Permission[]
  questions?: Question[]
  /** permission_modes capability: the current mode, null until known. */
  mode?: string | null
  /** model_info capability: the model and effort level, null until known. */
  model?: Choice | null
  effort?: Choice | null
  /** plans capability: plans waiting for approval. */
  plans?: Plan[]
  /** usage capability: null until the first count. */
  usage?: Usage | null
  notices: Notice[]
}

export interface HistoryMessage {
  message: Id
  agent: Id
  role: 'user' | 'assistant'
  kind?: MessageKind
  text: string
  at: string
  /** A user message only (usage capability): the output tokens of the turn it started. */
  turn_tokens?: number
}

/** A tool call in session.get_history (C04). */
export interface HistoryTool {
  tool_call: Id
  agent: Id
  tool: string
  summary: string
  input?: Record<string, unknown>
  status: 'running' | 'ok' | 'error' | 'denied'
  result?: string
  /** The chat message it came after; null before the first. */
  after: Id | null
  within?: Id
}

/** session.get_history's result. */
export interface History { messages: HistoryMessage[]; tools: HistoryTool[] }

export interface StoredSession {
  provider: string
  native_id: string
  project: Project
  title: string | null
  updated_at: string
}

// Session-scoped events as a provider emits them: the registry adds
// `session` and `seq`.
export type SessionEvent =
  | { type: 'agent.spawned'; agent: Agent }
  | { type: 'agent.state_changed'; agent: Id; state: State; reason: string | null }
  | { type: 'message.started'; message: Id; agent: Id; role: 'user' | 'assistant'; kind?: MessageKind }
  | { type: 'message.delta'; message: Id; text: string }
  | { type: 'message.completed'; message: Id; text: string }
  | { type: 'tool.started'; tool_call: Id; agent: Id; tool: string; summary: string; input?: Record<string, unknown>; within?: Id }
  | { type: 'tool.finished'; tool_call: Id; status: 'ok' | 'error' | 'denied'; summary?: string }
  | { type: 'permission.requested'; permission: Permission }
  | { type: 'permission.resolved'; permission: Id; decision: 'allow' | 'deny'; by: 'app' | 'external' }
  | { type: 'question.asked'; question: Question }
  | { type: 'question.resolved'; question: Id; by: 'app' | 'external' }
  | { type: 'plan.asked'; plan: Plan }
  | { type: 'plan.resolved'; plan: Id; decision: 'approved' | 'rejected'; by: 'app' | 'external' }
  | { type: 'session.notice'; notice: Notice }
  | { type: 'session.notice_cleared'; code: string }
  | { type: 'usage.updated'; usage: Usage }
  | { type: 'session.updated'; native_id?: string; title?: string | null; mode?: string; model?: Choice; effort?: Choice | null }
  | { type: `ext.${string}`; [key: string]: unknown }

export type EndReason = 'user' | 'exited' | 'error'

export type Command =
  | { type: 'session.create'; id: Id; provider: string; project: Project; prompt?: string; launch?: Launch }
  | { type: 'session.list_stored'; id: Id; provider: string; project?: string }
  | { type: 'session.resume'; id: Id; provider: string; native_id: string; launch?: Launch }
  | { type: 'session.end'; id: Id; session: Id }
  | { type: 'interrupt.request'; id: Id; session: Id }
  | { type: 'session.get_snapshot'; id: Id; session: Id }
  | { type: 'session.get_history'; id: Id; session: Id }
  | { type: 'message.send'; id: Id; session: Id; text: string }
  | { type: 'permission.respond'; id: Id; session: Id; permission: Id; decision: 'allow' | 'deny'; note?: string; option?: Id }
  | { type: 'plan.answer'; id: Id; session: Id; plan: Id; approve: boolean; mode?: string; note?: string }
  | { type: 'question.answer'; id: Id; session: Id; question: Id; answers?: string[][]; response?: string }
  | { type: 'client.set_focus'; id: Id; focused: boolean }
  | { type: 'client.set_outside_sessions'; id: Id; enabled: boolean }
  | { type: 'client.set_program_path'; id: Id; provider: string; path: string | null }

export type ExtensionCommand = { type: `ext.${string}`; id?: Id; session?: Id; [key: string]: unknown }

// Godot -> sidecar. Every other core type is an event and is refused as input.
export const COMMAND_TYPES: readonly Command['type'][] = [
  'session.create', 'session.list_stored', 'session.resume', 'session.end',
  'interrupt.request', 'session.get_snapshot', 'session.get_history',
  'message.send', 'permission.respond', 'question.answer', 'plan.answer', 'client.set_focus',
  'client.set_outside_sessions', 'client.set_program_path',
]

// Commands that belong to a capability: refused for sessions that don't declare it.
export const COMMAND_CAPABILITY: Partial<Record<Command['type'], string>> = {
  'interrupt.request': 'interrupt',
  'question.answer': 'questions',
  'plan.answer': 'plans',
}

// Events that belong to a capability: dropped if the session doesn't declare it.
export const EVENT_CAPABILITY: Partial<Record<string, string>> = {
  'question.asked': 'questions',
  'question.resolved': 'questions',
  'plan.asked': 'plans',
  'plan.resolved': 'plans',
  'usage.updated': 'usage',
}

// Error codes sent in `error` messages.
export type ErrorCode =
  | 'invalid_message'    // not JSON, not a known command, or fails the schema
  | 'unknown_provider'
  | 'unknown_session'    // no such session, or it has ended
  | 'session_starting'   // the session exists but hasn't come up yet
  | 'not_supported'      // capability or extension the session doesn't declare
  | 'invalid_project'    // project path not absolute or not a folder
  | 'invalid_program'    // client.set_program_path: the path failed a check
  | 'provider_error'     // the provider failed to do it

export const EXTENSION_TYPE = /^ext\.([a-z][a-z0-9_]*)\.[a-z][a-z0-9_.]*$/

// ---- validation ----

// strictRequired off: question.answer's `oneOf: [{required: [answers]}, ...]`
// is valid JSON Schema that strict mode flags; every other strict check stays.
const ajv = new Ajv2020({ allErrors: false, strict: true, strictRequired: false })
// date-time without pulling in ajv-formats: RFC 3339 shape, and a real date.
ajv.addFormat('date-time', {
  type: 'string',
  validate: (s: string) =>
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/i.test(s) && !Number.isNaN(Date.parse(s)),
})
ajv.addSchema(schema)
const SCHEMA_ID = (schema as { $id: string }).$id

const validators = new Map<string, ReturnType<typeof ajv.compile>>()
function validatorFor(def: string) {
  let v = validators.get(def)
  if (!v) {
    const found = ajv.getSchema(`${SCHEMA_ID}#/$defs/${def}`)
    if (!found) throw new Error(`schema has no $defs/${def}`)
    v = found
    validators.set(def, v)
  }
  return v
}

export function schemaDefs(): string[] {
  return Object.keys((schema as { $defs: Record<string, unknown> }).$defs)
}

function describeErrors(v: ReturnType<typeof ajv.compile>): string {
  const e = v.errors?.[0]
  if (!e) return 'invalid'
  const where = e.instancePath || '(message)'
  const extra = e.keyword === 'additionalProperties'
    ? ` (${(e.params as { additionalProperty: string }).additionalProperty})` : ''
  return `${where} ${e.message ?? 'is invalid'}${extra}`
}

export type Checked<T> = { ok: true; value: T } | { ok: false; message: string }

/** Validates any protocol message (either direction) against its schema entry. */
export function checkMessage(msg: unknown): Checked<Record<string, unknown>> {
  if (typeof msg !== 'object' || msg === null || Array.isArray(msg)) {
    return { ok: false, message: 'message must be a JSON object' }
  }
  const type = (msg as { type?: unknown }).type
  if (typeof type !== 'string') return { ok: false, message: 'message has no type' }
  const def = EXTENSION_TYPE.test(type) ? 'extension' : type
  if (def === 'id' || !schemaDefs().includes(def) || !isMessageDef(def)) {
    return { ok: false, message: `unknown message type ${JSON.stringify(type)}` }
  }
  const v = validatorFor(def)
  if (!v(msg)) return { ok: false, message: describeErrors(v) }
  return { ok: true, value: msg as Record<string, unknown> }
}

// $defs that are whole messages (have a `type` const), as opposed to shared shapes.
function isMessageDef(def: string): boolean {
  if (def === 'extension') return true
  const d = (schema as { $defs: Record<string, { properties?: { type?: { const?: string } } }> }).$defs[def]
  return d?.properties?.type?.const === def
}

/** Validates a message from Godot: it must be a command (core or extension). */
export function checkCommand(msg: unknown): Checked<Command | ExtensionCommand> {
  const checked = checkMessage(msg)
  if (!checked.ok) return checked
  const type = checked.value.type as string
  if (!EXTENSION_TYPE.test(type) && !(COMMAND_TYPES as readonly string[]).includes(type)) {
    return { ok: false, message: `${type} is not a command` }
  }
  return { ok: true, value: checked.value as Command | ExtensionCommand }
}
