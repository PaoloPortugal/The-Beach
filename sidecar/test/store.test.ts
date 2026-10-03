// Stored sessions (S04): listing Claude Code's transcripts, reading a
// resumed session's chat, and resuming through the provider. Lines are
// shaped like Claude Code 2.1.284's.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { describe, hasReply, listStored, readHistory, findStored } from '../src/providers/claude/store.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { takeSessionFile } from '../src/launch/launcher.ts'
import { connect, RecordingLog, testServer } from './helpers.ts'

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const jsonl = (...entries: object[]) => entries.map((e) => JSON.stringify(e)).join('\n') + '\n'

function store() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const projA = fs.mkdtempSync(path.join(os.tmpdir(), 'proj a '))
  const projB = fs.mkdtempSync(path.join(os.tmpdir(), 'projb-'))
  const put = (slug: string, id: string, body: string, ageMs = 0) => {
    fs.mkdirSync(path.join(dir, slug), { recursive: true })
    const file = path.join(dir, slug, `${id}.jsonl`)
    fs.writeFileSync(file, body)
    const t = new Date(Date.now() - ageMs)
    fs.utimesSync(file, t, t)
    return file
  }
  const meta = (cwd: string, entrypoint = 'cli') => ({ cwd, entrypoint, sessionId: 'x', version: '2.1.284' })
  // A named session in project A (the name we launch with).
  put('a', ID(1), jsonl(
    { type: 'custom-title', customTitle: 'cp1-project' },
    { type: 'user', isMeta: true, message: { role: 'user', content: '<channel source="world-bridge" sender="user">\nhello\n</channel>' }, ...meta(projA) },
  ), 1000)
  // Unnamed, in project B, older: titled by its first message.
  put('b', ID(2), jsonl(
    { type: 'user', isMeta: true, message: { content: 'Caveat: injected context' }, ...meta(projB) },
    { type: 'user', message: { role: 'user', content: 'fix the login bug\nplease' }, ...meta(projB) },
  ), 5000)
  // Left out: the desktop app's, an empty one, one where nothing was said, not a session id.
  put('b', ID(3), jsonl({ type: 'user', message: { content: 'from the desktop app' }, ...meta(projB, 'claude-desktop') }))
  put('b', ID(4), '')
  put('b', ID(5), jsonl({ type: 'user', isMeta: true, message: { content: 'only context' }, ...meta(projB) }))
  put('b', 'not-a-session', jsonl({ type: 'user', message: { content: 'x' }, ...meta(projB) }))
  // A later rename (/rename) near the end of a long file.
  put('a', ID(6), jsonl(
    { type: 'user', message: { content: 'first' }, ...meta(projA) },
    ...Array.from({ length: 800 }, (_, i) => ({ type: 'assistant', message: { id: `m${i}`, content: [{ type: 'text', text: 'x'.repeat(100) }] } })),
    { type: 'custom-title', customTitle: 'renamed later' },
    { type: 'ai-title', aiTitle: 'not over a rename' },
  ), 3000)
  // Named by Claude Code, after its first message.
  put('b', ID(8), jsonl(
    { type: 'user', message: { content: 'look at the logs' }, ...meta(projB) },
    { type: 'ai-title', aiTitle: 'Log review' },
  ), 6000)
  return { dir, projA, projB }
}

test('list: terminal sessions, newest first, titled by name or first message; filters by project', () => {
  const s = store()
  const all = listStored({ dir: s.dir })
  assert.deepEqual(all.map((x) => [x.native_id, x.title]), [
    [ID(1), 'cp1-project'], [ID(6), 'renamed later'], [ID(2), 'fix the login bug'], [ID(8), 'Log review'],
  ])
  assert.equal(all[0]!.provider, 'claude')
  assert.equal(all[0]!.project.path, s.projA)
  assert.ok(!Number.isNaN(Date.parse(all[0]!.updated_at)))
  assert.deepEqual(listStored({ dir: s.dir, project: s.projB }).map((x) => x.native_id), [ID(2), ID(8)])
  assert.deepEqual(listStored({ dir: s.dir, exclude: new Set([ID(1)]) }).map((x) => x.native_id), [ID(6), ID(2), ID(8)])
  assert.deepEqual(listStored({ dir: path.join(s.dir, 'missing') }), [])
  assert.equal(findStored(ID(2), s.dir)!.title, 'fix the login bug')
  assert.equal(findStored(ID(3), s.dir), null, 'desktop sessions are not resumed here')
  assert.equal(findStored('../../etc/passwd', s.dir), null)
  assert.equal(describe(path.join(s.dir, 'b', 'not-a-session.jsonl')), null)
})

test('history: what the user said (typed or from the world) and Claude\'s text, nothing else', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hist-'))
  const file = path.join(dir, `${ID(9)}.jsonl`)
  fs.writeFileSync(file, jsonl(
    { type: 'user', uuid: 'u1', timestamp: '2026-09-29T10:00:00Z', isMeta: true, message: { content: '<channel source="world-bridge" sender="user">\nfrom the world\n</channel>' } },
    { type: 'user', isMeta: true, message: { content: 'injected context' } },
    { type: 'assistant', timestamp: '2026-09-29T10:00:01Z', message: { id: 'msg_1', content: [{ type: 'thinking', thinking: 'hmm' }] } },
    { type: 'assistant', message: { id: 'msg_1', content: [{ type: 'text', text: 'Let me look.' }] } },
    { type: 'assistant', message: { id: 'msg_1', content: [{ type: 'tool_use', id: 't', name: 'Read', input: {} }] } },
    { type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 't', content: 'file text' }] } },
    { type: 'user', message: { content: '<task-notification>\n<task-id>a</task-id>\n</task-notification>' } },
    { type: 'user', message: { content: [{ type: 'text', text: '[Request interrupted by user]' }] } },
    { type: 'user', uuid: 'u2', message: { content: [{ type: 'text', text: 'typed in the terminal' }] } },
    { type: 'assistant', isSidechain: true, message: { id: 'msg_sub', content: [{ type: 'text', text: 'a subagent' }] } },
    { type: 'assistant', message: { id: 'msg_2', content: [{ type: 'text', text: 'Done.' }] } },
    'not json' as unknown as object,
  ))
  const h = readHistory(file).messages
  assert.deepEqual(h.map((m) => [m.role, m.text]), [
    ['user', 'from the world'], ['assistant', 'Let me look.'], ['user', 'typed in the terminal'], ['assistant', 'Done.'],
  ])
  assert.equal(h[0]!.message, 'u1')
  assert.equal(h[0]!.at, '2026-09-29T10:00:00Z')
  assert.equal(h[1]!.message, 'msg_1')
  assert.deepEqual(readHistory(path.join(dir, 'missing.jsonl')), { messages: [], tools: [] })
})

test('history: tool calls, how each ended, where each came, and subagents\' inside their Agent call', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hist-'))
  const id = ID(11)
  const file = path.join(dir, `${id}.jsonl`)
  const cwd = path.join(os.tmpdir(), 'proj')
  const use = (msg: string, tool: string, name: string, input: object, text?: string) => ({
    type: 'assistant', cwd, message: { id: msg, content: [...(text ? [{ type: 'text', text }] : []), { type: 'tool_use', id: tool, name, input }] },
  })
  const result = (tool: string, extra: object = {}, block: object = {}) => ({
    type: 'user', ...extra, message: { content: [{ type: 'tool_result', tool_use_id: tool, content: 'out', ...block }] },
  })
  fs.writeFileSync(file, jsonl(
    use('msg_0', 'early', 'Glob', { pattern: '*' }),
    result('early'),
    { type: 'user', uuid: 'u1', message: { content: 'go' } },
    // Text and a call in one entry: the call comes after that text.
    use('msg_1', 'read', 'Read', { file_path: path.join(cwd, 'a.ts') }, 'Looking.'),
    result('read'),
    use('msg_2', 'fail', 'Bash', { command: 'npm test' }),
    result('fail', {}, { is_error: true, content: [{ type: 'text', text: 'Error: Exit code 1\nmore' }] }),
    use('msg_3', 'deny', 'Bash', { command: 'rm x' }),
    result('deny', { toolDenialKind: 'user-rejected' }, { is_error: true }),
    use('msg_4', 'spawn', 'Agent', { description: 'Look around', subagent_type: 'Explore' }),
    result('spawn'),
    use('msg_5', 'cut', 'Bash', { command: 'sleep 99' }),
  ))
  const subs = path.join(dir, id, 'subagents')
  fs.mkdirSync(subs, { recursive: true })
  fs.writeFileSync(path.join(subs, 'agent-abc123.jsonl'), jsonl(
    { ...use('s_1', 'sub_read', 'Read', { file_path: path.join(cwd, 'b.ts') }), isSidechain: true },
    { ...result('sub_read'), isSidechain: true },
  ))
  fs.writeFileSync(path.join(subs, 'agent-abc123.meta.json'), JSON.stringify({ agentType: 'Explore', toolUseId: 'spawn' }))

  const { messages, tools } = readHistory(file)
  assert.deepEqual(messages.map((m) => m.message), ['u1', 'msg_1'])
  const row = (t: (typeof tools)[number]) => [t.tool_call, t.agent, t.status, t.after, t.within ?? null, t.result ?? null]
  assert.deepEqual(tools.map(row), [
    ['early', 'main', 'ok', null, null, null],
    ['read', 'main', 'ok', 'msg_1', null, null],
    ['fail', 'main', 'error', 'msg_1', null, 'Error: Exit code 1'],
    ['deny', 'main', 'denied', 'msg_1', null, null],
    ['spawn', 'main', 'ok', 'msg_1', null, null],
    ['cut', 'main', 'error', 'msg_1', null, 'No result was recorded.'],
    ['sub_read', 'abc123', 'ok', null, 'spawn', null],
  ])
  assert.equal(tools[1]!.summary, `Read ${path.join('a.ts')}`)
  assert.deepEqual(tools[1]!.input, { file_path: path.join(cwd, 'a.ts') })
})

// The start of a transcript /clear began, as Claude Code 2.1.285 wrote it
// (live re-check, 2026-10-01): the command itself is a user entry, not meta.
const CLEARED = [
  { type: 'user', isMeta: true, message: { role: 'user', content: '<local-command-caveat>Caveat: The messages below were generated by the user while running local commands.</local-command-caveat>' } },
  { type: 'user', message: { role: 'user', content: '<command-name>/clear</command-name>\n            <command-message>clear</command-message>\n            <command-args></command-args>' } },
  { type: 'system', subtype: 'local_command', content: '<local-command-stdout></local-command-stdout>' },
  { type: 'user', message: { role: 'user', content: '<local-command-stdout>Resumed</local-command-stdout>' } },
]

test('history: slash commands run in the terminal and their output aren\'t chat', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hist-'))
  const file = path.join(dir, `${ID(9)}.jsonl`)
  fs.writeFileSync(file, jsonl(...CLEARED,
    { type: 'user', isMeta: true, message: { content: '<channel source="world-bridge" sender="user">\nhello\n</channel>' } },
    { type: 'assistant', message: { id: 'msg_1', content: [{ type: 'text', text: 'Hi!' }] } },
  ))
  assert.deepEqual(readHistory(file).messages.map((m) => [m.role, m.text]), [['user', 'hello'], ['assistant', 'Hi!']])
  // Listed by what was said, not by the command.
  const proj = fs.mkdtempSync(path.join(os.tmpdir(), 'proj-'))
  const listed = path.join(dir, `${ID(10)}.jsonl`)
  fs.writeFileSync(listed, jsonl(...CLEARED.map((e) => ({ ...e, cwd: proj, entrypoint: 'cli' })),
    { type: 'user', message: { content: 'fix the tests' }, cwd: proj, entrypoint: 'cli' }))
  assert.equal(describe(listed)!.title, 'fix the tests')
})

test('hasReply: only a transcript with a reply from Claude (not just /clear\'s entries or a prompt)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'reply-'))
  const put = (name: string, ...entries: object[]) => {
    const f = path.join(dir, name)
    fs.writeFileSync(f, jsonl(...entries))
    return f
  }
  assert.equal(hasReply(put('cleared.jsonl', ...CLEARED, { type: 'user', message: { content: 'after' } })), false)
  assert.equal(hasReply(put('sub.jsonl', { type: 'assistant', isSidechain: true, message: { id: 'm', content: [] } })), false)
  assert.equal(hasReply(put('earlier.jsonl', { type: 'user', message: { content: 'q' } },
    { type: 'assistant', message: { id: 'm', content: [{ type: 'tool_use', id: 't', name: 'Read', input: {} }] } })), true)
  assert.equal(hasReply(path.join(dir, 'missing.jsonl')), false)
})

function provider(projectsDir: string) {
  const opened: string[] = []
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { opened.push(req.argv[2]!); return 'fake' },
    projectsDir,
  })
  return { p, opened }
}

test('through a session: list, resume with --resume in the project folder, its chat, no second copy', async () => {
  const s = store()
  const { p, opened } = provider(s.dir)
  const srv = await testServer([p])
  const c = await connect(srv.port, srv.token)
  let sock: net.Socket | null = null
  try {
    await c.sync()
    const listed = (await c.command({ type: 'session.list_stored', provider: 'claude' })).result as { sessions: any[] }
    assert.deepEqual(listed.sessions.map((x) => x.native_id), [ID(1), ID(6), ID(2), ID(8)])

    const r = await c.command({ type: 'session.resume', provider: 'claude', native_id: ID(1) })
    assert.equal(r.type, 'ok', JSON.stringify(r))
    const launch = takeSessionFile(opened[0]!)
    assert.deepEqual(launch.args.slice(0, 2), ['--resume', ID(1)])
    assert.ok(!launch.args.includes('--session-id') && !launch.args.includes('--name'))
    assert.equal(fs.realpathSync(launch.cwd), fs.realpathSync(s.projA))

    // Running now: not listed, and not resumed twice.
    const again = (await c.command({ type: 'session.list_stored', provider: 'claude' })).result as { sessions: any[] }
    assert.ok(!again.sessions.some((x) => x.native_id === ID(1)))
    const twice = await c.command({ type: 'session.resume', provider: 'claude', native_id: ID(1) })
    assert.deepEqual([twice.type, twice.code], ['error', 'provider_error'])

    // It comes up like a new one, with its earlier chat as history.
    const env = JSON.parse(fs.readFileSync(launch.args[launch.args.indexOf('--mcp-config') + 1]!, 'utf8')).mcpServers['world-bridge'].env
    sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
    const created = await c.next('session.created')
    assert.equal((created.session as any).native_id, ID(1))
    assert.equal((created.session as any).title, 'cp1-project')
    const id = (r.result as { session: string }).session
    const history = (await c.command({ type: 'session.get_history', session: id })).result as { messages: any[] }
    assert.deepEqual(history.messages.map((m) => m.text), ['hello'])

    for (const [nativeId, why] of [[ID(99), /wasn't found/], [ID(3), /wasn't found/]] as const) {
      const bad = await c.command({ type: 'session.resume', provider: 'claude', native_id: nativeId })
      assert.match(String(bad.message), why)
    }
    // A transcript naming a relative folder isn't resumed from wherever the sidecar runs.
    const rel = path.join(s.dir, 'c')
    fs.mkdirSync(rel)
    fs.writeFileSync(path.join(rel, `${ID(7)}.jsonl`), jsonl({ type: 'user', message: { content: 'x' }, cwd: 'src', entrypoint: 'cli' }))
    assert.match(String((await c.command({ type: 'session.resume', provider: 'claude', native_id: ID(7) })).message), /no longer exists/)
    fs.rmSync(s.projB, { recursive: true })
    const gone = await c.command({ type: 'session.resume', provider: 'claude', native_id: ID(2) })
    assert.match(String(gone.message), /no longer exists/)
    assert.deepEqual(c.invalid, [])
  } finally { sock?.destroy(); await c.close(); await srv.close(); await p.shutdown() }
})

test('a first prompt given at create is sent as world chat once the session is up', async () => {
  const { p, opened } = provider(fs.mkdtempSync(path.join(os.tmpdir(), 'empty-')))
  const srv = await testServer([p])
  const c = await connect(srv.port, srv.token)
  let sock: net.Socket | null = null
  try {
    await c.sync()
    await c.command({ type: 'session.create', provider: 'claude', project: { path: os.tmpdir() }, prompt: 'start with the tests' })
    const launch = takeSessionFile(opened[0]!)
    const env = JSON.parse(fs.readFileSync(launch.args[launch.args.indexOf('--mcp-config') + 1]!, 'utf8')).mcpServers['world-bridge'].env
    sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    const got: any[] = []
    sock.setEncoding('utf8').on('data', (d: string) => got.push(...d.trim().split('\n').map((l) => JSON.parse(l))))
    sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
    await c.next('session.created')
    for (let i = 0; i < 100 && got.length === 0; i++) await new Promise((res) => setTimeout(res, 10))
    assert.deepEqual(got, [{ type: 'chat', text: 'start with the tests' }])
  } finally { sock?.destroy(); await c.close(); await srv.close(); await p.shutdown() }
})
