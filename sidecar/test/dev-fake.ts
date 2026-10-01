// Development only: the sidecar with a fake provider, so the Godot side can
// be built and tried without a real AI tool. `npm run dev:fake` (from
// sidecar/). Chat drives it; a message containing one of these words acts
// out that part of a session, anything else is echoed back:
//   permission   a tool call waits on a permission prompt (answer it: C05)
//   question     a clarifying question (questions capability)
//   agents [n]   the orchestrator spawns n subagents (default 3) that work
//                in the background and report back (A02, A04)
//   notice       a session notice (transcripts off)
//   clear        a new conversation in the session, like /clear (S02)
// A stop from the world (interrupt capability) ends whatever is running.
import { serve } from '../src/serve.ts'
import { FakeProvider, FakeSession } from './fake-provider.ts'
import type { HistoryMessage, Id, SessionEvent } from '../src/protocol.ts'

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

class ScriptedSession extends FakeSession {
  private n = 0
  private stopped = false
  private pendingPermission: { id: Id; tool: Id; resolve: (allow: boolean) => void } | null = null
  private pendingQuestion: { id: Id; resolve: (answer: string) => void } | null = null
  private readonly working = new Set<Id>()

  private emit(e: SessionEvent) {
    if (this.host.ended) return
    this.host.emit(e)
    if (e.type === 'message.completed') {
      const who = this.speakers.get(e.message)
      if (who) this.history.push({ message: e.message, agent: who.agent, role: who.role, text: e.text, at: new Date().toISOString() })
    }
  }

  private readonly speakers = new Map<Id, Pick<HistoryMessage, 'agent' | 'role'>>()
  private state(agent: Id, state: 'working' | 'waiting' | 'idle' | 'done' | 'error', reason: string | null = null) {
    this.emit({ type: 'agent.state_changed', agent, state, reason })
  }

  /** A whole message at once (user) or streamed in line batches (assistant). */
  private async say(role: 'user' | 'assistant', text: string, agent = 'main') {
    const message = `${role[0]}${++this.n}`
    this.speakers.set(message, { agent, role })
    this.emit({ type: 'message.started', message, agent, role })
    if (role === 'assistant') {
      for (const line of text.split('\n')) {
        await sleep(150)
        if (this.stopped) break
        this.emit({ type: 'message.delta', message, text: line + '\n' })
      }
    }
    this.emit({ type: 'message.completed', message, text })
  }

  override async sendMessage(text: string) {
    this.stopped = false
    await this.say('user', text)
    this.state('main', 'working')
    const word = text.toLowerCase()
    if (word.includes('permission')) void this.permissionTurn()
    else if (word.includes('question')) void this.questionTurn()
    else if (/\bagents?\b/.test(word)) void this.agentsTurn(Number(/\d+/.exec(word)?.[0] ?? 3))
    else if (word.includes('notice')) void this.noticeTurn()
    else if (/\bclear\b/.test(word)) void this.clearTurn()
    else void this.echoTurn(text)
  }

  private async finish(reply: string) {
    if (this.stopped) return
    await this.say('assistant', reply)
    if (!this.stopped) this.state('main', 'idle')
  }

  private echoTurn(text: string) {
    return this.finish(['You said:', '', ...text.split('\n').map((l) => `> ${l}`), '', '(This is the fake provider.)'].join('\n'))
  }

  private async permissionTurn() {
    await this.say('assistant', 'I need to install the dependencies first.')
    const tool = `tool${++this.n}`
    const input = { command: 'npm install', description: 'Install dependencies' }
    this.emit({ type: 'tool.started', tool_call: tool, agent: 'main', tool: 'Bash', summary: 'Run: npm install', input })
    const id = `perm${this.n}`
    const allowed = await new Promise<boolean>((resolve) => {
      this.pendingPermission = { id, tool, resolve }
      this.emit({ type: 'permission.requested', permission: { permission: id, agent: 'main', tool: 'Bash', summary: 'Run: npm install', input } })
      this.state('main', 'waiting', 'permission')
    })
    this.state('main', 'working')
    if (allowed) {
      await sleep(1000)
      this.emit({ type: 'tool.finished', tool_call: tool, status: 'ok' })
      return this.finish('Installed. Everything is ready.')
    }
    this.emit({ type: 'tool.finished', tool_call: tool, status: 'denied' })
    return this.finish('OK, I won\'t install anything. How should I go on?')
  }

  override async respondPermission(permission: Id, decision: 'allow' | 'deny') {
    const p = this.pendingPermission
    if (!p || p.id !== permission) return
    this.pendingPermission = null
    this.emit({ type: 'permission.resolved', permission, decision, by: 'app' })
    p.resolve(decision === 'allow')
  }

  private async questionTurn() {
    const tool = `tool${++this.n}`
    this.emit({ type: 'tool.started', tool_call: tool, agent: 'main', tool: 'AskUserQuestion', summary: 'Ask the user' })
    const answer = await new Promise<string>((resolve) => {
      this.pendingQuestion = { id: tool, resolve }
      this.emit({ type: 'question.asked', question: { question: tool, agent: 'main', items: [{
        text: 'Which fruit do you prefer?', header: 'Fruit', multi_select: false,
        options: [{ label: 'Apple', description: 'Crisp' }, { label: 'Banana', description: 'Sweet' }],
      }] } })
      this.state('main', 'waiting', 'question')
    })
    this.emit({ type: 'tool.finished', tool_call: tool, status: 'ok' })
    this.state('main', 'working')
    return this.finish(`You picked: ${answer}.`)
  }

  override answerQuestion = async (question: Id, answer: { answers: string[][] } | { response: string }) => {
    const q = this.pendingQuestion
    if (!q || q.id !== question) return
    this.pendingQuestion = null
    this.emit({ type: 'question.resolved', question, by: 'app' })
    q.resolve('answers' in answer ? answer.answers.map((a) => a.join(', ')).join('; ') : answer.response)
  }

  private async agentsTurn(count: number) {
    count = Math.max(1, Math.min(count, 50))
    await this.say('assistant', `I'll split this across ${count} agents.`)
    const runs: Promise<void>[] = []
    for (let i = 1; i <= count; i++) {
      const agent = `sub${this.n}_${i}`
      this.working.add(agent)
      this.emit({ type: 'agent.spawned', agent: { agent, role: 'subagent', parent: 'main', name: 'Explore', task: `Look at part ${i}`, state: 'working', reason: null } })
      runs.push(this.subagent(agent, i))
    }
    // Background agents: the orchestrator's turn ends while they work.
    this.state('main', 'idle')
    await Promise.all(runs)
    if (this.stopped) return
    this.state('main', 'working')
    return this.finish(`All ${count} agents reported back.`)
  }

  private async subagent(agent: Id, i: number) {
    for (let step = 1; step <= 3; step++) {
      await sleep(600 + 400 * ((i * step) % 4))
      if (this.stopped || !this.working.has(agent)) return
      const tool = `tool_${agent}_${step}`
      this.emit({ type: 'tool.started', tool_call: tool, agent, tool: 'Read', summary: `Read part${i}/file${step}.ts` })
      await sleep(300)
      this.emit({ type: 'tool.finished', tool_call: tool, status: 'ok' })
    }
    this.working.delete(agent)
    this.state(agent, 'done')
  }

  private async noticeTurn() {
    this.emit({ type: 'session.notice', notice: {
      code: 'transcripts_off',
      message: 'Transcript saving is off in Claude Code, so some features may not work as intended. Turning it on is recommended.',
    } })
    return this.finish('I sent a notice for this session.')
  }

  private async clearTurn() {
    this.state('main', 'idle')
    await sleep(300)
    this.emit({ type: 'session.updated', native_id: crypto.randomUUID() })
    this.emit({ type: 'session.notice', notice: {
      code: 'conversation_cleared',
      message: 'A new conversation started in this session (/clear). Claude no longer remembers the chat above.',
    } })
  }

  override interrupt = async () => {
    this.stopped = true
    if (this.pendingPermission) void this.respondPermission(this.pendingPermission.id, 'deny')
    if (this.pendingQuestion) {
      const q = this.pendingQuestion
      this.pendingQuestion = null
      this.emit({ type: 'question.resolved', question: q.id, by: 'app' })
      q.resolve('(stopped)')
    }
    for (const agent of this.working) this.state(agent, 'error', 'interrupted')
    this.working.clear()
    this.state('main', 'idle')
  }
}

class ScriptedProvider extends FakeProvider {
  override async create(host: Parameters<FakeProvider['create']>[0], options: Parameters<FakeProvider['create']>[1]) {
    const s = new ScriptedSession(this, host, options.project)
    this.sessions.push(s)
    // Come up a moment later, like a real session starting in a terminal.
    setTimeout(() => s.announce(), 500)
    return s
  }
}

await serve([new ScriptedProvider({ capabilities: { questions: {}, interrupt: { immediate: false } } })])
