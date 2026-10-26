// Finding the user's own `claude` (NOTES.md -> Architecture -> Platforms).
// Apps started from the macOS Dock or a Linux menu don't get the shell's
// PATH, so the documented install locations are checked too, then (macOS and
// Linux) the PATH the user's login shell builds. On Windows only
// a real claude.exe is used: npm's claude.cmd wrapper needs a shell.
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFile, spawn } from 'node:child_process'
import { findOnPath } from '../../launch/terminal.ts'
import type { Env } from '../../launch/env.ts'

/** The version everything was verified against (S02 spike and build). */
export const MIN_VERSION = '2.1.284'

export interface FoundClaude { path: string; version: string }

export class ClaudeNotFound extends Error {}

/** Candidate paths, in order. Exported for tests. */
export function candidates(platform: NodeJS.Platform, env: Env, home: string): string[] {
  if (platform === 'win32') {
    const w = path.win32
    const list: string[] = []
    const onPath = findOnPath('claude.exe', env, 'win32')
    if (onPath) list.push(onPath)
    list.push(w.join(home, '.local', 'bin', 'claude.exe'))                        // native installer
    if (env.LOCALAPPDATA) list.push(w.join(env.LOCALAPPDATA, 'Microsoft', 'WinGet', 'Links', 'claude.exe'))
    const npmDirs = [findOnPath('claude.cmd', env, 'win32'), env.APPDATA && w.join(env.APPDATA, 'npm', 'claude.cmd')]
    for (const cmd of npmDirs) if (cmd) list.push(...npmWrapperTargets(cmd))
    return dedupe(list, true)
  }
  const p = path.posix
  const list: string[] = []
  const onPath = findOnPath('claude', env, platform)
  if (onPath) list.push(onPath)
  list.push(p.join(home, '.local', 'bin', 'claude'))                              // native installer
  if (platform === 'darwin') list.push('/opt/homebrew/bin/claude', '/usr/local/bin/claude')
  else list.push('/home/linuxbrew/.linuxbrew/bin/claude', '/usr/local/bin/claude', '/usr/bin/claude')
  list.push(p.join(home, '.npm-global', 'bin', 'claude'))
  return dedupe(list, false)
}

/**
 * npm on Windows puts a claude.cmd wrapper on PATH that starts the real
 * claude.exe. Read the wrapper (never run it) and pick out .exe paths
 * inside the npm folder that it names.
 */
export function npmWrapperTargets(cmdPath: string): string[] {
  let text: string
  try { text = fs.readFileSync(cmdPath, 'utf8') } catch { return [] }
  const dir = path.win32.dirname(cmdPath)
  const out: string[] = []
  for (const m of text.matchAll(/"?%(?:~)?dp0%?\\?([^"%\r\n]*?claude\.exe)"?/gi)) {
    const full = path.win32.resolve(dir, m[1]!)
    if (full.toLowerCase().startsWith(dir.toLowerCase() + '\\')) out.push(full)
  }
  // The package's own location, in case the wrapper's shape changes.
  out.push(path.win32.join(dir, 'node_modules', '@anthropic-ai', 'claude-code', 'bin', 'claude.exe'))
  return out
}

function dedupe(list: string[], caseless: boolean): string[] {
  const seen = new Set<string>()
  return list.filter((p) => {
    const k = caseless ? p.toLowerCase() : p
    if (seen.has(k)) return false
    seen.add(k)
    return true
  })
}

/** Parses `claude --version` output, e.g. "2.1.284 (Claude Code)". */
export function parseVersion(out: string): string | null {
  return /^\s*(\d+\.\d+\.\d+)/.exec(out)?.[1] ?? null
}

export function versionAtLeast(v: string, min: string): boolean {
  const a = v.split('.').map(Number)
  const b = min.split('.').map(Number)
  for (let i = 0; i < 3; i++) {
    if ((a[i] ?? 0) !== (b[i] ?? 0)) return (a[i] ?? 0) > (b[i] ?? 0)
  }
  return true
}

/** Runs `<path> --version` with an argument array and a clean environment. */
export function readVersion(file: string, env: Record<string, string>): Promise<string | null> {
  return new Promise((resolve) => {
    execFile(file, ['--version'], { env, timeout: 15000, windowsHide: true, shell: false }, (err, stdout) => {
      resolve(err ? null : parseVersion(stdout))
    })
  })
}

/** How long the login shell may take to print its PATH. */
export const LOGIN_SHELL_TIMEOUT_MS = 10000
/** Most of a PATH we read from the login shell's output. */
const LOGIN_SHELL_MAX_OUTPUT = 64 * 1024
const LOGIN_SHELL_MARK = '__login_shell_path_7f3a__'
/**
 * What the login shell runs: fixed text, never built from data (Security
 * rules -> No shell strings). printenv prints the exported PATH joined by
 * colons in every shell, fish included; the marks fence it off from
 * anything the user's profile prints.
 */
export const LOGIN_SHELL_SCRIPT = `printf '%s' ${LOGIN_SHELL_MARK}; printenv PATH; printf '%s' ${LOGIN_SHELL_MARK}`

/** The PATH folders between the marks: absolute paths only, in order. Exported for tests. */
export function parseLoginShellPath(out: string): string[] {
  const parts = out.split(LOGIN_SHELL_MARK)
  if (parts.length < 3) return []
  const dirs = parts[1]!.trim().split(':').filter((d) => path.posix.isAbsolute(d) && !/[\0-\x1f\x7f]/.test(d))
  return [...new Set(dirs)]
}

/** The user's login shell: SHELL, else the account's; only an absolute path. Exported for tests. */
export function loginShell(env: Env, account: () => string | null = () => os.userInfo().shell): string | null {
  let shell: string | null | undefined = env.SHELL
  if (!shell) {
    try { shell = account() } catch { return null }
  }
  return shell && path.posix.isAbsolute(shell) ? shell : null
}

/**
 * Asks the user's login shell for the PATH their terminal gets (macOS and
 * Linux: apps started from the Dock, a menu or Steam don't get it, so a
 * `claude` installed under a Node version manager isn't found otherwise).
 * Interactive and login, as a terminal starts it, since version managers
 * often set PATH only for interactive shells. No input, its own process
 * group, our clean environment, started in the home folder. Once it has
 * answered, the group is hung up, as closing a terminal does; stuck (the
 * timeout), flooding, or still running when the sidecar exits, it is
 * killed. Any failure gives [].
 */
export function readLoginShellPath(o: {
  shell: string
  env: Record<string, string>
  home: string
  timeoutMs?: number
}): Promise<string[]> {
  return new Promise((resolve) => {
    let out = ''
    let done = false
    let child: ReturnType<typeof spawn> | undefined
    const signalGroup = (signal: NodeJS.Signals) => {
      try { if (child?.pid) process.kill(-child.pid, signal) } catch { /* already gone */ }
    }
    const killOnExit = () => signalGroup('SIGKILL')
    process.once('exit', killOnExit)
    const finish = (dirs: string[], signal: NodeJS.Signals) => {
      if (done) return
      done = true
      clearTimeout(timer)
      process.off('exit', killOnExit)
      // Stop reading: something the profile started may hold the pipe open.
      child?.stdout?.destroy()
      signalGroup(signal)
      child?.unref()
      resolve(dirs)
    }
    // Stuck (a hung command, a slow profile): end the shell and anything it started.
    const timer = setTimeout(() => finish([], 'SIGKILL'), o.timeoutMs ?? LOGIN_SHELL_TIMEOUT_MS)
    try {
      child = spawn(o.shell, ['-i', '-l', '-c', LOGIN_SHELL_SCRIPT], {
        cwd: o.home, env: o.env, stdio: ['ignore', 'pipe', 'ignore'], detached: true, shell: false,
      })
    } catch {
      finish([], 'SIGKILL')
      return
    }
    child.once('error', () => finish([], 'SIGKILL'))
    child.stdout!.setEncoding('utf8')
    child.stdout!.on('data', (chunk: string) => {
      out += chunk
      if (out.length > LOGIN_SHELL_MAX_OUTPUT) return finish([], 'SIGKILL')
      if (out.split(LOGIN_SHELL_MARK).length >= 3) finish(parseLoginShellPath(out), 'SIGHUP')
    })
    child.once('close', () => finish(parseLoginShellPath(out), 'SIGHUP'))
  })
}

export type ReadVersion = (file: string, env: Record<string, string>) => Promise<string | null>

function tooOldMessage(version: string): string {
  return `Claude Code ${version} is too old; version ${MIN_VERSION} or newer is needed. Run \`claude update\`.`
}

/**
 * Checks a `claude` the user points at by hand (S02, client.set_program_path):
 * a full path, a file, on Windows an .exe (npm's claude.cmd wrapper needs a
 * shell), and answering `--version` with MIN_VERSION or newer. Throws
 * ClaudeNotFound saying which check failed.
 */
export async function checkClaudePath(file: string, o: {
  cleanEnv: Record<string, string>
  platform?: NodeJS.Platform
  readVersion?: ReadVersion
}): Promise<FoundClaude> {
  const platform = o.platform ?? process.platform
  const paths = platform === 'win32' ? path.win32 : path.posix
  if (!paths.isAbsolute(file)) throw new ClaudeNotFound('That isn\'t a full path.')
  if (!fs.statSync(file, { throwIfNoEntry: false })?.isFile()) throw new ClaudeNotFound('There\'s no program at that path.')
  if (platform === 'win32' && paths.extname(file).toLowerCase() !== '.exe') {
    throw new ClaudeNotFound('Pick claude.exe itself: a .cmd or other wrapper can\'t be started without a shell.')
  }
  const version = await (o.readVersion ?? readVersion)(file, o.cleanEnv)
  if (!version) throw new ClaudeNotFound('That program didn\'t answer as Claude Code (claude --version).')
  if (!versionAtLeast(version, MIN_VERSION)) throw new ClaudeNotFound(tooOldMessage(version))
  return { path: file, version }
}

/** The login shell's answer, asked at most once per run: it runs the user's startup files. */
let loginShellAnswer: Promise<string[]> | undefined

/** For tests: forget the answer, so the next lookup asks again. */
export function forgetLoginShellPath(): void {
  loginShellAnswer = undefined
}

/**
 * Finds a working claude of at least MIN_VERSION. `override` is a path the
 * user set by hand: the only one tried (checkClaudePath), even once it stops
 * working. Else, if none of the candidates works on macOS or Linux, asks the
 * login shell for its PATH, last (NOTES.md -> Architecture -> Platforms).
 * Throws ClaudeNotFound with a message for the player.
 */
export async function findClaude(opts: {
  env: Env
  cleanEnv: Record<string, string>
  override?: string
  platform?: NodeJS.Platform
  home?: string
  /** For tests: the login shell's PATH folders. */
  loginShellPath?: () => Promise<string[]>
  /** For tests: replaces running `--version`. */
  readVersion?: ReadVersion
}): Promise<FoundClaude> {
  const platform = opts.platform ?? process.platform
  const home = opts.home ?? os.homedir()
  const versionOf = opts.readVersion ?? readVersion
  if (opts.override !== undefined) {
    try {
      return await checkClaudePath(opts.override, { cleanEnv: opts.cleanEnv, platform, readVersion: versionOf })
    } catch (e) {
      if (!(e instanceof ClaudeNotFound)) throw e
      throw new ClaudeNotFound(`The Claude Code set in Settings doesn't work: ${e.message} Choose it again, or reset it.`)
    }
  }
  const list = candidates(platform, opts.env, home)
  let tooOld: string | null = null
  const check = async (file: string): Promise<FoundClaude | null> => {
    if (!fs.statSync(file, { throwIfNoEntry: false })?.isFile()) return null
    const version = await versionOf(file, opts.cleanEnv)
    if (!version) return null
    if (!versionAtLeast(version, MIN_VERSION)) { tooOld = version; return null }
    return { path: file, version }
  }
  for (const file of list) {
    const found = await check(file)
    if (found) return found
  }
  if (platform !== 'win32') {
    // Asked once per run, even when it found nothing: finding claude is
    // retried (a session list, a poll), the user's startup files are not.
    if (opts.loginShellPath) loginShellAnswer ??= opts.loginShellPath()
    else {
      const shell = loginShell(opts.env)
      loginShellAnswer ??= shell ? readLoginShellPath({ shell, env: opts.cleanEnv, home }) : Promise.resolve([])
    }
    const dirs = await loginShellAnswer
    // The first on that PATH, as the user's terminal would pick.
    const file = findOnPath('claude', { PATH: dirs.join(':') }, platform)
    if (file && !list.includes(file)) {
      const found = await check(file)
      if (found) return found
    }
  }
  if (tooOld) {
    throw new ClaudeNotFound(tooOldMessage(tooOld))
  }
  throw new ClaudeNotFound(platform === 'win32'
    ? 'Claude Code for Windows wasn\'t found. Install it from code.claude.com (the Windows version, not inside WSL) and sign in once in a terminal.'
    : 'Claude Code wasn\'t found. Install it from code.claude.com and sign in once in a terminal.')
}
