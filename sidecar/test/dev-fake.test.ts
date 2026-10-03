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

test('dev:fake: echo, permission, question, agents, tools, modes, plans, notice, stop and resume all play out validly', { timeout: 60000 }, async () => {
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
    assert.deepEqual((created.session as any).capabilities, { questions: {}, interrupt: { immediate: false }, permission_modes: {}, plans: {} })
    const idle = (m: Msg) => m.type === 'agent.state_changed' && m.agent === 'main' && m.state === 'idle'
    const say = (text: string) => c.command({ type: 'message.send', session, text })

    await say('hello')
    assert.match(String((await c.next((m) => m.type === 'message.completed' && String(m.message).startsWith('a'), 5000)).text), /You said/)
    await c.next(idle, 5000)

    await say('ask for permission please')
    const perm = await c.next('permission.requested', 5000)
    const pid = (perm.permission as any).permission
    // In auto mode: "don't ask again" only, no switch.
    assert.deepEqual((perm.permission as any).options, [{ option: 'suggested', label: 'Yes, and don\'t ask again for: npm install' }])
    assert.equal((await c.command({ type: 'permission.respond', session, permission: pid, decision: 'deny' })).type, 'ok')
    assert.equal((await c.next('tool.finished', 5000)).status, 'denied')
    await c.next(idle, 5000)

    await say('a question')
    const q = await c.next('question.asked', 5000)
    const qid = (q.question as any).question
    assert.equal((await c.command({ type: 'question.answer', session, question: qid, answers: [['Banana'], ['Honey', 'Nuts']] })).type, 'ok')
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

    // C04: three calls after the turn's first message, the last one failing;
    // the subagents' calls were within their Agent calls.
    await say('use some tools')
    await c.next((m) => m.type === 'message.completed' && /One test failed/.test(String(m.text)), 8000)
    await c.next(idle, 5000)
    const logged = ((await c.command({ type: 'session.get_history', session })).result as { tools: any[] }).tools
    const turn = logged.slice(-3)
    assert.deepEqual(turn.map((t) => t.status), ['ok', 'ok', 'error'])
    assert.equal(turn[2].result, 'Exit code 1')
    assert.ok(turn.every((t) => t.after === turn[0].after && t.after !== null))
    const agents = logged.filter((t) => t.tool === 'Agent').map((t) => t.tool_call)
    assert.equal(agents.length, 2)
    assert.ok(agents.every((a) => logged.filter((t) => t.within === a).length === 3))

    // C06: Shift+Tab-like switches; a Bash prompt in Manual can switch to
    // auto, one of its options (C05).
    assert.equal((created.session as any).mode, 'auto')
    await say('next mode')
    assert.equal((await c.next((m) => m.type === 'session.updated' && m.mode !== undefined, 5000)).mode, 'default')
    await c.next(idle, 5000)
    await say('permission again')
    const switchable = (await c.next('permission.requested', 5000)).permission as any
    assert.deepEqual(switchable.options.map((o: any) => o.option), ['suggested', 'auto'])
    assert.equal((await c.command({ type: 'permission.respond', session, permission: switchable.permission, decision: 'allow', option: 'auto' })).type, 'ok')
    assert.equal((await c.next((m) => m.type === 'session.updated' && m.mode !== undefined, 5000)).mode, 'auto')
    await c.next(idle, 5000)

    // C07: plan mode, a plan message, sent back with a note (a revised plan
    // comes), then approved with a mode.
    await say('make a plan')
    assert.equal((await c.next((m) => m.type === 'session.updated' && m.mode !== undefined, 5000)).mode, 'plan')
    const planMessage = await c.next((m) => m.type === 'message.started' && m.kind === 'plan', 5000)
    const asked = (await c.next('plan.asked', 8000)).plan as any
    assert.deepEqual(asked.modes, ['auto', 'default'])
    assert.equal((await c.next((m) => m.type === 'agent.state_changed' && m.agent === 'main', 5000)).reason, 'plan')
    assert.equal((await c.command({ type: 'plan.answer', session, plan: asked.plan, approve: false, note: 'add tests' })).type, 'ok')
    assert.equal((await c.next('plan.resolved', 5000)).decision, 'rejected')
    const again = (await c.next('plan.asked', 15000)).plan as any
    assert.match(again.text, /add tests/)
    assert.equal((await c.command({ type: 'plan.answer', session, plan: again.plan, approve: true, mode: 'default' })).type, 'ok')
    assert.equal((await c.next('plan.resolved', 5000)).decision, 'approved')
    assert.equal((await c.next((m) => m.type === 'session.updated' && m.mode !== undefined, 5000)).mode, 'default')
    await c.next(idle, 5000)
    const plans = ((await c.command({ type: 'session.get_history', session })).result as { messages: any[] }).messages.filter((m) => m.kind === 'plan')
    assert.equal(plans.length, 2)
    assert.equal(plans[0].message, planMessage.message)

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

    // Stored sessions: listed newest first, resumed with their chat, and not
    // listed while they run.
    const list = async () => ((await c.command({ type: 'session.list_stored', provider: 'fake' })).result as { sessions: any[] }).sessions
    assert.deepEqual((await list()).map((s) => s.native_id), ['stored-1', 'stored-2', 'stored-3'])
    const resumed = (await c.command({ type: 'session.resume', provider: 'fake', native_id: 'stored-2' })).result as { session: string }
    const back = await c.next('session.created', 3000)
    assert.equal((back.session as any).native_id, 'stored-2')
    assert.equal((back.session as any).title, 'Add a save system')
    const chat = (await c.command({ type: 'session.get_history', session: resumed.session })).result as { messages: any[] }
    assert.deepEqual(chat.messages.map((m) => m.text), ['Where were we?', 'Resumed **Add a save system**.'])
    assert.deepEqual((await list()).map((s) => s.native_id), ['stored-1', 'stored-3'])
    assert.deepEqual(c.invalid, [])
    await c.close()
  } finally { child.kill() }
})
