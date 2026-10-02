// Opens the user's terminal running our launcher (NOTES.md -> Architecture ->
// Platforms). Generic: any CLI provider runs in a terminal. A terminal is only
// ever given the launcher's fixed command (the sidecar executable, `launch`,
// and a session file path), never a command line with session data in it.
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import type { Env } from './env.ts'

export interface TerminalRequest {
  /** The launcher's argv: [executable, ...args]. Only paths we control. */
  argv: string[]
  /** Window or tab title. */
  title: string
  /** A private folder for this launch (macOS writes a small script there). */
  runDir: string
}

export interface TerminalOptions {
  platform?: NodeJS.Platform
  env?: Env
  /** A terminal id to try first (a user setting, later). */
  preferred?: string
  /** For tests: finds an executable on PATH or at known places. */
  which?: (name: string, env: Env) => string | null
  /** For tests: whether a file at a known place can be run. */
  isProgram?: (file: string) => boolean
  /** For tests: starts the terminal. */
  start?: (file: string, args: string[]) => Promise<void>
}

export class TerminalError extends Error {}

interface Terminal {
  id: string
  /** The executable, or null if this terminal isn't installed. */
  find(o: Required<Pick<TerminalOptions, 'env' | 'which' | 'isProgram'>>): string | null
  /** File and args to start, or null if it can't safely run this request. */
  command(exe: string, req: TerminalRequest): { file: string; args: string[] } | null
}

// ---- Windows ----

/**
 * The Windows Terminal window sessions open in, as tabs (user's decision,
 * 2026-10-02): wt opens a window by this name the first time, then adds
 * tabs to it; once it's closed, the next session opens it again.
 */
export const WT_WINDOW = 'agent-sessions'

const windowsTerminal: Terminal = {
  id: 'windows-terminal',
  find: ({ env, which, isProgram }) => which('wt.exe', env) ?? existing(isProgram,
    env.LOCALAPPDATA && path.win32.join(env.LOCALAPPDATA, 'Microsoft', 'WindowsApps', 'wt.exe')),
  command(exe, req) {
    // wt parses its own command line: `;` starts a new wt command even when
    // escaped, and `"` is mangled (both checked on Windows Terminal, 2026-09).
    // Our argv never has them; if it ever does, use the next terminal.
    if ([req.title, ...req.argv].some((a) => /[;"]/.test(a))) return null
    return { file: exe, args: ['-w', WT_WINDOW, 'new-tab', '--title', req.title, '--', ...req.argv] }
  },
}

/**
 * The classic console, through conhost.exe. Starting the launcher detached
 * on its own would open a console window, but with our ignored stdio its
 * stdin and stdout are NUL, not that window, and the program it starts isn't
 * interactive (claude exited right after starting; 2026-09-29). conhost
 * gives the launcher a real console.
 */
const windowsConsole: Terminal = {
  id: 'console',
  find: ({ env, isProgram }) => existing(isProgram, env.SystemRoot && path.win32.join(env.SystemRoot, 'System32', 'conhost.exe')),
  command: (exe, req) => ({ file: exe, args: ['--', ...req.argv] }),
}

// ---- macOS ----

/**
 * Terminal.app and iTerm2 can't be handed a program and its arguments, only
 * a file to open. The file is a two-line script whose only content is the
 * launcher's fixed argv, each part single-quoted.
 */
function macScriptTerminal(id: string, app: string, appPaths: string[]): Terminal {
  return {
    id,
    find: () => (appPaths.some((p) => fs.existsSync(p)) ? '/usr/bin/open' : null),
    command(exe, req) {
      const script = path.join(req.runDir, 'launch.command')
      const quoted = req.argv.map((a) => `'${a.replace(/'/g, `'\\''`)}'`).join(' ')
      fs.writeFileSync(script, `#!/bin/sh\nexec ${quoted}\n`, { mode: 0o700 })
      return { file: exe, args: ['-a', app, script] }
    },
  }
}

const macTerminal = macScriptTerminal('terminal-app', 'Terminal',
  ['/System/Applications/Utilities/Terminal.app', '/Applications/Utilities/Terminal.app'])
const iterm = macScriptTerminal('iterm2', 'iTerm', ['/Applications/iTerm.app'])

// ---- Linux ----

/** A terminal that takes the program as argv after a fixed flag. */
function argvTerminal(id: string, binary: string, before: (title: string) => string[]): Terminal {
  return {
    id,
    find: ({ env, which }) => which(binary, env),
    command: (exe, req) => ({ file: exe, args: [...before(req.title), ...req.argv] }),
  }
}

const linuxTerminals: Terminal[] = [
  argvTerminal('gnome-terminal', 'gnome-terminal', (t) => ['--title', t, '--']),
  argvTerminal('konsole', 'konsole', () => ['-e']),
  argvTerminal('xfce4-terminal', 'xfce4-terminal', (t) => ['--title', t, '-x']),
  argvTerminal('kitty', 'kitty', (t) => ['--title', t, '--']),
  argvTerminal('alacritty', 'alacritty', (t) => ['--title', t, '-e']),
  argvTerminal('wezterm', 'wezterm', () => ['start', '--']),
  argvTerminal('foot', 'foot', (t) => ['--title', t]),
  argvTerminal('xterm', 'xterm', (t) => ['-T', t, '-e']),
]

export function terminalsFor(platform: NodeJS.Platform): Terminal[] {
  if (platform === 'win32') return [windowsTerminal, windowsConsole]
  if (platform === 'darwin') return [macTerminal, iterm]
  return linuxTerminals
}

/**
 * Opens a terminal running `req.argv`. Tries the preferred terminal, then
 * the platform's list in order. Resolves with the terminal used. Starting
 * the terminal is all this confirms: whether the program inside runs is
 * known later (the provider hears from it, or times out).
 */
export async function openTerminal(req: TerminalRequest, opts: TerminalOptions = {}): Promise<string> {
  const platform = opts.platform ?? process.platform
  const env = opts.env ?? process.env
  const which = opts.which ?? findOnPath
  const isRunnable = opts.isProgram ?? ((f: string) => isProgram(f, platform))
  const start = opts.start ?? startDetached
  const list = terminalsFor(platform)
  const ordered = opts.preferred
    ? [...list.filter((t) => t.id === opts.preferred), ...list.filter((t) => t.id !== opts.preferred)]
    : list
  const failures: string[] = []
  for (const t of ordered) {
    const exe = t.find({ env, which, isProgram: isRunnable })
    if (!exe) continue
    const cmd = t.command(exe, req)
    if (!cmd) continue
    try {
      await start(cmd.file, cmd.args)
      return t.id
    } catch (e) {
      failures.push(`${t.id}: ${e instanceof Error ? e.message : String(e)}`)
    }
  }
  throw new TerminalError(failures.length > 0
    ? `no terminal could be opened (${failures.join('; ')})`
    : 'no supported terminal is installed')
}

function existing(isProgram: (file: string) => boolean, p: string | undefined | false): string | null {
  return p && isProgram(p) ? p : null
}

/**
 * Whether a file can be run. On Windows, apps from the Store (Windows
 * Terminal's wt.exe) are "app execution aliases": `stat` fails on them with
 * EACCES, so they look missing; `lstat` sees a link, and starting one works.
 */
function isProgram(full: string, platform: NodeJS.Platform = process.platform): boolean {
  try {
    const st = fs.statSync(full)
    return st.isFile() && (platform === 'win32' || (st.mode & 0o111) !== 0)
  } catch (e) {
    if (platform !== 'win32' || (e as NodeJS.ErrnoException).code !== 'EACCES') return false
    try { return fs.lstatSync(full).isSymbolicLink() } catch { return false }
  }
}

/** Finds an executable on PATH (with PATHEXT on Windows), without a shell. */
export function findOnPath(name: string, env: Env, platform: NodeJS.Platform = process.platform): string | null {
  const p = platform === 'win32' ? path.win32 : path.posix
  const dirs = (env.PATH ?? env.Path ?? '').split(platform === 'win32' ? ';' : ':').filter(Boolean)
  const exts = platform === 'win32' && !p.extname(name)
    ? (env.PATHEXT ?? '.EXE').split(';').filter(Boolean)
    : ['']
  for (const dir of dirs) {
    for (const ext of exts) {
      const full = p.join(dir.replace(/^"(.*)"$/, '$1'), name + ext)
      if (isProgram(full, platform)) return full
    }
  }
  return null
}

/** Starts a program detached from the sidecar, with no shell. */
function startDetached(file: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, { detached: true, stdio: 'ignore', shell: false, windowsHide: false })
    child.once('error', reject)
    child.once('spawn', () => { child.unref(); resolve() })
  })
}
