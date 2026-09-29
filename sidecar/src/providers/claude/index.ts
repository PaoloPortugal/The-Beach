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
import { BridgeServer, type BridgeLink } from './bridge-server.ts'
import { HookServer, type HookLink, type HookPayload } from './hook-server.ts'
import { HookTranslator, hookSettings, MAIN } from './hooks.ts'

/**
 * How long a launched session may take to come up (the user answering the
 * startup prompts in its terminal). After that it's treated as gone: if the
 * user chose Exit at a startup prompt, nothing else would tell us.
 */
export const STARTUP_TIMEOUT_MS = 15 * 60 * 1000

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
    const found = await this.find()
    const bridges = await this.bridgeServer()
    const hooks = await this.hookServer()
    const launch = this.prepare()
    const name = options.project.name ?? path.basename(options.project.path)
    const session = new ClaudeSession(host, launch, options.project, name, this.log,
      () => this.forget(launch.runDir), this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS)
    session.link = bridges.register(session.bridgeHandlers())
    session.hookLink = hooks.register({ onHook: (p) => session.onHook(p) })
    const settings = this.writeSettings(launch, hooks.url, session.hookLink.token)
    const mcpConfig = this.writeMcpConfig(launch, bridges.port, session.link.token)
    const args = [
      '--session-id', launch.nativeId,
      '--name', name,
      // Our hooks for this session only; the user's settings files are never edited.
      '--settings', settings,
      '--mcp-config', mcpConfig,
      // Custom channels need this while channels are a research preview;
      // Claude Code asks the user to confirm it in the terminal.
      '--dangerously-load-development-channels', `server:${BRIDGE_SERVER_NAME}`,
    ]
    try {
      await this.launch(launch, found.path, args, options.project.path, name)
    } catch (e) {
      session.dispose()
      throw e
    }
    this.log.info(`launched claude ${found.version} for session ${host.id}`)
    session.startWaiting()
    return session
  }

  async resume(): Promise<ProviderSession> {
    throw new CommandError('not_supported', 'resuming sessions comes later (S04)')
  }

  async listStored(): Promise<StoredSession[]> {
    return []
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
      this.forget(launch.runDir)
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
  link: BridgeLink | null = null
  hookLink: HookLink | null = null
  private readonly project: Project
  private readonly name: string
  private readonly log: Log
  private readonly cleanup: () => void
  private readonly startupTimeoutMs: number
  private launchedAt = 0
  private startupTimer: NodeJS.Timeout | null = null
  private disposed = false
  private readonly translator: HookTranslator

  constructor(host: SessionHost, launch: Launch, project: Project, name: string, log: Log,
    cleanup: () => void, startupTimeoutMs: number) {
    this.host = host
    this.launch = launch
    this.project = project
    this.name = name
    this.log = log
    this.cleanup = cleanup
    this.startupTimeoutMs = startupTimeoutMs
    this.translator = new HookTranslator(project.path)
  }

  bridgeHandlers() {
    return {
      onReady: () => this.onReady(),
      onPermissionRequest: () => { /* the permission relay comes with the hooks */ },
      onClose: () => this.onGone('the bridge closed'),
    }
  }

  /** Called once the terminal is open: the user now answers the startup prompts. */
  startWaiting() {
    this.launchedAt = Date.now()
    this.startupTimer = setTimeout(() => this.onGone('it never came up'), this.startupTimeoutMs)
    this.startupTimer.unref()
  }

  private onReady() {
    if (this.disposed || this.host.ended) return
    if (!this.startupTimer) return
    clearTimeout(this.startupTimer)
    this.startupTimer = null
    // Timing for NOTES.md -> S02 -> Starting up (checkpoint 1 measurements).
    this.log.info(`session ${this.host.id} came up ${Date.now() - this.launchedAt} ms after launch`)
    this.host.announce({
      native_id: this.launch.nativeId,
      project: this.project,
      title: this.name,
      capabilities: {},
      extensions: [],
      agents: [{ agent: MAIN, role: 'orchestrator', parent: null, name: 'Claude', state: 'idle', reason: null }],
    })
  }

  /** One hook from this session's Claude Code. Reports only: never a decision. */
  onHook(p: HookPayload): void {
    if (this.disposed || this.host.ended) return
    // Hooks only fire once Claude Code is past its startup dialogs, so a
    // hook arriving before the bridge's ready also means the session is up.
    if (this.startupTimer) this.onReady()
    for (const event of this.translator.translate(p)) this.host.emit(event)
  }

  /** Claude Code exited, or never came up. */
  private onGone(why: string) {
    if (this.disposed) return
    this.log.info(`session ${this.host.id} is gone: ${why}`)
    this.dispose()
    this.host.end('exited')
  }

  dispose() {
    if (this.disposed) return
    this.disposed = true
    if (this.startupTimer) clearTimeout(this.startupTimer)
    this.link?.unregister()
    this.hookLink?.unregister()
    this.cleanup()
  }

  async sendMessage(text: string): Promise<void> {
    if (!this.link?.send({ type: 'chat', text })) {
      throw new CommandError('provider_error', 'The session is not connected.')
    }
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
