// The permission relay (NOTES.md -> S02): prompts relayed by the channel,
// tied to their tool calls, answered from the world or in the terminal.
// Timings and shapes follow the S02 spike: PreToolUse, then about 100 ms
// later the relayed prompt; a world "deny" gets no tool hook at all.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { HookTranslator, MAIN, previewMatches } from '../src/providers/claude/hooks.ts'
import { ClaudeProvider, PERMISSION_MATCH_MS } from '../src/providers/claude/index.ts'
import type { SessionEvent } from '../src/protocol.ts'
import { connect, RecordingLog, testServer } from './helpers.ts'

const CWD = path.resolve(os.tmpdir(), 'proj')
const hook = (name: string, fields: Record<string, unknown> = {}) =>
  ({ session_id: 's', transcript_path: 'x', cwd: CWD, hook_event_name: name, ...fields })
const bash = (id: string, command: string, extra: Record<string, unknown> = {}) =>
  hook('PreToolUse', { tool_name: 'Bash', tool_input: { command, description: 'd' }, tool_use_id: id, ...extra })
const relayed = (request_id: string, command: string) => ({
  request_id, tool_name: 'Bash', description: 'd',
  // The relay's own spacing, as seen in the spike.
  input_preview: `{ "command": ${JSON.stringify(command)}, "description": "d" }`,
})
const types = (ev: SessionEvent[]) => ev.map((e) => {
  const x = e as any
  if (e.type === 'agent.state_changed') return `${x.agent}:${x.state}${x.reason ? `(${x.reason})` : ''}`
  if (e.type === 'permission.resolved') return `resolved ${x.permission} ${x.decision} by ${x.by}`
  if (e.type === 'tool.finished') return `finished ${x.tool_call} ${x.status}`
  if (e.type === 'permission.requested') return `requested ${x.permission.permission} for ${x.permission.agent}`
  return e.type
})

test('the input preview matches despite spacing and cut-offs, and only the same input', () => {
  const input = { command: 'echo spike-test-2 > perm2.txt', description: 'Write spike-test-2 to perm2.txt' }
  assert.ok(previewMatches('{ "command": "echo spike-test-2 > perm2.txt", "description": "Write spike-test-2 to perm2.txt" }', input))
  assert.ok(previewMatches('{ "command": "echo spike-test-2 > perm2.txt", "descri…', input))
  assert.ok(!previewMatches('{ "command": "echo other", "description": "Write spike-test-2 to perm2.txt" }', input))
  assert.ok(!previewMatches('{', input), 'too short to tell')
})

test('a prompt is tied to its tool call: agent, summary, input; waiting, then allowed from the world', () => {
  const t = new HookTranslator(CWD)
  t.translate(bash('toolu_1', 'echo hi > a.txt'))
  const req = t.permissionRequested(relayed('uxdpy', 'echo hi > a.txt'))!
  assert.deepEqual(req[0], {
    type: 'permission.requested',
    permission: { permission: 'uxdpy', agent: MAIN, tool: 'Bash', summary: 'Run: echo hi > a.txt', input: { command: 'echo hi > a.txt', description: 'd' } },
  })
  assert.deepEqual(types(req), ['requested uxdpy for main', 'main:waiting(permission)'])
  // The same relayed prompt twice changes nothing.
  assert.deepEqual(t.permissionRequested(relayed('uxdpy', 'echo hi > a.txt')), [])

  assert.deepEqual(types(t.permissionAnswered('uxdpy', 'allow')), ['resolved uxdpy allow by app', 'main:working'])
  // Then the call runs; it isn't resolved twice.
  assert.deepEqual(types(t.translate(hook('PostToolUse', { tool_name: 'Bash', tool_use_id: 'toolu_1' }))), ['finished toolu_1 ok'])
})

test('denied from the world: the call is closed as denied (Claude Code sends no hook for it)', () => {
  const t = new HookTranslator(CWD)
  t.translate(bash('toolu_1', 'rm -rf build'))
  t.permissionRequested(relayed('guhfx', 'rm -rf build'))
  assert.deepEqual(types(t.permissionAnswered('guhfx', 'deny')),
    ['resolved guhfx deny by app', 'finished toolu_1 denied', 'main:working'])
  assert.deepEqual(types(t.translate(hook('Stop', {}))), ['main:idle'])
  assert.deepEqual(t.permissionAnswered('guhfx', 'allow'), [], 'already answered')
})

test('allowed in the terminal: the call\'s PostToolUse resolves it (by external)', () => {
  const t = new HookTranslator(CWD)
  t.translate(bash('toolu_1', 'npm test'))
  t.permissionRequested(relayed('xburt', 'npm test'))
  assert.deepEqual(types(t.translate(hook('PostToolUseFailure', { tool_name: 'Bash', tool_use_id: 'toolu_1', error: 'Exit code 1' }))),
    ['resolved xburt allow by external', 'main:working', 'finished toolu_1 error'])
})

test('"No" in the terminal: resolved (deny, external) when the user types next, or the turn ends', () => {
  const t = new HookTranslator(CWD)
  t.translate(hook('UserPromptSubmit', { prompt: 'go' }))
  t.translate(bash('toolu_1', 'git push'))
  t.permissionRequested(relayed('wysdk', 'git push'))
  assert.deepEqual(types(t.translate(hook('UserPromptSubmit', { prompt: 'no, do it differently' }))),
    ['resolved wysdk deny by external', 'finished toolu_1 denied', 'message.started', 'message.completed', 'main:working'])

  t.translate(bash('toolu_2', 'git push -f'))
  t.permissionRequested(relayed('abcde', 'git push -f'))
  assert.deepEqual(types(t.translate(hook('Stop', {}))),
    ['resolved abcde deny by external', 'finished toolu_2 denied', 'main:idle'])
})

test('a subagent\'s prompt is the subagent\'s; a user message doesn\'t clear it, its stop does', () => {
  const t = new HookTranslator(CWD)
  t.translate(hook('SubagentStart', { agent_id: 'sub', agent_type: 'general-purpose' }))
  t.translate(bash('toolu_s', 'make', { agent_id: 'sub', agent_type: 'general-purpose' }))
  assert.deepEqual(types(t.permissionRequested(relayed('mxztk', 'make'))!), ['requested mxztk for sub', 'sub:waiting(permission)'])
  assert.ok(!types(t.translate(hook('UserPromptSubmit', { prompt: 'meanwhile' }))).some((x) => x.startsWith('resolved')))
  assert.deepEqual(types(t.translate(hook('SubagentStop', { agent_id: 'sub', agent_type: 'general-purpose' }))),
    ['resolved mxztk deny by external', 'finished toolu_s denied', 'sub:done'])
})

test('parallel calls of one tool: the prompt goes to the call whose input it shows', () => {
  const t = new HookTranslator(CWD)
  t.translate(bash('toolu_long', 'npm run build'))   // already allowed, still running
  t.translate(bash('toolu_new', 'npm publish'))
  t.translate(bash('toolu_other', 'ls'))
  t.permissionRequested(relayed('aaaaa', 'npm run build'))
  const ev = t.permissionAnswered('aaaaa', 'deny')
  assert.ok(types(ev).includes('finished toolu_long denied'), JSON.stringify(types(ev)))
  // With no preview match, the newest open call of that tool without a prompt.
  t.permissionRequested({ request_id: 'bbbbb', tool_name: 'Bash', description: 'x', input_preview: 'unreadable' })
  assert.ok(types(t.permissionAnswered('bbbbb', 'deny')).includes('finished toolu_other denied'))
})

test('a prompt with no tool call yet waits; forced, it is shown for the orchestrator from the preview', () => {
  const t = new HookTranslator(CWD)
  assert.equal(t.permissionRequested(relayed('ccccc', 'echo x')), null)
  const ev = t.permissionRequested(relayed('ccccc', 'echo x'), true)!
  assert.deepEqual(ev[0], {
    type: 'permission.requested',
    permission: { permission: 'ccccc', agent: MAIN, tool: 'Bash', summary: 'Run: echo x', input: { command: 'echo x', description: 'd' } },
  })
  const odd = t.permissionRequested({ request_id: 'ddddd', tool_name: 'WebFetch', description: 'Fetch a page', input_preview: 'cut off {' }, true)!
  assert.deepEqual((odd[0] as any).permission, { permission: 'ddddd', agent: MAIN, tool: 'WebFetch', summary: 'Fetch a page' })
  // Two prompts pending: answering one keeps the orchestrator waiting.
  assert.deepEqual(types(t.permissionAnswered('ccccc', 'allow')), ['resolved ccccc allow by app'])
  assert.deepEqual(types(t.permissionAnswered('ddddd', 'allow')), ['resolved ddddd allow by app', 'main:working'])
})

// ---- through a session: Godot, the provider, hooks and the bridge ----

function post(port: number, auth: string, body: object) {
  return new Promise<number>((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/hook',
      headers: { authorization: auth, 'content-type': 'application/json' } }, (res) => { res.resume(); resolve(res.statusCode!) })
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
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'perm-')) } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.PreToolUse[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  // Play the bridge.
  const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  const fromSidecar: any[] = []
  sock.setEncoding('utf8').on('data', (d: string) => fromSidecar.push(...d.trim().split('\n').map((l) => JSON.parse(l))))
  const toSidecar = (m: object) => sock.write(JSON.stringify(m) + '\n')
  toSidecar({ type: 'hello', token: env.BRIDGE_TOKEN })
  toSidecar({ type: 'ready' })
  await c.next('session.created')
  const hookPort = Number(new URL(h.url).port)
  return {
    c, id, fromSidecar, toSidecar,
    sendHook: (body: object) => post(hookPort, h.headers.Authorization, body),
    close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() },
  }
}

test('through a session: prompt shown in the world, answered there, the verdict goes down the bridge', async () => {
  const x = await liveSession()
  try {
    await x.sendHook(bash('toolu_1', 'echo hi > a.txt'))
    x.toSidecar({ type: 'permission_request', ...relayed('uxdpy', 'echo hi > a.txt') })
    const req = await x.c.next('permission.requested')
    assert.equal((req.permission as any).summary, 'Run: echo hi > a.txt')
    assert.equal((await x.c.next('agent.state_changed')).reason, 'permission')

    // A note can't travel with the verdict yet: refused, nothing sent.
    const noted = await x.c.command({ type: 'permission.respond', session: x.id, permission: 'uxdpy', decision: 'deny', note: 'use b.txt' })
    assert.equal(noted.code, 'not_supported')
    assert.deepEqual(x.fromSidecar, [])

    const r = await x.c.command({ type: 'permission.respond', session: x.id, permission: 'uxdpy', decision: 'allow' })
    assert.equal(r.type, 'ok')
    const resolved = await x.c.next('permission.resolved')
    assert.deepEqual([resolved.decision, resolved.by], ['allow', 'app'])
    for (let i = 0; i < 100 && x.fromSidecar.length === 0; i++) await new Promise((res) => setTimeout(res, 10))
    assert.deepEqual(x.fromSidecar, [{ type: 'verdict', request_id: 'uxdpy', behavior: 'allow' }])

    // Answering again, or an id that was never asked, is refused by the core.
    const again = await x.c.command({ type: 'permission.respond', session: x.id, permission: 'uxdpy', decision: 'deny' })
    assert.equal(again.code, 'invalid_message')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: a prompt whose PreToolUse arrives late is still tied to its call', async () => {
  const x = await liveSession()
  try {
    x.toSidecar({ type: 'permission_request', ...relayed('kateq', 'npm install') })
    await new Promise((res) => setTimeout(res, 50))
    await x.sendHook(bash('toolu_9', 'npm install', { agent_id: undefined }))
    const req = await x.c.next('permission.requested', PERMISSION_MATCH_MS + 2000)
    assert.equal((req.permission as any).agent, 'main')
    // Tied to the call: a deny from the world closes it.
    await x.c.command({ type: 'permission.respond', session: x.id, permission: 'kateq', decision: 'deny' })
    const fin = await x.c.next('tool.finished')
    assert.deepEqual([fin.tool_call, fin.status], ['toolu_9', 'denied'])
  } finally { await x.close() }
})
