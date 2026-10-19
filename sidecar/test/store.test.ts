// Stored sessions (S04): listing Claude Code's transcripts, reading a
// resumed session's chat, and resuming through the provider. Lines are
// shaped like Claude Code 2.1.284's.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { describe, describeAsync, hasReply, listStored, readHistory, findStored, StoredCache } from '../src/providers/claude/store.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import type { Running } from '../src/providers/claude/running.ts'
import { takeSessionFile } from '../src/launch/launcher.ts'
import { connect, RecordingLog, testServer, tempSessionsDir, bridgeOf } from './helpers.ts'

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
/** Claude Code can't tell which sessions run (agent view off): nothing is left out. */
const NOT_KNOWN = async (): Promise<Running> => ({ none: 'test' })
const FOUND = async () => ({ path: process.execPath, version: '2.1.284' })
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

test('list: terminal sessions, newest first, titled by name or first message; filters by project', async () => {
  const s = store()
  const all = await listStored({ dir: s.dir })
  assert.deepEqual(all.map((x) => [x.native_id, x.title]), [
    [ID(1), 'cp1-project'], [ID(6), 'renamed later'], [ID(2), 'fix the login bug'], [ID(8), 'Log review'],
  ])
  assert.equal(all[0]!.provider, 'claude')
  assert.equal(all[0]!.project.path, s.projA)
  assert.ok(!Number.isNaN(Date.parse(all[0]!.updated_at)))
  assert.deepEqual((await listStored({ dir: s.dir, project: s.projB })).map((x) => x.native_id), [ID(2), ID(8)])
  assert.deepEqual((await listStored({ dir: s.dir, exclude: new Set([ID(1)]) })).map((x) => x.native_id), [ID(6), ID(2), ID(8)])
  assert.deepEqual(await listStored({ dir: path.join(s.dir, 'missing') }), [])
  assert.equal(findStored(ID(2), s.dir)!.title, 'fix the login bug')
  assert.equal(findStored(ID(3), s.dir), null, 'desktop sessions are not resumed here')
  assert.equal(findStored('../../etc/passwd', s.dir), null)
  assert.equal(describe(path.join(s.dir, 'b', 'not-a-session.jsonl')), null)
})

test('list with a cache: the same list; files read again only once they change, gone ones forgotten', async () => {
  const s = store()
  const cache = new StoredCache()
  const plain = await listStored({ dir: s.dir })
  assert.deepEqual(await listStored({ dir: s.dir, cache }), plain)
  const firstReads = cache.reads
  assert.ok(firstReads >= plain.length)
  assert.deepEqual(await listStored({ dir: s.dir, cache }), plain, 'listed again, the same')
  assert.equal(cache.reads, firstReads, 'and nothing read again')
  // Renamed in the terminal: the file grows, and its new title shows.
  fs.appendFileSync(path.join(s.dir, 'b', `${ID(2)}.jsonl`), jsonl({ type: 'custom-title', customTitle: 'login fix' }))
  const after = await listStored({ dir: s.dir, cache })
  assert.equal(after.find((x) => x.native_id === ID(2))!.title, 'login fix')
  assert.equal(after[0]!.native_id, ID(2), 'and it is the newest now')
  assert.equal(cache.reads, firstReads + 1, 'only that one is read again')
  assert.deepEqual(after, await listStored({ dir: s.dir }), 'the same as without the cache')
  // Deleted (Claude Code's cleanup): gone from the list and the cache.
  const before = cache.size
  fs.rmSync(path.join(s.dir, 'a', `${ID(6)}.jsonl`))
  assert.ok(!(await listStored({ dir: s.dir, cache })).some((x) => x.native_id === ID(6)))
  assert.equal(cache.size, before - 1)
  // A new one is read and listed.
  fs.writeFileSync(path.join(s.dir, 'b', `${ID(9)}.jsonl`), jsonl({ type: 'user', message: { content: 'brand new' }, cwd: s.projB, entrypoint: 'cli' }))
  assert.equal((await listStored({ dir: s.dir, cache }))[0]!.title, 'brand new')
})

test('a transcript whose read fails is not kept, and is listed on the next call', async () => {
  const s = store()
  const failing = path.join(s.dir, 'b', `${ID(2)}.jsonl`)
  let fail = true
  const cache = new StoredCache(async (file, st) => {
    if (file === failing && fail) return undefined // e.g. locked mid-write
    return describeAsync(file, st)
  })
  assert.ok(!(await listStored({ dir: s.dir, cache })).some((x) => x.native_id === ID(2)), 'left out while it can\'t be read')
  fail = false
  const reads = cache.reads
  const next = await listStored({ dir: s.dir, cache })
  assert.equal(next.find((x) => x.native_id === ID(2))?.title, 'fix the login bug', 'read again, and listed')
  assert.equal(cache.reads, reads + 1, 'only that one is read again')
  assert.deepEqual(next, await listStored({ dir: s.dir }), 'the same as without the cache')
})

test('listing doesn\'t block: other work runs while the files are read', async () => {
  const s = store()
  for (let n = 10; n < 40; n++) {
    fs.writeFileSync(path.join(s.dir, 'b', `${ID(n)}.jsonl`), jsonl({ type: 'user', message: { content: `session ${n}` }, cwd: s.projB, entrypoint: 'cli' }))
  }
  let ticks = 0
  let done = false
  const tick = () => { if (!done) { ticks++; setImmediate(tick) } }
  setImmediate(tick)
  const list = await listStored({ dir: s.dir, cache: new StoredCache() })
  done = true
  assert.equal(list.length, 34)
  assert.ok(ticks >= 10, `the event loop turned ${ticks} times meanwhile`)
})

test('the provider keeps its listing between calls, and shows what changed', async () => {
  const s = store()
  const provider = new ClaudeProvider({ sessionsDir: tempSessionsDir(), projectsDir: s.dir, findClaude: FOUND, runningSessions: NOT_KNOWN })
  const first = await provider.listStored()
  fs.appendFileSync(path.join(s.dir, 'a', `${ID(1)}.jsonl`), jsonl({ type: 'custom-title', customTitle: 'renamed' }))
  const second = await provider.listStored()
  assert.equal(first.find((x) => x.native_id === ID(1))!.title, 'cp1-project')
  assert.equal(second.find((x) => x.native_id === ID(1))!.title, 'renamed', 'a change since shows')
  assert.deepEqual(await provider.listStored(s.projB), second.filter((x) => x.project.path === s.projB), 'and one project\'s')
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

test('history: a subagent without its .meta.json lists its calls at the top, with no parent call', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hist-'))
  const id = ID(12)
  const file = path.join(dir, `${id}.jsonl`)
  fs.writeFileSync(file, jsonl({ type: 'user', uuid: 'u1', message: { content: 'go' } }))
  const subs = path.join(dir, id, 'subagents')
  fs.mkdirSync(subs, { recursive: true })
  fs.writeFileSync(path.join(subs, 'agent-lone.jsonl'), jsonl(
    { type: 'assistant', isSidechain: true, message: { id: 's', content: [{ type: 'tool_use', id: 'g', name: 'Glob', input: { pattern: '*' } }] } },
  ))
  const { tools } = readHistory(file)
  assert.deepEqual(tools.map((t) => [t.tool_call, t.agent, t.after, 'within' in t]), [['g', 'lone', null, false]])
})

test('history: the main transcript and its subagents\' share one read budget; what doesn\'t fit is skipped', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hist-'))
  const id = ID(13)
  const file = path.join(dir, `${id}.jsonl`)
  const call = (tool: string, pad = '') => jsonl({
    type: 'assistant', isSidechain: true, message: { id: `m_${tool}`, content: [{ type: 'tool_use', id: tool, name: 'Read', input: { file_path: `/x/${tool}${pad}` } }] },
  })
  fs.writeFileSync(file, jsonl({ type: 'user', uuid: 'u1', message: { content: 'go' } }))
  const subs = path.join(dir, id, 'subagents')
  fs.mkdirSync(subs, { recursive: true })
  // Read in name order: a fits, b is too big for what's left (skipped), c still fits.
  fs.writeFileSync(path.join(subs, 'agent-a.jsonl'), call('a'))
  fs.writeFileSync(path.join(subs, 'agent-b.jsonl'), call('b', 'y'.repeat(2000)))
  fs.writeFileSync(path.join(subs, 'agent-c.jsonl'), call('c'))
  const sizes = ['', 'agent-a.jsonl', 'agent-c.jsonl'].map((n) => fs.statSync(n ? path.join(subs, n) : file).size)
  const budget = sizes.reduce((a, b) => a + b, 0) + 100
  assert.deepEqual(readHistory(file, budget).tools.map((t) => t.tool_call), ['a', 'c'])
  // The main transcript counts: with less left, c no longer fits either.
  assert.deepEqual(readHistory(file, sizes[0]! + sizes[1]! + 10).tools.map((t) => t.tool_call), ['a'])
  // A main transcript over the budget isn't read at all.
  assert.deepEqual(readHistory(file, sizes[0]! - 1), { messages: [], tools: [] })
  assert.deepEqual(readHistory(file).tools.map((t) => t.tool_call), ['a', 'b', 'c'])
})

test('history: a plan presented for approval is its own message, before its call (C07)', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hist-'))
  const file = path.join(dir, `${ID(12)}.jsonl`)
  const plan = (msg: string, tool: string, text: string) => ({
    type: 'assistant', message: { id: msg, content: [{ type: 'tool_use', id: tool, name: 'ExitPlanMode', input: { plan: text, planFilePath: '/x.md' } }] },
  })
  fs.writeFileSync(file, jsonl(
    { type: 'user', uuid: 'u1', message: { content: 'plan it' } },
    { type: 'assistant', message: { id: 'msg_1', content: [{ type: 'text', text: 'Here it is.' }] } },
    plan('msg_2', 'exit1', '# Plan\n\n1. Do it'),
    { type: 'user', toolDenialKind: 'user-rejected', message: { content: [{ type: 'tool_result', tool_use_id: 'exit1', is_error: true, content: 'no' }] } },
    plan('msg_3', 'exit2', '   '),
  ))
  const { messages, tools } = readHistory(file)
  assert.deepEqual(messages.map((m) => [m.message, m.kind ?? null, m.text]), [
    ['u1', null, 'plan it'], ['msg_1', null, 'Here it is.'], ['exit1:plan', 'plan', '# Plan\n\n1. Do it'],
  ])
  assert.deepEqual(tools.map((t) => [t.tool_call, t.after, t.status]), [['exit1', 'exit1:plan', 'denied'], ['exit2', 'exit1:plan', 'error']])
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

function provider(projectsDir: string, runningSessions: (claude: string, env: Record<string, string>) => Promise<Running> = NOT_KNOWN) {
  const opened: string[] = []
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    runningSessions,
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
    sock = net.connect(bridgeOf(env).port, '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    sock.write(JSON.stringify({ type: 'hello', token: bridgeOf(env).token }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
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
    sock = net.connect(bridgeOf(env).port, '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    const got: any[] = []
    sock.setEncoding('utf8').on('data', (d: string) => got.push(...d.trim().split('\n').map((l) => JSON.parse(l)).filter((m) => m.type !== 'welcome')))
    sock.write(JSON.stringify({ type: 'hello', token: bridgeOf(env).token }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
    await c.next('session.created')
    for (let i = 0; i < 100 && got.length === 0; i++) await new Promise((res) => setTimeout(res, 10))
    assert.deepEqual(got, [{ type: 'chat', text: 'start with the tests' }])
  } finally { sock?.destroy(); await c.close(); await srv.close(); await p.shutdown() }
})

test("running in a terminal the game doesn't follow: not listed, and not resumed (the conversation would run twice)", async () => {
  const s = store()
  let running: Running = { ids: new Set([ID(6)]) }
  const { p, opened } = provider(s.dir, async () => running)
  const srv = await testServer([p])
  const c = await connect(srv.port, srv.token)
  try {
    await c.sync()
    const listed = (await c.command({ type: 'session.list_stored', provider: 'claude' })).result as { sessions: any[] }
    assert.deepEqual(listed.sessions.map((x) => x.native_id), [ID(1), ID(2), ID(8)])
    const bad = await c.command({ type: 'session.resume', provider: 'claude', native_id: ID(6) })
    assert.deepEqual([bad.type, bad.code], ['error', 'provider_error'])
    assert.match(String(bad.message), /still running in a terminal/)
    assert.deepEqual(opened, [], 'no terminal opened')
    // Once it has exited there, it's listed and resumable again.
    running = { ids: new Set() }
    const after = (await c.command({ type: 'session.list_stored', provider: 'claude' })).result as { sessions: any[] }
    assert.deepEqual(after.sessions.map((x) => x.native_id), [ID(1), ID(6), ID(2), ID(8)])
    assert.equal((await c.command({ type: 'session.resume', provider: 'claude', native_id: ID(6) })).type, 'ok')
    assert.deepEqual(c.invalid, [])
  } finally { await c.close(); await srv.close(); await p.shutdown() }
})

test("when Claude Code can't say what runs, everything is listed and the reason is logged", async () => {
  const s = store()
  const log = new RecordingLog()
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(), log, projectsDir: s.dir, findClaude: FOUND, runningSessions: async () => ({ none: 'disabled by the disableAgentView setting' }) })
  assert.deepEqual((await p.listStored()).map((x) => x.native_id), [ID(1), ID(6), ID(2), ID(8)])
  assert.ok(log.lines.some((l) => l.includes('disableAgentView')))
})

test('asking which sessions run: the claude found, in the clean environment launches get, found once', async () => {
  const s = store()
  const saved = { CLAUDECODE: process.env.CLAUDECODE, CLAUDE_CONFIG_DIR: process.env.CLAUDE_CONFIG_DIR }
  process.env.CLAUDECODE = '1'
  process.env.CLAUDE_CONFIG_DIR = path.join(os.tmpdir(), 'user-config')
  try {
    let finds = 0
    const asked: Array<{ claude: string; env: Record<string, string> }> = []
    const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
      projectsDir: s.dir,
      findClaude: async () => { finds++; return FOUND() },
      runningSessions: async (claude, env) => { asked.push({ claude, env }); return { ids: new Set() } },
    })
    await p.listStored()
    await p.listStored()
    assert.equal(finds, 1, 'the claude found is kept for asking')
    assert.equal(asked.length, 2)
    assert.equal(asked[0]!.claude, process.execPath)
    assert.equal(asked[0]!.env.CLAUDECODE, undefined, "a session's markers are left out")
    assert.equal(asked[0]!.env.CLAUDE_CONFIG_DIR, path.join(os.tmpdir(), 'user-config'), "the user's settings are kept")
  } finally {
    for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v }
  }
})

test("when claude isn't found, everything is listed and the reason is logged", async () => {
  const s = store()
  const log = new RecordingLog()
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(), log, projectsDir: s.dir, findClaude: async () => { throw new Error('no claude here') } })
  assert.deepEqual((await p.listStored()).map((x) => x.native_id), [ID(1), ID(6), ID(2), ID(8)])
  assert.ok(log.lines.some((l) => l.includes('no claude here')))
})
