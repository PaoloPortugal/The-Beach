// The scripted fake (`npm run dev:fake`) as a real process: each scenario
// the Godot side is built against plays out, and every message it sends
// fits the protocol schema.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import os from 'node:os'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { connect, type Msg } from './helpers.ts'

const script = path.join(import.meta.dirname, 'dev-fake.ts')

test('dev:fake: echo, permission, question, agents, notice and stop all play out validly', { timeout: 60000 }, async () => {
  const child = spawn(process.execPath, [script], { stdio: ['pipe', 'pipe', 'pipe'] })
  try {
    const hs = await new Promise<{ port: number; token: string }>((resolve, reject) => {
      let buf = ''
      child.stdout.setEncoding('utf8').on('data', (d: string) => {
        buf += d
        const i = buf.indexOf('\n')
        if (i >= 0) resolve(JSON.parse(buf.slice(0, i)))
      })
      child.once('exit', () => reject(new Error('dev:fake exited')))
    })
    const c = await connect(hs.port, hs.token)
    await c.sync()
    const r = await c.command({ type: 'session.create', provider: 'fake', project: { path: os.tmpdir() } })
    const session = (r.result as { session: string }).session
    const created = await c.next('session.created', 3000)
    assert.deepEqual((created.session as any).capabilities, { questions: {}, interrupt: { immediate: false } })
    const idle = (m: Msg) => m.type === 'agent.state_changed' && m.agent === 'main' && m.state === 'idle'
    const say = (text: string) => c.command({ type: 'message.send', session, text })

    await say('hello')
    assert.match(String((await c.next((m) => m.type === 'message.completed' && String(m.message).startsWith('a'), 5000)).text), /You said/)
    await c.next(idle, 5000)

    await say('ask for permission please')
    const perm = await c.next('permission.requested', 5000)
    const pid = (perm.permission as any).permission
    assert.equal((await c.command({ type: 'permission.respond', session, permission: pid, decision: 'deny' })).type, 'ok')
    assert.equal((await c.next('tool.finished', 5000)).status, 'denied')
    await c.next(idle, 5000)

    await say('a question')
    const q = await c.next('question.asked', 5000)
    const qid = (q.question as any).question
    assert.equal((await c.command({ type: 'question.answer', session, question: qid, answers: [['Banana']] })).type, 'ok')
    assert.match(String((await c.next((m) => m.type === 'message.completed' && /picked/.test(String(m.text)), 5000)).text), /Banana/)
    await c.next(idle, 5000)

    await say('use 2 agents')
    const spawned = [await c.next('agent.spawned', 5000), await c.next('agent.spawned', 5000)]
    assert.deepEqual(spawned.map((m) => (m.agent as any).parent), ['main', 'main'])
    // They finish in any order.
    const waiting = new Set(spawned.map((s) => (s.agent as any).agent))
    while (waiting.size > 0) {
      const done = await c.next((m) => m.type === 'agent.state_changed' && waiting.has(m.agent) && m.state === 'done', 15000)
      waiting.delete(done.agent)
    }
    await c.next((m) => m.type === 'message.completed' && /reported back/.test(String(m.text)), 5000)

    await say('send a notice')
    assert.equal(((await c.next('session.notice', 5000)).notice as any).code, 'transcripts_off')
    await c.next(idle, 5000)

    await say('agents 3')
    await c.next('agent.spawned', 5000)
    assert.equal((await c.command({ type: 'interrupt.request', session })).type, 'ok')
    const interrupted = await c.next((m) => m.type === 'agent.state_changed' && m.state === 'error', 5000)
    assert.equal(interrupted.reason, 'interrupted')

    const history = (await c.command({ type: 'session.get_history', session })).result as { messages: any[] }
    assert.ok(history.messages.some((m) => m.role === 'user' && m.text === 'hello'))
    assert.deepEqual(c.invalid, [])
    await c.close()
  } finally { child.kill() }
})
