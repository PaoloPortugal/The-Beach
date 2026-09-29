// The questions capability (NOTES.md -> S02): AskUserQuestion shows in the
// terminal and in the world at once; the PermissionRequest hook is held
// until one side answers. Payloads follow the S02 spike (run 3).
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import os from 'node:os'
import path from 'node:path'
import { HookTranslator, MAIN, questionItems, questionReply } from '../src/providers/claude/hooks.ts'
import { ClaudeProvider } from '../src/providers/claude/index.ts'
import { connect, RecordingLog, testServer } from './helpers.ts'

const CWD = path.resolve(os.tmpdir(), 'proj')
const hook = (name: string, fields: Record<string, unknown> = {}) =>
  ({ session_id: 's', transcript_path: 'x', cwd: CWD, hook_event_name: name, ...fields })
const FRUIT = {
  questions: [{
    question: 'Which fruit do you prefer?', header: 'Fruit', multiSelect: false,
    options: [{ label: 'Apple', description: 'Choose Apple' }, { label: 'Banana', description: 'Choose Banana' }],
  }],
}
const ask = (id: string, input: object = FRUIT, extra: object = {}) =>
  hook('PreToolUse', { tool_name: 'AskUserQuestion', tool_input: input, tool_use_id: id, ...extra })
const held = (input: object = FRUIT, extra: object = {}) =>
  hook('PermissionRequest', { tool_name: 'AskUserQuestion', tool_input: input, permission_suggestions: [], ...extra })

test('question items from AskUserQuestion input; anything malformed is not shown', () => {
  assert.deepEqual(questionItems(FRUIT), [{
    text: 'Which fruit do you prefer?', header: 'Fruit', multi_select: false,
    options: [{ label: 'Apple', description: 'Choose Apple' }, { label: 'Banana', description: 'Choose Banana' }],
  }])
  assert.equal(questionItems({}), null)
  assert.equal(questionItems({ questions: [] }), null)
  assert.equal(questionItems({ questions: [{ question: 'q', options: [{ nolabel: 1 }] }] }), null)
})

test('replies: answers keyed by question text (as verified); a free response denies with the user\'s words', () => {
  assert.deepEqual(questionReply(FRUIT, { answers: [['Banana']] }), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest',
      decision: { behavior: 'allow', updatedInput: { ...FRUIT, answers: { 'Which fruit do you prefer?': 'Banana' } } } },
  })
  const two = { questions: [FRUIT.questions[0], { question: 'Toppings?', multiSelect: true, options: [{ label: 'Salt' }, { label: 'Honey' }] }] }
  const r = questionReply(two, { answers: [['Apple'], ['Salt', 'Honey']] }) as any
  assert.deepEqual(r.hookSpecificOutput.decision.updatedInput.answers, { 'Which fruit do you prefer?': 'Apple', 'Toppings?': 'Salt, Honey' })
  assert.deepEqual(questionReply(FRUIT, { response: 'Neither, I like mangoes' }), {
    hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'deny', message: 'Neither, I like mangoes' } },
  })
  assert.throws(() => questionReply(two, { answers: [['Apple']] }), /one answer per question/)
  assert.throws(() => questionReply(FRUIT, { answers: [[]] }), /one answer per question/)
})

test('translator: asked (tied to its tool call), answered in the world, then the call finishes once', () => {
  const t = new HookTranslator(CWD)
  t.translate(ask('toolu_q'))
  const asked = t.questionAsked(held())!
  assert.equal(asked.question, 'toolu_q')
  assert.deepEqual(asked.events, [
    { type: 'question.asked', question: { question: 'toolu_q', agent: MAIN, items: questionItems(FRUIT) } },
    { type: 'agent.state_changed', agent: MAIN, state: 'waiting', reason: 'question' },
  ])
  assert.deepEqual(t.questionInput('toolu_q'), FRUIT)
  assert.deepEqual(t.questionAnswered('toolu_q'), [
    { type: 'question.resolved', question: 'toolu_q', by: 'app' },
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
  ])
  assert.deepEqual(t.translate(hook('PostToolUse', { tool_name: 'AskUserQuestion', tool_use_id: 'toolu_q' })),
    [{ type: 'tool.finished', tool_call: 'toolu_q', status: 'ok' }])
})

test('translator: answered in the terminal (PostToolUse) resolves it by external', () => {
  const t = new HookTranslator(CWD)
  t.translate(ask('toolu_q'))
  t.questionAsked(held())
  assert.deepEqual(t.translate(hook('PostToolUse', { tool_name: 'AskUserQuestion', tool_use_id: 'toolu_q' })), [
    { type: 'question.resolved', question: 'toolu_q', by: 'external' },
    { type: 'agent.state_changed', agent: MAIN, state: 'working', reason: null },
    { type: 'tool.finished', tool_call: 'toolu_q', status: 'ok' },
  ])
})

test('translator: a subagent\'s question is the subagent\'s even if the hook doesn\'t name it', () => {
  const t = new HookTranslator(CWD)
  t.translate(hook('SubagentStart', { agent_id: 'sub', agent_type: 'Plan' }))
  t.translate(ask('toolu_s', FRUIT, { agent_id: 'sub', agent_type: 'Plan' }))
  const asked = t.questionAsked(held())!
  assert.equal((asked.events[0] as any).question.agent, 'sub')
  // Without a PreToolUse at all, it still shows, with an id of its own.
  const lone = new HookTranslator(CWD).questionAsked(held())!
  assert.match(lone.question, /^[0-9a-f-]{36}$/)
  assert.equal(new HookTranslator(CWD).questionAsked(held({ questions: 'bad' })), null)
})

test('translator: the turn ending or the user typing clears the orchestrator\'s question (Esc)', () => {
  const t = new HookTranslator(CWD)
  t.translate(ask('toolu_q'))
  t.questionAsked(held())
  const ev = t.translate(hook('Stop', {}))
  assert.deepEqual(ev.map((e) => e.type), ['question.resolved', 'agent.state_changed'])
  assert.equal((ev[1] as any).state, 'idle')
})

// ---- through a session ----

function post(port: number, auth: string, body: object) {
  let req!: http.ClientRequest
  const done = new Promise<{ status: number; body: string }>((resolve, reject) => {
    req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/hook',
      headers: { authorization: auth, 'content-type': 'application/json' } }, (res) => {
      let b = ''
      res.setEncoding('utf8').on('data', (d) => { b += d }).on('end', () => resolve({ status: res.statusCode!, body: b }))
    })
    req.on('error', reject)
    req.end(JSON.stringify(body))
  })
  return { done, abort: () => req.destroy() }
}

async function liveSession() {
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
  const r = await c.command({ type: 'session.create', provider: 'claude', project: { path: fs.mkdtempSync(path.join(os.tmpdir(), 'q-')) } })
  const id = (r.result as { session: string }).session
  const arg = (flag: string) => launch.args[launch.args.indexOf(flag) + 1]!
  const h = JSON.parse(fs.readFileSync(arg('--settings'), 'utf8')).hooks.PermissionRequest[0].hooks[0]
  const env = JSON.parse(fs.readFileSync(arg('--mcp-config'), 'utf8')).mcpServers['world-bridge'].env
  const sock = net.connect(Number(env.BRIDGE_PORT), '127.0.0.1')
  await new Promise((res) => sock.once('connect', res))
  sock.write(JSON.stringify({ type: 'hello', token: env.BRIDGE_TOKEN }) + '\n' + JSON.stringify({ type: 'ready' }) + '\n')
  const created = await c.next('session.created')
  const port = Number(new URL(h.url).port)
  return {
    c, id, created,
    send: (body: object) => post(port, h.headers.Authorization, body),
    close: async () => { sock.destroy(); await c.close(); await s.close(); await p.shutdown() },
  }
}

test('through a session: questions declared; a held question answered in the world gets the answer', async () => {
  const x = await liveSession()
  try {
    assert.deepEqual((x.created.session as any).capabilities, { questions: {}, interrupt: { immediate: false } })
    assert.deepEqual((x.created.session as any).questions, [])
    await x.send(ask('toolu_q')).done
    const hold = x.send(held())
    const asked = await x.c.next('question.asked')
    assert.equal((asked.question as any).question, 'toolu_q')
    // The hook is still open: Claude Code waits, and so does the terminal's question.
    const early = await Promise.race([hold.done.then(() => 'answered'), new Promise((r) => setTimeout(() => r('held'), 150))])
    assert.equal(early, 'held')

    const snap = await x.c.command({ type: 'session.get_snapshot', session: x.id })
    assert.equal(snap.type, 'ok')
    assert.equal(((await x.c.next('session.snapshot')).session as any).questions.length, 1)

    const bad = await x.c.command({ type: 'question.answer', session: x.id, question: 'toolu_q', answers: [] })
    assert.equal(bad.code, 'invalid_message')
    const ok = await x.c.command({ type: 'question.answer', session: x.id, question: 'toolu_q', answers: [['Banana']] })
    assert.equal(ok.type, 'ok')
    const reply = await hold.done
    assert.equal(reply.status, 200)
    assert.deepEqual(JSON.parse(reply.body).hookSpecificOutput.decision.updatedInput.answers, { 'Which fruit do you prefer?': 'Banana' })
    const resolved = await x.c.next('question.resolved')
    assert.equal(resolved.by, 'app')
    assert.deepEqual(x.c.invalid, [])
  } finally { await x.close() }
})

test('through a session: answered in the terminal releases the held hook with no decision', async () => {
  const x = await liveSession()
  try {
    await x.send(ask('toolu_q')).done
    const hold = x.send(held())
    await x.c.next('question.asked')
    await x.send(hook('PostToolUse', { tool_name: 'AskUserQuestion', tool_use_id: 'toolu_q', tool_response: {} })).done
    assert.deepEqual(await hold.done, { status: 200, body: '' })
    assert.equal((await x.c.next('question.resolved')).by, 'external')
    const late = await x.c.command({ type: 'question.answer', session: x.id, question: 'toolu_q', answers: [['Apple']] })
    assert.equal(late.code, 'invalid_message', 'no longer pending')
  } finally { await x.close() }
})

test('through a session: Claude Code dropping the held hook resolves the question', async () => {
  const x = await liveSession()
  try {
    await x.send(ask('toolu_q')).done
    const hold = x.send(held())
    hold.done.catch(() => {})
    await x.c.next('question.asked')
    hold.abort()
    assert.equal((await x.c.next('question.resolved')).by, 'external')
  } finally { await x.close() }
})

test('through a session: plain permission hooks are not held', async () => {
  const x = await liveSession()
  try {
    const r = await x.send(hook('PermissionRequest', { tool_name: 'Bash', tool_input: { command: 'ls' } })).done
    assert.deepEqual(r, { status: 200, body: '' })
  } finally { await x.close() }
})
