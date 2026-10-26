// The packaged bundle (scripts/build.ts) runs every mode: main.ts loads each
// mode's code with a dynamic import, which esbuild must keep inside the one
// file (NOTES.md -> S01 -> Process). Built to a temporary folder, run as
// the executable would be: the relay exits 0 with nothing on stdout, the
// bridge answers MCP's initialize, serve prints its ready line.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { build } from 'esbuild'
import { BUNDLE_OPTIONS } from '../scripts/build.ts'
import { tempSessionsDir } from './helpers.ts'
import { TEST_SESSIONS_DIR } from '../src/launch/app-data.ts'

/** Runs the bundle in a mode until `done` says so from its stdout, or it exits. */
function run(bundle: string, args: string[], stdin: string, done: (out: string) => boolean = () => false) {
  const child = spawn(process.execPath, [bundle, ...args], {
    shell: false, stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, [TEST_SESSIONS_DIR]: tempSessionsDir(), BRIDGE_FILE: path.join(os.tmpdir(), 'no-such-bridge-file.json') },
  })
  let out = ''
  child.stdout.setEncoding('utf8').on('data', (d) => { out += d; if (done(out)) child.kill() })
  child.stderr.resume()
  child.stdin.write(stdin)
  return new Promise<{ code: number | null; out: string }>((resolve) => child.on('close', (code) => resolve({ code, out })))
}

test('the bundle is one file that runs every mode', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bundle-'))
  const bundle = path.join(dir, 'sidecar.cjs')
  await build({ ...BUNDLE_OPTIONS, outfile: bundle, logLevel: 'silent' })
  assert.deepEqual(fs.readdirSync(dir), ['sidecar.cjs'], 'one file')
  assert.doesNotMatch(fs.readFileSync(bundle, 'utf8'), /\bimport\(|require\("\.\.?\//, 'every import inside it')

  const relay = await run(bundle, ['relay', path.join(dir, 'no-such-relay-file.json')], '{}')
  assert.equal(relay.code, 0, 'relay: exits 0')
  assert.equal(relay.out, '', 'relay: nothing on stdout')

  const init = { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'test', version: '1' } } }
  const bridge = await run(bundle, ['bridge', 'claude'], JSON.stringify(init) + '\n', (out) => out.includes('\n'))
  assert.equal(JSON.parse(bridge.out.split('\n')[0]!).id, 1, 'bridge: answers initialize')

  const serve = await run(bundle, ['serve', '--no-outside-sessions'], '', (out) => out.includes('\n'))
  assert.equal(JSON.parse(serve.out.split('\n')[0]!).type, 'ready', 'serve: its ready line')
})
