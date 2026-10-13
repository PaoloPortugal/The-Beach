// What a Claude session can be started or resumed with, and how its model
// and effort are named (NOTES.md -> S02 -> Model, effort and mode at launch).
// The flags are documented: `--model <alias>`, `--effort <level>`,
// `--permission-mode <mode>`; leaving one out is Claude Code's own default.
import type { Choice, Launch, LaunchOptions } from '../../protocol.ts'

/**
 * The aliases (always the newest of each), the effort levels and the
 * Shift+Tab four (C06: never Bypass or Don't ask), in the order the user
 * decided (2026-10-12). Labels are Claude Code's words where it has them.
 */
export const LAUNCH_OPTIONS: LaunchOptions = {
  model: [
    { id: 'opus', label: 'Opus' }, { id: 'sonnet', label: 'Sonnet' },
    { id: 'haiku', label: 'Haiku' }, { id: 'fable', label: 'Fable' },
  ],
  effort: [
    { id: 'low', label: 'Low' }, { id: 'medium', label: 'Medium' }, { id: 'high', label: 'High' },
    { id: 'xhigh', label: 'Extra high' }, { id: 'max', label: 'Max' },
  ],
  // `default` is Manual's id in hooks and settings; the CLI takes it too.
  mode: [
    { id: 'default', label: 'Manual' }, { id: 'acceptEdits', label: 'Accept edits' },
    { id: 'plan', label: 'Plan' }, { id: 'auto', label: 'Auto' },
  ],
}

/**
 * The command-line flags for the user's choices. The sidecar refuses ids
 * not offered before this; anything not in LAUNCH_OPTIONS is dropped here
 * too, so no caller can pass on another value.
 */
export function launchArgs(launch: Launch | undefined): string[] {
  const offered = (key: keyof LaunchOptions): string | undefined => {
    const id = launch?.[key]
    return id !== undefined && LAUNCH_OPTIONS[key]?.some((c) => c.id === id) ? id : undefined
  }
  const model = offered('model'), effort = offered('effort'), mode = offered('mode')
  return [
    ...(model ? ['--model', model] : []),
    ...(effort ? ['--effort', effort] : []),
    ...(mode ? ['--permission-mode', mode] : []),
  ]
}

/** Control and format characters (newlines, bidi overrides): not shown. */
const UNSHOWABLE = /[\p{Cc}\p{Cf}]/u

const FAMILIES: Record<string, string> = { opus: 'Opus', sonnet: 'Sonnet', haiku: 'Haiku', fable: 'Fable' }
/** A model id as Claude Code writes it: claude-opus-5-5, claude-haiku-4-5-20251001, claude-opus-5-5[1m]. */
const MODEL_ID = /^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?(\[1m\])?$/

/**
 * A model id (SessionStart, the status line, PostModelSwitch) as the user
 * would name it: "Opus 5.5", "Haiku 4.5", "Opus 5.5 (1M context)". Anything
 * else as it is; null for what isn't a model (`<synthetic>`, empty, too
 * long, control or format characters).
 */
export function modelChoice(id: unknown): Choice | null {
  if (typeof id !== 'string' || !id || id.length > 200 || id.startsWith('<') || UNSHOWABLE.test(id)) return null
  const m = MODEL_ID.exec(id)
  const family = m && FAMILIES[m[1]!]
  if (!m || !family) return { id, label: id }
  return { id, label: `${family} ${m[2]}${m[3] ? `.${m[3]}` : ''}${m[4] ? ' (1M context)' : ''}` }
}

/** An effort level from a hook (`effort.level`), labelled like the launch list; null if it isn't one. */
export function effortChoice(level: unknown): Choice | null {
  if (typeof level !== 'string' || !level || UNSHOWABLE.test(level)) return null
  return LAUNCH_OPTIONS.effort!.find((c) => c.id === level) ?? (level.length <= 50 ? { id: level, label: level } : null)
}
