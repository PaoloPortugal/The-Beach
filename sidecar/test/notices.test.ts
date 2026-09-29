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
import { connect, RecordingLog, testServer } from './helpers.ts'
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
  const p = new ClaudeProvider({
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
  const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
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
  const p = new ClaudeProvider({
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
  const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
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
