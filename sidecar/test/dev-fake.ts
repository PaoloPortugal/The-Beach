// Development only: the sidecar with a fake provider that answers chat by
// echoing, streamed in line batches like a real one. Lets the Godot side be
// built and tried without a real AI tool. `npm run dev:fake` (from sidecar/).
import { serve } from '../src/serve.ts'
import { FakeProvider, FakeSession } from './fake-provider.ts'

class EchoSession extends FakeSession {
  private n = 0
  override async sendMessage(text: string) {
    const h = this.host
    const user = `u${++this.n}`
    h.emit({ type: 'message.started', message: user, agent: 'main', role: 'user' })
    h.emit({ type: 'message.completed', message: user, text })
    h.emit({ type: 'agent.state_changed', agent: 'main', state: 'working', reason: null })
    const reply = `a${this.n}`
    const lines = [`You said:`, '', ...text.split('\n').map((l) => `> ${l}`), '', '(This is the fake provider.)']
    h.emit({ type: 'message.started', message: reply, agent: 'main', role: 'assistant' })
    for (const line of lines) {
      await new Promise((r) => setTimeout(r, 150))
      if (h.ended) return
      h.emit({ type: 'message.delta', message: reply, text: line + '\n' })
    }
    h.emit({ type: 'message.completed', message: reply, text: lines.join('\n') })
    h.emit({ type: 'agent.state_changed', agent: 'main', state: 'idle', reason: null })
  }
}

class EchoProvider extends FakeProvider {
  override async create(host: Parameters<FakeProvider['create']>[0], options: Parameters<FakeProvider['create']>[1]) {
    const s = new EchoSession(this, host, options.project)
    this.sessions.push(s)
    // Come up a moment later, like a real session starting in a terminal.
    setTimeout(() => s.announce(), 500)
    return s
  }
}

await serve([new EchoProvider({ capabilities: { interrupt: { immediate: false } } })])
