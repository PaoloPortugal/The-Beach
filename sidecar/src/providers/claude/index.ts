// The Claude provider (NOTES.md -> S02): the only place Claude-specific names
// may appear in the sidecar. It launches the user's own, unmodified `claude`
// in a terminal and never reads, stores or passes on Claude credentials.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import type { Provider, ProviderSession, SessionHost } from '../../provider.ts'
import { CommandError } from '../../provider.ts'
import type { HistoryMessage, Project, StoredSession } from '../../protocol.ts'
import { cleanEnv, STORE_CLIENT_VARIABLES } from '../../launch/env.ts'
import { openTerminal, TerminalError } from '../../launch/terminal.ts'
import { writeSessionFile } from '../../launch/launcher.ts'
import { selfCommand } from '../../launch/self.ts'
import type { Log } from '../../log.ts'
import { stderrLog } from '../../log.ts'
import { CLAUDE_SESSION_MARKER_PREFIXES, CLAUDE_SESSION_MARKERS } from './env.ts'
import { ClaudeNotFound, findClaude, type FoundClaude } from './find.ts'

export interface ClaudeOptions {
  log?: Log
  /** How to start this sidecar in another mode; tests and dev tools override it. */
  selfCommand?: (mode: string, ...args: string[]) => string[]
  /** A claude executable chosen by hand (a user setting, later). */
  claudePath?: string
  /** A terminal id to try first (a user setting, later). */
  terminal?: string
  /** For tests: replaces opening a real terminal. */
  openTerminal?: typeof openTerminal
  /** For tests: replaces finding claude. */
  findClaude?: () => Promise<FoundClaude>
}

/** Everything the launched claude and our side share for one session. */
interface Launch {
  runDir: string
  nativeId: string
}

export class ClaudeProvider implements Provider {
  readonly id = 'claude'
  readonly name = 'Claude Code'
  private readonly opts: ClaudeOptions
  private readonly log: Log
  private readonly runDirs = new Set<string>()

  constructor(opts: ClaudeOptions = {}) {
    this.opts = opts
    this.log = opts.log ?? stderrLog
  }

  /** Variables removed from every launched process's environment. */
  static readonly UNSET_ENV = {
    names: [...CLAUDE_SESSION_MARKERS, ...STORE_CLIENT_VARIABLES],
    prefixes: [...CLAUDE_SESSION_MARKER_PREFIXES],
  }

  async create(host: SessionHost, options: { project: Project; prompt?: string }): Promise<ProviderSession> {
    const found = await this.find()
    const launch = this.prepare()
    const name = options.project.name ?? path.basename(options.project.path)
    const args = ['--session-id', launch.nativeId, '--name', name]
    await this.launch(launch, found.path, args, options.project.path, name)
    this.log.info(`launched claude ${found.version} for session ${host.id}`)
    return new ClaudeSession(host, launch)
  }

  async resume(): Promise<ProviderSession> {
    throw new CommandError('not_supported', 'resuming sessions comes later (S04)')
  }

  async listStored(): Promise<StoredSession[]> {
    return []
  }

  async shutdown(): Promise<void> {
    for (const dir of this.runDirs) fs.rmSync(dir, { recursive: true, force: true })
    this.runDirs.clear()
  }

  private async find(): Promise<FoundClaude> {
    try {
      if (this.opts.findClaude) return await this.opts.findClaude()
      return await findClaude({
        env: process.env,
        cleanEnv: cleanEnv(process.env, ClaudeProvider.UNSET_ENV),
        ...(this.opts.claudePath ? { override: this.opts.claudePath } : {}),
      })
    } catch (e) {
      if (e instanceof ClaudeNotFound) throw new CommandError('provider_error', e.message)
      throw e
    }
  }

  /** A private folder for this session's launch file, settings and bridge config. */
  private prepare(): Launch {
    const runDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sidecar-session-'))
    fs.chmodSync(runDir, 0o700)
    this.runDirs.add(runDir)
    return { runDir, nativeId: crypto.randomUUID() }
  }

  private async launch(launch: Launch, claude: string, args: string[], cwd: string, name: string) {
    const file = path.join(launch.runDir, 'launch.json')
    writeSessionFile(file, { command: claude, args, cwd, unsetEnv: ClaudeProvider.UNSET_ENV })
    const argv = (this.opts.selfCommand ?? selfCommand)('launch', file)
    const open = this.opts.openTerminal ?? openTerminal
    try {
      const used = await open(
        { argv, title: `Claude Code - ${name}`.replace(/[;"]/g, ' '), runDir: launch.runDir },
        { ...(this.opts.terminal ? { preferred: this.opts.terminal } : {}) },
      )
      this.log.info(`opened ${used}`)
    } catch (e) {
      fs.rmSync(launch.runDir, { recursive: true, force: true })
      this.runDirs.delete(launch.runDir)
      if (e instanceof TerminalError) {
        throw new CommandError('provider_error', 'No terminal window could be opened to run Claude Code.')
      }
      throw e
    }
  }
}

class ClaudeSession implements ProviderSession {
  readonly host: SessionHost
  readonly launch: Launch

  constructor(host: SessionHost, launch: Launch) {
    this.host = host
    this.launch = launch
  }

  async sendMessage(): Promise<void> {
    throw new CommandError('not_supported', 'not built yet')
  }
  async respondPermission(): Promise<void> {
    throw new CommandError('not_supported', 'not built yet')
  }
  async end(): Promise<void> {
    // No documented way to close Claude Code from outside (S05 decides).
    throw new CommandError('not_supported', 'end the session with /exit in its terminal')
  }
  async getHistory(): Promise<HistoryMessage[]> {
    return []
  }
}
