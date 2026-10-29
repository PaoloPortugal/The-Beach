// The code's view of the protocol matches protocol/events.schema.json.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import schema from '../../protocol/events.schema.json' with { type: 'json' }
import { checkCommand, checkMessage, COMMAND_CAPABILITY, COMMAND_TYPES, schemaDefs } from '../src/protocol.ts'

type Def = { required?: string[]; properties?: { type?: { const?: string } } }
const defs = (schema as unknown as { $defs: Record<string, Def> }).$defs

test('COMMAND_TYPES lists exactly the schema\'s commands', () => {
  // A command is a message def that requires an id (ok/error are replies).
  const fromSchema = schemaDefs()
    .filter((d) => defs[d]?.properties?.type?.const === d)
    .filter((d) => d !== 'ok' && d !== 'error' && defs[d]?.required?.includes('id'))
    .sort()
  assert.deepEqual([...COMMAND_TYPES].sort(), fromSchema)
})

test('every message def is reachable from the top-level oneOf', () => {
  const listed = (schema as unknown as { oneOf: { $ref: string }[] }).oneOf.map((r) => r.$ref.replace('#/$defs/', ''))
  const messages = schemaDefs().filter((d) => defs[d]?.properties?.type?.const === d || d === 'extension')
  assert.deepEqual(listed.sort(), messages.sort())
})

test('capability-gated commands exist', () => {
  for (const t of Object.keys(COMMAND_CAPABILITY)) assert.ok(COMMAND_TYPES.includes(t as never), t)
})

test('valid commands pass', () => {
  const good = [
    { type: 'session.create', id: '1', provider: 'x', project: { path: '/p' } },
    { type: 'session.create', id: '1', provider: 'x', project: { path: '/p', name: 'P' }, prompt: 'hi' },
    { type: 'session.list_stored', id: '1', provider: 'x' },
    { type: 'session.resume', id: '1', provider: 'x', native_id: 'n' },
    { type: 'session.end', id: '1', session: 's' },
    { type: 'interrupt.request', id: '1', session: 's' },
    { type: 'session.get_snapshot', id: '1', session: 's' },
    { type: 'session.get_history', id: '1', session: 's' },
    { type: 'message.send', id: '1', session: 's', text: '' },
    { type: 'permission.respond', id: '1', session: 's', permission: 'p', decision: 'deny', note: 'no' },
    { type: 'permission.respond', id: '1', session: 's', permission: 'p', decision: 'allow', option: 'suggested' },
    { type: 'question.answer', id: '1', session: 's', question: 'q', answers: [['A'], ['typed']] },
    { type: 'question.answer', id: '1', session: 's', question: 'q', response: 'free' },
    { type: 'ext.fake.thing', id: '1', session: 's', anything: [1, 2] },
  ]
  for (const m of good) assert.deepEqual(checkCommand(m), { ok: true, value: m }, m.type)
})

test('bad commands fail', () => {
  const bad: unknown[] = [
    null, [], 'text', 42, {},
    { type: 7 },
    { type: 'nope', id: '1' },
    { type: 'hello', protocol: 1, providers: [] },               // an event, not a command
    { type: 'session.created', session: {} },
    { type: 'message.send', session: 's', text: 'x' },           // no id
    { type: 'message.send', id: '', session: 's', text: 'x' },   // empty id
    { type: 'message.send', id: '1', session: 's', text: 1 },
    { type: 'message.send', id: '1', session: 's', text: 'x', extra: true },
    { type: 'permission.respond', id: '1', session: 's', permission: 'p', decision: 'always' },
    { type: 'permission.respond', id: '1', session: 's', permission: 'p', decision: 'allow', mode: 'auto' },  // C06's, replaced by option
    { type: 'permission.respond', id: '1', session: 's', permission: 'p', decision: 'allow', option: '' },
    { type: 'question.answer', id: '1', session: 's', question: 'q' },
    { type: 'question.answer', id: '1', session: 's', question: 'q', answers: [], response: 'x' },
    { type: 'session.create', id: '1', provider: 'Bad Name', project: { path: '/p' } },
    { type: 'session.create', id: '1', provider: 'x', project: { path: '/p', evil: 1 } },
    { type: 'ext.Bad.x', id: '1' },
    { type: 'ext.fake', id: '1' },
    { type: 'id' },
    { type: 'agent' },
  ]
  for (const m of bad) assert.equal(checkCommand(m).ok, false, JSON.stringify(m))
})

test('a permission\'s options: an id and a non-empty label each, at least one; C06\'s modes are gone', () => {
  const perm = (over: Record<string, unknown>) => ({
    type: 'permission.requested', session: 's', seq: 2,
    permission: { permission: 'p', agent: 'a', tool: 'Bash', summary: 'Run: x', ...over },
  })
  assert.equal(checkMessage(perm({ options: [{ option: 'suggested', label: 'Yes, and don\'t ask again for: x' }, { option: 'auto', label: 'Yes, and switch to auto mode' }] })).ok, true)
  for (const options of [[], [{ option: 'a' }], [{ option: 'a', label: '' }], [{ option: '', label: 'x' }], [{ option: 'a', label: 'x', updates: [] }], ['auto']]) {
    assert.equal(checkMessage(perm({ options })).ok, false, JSON.stringify(options))
  }
  assert.equal(checkMessage(perm({ modes: ['auto'] })).ok, false)
})

test('C16 step 6: an option\'s kind and parts, an error\'s, a notice\'s and a program\'s reason and details', () => {
  const perm = (option: Record<string, unknown>) => ({
    type: 'permission.requested', session: 's', seq: 2,
    permission: { permission: 'p', agent: 'a', tool: 'Bash', summary: 'Run: x', options: [{ option: 'o', label: 'Yes', ...option }] },
  })
  assert.equal(checkMessage(perm({ kind: 'allow_commands', parts: { commands: ['npm test *'] } })).ok, true)
  assert.equal(checkMessage(perm({ kind: 'allow_domain', parts: { domain: 'a.com' } })).ok, true)
  for (const bad of [{ kind: 'Allow' }, { kind: '' }, { parts: { commands: [] } }, { parts: { commands: [3] } }, { parts: { Commands: 'x' } }, { parts: { n: 3 } }]) {
    assert.equal(checkMessage(perm(bad)).ok, false, JSON.stringify(bad))
  }
  const error = (over: Record<string, unknown>) => ({ type: 'error', id: '1', code: 'provider_error', message: 'm', ...over })
  assert.equal(checkMessage(error({ reason: 'project_gone', details: { path: '/p' } })).ok, true)
  for (const bad of [{ reason: 'Gone' }, { details: { path: 3 } }, { details: { 'a-b': 'x' } }, { details: 'x' }]) {
    assert.equal(checkMessage(error(bad)).ok, false, JSON.stringify(bad))
  }
  const notice = { type: 'session.notice', session: 's', seq: 2, notice: { code: 'sign_in_needed', message: 'm', reason: 'signed_out', details: { command: '/login' } } }
  assert.equal(checkMessage(notice).ok, true)
  const program = (over: Record<string, unknown>) => ({ type: 'provider.program', provider: 'p', program: { path: null, set_by_hand: false, message: 'm', ...over } })
  assert.equal(checkMessage(program({ reason: 'too_old', details: { version: '1', minimum: '2' } })).ok, true)
  assert.equal(checkMessage({ type: 'provider.program', provider: 'p', program: { path: '/x', version: '1', set_by_hand: false, reason: 'too_old' } }).ok, false, 'a found program has none')
})

test('date-time format is enforced on events', () => {
  const ok = { type: 'session.snapshot', session: sessionWith({ started_at: '2026-09-29T10:00:00.000Z' }) }
  const bad = { type: 'session.snapshot', session: sessionWith({ started_at: 'yesterday' }) }
  assert.equal(checkMessage(ok).ok, true)
  assert.equal(checkMessage(bad).ok, false)
})

function sessionWith(over: Record<string, unknown>) {
  return {
    session: 's', seq: 1, provider: 'x', native_id: null, origin: 'app', project: { path: '/p' },
    title: null, started_at: '2026-09-29T10:00:00Z', capabilities: {}, extensions: [],
    agents: [{ agent: 'a', role: 'orchestrator', parent: null, state: 'idle', reason: null }],
    permissions: [], notices: [], ...over,
  }
}
