// Chat history (session.get_history): what the world saw through the hooks,
// in memory only, oldest first.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { connect, RecordingLog, testServer } from './helpers.ts'

test('history: user and assistant messages, completed ones only, as the world saw them', async () => {
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  let sock: net.Socket | null = null
  try {
    await c.sync()
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'h-')) } })
    const id = (r.result as { session: string }).session
    const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
    const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.Stop[0].hooks[0]
    const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
    sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
    await c.next('session.created')
    const send = (body: object) => new Promise<void>((resolve, reject) => {
      const req = http.request({ host: '127.0.0.1', port: Number(new URL(h.url).port), method: 'POST', path: '/hook',
        headers: { authorization: h.headers.Authorization } }, (res) => { res.resume(); res.on('end', resolve) })
      req.on('error', reject)
      req.end(JSON.stringify(body))
    })

    assert.deepEqual((await c.command({ type: 'session.get_history', session: id })).result, { messages: [], tools: [] })
    await send({ hook_event_name: 'UserPromptSubmit', prompt_id: 'u1', prompt: '<channel source="world-bridge" sender="user">\nhello\n</channel>' })
    await send({ hook_event_name: 'MessageDisplay', message_id: 'm1', index: 0, final: false, delta: 'Hi ' })
    await send({ hook_event_name: 'MessageDisplay', message_id: 'm1', index: 1, final: true, delta: 'there.' })
    // Tool calls (C04): the orchestrator's after the message before them, a
    // subagent's inside the Agent call that started it.
    await send({ hook_event_name: 'PreToolUse', tool_name: 'Read', tool_use_id: 't1', tool_input: { file_path: 'a.ts' } })
    await send({ hook_event_name: 'PostToolUse', tool_name: 'Read', tool_use_id: 't1', tool_input: { file_path: 'a.ts' } })
    await send({ hook_event_name: 'PreToolUse', tool_name: 'Agent', tool_use_id: 't2', tool_input: { description: 'Look', subagent_type: 'Explore' } })
    await send({ hook_event_name: 'SubagentStart', agent_id: 'sub1', agent_type: 'Explore' })
    await send({ hook_event_name: 'PreToolUse', agent_id: 'sub1', agent_type: 'Explore', tool_name: 'Bash', tool_use_id: 't3', tool_input: { command: 'ls' } })
    await send({ hook_event_name: 'PostToolUseFailure', agent_id: 'sub1', agent_type: 'Explore', tool_name: 'Bash', tool_use_id: 't3', tool_input: { command: 'ls' }, error: 'Exit code 2\nmore' })
    await send({ hook_event_name: 'MessageDisplay', message_id: 'm2', index: 0, final: false, delta: 'Still typing' })

    const history = (await c.command({ type: 'session.get_history', session: id })).result as { messages: any[]; tools: any[] }
    assert.deepEqual(history.tools.map((t) => [t.tool_call, t.agent, t.status, t.after, t.within ?? null, t.result ?? null]), [
      ['t1', 'main', 'ok', 'm1', null, null],
      ['t2', 'main', 'running', 'm1', null, null],
      ['t3', 'sub1', 'error', 'm1', 't2', 'Exit code 2'],
    ])
    assert.deepEqual(history.messages.map((m) => [m.message, m.agent, m.role, m.text]), [
      ['u1', 'main', 'user', 'hello'],
      ['m1', 'main', 'assistant', 'Hi there.'],
    ])
    for (const m of history.messages) assert.ok(!Number.isNaN(Date.parse(m.at)))
    assert.deepEqual(c.invalid, [])
  } finally { sock?.destroy(); await c.close(); await s.close(); await p.shutdown() }
})
