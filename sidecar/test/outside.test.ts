// Read-only islands for sessions started outside the game (NOTES.md -> S08):
// which of `claude agents --json`'s sessions get one, shown from their
// transcripts like S07's read-only sessions, in the first sync or later,
// ended once no longer listed; agent view off; the poll's pace with focus;
// the player's setting turning them off and on.
// A fake listing stands in for Claude Code, and fake transcripts for its store.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { programPidFile } from '../src/launch/launcher.ts'
import type { AgentEntry, Running } from '../src/providers/claude/running.ts'
import { ClaudeProvider, OUTSIDE_SESSIONS_OFF, type ClaudeOptions } from '../src/providers/claude/index.ts'
import { OUTSIDE_READ_ONLY } from '../src/providers/claude/session.ts'
import { prepare, restoreSessions, serveOptions } from '../src/serve.ts'
import { Registry } from '../src/registry.ts'
import type { Provider } from '../src/provider.ts'
import { connect, RecordingLog, tempSessionsDir, testServer, type Msg } from './helpers.ts'

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const jsonl = (...entries: object[]) => entries.map((e) => JSON.stringify(e)).join('\n') + '\n'
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const until = async (cond: () => boolean, ms = 3000) => {
  for (const end = Date.now() + ms; !cond() && Date.now() < end;) await sleep(20)
}
const FOUND = async () => ({ path: process.execPath, version: '2.1.308' })
const self: ClaudeOptions['selfCommand'] = (mode, ...args) => ['/sidecar', mode, ...args]

/** A project folder of its own. */
const project = () => fs.mkdtempSync(path.join(os.tmpdir(), 'outside-proj-'))

/** A transcript for `id` in a projects folder, as Claude Code writes one: every entry with its cwd and entrypoint. */
function transcript(dir: string, id: string, cwd: string, entrypoint: string, ...entries: object[]): string {
  fs.mkdirSync(path.join(dir, 'slug'), { recursive: true })
  const file = path.join(dir, 'slug', `${id}.jsonl`)
  fs.writeFileSync(file, jsonl(...entries.map((e) => ({ cwd, entrypoint, ...e }))))
  return file
}

const said = (n: number, text: string) => [
  { type: 'user', uuid: `u${n}`, timestamp: '2026-10-22T10:00:01Z', message: { content: text } },
  { type: 'assistant', timestamp: '2026-10-22T10:00:02Z', message: { id: `msg_${n}`, content: [{ type: 'text', text: `re: ${text}` }] } },
]

/** A listing whose entries the test changes as it goes; counts the calls. */
function listing(entries: AgentEntry[] | Running) {
  const l = {
    now: entries as AgentEntry[] | Running,
    calls: 0,
    ask: async (): Promise<Running> => {
      l.calls++
      const now = l.now
      if (!Array.isArray(now)) return now
      return { ids: new Set(now.map((e) => e.sessionId)), agents: structuredClone(now) }
    },
  }
  return l
}

/** What the game sees at start: a provider restored from an empty sessions folder, its sidecar listening, a client synced. */
async function start(opts: Partial<ClaudeOptions> & { runningSessions: ClaudeOptions['runningSessions']; projectsDir: string }) {
  const log = new RecordingLog()
  const p = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, sessionsDir: tempSessionsDir(), agentsPollMs: 50, ...opts })
  const s = await testServer([p])
  await restoreSessions(s.registry, [p], log)
  const c = await connect(s.port, s.token)
  const { hello, snapshots } = await c.sync()
  const close = async () => { await c.close(); await s.close(); await p.shutdown() }
  return { p, s, c, log, hello, snapshots: snapshots.map((m) => m.session as Record<string, any>), close }
}

const snapshotOf = (m: Msg) => m.session as Record<string, any>

test('at start: an outside session is in the first sync, read-only and external, with its chat, title, state and start time', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', { type: 'custom-title', customTitle: 'the login fix' }, ...said(1, 'fix the login'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'busy', cwd, kind: 'interactive', startedAt: Date.parse('2026-10-22T09:59:00Z'), name: 'Session #1' }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    assert.deepEqual((r.hello.providers as any[])[0].capabilities, { outside_sessions: {} }, 'the provider declares it')
    assert.equal((r.hello.providers as any[])[0].notices, undefined, 'no notices')
    assert.equal(r.snapshots.length, 1)
    const s = r.snapshots[0]!
    assert.equal(s.origin, 'external')
    assert.equal(s.read_only, true)
    assert.equal(s.native_id, ID(1))
    assert.equal(s.project.path, cwd)
    assert.equal(s.title, 'the login fix', 'its transcript\'s title first')
    assert.equal(s.started_at, '2026-10-22T09:59:00.000Z')
    assert.deepEqual(Object.keys(s.capabilities).sort(), ['model_info', 'permission_modes', 'usage'], 'what its transcript shows, no stop or answers')
    assert.deepEqual(s.agents.map((a: any) => [a.agent, a.state]), [['main', 'working']])
    assert.deepEqual(s.notices, [OUTSIDE_READ_ONLY])
    assert.equal(OUTSIDE_READ_ONLY.message, 'This session was started outside the game, so it\'s read-only here. Use its own window to chat with it.', 'the user\'s wording')
    const history = (await r.c.command({ type: 'session.get_history', session: s.session })).result as { messages: any[] }
    assert.deepEqual(history.messages.map((m) => [m.role, m.text]), [['user', 'fix the login'], ['assistant', 're: fix the login']])
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('which: terminals, the desktop app and IDEs, not claude -p or SDK programs; one with no working folder, or a folder that isn\'t there, isn\'t shown', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'terminal'))
  transcript(projects, ID(2), cwd, 'claude-desktop', ...said(2, 'desktop'))
  transcript(projects, ID(3), cwd, 'claude-vscode', ...said(3, 'ide'))
  transcript(projects, ID(4), cwd, 'sdk-cli', ...said(4, 'a -p run'))
  transcript(projects, ID(5), cwd, 'cli', ...said(5, 'no folder listed'))
  const gone = path.join(cwd, 'deleted')
  const l = listing([
    { sessionId: ID(1), pid: 50001, status: 'idle', cwd },
    { sessionId: ID(2), pid: 50002, status: 'idle', cwd },
    { sessionId: ID(3), pid: 50003, status: 'idle', cwd },
    { sessionId: ID(4), pid: 50004, status: 'busy', cwd },
    { sessionId: ID(5), pid: 50005, status: 'idle' },
    { sessionId: ID(6), pid: 50006, status: 'idle', cwd: gone },
  ])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    assert.deepEqual(r.snapshots.map((s) => s.native_id).sort(), [ID(1), ID(2), ID(3)])
    // Still not shown on later listings.
    const before = l.calls
    await until(() => l.calls >= before + 3)
    assert.equal(r.c.received.filter((m) => m.type === 'session.snapshot').length, 0)
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('which: another project\'s transcript of the same id isn\'t taken for its own; with none of its own it waits like one not written yet', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), project(), 'cli', ...said(1, 'not this one'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    // At start it comes at once, so it's in the first sync (W12), with nothing of the other's.
    assert.equal(r.snapshots.length, 1)
    const history = (await r.c.command({ type: 'session.get_history', session: r.snapshots[0]!.session })).result
    assert.deepEqual(history, { messages: [], tools: [] })
  } finally { await r.close() }
})

test('title: its display name from claude agents when its transcript has none yet', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd, name: 'Session #7 (the API)' }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    assert.equal(r.snapshots[0]!.title, 'Session #7 (the API)')
  } finally { await r.close() }
})

test('later: a new outside session arrives as a snapshot once listed; one with no transcript only at its second listing; claude -p never', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  const l = listing([])
  const r = await start({ projectsDir: projects, runningSessions: l.ask, agentsPollMs: 200 })
  try {
    assert.deepEqual(r.snapshots, [])
    transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
    transcript(projects, ID(3), cwd, 'sdk-cli', ...said(3, 'one -p run'))
    l.now = [
      { sessionId: ID(1), pid: 50001, status: 'idle', cwd },
      { sessionId: ID(2), pid: 50002, status: 'idle', cwd },
      { sessionId: ID(3), pid: 50003, status: 'busy', cwd },
    ]
    const first = snapshotOf(await r.c.next('session.snapshot', 3000))
    assert.equal(first.native_id, ID(1))
    assert.equal(first.origin, 'external')
    const at = l.calls
    const second = snapshotOf(await r.c.next('session.snapshot', 3000))
    assert.equal(second.native_id, ID(2), 'no transcript: shown at the next listing')
    assert.ok(l.calls >= at + 1)
    const now = l.calls
    await until(() => l.calls >= now + 3)
    assert.ok(!r.c.received.some((m) => m.type === 'session.snapshot'), 'the claude -p run never')
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('later: a claude -p run that writes its transcript before the next listing is never shown', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  const l = listing([])
  const r = await start({ projectsDir: projects, runningSessions: l.ask, agentsPollMs: 100 })
  try {
    l.now = [{ sessionId: ID(3), pid: 50003, status: 'busy', cwd }]
    const seen = l.calls
    await until(() => l.calls >= seen + 1)
    transcript(projects, ID(3), cwd, 'sdk-cli', ...said(3, 'a -p run'))
    const now = l.calls
    await until(() => l.calls >= now + 3)
    assert.ok(!r.c.received.some((m) => m.type === 'session.snapshot'))
  } finally { await r.close() }
})

test('ending: one no longer listed ends (exited) and is never asked about again', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    const id = r.snapshots[0]!.session
    l.now = []
    const ended = await r.c.next('session.ended', 3000)
    assert.equal(ended.session, id)
    assert.equal(ended.reason, 'exited')
    assert.equal(((r.p as any).watched as Map<number, unknown>).size, 0)
    assert.equal(((r.p as any).outside as Map<number, unknown>).size, 0)
    // Listed again (the same process): back as a new island.
    l.now = [{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }]
    const back = snapshotOf(await r.c.next('session.snapshot', 3000))
    assert.notEqual(back.session, id)
  } finally { await r.close() }
})

test('read-only: the world can\'t send, stop or answer; what the terminal does shows from the transcript; nothing is written anywhere', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  const sessionsDir = tempSessionsDir()
  const file = transcript(projects, ID(1), cwd, 'claude-desktop', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, sessionsDir, runningSessions: l.ask })
  try {
    const session = r.snapshots[0]!.session
    const sent = await r.c.command({ type: 'message.send', session, text: 'hi' })
    assert.equal(sent.type, 'error')
    assert.equal(sent.code, 'not_supported')
    const stop = await r.c.command({ type: 'interrupt.request', session })
    assert.equal(stop.code, 'not_supported')
    const answer = await r.c.command({ type: 'permission.respond', session, permission: 'p1', decision: 'allow' })
    assert.equal(answer.code, 'invalid_message', 'nothing of it is ever pending')
    // Typed in its own window: seen from the transcript.
    fs.appendFileSync(file, jsonl({ type: 'user', uuid: 'u2', cwd, entrypoint: 'claude-desktop', message: { content: 'and now this' } }))
    const typed = await r.c.next((m) => m.type === 'message.completed' && m.text === 'and now this', 5000)
    assert.ok(typed)
    assert.deepEqual(fs.readdirSync(cwd), [], 'nothing written in its folder')
    assert.deepEqual(fs.existsSync(sessionsDir) ? fs.readdirSync(sessionsDir).filter((n) => n.startsWith('session-')) : [], [], 'and no run folder')
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('/clear in an outside session is followed: the new conversation once its transcript is there, from Claude Code\'s listing', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    const session = r.snapshots[0]!.session
    l.now = [{ sessionId: ID(2), pid: 50001, status: 'idle', cwd }]
    await sleep(200)
    transcript(projects, ID(2), cwd, 'cli', { type: 'user', uuid: 'n1', message: { content: 'fresh start' } })
    const updated = await r.c.next((m) => m.type === 'session.updated' && m.native_id === ID(2), 3000)
    assert.equal(updated.session, session, 'the same island')
    await r.c.next((m) => m.type === 'session.notice' && (m.notice as any).code === 'conversation_cleared')
    assert.ok(!r.c.received.some((m) => m.type === 'session.ended'), 'not taken for a session gone')
  } finally { await r.close() }
})

test('ours are left out: a session the world launched, by its session id and by the process its launcher started', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  let runDir = ''
  const l = listing([])
  const r = await start({
    projectsDir: projects, runningSessions: l.ask,
    openTerminal: async (req) => { runDir = req.runDir!; fs.writeFileSync(programPidFile(req.runDir!), '50077'); return 'fake' },
  })
  try {
    const created = await r.c.command({ type: 'session.create', provider: 'claude', project: { path: cwd } })
    assert.equal(created.type, 'ok', JSON.stringify(created))
    const launch = JSON.parse(fs.readFileSync(path.join(runDir, 'launch.json'), 'utf8')) as { args: string[] }
    const nativeId = launch.args[launch.args.indexOf('--session-id') + 1]!
    transcript(projects, nativeId, cwd, 'cli', ...said(1, 'ours'))
    transcript(projects, ID(9), cwd, 'cli', ...said(9, 'ours after /clear'))
    // Listed by its own id, then (a /clear the hooks haven't told yet) by another id under its process.
    l.now = [{ sessionId: nativeId, pid: 50088, status: 'idle', cwd }]
    let now = l.calls
    await until(() => l.calls >= now + 3)
    l.now = [{ sessionId: ID(9), pid: 50077, status: 'idle', cwd }]
    now = l.calls
    await until(() => l.calls >= now + 3)
    assert.ok(!r.c.received.some((m) => m.type === 'session.snapshot'), 'never an island of its own')
  } finally { await r.close() }
})

test('agent view off at start: the notice once, in hello, and no more looking for outside sessions', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const l = listing({ none: "'claude agents --json' is disabled by CLAUDE_CODE_DISABLE_AGENT_VIEW.", disabled: true })
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    assert.deepEqual((r.hello.providers as any[])[0].notices, [OUTSIDE_SESSIONS_OFF])
    assert.equal(OUTSIDE_SESSIONS_OFF.message, 'Sessions started outside the game can\'t be shown: agent view is off in Claude Code.')
    const calls = l.calls
    await sleep(400)
    assert.equal(l.calls, calls, 'not asked again')
    // A second client gets it in hello too; it's never sent twice.
    const c2 = await connect(r.s.port, r.s.token)
    const { hello } = await c2.sync()
    assert.deepEqual((hello.providers as any[])[0].notices, [OUTSIDE_SESSIONS_OFF])
    await c2.close()
    assert.ok(!r.c.received.some((m) => m.type === 'provider.notice'))
  } finally { await r.close() }
})

test('agent view turned off while the game runs: the notice as an event, and the outside sessions end', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    assert.equal(r.snapshots.length, 1)
    l.now = { none: "'claude agents --json' is disabled by the 'disableAgentView' setting.", disabled: true }
    const notice = await r.c.next('provider.notice', 3000)
    assert.deepEqual(notice, { type: 'provider.notice', provider: 'claude', notice: OUTSIDE_SESSIONS_OFF })
    const ended = await r.c.next('session.ended', 3000)
    assert.equal(ended.session, r.snapshots[0]!.session)
    const calls = l.calls
    await sleep(300)
    assert.equal(l.calls, calls, 'no more polls: nothing left to ask about')
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('another failure (slow, missing claude): logged once, the sessions stay, and the poll goes on', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    l.now = { none: 'spawn claude ETIMEDOUT' }
    const calls = l.calls
    await until(() => l.calls >= calls + 4)
    assert.equal(r.log.lines.filter((x) => x.includes('spawn claude ETIMEDOUT')).length, 1, 'logged once')
    assert.ok(!r.c.received.some((m) => m.type === 'session.ended' || m.type === 'provider.notice'))
    l.now = []
    await r.c.next('session.ended', 3000)
  } finally { await r.close() }
})

test('focus: asked every AGENTS_POLL_MS with the window focused, AGENTS_POLL_BACKGROUND_MS without (client.set_focus)', { timeout: 15_000 }, async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const l = listing([])
  const r = await start({ projectsDir: projects, runningSessions: l.ask, agentsPollMs: 50, agentsPollBackgroundMs: 600 })
  try {
    const count = async (ms: number) => { const at = l.calls; await sleep(ms); return l.calls - at }
    assert.ok(await count(1000) >= 8, 'focused: often')
    assert.equal((await r.c.command({ type: 'client.set_focus', focused: false })).type, 'ok')
    const background = await count(1000)
    assert.ok(background >= 1 && background <= 2, `background: ${background} in 1 s`)
    assert.equal((await r.c.command({ type: 'client.set_focus', focused: true })).type, 'ok')
    assert.ok(await count(500) >= 4, 'focused again: at once, not after the slow wait')
    const bad = await r.c.command({ type: 'client.set_focus', focused: 'yes' })
    assert.equal(bad.code, 'invalid_message')
  } finally { await r.close() }
})

test('the defaults: 5 s with focus, 10 s without (S08\'s decision)', async () => {
  const { AGENTS_POLL_MS, AGENTS_POLL_BACKGROUND_MS } = await import('../src/providers/claude/index.ts')
  assert.equal(AGENTS_POLL_MS, 5000)
  assert.equal(AGENTS_POLL_BACKGROUND_MS, 10_000)
})

test('the provider\'s shutdown stops the poll', async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const l = listing([])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    await until(() => l.calls >= 3)
    await r.p.shutdown()
    const stopped = l.calls
    await sleep(300)
    assert.equal(l.calls, stopped)
  } finally { await r.close() }
})

test('turned off (client.set_outside_sessions): each ends (user), no more polls, none shown; back on: asked at once, rising (session.created)', { timeout: 15_000 }, async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const r = await start({ projectsDir: projects, runningSessions: l.ask, agentsPollMs: 100 })
  try {
    const id = r.snapshots[0]!.session
    // Sent as is: command() would read past the session.ended before its reply.
    r.c.send({ type: 'client.set_outside_sessions', id: 'off', enabled: false })
    const ended = await r.c.next('session.ended', 3000)
    assert.equal((await r.c.next((m) => m.id === 'off')).type, 'ok')
    assert.deepEqual([ended.session, ended.reason], [id, 'user'])
    const calls = l.calls
    // A new one, even with no transcript yet: shown at once when turned back on.
    l.now = [{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }, { sessionId: ID(2), pid: 50002, status: 'busy', cwd }]
    await sleep(400)
    assert.ok(l.calls <= calls + 1, 'no more polls (one may have been on its way)')
    assert.ok(!r.c.received.some((m) => m.type === 'session.snapshot' || m.type === 'session.created'))
    assert.equal((await r.c.command({ type: 'client.set_outside_sessions', enabled: false })).type, 'ok', 'off twice: nothing')

    // Slow polls from here, so "at once" can't be the timer.
    ;(r.p as any).opts.agentsPollMs = 60_000
    const at = Date.now()
    r.c.send({ type: 'client.set_outside_sessions', id: 'on', enabled: true })
    const created = () => r.c.received.filter((m) => m.type === 'session.created').map(snapshotOf)
    await until(() => created().length === 2, 2000)
    assert.ok(Date.now() - at < 2000, 'at once')
    assert.ok(r.c.received.some((m) => m.id === 'on' && m.type === 'ok'))
    const [a, b] = created() as [Record<string, any>, Record<string, any>]
    assert.deepEqual([a.native_id, b.native_id].sort(), [ID(1), ID(2)])
    for (const s of [a, b]) {
      assert.equal(s.origin, 'external')
      assert.equal(s.read_only, true)
      // Its notice follows, as an event (a snapshot in the sync has it in its notices).
      assert.ok(r.c.received.some((m) => m.type === 'session.notice' && m.session === s.session && (m.notice as { code: string }).code === OUTSIDE_READ_ONLY.code))
    }
    assert.notEqual(a.session, id, 'a new island')
    assert.ok(!r.c.received.some((m) => m.type === 'session.snapshot'))
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('turned back on: later ones arrive as snapshots again, a session with no transcript waiting its listing as before', { timeout: 15_000 }, async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  const l = listing([])
  const r = await start({ projectsDir: projects, runningSessions: l.ask, agentsPollMs: 150 })
  try {
    await r.c.command({ type: 'client.set_outside_sessions', enabled: false })
    await r.c.command({ type: 'client.set_outside_sessions', enabled: true })
    const at = l.calls
    await until(() => l.calls >= at + 2)
    l.now = [{ sessionId: ID(2), pid: 50002, status: 'idle', cwd }]
    const seen = l.calls
    const s = snapshotOf(await r.c.next('session.snapshot', 3000))
    assert.equal(s.native_id, ID(2))
    assert.ok(l.calls >= seen + 2, 'no transcript: shown at its second listing')
    assert.ok(!r.c.received.some((m) => m.type === 'session.created'))
  } finally { await r.close() }
})

test('off from the start (serve --no-outside-sessions): none in the first sync, claude never asked; on later: they rise, or agent view off is said then', { timeout: 15_000 }, async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const log = new RecordingLog()
  const p = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, sessionsDir: tempSessionsDir(), agentsPollMs: 50, projectsDir: projects, runningSessions: l.ask })
  p.setOutsideSessions(false)
  const s = await testServer([p])
  await restoreSessions(s.registry, [p], log)
  const c = await connect(s.port, s.token)
  try {
    const { hello, snapshots } = await c.sync()
    assert.deepEqual(snapshots, [])
    assert.deepEqual((hello.providers as any[])[0].capabilities, { outside_sessions: {} }, 'still declared: the setting can be turned on')
    assert.equal(l.calls, 0, 'not asked at the restore')
    await sleep(300)
    assert.equal(l.calls, 0, 'no polls')
    assert.equal((await c.command({ type: 'client.set_outside_sessions', enabled: true })).type, 'ok')
    assert.equal(snapshotOf(await c.next('session.created', 2000)).native_id, ID(1))
  } finally { await c.close(); await s.close(); await p.shutdown() }

  // Agent view off with the setting off: found once turned on, and said then.
  const off = listing({ none: 'disabled', disabled: true })
  const p2 = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, sessionsDir: tempSessionsDir(), agentsPollMs: 50, projectsDir: projects, runningSessions: off.ask })
  p2.setOutsideSessions(false)
  const s2 = await testServer([p2])
  await restoreSessions(s2.registry, [p2], log)
  const c2 = await connect(s2.port, s2.token)
  try {
    const { hello } = await c2.sync()
    assert.equal((hello.providers as any[])[0].notices, undefined)
    assert.equal(off.calls, 0)
    assert.equal((await c2.command({ type: 'client.set_outside_sessions', enabled: true })).type, 'ok')
    assert.deepEqual((await c2.next('provider.notice', 2000)).notice, OUTSIDE_SESSIONS_OFF)
    // No more asking (agent view stays off this launch), even turned off and on again.
    await c2.command({ type: 'client.set_outside_sessions', enabled: false })
    await c2.command({ type: 'client.set_outside_sessions', enabled: true })
    await sleep(300)
    assert.equal(off.calls, 1)
  } finally { await c2.close(); await s2.close(); await p2.shutdown() }
})

test('turned off: S07\'s read-only sessions still polled; a bad command refused', { timeout: 15_000 }, async () => {
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const l = listing([])
  const r = await start({ projectsDir: projects, runningSessions: l.ask })
  try {
    // A read-only session of ours stands in: one watched program.
    ;(r.p as any).watched.set(40001, { onAgent() {}, host: { id: 'x' } })
    await r.c.command({ type: 'client.set_outside_sessions', enabled: false })
    const at = l.calls
    await until(() => l.calls >= at + 3)
    assert.ok(l.calls >= at + 3, 'the poll goes on for it')
    ;(r.p as any).watched.clear()
    const bad = await r.c.command({ type: 'client.set_outside_sessions', enabled: 'no' })
    assert.equal(bad.code, 'invalid_message')
  } finally { await r.close() }
})

test('serve --no-outside-sessions: parsed, and set before the restore, so none is shown and claude isn\'t asked', async () => {
  assert.deepEqual(serveOptions([]), { outsideSessions: true })
  assert.deepEqual(serveOptions(['--no-outside-sessions']), { outsideSessions: false })
  assert.throws(() => serveOptions(['--no-outside-sessions', 'extra']), /unexpected arguments: extra/)
  assert.throws(() => serveOptions(['--outside-sessions']), /unexpected arguments/)

  const order: string[] = []
  const spy = {
    id: 'spy', name: 'Spy',
    setOutsideSessions: (on: boolean) => { order.push(`set ${on}`) },
    restore: async () => { order.push('restore') },
    shutdown: async () => {},
  } as unknown as Provider
  const log = new RecordingLog()
  await prepare(new Registry([spy], log), [spy], log, { outsideSessions: false })
  assert.deepEqual(order, ['set false', 'restore'])
  order.length = 0
  await prepare(new Registry([spy], log), [spy], log, { outsideSessions: true })
  assert.deepEqual(order, ['restore'], 'on: left as the provider starts (on)')

  // The Claude provider: nothing listed, nothing asked.
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const cwd = project()
  transcript(projects, ID(1), cwd, 'cli', ...said(1, 'hello'))
  const l = listing([{ sessionId: ID(1), pid: 50001, status: 'idle', cwd }])
  const p = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, sessionsDir: tempSessionsDir(), agentsPollMs: 50, projectsDir: projects, runningSessions: l.ask })
  const registry = new Registry([p], log)
  try {
    await prepare(registry, [p], log, serveOptions(['--no-outside-sessions']))
    await sleep(200)
    assert.equal(l.calls, 0)
    assert.deepEqual(registry.snapshots(), [])
  } finally { await p.shutdown() }
})
