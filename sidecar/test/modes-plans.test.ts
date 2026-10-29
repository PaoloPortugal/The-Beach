// Permission modes (C06) and plan approval (C07), NOTES.md -> S02: the mode
// from the orchestrator's hooks, plans held like questions, and the switch
// to auto mode on Bash prompts, one of a prompt's options (C05) answered
// through its held hook (prompt-options.test.ts has the other options).
// Payloads and behaviour follow the C06/C07 spike (2026-10-02/03, claude
// 2.1.288): see docs/devlog/2026-10-02-c06-c07-spike.md.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { HookTranslator, MAIN, permissionReply } from '../src/providers/claude/hooks.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { AUTO_LABEL } from '../src/providers/claude/prompt-options.ts'
import { KEEP_PLANNING, NO_OPTION_ERROR } from '../src/providers/claude/session.ts'
import { FakeProvider } from './fake-provider.ts'
import { connect, RecordingLog, testServer, tempSessionsDir, bridgeOf } from './helpers.ts'

const CWD = path.resolve(os.tmpdir(), 'proj')
const hook = (name: string, fields: Record<string, unknown> = {}) =>
  ({ transcript_path: 'x', cwd: CWD, hook_event_name: name, ...fields })
const PLAN = { plan: '# Plan\n\nAdd `count` to notes.js.', planFilePath: 'C:\\plans\\p.md' }
const present = (id: string, mode = 'plan', extra: object = {}) =>
  hook('PreToolUse', { tool_name: 'ExitPlanMode', tool_input: PLAN, tool_use_id: id, permission_mode: mode, ...extra })
const heldPlan = (extra: object = {}) =>
  hook('PermissionRequest', { tool_name: 'ExitPlanMode', tool_input: PLAN, permission_mode: 'plan', ...extra })
const BASH = { command: 'node -e "1"', description: 'd' }
const bash = (id: string, mode: string) =>
  hook('PreToolUse', { tool_name: 'Bash', tool_input: BASH, tool_use_id: id, permission_mode: mode })
const heldBash = (mode: string) => hook('PermissionRequest', {
  tool_name: 'Bash', tool_input: BASH, permission_mode: mode,
  // What the spike saw: only "don't ask again", never a switch to auto.
  permission_suggestions: [{ type: 'addRules', rules: [{ toolName: 'Bash', ruleContent: BASH.command }], behavior: 'allow', destination: 'localSettings' }],
})
const DONT_ASK = { option: 'suggested', label: 'Yes, and don\'t ask again for: node -e "1"', kind: 'allow_commands', parts: { commands: ['node -e "1"'] } }
const TO_AUTO = { option: 'auto', label: AUTO_LABEL, kind: 'switch_mode', parts: { mode: 'auto' } }
const relayed = (request_id: string) => ({
  request_id, tool_name: 'Bash', description: 'd', input_preview: JSON.stringify(BASH, null, 1),
})
const prompt = (mode: string) => hook('UserPromptSubmit', { prompt: 'hi', permission_mode: mode })

// ---- the translator ----

test('mode: from the orchestrator\'s hooks, once per change; a subagent\'s and hooks without one are ignored', () => {
  const t = new HookTranslator(CWD)
  assert.deepEqual(t.noteMode(prompt('auto')), [{ type: 'session.updated', mode: 'auto' }])
  assert.deepEqual(t.noteMode(hook('Stop', { permission_mode: 'auto' })), [])
  assert.deepEqual(t.noteMode(hook('MessageDisplay', {})), [])
  assert.deepEqual(t.noteMode(hook('PreToolUse', { agent_id: 'sub', permission_mode: 'plan' })), [])
  assert.deepEqual(t.noteMode(prompt('default')), [{ type: 'session.updated', mode: 'default' }])
})

test('modes offered: a plan offers auto only once the session was seen in auto, else auto-accept edits', () => {
  const t = new HookTranslator(CWD)
  assert.deepEqual(t.planModes(), ['acceptEdits', 'default'])
  t.noteMode(prompt('default'))
  assert.deepEqual(t.switchModes('Bash'), [], 'auto never seen: no switch')
  t.noteMode(prompt('auto'))
  assert.deepEqual(t.planModes(), ['auto', 'default'])
  t.noteMode(prompt('default'))
  assert.deepEqual(t.switchModes('Bash'), ['auto'])
  assert.deepEqual(t.switchModes('Edit'), [], 'only Bash, as the terminal')
  assert.deepEqual(t.switchModes('Bash', 'acceptEdits'), ['auto'])
  assert.deepEqual(t.switchModes('Bash', 'plan'), [])
  assert.deepEqual(t.switchModes('Bash', 'auto'), [])
})

test('plan: its message comes first, then the call; held, answered in the world, then the call finishes once', () => {
  const t = new HookTranslator(CWD)
  assert.deepEqual(t.translate(present('toolu_p')), [
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
    { type: 'message.started', message: 'toolu_p:plan', agent: MAIN, role: 'assistant', kind: 'plan' },
    { type: 'message.completed', message: 'toolu_p:plan', text: PLAN.plan },
    { type: 'tool.started', tool_call: 'toolu_p', agent: MAIN, tool: 'ExitPlanMode', summary: 'Present the plan', input: PLAN },
  ])
  const asked = t.planAsked(heldPlan())!
  assert.equal(asked.plan, 'toolu_p')
  assert.deepEqual(asked.events, [
    { type: 'plan.asked', plan: { plan: 'toolu_p', agent: MAIN, text: PLAN.plan, modes: ['acceptEdits', 'default'] } },
    { type: 'agent.state_changed', agent: MAIN, state: 'waiting', reason: 'plan' },
  ])
  assert.deepEqual(t.planInput('toolu_p'), PLAN)
  assert.deepEqual(t.planAnswered('toolu_p', true), [
    { type: 'plan.resolved', plan: 'toolu_p', decision: 'approved', by: 'app' },
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
  ])
  assert.deepEqual(t.translate(hook('PostToolUse', { tool_name: 'ExitPlanMode', tool_use_id: 'toolu_p' })),
    [{ type: 'tool.finished', tool_call: 'toolu_p', status: 'ok' }])
})

test('plan: sent back from the world, the call is closed as denied (Claude Code sends no hook for it)', () => {
  const t = new HookTranslator(CWD)
  t.translate(present('toolu_p'))
  t.planAsked(heldPlan())
  assert.deepEqual(t.planAnswered('toolu_p', false), [
    { type: 'plan.resolved', plan: 'toolu_p', decision: 'rejected', by: 'app' },
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
    { type: 'tool.finished', tool_call: 'toolu_p', status: 'denied' },
  ])
})

test('plan: answered in the terminal, approved by its PostToolUse, sent back by the transcript or the turn ending', () => {
  const t = new HookTranslator(CWD)
  t.translate(present('toolu_a'))
  t.planAsked(heldPlan())
  assert.deepEqual(t.translate(hook('PostToolUse', { tool_name: 'ExitPlanMode', tool_use_id: 'toolu_a' })), [
    { type: 'plan.resolved', plan: 'toolu_a', decision: 'approved', by: 'external' },
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
    { type: 'tool.finished', tool_call: 'toolu_a', status: 'ok' },
  ])
  t.translate(present('toolu_b'))
  t.planAsked(heldPlan())
  assert.deepEqual(t.rejectedInTerminal('toolu_b'), [
    { type: 'plan.resolved', plan: 'toolu_b', decision: 'rejected', by: 'external' },
    { type: 'tool.finished', tool_call: 'toolu_b', status: 'denied' },
  ])
  t.translate(present('toolu_c'))
  t.planAsked(heldPlan())
  const ev = t.translate(hook('Stop', {}))
  assert.deepEqual(ev[0], { type: 'plan.resolved', plan: 'toolu_c', decision: 'rejected', by: 'external' })
})

test('plan: a malformed one isn\'t shown; without a PreToolUse it still is, with an id of its own', () => {
  assert.equal(new HookTranslator(CWD).planAsked(heldPlan({ tool_input: { plan: 3 } })), null)
  const lone = new HookTranslator(CWD).planAsked(heldPlan())!
  assert.match(lone.plan, /^[0-9a-f-]{36}$/)
})

test('a Bash prompt offers the switch to auto once auto was seen, after its suggestion; its hook is tied to its call', () => {
  const t = new HookTranslator(CWD)
  t.noteMode(prompt('auto'))
  t.noteMode(prompt('default'))
  t.translate(bash('toolu_b', 'default'))
  assert.equal(t.promptHooked({ ...heldBash('default'), tool_input: { command: 'other' } }), null, 'another input')
  assert.equal(t.promptHooked(heldBash('default')), 'toolu_b')
  const ev = t.permissionRequested(relayed('reqid'))!
  assert.deepEqual((ev[0] as any).permission.options, [DONT_ASK, TO_AUTO])
  assert.deepEqual(t.promptOption('reqid', 'auto'), {
    toolCall: 'toolu_b', input: BASH, updates: [{ type: 'setMode', mode: 'auto', destination: 'session' }],
  })
  assert.equal(t.promptOption('reqid', 'acceptEdits'), null)
  assert.equal(t.promptOption('other', 'auto'), null)

  // Asked in auto mode: no switch, only the suggestion.
  const u = new HookTranslator(CWD)
  u.noteMode(prompt('auto'))
  u.translate(bash('toolu_c', 'auto'))
  u.promptHooked(heldBash('auto'))
  assert.deepEqual((u.permissionRequested(relayed('reqid'))![0] as any).permission.options, [DONT_ASK])
})

test('replies: allow echoes the input, with a switch for this session only or an option\'s updates; deny carries the message', () => {
  assert.deepEqual(permissionReply({ behavior: 'allow', updatedInput: PLAN, mode: 'auto' }), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: {
      behavior: 'allow', updatedInput: PLAN,
      updatedPermissions: [{ type: 'setMode', mode: 'auto', destination: 'session' }],
    } },
  })
  const rule = { type: 'addRules', rules: [{ toolName: 'Bash', ruleContent: 'npm test' }], behavior: 'allow', destination: 'localSettings' }
  assert.deepEqual(permissionReply({ behavior: 'allow', updatedInput: BASH, updates: [rule] }), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow', updatedInput: BASH, updatedPermissions: [rule] } },
  })
  assert.deepEqual(permissionReply({ behavior: 'allow', updatedInput: BASH }), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow', updatedInput: BASH } },
  })
  assert.deepEqual(permissionReply({ behavior: 'deny', message: 'smaller' }), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'deny', message: 'smaller' } },
  })
})

// ---- the registry and commands (a fake provider) ----

test('registry: mode and plans only for sessions declaring them', async () => {
  const all: Record<string, Record<string, unknown>>[] = [{}, { permission_modes: {}, plans: {} }]
  for (const caps of all) {
    const p = new FakeProvider({ capabilities: caps })
    const s = await testServer([p])
    const c = await connect(s.port, s.token)
    try {
      await c.sync()
      await c.command({ type: 'session.create', provider: 'fake', project: { path: os.tmpdir() } })
      const session = (await c.next('session.created')).session as any
      const host = p.sessions[0]!.host
      const declared = 'plans' in caps
      assert.equal('mode' in session, declared)
      assert.equal('plans' in session, declared)
      if (declared) assert.equal(session.mode, null)
      assert.equal(host.emit({ type: 'session.updated', mode: 'plan' }), declared)
      assert.equal(host.emit({ type: 'message.started', message: 'm', agent: 'main', role: 'assistant', kind: 'plan' }), declared)
      assert.equal(host.emit({ type: 'plan.asked', plan: { plan: 'p1', agent: 'main', text: 't', modes: ['auto'] } }), declared)
      // A rename in the same event still goes out without the capability.
      assert.equal(host.emit({ type: 'session.updated', title: 'renamed', mode: 'auto' }), true)
      if (!declared) continue
      assert.equal(host.emit({ type: 'session.updated', mode: 'auto' }), false, 'nothing changed')
      assert.equal(host.emit({ type: 'plan.asked', plan: { plan: 'p1', agent: 'main', text: 't', modes: ['auto'] } }), false, 'already pending')
      const snap = (await c.command({ type: 'session.get_snapshot', session: host.id }), (await c.next('session.snapshot')).session as any)
      assert.equal(snap.mode, 'auto')
      assert.equal(snap.plans.length, 1)
      assert.ok(snap.plans[0].asked_at)
      assert.equal(host.emit({ type: 'plan.resolved', plan: 'p1', decision: 'approved', by: 'app' }), true)
      assert.equal(host.emit({ type: 'plan.resolved', plan: 'p1', decision: 'approved', by: 'app' }), false)
    } finally { await c.close(); await s.close() }
  }
})

test('commands: plan.answer\'s mode and a permission\'s option are checked against what was offered', async () => {
  const p = new FakeProvider({ capabilities: { permission_modes: {}, plans: {} } })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  try {
    await c.sync()
    await c.command({ type: 'session.create', provider: 'fake', project: { path: os.tmpdir() } })
    await c.next('session.created')
    const host = p.sessions[0]!.host
    const session = host.id
    host.emit({ type: 'plan.asked', plan: { plan: 'p1', agent: 'main', text: 't', modes: ['auto', 'default'] } })
    host.emit({ type: 'permission.requested', permission: { permission: 'r1', agent: 'main', tool: 'Bash', summary: 's', options: [TO_AUTO] } })
    host.emit({ type: 'permission.requested', permission: { permission: 'r2', agent: 'main', tool: 'Edit', summary: 's' } })
    const answer = (m: object) => c.command({ type: 'plan.answer', session, plan: 'p1', ...m })
    assert.equal((await answer({ approve: true })).code, 'invalid_message', 'approving needs a mode')
    assert.equal((await answer({ approve: false, mode: 'auto' })).code, 'invalid_message')
    assert.equal((await answer({ approve: true, mode: 'auto', note: 'x' })).code, 'invalid_message')
    assert.equal((await answer({ approve: true, mode: 'bypassPermissions' })).code, 'invalid_message', 'only offered modes')
    assert.equal((await c.command({ type: 'plan.answer', session, plan: 'nope', approve: false })).code, 'invalid_message')
    assert.equal((await answer({ approve: true, mode: 'default' })).type, 'ok')
    assert.equal((await answer({ approve: false, note: 'smaller' })).type, 'ok')
    const respond = (m: object) => c.command({ type: 'permission.respond', session, ...m })
    assert.equal((await respond({ permission: 'r1', decision: 'deny', option: 'auto' })).code, 'invalid_message')
    assert.equal((await respond({ permission: 'r2', decision: 'allow', option: 'auto' })).code, 'invalid_message', 'not offered on this one')
    assert.equal((await respond({ permission: 'r1', decision: 'allow', option: 'suggested' })).code, 'invalid_message')
    assert.equal((await respond({ permission: 'r1', decision: 'allow', mode: 'auto' })).code, 'invalid_message', 'C06\'s mode is gone')
    assert.equal((await respond({ permission: 'r1', decision: 'allow', option: 'auto' })).type, 'ok')
    assert.equal((await respond({ permission: 'r2', decision: 'allow' })).type, 'ok')
    assert.deepEqual(p.calls.filter((x) => x.method !== 'getHistory').map((x) => x.args), [
      ['p1', { approve: true, mode: 'default' }],
      ['p1', { approve: false, note: 'smaller' }],
      ['r1', 'allow', undefined, 'auto'],
      ['r2', 'allow', undefined],
    ])
  } finally { await c.close(); await s.close() }
})

test('commands: without the capabilities, plan.answer is not supported; a permission\'s options are core', async () => {
  const p = new FakeProvider({ capabilities: {} })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  try {
    await c.sync()
    await c.command({ type: 'session.create', provider: 'fake', project: { path: os.tmpdir() } })
    await c.next('session.created')
    const host = p.sessions[0]!.host
    host.emit({ type: 'permission.requested', permission: { permission: 'r1', agent: 'main', tool: 'Bash', summary: 's', options: [DONT_ASK] } })
    assert.equal((await c.command({ type: 'plan.answer', session: host.id, plan: 'p', approve: false })).code, 'not_supported')
    assert.equal((await c.command({ type: 'permission.respond', session: host.id, permission: 'r1', decision: 'allow', option: 'suggested' })).type, 'ok')
    assert.deepEqual(p.calls.filter((x) => x.method === 'respondPermission').map((x) => x.args), [['r1', 'allow', undefined, 'suggested']])
    assert.deepEqual(c.invalid, [])
  } finally { await c.close(); await s.close() }
})

// ---- through a Claude session ----

function post(port: number, auth: string, body: object) {
  let req!: http.ClientRequest
  const done = new Promise<{ status: number; body: string }>((resolve, reject) => {
    req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/hook',
      headers: { authorization: auth, 'content-type': 'application/json' } }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
  return { done, abort: () => req.destroy() }
}

async function liveSession() {
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.288' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'mp-')) } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.PermissionRequest[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  // Play the bridge.
  const sock = net.connect(bridgeOf(env).port, '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  const fromSidecar: any[] = []
  sock.setEncoding('utf8').on('data', (d: string) => fromSidecar.push(...d.trim().split('\n').map((l) => JSON.parse(l))))
  const toSidecar = (m: object) => sock.write(JSON.stringify(m) + '\n')
  toSidecar({ type: 'hello', token: bridgeOf(env).token })
  toSidecar({ type: 'ready' })
  const created = await c.next('session.created')
  const port = Number(new URL(h.url).port)
  return {
    c, id, created, fromSidecar, toSidecar,
    send: (body: object) => post(port, h.headers.Authorization, body),
    close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() },
  }
}

const decision = (r: { body: string }) => JSON.parse(r.body).hookSpecificOutput.decision
const stillHeld = (hold: { done: Promise<unknown> }) =>
  Promise.race([hold.done.then(() => 'answered'), new Promise((r) => setTimeout(() => r('held'), 150))])

test('through a session: declared; the mode starts unknown, then follows the hooks', async () => {
  const x = await liveSession()
  try {
    const session = x.created.session as any
    assert.equal(session.mode, null)
    assert.deepEqual(session.plans, [])
    assert.ok('permission_modes' in session.capabilities && 'plans' in session.capabilities)
    await x.send(prompt('auto')).done
    assert.equal((await x.c.next('session.updated')).mode, 'auto')
    await x.send(hook('Stop', { permission_mode: 'acceptEdits' })).done
    // (The prompt also named the session, in a session.updated of its own.)
    assert.equal((await x.c.next((m) => m.type === 'session.updated' && 'mode' in m)).mode, 'acceptEdits')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: a plan approved in the world echoes it back and switches mode', async () => {
  const x = await liveSession()
  try {
    await x.send(prompt('auto')).done
    await x.send(present('toolu_p')).done
    const message = await x.c.next((m) => m.type === 'message.started' && m.role === 'assistant')
    assert.deepEqual([message.message, message.kind], ['toolu_p:plan', 'plan'])
    const hold = x.send(heldPlan())
    const asked = (await x.c.next('plan.asked')).plan as any
    assert.deepEqual([asked.plan, asked.text, asked.modes], ['toolu_p', PLAN.plan, ['auto', 'default']])
    assert.equal(await stillHeld(hold), 'held')
    const bad = await x.c.command({ type: 'plan.answer', session: x.id, plan: 'toolu_p', approve: true, mode: 'acceptEdits' })
    assert.equal(bad.code, 'invalid_message', 'not offered: auto is available here')
    const ok = await x.c.command({ type: 'plan.answer', session: x.id, plan: 'toolu_p', approve: true, mode: 'auto' })
    assert.equal(ok.type, 'ok')
    assert.deepEqual(decision(await hold.done), {
      behavior: 'allow', updatedInput: PLAN, updatedPermissions: [{ type: 'setMode', mode: 'auto', destination: 'session' }],
    })
    const resolved = await x.c.next('plan.resolved')
    assert.deepEqual([resolved.decision, resolved.by], ['approved', 'app'])
    const history = await x.c.command({ type: 'session.get_history', session: x.id })
    const plan = (history.result as any).messages.find((m: any) => m.message === 'toolu_p:plan')
    assert.deepEqual([plan.kind, plan.text], ['plan', PLAN.plan], 'the plan stays in the chat')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: a plan sent back carries the note (or a default), and its call closes as denied', async () => {
  const x = await liveSession()
  try {
    for (const [id, note, message] of [['toolu_1', 'Call it noteCount', 'Call it noteCount'], ['toolu_2', '  ', KEEP_PLANNING]] as const) {
      await x.send(present(id)).done
      const hold = x.send(heldPlan())
      await x.c.next('plan.asked')
      assert.equal((await x.c.command({ type: 'plan.answer', session: x.id, plan: id, approve: false, note })).type, 'ok')
      assert.deepEqual(decision(await hold.done), { behavior: 'deny', message })
      assert.equal((await x.c.next('plan.resolved')).decision, 'rejected')
      const fin = await x.c.next('tool.finished')
      assert.deepEqual([fin.tool_call, fin.status], [id, 'denied'])
    }
  } finally { await x.close() }
})

test('through a session: a plan answered in the terminal lets go of the held hook with no decision', async () => {
  const x = await liveSession()
  try {
    await x.send(present('toolu_p')).done
    const hold = x.send(heldPlan())
    await x.c.next('plan.asked')
    await x.send(hook('PostToolUse', { tool_name: 'ExitPlanMode', tool_use_id: 'toolu_p', permission_mode: 'default' })).done
    assert.deepEqual(await hold.done, { status: 200, body: '' })
    const resolved = await x.c.next('plan.resolved')
    assert.deepEqual([resolved.decision, resolved.by], ['approved', 'external'])
    const late = await x.c.command({ type: 'plan.answer', session: x.id, plan: 'toolu_p', approve: false })
    assert.equal(late.code, 'invalid_message', 'no longer pending')
  } finally { await x.close() }
})

test('through a session: Claude Code dropping a held plan resolves it; a stop declines it', async () => {
  const x = await liveSession()
  try {
    await x.send(present('toolu_a')).done
    const a = x.send(heldPlan())
    a.done.catch(() => {})
    await x.c.next('plan.asked')
    a.abort()
    assert.equal((await x.c.next('plan.resolved')).by, 'external')
    await x.send(present('toolu_b')).done
    const b = x.send(heldPlan())
    await x.c.next('plan.asked')
    assert.equal((await x.c.command({ type: 'interrupt.request', session: x.id })).type, 'ok')
    const d = decision(await b.done)
    assert.equal(d.behavior, 'deny')
    assert.match(d.message, /stopped/)
    assert.deepEqual([(await x.c.next('plan.resolved')).by], ['app'])
  } finally { await x.close() }
})

test('through a session: a Bash prompt allowed with the switch to auto answers its held hook, not the relay', async () => {
  const x = await liveSession()
  try {
    await x.send(prompt('auto')).done
    await x.send(bash('toolu_b', 'default')).done
    x.toSidecar({ type: 'permission_request', ...relayed('reqid') })
    const hold = x.send(heldBash('default'))
    const requested = (await x.c.next('permission.requested')).permission as any
    assert.deepEqual(requested.options, [DONT_ASK, TO_AUTO])
    assert.equal(await stillHeld(hold), 'held')
    const ok = await x.c.command({ type: 'permission.respond', session: x.id, permission: 'reqid', decision: 'allow', option: 'auto' })
    assert.equal(ok.type, 'ok')
    assert.deepEqual(decision(await hold.done), {
      behavior: 'allow', updatedInput: BASH, updatedPermissions: [{ type: 'setMode', mode: 'auto', destination: 'session' }],
    })
    const resolved = await x.c.next('permission.resolved')
    assert.deepEqual([resolved.decision, resolved.by], ['allow', 'app'])
    assert.ok(!x.fromSidecar.some((m) => m.type === 'verdict'), 'Claude Code closes the relayed prompt itself')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: a plain answer to a held prompt goes through the relay; the hook is let go when the call ends', async () => {
  const x = await liveSession()
  try {
    await x.send(prompt('auto')).done
    await x.send(bash('toolu_b', 'default')).done
    x.toSidecar({ type: 'permission_request', ...relayed('reqid') })
    const hold = x.send(heldBash('default'))
    await x.c.next('permission.requested')
    assert.equal(await stillHeld(hold), 'held')
    assert.equal((await x.c.command({ type: 'permission.respond', session: x.id, permission: 'reqid', decision: 'allow' })).type, 'ok')
    await new Promise((r) => setTimeout(r, 50))
    assert.deepEqual(x.fromSidecar.filter((m) => m.type === 'verdict'), [{ type: 'verdict', request_id: 'reqid', behavior: 'allow' }])
    assert.equal(await stillHeld(hold), 'held', 'Claude Code keeps it open (spike)')
    await x.send(hook('PostToolUse', { tool_name: 'Bash', tool_use_id: 'toolu_b', permission_mode: 'default' })).done
    assert.deepEqual(await hold.done, { status: 200, body: '' })
  } finally { await x.close() }
})

test('through a session: no switch before auto was seen; no option once the hook is gone', async () => {
  const x = await liveSession()
  try {
    await x.send(prompt('default')).done
    await x.send(bash('toolu_1', 'default')).done
    x.toSidecar({ type: 'permission_request', ...relayed('reqaa') })
    const first = x.send(heldBash('default'))
    first.done.catch(() => {})
    assert.deepEqual(((await x.c.next('permission.requested')).permission as any).options, [DONT_ASK])
    const r = await x.c.command({ type: 'permission.respond', session: x.id, permission: 'reqaa', decision: 'allow', option: 'auto' })
    assert.equal(r.code, 'invalid_message')
    await x.send(hook('PostToolUse', { tool_name: 'Bash', tool_use_id: 'toolu_1' })).done
    assert.deepEqual(await first.done, { status: 200, body: '' }, 'let go when the call ended')

    await x.send(prompt('auto')).done
    await x.send(bash('toolu_2', 'acceptEdits')).done
    const hold = x.send(heldBash('acceptEdits'))
    hold.done.catch(() => {})
    await stillHeld(hold)
    x.toSidecar({ type: 'permission_request', ...relayed('reqbb') })
    assert.deepEqual(((await x.c.next('permission.requested')).permission as any).options, [DONT_ASK, TO_AUTO], 'hook before the relay')
    hold.abort()
    await new Promise((r) => setTimeout(r, 50))
    const gone = await x.c.command({ type: 'permission.respond', session: x.id, permission: 'reqbb', decision: 'allow', option: 'auto' })
    assert.deepEqual([gone.code, gone.message, gone.reason], ['provider_error', NO_OPTION_ERROR, 'option_unavailable'])
  } finally { await x.close() }
})
