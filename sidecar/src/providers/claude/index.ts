// The Claude provider (NOTES.md -> S02): the only place Claude-specific names
// may appear in the sidecar. It launches the user's own, unmodified `claude`
// in a terminal and never reads, stores or passes on Claude credentials.
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import type { Adopt, Provider, ProviderSession, SessionHost } from '../../provider.ts'
import { CommandError } from '../../provider.ts'
import type { History, Launch as LaunchChoice, Notice, Program, Project, StoredSession } from '../../protocol.ts'
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
import { checkClaudePath, ClaudeNotFound, findClaude, forgetLoginShellPath, type FoundClaude, type ReadVersion } from './find.ts'
import { runningSessions, type AgentEntry, type Running } from './running.ts'
import { BRIDGE_SERVER_NAME, writeBridgeFile } from './bridge.ts'
import { BridgeServer } from './bridge-server.ts'
import { HookServer, type HookLink } from './hook-server.ts'
import {
  HOLDER_FILE, readHookPort, readRunRecord, RUN_DIR_NAME, writeHolder, writeHookPort, writeRunRecord, type RunRecord,
} from './run-folder.ts'
import {
  findStored, findTranscript, listStored, NO_TITLES, pickTitle, projectsDir, readConversation, readTitles, samePath, StoredCache,
  type Titles, type TranscriptInfo,
} from './store.ts'
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
 * How often `claude agents --json` is asked, while the game has focus and
 * in the background (S08's decision): which sessions run outside the game
 * (S08), and, for read-only sessions (S07, S08), which conversation each is
 * in and whether it waits on the user. Each time costs about 0.7 s of a
 * `claude` process.
 */
export const AGENTS_POLL_MS = 5000
export const AGENTS_POLL_BACKGROUND_MS = 10_000

/**
 * The provider notice when agent view is off (S08): Claude Code won't list
 * its sessions, so none started outside the game can be shown. Sent once
 * per launch. The user's wording (2026-10-22); the game's settings show it
 * beside the greyed-out toggle.
 */
export const OUTSIDE_SESSIONS_OFF = {
  code: 'outside_sessions_off',
  message: 'Sessions started outside the game can\'t be shown: agent view is off in Claude Code.',
}

/** What started a conversation that gets no island (S08): `claude -p` runs and Agent SDK programs. */
const NOT_SHOWN_ENTRYPOINTS = new Set(['sdk-cli'])

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
  /** A claude executable set by hand at start (setProgramPath sets it later). */
  claudePath?: string
  /** A terminal id to try first (a user setting, later). */
  terminal?: string
  /** For tests: replaces opening a real terminal. */
  openTerminal?: typeof openTerminal
  /** For tests: replaces finding claude when none is set by hand. */
  findClaude?: () => Promise<FoundClaude>
  /** For tests: replaces running `claude --version` (finding, and checking a path set by hand). */
  readVersion?: ReadVersion
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
  /** For tests: how often `claude agents` is asked (AGENTS_POLL_MS), and in the background (AGENTS_POLL_BACKGROUND_MS). */
  agentsPollMs?: number
  agentsPollBackgroundMs?: number
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
  /** Sessions started outside the game get read-only islands (S08); `claude` can be set by hand (S02). */
  readonly capabilities = { outside_sessions: {}, program_path: { program: 'claude' } }
  private readonly opts: ClaudeOptions
  private readonly log: Log
  /** Sessions running now, by Claude's session id: not listed, not resumed twice. */
  private readonly live = new Set<string>()
  /** The stored sessions' listing, kept between calls (S04). */
  private readonly stored = new StoredCache()
  /** The `claude` the last find() gave, for asking which sessions run (running()). */
  private foundPath: string | undefined
  /** The `claude` set by hand (program_path): the only one tried. */
  private handPath: string | undefined
  /** Where what find() gives goes (provider.program). */
  private reportProgram: ((program: Program) => void) | null = null
  /** Bumped by setProgramPath, so a find() begun before it doesn't report the old setting's answer. */
  private programRun = 0
  /** The find() under way, shared by the looks that come while it runs (the one at start, a launch, a listing). */
  private finding: { run: number; found: Promise<FoundClaude> } | null = null
  private bridges: BridgeServer | null = null
  private hooks: HookServer | null = null
  /** Read-only sessions (S07, S08) by their `claude`'s process id, asked about together. */
  private readonly watched = new Map<number, ClaudeSession>()
  /** The run folders of the sessions this game runs (launched, or taken back): their programs are ours, not outside ones. */
  private readonly runDirs = new Set<string>()
  /**
   * Sessions started outside the game (S08), by process id. Adopted
   * through the registry's `adopt` from restore, so only once restore ran.
   */
  private readonly outside = new Map<number, ClaudeSession>()
  private adoptOutside: Adopt | null = null
  private notice: ((notice: Notice) => void) | null = null
  /** False once agent view is found off: no more looking for outside sessions this launch. */
  private outsideOn = true
  /** The player's setting (setOutsideSessions): false shows none and stops looking. */
  private outsideWanted = true
  /** Just turned back on: the next listing shows them at once, rising (session.created). */
  private turnedOn = false
  /** Whether outsideFrom has had a listing yet (the one at start). */
  private polled = false
  /** Listed once with no transcript yet (pid -> session id): adopted at the next listing if still none (a `claude -p` run writes it at once). */
  private readonly sightings = new Map<number, string>()
  /** Listed but given no island (pid -> session id): `claude -p` runs, Agent SDK programs, or one that failed to adopt. */
  private readonly passed = new Map<number, string>()
  /** Why the last listing failed, so a failure repeated every poll is logged once. */
  private lastFailure: string | null = null
  private pollTimer: NodeJS.Timeout | null = null
  private asking = false
  private focused = true
  private stopped = false

  constructor(opts: ClaudeOptions = {}) {
    this.opts = opts
    this.log = opts.log ?? stderrLog
    this.handPath = opts.claudePath
  }

  watchProgram(report: (program: Program) => void): void {
    this.reportProgram = report
  }

  /**
   * Sets `claude` by hand, or clears it (null), for sessions started from
   * now on (S02). A path is checked first (checkClaudePath); one that fails
   * is refused (invalid_program) and the old setting stays, unless
   * `evenIfInvalid` (the start's setting): then it's kept, reported not
   * found. Cleared, `claude` is looked for as usual at once.
   */
  async setProgramPath(file: string | null, evenIfInvalid = false): Promise<Program> {
    if (file === null || evenIfInvalid) {
      this.handPath = file ?? undefined
      this.foundPath = undefined
      this.programRun++
      return this.look()
    }
    let found: FoundClaude
    try {
      found = await checkClaudePath(file, { cleanEnv: this.cleanEnv(), ...(this.opts.readVersion ? { readVersion: this.opts.readVersion } : {}) })
    } catch (e) {
      if (e instanceof ClaudeNotFound) throw new CommandError('invalid_program', e.message)
      throw e
    }
    this.handPath = file
    this.foundPath = found.path
    this.programRun++
    const program = { path: found.path, version: found.version, set_by_hand: true }
    this.reportProgram?.(program)
    return program
  }

  /**
   * Looks for `claude` afresh (S02: at start, and the player's "Look
   * again"), the login shell asked again too: the player may have just
   * installed it.
   */
  async findProgram(): Promise<Program> {
    forgetLoginShellPath()
    return this.look(true)
  }

  /** Looks for `claude` now (reported), never throwing for one not found; `fresh`: not sharing a look under way. */
  private async look(fresh = false): Promise<Program> {
    try {
      const found = await this.find(fresh)
      return { path: found.path, version: found.version, set_by_hand: this.handPath !== undefined }
    } catch (e) {
      if (e instanceof CommandError) return { path: null, set_by_hand: this.handPath !== undefined, message: e.message }
      throw e
    }
  }

  private cleanEnv(): Record<string, string> {
    return cleanEnv(process.env, ClaudeProvider.UNSET_ENV)
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
    this.runDirs.add(launch.runDir)
    const session: ClaudeSession = new ClaudeSession(host, launch, o.project, o.titles, this.log,
      () => { this.forget(launch.runDir); this.runDirs.delete(launch.runDir); this.live.delete(session.nativeId) },
      this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS, o.history, o.prompt, this.opts.hooksCheckMs ?? HOOKS_CHECK_MS,
      o.usage ?? undefined)
    session.link = bridges.register(session.bridgeHandlers())
    session.hookLink = hooks.register({ onHook: (p, gone) => session.onHook(p, gone), onStatus: (p) => session.onStatus(p) })
    // What a later sidecar needs to take the session back (S07).
    const record = {
      native_id: o.nativeId, project: o.project, hook_port: hooks.port, hook_token: session.hookLink.token,
      started_at: new Date().toISOString(),
    }
    session.startedAt = record.started_at
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
    this.stopped = true
    if (this.pollTimer) clearTimeout(this.pollTimer)
    this.pollTimer = null
    // An answer still on its way then has no one to go to.
    this.watched.clear()
    this.outside.clear()
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
   * Then, from the same answer, the sessions started outside the game
   * (S08), so they're in the first sync too (W12), and from then on the
   * poll (AGENTS_POLL_MS) keeps looking.
   */
  async restore(adopt: Adopt, notice?: (notice: Notice) => void): Promise<void> {
    const hooks = await this.hookServer()
    const root = this.sessionsRoot()
    if (!this.opts.sessionsDir && root === process.env[TEST_SESSIONS_DIR]) this.log.info(`sessions folder: the tests' own (${TEST_SESSIONS_DIR})`)
    let names: string[] = []
    try {
      names = fs.readdirSync(root, { withFileTypes: true })
        .filter((d) => d.isDirectory() && RUN_DIR_NAME.test(d.name)).map((d) => d.name)
    } catch { /* none yet */ }
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

    // Nothing to take back and outside sessions off: `claude` isn't asked
    // at all (so a suite's sidecar never runs the developer's). Agent view
    // off is then found when they're turned on.
    const answer = found.length > 0 || this.outsideWanted ? await this.askRunning() : null
    const agents = answer === null || 'none' in answer ? null : answer.agents ?? null
    if (answer !== null && agents === null && found.length > 0) {
      this.log.info(`can't ask Claude Code which sessions run (${'none' in answer ? answer.none : 'no entries'}); trusting their launchers`)
    }
    if (found.length > 0) {
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
    // Once: a second restore (never in the sidecar) keeps the first one's.
    if (this.adoptOutside || this.stopped) return
    this.adoptOutside = adopt
    this.notice = notice ?? null
    if (answer) this.outsideFrom(answer)
    this.schedulePoll()
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
          () => {
            this.forget(f.runDir); this.runDirs.delete(f.runDir); this.live.delete(session?.nativeId ?? nativeId); this.watched.delete(f.program)
          },
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
    this.runDirs.add(f.runDir)
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
    if (readOnly) {
      this.watched.set(f.program, s)
      this.schedulePoll()
    }
    this.log.info(`took back session ${s.host.id}${readOnly ? ' (its hook port was taken: read-only)' : ''}`)
  }

  /** The window gained or lost focus (client.set_focus): the poll's pace changes from now. */
  setFocused(focused: boolean): void {
    if (focused === this.focused) return
    this.focused = focused
    if (!this.pollTimer) return
    clearTimeout(this.pollTimer)
    this.pollTimer = null
    this.schedulePoll()
  }

  /**
   * The player turned sessions started outside the game off or on (S08).
   * Off: each ends (reason user, so its island sinks and W12 forgets it)
   * and the poll stops unless a read-only session of ours still needs it.
   * On: asked at once, each found shown at once and rising.
   */
  setOutsideSessions(on: boolean): void {
    if (on === this.outsideWanted) return
    this.outsideWanted = on
    this.turnedOn = on
    if (!on) {
      for (const s of [...this.outside.values()]) s.gone('sessions started outside the game turned off', 'user')
      this.sightings.clear()
      this.passed.clear()
      if (this.pollTimer && this.watched.size === 0) {
        clearTimeout(this.pollTimer)
        this.pollTimer = null
      }
      return
    }
    if (!this.adoptOutside || !this.outsideOn || this.stopped) return
    if (this.pollTimer) clearTimeout(this.pollTimer)
    this.pollTimer = null
    // A listing already on its way shows them instead (turnedOn).
    if (!this.asking) void this.poll().finally(() => this.schedulePoll())
  }

  /**
   * The next `claude agents`, while there's anything to ask about: outside
   * sessions (once restore ran, while the player wants them, until agent
   * view is found off) or
   * read-only ones. Every AGENTS_POLL_MS with focus, AGENTS_POLL_BACKGROUND_MS without.
   */
  private schedulePoll() {
    if (this.pollTimer || this.stopped) return
    if (!(this.adoptOutside && this.outsideOn && this.outsideWanted) && this.watched.size === 0) return
    const wait = this.focused
      ? this.opts.agentsPollMs ?? AGENTS_POLL_MS
      : this.opts.agentsPollBackgroundMs ?? this.opts.agentsPollMs ?? AGENTS_POLL_BACKGROUND_MS
    this.pollTimer = setTimeout(() => {
      this.pollTimer = null
      void this.poll().finally(() => this.schedulePoll())
    }, wait)
    this.pollTimer.unref()
  }

  /** One `claude agents` at a time, for all: each read-only session gets its own entry, or null; then the outside sessions. */
  private async poll() {
    if (this.asking) return
    this.asking = true
    try {
      const answer = await this.askRunning()
      if (this.stopped) return
      const agents = 'none' in answer ? null : answer.agents ?? null
      for (const [program, session] of [...this.watched]) {
        // One session's failure mustn't stop the poll for the others, or the sidecar.
        try { session.onAgent(agents?.find((a) => a.pid === program) ?? null) } catch (e) {
          this.log.warn(`session ${session.host.id}: claude agents' answer not taken: ${e instanceof Error ? e.message : String(e)}`)
        }
      }
      if (this.adoptOutside && this.outsideOn) this.outsideFrom(answer)
    } finally {
      this.asking = false
    }
  }

  /**
   * The sessions started outside the game (S08), from one `claude agents`
   * answer: each live one with a working folder and a session id gets a
   * read-only island, except the game's own (by the process its launcher
   * started, or its session id) and `claude -p` runs and Agent SDK
   * programs (their transcript's entrypoint). One with no transcript yet
   * waits for the next listing, in case it's a `claude -p` about to write
   * one, except at start, so it's in the first sync (W12), and just after
   * the player turned them back on (then announced as session.created, so
   * they rise). One no longer listed ends. Agent view off: said once, the
   * outside sessions end, and no more are looked for this launch, even with
   * the setting off when S07's read-only sessions keep the poll going (the
   * setting shows why it can't be turned on).
   */
  private outsideFrom(answer: Running) {
    const first = !this.polled || this.turnedOn
    const created = this.turnedOn
    this.polled = true
    if ('none' in answer) {
      if (answer.disabled) {
        this.outsideOn = false
        this.log.info(`no sessions from outside the game: ${answer.none}`)
        this.notice?.(OUTSIDE_SESSIONS_OFF)
        for (const s of [...this.outside.values()]) s.gone('agent view is off')
      } else if (answer.none !== this.lastFailure) {
        this.log.info(`can't look for sessions started outside the game: ${answer.none}`)
      }
      this.lastFailure = answer.none
      return
    }
    if (this.lastFailure !== null) this.log.info('looking for sessions started outside the game again')
    this.lastFailure = null
    if (!this.outsideWanted) return
    this.turnedOn = false
    const agents = answer.agents ?? []
    const listed = new Map(agents.map((a) => [a.pid, a]))
    for (const [pid, s] of [...this.outside]) if (!listed.has(pid)) s.gone('Claude Code no longer lists it')
    for (const m of [this.sightings, this.passed]) for (const [pid, id] of [...m]) if (listed.get(pid)?.sessionId !== id) m.delete(pid)
    const ours = this.ownPrograms()
    for (const a of agents) {
      if (this.outside.has(a.pid) || ours.has(a.pid) || this.live.has(a.sessionId) || this.passed.has(a.pid) || !a.cwd) continue
      try {
        this.considerOutside(a, a.cwd, first, created)
      } catch (e) {
        this.passed.set(a.pid, a.sessionId)
        this.log.error(`couldn't show a session started outside the game: ${e instanceof Error ? e.message : String(e)}`)
      }
    }
  }

  /** The `claude` processes of the sessions this game runs, from their run folders. */
  private ownPrograms(): Set<number> {
    const pids = new Set<number>(this.watched.keys())
    for (const runDir of this.runDirs) {
      const pid = readPidFile(programPidFile(runDir))
      if (pid !== null) pids.add(pid)
    }
    return pids
  }

  private considerOutside(a: AgentEntry, cwd: string, first: boolean, created: boolean) {
    const t = this.findOwn(a.sessionId, cwd)
    if (t?.entrypoint && NOT_SHOWN_ENTRYPOINTS.has(t.entrypoint)) {
      this.passed.set(a.pid, a.sessionId)
      return
    }
    if (!t && !first && this.sightings.get(a.pid) !== a.sessionId) {
      this.sightings.set(a.pid, a.sessionId)
      return
    }
    this.sightings.delete(a.pid)
    if (!fs.statSync(cwd, { throwIfNoEntry: false })?.isDirectory()) {
      this.passed.set(a.pid, a.sessionId)
      this.log.info('a session started outside the game runs in a folder that isn\'t there; not shown')
      return
    }
    this.adoptOutsideSession(a, cwd, t?.file ?? null, created)
  }

  /** One outside session's read-only island (see outsideFrom), read from its transcript like S07's read-only ones. */
  private adoptOutsideSession(a: AgentEntry, cwd: string, file: string | null, created: boolean) {
    const read = file ? readConversation(file) : null
    let titles = file ? readTitles(file) : NO_TITLES
    // Its display name, when the transcript has none yet.
    if (pickTitle(titles) === null && a.name) titles = { ...titles, custom: a.name }
    const project: Project = { path: cwd }
    // No run folder: nothing of the session is written anywhere.
    const launch: Launch = { runDir: '', nativeId: a.sessionId }
    let session: ClaudeSession | null = null
    this.adoptOutside!((host) => {
      session = new ClaudeSession(host, launch, project, titles, this.log,
        () => { this.outside.delete(a.pid); this.watched.delete(a.pid) },
        this.opts.startupTimeoutMs ?? STARTUP_TIMEOUT_MS, read?.history, undefined, this.opts.hooksCheckMs ?? HOOKS_CHECK_MS,
        read?.usage)
      return session
    }, { created })
    const s = session as unknown as ClaudeSession
    this.outside.set(a.pid, s)
    this.watched.set(a.pid, s)
    s.restored({
      state: a.status === 'busy' ? 'working' : a.status === 'waiting' ? 'waiting' : 'idle',
      reason: a.status === 'waiting' ? 'input' : null,
      startedAt: new Date(a.startedAt ?? Date.now()).toISOString(),
      transcript: file,
      readOnly: true,
      outside: true,
      findTranscript: (id) => this.findOwn(id, cwd)?.file ?? null,
    })
    this.log.info(`showing session ${s.host.id}, started outside the game (read-only)`)
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
    // A session started outside the game has none (S08).
    if (!runDir) return
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

  /** A conversation's transcript, only if it's this project's (its cwd), whatever started it. */
  private findOwn(nativeId: string, project: string): TranscriptInfo | null {
    return findTranscript(nativeId, this.projects(), (cwd) => sameFolder(cwd, project))
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

  /**
   * Finds `claude` (the one set by hand, if any) and reports what it gave
   * (provider.program). A look under way for the same setting is shared,
   * unless `fresh`, so the one at start, a launch and a listing don't each
   * run `--version`.
   */
  private find(fresh = false): Promise<FoundClaude> {
    const run = this.programRun
    if (!fresh && this.finding?.run === run) return this.finding.found
    const found = this.findNow(run)
    const finding = { run, found }
    this.finding = finding
    const done = () => { if (this.finding === finding) this.finding = null }
    found.then(done, done)
    return found
  }

  private async findNow(run: number): Promise<FoundClaude> {
    const byHand = this.handPath !== undefined
    try {
      const found = this.opts.findClaude && !byHand ? await this.opts.findClaude() : await findClaude({
        env: process.env,
        cleanEnv: this.cleanEnv(),
        ...(byHand ? { override: this.handPath } : {}),
        ...(this.opts.readVersion ? { readVersion: this.opts.readVersion } : {}),
      })
      if (run === this.programRun) {
        this.foundPath = found.path
        this.reportProgram?.({ path: found.path, version: found.version, set_by_hand: byHand })
      }
      return found
    } catch (e) {
      if (e instanceof ClaudeNotFound) {
        if (run === this.programRun) {
          this.foundPath = undefined
          this.reportProgram?.({ path: null, set_by_hand: byHand, message: e.message })
        }
        throw new CommandError('provider_error', e.message)
      }
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
