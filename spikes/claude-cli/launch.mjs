// Hub + launcher (throwaway spike). Stands in for the sidecar: launches a real
// `claude` in a Windows Terminal tab with per-session hooks and our channel,
// logs everything, and exposes a local control API for driving the tests.
// Follows NOTES.md -> Security rules: loopback only, tokens, no shell strings.
import http from 'node:http'
import net from 'node:net'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const stamp = new Date().toISOString().replace(/[:.]/g, '-')
const runDir = path.join(here, 'runs', stamp)
const logDir = path.join(here, 'logs')
fs.mkdirSync(runDir, { recursive: true })
fs.mkdirSync(logDir, { recursive: true })
const logFile = path.join(logDir, `${stamp}.jsonl`)
const workDir = path.join(os.tmpdir(), 'claude-cli-spike-work')
fs.mkdirSync(workDir, { recursive: true })

const token = () => crypto.randomBytes(32).toString('hex')
const hookToken = token(), bridgeToken = token(), ctlToken = token()
const sessionId = crypto.randomUUID()
const same = (a, b) => typeof a === 'string' && a.length === b.length &&
  crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))

const log = (dir, data) => {
  fs.appendFileSync(logFile, JSON.stringify({ t: new Date().toISOString(), dir, data }) + '\n')
}

// ---- state driven by the control API ----
const state = {
  hookMode: 'normal',        // normal | hang | error
  stopPending: false,
  questionMode: 'parallel',  // parallel | hold
  heldQuestion: null,        // { res, input, via }
  permissions: {},           // request_id -> params
  counts: {},
}
const STOP_EVENTS = new Set(['PreToolUse', 'PostToolUse', 'PostToolUseFailure',
  'SubagentStart', 'SubagentStop'])

const readBody = (req) => new Promise((resolve, reject) => {
  let body = ''
  req.setEncoding('utf8')
  req.on('data', (c) => { body += c; if (body.length > 5e6) req.destroy() })
  req.on('end', () => resolve(body))
  req.on('error', reject)
})
const json = (res, code, obj) => {
  res.writeHead(code, { 'content-type': 'application/json' })
  res.end(obj === undefined ? '' : JSON.stringify(obj))
}

// ---- hook endpoint ----
const hookServer = http.createServer(async (req, res) => {
  if (req.method !== 'POST' || req.url !== '/hook' ||
      !same(req.headers.authorization, `Bearer ${hookToken}`)) {
    log('hook-rejected', { url: req.url, origin: req.headers.origin ?? null })
    return json(res, 401, { error: 'unauthorized' })
  }
  const raw = await readBody(req)
  let p
  try { p = JSON.parse(raw) } catch { return json(res, 400, { error: 'bad json' }) }
  const ev = p.hook_event_name
  state.counts[ev] = (state.counts[ev] ?? 0) + 1
  log('hook', p)

  if (state.hookMode === 'hang') return             // never answer: tests Claude's timeout
  if (state.hookMode === 'error') return json(res, 500, { error: 'simulated' })

  if (ev === 'MessageDisplay') return json(res, 200) // answer instantly, never alter text

  if (state.stopPending && STOP_EVENTS.has(ev)) {
    state.stopPending = false
    const out = { continue: false, stopReason: 'Stopped from the companion app (spike).' }
    // Run 1 showed continue:false alone lets the current tool call run; also deny it.
    if (ev === 'PreToolUse') out.hookSpecificOutput = { hookEventName: 'PreToolUse',
      permissionDecision: 'deny', permissionDecisionReason: 'The user stopped the session.' }
    log('hook-reply', { ev, out })
    return json(res, 200, out)
  }

  // Questions. 'hold' (run 1): hold PreToolUse, so the terminal never shows it.
  // 'parallel' (run 3): let the terminal show it and hold PermissionRequest
  // alongside; whichever side answers first wins.
  const holdEvent = state.questionMode === 'hold' ? 'PreToolUse' : 'PermissionRequest'
  if (ev === holdEvent && p.tool_name === 'AskUserQuestion') {
    state.heldQuestion = { res, input: p.tool_input, via: ev }
    res.on('close', () => {
      if (state.heldQuestion?.res === res) {
        state.heldQuestion = null
        log('held-closed', { via: ev, answered: res.writableEnded })
      }
    })
    log('question-held', { via: ev })
    return                                           // answered via /ctl/answer or /ctl/release
  }
  return json(res, 200)
})

// ---- bridge socket ----
let bridge = null
const bridgeServer = net.createServer((sock) => {
  sock.setEncoding('utf8')
  let buf = '', authed = false
  sock.on('data', (chunk) => {
    buf += chunk
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i)
      buf = buf.slice(i + 1)
      let msg
      try { msg = JSON.parse(line) } catch { sock.destroy(); return }
      if (!authed) {
        if (!same(msg.token, bridgeToken)) { log('bridge-rejected', {}); sock.destroy(); return }
        authed = true
        bridge = sock
        continue
      }
      log('bridge', msg)
      if (msg.type === 'permission_request') state.permissions[msg.params.request_id] = msg.params
    }
  })
  sock.on('close', () => { if (bridge === sock) bridge = null; log('bridge-closed', {}) })
  sock.on('error', () => {})
})
const toBridge = (msg) => {
  if (!bridge) return false
  bridge.write(JSON.stringify(msg) + '\n')
  log('to-bridge', msg)
  return true
}

// ---- control API (for the person or Claude driving the spike) ----
const ctlServer = http.createServer(async (req, res) => {
  if (!same(req.headers.authorization, `Bearer ${ctlToken}`) || req.headers.origin) {
    return json(res, 401, { error: 'unauthorized' })
  }
  let body = {}
  try { if (req.method === 'POST') body = JSON.parse((await readBody(req)) || '{}') } catch {
    return json(res, 400, { error: 'bad json' })
  }
  log('ctl', { url: req.url, body })
  switch (req.url) {
    case '/state':
      return json(res, 200, {
        sessionId, hookMode: state.hookMode, questionMode: state.questionMode,
        stopPending: state.stopPending,
        heldQuestion: state.heldQuestion && state.heldQuestion.input,
        permissions: state.permissions, bridgeConnected: !!bridge, counts: state.counts, logFile,
      })
    case '/chat':
      return json(res, 200, { sent: toBridge({ type: 'chat', text: String(body.text) }) })
    case '/permission': {
      const ok = toBridge({ type: 'verdict', request_id: body.request_id, behavior: body.behavior })
      delete state.permissions[body.request_id]
      return json(res, 200, { sent: ok })
    }
    case '/answer': {                                // body.answers: { "<question text>": "<label>" }
      const q = state.heldQuestion
      if (!q) return json(res, 409, { error: 'no held question' })
      state.heldQuestion = null
      const updatedInput = { questions: q.input.questions, answers: body.answers }
      const out = q.via === 'PreToolUse'
        ? { hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: 'allow', updatedInput } }
        : { hookSpecificOutput: { hookEventName: 'PermissionRequest',
            decision: { behavior: 'allow', updatedInput } } }
      log('hook-reply', { ev: q.via, out })
      json(q.res, 200, out)
      return json(res, 200, { answered: true })
    }
    case '/release': {                               // hand the question to the terminal
      const q = state.heldQuestion
      if (!q) return json(res, 409, { error: 'no held question' })
      state.heldQuestion = null
      json(q.res, 200)
      return json(res, 200, { released: true })
    }
    case '/stop':
      state.stopPending = true
      return json(res, 200, { stopPending: true })
    case '/mode':
      if (body.hookMode !== undefined) {
        if (!['normal', 'hang', 'error'].includes(body.hookMode)) return json(res, 400, {})
        state.hookMode = body.hookMode
      }
      if (body.questionMode !== undefined) {
        if (!['parallel', 'hold'].includes(body.questionMode)) return json(res, 400, {})
        state.questionMode = body.questionMode
      }
      return json(res, 200, { hookMode: state.hookMode, questionMode: state.questionMode })
    case '/hooks-down':
      hookServer.close()
      hookServer.closeAllConnections()
      return json(res, 200, { hooks: 'down' })
    case '/hooks-up':
      hookServer.listen(hookPort, '127.0.0.1')
      return json(res, 200, { hooks: 'up' })
    default:
      return json(res, 404, {})
  }
})

const listen = (srv) => new Promise((r) => srv.listen(0, '127.0.0.1', () => r(srv.address().port)))
const hookPort = await listen(hookServer)
const bridgePort = await listen(bridgeServer)
const ctlPort = await listen(ctlServer)

// ---- per-session settings (hooks) and MCP config (bridge) ----
const hook = (timeout) => ({
  type: 'http', url: `http://127.0.0.1:${hookPort}/hook`, timeout,
  headers: { Authorization: `Bearer ${hookToken}` },
})
const all = (timeout = 30) => [{ hooks: [hook(timeout)] }]
const settings = {
  hooks: {
    SessionStart: all(), SessionEnd: all(5), UserPromptSubmit: all(),
    MessageDisplay: all(2),
    PreToolUse: [
      { matcher: '^(?!AskUserQuestion$)', hooks: [hook(30)] },
      { matcher: 'AskUserQuestion', hooks: [hook(3600)] },
    ],
    PostToolUse: all(), PostToolUseFailure: all(),
    PermissionRequest: [
      { matcher: '^(?!AskUserQuestion$)', hooks: [hook(30)] },
      { matcher: 'AskUserQuestion', hooks: [hook(3600)] },
    ],
    Notification: all(), Stop: all(), StopFailure: all(),
    SubagentStart: all(), SubagentStop: all(), PreCompact: all(), PostCompact: all(),
  },
}
const settingsPath = path.join(runDir, 'settings.json')
const mcpPath = path.join(runDir, 'mcp.json')
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2))
fs.writeFileSync(mcpPath, JSON.stringify({
  mcpServers: {
    'world-bridge': {
      command: process.execPath,
      args: [path.join(here, 'bridge.mjs')],
      env: { BRIDGE_PORT: String(bridgePort), BRIDGE_TOKEN: bridgeToken },
    },
  },
}, null, 2))
fs.writeFileSync(path.join(runDir, 'ctl.json'),
  JSON.stringify({ url: `http://127.0.0.1:${ctlPort}`, token: ctlToken, sessionId, logFile }, null, 2))

const claudeArgs = [
  '--settings', settingsPath,
  '--mcp-config', mcpPath,
  '--dangerously-load-development-channels', 'server:world-bridge',
  // --no-session-id: run 2 checked the missing transcript wasn't caused by this flag
  // (it was nested-session detection: see the dev log).
  ...(process.argv.includes('--no-session-id') ? [] : ['--session-id', sessionId]),
  '--name', 'cli-spike',
]
log('launch', { workDir, claudeArgs })
if (!process.argv.includes('--no-launch')) {
  // Clean environment (NOTES.md -> Security rules): drop variables from any
  // Claude Code session this was started from. Runs 1-2 inherited them, so
  // claude treated itself as nested and saved no transcript.
  const env = Object.fromEntries(Object.entries(process.env)
    .filter(([k]) => !/^CLAUDE/i.test(k)))
  log('launch-env', { dropped: Object.keys(process.env).filter((k) => /^CLAUDE/i.test(k)) })
  spawn('wt.exe', ['-w', 'new', 'new-tab', '--title', 'cli-spike', '-d', workDir, 'claude', ...claudeArgs],
    { detached: true, stdio: 'ignore', shell: false, env }).unref()
}
console.log(`hub ready; control file: ${path.join(runDir, 'ctl.json')}`)
console.log(`log: ${logFile}`)
