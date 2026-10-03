// SPIKE (C06/C07), temporary: removed before the branch merges. Only active
// with SIDECAR_SPIKE_DIR set (try-claude sets it with --spike). Logs every
// hook's permission mode, and holds every PermissionRequest that isn't a
// question until test/try-claude.ts writes the reply to send back.
import fs from 'node:fs'
import path from 'node:path'
import type { HookPayload } from './hook-server.ts'

export const SPIKE_DIR = process.env.SIDECAR_SPIKE_DIR ?? ''
let n = 0

export function spikeLog(p: HookPayload) {
  if (!SPIKE_DIR) return
  const tool = typeof p.tool_name === 'string' ? ` tool=${p.tool_name}` : ''
  const agent = typeof p.agent_id === 'string' ? ` agent=${p.agent_type}` : ''
  console.error(`[spike] ${p.hook_event_name}${tool}${agent} mode=${String(p.permission_mode)}`)
}

/** Holds a PermissionRequest until answer-<n>.json appears (its JSON is the reply; {} = no decision). */
export function spikeHold(p: HookPayload, gone: AbortSignal): Promise<Record<string, unknown> | void> {
  const id = ++n
  fs.writeFileSync(path.join(SPIKE_DIR, `held-${id}.json`), JSON.stringify(p, null, 2))
  console.error(`[spike] held #${id} PermissionRequest ${String(p.tool_name)}`)
  const answer = path.join(SPIKE_DIR, `answer-${id}.json`)
  return new Promise((resolve) => {
    const timer = setInterval(() => {
      if (!fs.existsSync(answer)) return
      clearInterval(timer)
      const reply = JSON.parse(fs.readFileSync(answer, 'utf8')) as Record<string, unknown>
      console.error(`[spike] #${id} answered: ${JSON.stringify(reply).slice(0, 300)}`)
      resolve(Object.keys(reply).length > 0 ? reply : undefined)
    }, 200)
    gone.addEventListener('abort', () => {
      clearInterval(timer)
      console.error(`[spike] #${id} dropped by Claude Code (answered elsewhere or timed out)`)
      resolve()
    })
  })
}
