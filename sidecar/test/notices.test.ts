// Session notices (NOTES.md -> S02 -> When transcripts are off): a core
// event with a code and an English fallback, kept in the snapshot, one per
// code. The Claude provider raises transcripts_off.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { Registry } from '../src/registry.ts'
import { checkMessage } from '../src/protocol.ts'
import { ClaudeProvider, TRANSCRIPT_CHECK_MS, TRANSCRIPTS_OFF } from '../src/providers/claude/index.ts'
import { SIGN_IN_NEEDED } from '../src/providers/claude/hooks.ts'
import { connect, RecordingLog, testServer, tempSessionsDir, bridgeOf } from './helpers.ts'
import type { Provider } from '../src/provider.ts'

test('registry: a notice is sent and kept; the same code replaces it; a repeat is dropped', () => {
  const sent: any[] = []
  const log = new RecordingLog()
  const reg = new Registry([], log)
  reg.setSink((m) => sent.push(m))
  const e = reg.open({ id: 'x' } as Provider)
  reg.release(e)
  e.host.announce({
    native_id: null, project: { path: '/p' }, title: null, capabilities: {}, extensions: [],
    agents: [{ agent: 'main', role: 'orchestrator', parent: null, state: 'idle', reason: null }],
  })
  assert.deepEqual(sent[0].session.notices, [])
  assert.equal(e.host.emit({ type: 'session.notice', notice: { code: 'transcripts_off', message: 'a' } }), true)
  assert.equal(e.host.emit({ type: 'session.notice', notice: { code: 'transcripts_off', message: 'a' } }), false)
  assert.equal(e.host.emit({ type: 'session.notice', notice: { code: 'transcripts_off', message: 'b' } }), true)
  assert.equal(e.host.emit({ type: 'session.notice', notice: { code: 'Bad Code', message: 'x' } }), false, 'schema: code pattern')
  assert.deepEqual(reg.snapshot(e.id)!.notices, [{ code: 'transcripts_off', message: 'b' }])
  assert.deepEqual(sent.slice(1).map((m) => [m.type, m.seq, m.notice.message]), [['session.notice', 2, 'a'], ['session.notice', 3, 'b']])
  for (const m of sent) assert.equal(checkMessage(m).ok, true)
})

async function session() {
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'n-')) } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.Stop[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  const sock = net.connect(bridgeOf(env).port, '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: bridgeOf(env).token }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
  await c.next('session.created')
  const send = (body: object) => new Promise<void>((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: Number(new URL(h.url).port), method: 'POST', path: '/hook',
      headers: { authorization: h.headers.Authorization } }, (res) => { res.resume(); res.on('end', resolve) })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
  return { c, id, send, close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() } }
}

test('through a session: no transcript file after the first reply → transcripts_off, in events and snapshot', async () => {
  const x = await session()
  try {
    const missing = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'n-')), 'none.jsonl')
    await x.send({ hook_event_name: 'UserPromptSubmit', prompt: 'hi', transcript_path: missing })
    await x.send({ hook_event_name: 'Stop', transcript_path: missing })
    const n = await x.c.next('session.notice', TRANSCRIPT_CHECK_MS + 2000)
    assert.deepEqual(n.notice, TRANSCRIPTS_OFF)
    await x.c.command({ type: 'session.get_snapshot', session: x.id })
    assert.deepEqual(((await x.c.next('session.snapshot')).session as any).notices, [TRANSCRIPTS_OFF])
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: a transcript being written means no notice', async () => {
  const x = await session()
  try {
    const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'n-')), 'there.jsonl')
    fs.writeFileSync(file, '{}\n')
    await x.send({ hook_event_name: 'UserPromptSubmit', prompt: 'hi', transcript_path: file })
    await x.send({ hook_event_name: 'Stop', transcript_path: file })
    await new Promise((res) => setTimeout(res, TRANSCRIPT_CHECK_MS + 300))
    assert.ok(!x.c.received.some((m) => m.type === 'session.notice'))
  } finally { await x.close() }
})

async function hooklessSession() {
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
    hooksCheckMs: 300,
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: os.tmpdir() } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.UserPromptSubmit[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  const sock = net.connect(bridgeOf(env).port, '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: bridgeOf(env).token }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
  await c.next('session.created')
  const hook = (body: object) => new Promise<void>((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: Number(new URL(h.url).port), method: 'POST', path: '/hook',
      headers: { authorization: h.headers.Authorization } }, (res) => { res.resume(); res.on('end', resolve) })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
  return { c, id, hook, close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() } }
}

test('through a session: no hook after a world message sent while idle → hooks_unavailable, once', async () => {
  const x = await hooklessSession()
  try {
    await x.c.command({ type: 'message.send', session: x.id, text: 'hello?' })
    const n = await x.c.next('session.notice', 3000)
    assert.equal((n.notice as any).code, 'hooks_unavailable')
    await x.c.command({ type: 'message.send', session: x.id, text: 'again' })
    await new Promise((res) => setTimeout(res, 600))
    assert.ok(!x.c.received.some((m) => m.type === 'session.notice'), 'only once')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: hooks arriving means no hooks_unavailable notice', async () => {
  const x = await hooklessSession()
  try {
    await x.c.command({ type: 'message.send', session: x.id, text: 'hello' })
    await x.hook({ hook_event_name: 'UserPromptSubmit', prompt: '<channel source="world-bridge" sender="user">\nhello\n</channel>' })
    await new Promise((res) => setTimeout(res, 600))
    assert.ok(!x.c.received.some((m) => m.type === 'session.notice'))
  } finally { await x.close() }
})

test('registry: a cleared notice leaves the snapshot; clearing one that isn\'t there sends nothing', () => {
  const sent: any[] = []
  const reg = new Registry([], new RecordingLog())
  reg.setSink((m) => sent.push(m))
  const e = reg.open({ id: 'x' } as Provider)
  reg.release(e)
  e.host.announce({
    native_id: null, project: { path: '/p' }, title: null, capabilities: {}, extensions: [],
    agents: [{ agent: 'main', role: 'orchestrator', parent: null, state: 'idle', reason: null }],
  })
  assert.equal(e.host.emit({ type: 'session.notice_cleared', code: 'sign_in_needed' }), false)
  e.host.emit({ type: 'session.notice', notice: { code: 'transcripts_off', message: 'a' } })
  e.host.emit({ type: 'session.notice', notice: { code: 'sign_in_needed', message: 'b' } })
  assert.equal(e.host.emit({ type: 'session.notice_cleared', code: 'sign_in_needed' }), true)
  assert.equal(e.host.emit({ type: 'session.notice_cleared', code: 'sign_in_needed' }), false, 'once')
  assert.deepEqual(reg.snapshot(e.id)!.notices, [{ code: 'transcripts_off', message: 'a' }])
  assert.deepEqual(sent.at(-1), { type: 'session.notice_cleared', session: e.id, seq: 4, code: 'sign_in_needed' })
  for (const m of sent) assert.equal(checkMessage(m).ok, true)
  assert.equal(checkMessage({ type: 'session.notice_cleared', session: e.id, seq: 5, code: 'Bad Code' }).ok, false, 'schema: code pattern')
})

test('through a session: a turn failing on the account → sign_in_needed and waiting; signing in clears both', async () => {
  const x = await session()
  try {
    await x.send({ hook_event_name: 'UserPromptSubmit', prompt: 'hi' })
    // As recorded live (2.1.294): `error`, the rendered text in last_assistant_message.
    await x.send({ hook_event_name: 'StopFailure', error: 'authentication_failed', last_assistant_message: 'Failed to authenticate. API Error: 401' })
    const n = (await x.c.next('session.notice')).notice as { code: string; message: string }
    assert.equal(n.code, SIGN_IN_NEEDED)
    assert.match(n.message, /\/login in its terminal/)
    const w = await x.c.next((m) => m.type === 'agent.state_changed' && m.state === 'waiting')
    assert.equal(w.reason, 'sign_in')
    await x.c.command({ type: 'session.get_snapshot', session: x.id })
    const snap = (await x.c.next('session.snapshot')).session as any
    assert.deepEqual(snap.notices.map((m: any) => m.code), [SIGN_IN_NEEDED])
    assert.deepEqual([snap.agents[0].state, snap.agents[0].reason], ['waiting', 'sign_in'])
    await x.send({ hook_event_name: 'Notification', notification_type: 'auth_success', message: 'Signed in' })
    assert.equal((await x.c.next('session.notice_cleared')).code, SIGN_IN_NEEDED)
    assert.equal((await x.c.next((m) => m.type === 'agent.state_changed' && m.state === 'idle')).reason, null)
    await x.c.command({ type: 'session.get_snapshot', session: x.id })
    assert.deepEqual(((await x.c.next('session.snapshot')).session as any).notices, [])
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})
