// The generic launch pieces: clean environments, terminal commands per OS,
// and the launcher mode (NOTES.md -> Security rules, Architecture -> Platforms).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { cleanEnv } from '../src/launch/env.ts'
import { openTerminal, terminalsFor, TerminalError } from '../src/launch/terminal.ts'
import { takeSessionFile, writeSessionFile } from '../src/launch/launcher.ts'

const here = import.meta.dirname
const main = path.join(here, '..', 'src', 'main.ts')

function tmp(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'sidecar-test-'))
}

// ---- env ----

test('cleanEnv removes exactly the named variables', () => {
  const env = { CLAUDECODE: '1', CLAUDE_CONFIG_DIR: '/c', PATH: '/bin', KEEP: 'x', GONE: undefined }
  assert.deepEqual(cleanEnv(env, ['CLAUDECODE'], 'linux'), { CLAUDE_CONFIG_DIR: '/c', PATH: '/bin', KEEP: 'x' })
})

test('cleanEnv ignores case on Windows only', () => {
  const env = { ClaudeCode: '1', Path: 'C:\\x' }
  assert.deepEqual(cleanEnv(env, ['CLAUDECODE'], 'win32'), { Path: 'C:\\x' })
  assert.deepEqual(cleanEnv(env, ['CLAUDECODE'], 'linux'), env)
})

test('cleanEnv drops only store overlay preloads', () => {
  assert.deepEqual(cleanEnv({ LD_PRELOAD: '/a/libmine.so:/steam/gameoverlayrenderer.so' }, [], 'linux'),
    { LD_PRELOAD: '/a/libmine.so' })
  assert.deepEqual(cleanEnv({ LD_PRELOAD: '/steam/gameoverlayrenderer.so' }, [], 'linux'), {})
})

// ---- terminals ----

function fakeOpen(platform: NodeJS.Platform, installed: string[], argv: string[], extra: { preferred?: string; title?: string } = {}) {
  const started: { file: string; args: string[] }[] = []
  const runDir = tmp()
  const run = openTerminal({ argv, title: extra.title ?? 'T', runDir }, {
    platform,
    env: {},
    ...(extra.preferred ? { preferred: extra.preferred } : {}),
    which: (name) => (installed.includes(name) ? `/bin/${name}` : null),
    start: async (file, args) => { started.push({ file, args }) },
  })
  return { run, started, runDir }
}

test('Windows: Windows Terminal gets the launcher argv after --', async () => {
  const argv = ['C:\\Program Files\\Game\\sidecar.exe', 'launch', 'C:\\Temp\\s\\launch.json']
  const { run, started } = fakeOpen('win32', ['wt.exe'], argv)
  assert.equal(await run, 'windows-terminal')
  assert.deepEqual(started, [{ file: '/bin/wt.exe', args: ['-w', 'new', 'new-tab', '--title', 'T', '--', ...argv] }])
})

test('Windows: never hands Windows Terminal a ; or " (it would split them); uses the console', async () => {
  for (const bad of ['C:\\a;b\\sidecar.exe', 'C:\\a"b\\sidecar.exe']) {
    const { run, started } = fakeOpen('win32', ['wt.exe'], [bad, 'launch', 'f'])
    assert.equal(await run, 'console')
    assert.deepEqual(started, [{ file: bad, args: ['launch', 'f'] }])
  }
  const { run } = fakeOpen('win32', ['wt.exe'], ['C:\\x.exe'], { title: 'a;b' })
  assert.equal(await run, 'console')
})

test('Windows: falls back to the console without Windows Terminal', async () => {
  const { run, started } = fakeOpen('win32', [], ['C:\\x.exe', 'launch', 'f'])
  assert.equal(await run, 'console')
  assert.deepEqual(started, [{ file: 'C:\\x.exe', args: ['launch', 'f'] }])
})

test('Linux: first installed terminal, argv passed as separate arguments', async () => {
  const argv = ['/opt/game/sidecar', 'launch', '/tmp/s/launch.json']
  const { run, started } = fakeOpen('linux', ['konsole', 'xterm'], argv)
  assert.equal(await run, 'konsole')
  assert.deepEqual(started[0], { file: '/bin/konsole', args: ['-e', ...argv] })
  const pref = fakeOpen('linux', ['konsole', 'xterm'], argv, { preferred: 'xterm' })
  assert.equal(await pref.run, 'xterm')
  await assert.rejects(fakeOpen('linux', [], argv).run, TerminalError)
})

test('macOS: the script holds only the single-quoted argv', async () => {
  const mac = terminalsFor('darwin').find((t) => t.id === 'terminal-app')!
  const runDir = tmp()
  const argv = ["/Applications/My Game's.app/Contents/MacOS/sidecar", 'launch', '/tmp/x $(rm -rf ~)/launch.json']
  const cmd = mac.command('/usr/bin/open', { argv, title: 'T', runDir })!
  assert.deepEqual(cmd.args.slice(0, 2), ['-a', 'Terminal'])
  const script = fs.readFileSync(cmd.args[2]!, 'utf8')
  assert.equal(script,
    "#!/bin/sh\nexec '/Applications/My Game'\\''s.app/Contents/MacOS/sidecar' 'launch' '/tmp/x $(rm -rf ~)/launch.json'\n")
})

test('a terminal that fails to start is skipped', async () => {
  const started: string[] = []
  const id = await openTerminal({ argv: ['C:\\x.exe'], title: 'T', runDir: tmp() }, {
    platform: 'win32', env: {},
    which: (n) => (n === 'wt.exe' ? 'C:\\wt.exe' : null),
    start: async (file) => {
      started.push(file)
      if (file === 'C:\\wt.exe') throw new Error('ENOENT')
    },
  })
  assert.equal(id, 'console')
  assert.deepEqual(started, ['C:\\wt.exe', 'C:\\x.exe'])
})

// ---- session file ----

test('a session file is read once and deleted', () => {
  const dir = tmp()
  const file = path.join(dir, 'launch.json')
  writeSessionFile(file, { command: process.execPath, args: ['-v'], cwd: dir, unsetEnv: [] })
  const s = takeSessionFile(file)
  assert.equal(s.command, process.execPath)
  assert.equal(fs.existsSync(file), false)
  assert.throws(() => takeSessionFile(file), /already started|missing/)
})

test('bad session files are refused (and still deleted)', () => {
  const dir = tmp()
  const cases: [unknown, RegExp][] = [
    ['not json', /damaged/],
    [{ version: 2, command: process.execPath, args: [], cwd: dir, unsetEnv: [] }, /another version/],
    [{ version: 1, command: 'relative.exe', args: [], cwd: dir, unsetEnv: [] }, /not found/],
    [{ version: 1, command: process.execPath, args: [1], cwd: dir, unsetEnv: [] }, /another version/],
    [{ version: 1, command: process.execPath, args: [], cwd: path.join(dir, 'nope'), unsetEnv: [] }, /folder not found/],
  ]
  for (const [body, why] of cases) {
    const file = path.join(dir, 'launch.json')
    fs.writeFileSync(file, typeof body === 'string' ? body : JSON.stringify(body))
    assert.throws(() => takeSessionFile(file), why)
    assert.equal(fs.existsSync(file), false)
  }
})

test('the launcher starts the program with its args, folder and a clean environment', async () => {
  const dir = tmp()
  const project = fs.mkdtempSync(path.join(os.tmpdir(), 'project with spaces '))
  const out = path.join(dir, 'out.json')
  const recorder = path.join(dir, 'rec.cjs')
  fs.writeFileSync(recorder, `require('fs').writeFileSync(process.argv[2], JSON.stringify({
    args: process.argv.slice(3), cwd: process.cwd(),
    marker: process.env.CLAUDECODE ?? null, config: process.env.CLAUDE_CONFIG_DIR ?? null }))`)
  const file = path.join(dir, 'launch.json')
  const tricky = ['a b', 'c;d', 'e"f', '$(whoami)', '%PATH%', '']
  writeSessionFile(file, {
    command: process.execPath, args: [recorder, out, ...tricky], cwd: project, unsetEnv: ['CLAUDECODE'],
  })
  const code = await new Promise<number | null>((resolve) => {
    const child = spawn(process.execPath, [main, 'launch', file], {
      stdio: 'ignore', env: { ...process.env, CLAUDECODE: '1', CLAUDE_CONFIG_DIR: 'kept' },
    })
    child.once('exit', resolve)
  })
  assert.equal(code, 0)
  const got = JSON.parse(fs.readFileSync(out, 'utf8'))
  assert.deepEqual(got.args, tricky)
  assert.equal(fs.realpathSync(got.cwd), fs.realpathSync(project))
  assert.equal(got.marker, null)
  assert.equal(got.config, 'kept')
  assert.equal(fs.existsSync(file), false)
})

test('the launcher passes on the program\'s exit code', async () => {
  const dir = tmp()
  const file = path.join(dir, 'launch.json')
  writeSessionFile(file, { command: process.execPath, args: ['-e', 'process.exit(7)'], cwd: dir, unsetEnv: [] })
  const code = await new Promise<number | null>((resolve) => {
    spawn(process.execPath, [main, 'launch', file], { stdio: 'ignore' }).once('exit', resolve)
  })
  assert.equal(code, 7)
})
