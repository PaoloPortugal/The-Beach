// Claude Code's status line as our usage source (NOTES.md -> C08 -> The
// status line relay). The highest settings file that sets `statusLine`
// wins whole, so ours, in the session's --settings, would replace the
// user's own: we set ours only when none of their files sets one. Their
// files are read, never written (NOTES.md -> Security rules).
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { shellCommand, type CommandOptions } from '../../launch/shell-command.ts'

/** Settings files larger than this aren't parsed; only searched for the key. */
const MAX_SETTINGS = 4 * 1024 * 1024

/**
 * The settings files where a user may set their own status line: theirs
 * (under CLAUDE_CONFIG_DIR when set, like Claude Code) and the project's
 * shared and local ones. Managed settings win over ours anyway (we then
 * just get no status line calls), so they aren't read.
 */
export function statusLineSettingsFiles(project: string, env: NodeJS.ProcessEnv = process.env): string[] {
  const config = env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude')
  return [
    path.join(config, 'settings.json'),
    path.join(project, '.claude', 'settings.json'),
    path.join(project, '.claude', 'settings.local.json'),
  ]
}

/** Whether one settings file sets a status line. Unreadable: no; unparseable: yes if it names one (theirs wins when unsure). */
function setsStatusLine(file: string): boolean {
  let text: string
  try {
    const st = fs.statSync(file)
    if (!st.isFile()) return false
    if (st.size > MAX_SETTINGS) {
      const fd = fs.openSync(file, 'r')
      try {
        const buf = Buffer.alloc(MAX_SETTINGS)
        text = buf.subarray(0, fs.readSync(fd, buf, 0, MAX_SETTINGS, 0)).toString('utf8')
      } finally { fs.closeSync(fd) }
      return text.includes('"statusLine"')
    }
    text = fs.readFileSync(file, 'utf8')
  } catch { return false }
  try {
    const v: unknown = JSON.parse(text)
    return typeof v === 'object' && v !== null && !Array.isArray(v) &&
      (v as Record<string, unknown>).statusLine !== undefined && (v as Record<string, unknown>).statusLine !== null
  } catch {
    return text.includes('"statusLine"')
  }
}

/** The user's own settings file that sets a status line, if any. */
export function userStatusLine(project: string, env: NodeJS.ProcessEnv = process.env): string | null {
  return statusLineSettingsFiles(project, env).find(setsStatusLine) ?? null
}

/**
 * Our status line for a session's --settings: `relay`, this executable in
 * statusline mode with the relay file, as a command string (the one
 * exception to No shell strings), or why there's none.
 */
export function ourStatusLine(project: string, relay: string[], opts: CommandOptions & { env?: NodeJS.ProcessEnv } = {}):
  { statusLine: { type: 'command'; command: string } } | { none: string } {
  const theirs = userStatusLine(project, opts.env)
  if (theirs) return { none: 'the user has a status line of their own' }
  const command = shellCommand(relay, opts)
  if (!command) return { none: 'its paths can\'t be put safely in a command string' }
  return { statusLine: { type: 'command', command } }
}
