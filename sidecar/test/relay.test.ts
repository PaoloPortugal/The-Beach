// The relay mode (NOTES.md -> S02 -> Following the conversation): Claude
// Code runs it as SessionStart's command hook in exec form (no shell), and
// it posts the hook to our hook server. It must never block Claude Code:
// always exit 0, quickly, and print nothing (SessionStart's stdout becomes
// Claude's context).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import { PassThrough } from 'node:stream'
import { fileURLToPath } from 'node:url'
import { HookServer, type HookPayload } from '../src/providers/claude/hook-server.ts'
import { readRelayFile, runRelay, writeRelayFile, RELAY_TIMEOUT_MS } from '../src/launch/relay.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import type { ClaudeSession } from '../src/providers/claude/session.ts'
import { RecordingLog } from './helpers.ts'

const MAIN = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'src', 'main.ts')
const TOKEN = 'b'.repeat(64)

/** A folder whose name a shell would trip over. */
function awkwardDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'relay a&b $(x) `y` \'q\' -'))
}

/** Runs `node main.ts relay <args>` as Claude Code's exec form does: an argv, no shell. */
function runMode(args: string[], stdin: string | null, env: NodeJS.ProcessEnv = process.env) {
  const child = spawn(process.execPath, [MAIN, 'relay', ...args], { shell: false, env, stdio: ['pipe', 'pipe', 'pipe'] })
  let out = '', err = ''
  child.stdout.setEncoding('utf8').on('data', (d) => { out += d })
  child.stderr.setEncoding('utf8').on('data', (d) => { err += d })
  if (stdin !== null) child.stdin.end(stdin)
  const started = Date.now()
  return new Promise<{ code: number | null; out: string; err: string; ms: number }>((resolve) => {
    child.on('close', (code) => resolve({ code, out, err, ms: Date.now() - started }))
  })
}

async function hookServer(onHook: (p: HookPayload) => unknown = () => undefined) {
  const server = new HookServer(new RecordingLog())
  await server.start()
  const got: HookPayload[] = []
  const link = server.register({ onHook: (p) => { got.push(p); return onHook(p) as void } })
  return { server, link, got }
}

const START = { session_id: '11111111-2222-4333-8444-555555555555', transcript_path: '/t.jsonl', hook_event_name: 'SessionStart', source: 'clear' }

test('relay file: written for this user only; only loopback HTTP and a real token are accepted', () => {
  const dir = awkwardDir()
  const file = path.join(dir, 'relay.json')
  writeRelayFile(file, { url: 'http://127.0.0.1:5/hook', token: TOKEN })
  if (process.platform !== 'win32') assert.equal(fs.statSync(file).mode & 0o777, 0o600)
  assert.deepEqual(readRelayFile(file), { version: 1, url: 'http://127.0.0.1:5/hook', token: TOKEN })
  for (const bad of [
    { version: 1, url: 'http://example.com:5/hook', token: TOKEN },
    { version: 1, url: 'http://0.0.0.0:5/hook', token: TOKEN },
    { version: 1, url: 'https://127.0.0.1:5/hook', token: TOKEN },
    { version: 1, url: 'http://127.0.0.1/hook', token: TOKEN },
    { version: 1, url: 'http://127.0.0.1:5/hook', token: 'short' },
    { version: 2, url: 'http://127.0.0.1:5/hook', token: TOKEN },
  ]) {
    fs.writeFileSync(file, JSON.stringify(bad))
    assert.equal(readRelayFile(file), null, JSON.stringify(bad))
  }
  assert.equal(readRelayFile(path.join(dir, 'missing.json')), null)
})

test('relay: forwards the hook as it came, with the session\'s token', async () => {
  const h = await hookServer()
  try {
    const file = path.join(awkwardDir(), 'relay.json')
    writeRelayFile(file, { url: h.server.url, token: h.link.token })
    const input = new PassThrough()
    const logged: string[] = []
    const done = runRelay([file], input, (m) => logged.push(m))
    input.end(JSON.stringify(START))
    await done
    assert.deepEqual(h.got, [START])
    assert.deepEqual(logged, [])
  } finally { await h.server.close() }
})

test('relay mode, spawned with an argv and no shell (as Claude Code\'s exec form): posts, prints nothing, exits 0', async () => {
  const h = await hookServer(() => ({ hookSpecificOutput: { additionalContext: 'never shown to Claude' } }))
  try {
    const file = path.join(awkwardDir(), 'relay.json')
    writeRelayFile(file, { url: h.server.url, token: h.link.token })
    const r = await runMode([file], JSON.stringify(START))
    assert.equal(r.code, 0)
    assert.equal(r.out, '', 'nothing on stdout: it would become Claude\'s context')
    assert.equal(r.err, '')
    assert.deepEqual(h.got, [START])
  } finally { await h.server.close() }
})

test('relay mode: every failure still exits 0 with nothing on stdout, and quickly', async () => {
  const dir = awkwardDir()
  // Nothing listening: a port that was just freed.
  const gone = await hookServer()
  const closedUrl = gone.server.url
  await gone.server.close()
  const closed = path.join(dir, 'closed.json')
  writeRelayFile(closed, { url: closedUrl, token: TOKEN })
  // A wrong token: refused with 401.
  const h = await hookServer()
  const wrong = path.join(dir, 'wrong.json')
  writeRelayFile(wrong, { url: h.server.url, token: TOKEN })
  // A server that never answers.
  const hung = http.createServer(() => {})
  await new Promise<void>((r) => hung.listen(0, '127.0.0.1', () => r()))
  const hanging = path.join(dir, 'hanging.json')
  writeRelayFile(hanging, { url: `http://127.0.0.1:${(hung.address() as { port: number }).port}/hook`, token: TOKEN })
  try {
    const cases: [string, string[], string | null][] = [
      ['no server', [closed], JSON.stringify(START)],
      ['wrong token', [wrong], JSON.stringify(START)],
      ['hanging server', [hanging], JSON.stringify(START)],
      ['stdin never closed', [closed], null],
      ['missing relay file', [path.join(dir, 'missing.json')], JSON.stringify(START)],
      ['no arguments', [], JSON.stringify(START)],
      ['too many arguments', [closed, 'x'], JSON.stringify(START)],
    ]
    const results = await Promise.all(cases.map(([, args, stdin]) => runMode(args, stdin)))
    cases.forEach(([why], i) => {
      const r = results[i]!
      assert.equal(r.code, 0, why)
      assert.equal(r.out, '', why)
      assert.ok(r.ms < RELAY_TIMEOUT_MS + 3000, `${why}: took ${r.ms} ms`)
      assert.ok(!r.err.includes(TOKEN), `${why}: the token isn't logged`)
    })
    assert.deepEqual(h.got, [], 'a wrong token reaches no session')
  } finally {
    await h.server.close()
    hung.closeAllConnections()
    await new Promise<void>((r) => hung.close(() => r()))
  }
})

test('a launched session\'s SessionStart runs this executable in relay mode with its relay file', async () => {
  let argv: string[] = []
  let launch: { args: string[] } = { args: [] }
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.285' }),
    selfCommand: (mode, ...args) => ['/sidecar', mode, ...args],
    openTerminal: async (req) => { argv = req.argv; launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
    projectsDir: fs.mkdtempSync(path.join(os.tmpdir(), 'projects-')),
  })
  const host = { id: 's1', ended: false, emit: () => true, announce() {}, end() {} } as any
  const session = await p.create(host, { project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'proj-')) } })
  try {
    assert.equal(argv[1], 'launch')
    const settings = JSON.parse(fs.readFileSync(launch.args[launch.args.indexOf('--settings') + 1]!, 'utf8'))
    const hook = settings.hooks.SessionStart[0].hooks[0]
    assert.equal(hook.command, '/sidecar')
    assert.equal(hook.args[0], 'relay')
    assert.equal(hook.args.length, 2)
    const relay = readRelayFile(hook.args[1])
    assert.ok(relay, 'the relay file is there and valid')
    assert.equal(relay.url, settings.hooks.Stop[0].hooks[0].url)
    assert.equal(`Bearer ${relay.token}`, settings.hooks.Stop[0].hooks[0].headers.Authorization)
    assert.equal(path.dirname(hook.args[1]), path.dirname(argv[2]!), 'in the session\'s private run folder')
  } finally { (session as ClaudeSession).dispose(); await p.shutdown() }
})
