// A permission prompt's other ways to allow (C05 reopened; NOTES.md -> S02
// -> Prompt options). The terminal's prompt shows "Yes", at most one
// "Yes, and ..." built from Claude Code's permission_suggestions, "Yes, and
// switch to auto mode" on Bash, and "No". The hook gives us the suggestions
// but not the terminal's words, and its dialog sometimes applies something
// the hook doesn't report (dev log 2026-10-03-c05-prompt-options-spike).
// So: offer the suggestions Claude Code made, never more than the terminal
// would allow (user's rule), each labelled by exactly what it does.
import os from 'node:os'
import type { PermissionOption } from '../../protocol.ts'

/** A permission update entry (hooks docs: Permission update entries), as Claude Code sends and takes it. */
export type PermissionUpdate = Record<string, unknown>

/** An option with the updates choosing it applies (never sent to the world). */
export interface PromptOption extends PermissionOption { updates: PermissionUpdate[] }

/** Option ids: the terminal's "Yes, and ..." and "Yes, and switch to auto mode". */
export const SUGGESTED = 'suggested'
export const AUTO = 'auto'

/** Where an update can be written (hooks docs). Anything else is dropped. */
const DESTINATIONS: readonly string[] = ['session', 'localSettings', 'projectSettings', 'userSettings']
/**
 * The tools whose prompts offer the switch to accept edits, as the terminal
 * does (seen on Edit and Write, 2026-10-03). Elsewhere the hook suggests it
 * where the terminal doesn't (PowerShell), so it's dropped.
 */
const FILE_EDIT_TOOLS: readonly string[] = ['Edit', 'Write', 'NotebookEdit', 'MultiEdit']

export const ACCEPT_EDITS_LABEL = 'Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session'
export const AUTO_LABEL = 'Yes, and switch to auto mode'

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const str = (v: unknown): string | undefined => (typeof v === 'string' ? v : undefined)

interface Rule { toolName: string; ruleContent?: string }

function rulesOf(e: PermissionUpdate): Rule[] | null {
  if (!Array.isArray(e.rules) || e.rules.length === 0) return null
  const rules: Rule[] = []
  for (const r of e.rules) {
    if (!isObject(r) || !str(r.toolName)) return null
    if (r.ruleContent !== undefined && typeof r.ruleContent !== 'string') return null
    rules.push({ toolName: r.toolName as string, ...(r.ruleContent !== undefined ? { ruleContent: r.ruleContent as string } : {}) })
  }
  return rules
}

/** Whether a file path is in a `.claude` folder (the terminal offers a narrower choice there). */
function inClaudeFolder(file: string | undefined): boolean {
  return file !== undefined && file.split(/[\\/]/).includes('.claude')
}

/**
 * The suggestions we may offer, unchanged: allow rules, working
 * directories, and the switch to accept edits on a file edit outside a
 * `.claude` folder, each with a known destination. Anything else (rules
 * that restrict or remove, other modes, unknown shapes) is dropped: it
 * could do more than the terminal's choice, or something we can't label.
 */
export function offerable(tool: string, input: Record<string, unknown>, suggestions: unknown): PermissionUpdate[] {
  if (!Array.isArray(suggestions)) return []
  return suggestions.filter((e): e is PermissionUpdate => {
    if (!isObject(e) || !DESTINATIONS.includes(str(e.destination) ?? '')) return false
    switch (e.type) {
      case 'addRules': return e.behavior === 'allow' && rulesOf(e) !== null
      case 'addDirectories':
        return Array.isArray(e.directories) && e.directories.length > 0 && e.directories.every((d) => typeof d === 'string' && d !== '')
      case 'setMode':
        return e.mode === 'acceptEdits' && e.destination === 'session' && FILE_EDIT_TOOLS.includes(tool)
          && !inClaudeFolder(str(input.file_path) ?? str(input.notebook_path))
      default: return false
    }
  })
}

/** A Read rule's folder as the terminal shows it: `//c/x/**` -> `/c/x`. */
function folderOf(rule: Rule): string | null {
  const c = rule.ruleContent
  if (rule.toolName !== 'Read' || !c?.startsWith('//') || !c.endsWith('/**')) return null
  return c.slice(1, -3)
}

/** The project folder as the terminal shows it, `~` for the home folder. */
function shownFolder(cwd: string, home: string): string {
  return home && cwd.toLowerCase().startsWith(home.toLowerCase()) ? `~${cwd.slice(home.length)}` : cwd
}

const WHERE: Record<string, string> = {
  session: 'for this session',
  localSettings: '(saved in this project\'s .claude/settings.local.json)',
  projectSettings: '(saved in this project\'s .claude/settings.json)',
  userSettings: '(saved in your ~/.claude/settings.json)',
}

/** An option's words: the label, and the kind and parts Godot words it from (C16 step 6). */
type Worded = Pick<PermissionOption, 'label' | 'kind' | 'parts'>

/**
 * The label for a prompt's offered updates. The terminal's own words where
 * the live check (2026-10-03) showed the same updates behind them, each with
 * its kind; else a plain description of what they do and where they're
 * saved, with no kind (a stopgap, user's: each such kind is to be checked
 * live and worded like the terminal later).
 */
export function suggestedWords(updates: PermissionUpdate[], cwd: string, home = os.homedir()): Worded {
  const only = updates.length === 1 ? updates[0]! : null
  if (only?.type === 'setMode') return { label: ACCEPT_EDITS_LABEL, kind: 'switch_mode', parts: { mode: 'acceptEdits' } }
  if (only?.type === 'addDirectories' && only.destination === 'session') {
    const folders = only.directories as string[]
    // Not the terminal's words (it says "always allow access to … from this project"): no kind (user's, 2026-10-30).
    return { label: `Yes, and allow access to ${folders.join(', ')} during this session` }
  }
  if (only?.type === 'addRules') {
    const rules = rulesOf(only)!
    const folders = rules.map(folderOf)
    const bash = rules.filter((r) => r.toolName === 'Bash' && r.ruleContent).map((r) => r.ruleContent!)
    const reads = folders.filter((f): f is string => f !== null)
    if (only.destination === 'localSettings') {
      if (bash.length === rules.length) {
        return { label: `Yes, and don't ask again for: ${bash.join(', ')}`, kind: 'allow_commands', parts: { commands: bash } }
      }
      if (reads.length > 0 && bash.length > 0 && reads.length + bash.length === rules.length) {
        return {
          label: `Yes, and allow access to ${reads.join(', ')} and ${bash.map((c) => JSON.stringify(c)).join(', ')} commands`,
          kind: 'allow_folders_and_commands', parts: { folders: reads, commands: bash },
        }
      }
      const [rule] = rules
      if (rules.length === 1 && rule!.toolName === 'WebFetch' && rule!.ruleContent?.startsWith('domain:')) {
        const domain = rule!.ruleContent.slice('domain:'.length)
        return { label: `Yes, and don't ask again for ${domain}`, kind: 'allow_domain', parts: { domain } }
      }
      if (rules.length === 1 && rule!.toolName === 'WebSearch' && rule!.ruleContent === undefined) {
        const folder = shownFolder(cwd, home)
        return { label: `Yes, and don't ask again for Web Search commands in ${folder}`, kind: 'allow_web_search', parts: { folder } }
      }
    }
    if (only.destination === 'session' && reads.length === rules.length) {
      return { label: `Yes, allow reading from ${reads.join(', ')} during this session`, kind: 'read_folders', parts: { folders: reads } }
    }
  }
  const parts = updates.map((e) => {
    const where = WHERE[e.destination as string]!
    if (e.type === 'setMode') return `switch to accept edits ${where}`
    if (e.type === 'addDirectories') return `allow access to ${(e.directories as string[]).join(', ')} ${where}`
    const rules = rulesOf(e)!.map((r) => (r.ruleContent !== undefined ? `${r.toolName}(${r.ruleContent})` : r.toolName))
    return `${e.destination === 'session' ? 'allow' : 'always allow'} ${rules.join(', ')} ${where}`
  })
  return { label: `Yes, and ${parts.join(', and ')}` }
}

/** The label alone (what the terminal would say). */
export function suggestedLabel(updates: PermissionUpdate[], cwd: string, home = os.homedir()): string {
  return suggestedWords(updates, cwd, home).label
}

/**
 * A prompt's options, in the terminal's order: the suggested one (all the
 * offerable suggestions together, as the terminal's single "Yes, and ..."),
 * then the switch to auto mode when C06 offers it.
 */
export function promptOptions(
  tool: string, input: Record<string, unknown>, suggestions: unknown, auto: boolean, cwd: string, home = os.homedir(),
): PromptOption[] {
  const out: PromptOption[] = []
  const updates = offerable(tool, input, suggestions)
  if (updates.length > 0) out.push({ option: SUGGESTED, ...suggestedWords(updates, cwd, home), updates })
  if (auto) {
    out.push({
      option: AUTO, label: AUTO_LABEL, kind: 'switch_mode', parts: { mode: 'auto' },
      updates: [{ type: 'setMode', mode: 'auto', destination: 'session' }],
    })
  }
  return out
}
