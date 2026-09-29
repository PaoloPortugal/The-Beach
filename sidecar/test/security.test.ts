// NOTES.md -> Security rules, as they apply to the WebSocket server.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import http from 'node:http'
import { connect, rawUpgrade, testServer } from './helpers.ts'
import { tokenMatches } from '../src/server.ts'

test('listens on loopback only', async () => {
  const s = await testServer()
  try {
    // Reaching it through a non-loopback address of this machine must fail.
    const os = await import('node:os')
    const external = Object.values(os.networkInterfaces()).flat()
      .find((a) => a && a.family === 'IPv4' && !a.internal)?.address
    if (external) {
      await assert.rejects(new Promise((resolve, reject) => {
        const req = http.get({ host: external, port: s.port, timeout: 1000 }, resolve)
        req.on('error', reject)
        req.on('timeout', () => req.destroy(new Error('timeout')))
      }))
    }
  } finally { await s.close() }
})

test('accepts the right token', async () => {
  const s = await testServer()
  try {
    const status = await rawUpgrade(s.port, { authorization: `Bearer ${s.token}` })
    assert.equal(status, 101)
  } finally { await s.close() }
})

test('refuses a missing, wrong, or near-miss token', async () => {
  const s = await testServer()
  try {
    const cases: (string | undefined)[] = [
      undefined,
      '',
      `Bearer ${'0'.repeat(64)}`,
      `Bearer ${s.token.slice(0, -1)}`,           // one character short
      `Bearer ${s.token}0`,                       // one character long
      `bearer ${s.token}`,                        // wrong scheme case
      s.token,                                    // no scheme
      `Bearer ${s.token.toUpperCase()}`,
    ]
    for (const authorization of cases) {
      assert.equal(await rawUpgrade(s.port, { authorization }), 401, `authorization: ${authorization}`)
    }
  } finally { await s.close() }
})

test('refuses anything with an Origin header, even with the right token', async () => {
  const s = await testServer()
  try {
    for (const origin of ['https://evil.example', 'http://127.0.0.1', 'null', '']) {
      assert.equal(await rawUpgrade(s.port, { authorization: `Bearer ${s.token}`, origin }), 403, `origin ${origin}`)
    }
  } finally { await s.close() }
})

test('refuses a wrong Host (DNS rebinding)', async () => {
  const s = await testServer()
  try {
    for (const host of [`localhost:${s.port}`, `evil.example:${s.port}`, '127.0.0.1', `127.0.0.1:${s.port + 1}`]) {
      assert.equal(await rawUpgrade(s.port, { authorization: `Bearer ${s.token}`, host }), 403, `host ${host}`)
    }
  } finally { await s.close() }
})

test('refuses other paths and plain HTTP', async () => {
  const s = await testServer()
  try {
    assert.equal(await rawUpgrade(s.port, { authorization: `Bearer ${s.token}` }, { path: '/x' }), 404)
    assert.equal(await rawUpgrade(s.port, { authorization: `Bearer ${s.token}` }, { path: '/?a=1' }), 404)
    const status = await new Promise<number>((resolve, reject) => {
      http.get({ host: '127.0.0.1', port: s.port, path: '/' }, (res) => { res.resume(); resolve(res.statusCode!) })
        .on('error', reject)
    })
    assert.equal(status, 426)
  } finally { await s.close() }
})

test('refused connections leave no trace of the token in the log', async () => {
  const s = await testServer()
  try {
    await rawUpgrade(s.port, { authorization: `Bearer ${s.token.slice(0, -1)}` })
    await rawUpgrade(s.port, { authorization: `Bearer ${s.token}`, origin: 'https://evil.example' })
    assert.ok(s.log.lines.length >= 2)
    for (const line of s.log.lines) assert.ok(!line.includes(s.token.slice(0, 16)), line)
  } finally { await s.close() }
})

test('a message larger than the limit closes the connection', async () => {
  const s = await testServer()
  try {
    const c = await connect(s.port, s.token)
    await c.sync()
    const closed = new Promise<number>((resolve) => c.ws.once('close', (code) => resolve(code)))
    c.send({ type: 'message.send', id: 'x', session: 's', text: 'a'.repeat(5 * 1024 * 1024) })
    assert.equal(await closed, 1009)
  } finally { await s.close() }
})

test('tokenMatches compares exactly', () => {
  assert.equal(tokenMatches('Bearer abc', 'abc'), true)
  assert.equal(tokenMatches('Bearer abd', 'abc'), false)
  assert.equal(tokenMatches('Bearer ab', 'abc'), false)
  assert.equal(tokenMatches(undefined, 'abc'), false)
})
