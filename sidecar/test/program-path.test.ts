// A program set by hand (NOTES.md -> Protocol -> program_path; S02): the
// checks on a `claude` the player points at, the only one tried once set
// (no other found instead), client.set_program_path and provider.program
// (after the reply, kept for hello), serve --program-path at start.
// `claude --version` is a fake (readVersion), so no real claude runs.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { checkClaudePath, ClaudeNotFound, findClaude, MIN_VERSION } from '../src/providers/claude/find.ts'
import { ClaudeProvider, type ClaudeOptions } from '../src/providers/claude/index.ts'
import { prepare, serveDefaults, serveOptions } from '../src/serve.ts'
import { TEST_SESSIONS_DIR } from '../src/launch/app-data.ts'
import { findOnPath } from '../src/launch/terminal.ts'
import { Registry } from '../src/registry.ts'
import type { Program } from '../src/protocol.ts'
import { FakeProvider } from './fake-provider.ts'
import { connect, RecordingLog, tempSessionsDir, testServer, type Msg } from './helpers.ts'

const self: ClaudeOptions['selfCommand'] = (mode, ...args) => ['/sidecar', mode, ...args]

/** A fresh folder with an empty file named `name` in it; returns the file's full path. */
function file(name: string): string {
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'program-path-')), name)
  fs.writeFileSync(f, '')
  return f
}

/** A fake `--version`: each path's answer (null: no answer), counting the calls. */
function versions(answers: Record<string, string | null>) {
  const v = {
    calls: [] as string[],
    read: async (f: string) => { v.calls.push(f); return answers[f] ?? null },
  }
  return v
}

/** Waits until `ready()` holds (a look in the background), at most a second. */
async function until(ready: () => unknown): Promise<void> {
  for (let i = 0; i < 100 && !ready(); i++) await new Promise((r) => setTimeout(r, 10))
  assert.ok(ready(), 'in time')
}

/** A Claude provider that runs nothing real: no terminal, no `claude agents`, outside sessions off. */
function provider(o: ClaudeOptions = {}) {
  const p = new ClaudeProvider({
    log: new RecordingLog(), selfCommand: self, sessionsDir: tempSessionsDir(),
    openTerminal: async () => { throw new Error('no terminal in this test') },
    runningSessions: async () => ({ none: 'not asked in this test' }),
    ...o,
  })
  p.setOutsideSessions(false)
  return p
}

test('checks on a path set by hand: full path, a file, .exe on Windows, answering --version, new enough', async () => {
  const exe = file('claude.exe')
  const cmd = file('claude.cmd')
  const old = file('old-claude.exe')
  const v = versions({ [exe]: '2.1.300', [cmd]: '2.1.300', [old]: '2.1.1' })
  const check = (f: string, platform: NodeJS.Platform = process.platform) => checkClaudePath(f, { cleanEnv: {}, platform, readVersion: v.read })

  assert.deepEqual(await check(exe), { path: exe, version: '2.1.300' })
  await assert.rejects(check('claude.exe'), (e: Error) => e instanceof ClaudeNotFound && /isn't a full path/.test(e.message))
  const before = v.calls.length
  await assert.rejects(check(exe + '\u0000x'), /isn't a full path/, 'a control character is refused before anything touches the file')
  for (const network of ['\\\\host\\share\\claude.exe', '//host/share/claude.exe', '\\claude.exe']) {
    await assert.rejects(check(network, 'win32'), /on a drive of this computer/, `${network}: never reached`)
  }
  assert.equal(v.calls.length, before, 'nothing run for those')
  await assert.rejects(check(path.join(path.dirname(exe), 'missing.exe')), /no program at that path/)
  await assert.rejects(check(path.dirname(exe)), /no program at that path/, 'a folder is not a program')
  await assert.rejects(check(old), new RegExp(`2\\.1\\.1 is too old; version ${MIN_VERSION.replace(/\./g, '\\.')} or newer`))
  await assert.rejects(check(file('silent.exe')), /didn't answer as Claude Code/)
  if (process.platform === 'win32') {
    const calls = v.calls.length
    await assert.rejects(check(cmd, 'win32'), /Pick claude\.exe itself/)
    assert.equal(v.calls.length, calls, 'a .cmd is never run')
  } else {
    assert.deepEqual(await check(cmd), { path: cmd, version: '2.1.300' }, 'any name will do outside Windows')
  }
})

test('C16 step 6: each check that fails has its reason, for Godot to word', async () => {
  const exe = file('reasons-claude.exe')
  const old = file('reasons-old.exe')
  const v = versions({ [exe]: '2.1.300', [old]: '2.1.1' })
  const reason = async (f: string, platform: NodeJS.Platform = process.platform) => {
    try { await checkClaudePath(f, { cleanEnv: {}, platform, readVersion: v.read }) } catch (e) { return (e as ClaudeNotFound).reasoned }
    return null
  }
  assert.deepEqual(await reason('claude.exe'), { reason: 'not_full_path' })
  assert.deepEqual(await reason('\\\\host\\share\\claude.exe', 'win32'), { reason: 'network_path' })
  assert.deepEqual(await reason(path.join(path.dirname(exe), 'missing.exe')), { reason: 'no_file' })
  assert.deepEqual(await reason(old), { reason: 'too_old', details: { version: '2.1.1', minimum: MIN_VERSION } })
  assert.deepEqual(await reason(file('reasons-silent.exe')), { reason: 'not_the_program' })
  if (process.platform === 'win32') assert.deepEqual(await reason(file('reasons-claude.cmd'), 'win32'), { reason: 'wrapper' })
  // Nothing found at all, on each platform.
  for (const platform of ['win32', 'linux'] as const) {
    await assert.rejects(findClaude({ env: { PATH: '' }, cleanEnv: {}, home: path.join(os.tmpdir(), 'no-home-here'), platform, readVersion: v.read, loginShellPath: async () => [] }),
      (e: ClaudeNotFound) => e.reasoned.reason === 'not_installed' && e.reasoned.details?.site === 'code.claude.com', platform)
  }
})

test('a path set by hand is the only one tried: once it fails, no other claude is found instead', async () => {
  const good = file(process.platform === 'win32' ? 'claude.exe' : 'claude')
  const env = { PATH: path.dirname(good) }
  // Outside Windows the PATH lookup wants the exec bit: a plain file isn't a program.
  if (process.platform !== 'win32') assert.equal(findOnPath('claude', env), null, 'not executable: skipped')
  fs.chmodSync(good, 0o755)
  const v = versions({ [good]: '2.1.300' })
  // Without one, the one on PATH is found.
  assert.equal((await findClaude({ env, cleanEnv: {}, home: os.tmpdir(), readVersion: v.read, loginShellPath: async () => [] })).path, good)
  const gone = path.join(os.tmpdir(), 'no-such-folder-program-path', 'claude.exe')
  await assert.rejects(
    findClaude({ env, cleanEnv: {}, home: os.tmpdir(), override: gone, readVersion: v.read, loginShellPath: async () => { throw new Error('the login shell is not asked') } }),
    (e: Error) => e instanceof ClaudeNotFound && /^The Claude Code set in Settings doesn't work: There's no program at that path\. Choose it again, or reset it\.$/.test(e.message)
      && e.reasoned.reason === 'set_path_broken' && e.reasoned.details?.why === 'no_file',
  )
})

test('client.set_program_path: checked, answered with the program, then provider.program; kept for hello', async () => {
  const exe = file('claude.exe')
  const old = file('old.exe')
  const v = versions({ [exe]: '2.1.300', [old]: '2.0.0' })
  const p = provider({ readVersion: v.read, findClaude: async () => ({ path: '/found/claude', version: '2.1.299' }) })
  const s = await testServer([p, new FakeProvider({ id: 'plain' })])
  const c = await connect(s.port, s.token)
  try {
    const { hello } = await c.sync()
    const entry = (hello.providers as Msg[]).find((x) => x.provider === 'claude')!
    assert.deepEqual((entry.capabilities as Record<string, unknown>).program_path, { program: 'claude' })
    assert.equal(entry.program, undefined, 'not looked for yet: testServer runs no prepare(), so no look at start')

    const ok = await c.command({ type: 'client.set_program_path', provider: 'claude', path: exe })
    assert.equal(ok.type, 'ok')
    const found: Program = { path: exe, version: '2.1.300', set_by_hand: true }
    assert.deepEqual(ok.result, { program: found })
    assert.deepEqual((await c.next('provider.program')).program, found, 'after the reply')
    assert.deepEqual(v.calls, [exe], '--version run once')

    // Refused: the setting stays, nothing is sent.
    for (const [bad, why] of [['claude.exe', /full path/], [old, /too old/], [path.join(path.dirname(exe), 'nope.exe'), /no program/]] as const) {
      const err = await c.command({ type: 'client.set_program_path', provider: 'claude', path: bad })
      assert.equal(err.type, 'error')
      assert.equal(err.code, 'invalid_program')
      assert.match(err.message as string, why)
    }
    assert.equal((await c.command({ type: 'client.set_program_path', provider: 'claude', path: '' })).code, 'invalid_message')
    assert.equal((await c.command({ type: 'client.set_program_path', provider: 'nobody', path: exe })).code, 'unknown_provider')
    assert.equal((await c.command({ type: 'client.set_program_path', provider: 'plain', path: exe })).code, 'not_supported')
    assert.deepEqual((await c.quiet()).filter((m) => m.type === 'provider.program'), [])

    // A new connection gets it in hello.
    const c2 = await connect(s.port, s.token)
    const again = (await c2.sync()).hello.providers as Msg[]
    assert.deepEqual(again.find((x) => x.provider === 'claude')!.program, found)
    assert.equal(again.find((x) => x.provider === 'plain')!.program, undefined)

    // It stops working: a start fails with why, and no other claude is used.
    fs.rmSync(exe)
    const proj = fs.mkdtempSync(path.join(os.tmpdir(), 'program-path-proj-'))
    const failed = await c2.command({ type: 'session.create', provider: 'claude', project: { path: proj } })
    assert.equal(failed.code, 'provider_error')
    assert.match(failed.message as string, /set in Settings doesn't work: There's no program at that path/)
    // C16 step 6: the reason around the check's own, for Godot to word.
    assert.equal(failed.reason, 'set_path_broken')
    assert.deepEqual(failed.details, { why: 'no_file' })
    const lost = (await c2.next('provider.program')).program as Program
    assert.deepEqual(lost, { path: null, set_by_hand: true, message: failed.message, reason: 'set_path_broken', details: { why: 'no_file' } })

    // Reset: found as usual again, at once.
    const reset = await c2.command({ type: 'client.set_program_path', provider: 'claude', path: null })
    assert.deepEqual(reset.result, { program: { path: '/found/claude', version: '2.1.299', set_by_hand: false } })
    assert.deepEqual((await c2.next('provider.program')).program, { path: '/found/claude', version: '2.1.299', set_by_hand: false })
    assert.deepEqual([...c.invalid, ...c2.invalid], [])
    await c2.close()
  } finally {
    await c.close()
    await s.close()
    await p.shutdown()
  }
})

test('a session started after a path is set runs that claude, not the one found', async () => {
  const exe = file('claude.exe')
  const v = versions({ [exe]: '2.1.300' })
  let launch: { command?: string } = {}
  const p = provider({
    readVersion: v.read,
    findClaude: async () => ({ path: process.execPath, version: '2.1.299' }),
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
    projectsDir: fs.mkdtempSync(path.join(os.tmpdir(), 'program-path-projects-')),
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  try {
    await c.sync()
    assert.equal((await c.command({ type: 'client.set_program_path', provider: 'claude', path: exe })).type, 'ok')
    const proj = fs.mkdtempSync(path.join(os.tmpdir(), 'program-path-proj-'))
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: proj } })
    assert.equal(r.type, 'ok')
    assert.equal(launch.command, exe, 'the terminal starts the claude set by hand')
  } finally {
    await c.close()
    await s.close()
    await p.shutdown()
  }
})

test('the same answer again is not sent again; a lookup begun before a new setting doesn\'t report the old one', async () => {
  const exe = file('claude.exe')
  let release: () => void = () => {}
  const v = versions({ [exe]: '2.1.300' })
  let slow = false
  const p = provider({
    readVersion: v.read,
    findClaude: async () => {
      if (slow) await new Promise<void>((r) => { release = r })
      return { path: '/found/claude', version: '2.1.299' }
    },
  })
  const log = new RecordingLog()
  const registry = new Registry([p], log)
  const sent: Msg[] = []
  registry.setSink((m) => sent.push(m as Msg))
  try {
    await p.setProgramPath(null)
    await p.setProgramPath(null)
    assert.equal(sent.length, 1, 'once')
    slow = true
    const starting = (p as unknown as { find(): Promise<unknown> }).find()
    await new Promise((r) => setTimeout(r, 20))
    await p.setProgramPath(exe)
    release()
    await starting
    assert.deepEqual(sent.map((m) => m.program), [
      { path: '/found/claude', version: '2.1.299', set_by_hand: false },
      { path: exe, version: '2.1.300', set_by_hand: true },
    ])
    assert.deepEqual(registry.providerProgramOf('claude'), { path: exe, version: '2.1.300', set_by_hand: true })
  } finally { await p.shutdown() }
})

test('serve --program-path: parsed; set before the restore, checked in the background; one that fails is kept and reported, the start goes on', async () => {
  assert.deepEqual(serveOptions(['--program-path', 'claude=C:\\Tools\\claude.exe']), {
    outsideSessions: true, programPaths: { claude: 'C:\\Tools\\claude.exe' },
  })
  assert.deepEqual(serveOptions(['--no-outside-sessions', '--program-path', 'claude=/a b/c=d']), {
    outsideSessions: false, programPaths: { claude: '/a b/c=d' },
  })
  assert.throws(() => serveOptions(['--program-path']), /needs <provider>=<path>/)
  assert.throws(() => serveOptions(['--program-path', 'claude=']), /needs <provider>=<path>/)
  assert.throws(() => serveOptions(['--program-path', '/usr/bin/claude']), /needs <provider>=<path>/)
  assert.throws(() => serveOptions(['--program-path', 'claude=/a', '--program-path', 'claude=/b']), /given twice/)
  assert.throws(() => serveOptions(['--program-path=claude=/a']), /unexpected arguments/)

  const gone = path.join(os.tmpdir(), 'no-such-folder-program-path', 'claude.exe')
  const v = versions({})
  const p = provider({ readVersion: v.read, findClaude: async () => { throw new Error('nothing else is looked for') } })
  const log = new RecordingLog()
  const registry = new Registry([p, new FakeProvider({ id: 'plain' })], log)
  try {
    await prepare(registry, [p], log, serveOptions(['--no-outside-sessions', '--program-path', `claude=${gone}`, '--program-path', 'plain=/x', '--program-path', 'nobody=/y']))
    await until(() => registry.providerProgramOf('claude'))
    const program = registry.providerProgramOf('claude')!
    assert.equal(program.path, null)
    assert.equal(program.set_by_hand, true)
    assert.match((program as { message: string }).message, /set in Settings doesn't work: There's no program at that path/)
    assert.ok(log.lines.some((l) => /warn --program-path: no provider "plain" with program_path; ignored/.test(l)))
    assert.ok(log.lines.some((l) => /warn --program-path: no provider "nobody" with program_path; ignored/.test(l)))
  } finally { await p.shutdown() }
})

test('at start every program_path provider looks, in the background; one set by hand isn\'t looked for twice', async () => {
  let calls = 0
  let release: () => void = () => {}
  const p = provider({
    findClaude: async () => {
      calls++
      await new Promise<void>((r) => { release = r })
      return { path: '/found/claude', version: '2.1.299' }
    },
  })
  const log = new RecordingLog()
  const registry = new Registry([p, new FakeProvider({ id: 'plain' })], log)
  const sent: Msg[] = []
  registry.setSink((m) => sent.push(m as Msg))
  try {
    await prepare(registry, [p], log, { outsideSessions: false })
    assert.equal(calls, 1, 'looking, and prepare() didn\'t wait for it')
    assert.equal(registry.providerProgramOf('claude'), undefined, 'not found yet: hello has no program')
    release()
    await new Promise((r) => setTimeout(r, 20))
    assert.deepEqual(registry.providerProgramOf('claude'), { path: '/found/claude', version: '2.1.299', set_by_hand: false })
    assert.deepEqual(sent.map((m) => [m.type, m.provider]), [['provider.program', 'claude']], 'provider.program once found')
    assert.equal(registry.providerProgramOf('plain'), undefined)
  } finally { await p.shutdown() }

  const exe = file('claude.exe')
  const v = versions({ [exe]: '2.1.300' })
  const byHand = provider({ readVersion: v.read, findClaude: async () => { throw new Error('nothing else is looked for') } })
  const r2 = new Registry([byHand], log)
  try {
    await prepare(r2, [byHand], log, { outsideSessions: false, programPaths: { claude: exe } })
    await until(() => r2.providerProgramOf('claude'))
    assert.deepEqual(r2.providerProgramOf('claude'), { path: exe, version: '2.1.300', set_by_hand: true })
    assert.deepEqual(v.calls, [exe], 'checked once: setting it was the look')
  } finally { await byHand.shutdown() }

  // Under a Godot suite (serve() with TEST_SESSIONS_DIR): no look at all.
  let looked = false
  const quiet = provider({ findClaude: async () => { looked = true; return { path: '/found/claude', version: '2.1.299' } } })
  const r3 = new Registry([quiet], log)
  try {
    await prepare(r3, [quiet], log, { outsideSessions: false, lookAtStart: false })
    await new Promise((r) => setTimeout(r, 20))
    assert.equal(looked, false)
    assert.equal(r3.providerProgramOf('claude'), undefined)
    assert.ok(log.lines.some((l) => /a test run: programs not looked for at start/.test(l)))
  } finally { await quiet.shutdown() }

  // serve() turns the look off only under a Godot suite.
  assert.deepEqual(serveDefaults({}), { lookAtStart: true })
  assert.deepEqual(serveDefaults({ [TEST_SESSIONS_DIR]: '/tmp/sessions' }), { lookAtStart: false })
})

test('a program set by hand that hangs doesn\'t hold up the start; it\'s the one tried meanwhile', async () => {
  const exe = file('claude.exe')
  let asked = 0
  const p = provider({
    readVersion: () => { asked++; return new Promise<string | null>(() => {}) },
    findClaude: async () => { throw new Error('nothing else is looked for') },
  })
  const log = new RecordingLog()
  const registry = new Registry([p], log)
  try {
    const began = Date.now()
    await prepare(registry, [p], log, { outsideSessions: false, programPaths: { claude: exe } })
    assert.ok(Date.now() - began < 1000, 'ready without waiting for --version')
    assert.equal(asked, 1, 'checked, in the background')
    assert.equal(registry.providerProgramOf('claude'), undefined, 'no answer yet: the row says it\'s looking')
    assert.equal((p as unknown as { handPath?: string }).handPath, exe, 'already the only one tried')
  } finally { await p.shutdown() }
})

test('Look again outranks a look begun before it: the older one\'s answer isn\'t reported', async () => {
  let release: () => void = () => {}
  let calls = 0
  const p = provider({
    findClaude: async () => {
      if (++calls === 1) {
        await new Promise<void>((r) => { release = r })
        throw new ClaudeNotFound('Claude Code wasn\'t found.', { reason: 'not_installed', details: { site: 'code.claude.com' } })
      }
      return { path: '/found/claude', version: '2.1.299' }
    },
  })
  const reported: Program[] = []
  p.watchProgram((program) => reported.push(program))
  try {
    const older = (p as unknown as { find(): Promise<unknown> }).find().catch(() => {})
    await new Promise((r) => setTimeout(r, 20))
    assert.deepEqual(await p.findProgram(), { path: '/found/claude', version: '2.1.299', set_by_hand: false })
    release()
    await older
    assert.deepEqual(reported, [{ path: '/found/claude', version: '2.1.299', set_by_hand: false }], 'the older "not found" never reaches the game')
  } finally { await p.shutdown() }
})

test('the login shell is asked again only on Look again, not on a launch or listing', async () => {
  let forgot = 0
  const p = provider({
    forgetLoginShell: () => { forgot++ },
    findClaude: async () => ({ path: '/found/claude', version: '2.1.299' }),
  })
  const find = () => (p as unknown as { find(): Promise<unknown> }).find()
  try {
    await find()
    await find()
    assert.equal(forgot, 0, 'a launch or listing keeps the answer of this run')
    await p.findProgram()
    assert.equal(forgot, 1, 'Look again asks it again')
  } finally { await p.shutdown() }
})

test('looks that come while one runs share it (one --version); a fresh look doesn\'t', async () => {
  let calls = 0
  const p = provider({ findClaude: async () => { calls++; await new Promise((r) => setTimeout(r, 20)); return { path: '/found/claude', version: '2.1.299' } } })
  const find = (fresh?: boolean) => (p as unknown as { find(fresh?: boolean): Promise<unknown> }).find(fresh)
  try {
    const [a, b] = await Promise.all([find(), find()])
    assert.equal(calls, 1, 'shared')
    assert.deepEqual(a, b)
    await find()
    assert.equal(calls, 2, 'one that ended isn\'t reused: a later launch looks afresh')
    await Promise.all([find(), find(true)])
    assert.equal(calls, 4, 'fresh: its own look')
  } finally { await p.shutdown() }
})

test('client.find_program: looks again now, answered with the program; provider.program only when it changed; the one set by hand checked again', async () => {
  const exe = file('claude.exe')
  const v = versions({ [exe]: '2.1.300' })
  let installed = false
  const p = provider({
    readVersion: v.read,
    findClaude: async () => {
      if (!installed) throw new ClaudeNotFound('Claude Code wasn\'t found.', { reason: 'not_installed', details: { site: 'code.claude.com' } })
      return { path: '/found/claude', version: '2.1.299' }
    },
  })
  const s = await testServer([p, new FakeProvider({ id: 'plain' })])
  const c = await connect(s.port, s.token)
  try {
    await c.sync()
    const none = await c.command({ type: 'client.find_program', provider: 'claude' })
    assert.equal(none.type, 'ok', 'not found is an answer')
    assert.deepEqual(none.result, { program: { path: null, set_by_hand: false, message: 'Claude Code wasn\'t found.', reason: 'not_installed', details: { site: 'code.claude.com' } } })
    assert.deepEqual((await c.next('provider.program')).program, { path: null, set_by_hand: false, message: 'Claude Code wasn\'t found.', reason: 'not_installed', details: { site: 'code.claude.com' } })

    installed = true
    const found = await c.command({ type: 'client.find_program', provider: 'claude' })
    assert.deepEqual(found.result, { program: { path: '/found/claude', version: '2.1.299', set_by_hand: false } })
    assert.deepEqual((await c.next('provider.program')).program, { path: '/found/claude', version: '2.1.299', set_by_hand: false })
    const same = await c.command({ type: 'client.find_program', provider: 'claude' })
    assert.deepEqual(same.result, found.result, 'the same answer in the reply')
    assert.deepEqual((await c.quiet()).filter((m) => m.type === 'provider.program'), [], 'but no provider.program again')

    // Set by hand: only that one is checked again, gone or back.
    assert.equal((await c.command({ type: 'client.set_program_path', provider: 'claude', path: exe })).type, 'ok')
    await c.next('provider.program')
    const moved = exe + '.moved'
    fs.renameSync(exe, moved)
    const gone = await c.command({ type: 'client.find_program', provider: 'claude' })
    assert.equal(gone.type, 'ok')
    assert.match((gone.result as { program: { message: string } }).program.message, /set in Settings doesn't work: There's no program at that path/)
    assert.equal((gone.result as { program: Program }).program.path, null, 'not the one found as usual')
    fs.renameSync(moved, exe)
    const back = await c.command({ type: 'client.find_program', provider: 'claude' })
    assert.deepEqual(back.result, { program: { path: exe, version: '2.1.300', set_by_hand: true } })

    assert.equal((await c.command({ type: 'client.find_program', provider: 'plain' })).code, 'not_supported')
    assert.equal((await c.command({ type: 'client.find_program', provider: 'nobody' })).code, 'unknown_provider')
    assert.equal((await c.command({ type: 'client.find_program' })).code, 'invalid_message')
    assert.deepEqual(c.invalid, [])
  } finally {
    await c.close()
    await s.close()
    await p.shutdown()
  }
})
