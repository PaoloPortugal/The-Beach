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
import { CONVERSATION_CLEARED, CONVERSATION_MOVED, MOVED_ERROR, UNREACHABLE_ERROR } from '../src/providers/claude/session.ts'
import { POLL_MS } from '../src/providers/claude/transcript.ts'
import { checkMessage } from '../src/protocol.ts'
import { connect, RecordingLog, testServer, type Msg } from './helpers.ts'

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
 * unconnected (the session comes up through its first hook).
 */
async function liveSession(o: { bridge?: boolean } = {}) {
  let launch: { args: string[] } = { args: [] }
  const log = new RecordingLog()
  const p = new ClaudeProvider({
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
    sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
    await new Promise((res) => sock!.once('connect', res))
    sock.setEncoding('utf8').on('data', (d: string) => fromSidecar.push(...d.trim().split('\n').map((l) => JSON.parse(l))))
    sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n')
    sock.write(JSON.stringify({ type: 'ready' }) + '\n')
  }
  /** One hook from conversation `sid` (default: the launched one), as Claude Code sends it. */
  const send = (name: string, fields: Record<string, unknown> = {}, sid = nativeId) => post(port, h.headers.Authorization, {
    session_id: sid, transcript_path: transcript(sid), cwd: '/', hook_event_name: name, ...fields,
  })
  if (o.bridge === false) await send('Stop')
  const created = await c.next('session.created')
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

test('a hook naming a transcript in another folder is ignored', async () => {
  const x = await liveSession()
  try {
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'first' })
    await x.c.next('message.completed')
    await x.c.next('agent.state_changed')
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
    }
  } finally { await x.close() }
})

test('schema: session.updated carries at least one field', () => {
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, native_id: 'n' }).ok, true)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2 }).ok, false)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, native_id: '' }).ok, false)
  assert.equal(checkMessage({ type: 'session.updated', session: 's', seq: 2, title: 'x' }).ok, false)
})
