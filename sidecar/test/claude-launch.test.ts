// Claude provider: finding claude, and what a create launches.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { candidates, npmWrapperTargets, parseVersion, versionAtLeast, MIN_VERSION } from '../src/providers/claude/find.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { CLAUDE_SESSION_MARKERS } from '../src/providers/claude/env.ts'
import { takeSessionFile } from '../src/launch/launcher.ts'
import { CommandError } from '../src/provider.ts'
import { connect, testServer } from './helpers.ts'

test('version parsing and comparison', () => {
  assert.equal(parseVersion('2.1.284 (Claude Code)\n'), '2.1.284')
  assert.equal(parseVersion('v22.21.0'), null)
  assert.equal(parseVersion(''), null)
  assert.ok(versionAtLeast('2.1.284', MIN_VERSION))
  assert.ok(versionAtLeast('2.2.0', '2.1.284'))
  assert.ok(versionAtLeast('10.0.0', '2.1.284'))
  assert.ok(!versionAtLeast('2.1.99', '2.1.284'))
})

test('Windows candidates: PATH, native installer, WinGet, never a .cmd', () => {
  const list = candidates('win32', { LOCALAPPDATA: 'C:\\Users\\u\\AppData\\Local', PATH: '' }, 'C:\\Users\\u')
  assert.deepEqual(list, [
    'C:\\Users\\u\\.local\\bin\\claude.exe',
    'C:\\Users\\u\\AppData\\Local\\Microsoft\\WinGet\\Links\\claude.exe',
  ])
  assert.ok(list.every((p) => p.endsWith('.exe')))
})

test('macOS and Linux candidates include the documented locations', () => {
  const mac = candidates('darwin', { PATH: '' }, '/Users/u')
  assert.deepEqual(mac.slice(0, 3), ['/Users/u/.local/bin/claude', '/opt/homebrew/bin/claude', '/usr/local/bin/claude'])
  const linux = candidates('linux', { PATH: '' }, '/home/u')
  assert.ok(linux.includes('/usr/bin/claude'))
  assert.equal(linux[0], '/home/u/.local/bin/claude')
})

test('npm wrapper: finds the exe inside the npm folder, never outside it', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'npm-'))
  const cmd = path.join(dir, 'claude.cmd')
  fs.writeFileSync(cmd, '@ECHO off\r\n"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe" %*\r\n' +
    '"%dp0%\\..\\..\\evil\\claude.exe" %*\r\n')
  const got = npmWrapperTargets(cmd)
  const inside = path.win32.join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe')
  assert.ok(got.includes(inside))
  assert.ok(got.every((p) => p.toLowerCase().startsWith(dir.toLowerCase())), JSON.stringify(got))
})

test('session markers are named, and user settings are not among them', () => {
  for (const kept of ['CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_SKIP_PROMPT_HISTORY', 'ANTHROPIC_BASE_URL',
    'ANTHROPIC_API_KEY', 'CLAUDE_CODE_DISABLE_TERMINAL_TITLE', 'CLAUDE_CODE_GIT_BASH_PATH']) {
    assert.ok(!CLAUDE_SESSION_MARKERS.includes(kept), kept)
  }
  assert.ok(CLAUDE_SESSION_MARKERS.includes('CLAUDECODE'))
  assert.ok(CLAUDE_SESSION_MARKERS.includes('CLAUDE_CODE_CHILD_SESSION'))
})

function provider(over: Partial<ConstructorParameters<typeof ClaudeProvider>[0]> = {}) {
  const opened: { argv: string[]; title: string }[] = []
  const p = new ClaudeProvider({
    log: { info() {}, warn() {}, error() {} },
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { opened.push({ argv: req.argv, title: req.title }); return 'fake' },
    ...over,
  })
  return { p, opened }
}

test('create writes a launch file and opens a terminal with only our launcher', async () => {
  const { p, opened } = provider()
  const s = await testServer([p])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const project = fs.mkdtempSync(path.join(os.tmpdir(), 'proj;"x '))
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: project } })
    assert.equal(r.type, 'ok', JSON.stringify(r))
    assert.equal(opened.length, 1)
    const [exe, mode, file] = opened[0]!.argv
    assert.equal(exe, '/sidecar')
    assert.equal(mode, 'launch')
    assert.ok(!/[;"]/.test(opened[0]!.title), 'title has no characters a terminal could split on')
    const launch = takeSessionFile(file!)
    assert.equal(launch.command, process.execPath)
    assert.equal(launch.cwd, path.resolve(project))
    assert.equal(launch.args[0], '--session-id')
    assert.match(launch.args[1]!, /^[0-9a-f-]{36}$/)
    assert.deepEqual(launch.args.slice(2), ['--name', path.basename(project)])
    assert.deepEqual([...launch.unsetEnv].sort(), [...ClaudeProvider.UNSET_ENV].sort())
    // No permission mode is chosen for the user.
    assert.ok(!launch.args.some((a) => a.startsWith('--permission-mode') || a.includes('dangerously-skip')))
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('create reports a missing claude or terminal as a readable error', async () => {
  const { ClaudeNotFound } = await import('../src/providers/claude/find.ts')
  const { TerminalError } = await import('../src/launch/terminal.ts')
  const cases = [
    provider({ findClaude: async () => { throw new ClaudeNotFound('Claude Code wasn\'t found.') } }).p,
    provider({ openTerminal: async () => { throw new TerminalError('none') } }).p,
  ]
  for (const p of cases) {
    const s = await testServer([p])
    try {
      const c = await connect(s.port, s.token)
      await c.sync()
      const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: os.tmpdir() } })
      assert.equal(r.type, 'error')
      assert.equal(r.code, 'provider_error')
      assert.match(String(r.message), /wasn't found|terminal/)
      await c.close()
    } finally { await s.close(); await p.shutdown() }
  }
})

test('ending from the world is not supported yet', async () => {
  const { p } = provider()
  const session = await p.create({ id: 's', announce() {}, emit: () => true, end() {}, ended: false },
    { project: { path: os.tmpdir() } })
  await assert.rejects(session.end(), (e: unknown) => e instanceof CommandError && e.code === 'not_supported')
  await p.shutdown()
})
