// The one exception to "No shell strings" (NOTES.md -> Security rules; C08
// -> The command string): a provider's CLI that only runs a program
// through a shell (Claude Code's status line) gets a command string. It is
// built only from our own fixed paths (this executable, a relay file) and
// a mode word, never session data, in a form that means the same in every
// shell the CLI may use; when a path can't be made safe, there is no
// command (null) and the caller goes without. Replaced by an argument list
// as soon as the CLI offers one (NOTES.md -> Watch items).
import fs from 'node:fs'
import path from 'node:path'

/**
 * Windows: Git Bash or PowerShell. Unquoted words of only these characters
 * mean the same in both: no quotes, spaces, variables, globs, escapes,
 * separators or redirections. A drive letter and colon first, so a word
 * never starts with `~` (home in both shells) or `-`.
 */
const WINDOWS_WORD = /^[A-Za-z]:(\/[A-Za-z0-9._~-]+)+$/
/** A path component that needs no short name. */
const SAFE_COMPONENT = /^[A-Za-z0-9._~-]+$/
/** The mode word (and any other fixed argument that isn't a path). */
const PLAIN_WORD = /^[a-z][a-z0-9-]*$/

/** File identity, to check that a short name is the same file. */
export type Identify = (p: string) => string | null

const identify: Identify = (p) => {
  try {
    const st = fs.statSync(p, { bigint: true })
    return `${st.dev}:${st.ino}`
  } catch { return null }
}

/**
 * The 8.3 names Windows would likely give a long name, in the order it
 * tries them (`PROGRA~1`, `PROGRA~2`, ...): spaces and all dots but the
 * last dropped, upper case, six characters, `~n`, and three of the
 * extension. Characters outside ASCII come out as `_` or not at all.
 * Only guesses: shortPath checks each one is the same file.
 */
export function shortNameGuesses(name: string): string[] {
  const dot = name.lastIndexOf('.')
  const hasExt = dot > 0 && dot < name.length - 1
  const base = hasExt ? name.slice(0, dot) : name
  const ext = hasExt ? name.slice(dot + 1) : ''
  const out = new Set<string>()
  for (const other of ['_', '']) {
    const clean = (s: string) => s.replace(/[ .]/g, '').toUpperCase()
      .replace(/[+,;=[\]]/g, '_').replace(/[^\x21-\x7e]/g, other)
    const b = clean(base).slice(0, 6)
    const e = clean(ext).slice(0, 3)
    if (!b) continue
    for (let n = 1; n <= 4; n++) out.add(`${b}~${n}${e ? `.${e}` : ''}`)
  }
  return [...out]
}

/**
 * A Windows path whose every component is safe for WINDOWS_WORD, using
 * the 8.3 short name of any component that isn't, or null. No process is
 * started: each guess (shortNameGuesses) is accepted only if it names the
 * very same file (volume and file index), so a wrong guess can't point
 * elsewhere. Null when the volume makes no short names, or the name is
 * one Windows hashes (a fifth `PROGRA~` and on).
 */
export function shortPath(p: string, id: Identify = identify): string | null {
  const full = path.win32.resolve(p)
  const root = path.win32.parse(full).root
  if (!/^[A-Za-z]:\\$/.test(root)) return null // UNC and device paths: no
  const parts = full.slice(root.length).split('\\').filter(Boolean)
  let long = root
  let short = root
  for (const part of parts) {
    const nextLong = path.win32.join(long, part)
    if (SAFE_COMPONENT.test(part)) {
      long = nextLong
      short = path.win32.join(short, part)
      continue
    }
    const want = id(nextLong)
    if (want === null) return null
    const found = shortNameGuesses(part).find((g) => SAFE_COMPONENT.test(g) && id(path.win32.join(short, g)) === want)
    if (!found) return null
    long = nextLong
    short = path.win32.join(short, found)
  }
  return short
}

/** POSIX single quotes. Refused: a quote or backslash (fish reads those inside quotes) and control characters. */
function posixQuote(arg: string): string | null {
  if (/['\\\x00-\x1f\x7f]/.test(arg)) return null
  return `'${arg}'`
}

export interface CommandOptions {
  platform?: NodeJS.Platform
  /** For tests: Windows short names. */
  shortPath?: (p: string) => string | null
}

/**
 * One command string for `argv` (absolute paths, and plain words like a
 * mode), or null if it can't be made safe. Windows: unquoted short paths
 * with forward slashes, the same in Git Bash and PowerShell. Elsewhere:
 * each word in POSIX single quotes for `sh`.
 */
export function shellCommand(argv: string[], opts: CommandOptions = {}): string | null {
  const platform = opts.platform ?? process.platform
  if (argv.length === 0) return null
  const words: string[] = []
  for (const arg of argv) {
    if (PLAIN_WORD.test(arg)) { words.push(arg); continue }
    if (platform === 'win32') {
      if (!path.win32.isAbsolute(arg)) return null
      const short = (opts.shortPath ?? shortPath)(arg)
      const word = short?.replace(/\\/g, '/')
      if (!word || !WINDOWS_WORD.test(word)) return null
      words.push(word)
    } else {
      if (!path.posix.isAbsolute(arg)) return null
      const word = posixQuote(arg)
      if (word === null) return null
      words.push(word)
    }
  }
  return words.join(' ')
}
