// The Claude provider (NOTES.md -> S02): the only place Claude-specific names
// may appear in the sidecar. It launches the user's own, unmodified `claude`
// in a terminal and never reads, stores or passes on Claude credentials.
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import type { Adopt, Provider, ProviderSession, SessionHost } from '../../provider.ts'
import { CommandError } from '../../provider.ts'
import type { History, Launch as LaunchChoice, Project, StoredSession } from '../../protocol.ts'
import { LAUNCH_OPTIONS, launchArgs } from './launch-options.ts'
import { cleanEnv, STORE_CLIENT_VARIABLES } from '../../launch/env.ts'
import { openTerminal, TerminalError } from '../../launch/terminal.ts'
import { launcherPidFile, processAlive, programPidFile, readPidFile, writeSessionFile } from '../../launch/launcher.ts'
import { writeRelayFile } from '../../launch/relay.ts'
import { selfCommand } from '../../launch/self.ts'
import { sessionsDir, TEST_SESSIONS_DIR } from '../../launch/app-data.ts'
import type { Log } from '../../log.ts'
import { stderrLog } from '../../log.ts'
import { CLAUDE_SESSION_MARKER_PREFIXES, CLAUDE_SESSION_MARKERS } from './env.ts'
import { ClaudeNotFound, findClaude, type FoundClaude } from './find.ts'
import { runningSessions, type AgentEntry, type Running } from './running.ts'
import { BRIDGE_SERVER_NAME, writeBridgeFile } from './bridge.ts'
import { BridgeServer } from './bridge-server.ts'
import { HookServer, type HookLink } from './hook-server.ts'
import {
  HOLDER_FILE, readHookPort, readRunRecord, RUN_DIR_NAME, writeHolder, writeHookPort, writeRunRecord, type RunRecord,
} from './run-folder.ts'
import { findStored, listStored, NO_TITLES, projectsDir, readConversation, readTitles, samePath, StoredCache, type StoredInfo, type Titles } from './store.ts'
import { hookSettings } from './hooks.ts'
import { ourStatusLine } from './statusline.ts'
import type { UsageCounter } from './usage.ts'
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
 * How often `claude agents --json` is asked about read-only sessions (S07):
 * which conversation each is in, and whether it waits on the user. Each
 * time costs about 0.8 s of a `claude` process, so only while there are any.
 */
export const AGENTS_POLL_MS = 5000

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
  /** For tests: the environment the user's settings are found from (CLAUDE_CONFIG_DIR). */
  env?: NodeJS.ProcessEnv
  /** For tests: replaces running `claude agents --json`; gets the `claude` found and the environment it would run with. */
  runningSessions?: (claude: string, env: Record<string, string>) => Promise<Running>
  /**
   * The folder of run folders (S07); the user's app data folder otherwise.
   * Every sidecar test passes a temporary one, and the Godot suites set
   * TEST_SESSIONS_DIR (launch/app-data.ts), so none touches the real folder.
   */
  sessionsDir?: string
  /** For tests: how often read-only sessions are asked about (AGENTS_POLL_MS). */
  agentsPollMs?: number
}

/** A run folder's files (S07). The bridge file holds where the bridge connects. */
const BRIDGE_FILE = 'bridge.json'
const RELAY_FILE = 'relay.json'
const STATUS_FILE = 'status.json'

/** A run folder found at start whose session may still run. */
interface Found { runDir: string; record: RunRecord; program: number }

export class ClaudeProvider implements Provider {
  readonly id = 'claude'
  readonly name = 'Claude Code'
  readonly launchOptions = LAUNCH_OPTIONS
  private readonly opts: ClaudeOptions
  private readonly log: Log
  /** Sessions running now, by Claude's session id: not listed, not resumed twice. */
  private readonly live = new Set<string>()
  /** The stored sessions' listing, kept between calls (S04). */
  private readonly stored = new StoredCache()
  /** The `claude` the last find() gave, for asking which sessions run (running()). */
  private foundPath: string | undefined
  private bridges: BridgeServer | null = null
  private hooks: HookServer | null = null
  /** Read-only sessions (S07) by their `claude`'s process id, asked about together. */
  private readonly watched = new Map<number, ClaudeSession>()
  private watchTimer: NodeJS.Timeout | null = null
  private asking = false

  constructor(opts: ClaudeOptions = {}) {
    this.opts = opts
    this.log = opts.log ?? stderrLog
  }

  /** Variables removed from every launched process's environment. */
  static readonly UNSET_ENV = {
    names: [...CLAUDE_SESSION_MARKERS, ...STORE_CLIENT_VARIABLES],
    prefixes: [...CLAUDE_SESSION_MARKER_PREFIXES],
  }

  async create(host: SessionHost, options: { project: Project; prompt?: string; launch?: LaunchChoice }): Promise<ProviderSession> {
    // Named by Claude Code as it goes (no --name): NOTES.md -> S02 -> Titles.
    const name = options.project.name ?? path.basename(options.project.path)
    return this.start(host, {
      project: options.project, name, titles: NO_TITLES, nativeId: crypto.randomUUID(), resume: false,
      history: { messages: [], tools: [] }, usage: null, launch: options.launch,
      ...(options.prompt ? { prompt: options.prompt } : {}),
    })
  }

  /**
   * Resumes a stored session (S04): `claude --resume <id>` in its project
   * folder, with our hooks and channel like a new one. Its chat so far comes
   * from the transcript.
   */
  async resume(host: SessionHost, nativeId: string, launch?: LaunchChoice): Promise<ProviderSession> {
    if (this.live.has(nativeId)) throw new CommandError('provider_error', 'That session is already open.')
    // Running in a terminal the game doesn't follow: resuming it would run the conversation twice.
    if ((await this.running()).has(nativeId.toLowerCase())) {
      throw new CommandError('provider_error',
        'That session is still running in a terminal. Continue it there, or type /exit in it and resume it again.')
    }
    const stored = findStored(nativeId, this.opts.projectsDir ?? projectsDir())
    if (!stored) throw new CommandError('provider_error', 'That session wasn\'t found. Claude Code may have deleted it.')
    if (!path.isAbsolute(stored.project.path) || !fs.statSync(stored.project.path, { throwIfNoEntry: false })?.isDirectory()) {
      throw new CommandError('provider_error', `Its project folder no longer exists: ${stored.project.path}`)
    }
    const read = readConversation(stored.file)
    return this.start(host, {
      project: stored.project, name: stored.title ?? path.basename(stored.project.path), titles: readTitles(stored.file),
      nativeId, resume: true, history: read.history, usage: read.usage, launch,
    })
  }

  /**
   * Terminal sessions in Claude Code's store, newest first. The ones running
   * here are left out, and so are the ones Claude Code says are running
   * anywhere else (S04 -> Sessions running elsewhere), asked meanwhile.
   */
  async listStored(project?: string): Promise<StoredSession[]> {
    const [running, list] = await Promise.all([this.running(), listStored({
      dir: this.opts.projectsDir ?? projectsDir(),
      ...(project ? { project } : {}),
      exclude: this.live,
      cache: this.stored,
    })])
    return list.filter((s) => !running.has(s.native_id.toLowerCase())).map(({ file: _file, ...s }) => s)
  }

  /** Claude's session ids running anywhere on this machine; empty when that can't be known. */
  private async running(): Promise<Set<string>> {
    const answer = await this.askRunning()
    if ('none' in answer) {
      this.log.info(`can't tell which sessions run elsewhere: ${answer.none}`)
      return new Set()
    }
    return answer.ids
  }

  /** `claude agents --json`'s answer, or why there's none. */
  private async askRunning(): Promise<Running> {
    // The `claude` found last, so a listing doesn't run `--version` first each time; a launch still finds it afresh.
    let claude = this.foundPath
    if (!claude) {
      try { claude = (await this.find()).path } catch (e) {
        return { none: e instanceof Error ? e.message : String(e) }
      }
    }
    return (this.opts.runningSessions ?? runningSessions)(claude, cleanEnv(process.env, ClaudeProvider.UNSET_ENV))
  }

  private async start(host: SessionHost, o: {
    /** name: the terminal window's title. */
    project: Project; name: string; titles: Titles; nativeId: string; resume: boolean; history: History
    /** A resumed conversation's usage so far (C08). */
    usage: UsageCounter | null; prompt?: string
    /** The user's launch choices (C12). */
    launch: LaunchChoice | undefined
  }): Promise<ProviderSession> {
    const found = await this.find()
    const bridges = await this.bridgeServer()
    const hooks = await this.hookServer()
    const launch = this.prepare(o.nativeId)
    this.live.add(o.nativeId)
    const session: ClaudeSession = new ClaudeSession(host, launch, o.project, o.titles, this.log,
      () => { this.forget(launch.runDir); this.live.delete(session.nativeId) },
      this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS, o.history, o.prompt, this.opts.hooksCheckMs ?? HOOKS_CHECK_MS,
      o.usage ?? undefined)
    session.link = bridges.register(session.bridgeHandlers())
    session.hookLink = hooks.register({ onHook: (p, gone) => session.onHook(p, gone), onStatus: (p) => session.onStatus(p) })
    // What a later sidecar needs to take the session back (S07).
    const record = {
      native_id: o.nativeId, project: o.project, hook_port: hooks.port, hook_token: session.hookLink.token,
      started_at: new Date().toISOString(),
    }
    this.followIds(session, record)
    try {
      writeRunRecord(launch.runDir, record)
      writeBridgeFile(path.join(launch.runDir, BRIDGE_FILE), bridges.port, session.link)
    } catch (e) {
      session.dispose()
      throw e
    }
    const settings = await this.writeSettings(launch, hooks, session.hookLink.token, o.project.path, host.id)
    const mcpConfig = this.writeMcpConfig(launch)
    const args = [
      // A resumed session keeps its id and name; a new one is named by Claude Code.
      ...(o.resume ? ['--resume', o.nativeId] : ['--session-id', o.nativeId]),
      // Our hooks for this session only; the user's settings files are never edited.
      '--settings', settings,
      '--mcp-config', mcpConfig,
      // Custom channels need this while channels are a research preview;
      // Claude Code asks the user to confirm it in the terminal.
      '--dangerously-load-development-channels', `server:${BRIDGE_SERVER_NAME}`,
      // The model, effort and mode the user picked (C12); none: Claude Code's own.
      ...launchArgs(o.launch),
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

  /**
   * Run folders stay: sessions still running need them, and the next start
   * takes those back (S07). Each is deleted once its session has ended.
   */
  async shutdown(): Promise<void> {
    if (this.watchTimer) clearInterval(this.watchTimer)
    this.watchTimer = null
    await this.bridges?.close()
    this.bridges = null
    await this.hooks?.close()
    this.hooks = null
  }

  /**
   * Takes back the sessions launched before the sidecar last stopped and
   * still running (S07). The hook server comes first, on the kept port,
   * before anything else listens. Then each run folder found by listing
   * (never a path read from a file) and not held by another sidecar still
   * running (a second game): its launcher's process must be alive,
   * and, where `claude agents --json` answers, Claude Code must list its
   * program's process, so a reused process id alone doesn't count. Folders
   * of sessions gone are deleted; ones that can't be read are left alone.
   */
  async restore(adopt: Adopt): Promise<void> {
    const hooks = await this.hookServer()
    const root = this.sessionsRoot()
    if (!this.opts.sessionsDir && root === process.env[TEST_SESSIONS_DIR]) this.log.info(`sessions folder: the tests' own (${TEST_SESSIONS_DIR})`)
    let names: string[]
    try {
      names = fs.readdirSync(root, { withFileTypes: true })
        .filter((d) => d.isDirectory() && RUN_DIR_NAME.test(d.name)).map((d) => d.name)
    } catch {
      return
    }
    const found: Found[] = []
    for (const name of names) {
      const runDir = path.join(root, name)
      // Held by another sidecar still running (a second game, or one just launching it): not ours to touch.
      const holder = readPidFile(path.join(runDir, HOLDER_FILE))
      if (holder !== null && holder !== process.pid && processAlive(holder)) {
        this.log.info(`run folder ${name}: held by another running game; left alone`)
        continue
      }
      const launcher = readPidFile(launcherPidFile(runDir))
      if (launcher === null) {
        // A terminal that never ran the launcher: gone, unless it may still be opening.
        const age = Date.now() - (fs.statSync(runDir, { throwIfNoEntry: false })?.mtimeMs ?? 0)
        if (age > (this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS)) this.remove(runDir, 'its terminal never started')
        continue
      }
      if (!processAlive(launcher)) {
        this.remove(runDir, 'its session ended')
        continue
      }
      const record = readRunRecord(runDir)
      const program = readPidFile(programPidFile(runDir))
      if (!record || program === null) {
        this.log.info(`run folder ${name}: ${record ? 'its program never started' : 'no usable record'}; left alone`)
        continue
      }
      found.push({ runDir, record, program })
    }
    if (found.length === 0) return

    const answer = await this.askRunning()
    const agents = 'none' in answer ? null : answer.agents ?? null
    if (agents === null) {
      this.log.info(`can't ask Claude Code which sessions run (${'none' in answer ? answer.none : 'no entries'}); trusting their launchers`)
    }
    const bridges = await this.bridgeServer()
    for (const f of found) {
      const entry = agents === null ? null : agents.find((a) => a.pid === f.program) ?? null
      if (agents !== null && entry === null) {
        this.remove(f.runDir, 'Claude Code no longer lists it')
        continue
      }
      try {
        this.takeOver(adopt, hooks, bridges, f, entry)
      } catch (e) {
        this.log.error(`couldn't take back the session in ${path.basename(f.runDir)}: ${e instanceof Error ? e.message : String(e)}`)
      }
    }
  }

  /** Takes back one running session (see restore). */
  private takeOver(adopt: Adopt, hooks: HookServer, bridges: BridgeServer, f: Found, entry: AgentEntry | null) {
    // Claude Code's own id when it answered: /clear or /resume while the game was closed is followed.
    const nativeId = entry?.sessionId ?? f.record.native_id
    if (this.live.has(nativeId)) return
    // The hooks go to the port it was launched with: ours only if we got it
    // back. Else read-only: another program has its port, and its token.
    const readOnly = f.record.hook_port !== hooks.port
    // Read-only, its folder is taken from this transcript: only this project's.
    const stored = readOnly ? this.findOwn(nativeId, f.record.project.path) : findStored(nativeId, this.projects())
    const read = stored ? readConversation(stored.file) : null
    const launch: Launch = { runDir: f.runDir, nativeId }
    let session: ClaudeSession | null = null
    // Read-only: neither its hook token nor a bridge slot is taken, and its
    // relay files are left alone, so nothing posted with its token is
    // acted on and its bridge isn't offered a way back.
    const hookLink: HookLink | null = readOnly ? null : hooks.adopt(f.record.hook_token, {
      onHook: (p, gone) => session?.onHook(p, gone), onStatus: (p) => session?.onStatus(p),
    })
    if (!readOnly && !hookLink) throw new Error('its hook token is in use already')
    // The bridge's slot, before the session: every file is written before
    // it's adopted, so a failure leaves nothing half taken.
    const link = readOnly ? null : bridges.register({
      onReady: () => session?.bridgeHandlers().onReady(),
      onPermissionRequest: (p) => session?.bridgeHandlers().onPermissionRequest(p),
      onClose: () => session?.bridgeHandlers().onClose(),
    })
    try {
      writeHolder(f.runDir)
      if (link) {
        // The relays read their files on every run: they follow us, with the old token.
        for (const [file, url] of [[RELAY_FILE, hooks.url], [STATUS_FILE, hooks.statusUrl]] as const) {
          const at = path.join(f.runDir, file)
          if (fs.existsSync(at)) writeRelayFile(at, { url, token: f.record.hook_token })
        }
        // A fresh one-time token: the bridge, retrying, reads it and connects.
        writeBridgeFile(path.join(f.runDir, BRIDGE_FILE), bridges.port, link)
      }
      adopt((host) => {
        session = new ClaudeSession(host, launch, f.record.project, stored ? readTitles(stored.file) : NO_TITLES, this.log,
          () => { this.forget(f.runDir); this.live.delete(session?.nativeId ?? nativeId); this.unwatch(f.program) },
          this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS, read?.history, undefined, this.opts.hooksCheckMs ?? HOOKS_CHECK_MS,
          read?.usage)
        return session
      })
    } catch (e) {
      hookLink?.unregister()
      link?.unregister()
      throw e
    }
    const s = session as unknown as ClaudeSession
    this.live.add(nativeId)
    s.hookLink = hookLink
    s.link = link
    const record = { native_id: nativeId, project: f.record.project, hook_port: f.record.hook_port, hook_token: f.record.hook_token, started_at: f.record.started_at }
    this.followIds(s, record)
    if (nativeId !== f.record.native_id) this.rewriteRecord(f.runDir, record)
    const status = entry?.status
    s.restored({
      state: status === 'busy' ? 'working' : status === 'waiting' ? 'waiting' : 'idle',
      reason: status === 'waiting' ? 'input' : null,
      startedAt: f.record.started_at,
      transcript: stored?.file ?? null,
      readOnly,
      findTranscript: (id) => this.findOwn(id, f.record.project.path)?.file ?? null,
    })
    if (readOnly) this.watch(f.program, s)
    this.log.info(`took back session ${s.host.id}${readOnly ? ' (its hook port was taken: read-only)' : ''}`)
  }

  /** Asks `claude agents` about a read-only session from now on, with the others (see AGENTS_POLL_MS). */
  private watch(program: number, session: ClaudeSession) {
    this.watched.set(program, session)
    if (this.watchTimer) return
    this.watchTimer = setInterval(() => void this.askWatched(), this.opts.agentsPollMs ?? AGENTS_POLL_MS)
    this.watchTimer.unref()
  }

  private unwatch(program: number) {
    if (!this.watched.delete(program) || this.watched.size > 0 || !this.watchTimer) return
    clearInterval(this.watchTimer)
    this.watchTimer = null
  }

  /** One `claude agents` at a time; each read-only session gets its own entry, or null. */
  private async askWatched() {
    if (this.asking) return
    this.asking = true
    try {
      const answer = await this.askRunning()
      const agents = 'none' in answer ? null : answer.agents ?? null
      for (const [program, session] of [...this.watched]) session.onAgent(agents?.find((a) => a.pid === program) ?? null)
    } finally {
      this.asking = false
    }
  }

  /**
   * Keeps the live ids and the run folder's record with the conversation the
   * session follows. After /clear the old conversation is stored, not
   * running: it may be listed and resumed.
   */
  private followIds(session: ClaudeSession, record: Omit<RunRecord, 'version'>) {
    session.onNativeId = (from, to) => {
      this.live.delete(from)
      this.live.add(to)
      record.native_id = to
      this.rewriteRecord(session.launch.runDir, record)
    }
  }

  private rewriteRecord(runDir: string, record: Omit<RunRecord, 'version'>) {
    try {
      writeRunRecord(runDir, record)
    } catch (e) {
      this.log.warn(`couldn't update a session's record: ${e instanceof Error ? e.message : String(e)}`)
    }
  }

  /** Deletes a run folder found by listing (restore), never one named in a file. */
  private remove(runDir: string, why: string) {
    this.log.info(`removed run folder ${path.basename(runDir)}: ${why}`)
    fs.rmSync(runDir, { recursive: true, force: true })
  }

  private async bridgeServer(): Promise<BridgeServer> {
    if (!this.bridges) this.bridges = new BridgeServer(this.log)
    await this.bridges.start()
    return this.bridges
  }

  /**
   * The hook server, on the kept port (S07): sessions launched before keep
   * posting their hooks to it. The kept port is only written when none is
   * kept yet, so a fallback port (the kept one was taken) never replaces it.
   */
  private async hookServer(): Promise<HookServer> {
    if (!this.hooks) {
      this.hooks = new HookServer(this.log)
      const root = this.sessionsRoot()
      const kept = readHookPort(root)
      const port = await this.hooks.start(kept ?? undefined)
      if (kept === null) {
        try {
          fs.mkdirSync(root, { recursive: true, mode: 0o700 })
          writeHookPort(root, port)
        } catch (e) {
          this.log.warn(`couldn't keep the hook port: ${e instanceof Error ? e.message : String(e)}`)
        }
      }
    }
    return this.hooks
  }

  /** A stored conversation's transcript, only if it's this project's (its cwd). */
  private findOwn(nativeId: string, project: string): StoredInfo | null {
    return findStored(nativeId, this.projects(), (s) => sameFolder(s.project.path, project))
  }

  private projects(): string {
    return this.opts.projectsDir ?? projectsDir()
  }

  private sessionsRoot(): string {
    return this.opts.sessionsDir ?? sessionsDir()
  }

  private forget(runDir: string) {
    fs.rmSync(runDir, { recursive: true, force: true })
  }

  /**
   * The session's hooks, posting to our hook server with the session's
   * token. SessionStart runs this executable in relay mode, which finds the
   * URL and token in a relay file, so they're never on a command line.
   * The status line (C08) runs it in statusline mode with a relay file of
   * its own, unless the user has a status line of their own, or the
   * command string can't be made safe (then the session counts from its
   * transcript only).
   */
  private async writeSettings(launch: Launch, hooks: HookServer, token: string, project: string, id: string): Promise<string> {
    const self = this.opts.selfCommand ?? selfCommand
    const relayFile = path.join(launch.runDir, RELAY_FILE)
    writeRelayFile(relayFile, { url: hooks.url, token })
    const statusFile = path.join(launch.runDir, STATUS_FILE)
    writeRelayFile(statusFile, { url: hooks.statusUrl, token })
    const ours = await ourStatusLine(project, self('statusline', statusFile), this.opts.env ? { env: this.opts.env } : {})
    if ('none' in ours) this.log.info(`session ${id}: no status line of ours: ${ours.none}`)
    const file = path.join(launch.runDir, 'settings.json')
    fs.writeFileSync(file, JSON.stringify(hookSettings(hooks.url, token, self('relay', relayFile),
      'statusLine' in ours ? ours.statusLine : undefined)), { mode: 0o600 })
    return file
  }

  /**
   * The MCP config that makes Claude Code start our bridge: this executable
   * in bridge mode, with the path of its bridge file (where to connect, and
   * a one-time token, rewritten by each sidecar; S07) in the bridge's own
   * environment (not Claude's: the bridge is Claude Code's child, so
   * commands Claude runs never see it).
   */
  private writeMcpConfig(launch: Launch): string {
    const [command, ...args] = (this.opts.selfCommand ?? selfCommand)('bridge', 'claude')
    const file = path.join(launch.runDir, 'mcp.json')
    fs.writeFileSync(file, JSON.stringify({
      mcpServers: {
        [BRIDGE_SERVER_NAME]: { command, args, env: { BRIDGE_FILE: path.join(launch.runDir, BRIDGE_FILE) } },
      },
    }), { mode: 0o600 })
    return file
  }

  private async find(): Promise<FoundClaude> {
    try {
      const found = this.opts.findClaude ? await this.opts.findClaude() : await findClaude({
        env: process.env,
        cleanEnv: cleanEnv(process.env, ClaudeProvider.UNSET_ENV),
        ...(this.opts.claudePath ? { override: this.opts.claudePath } : {}),
      })
      this.foundPath = found.path
      return found
    } catch (e) {
      if (e instanceof ClaudeNotFound) throw new CommandError('provider_error', e.message)
      throw e
    }
  }

  /**
   * A private folder for this session's launch file, settings, bridge
   * config and record, in the app data folder (S07). Mode 0700 on macOS and
   * Linux; on Windows it relies on the per-user permissions of
   * %LOCALAPPDATA% (chmod does nothing there).
   */
  private prepare(nativeId: string): Launch {
    const root = this.sessionsRoot()
    fs.mkdirSync(root, { recursive: true, mode: 0o700 })
    const runDir = fs.mkdtempSync(path.join(root, 'session-'))
    fs.chmodSync(runDir, 0o700)
    try {
      writeHolder(runDir)
    } catch (e) {
      this.forget(runDir)
      throw e
    }
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

/** The same folder, as written or once links and short names are resolved. */
function sameFolder(a: string, b: string): boolean {
  if (samePath(a, b)) return true
  try { return samePath(fs.realpathSync.native(a), fs.realpathSync.native(b)) } catch { return false }
}
