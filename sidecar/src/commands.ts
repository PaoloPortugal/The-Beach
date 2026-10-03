// Runs one validated command from Godot against the registry and providers.
// The caller sends the outcome as `ok` or `error`, then calls `after`: events
// the command causes are held until then, so they follow the reply (as the
// schema's command descriptions say) and never overtake it.
import fs from 'node:fs'
import path from 'node:path'
import {
  COMMAND_CAPABILITY, EXTENSION_TYPE,
  type Command, type ErrorCode, type ExtensionCommand, type Project,
} from './protocol.ts'
import { CommandError, type ProviderSession } from './provider.ts'
import type { Entry, Registry } from './registry.ts'
import type { Log } from './log.ts'

/** What to do once the reply is out: send a snapshot, release held events. */
type Afters = (() => void)[]

export type Outcome =
  | { ok: true; result?: Record<string, unknown>; after: () => void }
  | { ok: false; code: ErrorCode; message: string; after: () => void }

export async function runCommand(
  registry: Registry, cmd: Command | ExtensionCommand, sendSnapshot: (entry: Entry) => void, log: Log,
): Promise<Outcome> {
  const afters: Afters = []
  const sessionId = (cmd as { session?: unknown }).session
  const entry = typeof sessionId === 'string' ? registry.get(sessionId) : undefined
  if (entry) {
    registry.hold(entry)
    afters.push(() => registry.release(entry))
  }
  const after = () => { for (const f of afters) f() }
  try {
    const result = await execute(registry, cmd, sendSnapshot, afters)
    return { ok: true, ...(result ? { result } : {}), after }
  } catch (e) {
    if (e instanceof CommandError) return { ok: false, code: e.code, message: e.message, after }
    // Unexpected failures: details stay in the log, not in the reply.
    log.error(`${cmd.type} failed: ${e instanceof Error ? e.message : String(e)}`)
    return { ok: false, code: 'provider_error', message: 'the provider failed to do this', after }
  }
}

type Result = Record<string, unknown> | undefined

async function execute(
  registry: Registry, cmd: Command | ExtensionCommand, sendSnapshot: (entry: Entry) => void, afters: Afters,
): Promise<Result> {
  if (EXTENSION_TYPE.test(cmd.type)) return runExtension(registry, cmd as ExtensionCommand)
  const c = cmd as Command

  switch (c.type) {
    case 'session.create': {
      const provider = findProvider(registry, c.provider)
      const project = checkProject(c.project)
      return startSession(registry, provider.id, afters, (host) =>
        provider.create(host, { project, ...(c.prompt !== undefined ? { prompt: c.prompt } : {}) }))
    }
    case 'session.resume': {
      const provider = findProvider(registry, c.provider)
      return startSession(registry, provider.id, afters, (host) => provider.resume(host, c.native_id))
    }
    case 'session.list_stored': {
      const provider = findProvider(registry, c.provider)
      return { sessions: await provider.listStored(c.project) }
    }
    case 'session.get_snapshot': {
      const entry = findSession(registry, c.session, false)
      // After the held events: the snapshot then supersedes them.
      afters.push(() => sendSnapshot(entry))
      return undefined
    }
    case 'session.get_history': {
      const control = findControl(registry, c.session)
      const { messages, tools } = await control.getHistory()
      return { messages, tools }
    }
    case 'message.send':
      await findControl(registry, c.session).sendMessage(c.text)
      return undefined
    case 'permission.respond': {
      const entry = findSession(registry, c.session)
      if (!entry.state!.permissions.some((p) => p.permission === c.permission)) {
        throw new CommandError('invalid_message', 'no such pending permission')
      }
      await entry.control!.respondPermission(c.permission, c.decision,
        ...(c.note !== undefined ? [c.note] : []))
      return undefined
    }
    case 'question.answer': {
      const entry = findSession(registry, c.session, true, c.type)
      if (!(entry.state!.questions ?? []).some((q) => q.question === c.question)) {
        throw new CommandError('invalid_message', 'no such pending question')
      }
      if (!entry.control!.answerQuestion) throw new CommandError('not_supported', 'provider cannot answer questions')
      await entry.control!.answerQuestion(c.question,
        c.answers !== undefined ? { answers: c.answers } : { response: c.response! })
      return undefined
    }
    case 'interrupt.request': {
      const entry = findSession(registry, c.session, true, c.type)
      if (!entry.control!.interrupt) throw new CommandError('not_supported', 'provider cannot interrupt')
      await entry.control!.interrupt()
      return undefined
    }
    case 'session.end':
      await findControl(registry, c.session).end()
      return undefined
  }
}

async function startSession(
  registry: Registry, providerId: string, afters: Afters,
  start: (host: Entry['host']) => Promise<ProviderSession>,
): Promise<Result> {
  // The new session starts with one hold, released once the reply is out.
  const entry = registry.open(registry.providers.get(providerId)!)
  afters.push(() => registry.release(entry))
  try {
    entry.control = await start(entry.host)
  } catch (e) {
    registry.discard(entry)
    throw e
  }
  const notice = entry.control.startupNotice
  return { session: entry.id, ...(notice ? { notice } : {}) }
}

async function runExtension(registry: Registry, cmd: ExtensionCommand): Promise<Result> {
  const namespace = EXTENSION_TYPE.exec(cmd.type)![1]!
  if (typeof cmd.session !== 'string') {
    throw new CommandError('not_supported', `no session-less ${namespace} commands`)
  }
  const entry = findSession(registry, cmd.session)
  if (!entry.state!.extensions.includes(namespace) || !entry.control!.extension) {
    throw new CommandError('not_supported', `session does not use the ${namespace} extension`)
  }
  return (await entry.control!.extension(cmd)) ?? undefined
}

function findProvider(registry: Registry, id: string) {
  const p = registry.providers.get(id)
  if (!p) throw new CommandError('unknown_provider', `no provider ${JSON.stringify(id)}`)
  return p
}

/** A session that is up. With `capabilityOf`, also checks the command's capability. */
function findSession(registry: Registry, id: string, mustBeUp = true, capabilityOf?: Command['type']): Entry {
  const entry = registry.get(id)
  if (!entry || entry.ended) throw new CommandError('unknown_session', 'no such session')
  if (!mustBeUp) {
    if (!entry.state) throw new CommandError('session_starting', 'the session has not come up yet')
    return entry
  }
  if (!entry.state || !entry.control) throw new CommandError('session_starting', 'the session has not come up yet')
  const capability = capabilityOf && COMMAND_CAPABILITY[capabilityOf]
  if (capability && !(capability in entry.state.capabilities)) {
    throw new CommandError('not_supported', `session does not declare ${capability}`)
  }
  return entry
}

function findControl(registry: Registry, id: string): ProviderSession {
  return findSession(registry, id).control!
}

/** The project folder must be an absolute path to an existing folder. */
function checkProject(project: Project): Project {
  const p = project.path
  if (!path.isAbsolute(p)) throw new CommandError('invalid_project', 'project path must be absolute')
  let stat: fs.Stats
  try { stat = fs.statSync(p) } catch {
    throw new CommandError('invalid_project', 'project folder does not exist')
  }
  if (!stat.isDirectory()) throw new CommandError('invalid_project', 'project path is not a folder')
  const resolved = path.resolve(p)
  // A drive or filesystem root has no folder name; show the path itself.
  return { path: resolved, name: project.name ?? (path.basename(resolved) || resolved) }
}
