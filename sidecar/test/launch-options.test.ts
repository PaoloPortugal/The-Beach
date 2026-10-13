// Model, effort and mode at launch (C12), NOTES.md -> S02 -> Model, effort
// and mode at launch: what hello offers, the flags a choice becomes, the
// refusal of anything not offered, and the session's model and effort
// followed as the terminal shows them. Behaviour checked with `claude -p`
// 2.1.296 (2026-10-13): --model fires no PostModelSwitch, a resume without
// --model fires one (source "resume"), and plan mode answers a Haiku
// session's turns with Sonnet while the session's model stays Haiku.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { effortChoice, LAUNCH_OPTIONS, launchArgs, modelChoice } from '../src/providers/claude/launch-options.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { STATUS_PATH } from '../src/providers/claude/hook-server.ts'
import { REPORTED_HOOKS } from '../src/providers/claude/hooks.ts'
import { checkMessage } from '../src/protocol.ts'
import { FakeProvider } from './fake-provider.ts'
import { connect, RecordingLog, testServer, type Msg, tempSessionsDir } from './helpers.ts'

const tmp = (prefix: string) => fs.mkdtempSync(path.join(os.tmpdir(), prefix))

function post(port: number, auth: string, body: object, at = '/hook') {
  return new Promise<{ status: number; body: string }>((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: at,
      headers: { authorization: auth, 'content-type': 'application/json' } }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
}

function claude() {
  const launches: { args: string[] }[] = []
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.296' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launches.push(JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8'))); return 'fake' },
    projectsDir: tmp('projects-'),
  })
  return { p, launches }
}

// ---- the lists and the flags ----

test('the lists: aliases, effort levels without ultracode, the Shift+Tab four; never Bypass or Don\'t ask', () => {
  assert.deepEqual(LAUNCH_OPTIONS.model!.map((c) => c.id), ['opus', 'sonnet', 'haiku', 'fable'])
  assert.deepEqual(LAUNCH_OPTIONS.effort!.map((c) => c.id), ['low', 'medium', 'high', 'xhigh', 'max'])
  assert.deepEqual(LAUNCH_OPTIONS.mode!.map((c) => c.id), ['default', 'acceptEdits', 'plan', 'auto'])
  assert.deepEqual(LAUNCH_OPTIONS.mode!.map((c) => c.label), ['Manual', 'Accept edits', 'Plan', 'Auto'])
})

test('launchArgs: a flag per choice made, none for Default', () => {
  assert.deepEqual(launchArgs(undefined), [])
  assert.deepEqual(launchArgs({}), [])
  assert.deepEqual(launchArgs({ model: 'haiku' }), ['--model', 'haiku'])
  assert.deepEqual(launchArgs({ model: 'opus', effort: 'max', mode: 'plan' }),
    ['--model', 'opus', '--effort', 'max', '--permission-mode', 'plan'])
  // Not offered: dropped even if a caller skipped the sidecar's check.
  assert.deepEqual(launchArgs({ model: '--settings', effort: 'ultracode', mode: 'bypassPermissions' }), [])
})

test('modelChoice: Claude Code\'s ids in the user\'s words; others as they are; not-models null', () => {
  assert.deepEqual(modelChoice('claude-opus-5-5'), { id: 'claude-opus-5-5', label: 'Opus 5.5' })
  assert.deepEqual(modelChoice('claude-opus-5'), { id: 'claude-opus-5', label: 'Opus 5' })
  assert.deepEqual(modelChoice('claude-haiku-4-5-20251001'), { id: 'claude-haiku-4-5-20251001', label: 'Haiku 4.5' })
  assert.deepEqual(modelChoice('claude-sonnet-5-5[1m]'), { id: 'claude-sonnet-5-5[1m]', label: 'Sonnet 5.5 (1M context)' })
  assert.deepEqual(modelChoice('claude-fable-5-1'), { id: 'claude-fable-5-1', label: 'Fable 5.1' })
  assert.deepEqual(modelChoice('claude-mystery-9'), { id: 'claude-mystery-9', label: 'claude-mystery-9' })
  assert.deepEqual(modelChoice('gpt-x'), { id: 'gpt-x', label: 'gpt-x' })
  for (const not of ['', '<synthetic>', 'x'.repeat(201), null, 5, { id: 'claude-opus-5' }, 'gpt\nx', 'gpt\u202ex']) assert.equal(modelChoice(not), null)
})

test('effortChoice: the launch list\'s words; an unknown level as it is; not-levels null', () => {
  assert.deepEqual(effortChoice('xhigh'), { id: 'xhigh', label: 'Extra high' })
  assert.deepEqual(effortChoice('ultracode'), { id: 'ultracode', label: 'ultracode' })
  for (const not of ['', 'x'.repeat(51), undefined, 3, 'hi\u0007gh']) assert.equal(effortChoice(not), null)
})

test('PostModelSwitch is one of the reported hooks', () => {
  assert.ok((REPORTED_HOOKS as readonly string[]).includes('PostModelSwitch'))
})

// ---- through the sidecar ----

test('hello offers each provider\'s lists, if it has any; they fit the schema', async () => {
  const s = await testServer([claude().p, new FakeProvider({ id: 'plain' })])
  try {
    const c = await connect(s.port, s.token)
    const { hello } = await c.sync()
    const providers = hello.providers as { provider: string; launch_options?: unknown }[]
    assert.deepEqual(providers.find((p) => p.provider === 'claude')!.launch_options, LAUNCH_OPTIONS)
    assert.ok(!('launch_options' in providers.find((p) => p.provider === 'plain')!))
    assert.deepEqual(c.invalid, [])
    await c.close()
  } finally { await s.close() }
})

test('create: the choices become flags after ours; Default adds none', async () => {
  const { p, launches } = claude()
  const s = await testServer([p])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const project = { path: tmp('launch-') }
    assert.equal((await c.command({ type: 'session.create', provider: 'claude', project,
      launch: { model: 'haiku', effort: 'low', mode: 'plan' } })).type, 'ok')
    assert.deepEqual(launches[0]!.args.slice(6),
      ['--dangerously-load-development-channels', 'server:world-bridge', '--model', 'haiku', '--effort', 'low', '--permission-mode', 'plan'])
    assert.equal((await c.command({ type: 'session.create', provider: 'claude', project, launch: {} })).type, 'ok')
    assert.deepEqual(launches[1]!.args.slice(6), ['--dangerously-load-development-channels', 'server:world-bridge'])
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('a choice not offered is refused before anything starts: Bypass, Don\'t ask, ultracode, a full model id, a provider with no lists', async () => {
  const { p, launches } = claude()
  const plain = new FakeProvider({ id: 'plain' })
  const s = await testServer([p, plain])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const project = { path: tmp('refuse-') }
    for (const launch of [{ mode: 'bypassPermissions' }, { mode: 'dontAsk' }, { effort: 'ultracode' }, { model: 'claude-opus-5-5' }, { model: '--settings' }]) {
      const r = await c.command({ type: 'session.create', provider: 'claude', project, launch })
      assert.equal(r.type, 'error', JSON.stringify(launch))
      assert.equal(r.code, 'invalid_message')
      const resumed = await c.command({ type: 'session.resume', provider: 'claude', native_id: crypto.randomUUID(), launch })
      assert.equal(resumed.code, 'invalid_message', 'resume too, before looking the session up')
    }
    assert.equal(launches.length, 0, 'no terminal opened')
    const r = await c.command({ type: 'session.create', provider: 'plain', project, launch: { model: 'opus' } })
    assert.equal(r.code, 'invalid_message')
    assert.deepEqual(plain.launches, [])
    // The schema refuses what isn't a launch at all.
    assert.equal((await c.command({ type: 'session.create', provider: 'claude', project, launch: { colour: 'red' } })).code, 'invalid_message')
    assert.equal(launches.length, 0)
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('resume passes the choices on; none given, none passed', async () => {
  const fake = new FakeProvider({ launchOptions: LAUNCH_OPTIONS })
  const s = await testServer([fake])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    assert.equal((await c.command({ type: 'session.resume', provider: 'fake', native_id: 'a', launch: { effort: 'high' } })).type, 'ok')
    assert.equal((await c.command({ type: 'session.resume', provider: 'fake', native_id: 'b' })).type, 'ok')
    assert.equal((await c.command({ type: 'session.resume', provider: 'fake', native_id: 'c', launch: {} })).type, 'ok')
    assert.deepEqual(fake.launches, [{ effort: 'high' }, undefined, undefined])
    await c.close()
  } finally { await s.close() }
})

// ---- following the model and effort ----

/** A launched Claude session, not up yet: hooks and status lines go to it as Claude Code sends them. */
async function session() {
  const { p, launches } = claude()
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  await c.command({ type: 'session.create', provider: 'claude', project: { path: tmp('follow-') }, launch: { model: 'haiku' } })
  const args = launches[0]!.args
  const arg = (flag: string) => args[args.indexOf(flag) + 1]!
  const nativeId = arg('--session-id')
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.PreToolUse[0].hooks[0]
  const port = Number(new URL(h.url).port)
  const transcript = path.join(tmp('transcripts-'), `${nativeId}.jsonl`)
  fs.writeFileSync(transcript, '')
  const send = (name: string, fields: Record<string, unknown> = {}) => post(port, h.headers.Authorization, {
    session_id: nativeId, transcript_path: transcript, cwd: '/', hook_event_name: name, ...fields,
  })
  const status = (fields: Record<string, unknown>) =>
    post(port, h.headers.Authorization, { session_id: nativeId, transcript_path: transcript, cwd: '/', ...fields }, STATUS_PATH)
  const updated = (key: string) => (m: Msg) => m.type === 'session.updated' && key in m
  return { c, transcript, send, status, updated, close: async () => { await c.close(); await s.close(); await p.shutdown() } }
}

test('the model from SessionStart, PostModelSwitch and the status line; the effort from the orchestrator\'s hooks', { timeout: 20_000 }, async () => {
  const x = await session()
  try {
    // Before it's up: kept, and in the snapshot it comes up with. SessionStart
    // is relayed only for clear and resume, so a resume's.
    assert.deepEqual(await x.send('SessionStart', { source: 'resume', model: 'claude-haiku-5-5' }), { status: 200, body: '' })
    await x.send('Stop', { effort: { level: 'low' } })
    const created = (await x.c.next('session.created')).session as Record<string, unknown>
    assert.deepEqual(created.capabilities, { questions: {}, interrupt: { immediate: false }, permission_modes: {}, plans: {}, usage: {}, model_info: {} })
    assert.deepEqual(created.model, { id: 'claude-haiku-5-5', label: 'Haiku 5.5' })
    // The hook that brings it up is read once it's up: its effort follows.
    assert.equal(created.effort, null)
    assert.deepEqual((await x.c.next(x.updated('effort'))).effort, { id: 'low', label: 'Low' })

    // /model: PostModelSwitch, answered with nothing (its output would reach Claude).
    assert.deepEqual(await x.send('PostModelSwitch', { from_model: 'claude-haiku-5-5', to_model: 'claude-opus-5-5', source: 'command' }), { status: 200, body: '' })
    assert.deepEqual((await x.c.next(x.updated('model'))).model, { id: 'claude-opus-5-5', label: 'Opus 5.5' })
    // /effort: the next hook says so; a subagent's own level doesn't count.
    await x.send('PreToolUse', { tool_name: 'Read', tool_input: {}, tool_use_id: 'toolu_1', agent_id: 'sub1', effort: { level: 'max' } })
    await x.send('Stop', { effort: { level: 'xhigh' } })
    assert.deepEqual((await x.c.next(x.updated('effort'))).effort, { id: 'xhigh', label: 'Extra high' })
    // The status line: both, live.
    await x.status({ model: { id: 'claude-sonnet-5-5', display_name: 'Sonnet 5.5' }, effort: { level: 'medium' } })
    assert.deepEqual((await x.c.next(x.updated('model'))).model, { id: 'claude-sonnet-5-5', label: 'Sonnet 5.5' })
    assert.deepEqual((await x.c.next(x.updated('effort'))).effort, { id: 'medium', label: 'Medium' })
    // The same again, nonsense, and a reply's own model in the transcript change nothing.
    await x.status({ model: { id: 'claude-sonnet-5-5' }, effort: { level: 'medium' } })
    await x.send('PostModelSwitch', { to_model: '<synthetic>' })
    await x.send('Stop', { effort: { level: 7 } })
    fs.appendFileSync(x.transcript, JSON.stringify({ type: 'assistant', uuid: crypto.randomUUID(), timestamp: '2026-10-13T10:00:00Z',
      message: { id: 'm1', role: 'assistant', model: 'claude-opus-5-5', content: [{ type: 'text', text: 'planning' }],
        usage: { input_tokens: 1, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 } } }) + '\n')
    assert.deepEqual((await x.c.quiet(800)).filter((m) => m.type === 'session.updated'), [])
    await x.c.command({ type: 'session.get_snapshot', session: created.session })
    const snap = (await x.c.next('session.snapshot')).session as Record<string, unknown>
    assert.deepEqual([snap.model, snap.effort], [{ id: 'claude-sonnet-5-5', label: 'Sonnet 5.5' }, { id: 'medium', label: 'Medium' }])
    assert.deepEqual(x.c.invalid, [], 'every message fits the schema')
  } finally { await x.close() }
})

test('with none of them yet, model and effort come up null', { timeout: 20_000 }, async () => {
  const x = await session()
  try {
    await x.send('Stop')
    const created = (await x.c.next('session.created')).session as Record<string, unknown>
    assert.equal(created.model, null)
    assert.equal(created.effort, null)
  } finally { await x.close() }
})

// ---- the registry ----

test('registry: model and effort only with model_info; a mixed update keeps its other fields', async () => {
  const without = new FakeProvider({ capabilities: { permission_modes: {} } })
  const s = await testServer([without])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    await c.command({ type: 'session.create', provider: 'fake', project: { path: tmp('reg-') } })
    const created = (await c.next('session.created')).session as Record<string, unknown>
    assert.ok(!('model' in created) && !('effort' in created))
    const fs0 = without.sessions[0]!
    fs0.host.emit({ type: 'session.updated', model: { id: 'm', label: 'M' } })
    fs0.host.emit({ type: 'session.updated', mode: 'plan', effort: { id: 'low', label: 'Low' } })
    const got = (await c.quiet(200)).filter((m) => m.type === 'session.updated')
    assert.equal(got.length, 1)
    assert.equal(got[0]!.mode, 'plan')
    assert.ok(!('effort' in got[0]!))
    await c.close()
  } finally { await s.close() }
})

test('schema: launch_options, launch and model_info fields; bad ones refused', () => {
  const choice = { id: 'opus', label: 'Opus' }
  assert.equal(checkMessage({ type: 'session.create', id: 'c1', provider: 'claude', project: { path: '/p' }, launch: { model: 'opus' } }).ok, true)
  assert.equal(checkMessage({ type: 'session.create', id: 'c1', provider: 'claude', project: { path: '/p' }, launch: { model: '' } }).ok, false)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 1, model: choice }).ok, true)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 1, effort: null }).ok, true)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 1, model: null }).ok, false)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 1, model: { id: 'x' } }).ok, false)
  assert.equal(checkMessage({ type: 'hello', protocol: 1, providers: [{ provider: 'claude', name: 'C', launch_options: { mode: [] } }] }).ok, false)
})
