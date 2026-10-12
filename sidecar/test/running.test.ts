// Sessions running elsewhere (S04): reading `claude agents --json`, and
// failing soft when it can't answer. The sample is shaped like Claude Code
// 2.1.296's output.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import os from 'node:os'
import { parseRunning, runningSessions } from '../src/providers/claude/running.ts'

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
