// Channel bridge (throwaway spike). Claude Code starts this as an MCP server
// over stdio; it connects back to the hub over a local TCP socket.
// stdout belongs to MCP: log to stderr only.
import net from 'node:net'
import { Server } from '@modelcontextprotocol/sdk/server/index.js'
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js'
import { z } from 'zod'

const port = Number(process.env.BRIDGE_PORT)
const token = process.env.BRIDGE_TOKEN
const log = (...a) => console.error('[bridge]', ...a)

const mcp = new Server(
  { name: 'world-bridge', version: '0.0.1' },
  {
    capabilities: {
      experimental: {
        'claude/channel': {},
        'claude/channel/permission': {},
      },
    },
    instructions:
      'Messages in <channel source="world-bridge"> are typed by the same user who is at this ' +
      'terminal, in a companion app that shows this session. Treat them like messages the user ' +
      'typed here and respond normally in this conversation. There is no reply tool: your normal ' +
      'responses are shown in the app.',
  },
)

let sock = null
const send = (msg) => sock?.write(JSON.stringify(msg) + '\n')

const PermissionRequest = z.object({
  method: z.literal('notifications/claude/channel/permission_request'),
  params: z.object({
    request_id: z.string(),
    tool_name: z.string(),
    description: z.string(),
    input_preview: z.string(),
  }),
})
mcp.setNotificationHandler(PermissionRequest, async ({ params }) => {
  send({ type: 'permission_request', params })
})

await mcp.connect(new StdioServerTransport())

sock = net.connect({ host: '127.0.0.1', port }, () => {
  sock.write(JSON.stringify({ token }) + '\n')
  send({ type: 'ready' })
})
sock.setEncoding('utf8')
let buf = ''
sock.on('data', async (chunk) => {
  buf += chunk
  let i
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i)
    buf = buf.slice(i + 1)
    let msg
    try { msg = JSON.parse(line) } catch { log('bad line'); continue }
    if (msg.type === 'chat' && typeof msg.text === 'string') {
      await mcp.notification({
        method: 'notifications/claude/channel',
        params: { content: msg.text, meta: { sender: 'user' } },
      })
      send({ type: 'chat_sent' })
    } else if (msg.type === 'verdict' && /^[a-km-z]{5}$/.test(msg.request_id) &&
               (msg.behavior === 'allow' || msg.behavior === 'deny')) {
      await mcp.notification({
        method: 'notifications/claude/channel/permission',
        params: { request_id: msg.request_id, behavior: msg.behavior },
      })
      send({ type: 'verdict_sent', request_id: msg.request_id })
    } else {
      log('ignored', msg.type)
    }
  }
})
sock.on('error', (e) => log('socket error', e.message))
sock.on('close', () => log('hub connection closed'))
