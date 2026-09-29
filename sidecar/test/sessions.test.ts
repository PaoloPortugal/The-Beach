// The generic core with a fake provider: connecting, commands, events, seq,
// snapshots and the checks that keep provider mistakes away from Godot.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import os from 'node:os'
import path from 'node:path'
import { connect, testServer, type Client, type TestServer } from './helpers.ts'
import { FakeProvider } from './fake-provider.ts'
import { CommandError } from '../src/provider.ts'

const project = { path: os.tmpdir() }

async function setup(provider = new FakeProvider()): Promise<{ s: TestServer; c: Client; p: FakeProvider }> {
  const s = await testServer([provider])
  const c = await connect(s.port, s.token)
  await c.sync()
  return { s, c, p: provider }
}

async function teardown(s: TestServer, c: Client) {
  assert.deepEqual(c.invalid, [], 'every message matched the schema')
  await c.close()
  await s.close()
}

async function created(c: Client) {
  const reply = await c.command({ type: 'session.create', provider: 'fake', project })
  assert.equal(reply.type, 'ok', JSON.stringify(reply))
  // No startup notice from this provider: just the id.
  assert.deepEqual(Object.keys(reply.result as object), ['session'])
  const id = (reply.result as { session: string }).session
  const ev = await c.next('session.created')
  return { id, ev }
}

test('hello lists providers; sync is hello, snapshots, sync.completed', async () => {
  const { s, c } = await setup()
  try {
    const c2 = await connect(s.port, s.token)
    const { hello, snapshots } = await c2.sync()
    assert.deepEqual(hello, { type: 'hello', protocol: 1, providers: [{ provider: 'fake', name: 'Fake' }] })
    assert.equal(snapshots.length, 0)
    await c2.close()
  } finally { await teardown(s, c) }
})

test('create: ok with the session id comes before session.created', async () => {
  const { s, c, p } = await setup()
  try {
    const reply = await c.command({ type: 'session.create', provider: 'fake', project })
    // The fake announces inside create(), before the reply is sent; the
    // registry holds its events until the ok is out.
    const all = await c.quiet()
    assert.equal(reply.type, 'ok')
    const id = (reply.result as { session: string }).session
    assert.equal(all[0]?.type, 'session.created')
    const session = all[0]!.session as Record<string, unknown>
    assert.equal(session.session, id)
    assert.equal(session.seq, 1)
    assert.equal(session.provider, 'fake')
    assert.equal(session.origin, 'app')
    assert.deepEqual(session.project, { path: path.resolve(project.path), name: path.basename(path.resolve(project.path)) })
    assert.equal(p.sessions.length, 1)
  } finally { await teardown(s, c) }
})

test('create refuses unknown providers and bad project paths', async () => {
  const { s, c } = await setup()
  try {
    const cases: [Record<string, unknown>, string][] = [
      [{ provider: 'nope', project }, 'unknown_provider'],
      [{ provider: 'fake', project: { path: 'relative/dir' } }, 'invalid_project'],
      [{ provider: 'fake', project: { path: path.join(os.tmpdir(), 'does-not-exist-' + Date.now()) } }, 'invalid_project'],
      [{ provider: 'fake', project: { path: path.resolve(import.meta.filename) } }, 'invalid_project'],
    ]
    for (const [fields, code] of cases) {
      const r = await c.command({ type: 'session.create', ...fields })
      assert.equal(r.type, 'error')
      assert.equal(r.code, code, JSON.stringify(fields))
    }
  } finally { await teardown(s, c) }
})

test('a failed create is an error and leaves no session behind', async () => {
  const { s, c } = await setup(new FakeProvider({ failCreate: new CommandError('provider_error', 'could not launch') }))
  try {
    const r = await c.command({ type: 'session.create', provider: 'fake', project })
    assert.deepEqual({ type: r.type, code: r.code, message: r.message },
      { type: 'error', code: 'provider_error', message: 'could not launch' })
    assert.equal(s.registry.snapshots().length, 0)
    assert.deepEqual(await c.quiet(), [])
  } finally { await teardown(s, c) }
})

test('unexpected provider errors are reported without their details', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    p.failNext = new Error('secret internal detail')
    const r = await c.command({ type: 'message.send', session: id, text: 'hi' })
    assert.equal(r.type, 'error')
    assert.equal(r.code, 'provider_error')
    assert.ok(!String(r.message).includes('secret'))
  } finally { await teardown(s, c) }
})

test('events get per-session seq numbers, starting after session.created', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    const a = await created(c)
    const b = await created(c)
    const [fa, fb] = p.sessions.map((x) => x.host)
    fa!.emit({ type: 'agent.state_changed', agent: 'main', state: 'working', reason: null })
    fb!.emit({ type: 'agent.state_changed', agent: 'main', state: 'working', reason: null })
    fa!.emit({ type: 'message.started', message: 'm1', agent: 'main', role: 'assistant' })
    const got = await c.quiet()
    assert.deepEqual(got.map((m) => [m.session, m.seq]), [[a.id, 2], [b.id, 2], [a.id, 3]])
  } finally { await teardown(s, c) }
})

test('a snapshot reflects every event and carries the current seq', async () => {
  const p = new FakeProvider({ capabilities: { questions: {} } })
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    const h = p.sessions[0]!.host
    h.emit({ type: 'agent.spawned', agent: { agent: 'sub1', role: 'subagent', parent: 'main', name: 'Explore', task: 'look', state: 'working', reason: null } })
    h.emit({ type: 'permission.requested', permission: { permission: 'p1', agent: 'sub1', tool: 'Bash', summary: 'Run: ls' } })
    h.emit({ type: 'agent.state_changed', agent: 'sub1', state: 'waiting', reason: 'permission' })
    h.emit({ type: 'question.asked', question: { question: 'q1', agent: 'main', items: [{ text: 'Which?', options: [{ label: 'A' }], multi_select: false }] } })
    h.emit({ type: 'question.resolved', question: 'q1', by: 'external' })
    await c.quiet()
    c.received.length = 0

    // A fresh connection gets the same state as a snapshot.
    const c2 = await connect(s.port, s.token)
    const { snapshots } = await c2.sync()
    assert.equal(snapshots.length, 1)
    const snap = snapshots[0]!.session as Record<string, unknown>
    assert.equal(snap.session, id)
    assert.equal(snap.seq, 6)
    assert.deepEqual((snap.agents as { agent: string; state: string }[]).map((a) => [a.agent, a.state]),
      [['main', 'idle'], ['sub1', 'waiting']])
    assert.deepEqual((snap.permissions as { permission: string }[]).map((x) => x.permission), ['p1'])
    assert.deepEqual(snap.questions, [])
    assert.deepEqual(c2.invalid, [])

    // Events continue from the snapshot's seq.
    h.emit({ type: 'permission.resolved', permission: 'p1', decision: 'allow', by: 'external' })
    const next = await c2.next('permission.resolved')
    assert.equal(next.seq, 7)
    await c2.close()
  } finally { await teardown(s, c) }
})

test('get_snapshot answers ok, then the snapshot', async () => {
  const { s, c } = await setup()
  try {
    const { id } = await created(c)
    const r = await c.command({ type: 'session.get_snapshot', session: id })
    assert.equal(r.type, 'ok')
    const snap = await c.next(() => true)
    assert.equal(snap.type, 'session.snapshot')
    assert.equal((snap.session as { session: string }).session, id)
  } finally { await teardown(s, c) }
})

test('a new connection replaces the old one; the old one gets nothing more', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    await created(c)
    const closed = new Promise<number>((resolve) => c.ws.once('close', (code) => resolve(code)))
    const c2 = await connect(s.port, s.token)
    await c2.sync()
    assert.equal(await closed, 4000)
    p.sessions[0]!.host.emit({ type: 'agent.state_changed', agent: 'main', state: 'working', reason: null })
    assert.equal((await c2.next('agent.state_changed')).seq, 2)
    await c2.close()
  } finally { await teardown(s, c) }
})

test('commands reach the provider session', async () => {
  const p = new FakeProvider({ capabilities: { questions: {}, interrupt: { immediate: false } } })
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    const h = p.sessions[0]!.host
    h.emit({ type: 'permission.requested', permission: { permission: 'p1', agent: 'main', tool: 'Bash', summary: 'Run: ls' } })
    h.emit({ type: 'question.asked', question: { question: 'q1', agent: 'main', items: [{ text: 'Which?', options: [{ label: 'A' }], multi_select: false }] } })
    await c.quiet()
    const ok = async (cmd: Record<string, unknown>) => assert.equal((await c.command(cmd)).type, 'ok', JSON.stringify(cmd))
    await ok({ type: 'message.send', session: id, text: 'hello' })
    await ok({ type: 'permission.respond', session: id, permission: 'p1', decision: 'deny', note: 'not now' })
    await ok({ type: 'question.answer', session: id, question: 'q1', answers: [['A']] })
    await ok({ type: 'interrupt.request', session: id })
    const history = await c.command({ type: 'session.get_history', session: id })
    assert.deepEqual(history.result, { messages: [] })
    await ok({ type: 'session.end', session: id })
    assert.deepEqual(p.calls.map((x) => [x.method, x.args]), [
      ['sendMessage', ['hello']],
      ['respondPermission', ['p1', 'deny', 'not now']],
      ['answerQuestion', ['q1', { answers: [['A']] }]],
      ['interrupt', []],
      ['getHistory', []],
      ['end', []],
    ])
    const ended = await c.next('session.ended')
    assert.equal(ended.reason, 'user')
  } finally { await teardown(s, c) }
})

test('unknown sessions, ended sessions and unpending ids are refused', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    const code = async (cmd: Record<string, unknown>) => (await c.command(cmd)).code
    assert.equal(await code({ type: 'message.send', session: 'nope', text: 'x' }), 'unknown_session')
    assert.equal(await code({ type: 'permission.respond', session: id, permission: 'nope', decision: 'allow' }), 'invalid_message')
    p.sessions[0]!.host.end('exited')
    assert.equal((await c.next('session.ended')).reason, 'exited')
    assert.equal(await code({ type: 'message.send', session: id, text: 'x' }), 'unknown_session')
    assert.equal(await code({ type: 'session.get_snapshot', session: id }), 'unknown_session')
    // Nothing is sent for a session after it ends.
    assert.equal(p.sessions[0]!.host.emit({ type: 'agent.state_changed', agent: 'main', state: 'working', reason: null }), false)
    assert.deepEqual(await c.quiet(), [])
    assert.equal(s.registry.snapshots().length, 0)
  } finally { await teardown(s, c) }
})

test('commands for a session that has not come up yet are refused', async () => {
  const p = new FakeProvider({ announceOnCreate: false })
  const { s, c } = await setup(p)
  try {
    const r = await c.command({ type: 'session.create', provider: 'fake', project })
    const id = (r.result as { session: string }).session
    assert.equal((await c.command({ type: 'message.send', session: id, text: 'x' })).code, 'session_starting')
    assert.equal((await c.command({ type: 'session.get_snapshot', session: id })).code, 'session_starting')
    // Not in snapshots until it comes up.
    assert.equal(s.registry.snapshots().length, 0)
    p.sessions[0]!.announce()
    assert.equal((await c.next('session.created')).type, 'session.created')
    assert.equal((await c.command({ type: 'message.send', session: id, text: 'x' })).type, 'ok')
  } finally { await teardown(s, c) }
})

test('a session that never comes up still gets session.ended', async () => {
  const p = new FakeProvider({ announceOnCreate: false })
  const { s, c } = await setup(p)
  try {
    const r = await c.command({ type: 'session.create', provider: 'fake', project })
    const id = (r.result as { session: string }).session
    p.sessions[0]!.host.end('error')
    const ended = await c.next('session.ended')
    assert.deepEqual(ended, { type: 'session.ended', session: id, seq: 1, reason: 'error' })
  } finally { await teardown(s, c) }
})

test('capability commands and events are refused unless declared', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    assert.equal((await c.command({ type: 'interrupt.request', session: id })).code, 'not_supported')
    assert.equal((await c.command({ type: 'question.answer', session: id, question: 'q', response: 'x' })).code, 'not_supported')
    const h = p.sessions[0]!.host
    assert.equal(h.emit({ type: 'question.asked', question: { question: 'q1', agent: 'main', items: [{ text: 'Q', options: [], multi_select: false }] } }), false)
    assert.equal(h.emit({ type: 'ext.fake.ping' }), false)
    assert.deepEqual(await c.quiet(), [])
  } finally { await teardown(s, c) }
})

test('extension commands and events work only for declared namespaces', async () => {
  const p = new FakeProvider({ extensions: ['fake'] })
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    const r = await c.command({ type: 'ext.fake.ping', session: id })
    assert.deepEqual(r.result, { echoed: 'ext.fake.ping' })
    assert.equal((await c.command({ type: 'ext.other.ping', session: id })).code, 'not_supported')
    assert.equal((await c.command({ type: 'ext.fake.ping' })).code, 'not_supported')
    assert.equal(p.sessions[0]!.host.emit({ type: 'ext.fake.pong', data: 1 }), true)
    const ev = await c.next('ext.fake.pong')
    assert.deepEqual(ev, { type: 'ext.fake.pong', session: id, seq: 2, data: 1 })
  } finally { await teardown(s, c) }
})

test('provider events that don\'t fit are dropped without a seq gap', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    await created(c)
    const h = p.sessions[0]!.host
    const refused = [
      h.emit({ type: 'agent.state_changed', agent: 'ghost', state: 'working', reason: null }),
      h.emit({ type: 'agent.state_changed', agent: 'main', state: 'done', reason: null }),
      h.emit({ type: 'agent.spawned', agent: { agent: 's', role: 'subagent', parent: 'ghost', state: 'working', reason: null } }),
      h.emit({ type: 'agent.spawned', agent: { agent: 'main', role: 'subagent', parent: 'main', state: 'working', reason: null } }),
      h.emit({ type: 'agent.spawned', agent: { agent: 's', role: 'subagent', parent: 'main', state: 'idle', reason: null } }),
      h.emit({ type: 'agent.spawned', agent: { agent: 'o2', role: 'orchestrator', parent: null, state: 'idle', reason: null } }),
      h.emit({ type: 'permission.resolved', permission: 'nope', decision: 'allow', by: 'app' }),
      h.emit({ type: 'message.started', message: 'm', agent: 'ghost', role: 'assistant' }),
      h.emit({ type: 'tool.finished', tool_call: 't', status: 'maybe' } as never),
      h.emit({ type: 'message.delta', message: 'm' } as never),
    ]
    assert.deepEqual(refused, refused.map(() => false))
    assert.equal(h.emit({ type: 'agent.state_changed', agent: 'main', state: 'working', reason: null }), true)
    const got = await c.quiet()
    assert.deepEqual(got.map((m) => [m.type, m.seq]), [['agent.state_changed', 2]])
    assert.ok(s.log.lines.filter((l) => l.startsWith('warn dropped')).length === refused.length)
  } finally { await teardown(s, c) }
})

test('invalid and non-command messages get protocol errors', async () => {
  const { s, c } = await setup()
  try {
    c.send('not json')
    assert.deepEqual(await c.next('error'), { type: 'error', code: 'invalid_message', message: 'not valid JSON' })
    c.send({ type: 'hello', protocol: 1, providers: [] })
    const e1 = await c.next('error')
    assert.equal(e1.code, 'invalid_message')
    assert.equal(e1.id, undefined)
    c.send({ type: 'message.send', id: 'k1', session: 's', text: 5 })
    const e2 = await c.next('error')
    assert.equal(e2.id, 'k1')
    c.send({ type: 'ext.fake.ping', session: 's' })
    assert.equal((await c.next('error')).message, 'commands need an id')
    c.ws.send(Buffer.from([1, 2, 3]))
    assert.equal((await c.next('error')).code, 'invalid_message')
    // Still connected and working afterwards.
    assert.equal((await c.command({ type: 'session.list_stored', provider: 'fake' })).type, 'ok')
  } finally { await teardown(s, c) }
})

test('list_stored filters by project', async () => {
  const p = new FakeProvider()
  p.stored = [
    { provider: 'fake', native_id: 'a', project: { path: '/one' }, title: null, updated_at: '2026-09-29T10:00:00Z' },
    { provider: 'fake', native_id: 'b', project: { path: '/two' }, title: 'B', updated_at: '2026-09-29T09:00:00Z' },
  ]
  const { s, c } = await setup(p)
  try {
    const all = await c.command({ type: 'session.list_stored', provider: 'fake' })
    assert.equal((all.result as { sessions: unknown[] }).sessions.length, 2)
    const one = await c.command({ type: 'session.list_stored', provider: 'fake', project: '/two' })
    assert.deepEqual((one.result as { sessions: { native_id: string }[] }).sessions.map((x) => x.native_id), ['b'])
  } finally { await teardown(s, c) }
})

test('resume works like create', async () => {
  const { s, c } = await setup()
  try {
    const r = await c.command({ type: 'session.resume', provider: 'fake', native_id: 'old' })
    assert.equal(r.type, 'ok')
    const ev = await c.next('session.created')
    assert.equal((ev.session as { session: string }).session, (r.result as { session: string }).session)
  } finally { await teardown(s, c) }
})

test('events a command causes come after its reply', async () => {
  const p = new FakeProvider()
  const { s, c } = await setup(p)
  try {
    const { id } = await created(c)
    const fake = p.sessions[0]!
    // A provider that reacts inside the command, before it returns.
    fake.sendMessage = async () => {
      fake.host.emit({ type: 'message.started', message: 'u1', agent: 'main', role: 'user' })
    }
    c.send({ type: 'message.send', id: 'm', session: id, text: 'hi' })
    assert.deepEqual((await c.quiet()).map((m) => m.type), ['ok', 'message.started'])
    c.received.length = 0
    // Overlapping commands: events wait until both are answered.
    c.send({ type: 'message.send', id: 'm2', session: id, text: 'hi' })
    c.send({ type: 'session.end', id: 'e', session: id })
    assert.deepEqual((await c.quiet()).map((m) => m.type), ['ok', 'ok', 'message.started', 'session.ended'])
  } finally { await teardown(s, c) }
})

test('a create that fails after coming up: error first, then created and ended', async () => {
  const p = new FakeProvider()
  p.create = async (host, options) => {
    const { FakeSession } = await import('./fake-provider.ts')
    new FakeSession(p, host, options.project).announce()
    throw new CommandError('provider_error', 'broke after starting')
  }
  const { s, c } = await setup(p)
  try {
    c.send({ type: 'session.create', id: 'k', provider: 'fake', project })
    const got = await c.quiet()
    assert.deepEqual(got.map((m) => m.type), ['error', 'session.created', 'session.ended'])
    assert.equal(got[2]!.reason, 'error')
    assert.equal(s.registry.snapshots().length, 0)
  } finally { await teardown(s, c) }
})
