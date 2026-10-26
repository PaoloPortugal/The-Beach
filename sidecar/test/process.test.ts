// The sidecar as a process, the way Godot runs it: handshake on stdout, logs
// on stderr, and it exits when its stdin pipe closes.
// SIDECAR_CMD (JSON array) runs a built bundle or executable instead of the source.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, type ChildProcess } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { connect, tempSessionsDir } from './helpers.ts'
import { TEST_SESSIONS_DIR } from '../src/launch/app-data.ts'

const here = import.meta.dirname
const command: string[] = process.env.SIDECAR_CMD
  ? JSON.parse(process.env.SIDECAR_CMD)
  : [process.execPath, path.join(here, '..', 'src', 'main.ts')]

/**
 * Each sidecar gets its own sessions folder: none touches the user's
 * (NOTES.md -> S07). And sessions started outside the game are off (S08),
 * so none shows the developer's own running sessions, nor asks `claude`.
 */
function start(args: string[] = ['serve', '--no-outside-sessions'], stdin: 'pipe' | 'ignore' = 'pipe', sessions = tempSessionsDir()) {
  const child = spawn(command[0]!, [...command.slice(1), ...args], {
    stdio: [stdin, 'pipe', 'pipe'], env: { ...process.env, [TEST_SESSIONS_DIR]: sessions },
  })
  let stdout = ''
  let stderr = ''
  child.stdout!.setEncoding('utf8').on('data', (d: string) => { stdout += d })
  child.stderr!.setEncoding('utf8').on('data', (d: string) => { stderr += d })
  const exited = new Promise<number | null>((resolve) => child.once('exit', (code) => resolve(code)))
  const handshake = new Promise<{ type: string; protocol: number; port: number; token: string }>((resolve, reject) => {
    const check = () => {
      const nl = stdout.indexOf('\n')
      if (nl >= 0) resolve(JSON.parse(stdout.slice(0, nl)))
    }
    child.stdout!.on('data', check)
    child.once('exit', () => reject(new Error(`exited before the handshake; stderr: ${stderr}`)))
  })
  handshake.catch(() => {}) // tests that expect an early exit never await it
  return { child, handshake, exited, out: () => stdout, err: () => stderr }
}

function within<T>(p: Promise<T>, ms: number, what: string): Promise<T> {
  return Promise.race([p, new Promise<T>((_, reject) => setTimeout(() => reject(new Error(`${what} took over ${ms} ms`)), ms))])
}

function kill(child: ChildProcess) {
  if (child.exitCode === null) child.kill()
}

test('prints one handshake line, then serves the protocol', async () => {
  const sessions = tempSessionsDir()
  const p = start(undefined, 'pipe', sessions)
  try {
    const hs = await within(p.handshake, 10000, 'handshake')
    assert.ok(fs.existsSync(path.join(sessions, 'hook-port.json')), 'its run folders in the test\'s own folder')
    assert.equal(hs.type, 'ready')
    assert.equal(hs.protocol, 1)
    assert.match(hs.token, /^[0-9a-f]{64}$/)
    const c = await connect(hs.port, hs.token)
    const { hello } = await c.sync()
    assert.equal(hello.protocol, 1)
    await c.close()
    // Nothing but the handshake ever goes to stdout; logs go to stderr.
    assert.equal(p.out(), JSON.stringify(hs) + '\n')
    assert.match(p.err(), /listening on 127\.0\.0\.1:/)
    assert.match(p.err(), /sessions folder: the tests' own/)
    assert.ok(!p.err().includes(hs.token), 'token never logged')
  } finally { kill(p.child) }
})

test('serve --no-outside-sessions (the player turned them off, S08) starts as usual', async () => {
  const p = start(['serve', '--no-outside-sessions'])
  try {
    const hs = await within(p.handshake, 10000, 'handshake')
    const c = await connect(hs.port, hs.token)
    const { hello } = await c.sync()
    assert.equal(hello.protocol, 1)
    await c.close()
  } finally { kill(p.child) }
})

test('each start makes a new token', async () => {
  const a = start()
  const b = start()
  try {
    const [ha, hb] = await within(Promise.all([a.handshake, b.handshake]), 10000, 'handshakes')
    assert.notEqual(ha.token, hb.token)
    assert.notEqual(ha.port, hb.port)
  } finally { kill(a.child); kill(b.child) }
})

test('exits when its stdin pipe closes (Godot quit or crashed)', async () => {
  const p = start()
  try {
    const hs = await within(p.handshake, 10000, 'handshake')
    const c = await connect(hs.port, hs.token)
    await c.sync()
    p.child.stdin!.end()
    assert.equal(await within(p.exited, 5000, 'exit'), 0)
  } finally { kill(p.child) }
})

test('exits at once when started without a stdin pipe', async () => {
  const p = start(undefined, 'ignore')
  try {
    await within(p.exited, 10000, 'exit')
  } finally { kill(p.child) }
})

test('refuses unknown modes and arguments', async () => {
  for (const args of [['bogus'], ['serve', 'extra'], ['serve', '--no-outside-sessions', 'extra']]) {
    const p = start(args)
    try {
      assert.equal(await within(p.exited, 10000, 'exit'), 1)
      assert.equal(p.out(), '')
    } finally { kill(p.child) }
  }
})
