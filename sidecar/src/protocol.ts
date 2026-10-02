// Protocol v1 types and validation. protocol/events.schema.json is the rule:
// every command from Godot and every event to Godot is checked against it.
// See NOTES.md -> Protocol.
import { Ajv2020 } from 'ajv/dist/2020.js'
import schema from '../../protocol/events.schema.json' with { type: 'json' }

export const PROTOCOL_VERSION = 1

// ---- shapes (mirror the schema's $defs; tests check events against the schema) ----

export type Id = string
export type State = 'working' | 'waiting' | 'idle' | 'done' | 'error'

export interface Project { path: string; name?: string }

export interface Agent {
  agent: Id
  role: 'orchestrator' | 'subagent'
  parent: Id | null
  name?: string
  task?: string
  state: State
  reason: string | null
}

export interface Permission {
  permission: Id
  agent: Id
  tool: string
  summary: string
  input?: Record<string, unknown>
}

export interface QuestionItem {
  text: string
  header?: string
  options: { label: string; description?: string }[]
  multi_select: boolean
}

export interface Question { question: Id; agent: Id; items: QuestionItem[] }

export interface Notice { code: string; message: string }

export interface Session {
  session: Id
  seq: number
  provider: string
  native_id: string | null
  origin: 'app' | 'external'
  project: Project
  title: string | null
  started_at: string
  capabilities: Record<string, Record<string, unknown>>
  extensions: string[]
  agents: Agent[]
  permissions: Permission[]
  questions?: Question[]
  notices: Notice[]
}

export interface HistoryMessage {
  message: Id
  agent: Id
  role: 'user' | 'assistant'
  text: string
  at: string
}

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
  | { type: 'message.started'; message: Id; agent: Id; role: 'user' | 'assistant' }
  | { type: 'message.delta'; message: Id; text: string }
  | { type: 'message.completed'; message: Id; text: string }
  | { type: 'tool.started'; tool_call: Id; agent: Id; tool: string; summary: string; input?: Record<string, unknown> }
  | { type: 'tool.finished'; tool_call: Id; status: 'ok' | 'error' | 'denied'; summary?: string }
  | { type: 'permission.requested'; permission: Permission }
  | { type: 'permission.resolved'; permission: Id; decision: 'allow' | 'deny'; by: 'app' | 'external' }
  | { type: 'question.asked'; question: Question }
  | { type: 'question.resolved'; question: Id; by: 'app' | 'external' }
  | { type: 'session.notice'; notice: Notice }
  | { type: 'session.updated'; native_id?: string; title?: string | null }
  | { type: `ext.${string}`; [key: string]: unknown }

export type EndReason = 'user' | 'exited' | 'error'

export type Command =
  | { type: 'session.create'; id: Id; provider: string; project: Project; prompt?: string }
  | { type: 'session.list_stored'; id: Id; provider: string; project?: string }
  | { type: 'session.resume'; id: Id; provider: string; native_id: string }
  | { type: 'session.end'; id: Id; session: Id }
  | { type: 'interrupt.request'; id: Id; session: Id }
  | { type: 'session.get_snapshot'; id: Id; session: Id }
  | { type: 'session.get_history'; id: Id; session: Id }
  | { type: 'message.send'; id: Id; session: Id; text: string }
  | { type: 'permission.respond'; id: Id; session: Id; permission: Id; decision: 'allow' | 'deny'; note?: string }
  | { type: 'question.answer'; id: Id; session: Id; question: Id; answers?: string[][]; response?: string }

export type ExtensionCommand = { type: `ext.${string}`; id?: Id; session?: Id; [key: string]: unknown }

// Godot -> sidecar. Every other core type is an event and is refused as input.
export const COMMAND_TYPES: readonly Command['type'][] = [
  'session.create', 'session.list_stored', 'session.resume', 'session.end',
  'interrupt.request', 'session.get_snapshot', 'session.get_history',
  'message.send', 'permission.respond', 'question.answer',
]

// Commands that belong to a capability: refused for sessions that don't declare it.
export const COMMAND_CAPABILITY: Partial<Record<Command['type'], string>> = {
  'interrupt.request': 'interrupt',
  'question.answer': 'questions',
}

// Events that belong to a capability: dropped if the session doesn't declare it.
export const EVENT_CAPABILITY: Partial<Record<string, string>> = {
  'question.asked': 'questions',
  'question.resolved': 'questions',
}

// Error codes sent in `error` messages.
export type ErrorCode =
  | 'invalid_message'    // not JSON, not a known command, or fails the schema
  | 'unknown_provider'
  | 'unknown_session'    // no such session, or it has ended
  | 'session_starting'   // the session exists but hasn't come up yet
  | 'not_supported'      // capability or extension the session doesn't declare
  | 'invalid_project'    // project path not absolute or not a folder
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
