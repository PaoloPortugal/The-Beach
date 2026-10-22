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
function readVersion(file: string, env: Record<string, string>): Promise<string | null> {
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
 * group (killed whole on timeout), our clean environment, started in the
 * home folder. Any failure gives [].
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
    const finish = (dirs: string[]) => {
      if (done) return
      done = true
      clearTimeout(timer)
      // Stop reading: something the profile started may hold the pipe open.
      child?.stdout?.destroy()
      child?.unref()
      resolve(dirs)
    }
    const timer = setTimeout(() => {
      // Stuck (a prompt, a hung command): end the shell and anything it started.
      try { if (child?.pid) process.kill(-child.pid, 'SIGKILL') } catch { /* already gone */ }
      finish([])
    }, o.timeoutMs ?? LOGIN_SHELL_TIMEOUT_MS)
    try {
      child = spawn(o.shell, ['-i', '-l', '-c', LOGIN_SHELL_SCRIPT], {
        cwd: o.home, env: o.env, stdio: ['ignore', 'pipe', 'ignore'], detached: true, shell: false,
      })
    } catch {
      finish([])
      return
    }
    child.once('error', () => finish([]))
    child.stdout!.setEncoding('utf8')
    child.stdout!.on('data', (chunk: string) => {
      out += chunk
      if (out.length > LOGIN_SHELL_MAX_OUTPUT) return finish([])
      if (out.split(LOGIN_SHELL_MARK).length >= 3) finish(parseLoginShellPath(out))
    })
    child.once('close', () => finish(parseLoginShellPath(out)))
  })
}

/**
 * Finds a working claude of at least MIN_VERSION. `override` is a path the
 * user set by hand. If none of the candidates works on macOS or Linux, asks
 * the login shell for its PATH, last (NOTES.md -> Architecture -> Platforms).
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
}): Promise<FoundClaude> {
  const platform = opts.platform ?? process.platform
  const home = opts.home ?? os.homedir()
  const list = opts.override ? [opts.override] : candidates(platform, opts.env, home)
  let tooOld: string | null = null
  const check = async (file: string): Promise<FoundClaude | null> => {
    if (!fs.statSync(file, { throwIfNoEntry: false })?.isFile()) return null
    const version = await readVersion(file, opts.cleanEnv)
    if (!version) return null
    if (!versionAtLeast(version, MIN_VERSION)) { tooOld = version; return null }
    return { path: file, version }
  }
  for (const file of list) {
    const found = await check(file)
    if (found) return found
  }
  if (!opts.override && platform !== 'win32') {
    const shell = loginShell(opts.env)
    const dirs = opts.loginShellPath
      ? await opts.loginShellPath()
      : shell ? await readLoginShellPath({ shell, env: opts.cleanEnv, home }) : []
    // The first on that PATH, as the user's terminal would pick.
    const file = findOnPath('claude', { PATH: dirs.join(':') }, platform)
    if (file && !list.includes(file)) {
      const found = await check(file)
      if (found) return found
    }
  }
  if (tooOld) {
    throw new ClaudeNotFound(`Claude Code ${tooOld} is too old; version ${MIN_VERSION} or newer is needed. Run \`claude update\`.`)
  }
  throw new ClaudeNotFound(platform === 'win32'
    ? 'Claude Code for Windows wasn\'t found. Install it from code.claude.com (the Windows version, not inside WSL) and sign in once in a terminal.'
    : 'Claude Code wasn\'t found. Install it from code.claude.com and sign in once in a terminal.')
}
