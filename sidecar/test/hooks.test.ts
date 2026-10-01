// Claude Code's hooks: the settings we launch with, the hook endpoint's
// security, the translation into generic events (payloads shaped like the
// ones Claude Code 2.1.284 sent in the S02 spike), and hooks reaching Godot
// through a real session.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import { HookServer, MAX_HOOK_BODY } from '../src/providers/claude/hook-server.ts'
import {
  HookTranslator, hookSettings, MAIN, parseHandback, parseTaskNotification, REPORTED_HOOKS, summarizeTool, unwrapChannel,
} from '../src/providers/claude/hooks.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import type { SessionEvent } from '../src/protocol.ts'
import { connect, RecordingLog, testServer } from './helpers.ts'

const CWD = path.resolve(os.tmpdir(), 'proj')

/** A hook payload with the fields every hook carries. */
function hook(name: string, fields: Record<string, unknown> = {}) {
  return {
    session_id: '1ee19967-3f2a-446d-9218-ab534db66409', transcript_path: 'x.jsonl', cwd: CWD,
    prompt_id: 'p1', permission_mode: 'default', hook_event_name: name, ...fields,
  }
}

function run(t: HookTranslator, ...hooks: ReturnType<typeof hook>[]): SessionEvent[] {
  return hooks.flatMap((h) => t.translate(h))
}

const states = (events: SessionEvent[]) => events
  .filter((e) => e.type === 'agent.state_changed')
  .map((e) => `${(e as any).agent}:${(e as any).state}${(e as any).reason ? `(${(e as any).reason})` : ''}`)

// ---- settings ----

test('settings: every reported hook posts to our URL with the token; short timeouts', () => {
  const s = hookSettings('http://127.0.0.1:5/hook', 'a'.repeat(64))
  assert.deepEqual(Object.keys(s.hooks).sort(), ['MessageDisplay', 'PermissionRequest', ...REPORTED_HOOKS].sort())
  for (const [name, groups] of Object.entries(s.hooks)) {
    const h = (groups as any)[0].hooks[0]
    assert.deepEqual(h, {
      type: 'http', url: 'http://127.0.0.1:5/hook',
      timeout: name === 'MessageDisplay' ? 2 : name === 'PermissionRequest' ? 86400 : 5,
      headers: { Authorization: `Bearer ${'a'.repeat(64)}` },
    }, name)
  }
  // PermissionRequest only for questions, which are held; plain prompts
  // come through the channel's relay.
  assert.equal((s.hooks.PermissionRequest as any)[0].matcher, '^AskUserQuestion$')
  assert.equal((s.hooks.PermissionRequest as any).length, 1)
  assert.ok(!('SessionStart' in s.hooks), 'SessionStart can\'t be an HTTP hook')
})

test('settings: agent view is off, so the conversation can\'t move to a background session', () => {
  const s = hookSettings('http://127.0.0.1:5/hook', 'a'.repeat(64))
  assert.deepEqual(Object.keys(s).sort(), ['disableAgentView', 'hooks'])
  assert.equal(s.disableAgentView, true)
})

// ---- translation ----

test('a plain turn: user message, streamed reply, tool call, idle', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('UserPromptSubmit', { prompt_id: 'u1', prompt: 'list the files' }),
    hook('MessageDisplay', { turn_id: 't', message_id: 'm1', index: 0, final: false, delta: 'Looking.\n\n' }),
    hook('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'ls -la\necho hi' }, tool_use_id: 'toolu_1' }),
    hook('PostToolUse', { tool_name: 'Bash', tool_input: {}, tool_response: {}, tool_use_id: 'toolu_1' }),
    hook('MessageDisplay', { turn_id: 't', message_id: 'm1', index: 1, final: true, delta: 'Two files.' }),
    hook('Stop', { last_assistant_message: 'Looking.\n\nTwo files.' }),
  )
  assert.deepEqual(ev, [
    { type: 'message.started', message: 'u1', agent: MAIN, role: 'user' },
    { type: 'message.completed', message: 'u1', text: 'list the files' },
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
    { type: 'message.started', message: 'm1', agent: MAIN, role: 'assistant' },
    { type: 'message.delta', message: 'm1', text: 'Looking.\n\n' },
    { type: 'tool.started', tool_call: 'toolu_1', agent: MAIN, tool: 'Bash', summary: 'Run: ls -la',
      input: { command: 'ls -la\necho hi' } },
    { type: 'tool.finished', tool_call: 'toolu_1', status: 'ok' },
    { type: 'message.completed', message: 'm1', text: 'Looking.\n\nTwo files.' },
    { type: 'agent.state_changed', agent: MAIN, state: 'idle', reason: null },
  ])
})

test('a one-batch reply is started and completed; the docs\' message_text shape works too', () => {
  const t = new HookTranslator(CWD)
  assert.deepEqual(run(t, hook('MessageDisplay', { message_id: 'm', index: 0, final: true, delta: 'OK' })), [
    { type: 'message.started', message: 'm', agent: MAIN, role: 'assistant' },
    { type: 'message.completed', message: 'm', text: 'OK' },
  ])
  assert.deepEqual(run(t, hook('MessageDisplay', { message_id: 'n', message_text: 'Whole' })), [
    { type: 'message.started', message: 'n', agent: MAIN, role: 'assistant' },
    { type: 'message.completed', message: 'n', text: 'Whole' },
  ])
})

test('a reply cut off before its final batch is completed when the turn ends', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('UserPromptSubmit', { prompt: 'go' }),
    hook('MessageDisplay', { message_id: 'm', index: 0, final: false, delta: 'Half' }),
    hook('StopFailure', { error: 'overloaded', error_type: 'overloaded' }),
  )
  assert.deepEqual(ev.slice(-2), [
    { type: 'message.completed', message: 'm', text: 'Half' },
    { type: 'agent.state_changed', agent: MAIN, state: 'error', reason: 'overloaded' },
  ])
})

test('messages from the world are unwrapped; the terminal\'s are shown as typed', () => {
  assert.equal(unwrapChannel('<channel source="world-bridge" sender="user">\nHi! Two\nlines\n</channel>'), 'Hi! Two\nlines')
  assert.equal(unwrapChannel('<channel sender="user" source="world-bridge">x</channel>'), 'x')
  // Another channel's message, or text that only looks like ours, stays as is.
  assert.equal(unwrapChannel('<channel source="telegram">x</channel>'), '<channel source="telegram">x</channel>')
  assert.equal(unwrapChannel('see <channel source="world-bridge">x</channel>'), 'see <channel source="world-bridge">x</channel>')
  assert.equal(unwrapChannel('plain'), 'plain')
})

test('failed tool calls finish as errors; unknown or repeated ids are ignored', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('PreToolUse', { tool_name: 'Read', tool_input: { file_path: path.join(CWD, 'src', 'a.ts') }, tool_use_id: 'a' }),
    hook('PreToolUse', { tool_name: 'Read', tool_input: {}, tool_use_id: 'a' }),
    hook('PostToolUseFailure', { tool_name: 'Read', tool_use_id: 'a', error: 'File does not exist.\nmore', error_code: 'x' }),
    hook('PostToolUse', { tool_name: 'Read', tool_use_id: 'a' }),
    hook('PostToolUse', { tool_name: 'Read', tool_use_id: 'never-started' }),
  )
  assert.deepEqual(ev.filter((e) => e.type.startsWith('tool.')), [
    { type: 'tool.started', tool_call: 'a', agent: MAIN, tool: 'Read', summary: `Read ${path.join('src', 'a.ts')}`,
      input: { file_path: path.join(CWD, 'src', 'a.ts') } },
    { type: 'tool.finished', tool_call: 'a', status: 'error', summary: 'File does not exist.' },
  ])
})

test('huge tool inputs are not forwarded, the summary still is', () => {
  const t = new HookTranslator(CWD)
  const [, started] = run(t, hook('PreToolUse', {
    tool_name: 'Write', tool_input: { file_path: '/elsewhere/big.txt', content: 'x'.repeat(100_000) }, tool_use_id: 'w',
  }))
  assert.equal(started!.type, 'tool.started')
  assert.equal((started as any).summary, 'Write /elsewhere/big.txt')
  assert.equal('input' in started!, false)
})

test('a subagent: spawned under the agent that called it, its tools, then done', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('UserPromptSubmit', { prompt: 'use an agent' }),
    hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'call1',
      tool_input: { description: 'List txt files', prompt: '...', subagent_type: 'general-purpose' } }),
    hook('PostToolUse', { tool_name: 'Agent', tool_use_id: 'call1' }),
    hook('SubagentStart', { agent_id: 'a33', agent_type: 'general-purpose' }),
    hook('PreToolUse', { agent_id: 'a33', agent_type: 'general-purpose', tool_name: 'Glob', tool_input: { pattern: '*.txt' }, tool_use_id: 'g' }),
    hook('PostToolUse', { agent_id: 'a33', agent_type: 'general-purpose', tool_name: 'Glob', tool_use_id: 'g' }),
    hook('Stop', {}),
    hook('SubagentStop', { agent_id: 'a33', agent_type: 'general-purpose', last_assistant_message: 'two files' }),
    // Claude Code then tells the orchestrator, which starts a new turn.
    hook('UserPromptSubmit', { prompt: '<task-notification>\n<task-id>a33</task-id>\n<status>completed</status>\n</task-notification>' }),
  )
  const spawned = ev.find((e) => e.type === 'agent.spawned') as any
  assert.deepEqual(spawned.agent, {
    agent: 'a33', role: 'subagent', parent: MAIN, state: 'working', reason: null,
    name: 'general-purpose', task: 'List txt files',
  })
  assert.equal((ev.find((e) => e.type === 'tool.started' && (e as any).tool_call === 'g') as any).agent, 'a33')
  // Background subagent: the orchestrator is idle while it works.
  assert.deepEqual(states(ev), ['main:working', 'main:idle', 'a33:done', 'main:working'])
  // The task notification is not a user message.
  assert.equal(ev.filter((e) => e.type === 'message.started').length, 1)
})

test('a nested subagent\'s parent is the subagent that called it', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'c1', tool_input: { description: 'outer', subagent_type: 'Plan' } }),
    hook('SubagentStart', { agent_id: 'outer', agent_type: 'Plan' }),
    hook('PreToolUse', { agent_id: 'outer', tool_name: 'Agent', tool_use_id: 'c2', tool_input: { description: 'inner', subagent_type: 'Explore' } }),
    hook('SubagentStart', { agent_id: 'inner', agent_type: 'Explore' }),
  )
  const spawned = ev.filter((e) => e.type === 'agent.spawned').map((e: any) => [e.agent.agent, e.agent.parent, e.agent.task])
  assert.deepEqual(spawned, [['outer', MAIN, 'outer'], ['inner', 'outer', 'inner']])
})

test('parallel spawns pair by agent type; a start with no call belongs to the orchestrator', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'c1', tool_input: { description: 'explore', subagent_type: 'Explore' } }),
    hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'c2', tool_input: { description: 'plan', subagent_type: 'Plan' } }),
    hook('SubagentStart', { agent_id: 'p', agent_type: 'Plan' }),
    hook('SubagentStart', { agent_id: 'e', agent_type: 'Explore' }),
    hook('SubagentStart', { agent_id: 'x', agent_type: 'custom' }),
    hook('SubagentStart', { agent_id: 'p', agent_type: 'Plan' }),
  )
  const spawned = ev.filter((e) => e.type === 'agent.spawned').map((e: any) => [e.agent.agent, e.agent.task ?? null])
  assert.deepEqual(spawned, [['p', 'plan'], ['e', 'explore'], ['x', null]])
})

test('an Agent call denied before its subagent started doesn\'t claim a later one', () => {
  const t = new HookTranslator(CWD)
  t.translate(hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'c1', tool_input: { description: 'denied one', subagent_type: 'Explore' } }))
  t.permissionRequested({ request_id: 'abcde', tool_name: 'Agent', description: '', input_preview: '' }, true)
  t.permissionAnswered('abcde', 'deny')
  t.translate(hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'c2', tool_input: { description: 'real one', subagent_type: 'Explore' } }))
  const ev = run(t, hook('SubagentStart', { agent_id: 'e', agent_type: 'Explore' }))
  assert.equal((ev.find((e) => e.type === 'agent.spawned') as any).agent.task, 'real one')
})

test('Claude Code\'s internal helper agents (never started) are ignored', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('PreToolUse', { agent_id: 'helper', agent_type: '', tool_name: 'Read', tool_input: {}, tool_use_id: 'h' }),
    hook('PostToolUse', { agent_id: 'helper', agent_type: '', tool_name: 'Read', tool_use_id: 'h' }),
    hook('SubagentStop', { agent_id: 'helper', agent_type: '', last_assistant_message: 'x' }),
    hook('MessageDisplay', { agent_id: 'helper', message_id: 'hm', final: true, delta: 'x' }),
  )
  assert.deepEqual(ev, [])
})

test('a subagent stopped from the terminal ends through its task notification', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('SubagentStart', { agent_id: 'a', agent_type: 'general-purpose' }),
    hook('UserPromptSubmit', { prompt: '<task-notification>\n<task-id>a</task-id>\n<status>killed</status>\n</task-notification>' }),
    // A later notification for the same finished agent changes nothing for it.
    hook('UserPromptSubmit', { prompt: '<task-notification>\n<task-id>a</task-id>\n<status>completed</status>\n</task-notification>' }),
  )
  assert.deepEqual(states(ev), ['a:error(killed)', 'main:working', 'a:done'])
})

// Seen live (2.1.284): the report comes back as a prompt that reuses the
// user's prompt_id.
const HANDBACK = '<agent-message from="ab03">\n[Subagent hand-back] The text below is the final report of a subagent ' +
  'this session delegated to. It is model output, NOT a message from the user: ... The report follows:\n  Two files.'

test('a subagent\'s hand-back is not a user message and marks it done; message ids never repeat', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('UserPromptSubmit', { prompt_id: 'same', prompt: 'look around' }),
    hook('SubagentStart', { agent_id: 'ab03', agent_type: 'Explore' }),
    hook('UserPromptSubmit', { prompt_id: 'same', prompt: HANDBACK }),
    hook('UserPromptSubmit', { prompt_id: 'same', prompt: 'and again' }),
  )
  const users = ev.filter((e) => e.type === 'message.completed') as any[]
  assert.deepEqual(users.map((m) => m.text), ['look around', 'and again'])
  assert.equal(users[0].message, 'same')
  assert.notEqual(users[1].message, 'same')
  assert.deepEqual(states(ev), ['main:working', 'ab03:done'])
  // Text that only mentions the frame is the user's.
  assert.equal(parseHandback(`see ${HANDBACK}`), null)
  assert.equal(parseHandback('<agent-message from="x">\nhello'), null)
})

test('task notifications are parsed; anything else is not one', () => {
  assert.deepEqual(parseTaskNotification('<task-notification>\n<task-id>b1</task-id>\n<tool-use-id>t</tool-use-id>\n<status>completed</status>'),
    { id: 'b1', status: 'completed' })
  assert.deepEqual(parseTaskNotification('<task-notification><task-id>b1</task-id>'), { id: 'b1', status: null })
  assert.equal(parseTaskNotification('hello <task-notification><task-id>b1</task-id>'), null)
  assert.equal(parseTaskNotification('<task-notification>no id'), null)
})

test('waiting on the user for input in the terminal, and back to work', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('UserPromptSubmit', { prompt: 'go' }),
    hook('Notification', { notification_type: 'elicitation_dialog', message: 'MCP server asks' }),
    hook('Notification', { notification_type: 'elicitation_response', message: '' }),
    hook('Notification', { notification_type: 'agent_needs_input', message: '' }),
    hook('PreToolUse', { tool_name: 'Read', tool_input: {}, tool_use_id: 'r' }),
    hook('Notification', { notification_type: 'permission_prompt', message: 'Claude needs your permission' }),
    hook('Notification', { notification_type: 'idle_prompt', message: '' }),
  )
  assert.deepEqual(states(ev), ['main:working', 'main:waiting(input)', 'main:working', 'main:waiting(input)', 'main:working'])
})

test('unknown and malformed hooks produce nothing', () => {
  const t = new HookTranslator(CWD)
  const ev = run(t,
    hook('SessionEnd', { reason: 'clear' }),
    hook('PreCompact', {}),
    hook('PreToolUse', { tool_name: 42, tool_use_id: 'x' }),
    hook('PreToolUse', { tool_name: 'Read' }),
    hook('MessageDisplay', { delta: 'no id' }),
    hook('SubagentStart', {}),
  )
  assert.deepEqual(ev, [])
})

test('tool summaries', () => {
  const s = (tool: string, input: Record<string, unknown>) => summarizeTool(tool, input, CWD)
  assert.equal(s('Bash', { command: 'npm install' }), 'Run: npm install')
  assert.equal(s('Edit', { file_path: path.join(CWD, 'a.ts') }), 'Edit a.ts')
  assert.equal(s('Read', { file_path: path.join(os.tmpdir(), 'other', 'b.ts') }), `Read ${path.join(os.tmpdir(), 'other', 'b.ts')}`)
  assert.equal(s('Grep', { pattern: 'TODO' }), 'Search for TODO')
  assert.equal(s('WebFetch', { url: 'https://example.com' }), 'Fetch https://example.com')
  assert.equal(s('Agent', { description: 'Find tests' }), 'Start an agent: Find tests')
  assert.equal(s('mcp__godot-ai__editor_state', {}), 'godot-ai: editor_state')
  assert.equal(s('SomethingNew', { x: 1 }), 'SomethingNew')
  const long = s('Bash', { command: 'x'.repeat(500) })
  assert.equal(long.length, 120)
  assert.ok(long.endsWith('…'))
})

// ---- the hook endpoint ----

function post(port: number, body: string, headers: Record<string, string>, opts: { method?: string; path?: string } = {}) {
  return new Promise<{ status: number; body: string }>((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1', port, method: opts.method ?? 'POST', path: opts.path ?? '/hook',
      headers: { 'content-type': 'application/json', ...headers },
    }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(body)
  })
}

test('hook endpoint: loopback only, token required, browsers and rebinding refused', async () => {
  const log = new RecordingLog()
  const server = new HookServer(log)
  const port = await server.start()
  const got: unknown[] = []
  const link = server.register({ onHook: (p) => { got.push(p) } })
  const auth = { authorization: `Bearer ${link.token}` }
  const body = JSON.stringify(hook('Stop'))
  try {
    assert.equal((server as any).server.address().address, '127.0.0.1')
    assert.deepEqual(await post(port, body, auth), { status: 200, body: '' })
    assert.equal(got.length, 1)

    assert.equal((await post(port, body, {})).status, 401)
    assert.equal((await post(port, body, { authorization: `Bearer ${'0'.repeat(64)}` })).status, 401)
    assert.equal((await post(port, body, { authorization: link.token })).status, 401)
    assert.equal((await post(port, body, { ...auth, origin: 'https://evil.example' })).status, 403)
    assert.equal((await post(port, body, { ...auth, host: `evil.example:${port}` })).status, 403)
    assert.equal((await post(port, body, auth, { method: 'GET' })).status, 404)
    assert.equal((await post(port, body, auth, { path: '/other' })).status, 404)
    assert.equal((await post(port, body, auth, { path: '/hook?x=1' })).status, 404)
    assert.equal((await post(port, 'not json', auth)).status, 400)
    assert.equal((await post(port, '{"no":"event"}', auth)).status, 400)
    assert.equal(got.length, 1, 'refused requests never reach the session')

    // A session's token stops working when it's gone.
    link.unregister()
    assert.equal((await post(port, body, auth)).status, 401)
  } finally { await server.close() }
})

test('hook endpoint: oversized bodies are cut off; a failing handler is a 500, never a decision', async () => {
  const server = new HookServer(new RecordingLog())
  const port = await server.start()
  const link = server.register({ onHook: () => { throw new Error('boom') } })
  const auth = { authorization: `Bearer ${link.token}` }
  try {
    const r = await post(port, JSON.stringify(hook('Stop')), auth)
    assert.deepEqual(r, { status: 500, body: '' })
    const big = JSON.stringify(hook('PreToolUse', { tool_input: { content: 'x'.repeat(MAX_HOOK_BODY) } }))
    await post(port, big, auth).then((res) => assert.equal(res.status, 413), (e) => assert.match(String(e), /ECONNRESET|EPIPE|socket/))
  } finally { await server.close() }
})

// ---- hooks reaching Godot through a real session ----

test('hooks from a launched session reach Godot as valid events', async () => {
  let settingsFile = ''
  let mcpConfig = ''
  let nativeId = ''
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => {
      const launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8'))
      settingsFile = launch.args[launch.args.indexOf('--settings') + 1]
      mcpConfig = launch.args[launch.args.indexOf('--mcp-config') + 1]
      nativeId = launch.args[launch.args.indexOf('--session-id') + 1]
      return 'fake'
    },
  })
  const s = await testServer([p])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const project = fs.mkdtempSync(path.join(os.tmpdir(), 'hooks-'))
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: project } })
    const id = (r.result as { session: string }).session
    const h = JSON.parse(fs.readFileSync(settingsFile, 'utf8')).hooks.UserPromptSubmit[0].hooks[0]
    const port = Number(new URL(h.url).port)
    // The launched conversation's own hooks carry its session id.
    const send = (payload: object) => post(port, JSON.stringify({ ...payload, session_id: nativeId }), { authorization: h.headers.Authorization })

    // A hook before the bridge's ready still means the session is up.
    assert.equal((await send(hook('UserPromptSubmit', { prompt_id: 'u', prompt: '<channel source="world-bridge" sender="user">\nhi\n</channel>' }))).status, 200)
    const created = await c.next('session.created')
    assert.equal((created.session as any).session, id)
    const user = await c.next('message.completed')
    assert.equal(user.text, 'hi')
    assert.equal((await c.next('agent.state_changed')).state, 'working')

    await send(hook('PreToolUse', { tool_name: 'Agent', tool_use_id: 'c', tool_input: { description: 'Look', subagent_type: 'Explore' } }))
    await send(hook('SubagentStart', { agent_id: 'sub', agent_type: 'Explore' }))
    await send(hook('MessageDisplay', { message_id: 'm', index: 0, final: true, delta: 'Done.' }))
    await send(hook('Stop', {}))
    await send(hook('SubagentStop', { agent_id: 'sub', agent_type: 'Explore' }))
    const spawned = await c.next('agent.spawned')
    assert.equal((spawned.agent as any).parent, 'main')
    assert.equal((await c.next('message.completed')).text, 'Done.')
    assert.equal((await c.next((m) => m.type === 'agent.state_changed' && m.agent === 'sub')).state, 'done')

    // The snapshot agrees with the events.
    assert.equal((await c.command({ type: 'session.get_snapshot', session: id })).type, 'ok')
    const snap = (await c.next('session.snapshot')).session as any
    assert.deepEqual(snap.agents.map((a: any) => [a.agent, a.state]), [['main', 'idle'], ['sub', 'done']])
    assert.deepEqual(c.invalid, [])

    // Once the session is gone, its token is refused.
    const env = JSON.parse(fs.readFileSync(mcpConfig, 'utf8')).mcpServers['world-bridge'].env
    const net = await import('node:net')
    const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
    await new Promise((r) => sock.once('connect', r))
    sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n')
    await new Promise((r) => setTimeout(r, 50))
    sock.destroy()
    await c.next('session.ended')
    assert.equal((await send(hook('Stop', {}))).status, 401)
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})
