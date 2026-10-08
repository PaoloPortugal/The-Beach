// The one exception to "No shell strings" (NOTES.md -> Security rules; C08
// -> The command string): a provider's CLI that only runs a program
// through a shell (Claude Code's status line) gets a command string. It is
// built only from our own fixed paths (this executable, a relay file) and
// a mode word, never session data, in a form that means the same in every
// shell the CLI may use; when a path can't be made safe, there is no
// command (null) and the caller goes without. Replaced by an argument list
// as soon as the CLI offers one (NOTES.md -> Watch items).
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { cleanEnv, STORE_CLIENT_VARIABLES } from './env.ts'

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

/** Asks Windows for a path's short form; null if it can't say. */
export type AskShort = (p: string) => string | null

/**
 * Windows PowerShell by its full path under SystemRoot, never by a bare
 * name Windows might look for in the working folder first (like conhost
 * in terminal.ts); null if it isn't there.
 */
export function windowsPowerShell(env: NodeJS.ProcessEnv = process.env): string | null {
  const root = env.SystemRoot
  if (!root || !/^[A-Za-z]:\\/.test(root)) return null
  const exe = path.win32.join(root, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  return fs.existsSync(exe) ? exe : null
}

/** What askWindows runs, injectable for tests. */
export interface AskOptions {
  /** The PowerShell to run (default windowsPowerShell()); null: no answer. */
  program?: string | null
  /** Its working folder: a fixed one (default the temp folder), not whatever the sidecar inherited. */
  cwd?: string
  env?: NodeJS.ProcessEnv
  run?: typeof spawnSync
}

const SHORT_PATH_SCRIPT = '$f = New-Object -ComObject Scripting.FileSystemObject; $p = $env:SIDECAR_SHORT_PATH; ' +
  'if ($f.FileExists($p)) { [Console]::Out.Write($f.GetFile($p).ShortPath) } ' +
  'elseif ($f.FolderExists($p)) { [Console]::Out.Write($f.GetFolder($p).ShortPath) }'

/**
 * Windows' own short form of an existing path (GetShortPathName, through
 * the Scripting.FileSystemObject in PowerShell), for the names it hashes
 * (`AB2761~1`), which can't be guessed. A fixed script in an argument
 * array, run from a fixed folder with the user's environment, cleaned
 * (Security rules -> Clean child environments; with only SystemRoot,
 * PowerShell hung on CI's Windows runner), and the path (in a variable,
 * never on a command line). Blocks for up to
 * 10 s. Only the answer's file identity is trusted (shortPath checks it).
 */
export function askWindows(p: string, opts: AskOptions = {}): string | null {
  const env = opts.env ?? process.env
  const program = opts.program === undefined ? windowsPowerShell(env) : opts.program
  if (program === null || !env.SystemRoot) return null
  try {
    const r = (opts.run ?? spawnSync)(program, ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', SHORT_PATH_SCRIPT], {
      cwd: opts.cwd ?? os.tmpdir(), env: { ...cleanEnv(env, { names: STORE_CLIENT_VARIABLES }, 'win32'), SIDECAR_SHORT_PATH: p },
      encoding: 'utf8', shell: false, timeout: 10_000, windowsHide: true,
    })
    if (r.status === 0 && typeof r.stdout === 'string' && r.stdout) return r.stdout.trim()
  } catch { /* no PowerShell: no answer */ }
  return null
}

/** Windows' answers, per path: asked at most once per run. */
const asked = new Map<string, string | null>()

const askWindowsOnce: AskShort = (p) => {
  if (!asked.has(p)) asked.set(p, askWindows(p))
  return asked.get(p)!
}

/**
 * A Windows path whose every component is safe for WINDOWS_WORD, using
 * the 8.3 short name of any component that isn't, or null. First without
 * starting a process: each guess (shortNameGuesses) is accepted only if it
 * names the very same file (volume and file index), so a wrong guess
 * can't point elsewhere. Failing that (a name Windows hashes), Windows
 * itself is asked (askWindows), and its answer is checked the same way.
 * Null when the volume makes no short names, or a short name still isn't
 * safe (`$(NEW-~1`).
 */
export function shortPath(p: string, id: Identify = identify, ask: AskShort = askWindowsOnce): string | null {
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
    if (found) {
      short = path.win32.join(short, found)
    } else {
      // Asked for this folder (or file), not the whole path: a session's
      // own folder is new each time, the folders above it aren't.
      const theirs = windowsShort(ask, nextLong, root)
      if (theirs === null || id(theirs) !== want) return null
      short = theirs
    }
    long = nextLong
  }
  return short
}

/** Windows' short form of `p`, if it's on the same drive and every component is safe. */
function windowsShort(ask: AskShort, p: string, root: string): string | null {
  const answer = ask(p)
  if (answer === null || !path.win32.isAbsolute(answer)) return null
  const theirs = path.win32.resolve(answer)
  const rest = theirs.slice(root.length).split('\\').filter(Boolean)
  if (path.win32.parse(theirs).root.toUpperCase() !== root.toUpperCase() || !rest.every((c) => SAFE_COMPONENT.test(c))) return null
  return root + rest.join('\\')
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
