// A session's conversation changing under it (NOTES.md -> S02 -> Launch and
// "When the conversation changes"): /clear starts a new conversation in the
// same claude, which the world follows (session.updated + a notice); a
// conversation that moved to another session (agent view, turned off) is
// out of reach, so world messages get an error instead of being lost.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { CONVERSATION_CLEARED, CONVERSATION_MOVED, CONVERSATION_RESUMED, MOVED_ERROR, UNREACHABLE_ERROR } from '../src/providers/claude/session.ts'
import { POLL_MS } from '../src/providers/claude/transcript.ts'
import { checkMessage, type Usage } from '../src/protocol.ts'
import { connect, RecordingLog, testServer, type Msg, tempSessionsDir, bridgeOf } from './helpers.ts'

function post(port: number, auth: string, body: object) {
  return new Promise<{ status: number; body: string }>((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/hook',
      headers: { authorization: auth, 'content-type': 'application/json' } }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
}

/**
 * A launched session with a stand-in Claude Code. Its transcripts live in
 * a temporary "projects folder"; `bridge: false` leaves the channel
 * unconnected (the session comes up through its first hook); with
 * `up: false` too, no hook is sent, so it isn't up yet.
 */
async function liveSession(o: { bridge?: boolean; up?: boolean } = {}) {
  let launch: { args: string[] } = { args: [] }
  const log = new RecordingLog()
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log,
    findClaude: async () => ({ path: process.execPath, version: '2.1.285' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
    projectsDir: fs.mkdtempSync(path.join(os.tmpdir(), 'projects-')),
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'conv-')) } })
  const id = (r.result as { session: string }).session
  await c.next('provider.program') // the claude found for it (program_path), after the reply
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const nativeId = arg('--session-id')
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.PreToolUse[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  const port = Number(new URL(h.url).port)
  const transcripts = fs.mkdtempSync(path.join(os.tmpdir(), 'transcripts-'))
  const transcript = (sid: string) => path.join(transcripts, `${sid}.jsonl`)
  fs.writeFileSync(transcript(nativeId), '')
  const fromSidecar: any[] = []
  let sock: net.Socket | null = null
  if (o.bridge !== false) {
    sock = net.connect(bridgeOf(env).port, '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    sock.setEncoding('utf8').on('data', (d: string) => fromSidecar.push(...d.trim().split('\n').map((l) => JSON.parse(l))))
    sock.write(JSON.stringify({ type: 'hello', token: bridgeOf(env).token }) + '\n')
    sock.write(JSON.stringify({ type: 'ready' }) + '\n')
  }
  /** One hook from conversation `sid` (default: the launched one), as Claude Code sends it. */
  const send = (name: string, fields: Record<string, unknown> = {}, sid = nativeId) => post(port, h.headers.Authorization, {
    session_id: sid, transcript_path: transcript(sid), cwd: '/', hook_event_name: name, ...fields,
  })
  if (o.bridge === false && o.up !== false) await send('Stop')
  const created = o.up === false ? null : await c.next('session.created')
  const toBridge = (m: object) => sock!.write(JSON.stringify(m) + '\n')
  return {
    p, c, id, nativeId, created, fromSidecar, log, transcript, send, toBridge,
    close: async () => { sock?.destroy(); await c.close(); await s.close(); await p.shutdown() },
  }
}

const notice = (code: string) => (m: Msg) => m.type === 'session.notice' && (m.notice as { code: string }).code === code

test('/clear: the world follows the new conversation: session.updated, a notice, then its hooks', async () => {
  const x = await liveSession()
  try {
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'before' })
    assert.equal((await x.c.next('message.completed')).text, 'before')
    await x.send('Stop')
    await x.c.next('agent.state_changed')

    // /clear: same process, same projects folder, a new session id.
    const fresh = crypto.randomUUID()
    fs.writeFileSync(x.transcript(fresh), '')
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'after' }, fresh)
    const updated = await x.c.next('session.updated')
    assert.equal(updated.native_id, fresh)
    assert.deepEqual((await x.c.next(notice('conversation_cleared'))).notice, CONVERSATION_CLEARED)
    assert.equal((await x.c.next('message.completed')).text, 'after', 'its hooks are translated as before')
    const h = await x.c.command({ type: 'session.get_history', session: x.id })
    assert.deepEqual(((h.result as { messages: { text: string }[] }).messages).map((m) => m.text), ['after'],
      'the history starts over: the world clears its chat')
    // A later snapshot has it too.
    assert.equal((await x.c.command({ type: 'session.get_snapshot', session: x.id })).type, 'ok')
    assert.equal(((await x.c.next('session.snapshot')).session as { native_id: string }).native_id, fresh)
    // The world still talks to it through the same bridge.
    assert.equal((await x.c.command({ type: 'message.send', session: x.id, text: 'hi' })).type, 'ok')
    assert.deepEqual(x.fromSidecar.at(-1), { type: 'chat', text: 'hi' })

    // The new conversation is running: not resumable twice. The old one is stored now.
    await assert.rejects(x.p.resume({} as any, fresh), /already open/)
    await assert.rejects(x.p.resume({} as any, x.nativeId), /wasn't found/)
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('/resume: an earlier conversation with chat: its chat becomes the history, and a notice says so', async () => {
  const x = await liveSession()
  try {
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'before' })
    await x.c.next('message.completed')
    await x.send('Stop')
    await x.c.next('agent.state_changed')

    // /resume: an earlier conversation from the same folder, whose
    // transcript already holds its chat, plus the prompt that woke it.
    const earlier = crypto.randomUUID()
    const line = (e: object) => JSON.stringify(e) + '\n'
    fs.writeFileSync(x.transcript(earlier),
      line({ type: 'user', uuid: 'e1', timestamp: '2026-10-01T09:00:00Z', message: { role: 'user', content: 'old question' } }) +
      line({ type: 'assistant', timestamp: '2026-10-01T09:00:01Z', message: { id: 'm1', role: 'assistant', content: [{ type: 'text', text: 'old answer' }] } }) +
      line({ type: 'user', uuid: 'e2', timestamp: '2026-10-01T12:00:00Z', message: { role: 'user', content: 'what did we say?' } }))
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'what did we say?' }, earlier)
    assert.equal((await x.c.next('session.updated')).native_id, earlier)
    assert.deepEqual((await x.c.next(notice('conversation_resumed'))).notice, CONVERSATION_RESUMED)
    assert.equal((await x.c.next('message.completed')).text, 'what did we say?')
    await x.send('Stop', {}, earlier)
    await x.c.next('agent.state_changed')
    // The history is the resumed conversation's chat, then what came live; not the chat before.
    const h = await x.c.command({ type: 'session.get_history', session: x.id })
    const texts = ((h.result as { messages: { text: string }[] }).messages).map((m) => m.text)
    assert.deepEqual(texts, ['old question', 'old answer', 'what did we say?'])
    assert.ok(x.log.lines.some((l) => l.includes('earlier conversation (/resume)')))
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

// What /clear writes at the start of the new transcript (Claude Code
// 2.1.285, live re-check 2026-10-01): the command is a user entry.
const line = (e: object) => JSON.stringify(e) + '\n'
const CLEAR_ENTRIES =
  line({ type: 'user', isMeta: true, message: { role: 'user', content: '<local-command-caveat>Caveat: run directly in Claude Code.</local-command-caveat>' } }) +
  line({ type: 'user', message: { role: 'user', content: '<command-name>/clear</command-name>\n<command-message>clear</command-message>\n<command-args></command-args>' } }) +
  line({ type: 'system', subtype: 'local_command', content: '<local-command-stdout></local-command-stdout>' })
const EARLIER_CHAT =
  line({ type: 'user', uuid: 'e1', timestamp: '2026-10-01T09:00:00Z', message: { role: 'user', content: 'old question' } }) +
  line({ type: 'assistant', timestamp: '2026-10-01T09:00:01Z', message: { id: 'm1', role: 'assistant', content: [{ type: 'text', text: 'old answer' }] } })

const switches = (ms: Msg[]) => ms.filter((m) => (m.type === 'session.updated' && 'native_id' in m) || m.type === 'session.notice')
const titles = (ms: Msg[]) => ms.filter((m) => m.type === 'session.updated' && 'title' in m).map((m) => m.title)

const historyTexts = async (x: Awaited<ReturnType<typeof liveSession>>) => {
  const h = await x.c.command({ type: 'session.get_history', session: x.id })
  return ((h.result as { messages: { text: string }[] }).messages).map((m) => m.text)
}

/** A first turn in the launched conversation, so there's chat before the switch. */
async function chatBefore(x: Awaited<ReturnType<typeof liveSession>>) {
  await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'before' })
  await x.c.next('message.completed')
  await x.send('Stop')
  await x.c.next((m) => m.type === 'agent.state_changed' && m.state === 'idle')
}

test('SessionStart clear: the switch reaches the world at once, before any prompt; the chat starts over', async () => {
  const x = await liveSession()
  try {
    await chatBefore(x)
    const fresh = crypto.randomUUID()
    // Sent in the background right after /clear; the transcript may not exist yet.
    assert.deepEqual(await x.send('SessionStart', { source: 'clear' }, fresh), { status: 200, body: '' })
    const cleared = await x.c.next((m) => m.type === 'session.updated' && 'native_id' in m)
    assert.equal(cleared.native_id, fresh)
    assert.equal(cleared.title, null, 'a new conversation has no name yet')
    assert.deepEqual((await x.c.next(notice('conversation_cleared'))).notice, CONVERSATION_CLEARED)
    assert.deepEqual(await historyTexts(x), [], 'the history empties at once: the world clears its chat')
    // Then /clear's own entries and the first prompt: no second switch, not taken for a resume.
    fs.writeFileSync(x.transcript(fresh), CLEAR_ENTRIES)
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'after' }, fresh)
    assert.equal((await x.c.next('message.completed')).text, 'after')
    const after = await x.c.quiet()
    assert.deepEqual(switches(after), [], 'no second switch')
    assert.deepEqual(titles(after), ['after'], 'named by its first message')
    assert.deepEqual(await historyTexts(x), ['after'])
    await assert.rejects(x.p.resume({} as any, fresh), /already open/)
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('titles: none at first, then the first message, Claude Code\'s own title, and a /rename that stays', async () => {
  const x = await liveSession()
  try {
    assert.equal((x.created!.session as { title: unknown }).title, null, 'nothing to call it yet')
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: '  fix the login bug\nplease' })
    assert.equal((await x.c.next((m) => m.type === 'session.updated')).title, 'fix the login bug', 'its first line')
    // Claude Code writes its title a moment later (2.1.287), and again now and then.
    fs.appendFileSync(x.transcript(x.nativeId), line({ type: 'ai-title', aiTitle: 'Login bug fix', sessionId: x.nativeId }))
    assert.equal((await x.c.next((m) => m.type === 'session.updated')).title, 'Login bug fix')
    fs.appendFileSync(x.transcript(x.nativeId), line({ type: 'custom-title', customTitle: 'auth work', sessionId: x.nativeId }))
    assert.equal((await x.c.next((m) => m.type === 'session.updated')).title, 'auth work', '/rename wins')
    fs.appendFileSync(x.transcript(x.nativeId), line({ type: 'ai-title', aiTitle: 'Login bug fix again', sessionId: x.nativeId }) +
      line({ type: 'custom-title', customTitle: 'auth work', sessionId: x.nativeId }))
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'and the signup one' })
    await x.c.next('message.completed')
    assert.deepEqual(titles(await x.c.quiet(POLL_MS * 3)), [], 'and stays')
    await x.c.command({ type: 'session.get_snapshot', session: x.id })
    assert.equal(((await x.c.next('session.snapshot')).session as { title: string }).title, 'auth work', 'the snapshot has it too')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('SessionStart resume: the resumed conversation\'s chat becomes the history at once, all of it', async () => {
  const x = await liveSession()
  try {
    await chatBefore(x)
    const earlier = crypto.randomUUID()
    // Resumed before: its transcript holds /resume's entries too, which aren't chat.
    fs.writeFileSync(x.transcript(earlier), EARLIER_CHAT + CLEAR_ENTRIES.replaceAll('/clear', '/resume') +
      line({ type: 'user', uuid: 'e2', timestamp: '2026-10-01T10:00:00Z', message: { role: 'user', content: 'last question' } }))
    await x.send('SessionStart', { source: 'resume' }, earlier)
    const resumed = await x.c.next((m) => m.type === 'session.updated' && 'native_id' in m)
    assert.equal(resumed.native_id, earlier)
    assert.equal(resumed.title, 'old question', 'its own name comes with it')
    assert.deepEqual((await x.c.next(notice('conversation_resumed'))).notice, CONVERSATION_RESUMED)
    assert.deepEqual(await historyTexts(x), ['old question', 'old answer', 'last question'])
    // The world's chat reaches it through the same bridge.
    assert.equal((await x.c.command({ type: 'message.send', session: x.id, text: 'hi' })).type, 'ok')
    assert.deepEqual(x.fromSidecar.at(-1), { type: 'chat', text: 'hi' })
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'hi' }, earlier)
    assert.equal((await x.c.next('message.completed')).text, 'hi')
    const later = await x.c.quiet()
    assert.deepEqual(switches(later), [], 'no second switch')
    assert.deepEqual(titles(later), [], 'it keeps its name')
    assert.deepEqual(await historyTexts(x), ['old question', 'old answer', 'last question', 'hi'])
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('SessionStart: our own launch, compaction, the same id, a stray folder or a bad id change nothing', async () => {
  const x = await liveSession()
  try {
    await chatBefore(x)
    const other = crypto.randomUUID()
    const elsewhere = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'elsewhere-')), `${other}.jsonl`)
    for (const [fields, sid] of [
      [{ source: 'startup' }, other], [{ source: 'compact' }, other], [{ source: 'fork' }, other], [{}, other],
      [{ source: 'resume' }, x.nativeId],
      [{ source: 'clear', transcript_path: elsewhere }, other],
      [{ source: 'clear', transcript_path: '/x/not-a-uuid.jsonl' }, 'not-a-uuid'],
    ] as [Record<string, unknown>, string][]) {
      assert.deepEqual(await x.send('SessionStart', fields, sid), { status: 200, body: '' })
    }
    assert.deepEqual((await x.c.quiet()).map((m) => m.type), [])
    assert.deepEqual(await historyTexts(x), ['before'])
  } finally { await x.close() }
})

test('SessionStart before the session is up does not count as it coming up', async () => {
  const x = await liveSession({ bridge: false, up: false })
  try {
    await x.send('SessionStart', { source: 'resume' })
    await x.send('SessionStart', { source: 'clear' }, crypto.randomUUID())
    assert.deepEqual((await x.c.quiet()).map((m) => m.type), [], 'no session.created, no switch')
  } finally { await x.close() }
})

test('fallback (the relay failed): /clear\'s entries in the new transcript are not taken for a resume', async () => {
  const x = await liveSession()
  try {
    await chatBefore(x)
    const fresh = crypto.randomUUID()
    fs.writeFileSync(x.transcript(fresh), CLEAR_ENTRIES +
      line({ type: 'user', isMeta: true, message: { role: 'user', content: '<channel source="world-bridge" sender="user">\nafter\n</channel>' } }))
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: '<channel source="world-bridge" sender="user">\nafter\n</channel>' }, fresh)
    assert.equal((await x.c.next('session.updated')).native_id, fresh)
    assert.deepEqual((await x.c.next(notice('conversation_cleared'))).notice, CONVERSATION_CLEARED)
    assert.equal((await x.c.next('message.completed')).text, 'after')
    assert.deepEqual(await historyTexts(x), ['after'])
  } finally { await x.close() }
})

test('a hook naming a transcript in another folder is ignored', async () => {
  const x = await liveSession()
  try {
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'first' })
    await x.c.next('message.completed')
    await x.c.next('agent.state_changed')
    // The user's message starts a turn (C08).
    assert.equal(((await x.c.next('usage.updated')).usage as Usage).turn.message, 'p1')
    const other = crypto.randomUUID()
    const elsewhere = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'elsewhere-')), `${other}.jsonl`)
    const r = await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'stray', transcript_path: elsewhere }, other)
    assert.deepEqual(r, { status: 200, body: '' })
    assert.deepEqual((await x.c.quiet()).map((m) => m.type), [])
    assert.ok(x.log.lines.some((l) => /another project's conversation/.test(l)))
  } finally { await x.close() }
})

test('a moved conversation: a notice; its hooks are ignored; world messages get a clear error', async () => {
  const x = await liveSession()
  try {
    // A prompt waiting in the world when the conversation moves.
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'before' })
    await x.send('PreToolUse', { tool_name: 'Bash', tool_input: { command: 'ls' }, tool_use_id: 'toolu_1' })
    x.toBridge({ type: 'permission_request', request_id: 'abcde', tool_name: 'Bash', description: 'ls', input_preview: '{"command":"ls"}' })
    await x.c.next('permission.requested')

    // Agent view (turned off, but just in case): continued-in in the
    // followed transcript, then the new session's hooks. Its first hook may
    // beat the next poll: it's still recognised.
    const moved = crypto.randomUUID()
    fs.appendFileSync(x.transcript(x.nativeId), JSON.stringify({ type: 'continued-in', sessionId: x.nativeId, continuedInSessionId: moved }) + '\n')
    assert.deepEqual(await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'elsewhere' }, moved), { status: 200, body: '' })
    assert.deepEqual((await x.c.next(notice('conversation_moved'))).notice, CONVERSATION_MOVED)
    await new Promise((r) => setTimeout(r, POLL_MS * 2))
    assert.deepEqual((await x.c.quiet()).map((m) => m.type), [], 'no session.updated, no message from the moved conversation')

    // The old bridge is still connected, but sending to it would be lost.
    const sent = x.fromSidecar.length
    for (const cmd of [
      { type: 'message.send', session: x.id, text: 'hello?' },
      { type: 'permission.respond', session: x.id, permission: 'abcde', decision: 'allow' },
      { type: 'interrupt.request', session: x.id },
    ]) {
      const r = await x.c.command(cmd)
      assert.equal(r.type, 'error', cmd.type)
      assert.equal(r.code, 'provider_error')
      assert.equal(r.message, MOVED_ERROR)
      assert.equal(r.reason, 'conversation_moved')
    }
    assert.equal(x.fromSidecar.length, sent, 'nothing went down the old bridge')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

// (A prompt needs the bridge to reach the world, so permission.respond
// without one is covered by the moved case and the reachable() check.)
test('no live bridge: message.send says so', async () => {
  const x = await liveSession({ bridge: false })
  try {
    for (const cmd of [
      { type: 'message.send', session: x.id, text: 'hello?' },
    ]) {
      const r = await x.c.command(cmd)
      assert.equal(r.type, 'error', cmd.type)
      assert.equal(r.message, UNREACHABLE_ERROR)
      assert.equal(r.reason, 'unreachable')
    }
  } finally { await x.close() }
})

test('schema: session.updated carries at least one field', () => {
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, native_id: 'n' }).ok, true)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2 }).ok, false)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, native_id: '' }).ok, false)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, title: 'x' }).ok, true)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, title: null }).ok, true)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, title: 5 }).ok, false)
})
