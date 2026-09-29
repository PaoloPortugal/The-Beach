// The interrupt capability (NOTES.md -> S02, flows.md 6): a stop from the
// world lands at each busy agent's next tool call, which is denied with
// `continue: false`. Claude Code sends no hook for the stop itself.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { ClaudeProvider, STOP_REASON } from '../src/providers/claude/index.ts'
import { HookTranslator, MAIN } from '../src/providers/claude/hooks.ts'
import { connect, RecordingLog, testServer, type Msg } from './helpers.ts'

const CWD = path.resolve(os.tmpdir(), 'proj')
const hook = (name: string, fields: Record<string, unknown> = {}) =>
  ({ session_id: 's', transcript_path: 'x', cwd: CWD, hook_event_name: name, ...fields })
const tool = (id: string, extra: object = {}) =>
  hook('PreToolUse', { tool_name: 'Read', tool_input: { file_path: path.join(CWD, 'a') }, tool_use_id: id, ...extra })

test('translator: a stopped call is denied; the orchestrator goes idle, a subagent is interrupted', () => {
  const t = new HookTranslator(CWD)
  assert.equal(t.busy(), false)
  t.translate(hook('UserPromptSubmit', { prompt: 'go' }))
  t.translate(hook('MessageDisplay', { message_id: 'm', final: false, delta: 'Working on it\n' }))
  t.translate(tool('toolu_1'))
  assert.equal(t.busy(), true)
  assert.deepEqual(t.stopped(tool('toolu_1')), [
    { type: 'tool.finished', tool_call: 'toolu_1', status: 'denied' },
    { type: 'message.completed', message: 'm', text: 'Working on it\n' },
    { type: 'agent.state_changed', agent: MAIN, state: 'idle', reason: null },
  ])
  t.translate(hook('SubagentStart', { agent_id: 'sub', agent_type: 'Explore' }))
  t.translate(tool('toolu_2', { agent_id: 'sub' }))
  assert.deepEqual(t.stopped(tool('toolu_2', { agent_id: 'sub' })).slice(-1),
    [{ type: 'agent.state_changed', agent: 'sub', state: 'error', reason: 'interrupted' }])
  assert.equal(t.busy(), false)
})

// ---- through a session ----

function post(port: number, auth: string, body: object) {
  return new Promise<{ status: number; body: string }>((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/hook',
      headers: { authorization: auth, 'content-type': 'application/json' } }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
}

async function liveSession() {
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'stop-')) } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.PreToolUse[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  const fromSidecar: any[] = []
  sock.setEncoding('utf8').on('data', (d: string) => fromSidecar.push(...d.trim().split('\n').map((l) => JSON.parse(l))))
  const toSidecar = (m: object) => sock.write(JSON.stringify(m) + '\n')
  toSidecar({ type: 'hello', token: env.BRIDGE_TOKEN })
  toSidecar({ type: 'ready' })
  const created = await c.next('session.created')
  const port = Number(new URL(h.url).port)
  return {
    c, id, created, fromSidecar, toSidecar,
    send: (body: object) => post(port, h.headers.Authorization, body),
    close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() },
  }
}

const stateOf = (agent: string) => (m: Msg) => m.type === 'agent.state_changed' && m.agent === agent

test('through a session: declared; the next tool call of each busy agent is stopped, then things run again', async () => {
  const x = await liveSession()
  try {
    assert.deepEqual((x.created.session as any).capabilities.interrupt, { immediate: false })
    // Nothing running: a stop does nothing, and later calls run.
    assert.equal((await x.c.command({ type: 'interrupt.request', session: x.id })).type, 'ok')
    await x.send(hook('UserPromptSubmit', { prompt: 'go' }))
    assert.deepEqual(await x.send(tool('toolu_0')), { status: 200, body: '' })

    await x.send(hook('SubagentStart', { agent_id: 'sub', agent_type: 'Explore' }))
    assert.equal((await x.c.command({ type: 'interrupt.request', session: x.id })).type, 'ok')

    const r1 = await x.send(tool('toolu_1'))
    const out1 = JSON.parse(r1.body)
    assert.equal(out1.continue, false)
    assert.equal(out1.stopReason, STOP_REASON)
    assert.equal(out1.hookSpecificOutput.permissionDecision, 'deny')
    const denied = await x.c.next('tool.finished')
    assert.deepEqual([denied.tool_call, denied.status], ['toolu_1', 'denied'])
    assert.equal((await x.c.next(stateOf('main'))).state, 'idle')

    // The subagent was still busy, so its next call is stopped too...
    const r2 = await x.send(tool('toolu_2', { agent_id: 'sub' }))
    assert.equal(JSON.parse(r2.body).continue, false)
    const sub = await x.c.next(stateOf('sub'))
    assert.deepEqual([sub.state, sub.reason], ['error', 'interrupted'])
    // ...and then the stop is over.
    await x.send(hook('UserPromptSubmit', { prompt: 'again' }))
    assert.deepEqual(await x.send(tool('toolu_3')), { status: 200, body: '' })
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: a stop denies pending permission prompts, so they can\'t block it', async () => {
  const x = await liveSession()
  try {
    await x.send(hook('UserPromptSubmit', { prompt: 'go' }))
    await x.send(hook('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'make' }, tool_use_id: 'toolu_b' }))
    x.toSidecar({ type: 'permission_request', request_id: 'qwert', tool_name: 'Bash', description: 'd', input_preview: '{"command":"make"}' })
    await x.c.next('permission.requested')
    assert.equal((await x.c.command({ type: 'interrupt.request', session: x.id })).type, 'ok')
    const resolved = await x.c.next('permission.resolved')
    assert.deepEqual([resolved.permission, resolved.decision, resolved.by], ['qwert', 'deny', 'app'])
    for (let i = 0; i < 100 && x.fromSidecar.length === 0; i++) await new Promise((res) => setTimeout(res, 10))
    assert.deepEqual(x.fromSidecar, [{ type: 'verdict', request_id: 'qwert', behavior: 'deny' }])
  } finally { await x.close() }
})

test('through a session: a stop only applies to the turn it was asked in', async () => {
  const x = await liveSession()
  try {
    await x.send(hook('UserPromptSubmit', { prompt: 'go' }))
    await x.send(hook('SubagentStart', { agent_id: 'bg', agent_type: 'Explore' }))
    await x.c.command({ type: 'interrupt.request', session: x.id })
    assert.equal(JSON.parse((await x.send(tool('toolu_1'))).body).continue, false)
    // The background subagent is still working when the user starts a new
    // turn: that turn runs normally; the subagent is still stopped.
    await x.send(hook('UserPromptSubmit', { prompt: 'try again' }))
    assert.deepEqual(await x.send(tool('toolu_2')), { status: 200, body: '' })
    assert.equal(JSON.parse((await x.send(tool('toolu_b', { agent_id: 'bg' }))).body).continue, false)
    assert.deepEqual(await x.send(tool('toolu_4')), { status: 200, body: '' })

    // Stopped while the orchestrator was busy, but its turn ended on its own first.
    await x.c.command({ type: 'interrupt.request', session: x.id })
    await x.send(hook('Stop', {}))
    await x.send(hook('UserPromptSubmit', { prompt: 'and again' }))
    assert.deepEqual(await x.send(tool('toolu_3')), { status: 200, body: '' })
  } finally { await x.close() }
})

// Seen with claude -p (2.1.284): calls issued in the same batch as the
// stopped one still arrive, and would otherwise run.
test('through a session: the rest of a stopped batch is stopped too, silently, until the next turn', async () => {
  const x = await liveSession()
  try {
    await x.send(hook('UserPromptSubmit', { prompt: 'read and glob' }))
    await x.c.command({ type: 'interrupt.request', session: x.id })
    assert.equal(JSON.parse((await x.send(tool('toolu_read'))).body).continue, false)
    await x.c.next((m) => m.type === 'agent.state_changed' && m.agent === 'main' && m.state === 'idle')
    const glob = await x.send(hook('PreToolUse', { tool_name: 'Glob', tool_input: { pattern: '*.md' }, tool_use_id: 'toolu_glob' }))
    assert.equal(JSON.parse(glob.body).continue, false)
    const after = await x.c.quiet()
    assert.ok(!after.some((m) => m.type === 'tool.started' || m.type === 'agent.state_changed'), JSON.stringify(after.map((m) => m.type)))
    // The next turn runs normally.
    await x.send(hook('UserPromptSubmit', { prompt: 'go on' }))
    assert.deepEqual(await x.send(tool('toolu_next')), { status: 200, body: '' })
  } finally { await x.close() }
})
