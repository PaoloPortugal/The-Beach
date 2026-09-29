// Finding the user's own `claude` (NOTES.md -> Architecture -> Platforms).
// Apps started from the macOS Dock or a Linux menu don't get the shell's
// PATH, so the documented install locations are checked too. On Windows only
// a real claude.exe is used: npm's claude.cmd wrapper needs a shell.
import fs from 'node:fs'
import path from 'node:path'
import os from 'node:os'
import { execFile } from 'node:child_process'
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

/**
 * Finds a working claude of at least MIN_VERSION. `override` is a path the
 * user set by hand. Throws ClaudeNotFound with a message for the player.
 */
export async function findClaude(opts: {
  env: Env
  cleanEnv: Record<string, string>
  override?: string
  platform?: NodeJS.Platform
  home?: string
}): Promise<FoundClaude> {
  const platform = opts.platform ?? process.platform
  const list = opts.override ? [opts.override] : candidates(platform, opts.env, opts.home ?? os.homedir())
  let tooOld: string | null = null
  for (const file of list) {
    if (!fs.statSync(file, { throwIfNoEntry: false })?.isFile()) continue
    const version = await readVersion(file, opts.cleanEnv)
    if (!version) continue
    if (!versionAtLeast(version, MIN_VERSION)) { tooOld = version; continue }
    return { path: file, version }
  }
  if (tooOld) {
    throw new ClaudeNotFound(`Claude Code ${tooOld} is too old; version ${MIN_VERSION} or newer is needed. Run \`claude update\`.`)
  }
  throw new ClaudeNotFound(platform === 'win32'
    ? 'Claude Code for Windows wasn\'t found. Install it from code.claude.com (the Windows version, not inside WSL) and sign in once in a terminal.'
    : 'Claude Code wasn\'t found. Install it from code.claude.com and sign in once in a terminal.')
}
