// Development only: drives the real sidecar like Godot would, to try the
// Claude provider against a real `claude` (S02 checkpoints).
//
//   node test/try-claude.ts <project folder>
//
// It starts the sidecar from source, creates a session in that folder (a
// terminal opens with claude), prints every event with the time since
// launch, and sends each line you type as a chat message from the world.
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
})

readline.createInterface({ input: process.stdin }).on('line', (line) => {
  if (!session) return console.log('no session yet')
  send({ type: 'message.send', session, text: line })
})
