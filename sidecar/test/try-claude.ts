// Development only: drives the real sidecar like Godot would, to try the
// Claude provider against a real `claude` (S02 checkpoints).
//
//   node test/try-claude.ts <project folder>
//
// It starts the sidecar from source, creates a session in that folder (a
// terminal opens with claude), prints every event with the time since
// launch, and sends each line you type as a chat message from the world.
// Lines starting with / act like the world's buttons instead:
//   /allow [id]   /deny [id] [note] answer a permission (default: the latest)
//   /answer [id] <label>[|label...]  answer a question (one item; | for multi-select)
//   /reply [id] <text>                answer a question with free text
//   /switch [id] <mode>               allow a permission and switch mode (C06)
//   /approve [id] <mode>              approve a plan, switching to that mode (C07)
//   /keep [id] [note]                 send a plan back: "No, keep planning"
//   /stop                             interrupt.request
//   /history                          session.get_history
// Ctrl+C quits; the claude session keeps running in its terminal.
import { spawn } from 'node:child_process'
import path from 'node:path'
import readline from 'node:readline'
import { WebSocket } from 'ws'

const project = process.argv[2]
if (!project) {
  console.error('usage: node test/try-claude.ts <project folder>')
  process.exit(2)
}

const main = path.join(import.meta.dirname, '..', 'src', 'main.ts')
const sidecar = spawn(process.execPath, [main], { stdio: ['pipe', 'pipe', 'pipe'] })
const t0 = Date.now()
const stamp = () => `${((Date.now() - t0) / 1000).toFixed(1).padStart(6)}s`
sidecar.stderr.setEncoding('utf8').on('data', (d: string) => {
  for (const line of d.trimEnd().split('\n')) console.log(`${stamp()}  ${line}`)
})
sidecar.once('exit', (code) => { console.log(`${stamp()}  sidecar exited (${code})`); process.exit(0) })

const handshake = await new Promise<{ port: number; token: string }>((resolve) => {
  let buf = ''
  sidecar.stdout.setEncoding('utf8').on('data', (d: string) => {
    buf += d
    const i = buf.indexOf('\n')
    if (i >= 0) resolve(JSON.parse(buf.slice(0, i)))
  })
})

const ws = new WebSocket(`ws://127.0.0.1:${handshake.port}/`, { headers: { authorization: `Bearer ${handshake.token}` } })
let session = ''
let n = 0
// Pending prompts and questions, newest last, for the / commands.
const permissions: string[] = []
const questions: string[] = []
const plans: string[] = []
const send = (m: Record<string, unknown>) => ws.send(JSON.stringify({ ...m, id: `t${++n}` }))

ws.on('message', (data) => {
  const m = JSON.parse(data.toString())
  const short = m.type === 'session.created' || m.type === 'session.snapshot'
    ? { type: m.type, session: m.session.session, native_id: m.session.native_id, agents: m.session.agents.length }
    : m
  console.log(`${stamp()}  <- ${JSON.stringify(short)}`)
  if (m.type === 'sync.completed' && !session) {
    console.log(`${stamp()}  creating a session in ${path.resolve(project)}`)
    send({ type: 'session.create', provider: 'claude', project: { path: path.resolve(project) } })
  }
  if (m.type === 'ok' && m.result?.session) session = m.result.session
  if (m.type === 'ok' && m.result?.messages) {
    for (const h of m.result.messages) console.log(`         ${h.role} ${h.agent}: ${JSON.stringify(h.text).slice(0, 200)}`)
  }
  if (m.type === 'permission.requested') permissions.push(m.permission.permission)
  if (m.type === 'permission.resolved') drop(permissions, m.permission)
  if (m.type === 'question.asked') questions.push(m.question.question)
  if (m.type === 'question.resolved') drop(questions, m.question)
  if (m.type === 'plan.asked') plans.push(m.plan.plan)
  if (m.type === 'plan.resolved') drop(plans, m.plan)
})

function drop(list: string[], id: string) {
  const i = list.indexOf(id)
  if (i >= 0) list.splice(i, 1)
}

/** `[id] rest`: an explicit id if the first word is a pending one, else the latest. */
function target(pending: string[], words: string[]): { id: string | undefined; rest: string } {
  if (words[0] && pending.includes(words[0])) return { id: words[0], rest: words.slice(1).join(' ') }
  return { id: pending.at(-1), rest: words.join(' ') }
}

function command(line: string) {
  const [cmd, ...words] = line.slice(1).split(' ')
  switch (cmd) {
    case 'allow':
    case 'deny': {
      const { id, rest } = target(permissions, words)
      if (!id) return console.log('no pending permission')
      return send({ type: 'permission.respond', session, permission: id, decision: cmd, ...(rest ? { note: rest } : {}) })
    }
    case 'answer':
    case 'reply': {
      const { id, rest } = target(questions, words)
      if (!id) return console.log('no pending question')
      return send(cmd === 'answer'
        ? { type: 'question.answer', session, question: id, answers: [rest.split('|').map((x) => x.trim())] }
        : { type: 'question.answer', session, question: id, response: rest })
    }
    case 'switch': {
      const { id, rest } = target(permissions, words)
      if (!id) return console.log('no pending permission')
      return send({ type: 'permission.respond', session, permission: id, decision: 'allow', mode: rest.trim() })
    }
    case 'approve':
    case 'keep': {
      const { id, rest } = target(plans, words)
      if (!id) return console.log('no pending plan')
      return send(cmd === 'approve'
        ? { type: 'plan.answer', session, plan: id, approve: true, mode: rest.trim() }
        : { type: 'plan.answer', session, plan: id, approve: false, ...(rest ? { note: rest } : {}) })
    }
    case 'stop': return send({ type: 'interrupt.request', session })
    case 'history': return send({ type: 'session.get_history', session })
    default: console.log('commands: /allow /deny /switch /answer /reply /approve /keep /stop /history')
  }
}

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  if (!session) return console.log('no session yet')
  if (line.startsWith('/')) return command(line)
  send({ type: 'message.send', session, text: line })
})
