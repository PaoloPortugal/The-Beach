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
import { prepare, serveOptions } from '../src/serve.ts'
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

test('a path set by hand is the only one tried: once it fails, no other claude is found instead', async () => {
  const good = file(process.platform === 'win32' ? 'claude.exe' : 'claude')
  const v = versions({ [good]: '2.1.300' })
  const env = { PATH: path.dirname(good) }
  // Without one, the one on PATH is found.
  assert.equal((await findClaude({ env, cleanEnv: {}, home: os.tmpdir(), readVersion: v.read, loginShellPath: async () => [] })).path, good)
  const gone = path.join(os.tmpdir(), 'no-such-folder-program-path', 'claude.exe')
  await assert.rejects(
    findClaude({ env, cleanEnv: {}, home: os.tmpdir(), override: gone, readVersion: v.read, loginShellPath: async () => { throw new Error('the login shell is not asked') } }),
    (e: Error) => e instanceof ClaudeNotFound && /^The Claude Code set in Settings doesn't work: There's no program at that path\. Choose it again, or reset it\.$/.test(e.message),
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
    assert.equal(entry.program, undefined, 'not looked for yet: nothing asked claude at start')

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
    const lost = (await c2.next('provider.program')).program as Program
    assert.deepEqual(lost, { path: null, set_by_hand: true, message: failed.message })

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

test('serve --program-path: parsed; applied before the restore; one that fails is kept and reported, the start goes on', async () => {
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
    const program = registry.providerProgramOf('claude')!
    assert.equal(program.path, null)
    assert.equal(program.set_by_hand, true)
    assert.match((program as { message: string }).message, /set in Settings doesn't work: There's no program at that path/)
    assert.ok(log.lines.some((l) => /warn --program-path: no provider "plain" with program_path; ignored/.test(l)))
    assert.ok(log.lines.some((l) => /warn --program-path: no provider "nobody" with program_path; ignored/.test(l)))
  } finally { await p.shutdown() }
})
