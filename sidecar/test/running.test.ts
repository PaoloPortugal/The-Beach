// Sessions running elsewhere (S04): reading `claude agents --json`, and
// failing soft when it can't answer. The sample is shaped like Claude Code
// 2.1.296's output.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import os from 'node:os'
import fs from 'node:fs'
import { AGENT_NAME_MAX, agentViewOff, parseAgents, parseRunning, runningSessions } from '../src/providers/claude/running.ts'

const A = '941123d6-76b6-49dd-a535-ead2d397f818'
const B = '7f5fa86f-d520-41df-a38c-dc9c01d7a087'
const C = '1815f799-d02c-438c-95c0-a1811663c8ac'

test('parse: sessions whose process is alive, by their full id', () => {
  const out = JSON.stringify([
    { pid: 20048, cwd: 'C:\\p', kind: 'interactive', startedAt: 1, sessionId: A, name: 'Session', status: 'idle' },
    // A background session whose process exited: listed, but not running.
    { cwd: '/p', kind: 'background', startedAt: 2, id: 'ab12', state: 'blocked', sessionId: B },
    // Ids in another case are the same session.
    { pid: 3, cwd: '/p', kind: 'interactive', startedAt: 3, sessionId: C.toUpperCase(), status: 'busy' },
    // Not a session id, no id, a pid that isn't a number, not an object.
    { pid: 4, cwd: '/p', kind: 'interactive', startedAt: 4, sessionId: '../../x' },
    { pid: 5, cwd: '/p', kind: 'interactive', startedAt: 5 },
    { pid: '6', sessionId: A.replace('9', '8') },
    null, 'x', 7,
  ])
  assert.deepEqual([...parseRunning(out)], [A, C])
})

test('parse agents (S07): each live entry with its process and state, ids lowercased', () => {
  const out = JSON.stringify([
    { pid: 20048, cwd: 'C:\\p', kind: 'interactive', sessionId: A, status: 'idle' },
    { cwd: '/p', kind: 'background', sessionId: B, state: 'blocked' },
    { pid: 3, sessionId: C.toUpperCase(), status: 'waiting' },
    // A state we don't know yet is kept as is; none at all is empty.
    { pid: 8, sessionId: B, status: 'thinking' },
    { pid: 9, sessionId: A },
    // Not a usable process id.
    { pid: 0, sessionId: A }, { pid: -1, sessionId: A }, { pid: 1.5, sessionId: A }, { pid: '6', sessionId: A },
  ])
  assert.deepEqual(parseAgents(out), [
    // A Windows folder is only absolute on Windows.
    { sessionId: A, pid: 20048, status: 'idle', ...(path.isAbsolute('C:\\p') ? { cwd: 'C:\\p' } : {}), kind: 'interactive' },
    { sessionId: C, pid: 3, status: 'waiting' },
    { sessionId: B, pid: 8, status: 'thinking' },
    { sessionId: A, pid: 9, status: '' },
  ])
  for (const bad of ['', 'not json', '{"pid":1}', 'null']) assert.deepEqual(parseAgents(bad), [], bad)
})

test('parse agents (S08): the documented fields an outside session is shown with; each of the wrong shape left out', () => {
  const abs = path.resolve(os.tmpdir(), 'proj')
  const out = JSON.stringify([
    { pid: 1, sessionId: A, status: 'waiting', cwd: abs, kind: 'interactive', startedAt: 1792667057753, name: 'Session #65 (W12)', waitingFor: 'permission prompt' },
    // Wrong shapes: a relative or control-laden folder, an odd kind, a start that isn't a whole positive number, a name of nothing but spaces.
    { pid: 2, sessionId: B, status: 'idle', cwd: 'relative/p', kind: 'Inter active', startedAt: -5, name: '  \t ', waitingFor: 'x'.repeat(41) },
    { pid: 3, sessionId: C, status: 'idle', cwd: abs + '\n', kind: 7, startedAt: 1.5, name: 7, waitingFor: 'a\u0007b' },
    { pid: 4, sessionId: C, status: 'idle', startedAt: '1792667057753', cwd: 42 },
  ])
  assert.deepEqual(parseAgents(out), [
    { sessionId: A, pid: 1, status: 'waiting', cwd: abs, kind: 'interactive', startedAt: 1792667057753, name: 'Session #65 (W12)', waitingFor: 'permission prompt' },
    { sessionId: B, pid: 2, status: 'idle' },
    { sessionId: C, pid: 3, status: 'idle' },
    { sessionId: C, pid: 4, status: 'idle' },
  ])
})

test('parse agents (S08): a name is plain text on one line, without control or bidi characters, cut to its limit', () => {
  const name = (n: string) => parseAgents(JSON.stringify([{ pid: 1, sessionId: A, status: 'idle', name: n }]))[0]!.name
  assert.equal(name('fix\nthe\u0000 login‮ reversed⁦'), 'fix the login reversed')
  assert.equal(name('x'.repeat(AGENT_NAME_MAX + 50))!.length, AGENT_NAME_MAX)
})

test('agent view off (S08): Claude Code\'s refusal is told apart from other failures', () => {
  assert.equal(agentViewOff("'claude agents --json' is disabled by CLAUDE_CODE_DISABLE_AGENT_VIEW."), true)
  assert.equal(agentViewOff("'claude agents --json' is disabled by the 'disableAgentView' setting."), true)
  for (const other of ['spawn claude ENOENT', 'Command failed: claude agents --json', 'claude agents --json printed no list', 'agent view crashed']) {
    assert.equal(agentViewOff(other), false, other)
  }
})

test('asking (S08): with agent view off, the answer says so', async () => {
  const got = await withAgents("console.error(\"'claude agents --json' is disabled by CLAUDE_CODE_DISABLE_AGENT_VIEW.\"); process.exit(1)",
    () => runningSessions(process.execPath, { PATH: process.env.PATH ?? '' }))
  assert.deepEqual(got, { none: "'claude agents --json' is disabled by CLAUDE_CODE_DISABLE_AGENT_VIEW.", disabled: true })
  const other = await withAgents("console.error('something else broke'); process.exit(1)",
    () => runningSessions(process.execPath, { PATH: process.env.PATH ?? '' }))
  assert.deepEqual(other, { none: 'something else broke' })
})

test('parse: anything but the documented array gives nothing', () => {
  for (const out of ['', 'not json', '{"pid":1}', 'null', '[]',
    "'claude agents --json' is disabled by the 'disableAgentView' setting.",
    '2 agents\n  general-purpose · inherit']) {
    assert.deepEqual([...parseRunning(out)], [], out)
  }
})

test('asking fails soft: a missing claude, or one that errors, gives a reason and no list', async () => {
  const missing = await runningSessions(path.join(os.tmpdir(), 'no-such-claude', 'claude.exe'), {})
  assert.ok('none' in missing && missing.none.length > 0)
  // node runs "agents" as a script, which doesn't exist: an error exit.
  const failing = await runningSessions(process.execPath, { PATH: process.env.PATH ?? '' })
  assert.ok('none' in failing, JSON.stringify(failing))
})

// `node agents --json` runs the file `agents` in the current folder: stand-ins for a claude that hangs,
// floods its output or prints something else.
async function withAgents(script: string, ask: () => Promise<unknown>): Promise<unknown> {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'agents-'))
  fs.writeFileSync(path.join(dir, 'agents'), script)
  const cwd = process.cwd()
  process.chdir(dir)
  try { return await ask() } finally { process.chdir(cwd); fs.rmSync(dir, { recursive: true, force: true }) }
}

test('asking fails soft: one that hangs is stopped at the time limit', async () => {
  const started = Date.now()
  const got = await withAgents('setTimeout(() => {}, 60000)',
    () => runningSessions(process.execPath, { PATH: process.env.PATH ?? '' }, { timeoutMs: 500 }))
  assert.ok(got && typeof got === 'object' && 'none' in got, JSON.stringify(got))
  assert.ok(Date.now() - started < 10000, 'stopped, not waited out')
})

test('asking fails soft: output over the limit is refused', async () => {
  const got = await withAgents("process.stdout.write('[' + '0,'.repeat(100000) + '0]')",
    () => runningSessions(process.execPath, { PATH: process.env.PATH ?? '' }, { maxOutput: 1024 }))
  assert.ok(got && typeof got === 'object' && 'none' in got, JSON.stringify(got))
})

test('asking fails soft: an answer that is no list gives a reason, a list gives its ids', async () => {
  const none = await withAgents("console.log('No agents.')",
    () => runningSessions(process.execPath, { PATH: process.env.PATH ?? '' }))
  assert.deepEqual(none, { none: 'claude agents --json printed no list' })
  const some = await withAgents(`console.log(JSON.stringify([{ pid: 1, sessionId: '${A}', status: 'busy' }]))`,
    () => runningSessions(process.execPath, { PATH: process.env.PATH ?? '' })) as { ids: Set<string>; agents: unknown }
  assert.deepEqual([...some.ids], [A])
  assert.deepEqual(some.agents, [{ sessionId: A, pid: 1, status: 'busy' }], 'with the entries, for S07')
})

test('asking fails soft: a claude that can\'t be started at all gives a reason', async () => {
  // A NUL in the path makes execFile throw at once instead of reporting.
  const got = await runningSessions('claude\0.exe', {})
  assert.ok('none' in got && got.none.length > 0, JSON.stringify(got))
})
