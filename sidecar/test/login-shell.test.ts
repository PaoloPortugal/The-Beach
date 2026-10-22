// Claude provider: finding claude through the login shell's PATH (NOTES.md ->
// Architecture -> Platforms -> Finding claude). The fake shells are sh
// scripts, so those tests run on macOS and Linux only.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import {
  findClaude, loginShell, parseLoginShellPath, readLoginShellPath, LOGIN_SHELL_SCRIPT, MIN_VERSION,
} from '../src/providers/claude/find.ts'

const posixOnly = { skip: process.platform === 'win32' }
const MARK = /printf '%s' (\S+);/.exec(LOGIN_SHELL_SCRIPT)![1]!

function tempDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'login-shell-'))
}

/** An executable sh script in `dir`. */
function script(dir: string, name: string, body: string): string {
  const file = path.join(dir, name)
  fs.writeFileSync(file, `#!/bin/sh\n${body}\n`, { mode: 0o755 })
  return file
}

/** A fake login shell: sets PATH like a profile would, then runs the script it was given ($4, after -i -l -c). */
function fakeShell(dir: string, before: string): string {
  return script(dir, 'shell', `${before}\nexec /bin/sh -c "$4"`)
}

function alive(pid: number): boolean {
  try { process.kill(pid, 0); return true } catch { return false }
}

test('the script is fixed text: no data goes into it', () => {
  assert.equal(LOGIN_SHELL_SCRIPT, `printf '%s' ${MARK}; printenv PATH; printf '%s' ${MARK}`)
  assert.match(MARK, /^[A-Za-z0-9_]+$/)
})

test('parsing keeps absolute folders between the marks, once each, in order', () => {
  const out = `Welcome back!\n${MARK}/home/u/.nvm/versions/node/v22/bin:bin:/usr/bin::./x:/usr/bin:/a\x1bb:/bin\n${MARK}bye`
  assert.deepEqual(parseLoginShellPath(out), ['/home/u/.nvm/versions/node/v22/bin', '/usr/bin', '/bin'])
  assert.deepEqual(parseLoginShellPath('no marks at all'), [])
  assert.deepEqual(parseLoginShellPath(`${MARK}/usr/bin`), [], 'an unfinished answer counts for nothing')
})

test('the login shell is SHELL, else the account\'s, and only an absolute path', () => {
  assert.equal(loginShell({ SHELL: '/bin/zsh' }, () => '/bin/bash'), '/bin/zsh')
  assert.equal(loginShell({}, () => '/bin/bash'), '/bin/bash')
  assert.equal(loginShell({ SHELL: 'zsh' }, () => '/bin/bash'), null, 'a bare name would be looked up on a PATH we don\'t trust')
  assert.equal(loginShell({}, () => null), null)
  assert.equal(loginShell({}, () => { throw new Error('no passwd entry') }), null)
})

test('reads the PATH the profile builds, ignoring what else it prints', posixOnly, async () => {
  const dir = tempDir()
  const shell = fakeShell(dir, 'echo "Good morning"\nPATH=/opt/nvm/bin:relative:/usr/bin:/bin; export PATH')
  assert.deepEqual(await readLoginShellPath({ shell, env: {}, home: dir }), ['/opt/nvm/bin', '/usr/bin', '/bin'])
})

test('runs in the home folder with the environment it is given', posixOnly, async () => {
  const dir = tempDir()
  const shell = fakeShell(dir, 'PATH="$(pwd):$CHECK:/usr/bin:/bin"; export PATH')
  const dirs = await readLoginShellPath({ shell, env: { CHECK: '/given' }, home: dir })
  assert.deepEqual(dirs, [fs.realpathSync(dir), '/given', '/usr/bin', '/bin'])
})

test('a stuck profile is cut off: nothing found, its whole process group killed', posixOnly, async () => {
  const dir = tempDir()
  const pidFile = path.join(dir, 'pid')
  const shell = script(dir, 'shell', `sleep 30 &\necho $! > "${pidFile}"\nwait`)
  const started = Date.now()
  assert.deepEqual(await readLoginShellPath({ shell, env: {}, home: dir, timeoutMs: 500 }), [])
  assert.ok(Date.now() - started < 5000)
  const pid = Number(fs.readFileSync(pidFile, 'utf8'))
  for (let i = 0; i < 50 && alive(pid); i++) await new Promise((r) => setTimeout(r, 20))
  assert.equal(alive(pid), false, 'what the profile started is gone too')
})

test('a background job holding the output open doesn\'t make it wait', posixOnly, async () => {
  const dir = tempDir()
  const shell = fakeShell(dir, 'PATH=/opt/x:/usr/bin:/bin; export PATH\n(sleep 30) &')
  const started = Date.now()
  assert.deepEqual(await readLoginShellPath({ shell, env: {}, home: dir, timeoutMs: 8000 }), ['/opt/x', '/usr/bin', '/bin'])
  assert.ok(Date.now() - started < 4000)
})

test('a missing shell, a failing one or a flood of output finds nothing', posixOnly, async () => {
  const dir = tempDir()
  assert.deepEqual(await readLoginShellPath({ shell: path.join(dir, 'nope'), env: {}, home: dir }), [])
  assert.deepEqual(await readLoginShellPath({ shell: script(dir, 'fail', 'exit 1'), env: {}, home: dir }), [])
  const flood = script(dir, 'flood', `printf '%s' ${MARK}\nhead -c 200000 /dev/zero | tr '\\0' a\nwait`)
  assert.deepEqual(await readLoginShellPath({ shell: flood, env: {}, home: dir, timeoutMs: 5000 }), [])
})

test('findClaude asks the login shell last, and uses what it finds', posixOnly, async () => {
  const dir = tempDir()
  const bin = path.join(dir, 'nvm', 'bin')
  fs.mkdirSync(bin, { recursive: true })
  const claude = script(bin, 'claude', 'echo "2.1.300 (Claude Code)"')
  let asked = 0
  const found = await findClaude({
    env: { PATH: '' }, cleanEnv: {}, platform: 'linux', home: dir,
    loginShellPath: async () => { asked++; return ['/nowhere', bin] },
  })
  assert.deepEqual(found, { path: claude, version: '2.1.300' })
  assert.equal(asked, 1)
})

test('findClaude doesn\'t ask the login shell when a candidate works, on Windows, or with a path set by hand', posixOnly, async () => {
  const dir = tempDir()
  const local = path.join(dir, '.local', 'bin')
  fs.mkdirSync(local, { recursive: true })
  script(local, 'claude', 'echo "2.1.300 (Claude Code)"')
  let asked = 0
  const loginShellPath = async () => { asked++; return [] }
  await findClaude({ env: { PATH: '' }, cleanEnv: {}, platform: 'linux', home: dir, loginShellPath })
  const manual = script(dir, 'my-claude', 'echo "2.1.300 (Claude Code)"')
  await findClaude({ env: { PATH: '' }, cleanEnv: {}, platform: 'linux', home: tempDir(), override: manual, loginShellPath })
  await assert.rejects(findClaude({ env: { PATH: '' }, cleanEnv: {}, platform: 'linux', home: tempDir(), override: path.join(dir, 'nope'), loginShellPath }))
  await assert.rejects(findClaude({ env: { PATH: '' }, cleanEnv: {}, platform: 'win32', home: tempDir(), loginShellPath }))
  assert.equal(asked, 0)
})

test('findClaude says a claude found through the login shell is too old', posixOnly, async () => {
  const dir = tempDir()
  script(dir, 'claude', 'echo "2.1.1 (Claude Code)"')
  await assert.rejects(
    findClaude({ env: { PATH: '' }, cleanEnv: {}, platform: 'linux', home: tempDir(), loginShellPath: async () => [dir] }),
    (e: Error) => e.message.includes('2.1.1 is too old') && e.message.includes(MIN_VERSION),
  )
})
