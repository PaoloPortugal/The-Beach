// Self-test for the spike hub and bridge, without a real Claude session.
// Starts the hub with --no-launch, plays Claude Code's side with fake hook
// calls and a real MCP client talking to the bridge over stdio.
import { spawn } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'

const here = path.dirname(fileURLToPath(import.meta.url))
let failed = 0
const check = (name, ok, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${extra ? '  ' + extra : ''}`)
  if (!ok) failed++
}

const hub = spawn(process.execPath, [path.join(here, 'launch.mjs'), '--no-launch'], { stdio: ['ignore', 'pipe', 'inherit'] })
const ctlPath = await new Promise((resolve) => {
  hub.stdout.setEncoding('utf8')
  hub.stdout.on('data', (d) => { const m = d.match(/control file: (.+ctl\.json)/); if (m) resolve(m[1].trim()) })
})
const ctl = JSON.parse(fs.readFileSync(ctlPath, 'utf8'))
const runDir = path.dirname(ctlPath)
const settings = JSON.parse(fs.readFileSync(path.join(runDir, 'settings.json'), 'utf8'))
const mcpConf = JSON.parse(fs.readFileSync(path.join(runDir, 'mcp.json'), 'utf8'))
const hookUrl = settings.hooks.Stop[0].hooks[0].url
const hookAuth = settings.hooks.Stop[0].hooks[0].headers.Authorization

const post = async (url, body, headers = {}, ms = 3000) => {
  const ac = new AbortController()
  const t = setTimeout(() => ac.abort(), ms)
  try {
    const r = await fetch(url, { method: 'POST', body: JSON.stringify(body), signal: ac.signal,
      headers: { 'content-type': 'application/json', ...headers } })
    const text = await r.text()
    return { status: r.status, body: text ? JSON.parse(text) : null }
  } catch (e) { return { status: 'timeout' } } finally { clearTimeout(t) }
}
const hookCall = (payload, ms) => post(hookUrl, payload, { Authorization: hookAuth }, ms)
const ctlCall = (p, body = {}, headers = {}) => post(ctl.url + p, body, { Authorization: `Bearer ${ctl.token}`, ...headers })

// --- security ---
check('hook without token rejected', (await post(hookUrl, { hook_event_name: 'Stop' })).status === 401)
check('hook with wrong token rejected', (await post(hookUrl, { hook_event_name: 'Stop' }, { Authorization: 'Bearer nope' })).status === 401)
check('control without token rejected', (await post(ctl.url + '/stop', {})).status === 401)
check('control from a browser origin rejected',
  (await ctlCall('/stop', {}, { Origin: 'https://evil.example' })).status === 401)
check('servers bind to loopback only', /^http:\/\/127\.0\.0\.1:/.test(hookUrl) && /^http:\/\/127\.0\.0\.1:/.test(ctl.url))
check('bad control JSON does not crash hub',
  (await fetch(ctl.url + '/chat', { method: 'POST', body: '{', headers: { Authorization: `Bearer ${ctl.token}` } })).status === 400)

// --- hook behaviour ---
let r = await hookCall({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command: 'ls' } })
check('ordinary PreToolUse gets an empty 200 (no decision)', r.status === 200 && r.body === null)
r = await hookCall({ hook_event_name: 'MessageDisplay', delta: 'hi\n', final: true })
check('MessageDisplay answered instantly with no replacement', r.status === 200 && r.body === null)

await ctlCall('/stop')
r = await hookCall({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: {} })
check('stop: next step hook returns continue:false', r.body?.continue === false)
r = await hookCall({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: {} })
check('stop applies once', r.body === null)

const questions = [{ question: 'Pick one?', header: 'Pick', options: [{ label: 'A' }, { label: 'B' }], multiSelect: false }]
const held = hookCall({ hook_event_name: 'PreToolUse', tool_name: 'AskUserQuestion', tool_input: { questions } }, 5000)
await new Promise((res) => setTimeout(res, 300))
const st = await fetch(ctl.url + '/state', { headers: { Authorization: `Bearer ${ctl.token}` } }).then((x) => x.json())
check('question is held until answered', st.heldQuestion?.questions?.[0]?.question === 'Pick one?')
await ctlCall('/answer', { answers: { 'Pick one?': 'B' } })
r = await held
const out = r.body?.hookSpecificOutput
check('answer returns allow + updatedInput with answers',
  out?.permissionDecision === 'allow' && out?.updatedInput?.answers?.['Pick one?'] === 'B' &&
  out?.updatedInput?.questions?.length === 1)

await ctlCall('/mode', { hookMode: 'hang' })
r = await hookCall({ hook_event_name: 'Stop' }, 800)
check('hang mode never answers (for the fail-safe test)', r.status === 'timeout')
await ctlCall('/mode', { hookMode: 'normal' })

// --- bridge ---
const conf = mcpConf.mcpServers['world-bridge']
const client = new Client({ name: 'fake-claude-code', version: '0' })
const got = []
client.fallbackNotificationHandler = async (n) => { got.push(n) }
await client.connect(new StdioClientTransport({ command: conf.command, args: conf.args, env: { ...process.env, ...conf.env } }))
const caps = client.getServerCapabilities()
check('bridge declares channel + permission relay',
  !!caps?.experimental?.['claude/channel'] && !!caps?.experimental?.['claude/channel/permission'])
check('bridge declares no tools', !caps?.tools)
await new Promise((res) => setTimeout(res, 300))
r = await ctlCall('/chat', { text: 'hello from the world' })
await new Promise((res) => setTimeout(res, 300))
const chat = got.find((n) => n.method === 'notifications/claude/channel')
check('chat reaches Claude Code as a channel notification', r.body?.sent === true && chat?.params?.content === 'hello from the world')

await client.notification({ method: 'notifications/claude/channel/permission_request',
  params: { request_id: 'abcde', tool_name: 'Bash', description: 'List files', input_preview: '{"command":"ls"}' } })
await new Promise((res) => setTimeout(res, 300))
const st2 = await fetch(ctl.url + '/state', { headers: { Authorization: `Bearer ${ctl.token}` } }).then((x) => x.json())
check('permission request reaches the hub', st2.permissions?.abcde?.tool_name === 'Bash')
await ctlCall('/permission', { request_id: 'abcde', behavior: 'deny' })
await new Promise((res) => setTimeout(res, 300))
const verdict = got.find((n) => n.method === 'notifications/claude/channel/permission')
check('verdict goes back to Claude Code', verdict?.params?.request_id === 'abcde' && verdict?.params?.behavior === 'deny')
await ctlCall('/permission', { request_id: 'ABCDE; rm', behavior: 'allow' })
await new Promise((res) => setTimeout(res, 300))
check('bridge drops a malformed verdict', got.filter((n) => n.method === 'notifications/claude/channel/permission').length === 1)

await client.close()
hub.kill()
fs.rmSync(runDir, { recursive: true, force: true })
console.log(failed ? `\n${failed} FAILED` : '\nall passed')
process.exit(failed ? 1 : 0)
