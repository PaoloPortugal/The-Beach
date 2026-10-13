// Reattaching to running sessions after a restart (NOTES.md -> S07): where
// run folders live, what they record and how it's checked, the kept hook
// port, and taking sessions back from fake run folders (a live node process
// stands in for the launcher and for Claude Code).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { spawn, type ChildProcess } from 'node:child_process'
import { APP_FOLDER, appDataDir, sessionsDir, TEST_SESSIONS_DIR } from '../src/launch/app-data.ts'
import { programPidFile, launcherPidFile } from '../src/launch/launcher.ts'
import { readRelayFile, writeRelayFile } from '../src/launch/relay.ts'
import { HookServer } from '../src/providers/claude/hook-server.ts'
import { readBridgeFile } from '../src/providers/claude/bridge.ts'
import {
  HOLDER_FILE, HOOK_PORT_FILE, readHookPort, readRunRecord, RUN_RECORD_FILE, writeHookPort, writeRunRecord, type RunRecord,
} from '../src/providers/claude/run-folder.ts'
import type { AgentEntry, Running } from '../src/providers/claude/running.ts'
import { ClaudeProvider, type ClaudeOptions } from '../src/providers/claude/index.ts'
import { REATTACHED_LIMITED } from '../src/providers/claude/session.ts'
import { TranscriptHooks, type Fed } from '../src/providers/claude/transcript-hooks.ts'
import { TranscriptFollower, type TranscriptSignal } from '../src/providers/claude/transcript.ts'
import { RESTORE_WAIT_MS, restoreSessions } from '../src/serve.ts'
import type { Provider } from '../src/provider.ts'
import { bridgeOf, connect, RecordingLog, tempSessionsDir, testServer, type Msg } from './helpers.ts'

const ID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`
const TOKEN = (c: string) => c.repeat(64)
const jsonl = (...entries: object[]) => entries.map((e) => JSON.stringify(e)).join('\n') + '\n'
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const until = async (cond: () => boolean, ms = 3000) => {
  for (const end = Date.now() + ms; !cond() && Date.now() < end;) await sleep(20)
}

// ---- where run folders live ----

test('app data: the user\'s own folder per platform; a relative XDG_STATE_HOME or LOCALAPPDATA is ignored', () => {
  const A = APP_FOLDER
  assert.equal(appDataDir('win32', { LOCALAPPDATA: 'C:\\Users\\u\\AppData\\Local' }, 'C:\\Users\\u'), `C:\\Users\\u\\AppData\\Local\\${A}`)
  assert.equal(appDataDir('win32', { LOCALAPPDATA: 'relative' }, 'C:\\Users\\u'), `C:\\Users\\u\\AppData\\Local\\${A}`)
  assert.equal(appDataDir('win32', {}, 'C:\\Users\\u'), `C:\\Users\\u\\AppData\\Local\\${A}`)
  assert.equal(appDataDir('darwin', {}, '/Users/u'), `/Users/u/Library/Application Support/${A}`)
  assert.equal(appDataDir('linux', { XDG_STATE_HOME: '/x/state' }, '/home/u'), `/x/state/${A}`)
  assert.equal(appDataDir('linux', { XDG_STATE_HOME: 'state' }, '/home/u'), `/home/u/.local/state/${A}`)
  assert.equal(appDataDir('linux', {}, '/home/u'), `/home/u/.local/state/${A}`)
  assert.equal(sessionsDir('win32', {}, 'C:\\Users\\u'), `C:\\Users\\u\\AppData\\Local\\${A}\\agent-sessions`)
  assert.equal(sessionsDir('linux', {}, '/home/u'), `/home/u/.local/state/${A}/agent-sessions`)
})

test('app data: the Godot suites\' own sessions folder, when absolute', () => {
  assert.equal(sessionsDir('win32', { [TEST_SESSIONS_DIR]: 'C:\\Temp\\t' }, 'C:\\Users\\u'), 'C:\\Temp\\t')
  assert.equal(sessionsDir('linux', { [TEST_SESSIONS_DIR]: '/tmp/t' }, '/home/u'), '/tmp/t')
  assert.equal(sessionsDir('linux', { [TEST_SESSIONS_DIR]: 'tmp/t' }, '/home/u'), `/home/u/.local/state/${APP_FOLDER}/agent-sessions`)
})

// ---- what a run folder records ----

function goodRecord(project = os.tmpdir()): Omit<RunRecord, 'version'> {
  return { native_id: ID(1), project: { path: project, name: 'proj' }, hook_port: 4321, hook_token: TOKEN('a'), started_at: '2026-10-13T10:00:00.000Z' }
}

test('session.json: written owner-only and read back; any field that fails a check makes it unusable', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'run-'))
  writeRunRecord(dir, goodRecord())
  if (process.platform !== 'win32') assert.equal(fs.statSync(path.join(dir, RUN_RECORD_FILE)).mode & 0o777, 0o600)
  assert.deepEqual(readRunRecord(dir), { version: 1, ...goodRecord() })
  const good = { version: 1, ...goodRecord() }
  for (const bad of [
    { ...good, version: 2 }, { ...good, native_id: '../../x' }, { ...good, native_id: 7 },
    { ...good, hook_port: 0 }, { ...good, hook_port: 65536 }, { ...good, hook_port: 80.5 }, { ...good, hook_port: '4321' },
    { ...good, hook_token: 'short' }, { ...good, hook_token: TOKEN('A') }, { ...good, started_at: 'yesterday' },
    { ...good, project: { path: 'relative' } }, { ...good, project: null }, { ...good, project: { path: os.tmpdir(), name: 3 } },
    [], null,
  ]) {
    fs.writeFileSync(path.join(dir, RUN_RECORD_FILE), JSON.stringify(bad))
    assert.equal(readRunRecord(dir), null, JSON.stringify(bad))
  }
  fs.writeFileSync(path.join(dir, RUN_RECORD_FILE), '{ not json')
  assert.equal(readRunRecord(dir), null)
  fs.rmSync(path.join(dir, RUN_RECORD_FILE))
  assert.equal(readRunRecord(dir), null)
  // Unknown fields don't come along.
  fs.writeFileSync(path.join(dir, RUN_RECORD_FILE), JSON.stringify({ ...good, extra: 'x', project: { path: os.tmpdir(), evil: 1 } }))
  assert.deepEqual(readRunRecord(dir), { ...good, project: { path: os.tmpdir() } })
})

test('the kept hook port: read back, anything else is none', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kept-'))
  assert.equal(readHookPort(dir), null)
  writeHookPort(dir, 5555)
  assert.equal(readHookPort(dir), 5555)
  for (const bad of ['{"port":0}', '{"port":"5555"}', '{"port":70000}', '[]', 'nope']) {
    fs.writeFileSync(path.join(dir, HOOK_PORT_FILE), bad)
    assert.equal(readHookPort(dir), null, bad)
  }
})

// ---- the hook server ----

/** A port nothing listens on (just freed). */
async function freePort(): Promise<number> {
  const s = net.createServer()
  await new Promise<void>((r) => s.listen(0, '127.0.0.1', () => r()))
  const port = (s.address() as net.AddressInfo).port
  await new Promise<void>((r) => s.close(() => r()))
  return port
}

/** Something else listening on a port (another program took it). */
async function occupy(): Promise<{ port: number; close: () => Promise<void> }> {
  const s = net.createServer()
  await new Promise<void>((r) => s.listen(0, '127.0.0.1', () => r()))
  return { port: (s.address() as net.AddressInfo).port, close: () => new Promise((r) => s.close(() => r())) }
}

function post(port: number, token: string, body: object, at = '/hook'): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: at, headers: { authorization: `Bearer ${token}` } }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d: string) => { b += d }).on('end', () => resolve({ status: res.statusCode ?? 0, body: b }))
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
}

test('hook server: listens on the kept port, or on another when it\'s taken', async () => {
  const kept = await freePort()
  const a = new HookServer(new RecordingLog())
  try { assert.equal(await a.start(kept), kept) } finally { await a.close() }

  const taken = await occupy()
  const log = new RecordingLog()
  const b = new HookServer(log)
  try {
    const port = await b.start(taken.port)
    assert.notEqual(port, taken.port)
    assert.ok(log.lines.some((l) => l.startsWith('warn') && l.includes(`${taken.port} is taken`)))
  } finally { await b.close(); await taken.close() }
})

test('hook server: adopts an earlier sidecar\'s token; refuses odd shapes and one in use', async () => {
  const hooks = new HookServer(new RecordingLog())
  const port = await hooks.start()
  try {
    const seen: string[] = []
    const link = hooks.adopt(TOKEN('b'), { onHook: (p) => { seen.push(p.hook_event_name) } })
    assert.ok(link)
    assert.equal(link.token, TOKEN('b'))
    assert.equal(hooks.adopt(TOKEN('b'), { onHook() {} }), null, 'in use already')
    for (const bad of ['', 'short', TOKEN('B'), TOKEN('g')]) assert.equal(hooks.adopt(bad, { onHook() {} }), null, bad)
    assert.equal((await post(port, TOKEN('b'), { hook_event_name: 'Stop' })).status, 200)
    assert.deepEqual(seen, ['Stop'])
    link.unregister()
    assert.equal((await post(port, TOKEN('b'), { hook_event_name: 'Stop' })).status, 401)
    // A link let go never removes the token's next holder.
    const again = hooks.adopt(TOKEN('b'), { onHook() {} })!
    link.unregister()
    assert.equal((await post(port, TOKEN('b'), { hook_event_name: 'Stop' })).status, 200)
    again.unregister()
  } finally { await hooks.close() }
})

// ---- a launched session's run folder ----

const FOUND = async () => ({ path: process.execPath, version: '2.1.296' })
const self: ClaudeOptions['selfCommand'] = (mode, ...args) => ['/sidecar', mode, ...args]

test('a launched session: its run folder in the sessions folder holds session.json and bridge.json, and outlives shutdown', async () => {
  const root = tempSessionsDir()
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'proj-'))
  let launch: { args: string[] } = { args: [] }
  let runDir = ''
  const p = new ClaudeProvider({
    sessionsDir: root, log: new RecordingLog(), findClaude: FOUND, selfCommand: self,
    openTerminal: async (req) => { runDir = req.runDir; launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  try {
    await c.sync()
    await c.command({ type: 'session.create', provider: 'claude', project: { path: project } })
    assert.equal(path.dirname(runDir), root)
    assert.match(path.basename(runDir), /^session-[A-Za-z0-9]{6}$/)
    if (process.platform !== 'win32') assert.equal(fs.statSync(runDir).mode & 0o777, 0o700)
    const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
    const hook = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.Stop[0].hooks[0]
    const record = readRunRecord(runDir)!
    assert.ok(record)
    assert.equal(record.native_id, arg('--session-id'))
    assert.equal(record.project.path, project)
    assert.equal(`http://127.0.0.1:${record.hook_port}/hook`, hook.url)
    assert.equal(`Bearer ${record.hook_token}`, hook.headers.Authorization)
    assert.ok(Math.abs(Date.parse(record.started_at) - Date.now()) < 10_000)
    // The bridge's env names only its bridge file, which holds where to connect.
    const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
    assert.deepEqual(Object.keys(env), ['BRIDGE_FILE'])
    assert.equal(path.dirname(env.BRIDGE_FILE), runDir)
    assert.ok(bridgeOf(env))
    // The port is kept for the next start.
    assert.equal(readHookPort(root), record.hook_port)
    // This sidecar holds it: another game running meanwhile leaves it alone.
    assert.equal(fs.readFileSync(path.join(runDir, HOLDER_FILE), 'utf8'), String(process.pid))
  } finally { await c.close(); await s.close(); await p.shutdown() }
  // The game quit: the session runs on, and its folder stays for the next start.
  assert.ok(fs.existsSync(path.join(runDir, RUN_RECORD_FILE)))
})

test('the kept port: a fallback never replaces it', async () => {
  const root = tempSessionsDir()
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const p = new ClaudeProvider({ sessionsDir: root, log: new RecordingLog(), findClaude: FOUND, selfCommand: self, runningSessions: async () => ({ none: 'test' }) })
  try {
    await p.restore(() => { throw new Error('nothing to take back') })
    assert.equal(readHookPort(root), taken.port, 'still the port sessions were launched with')
  } finally { await p.shutdown(); await taken.close() }
})

// ---- taking sessions back ----

const children: ChildProcess[] = []
/** A process that runs until the test ends: a live launcher or Claude Code. */
function live(): number {
  const c = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' })
  children.push(c)
  return c.pid!
}
/** A process id that was alive and isn't any more. */
async function dead(): Promise<number> {
  const c = spawn(process.execPath, ['-e', ''], { stdio: 'ignore' })
  await new Promise((r) => c.once('exit', r))
  return c.pid!
}
test.after(() => { for (const c of children) c.kill() })

interface Fake {
  runDir: string
  launcher: number
  program: number
  record: Omit<RunRecord, 'version'>
}

/** A run folder as a session launched by an earlier sidecar left it. */
function runFolder(root: string, o: {
  name?: string; launcher?: number | null; program?: number | null; record?: Partial<Omit<RunRecord, 'version'>> | 'damaged'
  relays?: boolean; project?: string
} = {}): Fake {
  fs.mkdirSync(root, { recursive: true })
  const runDir = path.join(root, o.name ?? `session-${Math.random().toString(36).slice(2, 8).padEnd(6, 'x')}`)
  fs.mkdirSync(runDir)
  const launcher = o.launcher === undefined ? live() : o.launcher
  const program = o.program === undefined ? live() : o.program
  if (launcher !== null) fs.writeFileSync(launcherPidFile(runDir), String(launcher))
  if (program !== null) fs.writeFileSync(programPidFile(runDir), String(program))
  const record = { ...goodRecord(o.project ?? fs.mkdtempSync(path.join(os.tmpdir(), 'proj-'))), ...(o.record === 'damaged' ? {} : o.record) }
  if (o.record === 'damaged') fs.writeFileSync(path.join(runDir, RUN_RECORD_FILE), '{ damaged')
  else writeRunRecord(runDir, record)
  if (o.relays) {
    writeRelayFile(path.join(runDir, 'relay.json'), { url: `http://127.0.0.1:${record.hook_port}/hook`, token: record.hook_token })
    writeRelayFile(path.join(runDir, 'status.json'), { url: `http://127.0.0.1:${record.hook_port}/status`, token: record.hook_token })
  }
  return { runDir, launcher: launcher ?? 0, program: program ?? 0, record }
}

/** Claude Code's answer to `claude agents --json`, listing these processes. */
function agentsListing(entries: AgentEntry[]): ClaudeOptions['runningSessions'] {
  return async (): Promise<Running> => ({ ids: new Set(entries.map((e) => e.sessionId)), agents: entries })
}

/** A stored transcript for `id` in a projects folder. */
function transcript(dir: string, id: string, project: string, ...entries: object[]): string {
  fs.mkdirSync(path.join(dir, 'proj'), { recursive: true })
  const file = path.join(dir, 'proj', `${id}.jsonl`)
  fs.writeFileSync(file, jsonl(...entries.map((e) => ({ cwd: project, entrypoint: 'cli', ...e }))))
  return file
}

/** A provider restoring from `root`, its sidecar listening, and a client synced: what the game sees at start. */
async function restoreAndSync(opts: ClaudeOptions & { sessionsDir: string }) {
  const log = new RecordingLog()
  const p = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, ...opts })
  const s = await testServer([p])
  await restoreSessions(s.registry, [p], log)
  const c = await connect(s.port, s.token)
  const { snapshots } = await c.sync()
  const close = async () => { await c.close(); await s.close(); await p.shutdown() }
  return { p, s, c, log, snapshots: snapshots.map((m) => m.session as Record<string, any>), close }
}

test('restore: a running session comes back as a snapshot, in Claude Code\'s state, with its chat and start time', async () => {
  const root = tempSessionsDir()
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const kept = await freePort()
  writeHookPort(root, kept)
  const f = runFolder(root, { record: { hook_port: kept }, relays: true })
  const relayBefore = fs.readFileSync(path.join(f.runDir, 'relay.json'), 'utf8')
  transcript(projects, ID(1), f.record.project.path,
    { type: 'custom-title', customTitle: 'the login fix' },
    { type: 'user', uuid: 'u1', timestamp: '2026-10-13T10:00:01Z', message: { content: 'fix the login' } },
    { type: 'assistant', timestamp: '2026-10-13T10:00:02Z', message: { id: 'msg_1', content: [{ type: 'text', text: 'On it.' }] } },
  )
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: projects,
    runningSessions: agentsListing([{ sessionId: ID(1), pid: f.program, status: 'busy' }]),
  })
  try {
    assert.equal(r.snapshots.length, 1)
    const s = r.snapshots[0]!
    assert.equal(s.native_id, ID(1))
    assert.equal(s.provider, 'claude')
    assert.equal(s.project.path, f.record.project.path)
    assert.equal(s.title, 'the login fix')
    assert.equal(s.started_at, f.record.started_at)
    assert.deepEqual(s.agents.map((a: any) => [a.agent, a.state, a.reason]), [['main', 'working', null]])
    assert.deepEqual(s.notices, [], 'its hook port was kept: nothing limited')
    const history = (await r.c.command({ type: 'session.get_history', session: s.session })).result as { messages: any[] }
    assert.deepEqual(history.messages.map((m) => [m.role, m.text]), [['user', 'fix the login'], ['assistant', 'On it.']])
    // Kept port: the relays already point here, and stay untouched.
    assert.equal(fs.readFileSync(path.join(f.runDir, 'relay.json'), 'utf8'), relayBefore)
    // Its hooks, with the old token, reach it again.
    assert.equal((await post(kept, f.record.hook_token, { hook_event_name: 'Stop', session_id: ID(1) })).status, 200)
    const updated = await r.c.next('agent.state_changed')
    assert.equal(updated.state, 'idle')
    // The bridge has a fresh one-time token to come back with.
    const bridge = readBridgeFile(path.join(f.runDir, 'bridge.json'))
    assert.ok(bridge)
    assert.notEqual(bridge.token, f.record.hook_token)
    // Not listed under Resume, not resumable twice.
    const stored = (await r.c.command({ type: 'session.list_stored', provider: 'claude' })).result as { sessions: any[] }
    assert.deepEqual(stored.sessions.filter((x) => x.native_id === ID(1)), [])
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('restore: waiting and idle sessions; a session with no transcript comes back with an empty chat', async () => {
  const root = tempSessionsDir()
  const a = runFolder(root, { record: { native_id: ID(1) } })
  const b = runFolder(root, { record: { native_id: ID(2), hook_token: TOKEN('c') } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: fs.mkdtempSync(path.join(os.tmpdir(), 'projects-')),
    runningSessions: agentsListing([
      { sessionId: ID(1), pid: a.program, status: 'waiting' },
      { sessionId: ID(2), pid: b.program, status: 'idle' },
    ]),
  })
  try {
    const by = new Map(r.snapshots.map((s) => [s.native_id, s]))
    assert.deepEqual(by.get(ID(1))!.agents[0].state, 'waiting')
    assert.deepEqual(by.get(ID(1))!.agents[0].reason, 'input')
    assert.deepEqual(by.get(ID(2))!.agents[0].state, 'idle')
    const history = (await r.c.command({ type: 'session.get_history', session: by.get(ID(2))!.session })).result
    assert.deepEqual(history, { messages: [], tools: [] })
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('restore: folders of sessions gone are deleted; ones it can\'t read are left alone; nothing else is touched', async () => {
  const root = tempSessionsDir()
  const launcherGone = runFolder(root, { launcher: await dead() })
  const notListed = runFolder(root)
  const neverStarted = runFolder(root, { launcher: null, program: null })
  const old = new Date(Date.now() - 60_000)
  fs.utimesSync(neverStarted.runDir, old, old)
  const stillOpening = runFolder(root, { launcher: null, program: null })
  const damaged = runFolder(root, { record: 'damaged' })
  const noProgram = runFolder(root, { program: null })
  const other = runFolder(root, { name: 'not-a-run-folder', launcher: await dead() })
  fs.writeFileSync(path.join(root, 'session-file1'), 'a file, not a folder')
  const r = await restoreAndSync({
    sessionsDir: root, startupTimeoutMs: 30_000,
    // Lists another session, not this folder's program.
    runningSessions: agentsListing([{ sessionId: ID(9), pid: 1, status: 'idle' }]),
  })
  try {
    assert.deepEqual(r.snapshots, [])
    assert.equal(fs.existsSync(launcherGone.runDir), false, 'its launcher exited')
    assert.equal(fs.existsSync(notListed.runDir), false, 'Claude Code no longer lists its process')
    assert.equal(fs.existsSync(neverStarted.runDir), false, 'no launcher, past the startup timeout')
    assert.equal(fs.existsSync(stillOpening.runDir), true, 'no launcher yet, its terminal may still be opening')
    assert.equal(fs.existsSync(damaged.runDir), true, 'no usable record: left alone')
    assert.equal(fs.existsSync(noProgram.runDir), true, 'its program never started: left alone')
    assert.equal(fs.existsSync(other.runDir), true, 'not a run folder\'s name')
    assert.equal(fs.existsSync(path.join(root, 'session-file1')), true)
  } finally { await r.close() }
})

test('restore: a folder held by another game still running is left alone, even its launcher gone; one whose holder exited is taken', async () => {
  const root = tempSessionsDir()
  const held = runFolder(root, { launcher: await dead() })
  fs.writeFileSync(path.join(held.runDir, HOLDER_FILE), String(live()))
  const heldStarting = runFolder(root, { launcher: null, program: null })
  fs.writeFileSync(path.join(heldStarting.runDir, HOLDER_FILE), String(live()))
  const old = new Date(Date.now() - 60_000)
  fs.utimesSync(heldStarting.runDir, old, old)
  const orphan = runFolder(root)
  fs.writeFileSync(path.join(orphan.runDir, HOLDER_FILE), String(await dead()))
  const r = await restoreAndSync({
    sessionsDir: root, startupTimeoutMs: 30_000,
    runningSessions: agentsListing([{ sessionId: orphan.record.native_id, pid: orphan.program, status: 'idle' }]),
  })
  try {
    assert.equal(fs.existsSync(held.runDir), true)
    assert.equal(fs.existsSync(heldStarting.runDir), true)
    assert.deepEqual(r.snapshots.map((s) => s.native_id), [orphan.record.native_id])
    assert.equal(fs.readFileSync(path.join(orphan.runDir, HOLDER_FILE), 'utf8'), String(process.pid), 'now held by this sidecar')
  } finally { await r.close() }
})

test('restore: when Claude Code can\'t say which sessions run, a live launcher is trusted', async () => {
  const root = tempSessionsDir()
  const f = runFolder(root)
  const gone = runFolder(root, { launcher: await dead() })
  const r = await restoreAndSync({ sessionsDir: root, runningSessions: async () => ({ none: 'agent view is off' }) })
  try {
    assert.deepEqual(r.snapshots.map((s) => [s.native_id, s.agents[0].state]), [[f.record.native_id, 'idle']])
    assert.equal(fs.existsSync(gone.runDir), false)
    assert.ok(r.log.lines.some((l) => l.includes('trusting their launchers')))
  } finally { await r.close() }
})

test('restore: /clear while the game was closed is followed: Claude Code\'s id, and the record rewritten', async () => {
  const root = tempSessionsDir()
  const f = runFolder(root, { record: { native_id: ID(1) } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: fs.mkdtempSync(path.join(os.tmpdir(), 'projects-')),
    runningSessions: agentsListing([{ sessionId: ID(2), pid: f.program, status: 'idle' }]),
  })
  try {
    assert.equal(r.snapshots[0]!.native_id, ID(2))
    const record = readRunRecord(f.runDir)!
    assert.equal(record.native_id, ID(2))
    assert.equal(record.hook_token, f.record.hook_token, 'the rest kept')
    assert.equal(record.started_at, f.record.started_at)
  } finally { await r.close() }
})

test('restore, limited: its hook port was taken: relays point to the new port with the old token, and the notice says so', async () => {
  const root = tempSessionsDir()
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const f = runFolder(root, { record: { hook_port: taken.port }, relays: true })
  const r = await restoreAndSync({
    sessionsDir: root, runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }]),
  })
  try {
    const s = r.snapshots[0]!
    assert.deepEqual(s.notices, [REATTACHED_LIMITED])
    assert.equal(REATTACHED_LIMITED.message, 'This session started before the game restarted, so some features may not work fully.')
    const relay = readRelayFile(path.join(f.runDir, 'relay.json'))!
    const status = readRelayFile(path.join(f.runDir, 'status.json'))!
    const port = Number(new URL(relay.url).port)
    assert.notEqual(port, taken.port)
    assert.equal(relay.url, `http://127.0.0.1:${port}/hook`)
    assert.equal(status.url, `http://127.0.0.1:${port}/status`)
    assert.equal(relay.token, f.record.hook_token)
    assert.equal(status.token, f.record.hook_token)
    assert.equal(readRunRecord(f.runDir)!.hook_port, taken.port, 'the record keeps the port its hooks go to')
    assert.equal(readHookPort(root), taken.port, 'and the kept port stays')
    // The relays reach it: a status line input arrives with the old token.
    assert.equal((await post(port, f.record.hook_token, { model: { id: 'claude-x' } }, '/status')).status, 200)
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close(); await taken.close() }
})

/** The bridge of a restored session coming back: connects with the token in its bridge file. */
async function bridgeBack(runDir: string) {
  const where = readBridgeFile(path.join(runDir, 'bridge.json'))!
  const sock = net.connect(where.port, '127.0.0.1')
  sock.on('error', () => {})
  const lines: Msg[] = []
  sock.setEncoding('utf8').on('data', (d: string) => { for (const l of d.trim().split('\n')) lines.push(JSON.parse(l)) })
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: where.token }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
  await until(() => lines.length > 0)
  return { sock, lines, proof: where.proof }
}

test('restore: the bridge reconnects; chat goes down it; from then on its closing ends the session, not the launcher', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const launcher = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' })
  children.push(launcher)
  const f = runFolder(root, { launcher: launcher.pid! })
  const r = await restoreAndSync({
    sessionsDir: root, runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }]),
  })
  try {
    const id = r.snapshots[0]!.session
    const b = await bridgeBack(f.runDir)
    assert.deepEqual(b.lines, [{ type: 'welcome', proof: b.proof }])
    // Nothing new is announced: it was there already.
    assert.deepEqual((await r.c.quiet()).filter((m) => m.type === 'session.created' || m.type === 'session.snapshot'), [])
    assert.equal((await r.c.command({ type: 'message.send', session: id, text: 'back again' })).type, 'ok')
    await until(() => b.lines.length > 1)
    assert.deepEqual(b.lines[1], { type: 'chat', text: 'back again' })
    // The launcher check stopped with the bridge's ready: the bridge says when it ends.
    launcher.kill()
    await sleep(1500)
    assert.ok(!r.c.received.some((m) => m.type === 'session.ended'), 'not ended by the launcher check')
    assert.ok(fs.existsSync(f.runDir))
    b.sock.destroy()
    assert.equal((await r.c.next('session.ended', 3000)).reason, 'exited')
    assert.equal(fs.existsSync(f.runDir), false, 'its folder goes with it')
    assert.deepEqual(r.c.invalid, [])
  } finally { await r.close() }
})

test('restore: until its bridge is back, the launcher exiting ends it', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const launcher = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], { stdio: 'ignore' })
  children.push(launcher)
  const f = runFolder(root, { launcher: launcher.pid! })
  const r = await restoreAndSync({
    sessionsDir: root, runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }]),
  })
  try {
    launcher.kill()
    const ended = await r.c.next('session.ended', 5000)
    assert.equal(ended.session, r.snapshots[0]!.session)
    assert.equal(fs.existsSync(f.runDir), false)
  } finally { await r.close() }
})

test('restore: a session it took back isn\'t taken twice, nor resumed', async () => {
  const root = tempSessionsDir()
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const f = runFolder(root)
  transcript(projects, f.record.native_id, f.record.project.path, { type: 'user', message: { content: 'hi' } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: projects,
    runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }]),
  })
  try {
    // A second look finds it live already.
    await r.p.restore(() => { throw new Error('taken twice') })
    const res = await r.c.command({ type: 'session.resume', provider: 'claude', native_id: f.record.native_id })
    assert.equal(res.type, 'error')
  } finally { await r.close() }
})

// ---- limited mode: seen from the transcript alone ----

const hooksOf = (fed: Fed[]) => fed.map((f) => ('denied' in f ? { denied: f.denied } : f.hook))

test('limited: transcript entries read as the hooks they stand for (shapes as 2.1.296 writes them)', () => {
  const t = new TranscriptHooks()
  const user = (content: unknown, more: object = {}) => ({ type: 'user', uuid: 'u1', message: { role: 'user', content }, ...more })
  // What the user said: typed, or from the world (meta, in our channel).
  assert.deepEqual(hooksOf(t.entry(user('fix the login'))), [{ hook_event_name: 'UserPromptSubmit', prompt: 'fix the login', prompt_id: 'u1' }])
  const world = '<channel source="world-bridge" sender="user">\nfrom the world\n</channel>'
  assert.deepEqual(hooksOf(t.entry(user(world, { isMeta: true }))), [{ hook_event_name: 'UserPromptSubmit', prompt: world, prompt_id: 'u1' }])
  // Not the user's: Claude Code's own context, slash commands, the interruption marker, a compaction summary.
  assert.deepEqual(t.entry(user('<system-reminder>x</system-reminder>', { isMeta: true })), [])
  assert.deepEqual(t.entry(user('<command-name>/model</command-name>')), [])
  assert.deepEqual(t.entry(user([{ type: 'text', text: '[Request interrupted by user]' }])), [])
  assert.deepEqual(t.entry(user('summary', { isCompactSummary: true })), [])
  // A task's notification, and a hand-back as Claude Code writes it: the translator tells them apart.
  const task = '<task-notification>\n<task-id>a1</task-id>\n<status>completed</status>\n</task-notification>'
  assert.deepEqual(hooksOf(t.entry(user(task))), [{ hook_event_name: 'UserPromptSubmit', prompt: task, prompt_id: 'u1' }])
  const handback = '<agent-message from="a1">\n[Subagent hand-back] report'
  assert.deepEqual(hooksOf(t.entry(user(`Another Claude session sent a message:\n${handback}`, { isMeta: true }))),
    [{ hook_event_name: 'UserPromptSubmit', prompt: handback, prompt_id: 'u1' }])

  // A reply, whole; a second text block of the same API message gets its own id. Thinking isn't shown.
  const reply = (content: object[], more: object = {}) => ({ type: 'assistant', message: { id: 'msg_1', content }, ...more })
  assert.deepEqual(hooksOf(t.entry(reply([{ type: 'thinking', thinking: 'hm' }, { type: 'text', text: 'On it.' }]))),
    [{ hook_event_name: 'MessageDisplay', message_id: 'msg_1', message_text: 'On it.' }])
  assert.deepEqual(hooksOf(t.entry(reply([{ type: 'text', text: 'And more.' }]))),
    [{ hook_event_name: 'MessageDisplay', message_id: 'msg_1:2', message_text: 'And more.' }])
  // Tool calls and their results.
  assert.deepEqual(hooksOf(t.entry(reply([{ type: 'tool_use', id: 'toolu_1', name: 'Bash', input: { command: 'ls' } }]))),
    [{ hook_event_name: 'PreToolUse', tool_use_id: 'toolu_1', tool_name: 'Bash', tool_input: { command: 'ls' } }])
  assert.deepEqual(hooksOf(t.entry(user([{ type: 'tool_result', tool_use_id: 'toolu_1', content: 'a.txt' }]))),
    [{ hook_event_name: 'PostToolUse', tool_use_id: 'toolu_1' }])
  assert.deepEqual(hooksOf(t.entry(user([{ type: 'tool_result', tool_use_id: 'toolu_2', is_error: true, content: 'Exit code 1' }]))),
    [{ hook_event_name: 'PostToolUseFailure', tool_use_id: 'toolu_2', error: 'Exit code 1' }])
  // Refused by a rule: denied. A "No" in the terminal is the follower's own signal.
  assert.deepEqual(hooksOf(t.entry(user([{ type: 'tool_result', tool_use_id: 'toolu_3', is_error: true }], { toolDenialKind: 'permission-rule' }))), [{ denied: 'toolu_3' }])
  assert.deepEqual(t.entry(user([{ type: 'tool_result', tool_use_id: 'toolu_4', is_error: true }], { toolDenialKind: 'user-rejected' })), [])
  // The turn's end; an API error ends it as an error, and its turn_duration changes nothing.
  assert.deepEqual(hooksOf(t.entry({ type: 'system', subtype: 'turn_duration', durationMs: 10 })), [{ hook_event_name: 'Stop' }])
  assert.deepEqual(hooksOf(t.entry(reply([{ type: 'text', text: 'API Error' }], { isApiErrorMessage: true, error: 'rate_limit' }))),
    [{ hook_event_name: 'StopFailure', error: 'rate_limit' }])
  assert.deepEqual(t.entry({ type: 'system', subtype: 'turn_duration' }), [])
  assert.deepEqual(hooksOf(t.entry({ type: 'system', subtype: 'turn_duration' })), [{ hook_event_name: 'Stop' }])
  assert.deepEqual(t.entry({ type: 'system', subtype: 'stop_hook_summary' }), [])
  // The main file's sidechain entries, and anything unknown, are skipped.
  assert.deepEqual(t.entry(reply([{ type: 'text', text: 'x' }], { isSidechain: true })), [])
  assert.deepEqual(t.entry({ type: 'permission-mode', permissionMode: 'auto' }), [])
  assert.deepEqual(t.entry(user(42)), [])
})

test('limited: subagents: started from their file, their calls theirs, a foreground one done when its call returns', () => {
  const t = new TranscriptHooks()
  assert.deepEqual(hooksOf(t.subagent('a1', 'Explore', 'toolu_A', false)),
    [{ hook_event_name: 'SubagentStart', agent_id: 'a1', agent_type: 'Explore', spawned_by: 'toolu_A' }])
  assert.deepEqual(hooksOf(t.subagent('a2', null, 'toolu_B', true)), [{ hook_event_name: 'SubagentStart', agent_id: 'a2', spawned_by: 'toolu_B' }])
  // Its own file: its calls and replies carry its id; its task prompt isn't the user's.
  assert.deepEqual(t.entry({ type: 'user', isSidechain: true, message: { content: 'look around' } }, 'a1'), [])
  assert.deepEqual(hooksOf(t.entry({ type: 'assistant', isSidechain: true, message: { id: 'm', content: [{ type: 'tool_use', id: 't1', name: 'Read', input: {} }] } }, 'a1')),
    [{ hook_event_name: 'PreToolUse', tool_use_id: 't1', tool_name: 'Read', tool_input: {}, agent_id: 'a1' }])
  assert.deepEqual(hooksOf(t.entry({ type: 'user', isSidechain: true, message: { content: [{ type: 'tool_result', tool_use_id: 't1' }] } }, 'a1')),
    [{ hook_event_name: 'PostToolUse', tool_use_id: 't1', agent_id: 'a1' }])
  assert.deepEqual(t.entry({ type: 'system', subtype: 'turn_duration' }, 'a1'), [], 'a subagent\'s turn isn\'t the session\'s')
  const result = (id: string) => ({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: id }] } })
  assert.deepEqual(hooksOf(t.entry(result('toolu_A'))), [{ hook_event_name: 'PostToolUse', tool_use_id: 'toolu_A' }, { hook_event_name: 'SubagentStop', agent_id: 'a1' }])
  // A background one's call returns at once; its task notification ends it.
  assert.deepEqual(hooksOf(t.entry(result('toolu_B'))), [{ hook_event_name: 'PostToolUse', tool_use_id: 'toolu_B' }])
})

test('limited: the follower hands over every entry, and subagents started from now on, each once its meta is there', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tr-'))
  const file = path.join(dir, `${ID(1)}.jsonl`)
  const subs = path.join(dir, ID(1), 'subagents')
  fs.mkdirSync(subs, { recursive: true })
  fs.writeFileSync(file, jsonl({ type: 'user', message: { content: 'the past' } }))
  fs.writeFileSync(path.join(subs, 'agent-old.jsonl'), jsonl({ type: 'assistant', message: { id: 'x', content: [] } }))
  const seen: TranscriptSignal[] = []
  const f = new TranscriptFollower((s) => seen.push(s))
  f.followAll()
  f.follow(file)
  try {
    fs.appendFileSync(file, jsonl({ type: 'custom-title', customTitle: 'named' }, { type: 'system', subtype: 'turn_duration' }))
    fs.writeFileSync(path.join(subs, 'agent-a1.jsonl'), jsonl({ type: 'user', isSidechain: true, message: { content: 'task' } }))
    fs.writeFileSync(path.join(subs, 'not-an-agent.jsonl'), jsonl({ type: 'user' }))
    f.poll()
    assert.deepEqual(seen, [
      { kind: 'entry', entry: { type: 'custom-title', customTitle: 'named' } },
      { kind: 'title', titles: { custom: 'named' } },
      { kind: 'entry', entry: { type: 'system', subtype: 'turn_duration' } },
    ], 'a1 waits for its meta; the one there before is the past')
    fs.writeFileSync(path.join(subs, 'agent-a1.meta.json'), JSON.stringify({ agentType: 'Explore', toolUseId: 'toolu_A', requestShape: 'foreground' }))
    fs.appendFileSync(path.join(subs, 'agent-old.jsonl'), jsonl({ type: 'assistant', message: { id: 'y', content: [] } }))
    seen.length = 0
    f.poll()
    assert.deepEqual(seen, [
      { kind: 'subagent', agent: 'a1', type: 'Explore', toolUseId: 'toolu_A', background: false },
      { kind: 'entry', entry: { type: 'user', isSidechain: true, message: { content: 'task' } }, agent: 'a1' },
    ])
    // No meta at all: started without it after a while.
    fs.writeFileSync(path.join(subs, 'agent-a2.jsonl'), '')
    seen.length = 0
    for (let i = 0; i < 10; i++) f.poll()
    assert.deepEqual(seen, [{ kind: 'subagent', agent: 'a2', type: null, toolUseId: null, background: false }])
  } finally { f.stop() }

  // Without followAll: only the signals, as before.
  const plain: TranscriptSignal[] = []
  const g = new TranscriptFollower((s) => plain.push(s))
  g.follow(file)
  try {
    fs.appendFileSync(file, jsonl({ type: 'ai-title', aiTitle: 'x' }, { type: 'system', subtype: 'turn_duration' }))
    fs.writeFileSync(path.join(subs, 'agent-a3.jsonl'), '')
    fs.writeFileSync(path.join(subs, 'agent-a3.meta.json'), '{}')
    g.poll()
    assert.deepEqual(plain, [{ kind: 'title', titles: { ai: 'x' } }])
  } finally { g.stop() }
})

test('restore, limited: a busy session stays working until its transcript ends the turn; replies, calls, prompts and subagents from it', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const f = runFolder(root, { record: { hook_port: taken.port } })
  const file = transcript(projects, f.record.native_id, f.record.project.path,
    { type: 'user', uuid: 'u1', message: { content: 'fix the login' } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: projects,
    runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'busy' }]),
  })
  const add = (...entries: object[]) => fs.appendFileSync(file, jsonl(...entries))
  try {
    const s = r.snapshots[0]!
    assert.deepEqual(s.agents.map((a: any) => a.state), ['working'])
    assert.deepEqual(Object.keys(s.capabilities).sort(), ['model_info', 'usage'], 'no questions, plans, mode or stop without hooks')
    await sleep(600)
    assert.equal(r.c.received.filter((m) => m.type === 'agent.state_changed').length, 0, 'still working: nothing says otherwise')

    // A reply, whole; a tool call.
    add({ type: 'assistant', message: { id: 'msg_1', content: [{ type: 'text', text: 'Looking.' }] } },
      { type: 'assistant', message: { id: 'msg_1', content: [{ type: 'tool_use', id: 'toolu_1', name: 'Bash', input: { command: 'git push', description: 'd' } }] } })
    const started = await r.c.next('message.started')
    assert.equal(started.role, 'assistant')
    assert.deepEqual(pick(await r.c.next('message.completed'), 'message', 'text'), { message: 'msg_1', text: 'Looking.' })
    assert.equal(r.c.received.some((m) => m.type === 'message.delta'), false, 'not streamed')
    assert.deepEqual(pick(await r.c.next('tool.started'), 'tool_call', 'tool', 'summary'), { tool_call: 'toolu_1', tool: 'Bash', summary: 'Run: git push' })

    // Its prompt, relayed by the bridge, matched to the call at once (no options to wait for), and answered from the world.
    const b = await bridgeBack(f.runDir)
    b.sock.write(JSON.stringify({ type: 'permission_request', request_id: 'abcde', tool_name: 'Bash', description: 'd', input_preview: '{"command":"git push","description":"d"}' }) + '\n')
    const asked = await r.c.next('permission.requested', 800) as any
    assert.equal(asked.permission.agent, 'main')
    assert.equal(asked.permission.summary, 'Run: git push')
    assert.equal(asked.permission.options, undefined)
    assert.equal((await r.c.next('agent.state_changed')).state, 'waiting')
    assert.equal((await r.c.command({ type: 'permission.respond', session: s.session, permission: 'abcde', decision: 'allow' })).type, 'ok')
    await until(() => b.lines.some((l) => l.type === 'verdict'))
    assert.deepEqual(b.lines.find((l) => l.type === 'verdict'), { type: 'verdict', request_id: 'abcde', behavior: 'allow' })
    add({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'toolu_1', content: 'done' }] } })
    assert.deepEqual(pick(await r.c.next('tool.finished'), 'tool_call', 'status'), { tool_call: 'toolu_1', status: 'ok' })

    // A subagent: its Agent call, then its own file.
    add({ type: 'assistant', message: { id: 'msg_2', content: [{ type: 'tool_use', id: 'toolu_A', name: 'Agent', input: { subagent_type: 'Explore', description: 'look around' } }] } })
    await r.c.next((m) => m.type === 'tool.started' && m.tool_call === 'toolu_A')
    const subs = path.join(path.dirname(file), f.record.native_id, 'subagents')
    fs.mkdirSync(subs, { recursive: true })
    fs.writeFileSync(path.join(subs, 'agent-a1.meta.json'), JSON.stringify({ agentType: 'Explore', toolUseId: 'toolu_A', requestShape: 'foreground' }))
    fs.writeFileSync(path.join(subs, 'agent-a1.jsonl'), jsonl({ type: 'user', isSidechain: true, message: { content: 'look around' } }))
    const spawned = (await r.c.next('agent.spawned')).agent as Record<string, any>
    assert.deepEqual(pick(spawned, 'agent', 'parent', 'name', 'task', 'state'), { agent: 'a1', parent: 'main', name: 'Explore', task: 'look around', state: 'working' })
    fs.appendFileSync(path.join(subs, 'agent-a1.jsonl'), jsonl({ type: 'assistant', isSidechain: true, message: { id: 'm', content: [{ type: 'tool_use', id: 't1', name: 'Read', input: { file_path: 'a.ts' } }] } }))
    assert.deepEqual(pick(await r.c.next('tool.started'), 'tool_call', 'agent', 'within'), { tool_call: 't1', agent: 'a1', within: 'toolu_A' })
    add({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'toolu_A', content: 'report' }] } })
    await r.c.next((m) => m.type === 'tool.finished' && m.tool_call === 'toolu_A')
    assert.deepEqual(pick(await r.c.next('agent.state_changed'), 'agent', 'state'), { agent: 'a1', state: 'done' })

    // The turn's end: idle at last.
    add({ type: 'assistant', message: { id: 'msg_3', content: [{ type: 'text', text: 'Pushed.' }] } }, { type: 'system', subtype: 'turn_duration', durationMs: 1 })
    await r.c.next((m) => m.type === 'message.completed' && m.text === 'Pushed.')
    assert.deepEqual(pick(await r.c.next('agent.state_changed'), 'agent', 'state'), { agent: 'main', state: 'idle' })

    // The user types in the terminal: their message, and working again; Esc ends it.
    add({ type: 'user', uuid: 'u2', message: { content: 'and the tests' } })
    assert.deepEqual(pick(await r.c.next('message.completed'), 'message', 'text'), { message: 'u2', text: 'and the tests' })
    assert.equal((await r.c.next('agent.state_changed')).state, 'working')
    add({ type: 'user', message: { content: [{ type: 'text', text: '[Request interrupted by user]' }] } })
    assert.equal((await r.c.next('agent.state_changed')).state, 'idle')

    // Everything said is in the history; a stop from the world is refused (Esc in the terminal).
    const history = (await r.c.command({ type: 'session.get_history', session: s.session })).result as { messages: any[] }
    assert.deepEqual(history.messages.map((m) => m.text), ['fix the login', 'Looking.', 'Pushed.', 'and the tests'])
    const stop = await r.c.command({ type: 'interrupt.request', session: s.session })
    assert.equal(stop.type, 'error')
    assert.equal(stop.code, 'not_supported')
    assert.deepEqual(r.c.invalid, [])
    b.sock.destroy()
  } finally { await r.close(); await taken.close() }
})

test('restore, limited: a relayed prompt is only ever tied to the call it shows; else, after the wait, shown from its own preview', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const f = runFolder(root, { record: { hook_port: taken.port } })
  const file = transcript(projects, f.record.native_id, f.record.project.path,
    { type: 'user', uuid: 'u1', message: { content: 'build it' } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: projects,
    runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'busy' }]),
  })
  try {
    // Two Bash calls open (one auto-allowed, one long-running); the prompting one not read yet.
    fs.appendFileSync(file, jsonl({ type: 'assistant', message: { id: 'msg_1', content: [
      { type: 'tool_use', id: 'toolu_ls', name: 'Bash', input: { command: 'ls' } },
      { type: 'tool_use', id: 'toolu_build', name: 'Bash', input: { command: 'npm run build' } },
    ] } }))
    await r.c.next((m) => m.type === 'tool.started' && m.tool_call === 'toolu_build')
    const b = await bridgeBack(f.runDir)
    b.sock.write(JSON.stringify({ type: 'permission_request', request_id: 'abcde', tool_name: 'Bash', description: 'd', input_preview: '{"command":"rm -rf build"}' }) + '\n')
    assert.equal((await r.c.quiet(500)).filter((m) => m.type === 'permission.requested').length, 0, 'waits for its own call')
    const asked = (await r.c.next('permission.requested', 2000) as any).permission
    assert.equal(asked.summary, 'Run: rm -rf build', 'what a Yes approves, never another call\'s')
    assert.deepEqual(asked.input, { command: 'rm -rf build' })
    assert.deepEqual(r.c.invalid, [])
    b.sock.destroy()
  } finally { await r.close(); await taken.close() }
})

test('restore, limited: hooks posted to it with the session\'s token are dropped (only the program on its old port has them)', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const f = runFolder(root, { record: { hook_port: taken.port }, relays: true })
  const file = transcript(projects, f.record.native_id, f.record.project.path, { type: 'user', uuid: 'u1', message: { content: 'hi' } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: projects,
    runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'busy' }]),
  })
  try {
    const port = Number(new URL(readRelayFile(path.join(f.runDir, 'relay.json'))!.url).port)
    const base = { session_id: f.record.native_id, transcript_path: file, cwd: f.record.project.path }
    for (const body of [
      { ...base, hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_use_id: 'toolu_forged', tool_input: { command: 'ls' } },
      { ...base, hook_event_name: 'UserPromptSubmit', prompt: 'forged' },
      { ...base, hook_event_name: 'Stop' },
    ]) assert.equal((await post(port, f.record.hook_token, body)).status, 200)
    // A forged prompt is neither shown nor answered: the body says nothing.
    const asked = await post(port, f.record.hook_token, { ...base, hook_event_name: 'PermissionRequest', tool_name: 'Bash', tool_input: { command: 'rm -rf /' } })
    assert.equal(asked.status, 200)
    assert.equal(asked.body, '')
    const seen = await r.c.quiet(600)
    assert.deepEqual(seen.filter((m) => m.type !== 'usage.updated'), [], 'nothing from them reaches the world')
  } finally { await r.close(); await taken.close() }
})

test('restore: back on the kept port after a limited start, the relays point here again', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const f = runFolder(root, { record: { hook_port: taken.port }, relays: true })
  const listing = agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }])
  const first = await restoreAndSync({ sessionsDir: root, runningSessions: listing })
  const elsewhere = readRelayFile(path.join(f.runDir, 'relay.json'))!.url
  await first.close()
  await taken.close()
  assert.notEqual(Number(new URL(elsewhere).port), taken.port)

  const second = await restoreAndSync({ sessionsDir: root, runningSessions: listing })
  try {
    assert.deepEqual(second.snapshots[0]!.notices, [], 'not limited')
    assert.equal(readRelayFile(path.join(f.runDir, 'relay.json'))!.url, `http://127.0.0.1:${taken.port}/hook`)
    assert.equal(readRelayFile(path.join(f.runDir, 'status.json'))!.url, `http://127.0.0.1:${taken.port}/status`)
  } finally { await second.close() }
})

test('restore: a session that fails to be taken back leaves nothing behind; its token is free for the next try', async () => {
  const root = tempSessionsDir()
  const f = runFolder(root)
  const listing = agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }])
  const log = new RecordingLog()
  const p = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, sessionsDir: root, runningSessions: listing })
  const s = await testServer([p])
  try {
    // The registry's half: a failing make leaves no session.
    assert.throws(() => s.registry.adopt(p, () => { throw new Error('no') }), /no/)
    await p.restore(() => { throw new Error('no') })
    assert.ok(log.lines.some((l) => l.includes('couldn\'t take back')))
    await p.restore((make) => s.registry.adopt(p, make))
    const c = await connect(s.port, s.token)
    const { snapshots } = await c.sync()
    assert.equal(snapshots.length, 1, 'taken on the next try: its hook token was let go')
    assert.equal((snapshots[0]!.session as any).project.path, f.record.project.path)
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('restore: a file it can\'t write while taking a session back leaves no session and no bridge file; a later restore takes it', async () => {
  const root = tempSessionsDir()
  const f = runFolder(root, { relays: true })
  const relay = path.join(f.runDir, 'relay.json')
  fs.rmSync(relay)
  fs.mkdirSync(relay)
  const listing = agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }])
  const log = new RecordingLog()
  const p = new ClaudeProvider({ log, findClaude: FOUND, selfCommand: self, sessionsDir: root, runningSessions: listing })
  const s = await testServer([p])
  try {
    await p.restore((make) => s.registry.adopt(p, make))
    assert.ok(log.lines.some((l) => l.includes('couldn\'t take back')))
    assert.equal(fs.existsSync(path.join(f.runDir, 'bridge.json')), false, 'no token offered for a session not taken')
    const c = await connect(s.port, s.token)
    assert.deepEqual((await c.sync()).snapshots, [])
    await c.close()

    fs.rmdirSync(relay)
    writeRelayFile(relay, { url: `http://127.0.0.1:${f.record.hook_port}/hook`, token: f.record.hook_token })
    await p.restore((make) => s.registry.adopt(p, make))
    const again = await connect(s.port, s.token)
    const { snapshots } = await again.sync()
    assert.deepEqual(snapshots.map((m) => (m.session as any).native_id), [f.record.native_id], 'its hook token and bridge slot were let go')
    assert.ok(readBridgeFile(path.join(f.runDir, 'bridge.json')))
    await again.close()
  } finally { await s.close(); await p.shutdown() }
})

test('restore, limited: a SessionStart switching conversation is ignored while the project\'s transcript folder is unknown', { timeout: 15_000 }, async () => {
  const root = tempSessionsDir()
  const taken = await occupy()
  writeHookPort(root, taken.port)
  const f = runFolder(root, { record: { hook_port: taken.port }, relays: true })
  // No transcript of it anywhere: its folder can't be known.
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: fs.mkdtempSync(path.join(os.tmpdir(), 'projects-')),
    runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'idle' }]),
  })
  try {
    const port = Number(new URL(readRelayFile(path.join(f.runDir, 'relay.json'))!.url).port)
    const elsewhere = fs.mkdtempSync(path.join(os.tmpdir(), 'forged-'))
    const forged = { hook_event_name: 'SessionStart', source: 'resume', session_id: ID(7), transcript_path: path.join(elsewhere, `${ID(7)}.jsonl`), cwd: f.record.project.path }
    assert.equal((await post(port, f.record.hook_token, forged)).status, 200)
    const seen = await r.c.quiet(600)
    assert.deepEqual(seen.filter((m) => m.type === 'session.updated' || m.type === 'session.notice'), [], 'not followed')
    assert.ok(r.log.lines.some((l) => l.includes('ignored a switch of conversation (limited')))
    assert.equal(readRunRecord(f.runDir)!.native_id, f.record.native_id)
  } finally { await r.close(); await taken.close() }
})

test('restore, kept port: the transcript only fills the gaps, as for any session', async () => {
  const root = tempSessionsDir()
  const projects = fs.mkdtempSync(path.join(os.tmpdir(), 'projects-'))
  const kept = await freePort()
  writeHookPort(root, kept)
  const f = runFolder(root, { record: { hook_port: kept } })
  const file = transcript(projects, f.record.native_id, f.record.project.path, { type: 'user', message: { content: 'hi' } })
  const r = await restoreAndSync({
    sessionsDir: root, projectsDir: projects,
    runningSessions: agentsListing([{ sessionId: f.record.native_id, pid: f.program, status: 'busy' }]),
  })
  try {
    assert.ok('interrupt' in r.snapshots[0]!.capabilities)
    fs.appendFileSync(file, jsonl({ type: 'assistant', message: { id: 'msg_1', content: [{ type: 'text', text: 'from the transcript' }] } }, { type: 'system', subtype: 'turn_duration' }))
    const unread = await r.c.quiet(700)
    assert.deepEqual(unread.filter((m) => m.type.startsWith('message.') || m.type === 'agent.state_changed'), [], 'its hooks say these')
  } finally { await r.close() }
})

const pick = (o: Record<string, any>, ...keys: string[]) => Object.fromEntries(keys.map((k) => [k, o[k]]))

// ---- the sidecar's start ----

test('serve: the start waits for restore, at most its bound; a failing restore never fails the start', async () => {
  assert.ok(RESTORE_WAIT_MS < 20_000, 'well inside Godot\'s handshake timeout')
  const log = new RecordingLog()
  const s = await testServer()
  try {
    const never = { id: 'never', restore: () => new Promise<void>(() => {}) } as unknown as Provider
    const failing = { id: 'failing', restore: async () => { throw new Error('boom') } } as unknown as Provider
    const none = { id: 'none' } as unknown as Provider
    const t0 = Date.now()
    await restoreSessions(s.registry, [never, failing, none], log, 200)
    const took = Date.now() - t0
    assert.ok(took >= 190 && took < 2000, `took ${took} ms`)
    assert.ok(log.lines.some((l) => l.startsWith('warn') && l.includes('starting anyway')))
    assert.ok(log.lines.some((l) => l.startsWith('error') && l.includes('failing') && l.includes('boom')))

    // A quick one doesn't wait for the bound.
    const quick = { id: 'quick', restore: async () => {} } as unknown as Provider
    const t1 = Date.now()
    await restoreSessions(s.registry, [quick], log, 5000)
    assert.ok(Date.now() - t1 < 1000)
  } finally { await s.close() }
})
