// The transcript follower (NOTES.md -> S02 -> Filling the gaps): Esc and a
// terminal "No" fire no hook but are written to the transcript. Lines are
// shaped like Claude Code 2.1.284's (spike transcript, trimmed).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { signalsIn, TranscriptFollower, POLL_MS, type TranscriptSignal } from '../src/providers/claude/transcript.ts'
import { HookTranslator, MAIN } from '../src/providers/claude/hooks.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { connect, RecordingLog, testServer } from './helpers.ts'

const REJECTED = JSON.stringify({
  parentUuid: 'p', isSidechain: false, promptId: 'x', type: 'user',
  message: { role: 'user', content: [{ type: 'tool_result', content: 'The user doesn\'t want to proceed with this tool use...', is_error: true, tool_use_id: 'toolu_1' }] },
  toolUseResult: 'User rejected tool use', toolDenialKind: 'user-rejected', sessionId: 's', version: '2.1.284',
})
const AFTER_NO = JSON.stringify({ type: 'user', isSidechain: false, message: { role: 'user', content: [{ type: 'text', text: '[Request interrupted by user for tool use]' }] } })
const ESC = JSON.stringify({ type: 'user', isSidechain: false, message: { role: 'user', content: [{ type: 'text', text: '[Request interrupted by user]' }] }, interruptedMessageId: 'msg_1' })

test('signals: a terminal "No", the interruption after it, and Esc', () => {
  assert.deepEqual(signalsIn(REJECTED), [{ kind: 'rejected', toolUseId: 'toolu_1' }])
  assert.deepEqual(signalsIn(AFTER_NO), [{ kind: 'interrupted' }])
  assert.deepEqual(signalsIn(ESC), [{ kind: 'interrupted' }])
  assert.deepEqual(signalsIn(JSON.stringify({ type: 'user', message: { content: '[Request interrupted by user]' } })), [{ kind: 'interrupted' }])
})

test('signals: ordinary errors, user text that merely mentions it, subagents and junk are not', () => {
  const failed = JSON.stringify({ type: 'user', message: { content: [{ type: 'tool_result', is_error: true, tool_use_id: 't', content: 'Exit code 1' }] }, toolUseResult: 'Error: Exit code 1' })
  assert.deepEqual(signalsIn(failed), [])
  assert.deepEqual(signalsIn(JSON.stringify({ type: 'user', message: { content: 'what does [Request interrupted by user] mean?' } })), [])
  assert.deepEqual(signalsIn(JSON.stringify({ type: 'user', isSidechain: true, message: { content: [{ type: 'text', text: '[Request interrupted by user]' }] } })), [])
  assert.deepEqual(signalsIn(JSON.stringify({ type: 'assistant', message: { content: [{ type: 'text', text: '[Request interrupted by user]' }] } })), [])
  assert.deepEqual(signalsIn('not json'), [])
  // A conversation moved to another session (seen live, 2.1.285).
  const CONTINUED = '{"type":"continued-in","timestamp":"2026-10-01T11:29:01.003Z","sessionId":"c5c192c8-4583-4d49-83ea-83f7e6e5acb0","continuedInSessionId":"96033ade-7ef9-4542-a7ba-abbf1bf5ebbd"}'
  assert.deepEqual(signalsIn(CONTINUED), [{ kind: 'continued', sessionId: '96033ade-7ef9-4542-a7ba-abbf1bf5ebbd' }])
  assert.deepEqual(signalsIn(JSON.stringify({ type: 'continued-in', continuedInSessionId: '../../x' })), [])
  assert.deepEqual(signalsIn(JSON.stringify({ type: 'continued-in' })), [])
  assert.deepEqual(signalsIn('null'), [])
})

test('translator: a "No" denies the call\'s prompt; the interruption leaves the orchestrator idle', () => {
  const t = new HookTranslator(os.tmpdir())
  t.translate({ hook_event_name: 'UserPromptSubmit', prompt: 'go' })
  t.translate({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'git push' }, tool_use_id: 'toolu_1' })
  t.translate({ hook_event_name: 'PreToolUse', tool_name: 'Read', tool_input: {}, tool_use_id: 'toolu_r' })
  t.permissionRequested({ request_id: 'abcde', tool_name: 'Bash', description: '', input_preview: '{"command":"git push"}' })
  assert.deepEqual(t.rejectedInTerminal('toolu_1'), [
    { type: 'permission.resolved', permission: 'abcde', decision: 'deny', by: 'external' },
    { type: 'tool.finished', tool_call: 'toolu_1', status: 'denied' },
  ])
  assert.deepEqual(t.rejectedInTerminal('toolu_1'), [], 'once')
  assert.deepEqual(t.interruptedByUser(), [
    { type: 'tool.finished', tool_call: 'toolu_r', status: 'error', summary: 'Interrupted' },
    { type: 'agent.state_changed', agent: MAIN, state: 'idle', reason: null },
  ])
  assert.deepEqual(t.interruptedByUser(), [], 'already idle')
})

// ---- the follower on real files ----

const tmpFile = () => path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'tr-')), 'session.jsonl')

test('follower: only lines written after it starts, whole lines only, across split reads', () => {
  const file = tmpFile()
  fs.writeFileSync(file, ESC + '\n')                     // before: ignored
  const got: TranscriptSignal[] = []
  const f = new TranscriptFollower((s) => got.push(s))
  try {
    f.follow(file)
    f.poll()
    assert.deepEqual(got, [])
    // A line arriving in two pieces, split inside a multi-byte character.
    const line = Buffer.from(JSON.stringify({ type: 'user', message: { content: [{ type: 'text', text: 'héllo ✓' }] } }) + '\n' + REJECTED + '\n')
    const cut = line.indexOf(Buffer.from('✓')) + 1
    fs.appendFileSync(file, line.subarray(0, cut))
    f.poll()
    assert.deepEqual(got, [])
    fs.appendFileSync(file, line.subarray(cut))
    f.poll()
    assert.deepEqual(got, [{ kind: 'rejected', toolUseId: 'toolu_1' }])
    fs.appendFileSync(file, AFTER_NO + '\n')
    f.poll()
    assert.equal(got.length, 2)
  } finally { f.stop() }
})

test('follower: a missing file (transcripts off) is fine; a new path (/clear) is followed from its end', () => {
  const got: TranscriptSignal[] = []
  const f = new TranscriptFollower((s) => got.push(s))
  try {
    const missing = tmpFile()
    f.follow(missing)
    f.poll()
    fs.writeFileSync(missing, ESC + '\n')                  // created later: read from the start
    f.poll()
    assert.deepEqual(got, [{ kind: 'interrupted' }])

    const next = tmpFile()
    fs.writeFileSync(next, ESC + '\n')
    f.follow(next)
    f.poll()
    assert.equal(got.length, 1, 'what was already there is the past')
    f.follow('relative.jsonl')
    f.follow('/abs/not-a-transcript.txt')
    fs.appendFileSync(next, ESC + '\n')
    f.poll()
    assert.equal(got.length, 2, 'still following the last good path')
    // Rewritten shorter: its old lines aren't replayed; new ones are read.
    fs.writeFileSync(next, ESC + '\n')
    f.poll()
    assert.equal(got.length, 2, 'a rewrite is not news')
    fs.appendFileSync(next, AFTER_NO + '\n')
    f.poll()
    assert.equal(got.length, 3)
  } finally { f.stop() }
})

// ---- through a session ----

test('through a session: Esc in the terminal reaches the world from the transcript', async () => {
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  let sock: net.Socket | null = null
  try {
    await c.sync()
    await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'esc-')) } })
    const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
    const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.UserPromptSubmit[0].hooks[0]
    const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
    sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
    await c.next('session.created')

    const transcript = tmpFile()
    fs.writeFileSync(transcript, '')
    await new Promise<void>((resolve, reject) => {
      const req = http.request({ host: '127.0.0.1', port: Number(new URL(h.url).port), method: 'POST', path: '/hook',
        headers: { authorization: h.headers.Authorization } }, (res) => { res.resume(); res.on('end', resolve) })
      req.on('error', reject)
      req.end(JSON.stringify({ hook_event_name: 'UserPromptSubmit', prompt: 'write a long story', transcript_path: transcript }))
    })
    assert.equal((await c.next((m) => m.type === 'agent.state_changed')).state, 'working')
    fs.appendFileSync(transcript, ESC + '\n')
    const idle = await c.next((m) => m.type === 'agent.state_changed', POLL_MS * 8)
    assert.deepEqual([idle.agent, idle.state], ['main', 'idle'])
    assert.deepEqual(c.invalid, [])
  } finally { sock?.destroy(); await c.close(); await s.close(); await p.shutdown() }
})
