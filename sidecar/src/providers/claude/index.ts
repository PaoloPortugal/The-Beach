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
import { BRIDGE_SERVER_NAME } from './bridge.ts'
import { BridgeServer } from './bridge-server.ts'
import { HookServer } from './hook-server.ts'
import { findStored, listStored, projectsDir, readHistory } from './store.ts'
import { hookSettings } from './hooks.ts'
import { ClaudeSession, HOOKS_CHECK_MS, type Launch } from './session.ts'

export {
  HISTORY_MAX, HOOKS_CHECK_MS, HOOKS_UNAVAILABLE, PERMISSION_MATCH_MS, STOP_REASON, TRANSCRIPT_CHECK_MS, TRANSCRIPTS_OFF,
} from './session.ts'

/**
 * How long a launched session may take to come up (the user answering the
 * startup prompts in its terminal). After that it's treated as gone: if the
 * user chose Exit at a startup prompt, nothing else would tell us.
 */
export const STARTUP_TIMEOUT_MS = 15 * 60 * 1000

/**
 * The terminal window's title. The name can come from a stored session's
 * transcript (anything the user once typed), and Windows Terminal parses its
 * own command line, so only plain printable text goes in, short.
 */
export function terminalTitle(name: string): string {
  const clean = name.replace(/[\u0000-\u001f\u007f-\u009f;"\\]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60)
  return `Claude Code - ${clean || 'session'}`
}

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
  /** For tests: a shorter startup timeout. */
  startupTimeoutMs?: number
  /** For tests: Claude Code's projects folder (stored sessions). */
  projectsDir?: string
  /** For tests: how long a world message waits for its first hook. */
  hooksCheckMs?: number
}


export class ClaudeProvider implements Provider {
  readonly id = 'claude'
  readonly name = 'Claude Code'
  private readonly opts: ClaudeOptions
  private readonly log: Log
  private readonly runDirs = new Set<string>()
  /** Sessions running now, by Claude's session id: not listed, not resumed twice. */
  private readonly live = new Set<string>()
  private bridges: BridgeServer | null = null
  private hooks: HookServer | null = null

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
    const name = options.project.name ?? path.basename(options.project.path)
    return this.start(host, {
      project: options.project, name, nativeId: crypto.randomUUID(), resume: false, history: [],
      ...(options.prompt ? { prompt: options.prompt } : {}),
    })
  }

  /**
   * Resumes a stored session (S04): `claude --resume <id>` in its project
   * folder, with our hooks and channel like a new one. Its chat so far comes
   * from the transcript.
   */
  async resume(host: SessionHost, nativeId: string): Promise<ProviderSession> {
    if (this.live.has(nativeId)) throw new CommandError('provider_error', 'That session is already open.')
    const stored = findStored(nativeId, this.opts.projectsDir ?? projectsDir())
    if (!stored) throw new CommandError('provider_error', 'That session wasn\'t found. Claude Code may have deleted it.')
    if (!path.isAbsolute(stored.project.path) || !fs.statSync(stored.project.path, { throwIfNoEntry: false })?.isDirectory()) {
      throw new CommandError('provider_error', `Its project folder no longer exists: ${stored.project.path}`)
    }
    return this.start(host, {
      project: stored.project, name: stored.title ?? path.basename(stored.project.path),
      nativeId, resume: true, history: readHistory(stored.file),
    })
  }

  /** Terminal sessions in Claude Code's store, newest first; the ones running here are left out. */
  async listStored(project?: string): Promise<StoredSession[]> {
    return listStored({
      dir: this.opts.projectsDir ?? projectsDir(),
      ...(project ? { project } : {}),
      exclude: this.live,
    }).map(({ file: _file, ...s }) => s)
  }

  private async start(host: SessionHost, o: {
    project: Project; name: string; nativeId: string; resume: boolean; history: HistoryMessage[]; prompt?: string
  }): Promise<ProviderSession> {
    const found = await this.find()
    const bridges = await this.bridgeServer()
    const hooks = await this.hookServer()
    const launch = this.prepare(o.nativeId)
    this.live.add(o.nativeId)
    const session: ClaudeSession = new ClaudeSession(host, launch, o.project, o.name, this.log,
      () => { this.forget(launch.runDir); this.live.delete(session.nativeId) },
      this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS, o.history, o.prompt, this.opts.hooksCheckMs ?? HOOKS_CHECK_MS)
    // After /clear the old conversation is stored, not running: it may be listed and resumed.
    session.onNativeId = (from, to) => { this.live.delete(from); this.live.add(to) }
    session.link = bridges.register(session.bridgeHandlers())
    session.hookLink = hooks.register({ onHook: (p, gone) => session.onHook(p, gone) })
    const settings = this.writeSettings(launch, hooks.url, session.hookLink.token)
    const mcpConfig = this.writeMcpConfig(launch, bridges.port, session.link.token)
    const args = [
      // A resumed session keeps its id and name.
      ...(o.resume ? ['--resume', o.nativeId] : ['--session-id', o.nativeId, '--name', o.name]),
      // Our hooks for this session only; the user's settings files are never edited.
      '--settings', settings,
      '--mcp-config', mcpConfig,
      // Custom channels need this while channels are a research preview;
      // Claude Code asks the user to confirm it in the terminal.
      '--dangerously-load-development-channels', `server:${BRIDGE_SERVER_NAME}`,
    ]
    try {
      await this.launch(launch, found.path, args, o.project.path, o.name)
    } catch (e) {
      session.dispose()
      throw e
    }
    this.log.info(`launched claude ${found.version} for session ${host.id}${o.resume ? ' (resumed)' : ''}`)
    session.startWaiting()
    return session
  }

  async shutdown(): Promise<void> {
    await this.bridges?.close()
    this.bridges = null
    await this.hooks?.close()
    this.hooks = null
    for (const dir of this.runDirs) fs.rmSync(dir, { recursive: true, force: true })
    this.runDirs.clear()
  }

  private async bridgeServer(): Promise<BridgeServer> {
    if (!this.bridges) this.bridges = new BridgeServer(this.log)
    await this.bridges.start()
    return this.bridges
  }

  private async hookServer(): Promise<HookServer> {
    if (!this.hooks) this.hooks = new HookServer(this.log)
    await this.hooks.start()
    return this.hooks
  }

  private forget(runDir: string) {
    fs.rmSync(runDir, { recursive: true, force: true })
    this.runDirs.delete(runDir)
  }

  /** The session's hooks, posting to our hook server with the session's token. */
  private writeSettings(launch: Launch, url: string, token: string): string {
    const file = path.join(launch.runDir, 'settings.json')
    fs.writeFileSync(file, JSON.stringify(hookSettings(url, token)), { mode: 0o600 })
    return file
  }

  /**
   * The MCP config that makes Claude Code start our bridge: this executable
   * in bridge mode, with the link's port and token in the bridge's own
   * environment (not Claude's: the bridge is Claude Code's child, so
   * commands Claude runs never see it).
   */
  private writeMcpConfig(launch: Launch, port: number, token: string): string {
    const [command, ...args] = (this.opts.selfCommand ?? selfCommand)('bridge', 'claude')
    const file = path.join(launch.runDir, 'mcp.json')
    fs.writeFileSync(file, JSON.stringify({
      mcpServers: {
        [BRIDGE_SERVER_NAME]: { command, args, env: { BRIDGE_PORT: String(port), BRIDGE_TOKEN: token } },
      },
    }), { mode: 0o600 })
    return file
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
  private prepare(nativeId: string): Launch {
    const runDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sidecar-session-'))
    fs.chmodSync(runDir, 0o700)
    this.runDirs.add(runDir)
    return { runDir, nativeId }
  }

  private async launch(launch: Launch, claude: string, args: string[], cwd: string, name: string) {
    const file = path.join(launch.runDir, 'launch.json')
    writeSessionFile(file, { command: claude, args, cwd, unsetEnv: ClaudeProvider.UNSET_ENV })
    const argv = (this.opts.selfCommand ?? selfCommand)('launch', file)
    const open = this.opts.openTerminal ?? openTerminal
    try {
      const used = await open(
        { argv, title: terminalTitle(name), runDir: launch.runDir },
        { ...(this.opts.terminal ? { preferred: this.opts.terminal } : {}) },
      )
      this.log.info(`opened ${used}`)
    } catch (e) {
      this.forget(launch.runDir)
      if (e instanceof TerminalError) {
        throw new CommandError('provider_error', 'No terminal window could be opened to run Claude Code.')
      }
      throw e
    }
  }
}
