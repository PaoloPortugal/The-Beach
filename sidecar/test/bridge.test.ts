// The channel bridge: its MCP answers, the real bridge process against a
// stand-in for Claude Code, the sidecar's bridge server, and a session's
// life from launch to exit.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { answerMcp, BRIDGE_RETRY_MS, BRIDGE_SERVER_NAME, MCP_VERSIONS, readBridgeFile, writeBridgeFile } from '../src/providers/claude/bridge.ts'
import { BridgeServer, HELLO_TIMEOUT_MS } from '../src/providers/claude/bridge-server.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { connect, RecordingLog, testServer, tempSessionsDir, bridgeOf } from './helpers.ts'

const main = path.join(import.meta.dirname, '..', 'src', 'main.ts')

// ---- MCP answers ----

test('initialize: echoes a version we know, else offers our newest; declares the channel', () => {
  const r = answerMcp({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } })!
  const result = r.result as Record<string, any>
  assert.equal(result.protocolVersion, '2025-06-18')
  assert.deepEqual(result.capabilities, { experimental: { 'claude/channel': {}, 'claude/channel/permission': {} } })
  assert.equal(result.serverInfo.name, BRIDGE_SERVER_NAME)
  assert.match(result.instructions, /same user/)
  const r2 = answerMcp({ jsonrpc: '2.0', id: 2, method: 'initialize', params: { protocolVersion: '2099-01-01' } })!
  assert.equal((r2.result as any).protocolVersion, MCP_VERSIONS[0])
})

test('ping answers; anything else (incl. the newer server/discover probe) is method-not-found', () => {
  assert.deepEqual(answerMcp({ jsonrpc: '2.0', id: 'p', method: 'ping' }), { jsonrpc: '2.0', id: 'p', result: {} })
  for (const method of ['server/discover', 'tools/list', 'tools/call']) {
    assert.equal((answerMcp({ jsonrpc: '2.0', id: 3, method })!.error as any).code, -32601, method)
  }
  // Notifications get no reply.
  assert.equal(answerMcp({ jsonrpc: '2.0', method: 'notifications/initialized' }), null)
})

// ---- the bridge process, driven like Claude Code drives it ----

function startBridge(env: Record<string, string>) {
  const child = spawn(process.execPath, [main, 'bridge', 'claude'], {
    stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, ...env },
  })
  const out: Record<string, any>[] = []
  let buf = ''
  let stdoutRaw = ''
  child.stdout.setEncoding('utf8').on('data', (d: string) => {
    stdoutRaw += d
    buf += d
    let i
    while ((i = buf.indexOf('\n')) >= 0) { out.push(JSON.parse(buf.slice(0, i))); buf = buf.slice(i + 1) }
  })
  const exited = new Promise<number | null>((r) => child.once('exit', r))
  const send = (m: unknown) => child.stdin.write(JSON.stringify(m) + '\n')
  const waitFor = async (pred: (m: any) => boolean, ms = 5000) => {
    const end = Date.now() + ms
    while (Date.now() < end) {
      const m = out.find(pred)
      if (m) return m
      await new Promise((r) => setTimeout(r, 20))
    }
    throw new Error(`bridge never sent it; got ${JSON.stringify(out)}`)
  }
  return { child, send, out, waitFor, exited, stdoutRaw: () => stdoutRaw }
}

/** A bridge file in a folder of its own, as a run folder holds it. */
function bridgeFile(port: number, token: string): string {
  const file = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'bridge-')), 'bridge.json')
  writeBridgeFile(file, port, token)
  return file
}

const until = async (cond: () => boolean, ms = 2000) => {
  for (const end = Date.now() + ms; !cond() && Date.now() < end;) await new Promise((r) => setTimeout(r, 20))
}

test('the bridge file: written owner-only, read back, anything else refused', () => {
  const token = 'a'.repeat(64)
  const file = bridgeFile(4321, token)
  if (process.platform !== 'win32') assert.equal(fs.statSync(file).mode & 0o777, 0o600)
  assert.deepEqual(readBridgeFile(file), { port: 4321, token })
  for (const bad of [
    { version: 2, port: 4321, token }, { version: 1, port: 0, token }, { version: 1, port: 70000, token },
    { version: 1, port: '4321', token }, { version: 1, port: 4321, token: 'short' }, [],
  ]) {
    fs.writeFileSync(file, JSON.stringify(bad))
    assert.equal(readBridgeFile(file), null, JSON.stringify(bad))
  }
  fs.writeFileSync(file, '{ not json')
  assert.equal(readBridgeFile(file), null)
  assert.equal(readBridgeFile(path.join(path.dirname(file), 'missing.json')), null)
})

test('the bridge process: handshake, connects after initialized, relays both ways, exits with stdin', async () => {
  const events: string[] = []
  const permissions: unknown[] = []
  const server = new BridgeServer(new RecordingLog())
  const port = await server.start()
  const link = server.register({
    onReady: () => events.push('ready'),
    onPermissionRequest: (p) => permissions.push(p),
    onClose: () => events.push('close'),
  })
  const b = startBridge({ BRIDGE_FILE: bridgeFile(port, link.token) })
  try {
    b.send({ jsonrpc: '2.0', id: 0, method: 'server/discover', params: {} })
    assert.equal((await b.waitFor((m) => m.id === 0)).error.code, -32601)
    b.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'test' } } })
    await b.waitFor((m) => m.id === 1)
    await new Promise((r) => setTimeout(r, 200))
    assert.equal(events.length, 0, 'no connection before initialized')
    b.send({ jsonrpc: '2.0', method: 'notifications/initialized' })
    for (let i = 0; i < 100 && !events.includes('ready'); i++) await new Promise((r) => setTimeout(r, 20))
    assert.deepEqual(events, ['ready'])

    // World chat reaches Claude Code as a channel event.
    assert.ok(link.send({ type: 'chat', text: 'hello\nthere' }))
    const chat = await b.waitFor((m) => m.method === 'notifications/claude/channel')
    assert.deepEqual(chat.params, { content: 'hello\nthere', meta: { sender: 'user' } })

    // A permission prompt reaches the sidecar; a verdict goes back.
    b.send({ jsonrpc: '2.0', method: 'notifications/claude/channel/permission_request',
      params: { request_id: 'abcde', tool_name: 'Bash', description: 'List files', input_preview: '{"command":"ls"}' } })
    for (let i = 0; i < 100 && permissions.length === 0; i++) await new Promise((r) => setTimeout(r, 20))
    assert.deepEqual(permissions, [{ request_id: 'abcde', tool_name: 'Bash', description: 'List files', input_preview: '{"command":"ls"}' }])
    link.send({ type: 'verdict', request_id: 'abcde', behavior: 'deny' })
    const verdict = await b.waitFor((m) => m.method === 'notifications/claude/channel/permission')
    assert.deepEqual(verdict.params, { request_id: 'abcde', behavior: 'deny' })

    // Malformed verdicts never reach Claude Code.
    link.send({ type: 'verdict', request_id: 'ABCDE', behavior: 'allow' } as never)
    link.send({ type: 'verdict', request_id: 'abcdl', behavior: 'allow' })
    link.send({ type: 'verdict', request_id: 'abcde', behavior: 'always' } as never)
    await new Promise((r) => setTimeout(r, 200))
    assert.equal(b.out.filter((m) => m.method === 'notifications/claude/channel/permission').length, 1)

    // Claude Code exits: stdin closes, the bridge exits, the sidecar hears it.
    b.child.stdin.end()
    assert.equal(await b.exited, 0)
    for (let i = 0; i < 100 && !events.includes('close'); i++) await new Promise((r) => setTimeout(r, 20))
    assert.deepEqual(events, ['ready', 'close'])
    // stdout held only MCP messages.
    for (const line of b.stdoutRaw().trim().split('\n')) assert.equal(JSON.parse(line).jsonrpc, '2.0')
  } finally {
    b.child.kill()
    await server.close()
  }
})

test('without a sidecar, the bridge still answers MCP (Claude Code keeps working)', async () => {
  for (const env of [{ BRIDGE_FILE: '' }, { BRIDGE_FILE: path.join(os.tmpdir(), 'no-such-folder', 'bridge.json') }]) {
    const b = startBridge(env)
    try {
      b.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } })
      await b.waitFor((m) => m.id === 1)
      b.send({ jsonrpc: '2.0', method: 'notifications/initialized' })
      b.send({ jsonrpc: '2.0', id: 2, method: 'ping' })
      await b.waitFor((m) => m.id === 2)
      b.child.stdin.end()
      assert.equal(await b.exited, 0, 'exits with stdin, retrying or not')
    } finally { b.child.kill() }
  }
})

test('the bridge process reconnects (S07): when the sidecar goes, it retries, and takes the next sidecar\'s fresh token', { timeout: 20_000 }, async () => {
  const events: string[] = []
  const first = new BridgeServer(new RecordingLog())
  const firstLink = first.register({ onReady: () => events.push('ready 1'), onPermissionRequest() {}, onClose: () => events.push('close 1') })
  const file = bridgeFile(await first.start(), firstLink.token)
  const b = startBridge({ BRIDGE_FILE: file })
  const second = new BridgeServer(new RecordingLog())
  try {
    b.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } })
    await b.waitFor((m) => m.id === 1)
    b.send({ jsonrpc: '2.0', method: 'notifications/initialized' })
    await until(() => events.includes('ready 1'))
    assert.deepEqual(events, ['ready 1'])

    // The game quits: the sidecar and its token are gone. The bridge keeps
    // trying, but never offers the spent token again.
    await first.close()
    await new Promise((r) => setTimeout(r, BRIDGE_RETRY_MS + 500))

    // The next sidecar: a new port and a fresh token in the same file.
    const secondLink = second.register({ onReady: () => events.push('ready 2'), onPermissionRequest() {}, onClose: () => events.push('close 2') })
    writeBridgeFile(file, await second.start(), secondLink.token)
    await until(() => events.includes('ready 2'), BRIDGE_RETRY_MS * 2 + 1000)
    assert.deepEqual(events, ['ready 1', 'close 1', 'ready 2'])
    assert.ok(secondLink.send({ type: 'chat', text: 'back' }))
    assert.deepEqual((await b.waitFor((m) => m.method === 'notifications/claude/channel')).params, { content: 'back', meta: { sender: 'user' } })

    b.child.stdin.end()
    assert.equal(await b.exited, 0)
    await until(() => events.includes('close 2'))
    assert.deepEqual(events, ['ready 1', 'close 1', 'ready 2', 'close 2'])
  } finally {
    b.child.kill()
    await second.close()
  }
})

test('the bridge process: a refused token never admits it; a fresh one in the file does', { timeout: 20_000 }, async () => {
  const server = new BridgeServer(new RecordingLog())
  const port = await server.start()
  const events: string[] = []
  const link = server.register({ onReady: () => events.push('ready'), onPermissionRequest() {}, onClose() {} })
  const file = bridgeFile(port, 'f'.repeat(64))
  const b = startBridge({ BRIDGE_FILE: file })
  try {
    b.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } })
    await b.waitFor((m) => m.id === 1)
    b.send({ jsonrpc: '2.0', method: 'notifications/initialized' })
    await new Promise((r) => setTimeout(r, BRIDGE_RETRY_MS * 2 + 500))
    assert.equal(events.length, 0, 'a token the sidecar refused never admits the bridge')
    writeBridgeFile(file, port, link.token)
    await until(() => events.includes('ready'), BRIDGE_RETRY_MS * 2 + 1000)
    assert.deepEqual(events, ['ready'])
  } finally {
    b.child.kill()
    await server.close()
  }
})

/** A stand-in for whatever answers on a port: records what comes, says `lines` to each connection. */
async function squatter(port: number, lines: unknown[]) {
  const got: string[] = []
  let connections = 0
  const server = net.createServer((sock) => {
    connections++
    sock.setEncoding('utf8')
    sock.on('data', (d: string) => got.push(d))
    sock.on('error', () => {})
    for (const l of lines) sock.write(JSON.stringify(l) + '\n')
  })
  await new Promise<void>((r) => server.listen(port, '127.0.0.1', () => r()))
  return { got, connections: () => connections, close: () => new Promise<void>((r) => server.close(() => r())) }
}

/** A port nothing listens on (now). */
async function freePort(): Promise<number> {
  const s = net.createServer()
  await new Promise<void>((r) => s.listen(0, '127.0.0.1', () => r()))
  const port = (s.address() as net.AddressInfo).port
  await new Promise<void>((r) => s.close(() => r()))
  return port
}

test('the bridge process: a token whose try was refused is spent; a program taking that port later is never offered it or trusted', { timeout: 20_000 }, async () => {
  const port = await freePort()
  const file = bridgeFile(port, 'a'.repeat(64))
  const b = startBridge({ BRIDGE_FILE: file })
  let other: Awaited<ReturnType<typeof squatter>> | null = null
  try {
    b.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } })
    await b.waitFor((m) => m.id === 1)
    b.send({ jsonrpc: '2.0', method: 'notifications/initialized' })
    // Its one try is refused (the sidecar that wrote the file is gone).
    await new Promise((r) => setTimeout(r, 500))
    // Another program takes the port and would welcome it, approve and chat.
    other = await squatter(port, [{ type: 'welcome' }, { type: 'verdict', request_id: 'abcde', behavior: 'allow' }, { type: 'chat', text: 'hi' }])
    b.send({ jsonrpc: '2.0', method: 'notifications/claude/channel/permission_request',
      params: { request_id: 'abcde', tool_name: 'Bash', description: 'd', input_preview: '{"command":"rm -rf x"}' } })
    await new Promise((r) => setTimeout(r, BRIDGE_RETRY_MS * 2 + 500))
    assert.equal(other.connections(), 0, 'never connects to it')
    assert.deepEqual(other.got, [], 'never offers the token, a ready or a prompt')
    assert.ok(!b.out.some((m) => typeof m.method === 'string' && m.method.startsWith('notifications/claude/channel')), 'nothing from it reaches Claude Code')
  } finally {
    b.child.kill()
    await other?.close()
  }
})

test('the bridge process: nothing a sidecar sends before its welcome is acted on', { timeout: 20_000 }, async () => {
  const port = await freePort()
  const other = await squatter(port, [{ type: 'verdict', request_id: 'abcde', behavior: 'allow' }, { type: 'welcome' }, { type: 'chat', text: 'hi' }])
  const b = startBridge({ BRIDGE_FILE: bridgeFile(port, 'b'.repeat(64)) })
  try {
    b.send({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-11-25' } })
    await b.waitFor((m) => m.id === 1)
    b.send({ jsonrpc: '2.0', method: 'notifications/initialized' })
    await until(() => other.connections() > 0)
    await new Promise((r) => setTimeout(r, BRIDGE_RETRY_MS + 500))
    assert.equal(other.connections(), 1, 'tried once, never again with that token')
    assert.ok(!other.got.join('').includes('"ready"'), 'no ready: it was never welcomed')
    assert.deepEqual(b.out.filter((m) => typeof m.method === 'string' && m.method.startsWith('notifications/claude/channel')), [], 'neither the verdict nor the chat reaches Claude Code')
  } finally {
    b.child.kill()
    await other.close()
  }
})

// ---- the bridge server ----

function rawClient(port: number) {
  const sock = net.connect({ host: '127.0.0.1', port })
  const closed = new Promise<void>((r) => sock.once('close', () => r()))
  sock.on('error', () => {})
  return { sock, closed, send: (m: unknown) => sock.write(JSON.stringify(m) + '\n') }
}

test('bridge server: refuses wrong, reused and missing tokens', async () => {
  const server = new BridgeServer(new RecordingLog())
  const port = await server.start()
  const ready: string[] = []
  const link = server.register({ onReady: () => ready.push('x'), onPermissionRequest() {}, onClose() {} })
  try {
    const wrong = rawClient(port)
    wrong.send({ type: 'hello', token: '0'.repeat(64) })
    wrong.send({ type: 'ready' })
    await wrong.closed

    const good = rawClient(port)
    let welcome = ''
    good.sock.setEncoding('utf8').on('data', (d: string) => { welcome += d })
    good.send({ type: 'hello', token: link.token })
    good.send({ type: 'ready' })
    for (let i = 0; i < 100 && ready.length === 0; i++) await new Promise((r) => setTimeout(r, 10))
    assert.deepEqual(ready, ['x'])
    assert.equal(welcome, '{"type":"welcome"}\n', 'an accepted token is answered welcome')

    const again = rawClient(port)
    again.send({ type: 'hello', token: link.token })
    again.send({ type: 'ready' })
    await again.closed
    assert.deepEqual(ready, ['x'], 'a token admits one connection, once')

    const junk = rawClient(port)
    junk.sock.write('not json\n')
    await junk.closed
    good.sock.destroy()
  } finally { await server.close() }
})

test('bridge server: a silent connection is dropped after the hello timeout', { timeout: HELLO_TIMEOUT_MS + 5000 }, async () => {
  const server = new BridgeServer(new RecordingLog())
  const port = await server.start()
  try {
    const silent = rawClient(port)
    const t0 = Date.now()
    await silent.closed
    assert.ok(Date.now() - t0 >= HELLO_TIMEOUT_MS - 100)
  } finally { await server.close() }
})

// ---- a session's life through the provider ----

test('a Claude session comes up when its bridge is ready and ends when it closes', async () => {
  const log = new RecordingLog()
  let mcpConfig = ''
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log,
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => {
      const fs = await import('node:fs')
      const launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8'))
      mcpConfig = launch.args[launch.args.indexOf('--mcp-config') + 1]
      return 'fake'
    },
  })
  const s = await testServer([p])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: os.tmpdir() } })
    const id = (r.result as { session: string }).session
    assert.equal((await c.command({ type: 'message.send', session: id, text: 'hi' })).code, 'session_starting')

    // Play the bridge: connect with the token from the MCP config.
    const fs = await import('node:fs')
    const env = JSON.parse(fs.readFileSync(mcpConfig, 'utf8')).mcpServers['world-bridge'].env
    const bridge = rawClient(bridgeOf(env).port)
    const lines: string[] = []
    bridge.sock.setEncoding('utf8').on('data', (d: string) => lines.push(...d.trim().split('\n')))
    bridge.send({ type: 'hello', token: bridgeOf(env).token })
    bridge.send({ type: 'ready' })
    const created = await c.next('session.created')
    const session = created.session as Record<string, any>
    assert.equal(session.session, id)
    assert.equal(session.provider, 'claude')
    assert.match(session.native_id, /^[0-9a-f-]{36}$/)
    assert.deepEqual(session.agents.map((a: any) => [a.agent, a.role, a.state]), [['main', 'orchestrator', 'idle']])
    assert.ok(log.lines.some((l) => /came up \d+ ms after launch/.test(l)))

    // Chat from the world goes down the bridge.
    assert.equal((await c.command({ type: 'message.send', session: id, text: 'hello' })).type, 'ok')
    for (let i = 0; i < 100 && lines.length < 2; i++) await new Promise((r) => setTimeout(r, 10))
    assert.deepEqual(lines.map((l) => JSON.parse(l)), [{ type: 'welcome' }, { type: 'chat', text: 'hello' }])

    // Claude Code exits: the bridge goes, the island sinks, files are removed.
    bridge.sock.destroy()
    const ended = await c.next('session.ended')
    assert.equal(ended.reason, 'exited')
    assert.equal(fs.existsSync(mcpConfig), false)
    assert.deepEqual(c.invalid, [])
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('a Claude session whose launcher exits before it comes up ends at once', async () => {
  // Claude Code exits at a startup prompt (folder trust declined) or its terminal is closed.
  const fs = await import('node:fs')
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => {
      const launcher = spawn(process.execPath, ['-e', 'setTimeout(() => {}, 300)'], { stdio: 'ignore' })
      fs.writeFileSync(path.join(req.runDir, 'launcher.pid'), String(launcher.pid))
      return 'fake'
    },
    startupTimeoutMs: 60_000,
  })
  const s = await testServer([p])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const t0 = Date.now()
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: os.tmpdir() } })
    const ended = await c.next('session.ended', 5000)
    assert.equal(ended.session, (r.result as { session: string }).session)
    assert.equal(ended.reason, 'exited')
    assert.ok(Date.now() - t0 < 5000, 'long before the startup timeout')
    assert.deepEqual(c.invalid, [])
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})

test('a Claude session that never comes up ends after the startup timeout', async () => {
  const p = new ClaudeProvider({ sessionsDir: tempSessionsDir(),
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.284' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async () => 'fake',
    startupTimeoutMs: 300,
  })
  const s = await testServer([p])
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: os.tmpdir() } })
    const ended = await c.next('session.ended', 3000)
    assert.equal(ended.session, (r.result as { session: string }).session)
    assert.equal(ended.reason, 'exited')
    await c.close()
  } finally { await s.close(); await p.shutdown() }
})
