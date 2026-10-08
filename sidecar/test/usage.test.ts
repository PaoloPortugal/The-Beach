// C08 token usage (NOTES.md -> C08): counting from the transcript, the
// status line's figures, the status line relay, and the one command
// string we hand a shell (Security rules -> No shell strings, the one
// exception), run here in the real shells with hostile paths.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import crypto from 'node:crypto'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { callUsageIn, statusFiguresIn, UsageCounter } from '../src/providers/claude/usage.ts'
import { readConversation } from '../src/providers/claude/store.ts'
import { shellCommand, shortNameGuesses, shortPath } from '../src/launch/shell-command.ts'
import { ourStatusLine, statusLineSettingsFiles, userStatusLine } from '../src/providers/claude/statusline.ts'
import { HookServer, STATUS_PATH } from '../src/providers/claude/hook-server.ts'
import { writeRelayFile } from '../src/launch/relay.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { checkMessage, type Usage } from '../src/protocol.ts'
import { connect, RecordingLog, testServer, type Msg } from './helpers.ts'

const MAIN = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'src', 'main.ts')
const tmp = (prefix: string) => fs.mkdtempSync(path.join(os.tmpdir(), prefix))

/** One API call as Claude Code writes it: an entry per content block, each with the same usage. */
function call(id: string, u: { input?: number; output?: number; read?: number; write?: number }, extra: object = {}) {
  return {
    type: 'assistant', uuid: crypto.randomUUID(), timestamp: '2026-10-08T10:00:00Z', ...extra,
    message: {
      id, role: 'assistant', model: 'claude-sonnet-5-5', content: [{ type: 'text', text: `reply ${id}` }],
      usage: {
        input_tokens: u.input ?? 0, output_tokens: u.output ?? 0,
        cache_read_input_tokens: u.read ?? 0, cache_creation_input_tokens: u.write ?? 0,
        output_tokens_details: { thinking_tokens: 0 },
      },
    },
  }
}
const said = (text: string, uuid: string = crypto.randomUUID()) =>
  ({ type: 'user', uuid, timestamp: '2026-10-08T10:00:00Z', message: { role: 'user', content: text } })
const line = (e: object) => JSON.stringify(e) + '\n'
const STATUS = (sid: string, extra: object = {}) => ({
  session_id: sid, transcript_path: '/t.jsonl', cwd: '/', model: { id: 'm', display_name: 'M' },
  cost: { total_cost_usd: 1.23 },
  context_window: {
    context_window_size: 200000, used_percentage: 12,
    current_usage: { input_tokens: 4000, output_tokens: 900, cache_creation_input_tokens: 1000, cache_read_input_tokens: 19000 },
  },
  rate_limits: {
    five_hour: { used_percentage: 23.5, resets_at: 1791000000 },
    seven_day: { used_percentage: 41.2, resets_at: 1791500000 },
    spend_limit: { used_percentage: 5, resets_at: 1791500000, used_usd: 10, limit_usd: 200, period: 'monthly' },
  },
  ...extra,
})

// ---- counting ----

test('callUsageIn: an assistant entry of the main conversation; subagents, other entries and odd figures left out', () => {
  assert.deepEqual(callUsageIn(call('m1', { input: 3, output: 5, read: 7, write: 11 })),
    { id: 'm1', input: 3, output: 5, cacheRead: 7, cacheWrite: 11 })
  assert.equal(callUsageIn(call('m1', { output: 5 }, { isSidechain: true })), null, 'a subagent\'s')
  assert.equal(callUsageIn(said('hi')), null)
  assert.equal(callUsageIn({ type: 'assistant', message: { usage: { output_tokens: 1 } } }), null, 'no message id')
  assert.equal(callUsageIn({ type: 'assistant', message: { id: 'x' } }), null, 'no usage')
  const odd = call('m2', {})
  Object.assign(odd.message.usage, { input_tokens: -4, output_tokens: 2.9, cache_read_input_tokens: 'lots', cache_creation_input_tokens: Infinity })
  assert.deepEqual(callUsageIn(odd), { id: 'm2', input: 0, output: 2, cacheRead: 0, cacheWrite: 0 }, 'not a count: 0')
})

test('statusFiguresIn: context and limits only; cost, spend limit and the rest ignored', () => {
  const f = statusFiguresIn(STATUS('s1'))
  assert.deepEqual(f, {
    sessionId: 's1',
    context: { tokens: 24000, percent: 12, window: 200000 },
    limits: {
      five_hour: { used_percent: 23.5, resets_at: new Date(1791000000 * 1000).toISOString() },
      seven_day: { used_percent: 41.2, resets_at: new Date(1791500000 * 1000).toISOString() },
    },
  })
  // Early in a session: no current usage, no % yet, no limits.
  assert.deepEqual(statusFiguresIn({ session_id: 's1', context_window: { context_window_size: 200000, used_percentage: null, current_usage: null } }),
    { sessionId: 's1', context: { tokens: null, percent: null, window: 200000 }, limits: null })
  // Broken or hostile input: nothing taken from it.
  assert.deepEqual(statusFiguresIn({ session_id: 5, context_window: 'x', rate_limits: [] }), { sessionId: null, context: null, limits: {} })
  assert.deepEqual(statusFiguresIn({ rate_limits: { five_hour: { used_percentage: 5, resets_at: 1e15 }, seven_day: { used_percentage: -1, resets_at: 1 } } }).limits,
    {}, 'an absurd time or a negative % drops that limit')
})

test('UsageCounter: each call once, context from the latest, a turn\'s output tokens, /clear and /resume', () => {
  const u = new UsageCounter()
  assert.equal(u.get(), null, 'nothing to show before the first count')
  u.newTurn('p1')
  assert.deepEqual(u.get(), { tokens: { input: 0, output: 0, cache_read: 0, cache_write: 0 }, context: null, turn: { message: 'p1', output_tokens: 0 }, limits: {} })
  assert.equal(u.add({ id: 'a', input: 10, output: 100, cacheRead: 1000, cacheWrite: 50 }), true)
  assert.equal(u.add({ id: 'a', input: 10, output: 100, cacheRead: 1000, cacheWrite: 50 }), false, 'the same call again (another entry of it)')
  u.add({ id: 'b', input: 5, output: 20, cacheRead: 1200, cacheWrite: 0 })
  let g = u.get()!
  assert.deepEqual(g.tokens, { input: 15, output: 120, cache_read: 2200, cache_write: 50 })
  assert.deepEqual(g.context, { tokens: 1205, percent: null, window: null }, 'the latest call\'s input, cache reads and writes; no % without the status line')
  assert.deepEqual(g.turn, { message: 'p1', output_tokens: 120 })

  // The status line gives the window and %; the next call works it out the same way.
  assert.equal(u.status(statusFiguresIn(STATUS('s'))), true)
  assert.deepEqual(u.get()!.context, { tokens: 24000, percent: 12, window: 200000 })
  assert.equal(u.status(statusFiguresIn(STATUS('s'))), false, 'the same again is no change')
  u.newTurn('p2')
  u.add({ id: 'c', input: 1000, output: 7, cacheRead: 29000, cacheWrite: 0 })
  g = u.get()!
  assert.deepEqual(g.context, { tokens: 30000, percent: 15, window: 200000 })
  assert.deepEqual(g.turn, { message: 'p2', output_tokens: 7 }, 'a new turn counts from 0')
  assert.equal(g.limits.five_hour?.used_percent, 23.5)
  // A status line input without limits (not known yet) keeps the last.
  u.status(statusFiguresIn(STATUS('s', { rate_limits: undefined })))
  assert.equal(u.get()!.limits.seven_day?.used_percent, 41.2)

  // /clear: counts start over, the account's limits stay.
  u.reset()
  g = u.get()!
  assert.deepEqual(g.tokens, { input: 0, output: 0, cache_read: 0, cache_write: 0 })
  assert.equal(g.context, null)
  assert.equal(g.limits.five_hour?.used_percent, 23.5)
  assert.equal(u.add({ id: 'a', input: 1, output: 1, cacheRead: 0, cacheWrite: 0 }), true, 'calls are counted again in a new conversation')

  // /resume: the read conversation's counts, limits kept; a call already read isn't counted twice.
  const read = new UsageCounter()
  read.newTurn('r1')
  read.add({ id: 'r', input: 2, output: 3, cacheRead: 4, cacheWrite: 5 })
  u.load(read)
  g = u.get()!
  assert.deepEqual(g.tokens, { input: 2, output: 3, cache_read: 4, cache_write: 5 })
  assert.deepEqual(g.turn, { message: 'r1', output_tokens: 3 })
  assert.equal(g.limits.five_hour?.used_percent, 23.5)
  assert.equal(u.add({ id: 'r', input: 2, output: 3, cacheRead: 4, cacheWrite: 5 }), false)
  // get() is a copy.
  g.tokens.input = 999
  assert.equal(u.get()!.tokens.input, 2)
})

test('readConversation: totals, the latest context, and each user message\'s turn tokens; subagents and injected prompts in their place', () => {
  const dir = tmp('usage-store-')
  const file = path.join(dir, `${crypto.randomUUID()}.jsonl`)
  fs.writeFileSync(file, [
    said('first', 'u1'),
    call('m1', { input: 10, output: 100, read: 0, write: 500 }),
    call('m1', { input: 10, output: 100, read: 0, write: 500 }), // the same call's next block
    call('s1', { input: 1, output: 9999 }, { isSidechain: true }),
    // A subagent's report: Claude Code's prompt, not the user's; its call counts toward the turn.
    said('<task-notification>\n<task-id>t1</task-id>\n<status>completed</status>\n</task-notification>'),
    call('m2', { input: 5, output: 40, read: 500 }),
    said('second', 'u2'),
    call('m3', { input: 7, output: 3, read: 600, write: 10 }),
  ].map(line).join(''))
  const { history, usage } = readConversation(file)
  assert.deepEqual(history.messages.filter((m) => m.role === 'user').map((m) => [m.text, m.turn_tokens]), [['first', 140], ['second', 3]])
  assert.deepEqual(usage.get(), {
    tokens: { input: 22, output: 143, cache_read: 1100, cache_write: 510 },
    context: { tokens: 617, percent: null, window: null },
    turn: { message: 'u2', output_tokens: 3 },
    limits: {},
  })
  assert.equal(readConversation(path.join(dir, 'missing.jsonl')).usage.get(), null)
})

// ---- the command string (the one exception to No shell strings) ----

test('short name guesses: the order Windows tries, ASCII only', () => {
  assert.deepEqual(shortNameGuesses('Program Files').slice(0, 2), ['PROGRA~1', 'PROGRA~2'])
  assert.deepEqual(shortNameGuesses('my.long.name.json').slice(0, 1), ['MYLONG~1.JSO'])
  assert.ok(shortNameGuesses('Paulo Conceição').every((g) => /^[\x21-\x7e]+$/.test(g)))
  assert.deepEqual(shortNameGuesses('...'), [], 'nothing left of the name')
})

test('shortPath: a guess is used only if it is the very same file', () => {
  // A made-up volume: "C:\Program Files" is 1, its short name PROGRA~2 (PROGRA~1 is another folder).
  const ids: Record<string, string> = {
    'C:\\Program Files': 'pf', 'C:\\PROGRA~1': 'other', 'C:\\PROGRA~2': 'pf',
    'C:\\a b': 'ab',
  }
  const id = (p: string) => ids[p] ?? null
  const asked: string[] = []
  const ask = (answer: string | null) => (p: string) => { asked.push(p); return answer }
  assert.equal(shortPath('C:\\Program Files\\nodejs\\node.exe', id, ask(null)), 'C:\\PROGRA~2\\nodejs\\node.exe')
  assert.deepEqual(asked, [], 'a right guess needs no process')
  assert.equal(shortPath('\\\\server\\share\\x', id, ask(null)), null, 'UNC: no')
  assert.equal(shortPath('C:\\plain\\path.txt', () => null, ask(null)), 'C:\\plain\\path.txt', 'safe parts need no lookup')

  // A name Windows hashes (no guess fits): Windows is asked for that folder only, and its answer checked.
  assert.equal(shortPath('C:\\a b\\run-1\\status.json', id, ask(null)), null, 'no answer (no short names on this volume)')
  assert.deepEqual(asked, ['C:\\a b'], 'the folder, not the session\'s file under it')
  ids['C:\\AB2761~1'] = 'ab'
  assert.equal(shortPath('C:\\a b\\run-1\\status.json', id, ask('C:\\AB2761~1')), 'C:\\AB2761~1\\run-1\\status.json')
  assert.equal(shortPath('C:\\a b\\x', id, ask('C:\\PROGRA~2')), null, 'an answer naming another folder')
  assert.equal(shortPath('C:\\a b\\x', id, ask('D:\\AB2761~1')), null, 'another drive')
  ids['C:\\$(AB~1'] = 'ab'
  assert.equal(shortPath('C:\\a b\\x', id, ask('C:\\$(AB~1')), null, 'a short name that still isn\'t safe')
  assert.equal(shortPath('C:\\a b\\x', id, ask('AB2761~1')), null, 'not absolute')
})

test('shellCommand: Windows words unquoted with forward slashes, POSIX single quotes; anything unsafe means no command', () => {
  const win = (argv: string[], short: (p: string) => string | null = (p) => p) => shellCommand(argv, { platform: 'win32', shortPath: short })
  assert.equal(win(['C:\\sidecar\\sidecar.exe', 'statusline', 'C:\\Users\\me\\run\\status.json']),
    'C:/sidecar/sidecar.exe statusline C:/Users/me/run/status.json')
  for (const bad of [
    'relative\\path', 'C:\\has space\\x', 'C:\\a&b', 'C:\\$(x)', 'C:\\a;b', 'C:\\100%', 'C:\\a`b', 'C:\\a\'b', 'C:\\a!b',
    'C:\\caf\u00e9', '\\\\server\\share\\x', 'C:', 'C:\\a,b', 'C:\\a=b', 'C:\\a(b)', 'C:\\a{b}', 'C:\\a@b', 'C:\\a#b', 'C:\\a+b',
  ]) {
    assert.equal(win(['C:\\sidecar.exe', 'statusline', bad]), null, `refused: ${bad}`)
  }
  // A short name that still isn't safe is refused too.
  assert.equal(win(['C:\\x', 'statusline'], () => 'C:\\x y'), null)
  assert.equal(win(['C:\\x', 'statusline'], () => null), null, 'no short name')
  assert.equal(win(['C:\\x', '-flag']), null, 'a word that isn\'t a plain mode word or a path')
  assert.equal(win(['C:\\x', 'Mode']), null)
  assert.equal(win([]), null)

  const posix = (argv: string[]) => shellCommand(argv, { platform: 'linux' })
  assert.equal(posix(['/opt/the app/sidecar', 'statusline', '/tmp/a $(b) `c` & d/status.json']),
    "'/opt/the app/sidecar' statusline '/tmp/a $(b) `c` & d/status.json'")
  for (const bad of ['rel/path', "/a'b", '/a\\b', '/a\nb', '/a\x07b']) assert.equal(posix(['/sidecar', 'statusline', bad]), null, `refused: ${JSON.stringify(bad)}`)
})

/** Git Bash, if installed: Claude Code's first choice on Windows. Never WSL's bash. */
function gitBash(): string | null {
  const tries = [process.env.CLAUDE_CODE_GIT_BASH_PATH, 'C:\\Program Files\\Git\\bin\\bash.exe']
  const where = spawnSync('where', ['git'], { encoding: 'utf8', shell: false })
  for (const g of (where.stdout ?? '').split(/\r?\n/).filter(Boolean)) tries.push(path.join(path.dirname(g), '..', 'bin', 'bash.exe'))
  return tries.find((p): p is string => !!p && fs.existsSync(p)) ?? null
}

/** The shells Claude Code may hand a status line command to here, as it would: the command as one string. */
function shells(): { name: string; run: (command: string, cwd: string, env: NodeJS.ProcessEnv) => ReturnType<typeof spawnSync> }[] {
  const run = (exe: string, args: (c: string) => string[]) => (command: string, cwd: string, env: NodeJS.ProcessEnv) =>
    spawnSync(exe, args(command), { cwd, env, encoding: 'utf8', shell: false, timeout: 20_000 })
  if (process.platform !== 'win32') return [{ name: 'sh', run: run('/bin/sh', (c) => ['-c', c]) }]
  const out = [{ name: 'Windows PowerShell', run: run('powershell.exe', (c) => ['-NoProfile', '-NonInteractive', '-Command', c]) }]
  const bash = gitBash()
  if (bash) out.unshift({ name: 'Git Bash', run: run(bash, (c) => ['-c', c]) })
  const pwsh = spawnSync('where', ['pwsh'], { encoding: 'utf8', shell: false }).stdout?.split(/\r?\n/)[0]
  if (pwsh) out.push({ name: 'PowerShell 7', run: run(pwsh, (c) => ['-NoProfile', '-NonInteractive', '-Command', c]) })
  return out
}

const fileId = (p: string) => { const s = fs.statSync(p, { bigint: true }); return `${s.dev}:${s.ino}` }

/** Whether this Windows volume makes short names: a folder with a space gets one. */
function makesShortNames(dir: string): boolean {
  const probe = path.join(dir, 'probe with space')
  fs.mkdirSync(probe)
  return shortPath(probe) !== null
}

/**
 * Builds `parts` as nested folders in a new one, puts a recorder script and
 * a relay file at the bottom, and runs our command for them in each shell:
 * it must reach the script as exactly its three arguments, and nothing in
 * a name may run. Returns the command, or null when none was made.
 */
function runInShells(t: { diagnostic: (m: string) => void }, parts: string[]): string | null {
  const base = tmp('cmd-')
  const dir = parts.reduce((d, part) => { const n = path.join(d, part); fs.mkdirSync(n); return n }, base)
  const script = path.join(dir, 'record.cjs')
  const relay = path.join(dir, 'status.json')
  const record = path.join(base, 'argv.json')
  fs.writeFileSync(script, `require('fs').writeFileSync(process.env.RECORD_TO, JSON.stringify(process.argv.slice(1)))\n`)
  fs.writeFileSync(relay, '{}')
  const command = shellCommand([process.execPath, script, 'statusline', relay])
  if (command === null) return null
  const cwd = tmp('cmd-cwd-')
  for (const sh of shells()) {
    fs.rmSync(record, { force: true })
    const r = sh.run(command, cwd, { ...process.env, RECORD_TO: record, HOME: cwd, USERPROFILE: cwd })
    assert.equal(r.status, 0, `${sh.name}: ${r.stderr}`)
    const argv = JSON.parse(fs.readFileSync(record, 'utf8')) as string[]
    assert.equal(argv.length, 3, `${sh.name}: three arguments, no more: ${JSON.stringify(argv)}`)
    assert.equal(fileId(argv[0]!), fileId(script), `${sh.name}: our script`)
    assert.equal(argv[1], 'statusline')
    assert.equal(fileId(argv[2]!), fileId(relay), `${sh.name}: our relay file`)
    for (const d of [cwd, base, dir]) assert.ok(!fs.existsSync(path.join(d, 'PWNED')), `${sh.name}: nothing ran from a path`)
    t.diagnostic(`${sh.name}: ok`)
  }
  return command
}

test('the command string, run by the real shells, reaches us as exactly our three arguments, whatever the paths', { timeout: 120_000 }, async (t) => {
  t.diagnostic(`shells: ${shells().map((s) => s.name).join(', ')}`)
  if (process.platform !== 'win32') {
    // POSIX: single quotes keep every one of these whole.
    const command = runInShells(t, ['a b', 'x;touch PWNED;y', '$(touch PWNED)', '`touch PWNED`', '100% & more', '!hist', 'ça va', '{e}@f#g+h', '~home', '-dash', '*', 'a\tb', '$HOME', '"dq"'])
    assert.ok(command)
    return
  }
  if (!makesShortNames(tmp('probe-'))) {
    t.diagnostic('this volume makes no short names: no command; sessions count from their transcripts only')
    assert.equal(runInShells(t, ['a b']), null)
    return
  }
  // Windows: names whose short names are safe, including ones Windows
  // hashes ("a b" -> AB2761~1), so Windows is asked.
  const command = runInShells(t, ['a b', 'x;touch PWNED;y', 'ça va', '100 percent & more', 'Paulo Conceição', 'semi;colon & amp (paren) = eq'])
  assert.ok(command, 'a command for paths with spaces, separators and accents')
  t.diagnostic(`command: ${command}`)
  // Names whose short names a shell would still read (or that have none): no command at all.
  for (const bad of ['$(New-Item PWNED)', '`touch PWNED`', "it's", '!hist', '{e}@f#g+h', '100% & more']) {
    assert.equal(runInShells(t, [bad]), null, `no command under ${bad}`)
  }
})

// ---- whose status line ----

test('a status line of the user\'s own (their settings, the project\'s shared or local) wins: we set none', () => {
  const config = tmp('config-')
  const project = tmp('project-')
  const env = { CLAUDE_CONFIG_DIR: config }
  assert.deepEqual(statusLineSettingsFiles(project, env), [
    path.join(config, 'settings.json'), path.join(project, '.claude', 'settings.json'), path.join(project, '.claude', 'settings.local.json'),
  ])
  const self = [process.platform === 'win32' ? 'C:\\sidecar\\sidecar.exe' : '/sidecar/sidecar', 'statusline',
    process.platform === 'win32' ? 'C:\\run\\status.json' : '/run/status.json']
  const opts = { env, shortPath: (p: string) => p }
  const ours = ourStatusLine(project, self, opts)
  assert.ok('statusLine' in ours && ours.statusLine.type === 'command' && ours.statusLine.command.includes(' statusline '))
  assert.equal(userStatusLine(project, env), null)

  // Other settings, or a status line set to null, don't count.
  fs.writeFileSync(path.join(config, 'settings.json'), JSON.stringify({ theme: 'dark', statusLine: null }))
  assert.equal(userStatusLine(project, env), null)
  for (const file of statusLineSettingsFiles(project, env)) {
    fs.mkdirSync(path.dirname(file), { recursive: true })
    const before = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
    fs.writeFileSync(file, JSON.stringify({ statusLine: { type: 'command', command: 'mine' } }))
    assert.equal(userStatusLine(project, env), file)
    assert.deepEqual(ourStatusLine(project, self, opts), { none: 'the user has a status line of their own' })
    assert.equal(fs.readFileSync(file, 'utf8'), JSON.stringify({ statusLine: { type: 'command', command: 'mine' } }), 'their file is never written')
    if (before === null) fs.rmSync(file); else fs.writeFileSync(file, before)
  }
  // Unparseable but naming one: theirs, to be safe. A folder in the way: not a file.
  fs.writeFileSync(path.join(config, 'settings.json'), '{ "statusLine": { "type": "command", // comment')
  assert.equal(userStatusLine(project, env), path.join(config, 'settings.json'))
  fs.rmSync(path.join(config, 'settings.json'))
  fs.mkdirSync(path.join(config, 'settings.json'))
  assert.equal(userStatusLine(project, env), null)
  // A path that can't be made safe: no status line either.
  assert.deepEqual(ourStatusLine(project, self, { env, shortPath: () => null, platform: 'win32' }), { none: 'its paths can\'t be put safely in a command string' })
})

// ---- the status endpoint and the relay ----

function post(port: number, body: string, headers: Record<string, string>, o: { path?: string; method?: string } = {}) {
  return new Promise<{ status: number; body: string }>((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1', port, path: o.path ?? STATUS_PATH, method: o.method ?? 'POST',
      headers: { host: `127.0.0.1:${port}`, 'content-type': 'application/json', ...headers },
    }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(body)
  })
}

test('status endpoint: the session\'s token, loopback, no browsers; an object only; answered with nothing', async () => {
  const log = new RecordingLog()
  const server = new HookServer(log)
  const port = await server.start()
  const got: unknown[] = []
  const hooks: unknown[] = []
  const link = server.register({ onHook: (p) => { hooks.push(p) }, onStatus: (p) => { got.push(p) } })
  const auth = { authorization: `Bearer ${link.token}` }
  const body = JSON.stringify(STATUS('s1'))
  try {
    assert.equal(server.statusUrl, `http://127.0.0.1:${port}/status`)
    assert.deepEqual(await post(port, body, auth), { status: 200, body: '' })
    assert.deepEqual(got, [STATUS('s1')])
    assert.equal(hooks.length, 0, 'not a hook')
    assert.equal((await post(port, body, {})).status, 401)
    assert.equal((await post(port, body, { authorization: `Bearer ${'0'.repeat(64)}` })).status, 401)
    assert.equal((await post(port, body, { ...auth, origin: 'http://localhost' })).status, 403)
    assert.equal((await post(port, body, { ...auth, host: `localhost:${port}` })).status, 403)
    assert.equal((await post(port, body, auth, { method: 'GET' })).status, 404)
    assert.equal((await post(port, body, auth, { path: '/status/' })).status, 404)
    for (const bad of ['nope', '[1]', '"x"', 'null']) assert.equal((await post(port, bad, auth)).status, 400, bad)
    assert.equal(got.length, 1, 'refused requests never reach the session')
    // A failing handler is logged; the status line still gets its answer.
    const failing = server.register({ onHook: () => undefined, onStatus: () => { throw new Error('boom') } })
    assert.equal((await post(port, body, { authorization: `Bearer ${failing.token}` })).status, 200)
    assert.ok(log.lines.some((l) => /status line input failed: boom/.test(l)))
    link.unregister()
    assert.equal((await post(port, body, auth)).status, 401)
  } finally { await server.close() }
})

test('statusline mode, as the shell runs it: posts its input to the status endpoint, prints nothing, exits 0', { timeout: 30_000 }, async () => {
  const server = new HookServer(new RecordingLog())
  await server.start()
  const got: unknown[] = []
  const link = server.register({ onHook: () => undefined, onStatus: (p) => { got.push(p) } })
  const dir = tmp('statusline-')
  const file = path.join(dir, 'status.json')
  writeRelayFile(file, { url: server.statusUrl, token: link.token })
  const run = (args: string[], stdin: string) => new Promise<{ code: number | null; out: string }>((resolve) => {
    const child = spawn(process.execPath, [MAIN, 'statusline', ...args], { shell: false, stdio: ['pipe', 'pipe', 'pipe'] })
    let out = ''
    child.stdout.setEncoding('utf8').on('data', (d) => { out += d })
    child.stdin.end(stdin)
    child.on('close', (code) => resolve({ code, out }))
  })
  try {
    assert.deepEqual(await run([file], JSON.stringify(STATUS('s1'))), { code: 0, out: '' })
    assert.deepEqual(got, [STATUS('s1')])
    // Failures: still exit 0, still nothing shown in the terminal's status row.
    await server.close()
    assert.deepEqual(await run([file], JSON.stringify(STATUS('s1'))), { code: 0, out: '' }, 'sidecar gone')
    assert.deepEqual(await run([path.join(dir, 'missing.json')], '{}'), { code: 0, out: '' }, 'no relay file')
    assert.deepEqual(await run([], '{}'), { code: 0, out: '' }, 'no arguments')
  } finally { await server.close().catch(() => undefined) }
})

// ---- through a session ----

async function usageSession(o: { config?: string } = {}) {
  let launch: { args: string[] } = { args: [] }
  const config = o.config ?? tmp('config-')
  const p = new ClaudeProvider({
    log: new RecordingLog(),
    findClaude: async () => ({ path: process.execPath, version: '2.1.294' }),
    selfCommand: (mode, ...args) => [process.platform === 'win32' ? 'C:\\sidecar\\sidecar.exe' : '/sidecar/sidecar', mode, ...args],
    openTerminal: async (req) => { launch = JSON.parse(fs.readFileSync(req.argv[2]!, 'utf8')); return 'fake' },
    projectsDir: tmp('projects-'),
    env: { CLAUDE_CONFIG_DIR: config },
  })
  const s = await testServer([p])
  const c = await connect(s.port, s.token)
  await c.sync()
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: tmp('usage-project-') } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const nativeId = arg('--session-id')
  const settings = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8'))
  const h = settings.hooks.PreToolUse[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  const port = Number(new URL(h.url).port)
  const transcripts = tmp('transcripts-')
  const transcript = (sid: string) => path.join(transcripts, `${sid}.jsonl`)
  fs.writeFileSync(transcript(nativeId), '')
  const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n')
  sock.write(JSON.stringify({ type: 'ready' }) + '\n')
  const auth = h.headers.Authorization as string
  const send = (name: string, fields: Record<string, unknown> = {}, sid = nativeId) =>
    post(port, JSON.stringify({ session_id: sid, transcript_path: transcript(sid), cwd: '/', hook_event_name: name, ...fields }), { authorization: auth }, { path: '/hook' })
  const status = (body: object) => post(port, JSON.stringify(body), { authorization: auth })
  const created = await c.next('session.created')
  const usage = async () => (await c.next('usage.updated', 5000)).usage as Usage
  return {
    c, id, nativeId, settings, created, transcript, send, status, usage,
    close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() },
  }
}

test('a session declares usage; its figures follow the transcript live, each call once, and the status line', { timeout: 30_000 }, async () => {
  const x = await usageSession()
  try {
    const session = x.created.session as { capabilities: Record<string, unknown>; usage: unknown }
    assert.deepEqual(session.capabilities.usage, {})
    assert.equal(session.usage, null, 'nothing counted yet')
    // Our status line: this executable in statusline mode with its relay file, nothing else.
    const cmd = x.settings.statusLine.command as string
    assert.equal(x.settings.statusLine.type, 'command')
    const words = cmd.split(' ')
    assert.equal(words.length, 3)
    assert.equal(words[1], 'statusline')
    assert.match(words[2]!, /status\.json'?$/)
    assert.ok(!cmd.includes(x.nativeId) && !/Bearer|token/i.test(cmd), 'no session data on the command line')

    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'count please' })
    assert.deepEqual((await x.usage()).turn, { message: 'p1', output_tokens: 0 })
    // Two entries of one call, then another call: counted once each, as they're written.
    fs.appendFileSync(x.transcript(x.nativeId), line(call('m1', { input: 10, output: 100, write: 500 })) + line(call('m1', { input: 10, output: 100, write: 500 })))
    let u = await x.usage()
    assert.deepEqual(u.tokens, { input: 10, output: 100, cache_read: 0, cache_write: 500 })
    assert.deepEqual(u.turn, { message: 'p1', output_tokens: 100 })
    fs.appendFileSync(x.transcript(x.nativeId), line(call('m2', { input: 5, output: 20, read: 510 })) + line(call('s1', { output: 9999 }, { isSidechain: true })))
    u = await x.usage()
    assert.deepEqual(u.tokens, { input: 15, output: 120, cache_read: 510, cache_write: 500 })
    assert.deepEqual(u.context, { tokens: 515, percent: null, window: null })

    // The status line: context % and window, and the account's limits.
    assert.deepEqual(await x.status(STATUS(x.nativeId)), { status: 200, body: '' })
    u = await x.usage()
    assert.deepEqual(u.context, { tokens: 24000, percent: 12, window: 200000 })
    assert.equal(u.limits.five_hour?.used_percent, 23.5)
    // Another conversation's status line (not the one the world follows) is ignored; so is the same again.
    await x.status(STATUS(crypto.randomUUID(), { context_window: { context_window_size: 1, used_percentage: 99 } }))
    await x.status(STATUS(x.nativeId))
    assert.deepEqual((await x.c.quiet()).filter((m) => m.type === 'usage.updated'), [])

    // The history notes each user message's turn tokens; the snapshot has the figures.
    const hist = await x.c.command({ type: 'session.get_history', session: x.id })
    const msgs = (hist.result as { messages: { role: string; text: string; turn_tokens?: number }[] }).messages
    assert.equal(msgs.find((m) => m.role === 'user')?.turn_tokens, 120)
    await x.c.command({ type: 'session.get_snapshot', session: x.id })
    const snap = (await x.c.next('session.snapshot')).session as { usage: Usage }
    assert.deepEqual(snap.usage.tokens, { input: 15, output: 120, cache_read: 510, cache_write: 500 })
    assert.deepEqual(x.c.invalid, [], 'every message fits the schema')

    // /clear: counts start over; limits stay.
    const fresh = crypto.randomUUID()
    fs.writeFileSync(x.transcript(fresh), '')
    await x.send('UserPromptSubmit', { prompt_id: 'p2', prompt: 'after' }, fresh)
    u = await x.usage()
    assert.deepEqual(u.tokens, { input: 0, output: 0, cache_read: 0, cache_write: 0 })
    assert.equal(u.context, null)
    assert.equal(u.limits.five_hour?.used_percent, 23.5)
  } finally { await x.close() }
})

test('with a status line of the user\'s own, the session keeps it: no statusLine in our settings, figures from the transcript', { timeout: 30_000 }, async () => {
  const config = tmp('config-')
  fs.writeFileSync(path.join(config, 'settings.json'), JSON.stringify({ statusLine: { type: 'command', command: 'their-own' } }))
  const x = await usageSession({ config })
  try {
    assert.equal(x.settings.statusLine, undefined)
    assert.deepEqual(Object.keys(x.settings), ['hooks', 'disableAgentView'])
    await x.send('UserPromptSubmit', { prompt_id: 'p1', prompt: 'hi' })
    await x.usage()
    fs.appendFileSync(x.transcript(x.nativeId), line(call('m1', { input: 1, output: 2, read: 3 })))
    assert.deepEqual((await x.usage()).context, { tokens: 4, percent: null, window: null })
  } finally { await x.close() }
})

test('usage.updated fits the schema; a bad one doesn\'t', () => {
  const good = {
    type: 'usage.updated', session: 's', seq: 1,
    usage: { tokens: { input: 1, output: 2, cache_read: 3, cache_write: 4 }, context: { tokens: 5, percent: 1.5, window: 200000 }, turn: { message: null, output_tokens: 0 }, limits: { five_hour: { used_percent: 101, resets_at: '2026-10-08T10:00:00.000Z' } } },
  }
  assert.ok(checkMessage(good).ok)
  for (const bad of [
    { ...good, usage: { ...good.usage, tokens: { ...good.usage.tokens, input: -1 } } },
    { ...good, usage: { ...good.usage, context: { tokens: 1, percent: null, window: 0 } } },
    { ...good, usage: { ...good.usage, limits: { spend_limit: { used_percent: 1, resets_at: '2026-10-08T10:00:00.000Z' } } } },
    { ...good, usage: { ...good.usage, cost: 1 } },
  ]) assert.ok(!checkMessage(bad as Msg).ok, JSON.stringify(bad.usage))
})
