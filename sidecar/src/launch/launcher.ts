// The launcher: the mode of the sidecar executable that a terminal runs
// (`<sidecar> launch <session file>`). It reads what to start from the
// session file, deletes the file, and starts that program in this terminal
// with an argument array, a clean environment and the given folder. So no
// terminal ever gets a command line built from text (NOTES.md -> Security
// rules -> No shell strings). Generic: the provider fills in the file.
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { cleanEnv } from './env.ts'

export const SESSION_FILE_VERSION = 1

export interface SessionFile {
  version: typeof SESSION_FILE_VERSION
  /** Absolute path of the program to start. */
  command: string
  args: string[]
  /** Absolute folder to start it in. */
  cwd: string
  /** Environment variables to remove (see env.ts). */
  unsetEnv: string[]
}

/** Writes a session file readable only by this user. */
export function writeSessionFile(file: string, s: Omit<SessionFile, 'version'>): void {
  const body: SessionFile = { version: SESSION_FILE_VERSION, ...s }
  fs.writeFileSync(file, JSON.stringify(body), { mode: 0o600 })
}

/** Reads, checks and deletes a session file. Throws with a message for the user. */
export function takeSessionFile(file: string): SessionFile {
  let raw: string
  try {
    raw = fs.readFileSync(file, 'utf8')
  } catch {
    throw new Error('This session was already started, or its launch file is missing.')
  } finally {
    // One use only; it names files that hold the session's tokens.
    fs.rmSync(file, { force: true })
  }
  let s: Partial<SessionFile>
  try { s = JSON.parse(raw) as Partial<SessionFile> } catch { throw new Error('The launch file is damaged.') }
  const strings = (a: unknown): a is string[] => Array.isArray(a) && a.every((x) => typeof x === 'string')
  if (s.version !== SESSION_FILE_VERSION || typeof s.command !== 'string' || typeof s.cwd !== 'string' ||
      !strings(s.args) || !strings(s.unsetEnv)) {
    throw new Error('The launch file is from another version of the game.')
  }
  if (!path.isAbsolute(s.command) || !fs.existsSync(s.command)) throw new Error(`Program not found: ${s.command}`)
  if (!path.isAbsolute(s.cwd) || !fs.statSync(s.cwd, { throwIfNoEntry: false })?.isDirectory()) {
    throw new Error(`Project folder not found: ${s.cwd}`)
  }
  return s as SessionFile
}

/** Runs the launcher mode. Resolves with the exit code to use. */
export async function runLauncher(args: string[]): Promise<number> {
  if (args.length !== 1) {
    return fail('The launcher needs exactly one argument, a session file.')
  }
  let s: SessionFile
  try { s = takeSessionFile(args[0]!) } catch (e) { return fail((e as Error).message) }

  // Ctrl+C in this terminal is for the program, which handles it itself; the
  // launcher must not die first.
  process.on('SIGINT', () => {})
  if (process.platform === 'win32') process.on('SIGBREAK', () => {})

  return new Promise<number>((resolve) => {
    const child = spawn(s.command, s.args, {
      cwd: s.cwd,
      env: cleanEnv(process.env, s.unsetEnv),
      stdio: 'inherit',
      shell: false,
      windowsHide: false,
    })
    child.once('error', (e) => { void fail(`Couldn't start ${s.command}: ${e.message}`).then(resolve) })
    child.once('exit', (code, signal) => resolve(code ?? (signal ? 1 : 0)))
  })
}

/** Shows a message and waits for Enter, so the terminal doesn't vanish unread. */
async function fail(message: string): Promise<number> {
  process.stderr.write(`\n${message}\n\nPress Enter to close this window.\n`)
  if (process.stdin.isTTY) {
    await new Promise<void>((resolve) => {
      process.stdin.resume()
      process.stdin.once('data', () => resolve())
      process.stdin.once('end', () => resolve())
    })
  }
  return 1
}
