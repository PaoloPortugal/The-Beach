// Claude provider: finding claude, and what a create launches.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { candidates, npmWrapperTargets, parseVersion, versionAtLeast, MIN_VERSION } from '../src/providers/claude/find.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { CLAUDE_SESSION_MARKER_PREFIXES, CLAUDE_SESSION_MARKERS } from '../src/providers/claude/env.ts'
import { cleanEnv } from '../src/launch/env.ts'
import { takeSessionFile } from '../src/launch/launcher.ts'
import { CommandError } from '../src/provider.ts'
import { connect, testServer, tempSessionsDir, bridgeOf } from './helpers.ts'

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

// Windows paths on a real folder: only meaningful where the wrapper exists.
test('npm wrapper: finds the exe inside the npm folder, never outside it', { skip: process.platform !== 'win32' }, () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'npm-'))
  const cmd = path.join(dir, 'claude.cmd')
  fs.writeFileSync(cmd, '@ECHO off\r\n"%dp0%\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude.exe" %*\r\n' +
    '"%dp0%\\..\\..\\evil\\claude.exe" %*\r\n')
  const got = npmWrapperTargets(cmd)
  const inside = path.win32.join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe')
  assert.ok(got.includes(inside))
  assert.ok(got.every((p) => p.toLowerCase().startsWith(dir.toLowerCase())), JSON.stringify(got))
})

test('session markers go, user settings stay', () => {
  const settings = {
    CLAUDE_CONFIG_DIR: '1', CLAUDE_CODE_SKIP_PROMPT_HISTORY: '1', ANTHROPIC_BASE_URL: '1', ANTHROPIC_API_KEY: '1',
    CLAUDE_CODE_DISABLE_TERMINAL_TITLE: '1', CLAUDE_CODE_GIT_BASH_PATH: '1', CLAUDE_CODE_EFFORT_LEVEL: '1',
    CLAUDE_CODE_USE_POWERSHELL_TOOL: '1', CLAUDE_CODE_OAUTH_SCOPES: '1', DISABLE_AUTOUPDATER: '1',
  }
  const markers = {
    CLAUDECODE: '1', CLAUDE_CODE_CHILD_SESSION: '1', CLAUDE_CODE_SESSION_ID: '1', CLAUDE_CODE_SESSION_ATTENDED: '1',
    CLAUDE_CODE_MESSAGING_SOCKET: '1', CLAUDE_CODE_MESSAGING_TOKEN: '1', CLAUDE_CODE_BRIDGE_SESSION_ID: '1',
    CLAUDE_EFFORT: '1', CLAUDE_CODE_HOST_SESSION_ID: '1', CLAUDE_PID: '1',
  }
  const unset = { names: CLAUDE_SESSION_MARKERS, prefixes: CLAUDE_SESSION_MARKER_PREFIXES }
  for (const platform of ['win32', 'linux'] as const) {
    assert.deepEqual(cleanEnv({ ...settings, ...markers }, unset, platform), settings, platform)
  }
})

function provider(over: Partial<ConstructorParameters<typeof ClaudeProvider>[0]> = {}) {
  const opened: { argv: string[]; title: string }[] = []
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
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
    // `;` and spaces are legal in folder names and must not reach a terminal.
    const project = fs.mkdtempSync(path.join(os.tmpdir(), 'proj;x '))
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: project } })
    assert.equal(r.type, 'ok', JSON.stringify(r))
    // Until it's up, the world tells the user to confirm in the terminal.
    assert.deepEqual((r.result as any).notice, {
      code: 'confirm_in_terminal', message: 'Confirm in the Claude Code terminal to start this session.',
    })
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
    // No --name: Claude Code names it (NOTES.md -> S02 -> Titles).
    assert.equal(launch.args[2], '--settings')
    assert.equal(launch.args[4], '--mcp-config')
    assert.deepEqual(launch.args.slice(6), ['--dangerously-load-development-channels', 'server:world-bridge'])
    // Hooks for this session only, posting to loopback with a token.
    const settings = JSON.parse(fs.readFileSync(launch.args[3]!, 'utf8'))
    const hook = settings.hooks.PreToolUse[0].hooks[0]
    assert.equal(hook.type, 'http')
    assert.match(hook.url, /^http:\/\/127\.0\.0\.1:\d+\/hook$/)
    assert.match(hook.headers.Authorization, /^Bearer [0-9a-f]{64}$/)
    // Only hooks, agent view off (it would move the conversation out of
    // the world's reach) and, with no status line of the user's own, our
    // status line relay (C08); no other setting is changed for the user.
    assert.deepEqual(Object.keys(settings).filter((k) => k !== 'statusLine'), ['hooks', 'disableAgentView'])
    assert.equal(settings.disableAgentView, true)
    // The bridge's config: this executable in bridge mode, and only the path
    // of its bridge file (in the run folder, beside the launch file) in the
    // bridge's own environment; the file holds the port and a token (S07).
    const mcp = JSON.parse(fs.readFileSync(launch.args[5]!, 'utf8'))
    const bridge = mcp.mcpServers['world-bridge']
    assert.equal(bridge.command, '/sidecar')
    assert.deepEqual(bridge.args, ['bridge', 'claude'])
    assert.deepEqual(Object.keys(bridge.env), ['BRIDGE_FILE'])
    assert.equal(path.dirname(bridge.env.BRIDGE_FILE), path.dirname(file!))
    assert.match(bridgeOf(bridge.env).token, /^[0-9a-f]{64}$/)
    assert.ok(bridgeOf(bridge.env).port > 0)
    assert.deepEqual(launch.unsetEnv, ClaudeProvider.UNSET_ENV)
    // No permission mode is chosen for the user.
    assert.ok(!launch.args.some((a) => a.startsWith('--permission-mode') || a.includes('dangerously-skip')))
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('terminal titles are plain printable text, short, whatever the session name holds', async () => {
  const { terminalTitle } = await import('../src/providers/claude/index.ts')
  assert.equal(terminalTitle('my-project'), 'Claude Code - my-project')
  const nasty = 'fix it"; wt new-tab calc\r\n\t\u0007\u009b[31m \\ back\\slash' + 'x'.repeat(200)
  const t = terminalTitle(nasty)
  assert.ok(!/[\u0000-\u001f\u007f-\u009f;"\\]/.test(t), JSON.stringify(t))
  assert.ok(t.length <= 'Claude Code - '.length + 60)
  assert.equal(terminalTitle('\n\n'), 'Claude Code - session')
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
