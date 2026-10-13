// Where the sidecar keeps what must outlive it: the run folders of sessions
// still running after the game quits, so the next start can reattach to them
// (NOTES.md -> S07). The folder is named after the project's working name,
// in this one constant (NOTES.md -> Conventions -> Renaming the project).
import os from 'node:os'
import path from 'node:path'

export const APP_FOLDER = 'The Beach'
export const SESSIONS_FOLDER = 'agent-sessions'

/**
 * The user's own application data folder for this platform: %LOCALAPPDATA%
 * on Windows, ~/Library/Application Support on macOS, $XDG_STATE_HOME (or
 * ~/.local/state) elsewhere. Not the temp folder: Windows Storage Sense and
 * tmp cleaners can delete a long-running session's files there.
 */
export function appDataDir(
  platform: NodeJS.Platform = process.platform, env: NodeJS.ProcessEnv = process.env, home = os.homedir(),
): string {
  if (platform === 'win32') {
    const local = env.LOCALAPPDATA && path.win32.isAbsolute(env.LOCALAPPDATA) ? env.LOCALAPPDATA : path.win32.join(home, 'AppData', 'Local')
    return path.win32.join(local, APP_FOLDER)
  }
  if (platform === 'darwin') return path.posix.join(home, 'Library', 'Application Support', APP_FOLDER)
  // XDG: a relative path is invalid and must be ignored.
  const state = env.XDG_STATE_HOME && path.posix.isAbsolute(env.XDG_STATE_HOME) ? env.XDG_STATE_HOME : path.posix.join(home, '.local', 'state')
  return path.posix.join(state, APP_FOLDER)
}

/** The folder holding one run folder per session the sidecar launched. */
export function sessionsDir(
  platform: NodeJS.Platform = process.platform, env: NodeJS.ProcessEnv = process.env, home = os.homedir(),
): string {
  return (platform === 'win32' ? path.win32 : path.posix).join(appDataDir(platform, env, home), SESSIONS_FOLDER)
}
