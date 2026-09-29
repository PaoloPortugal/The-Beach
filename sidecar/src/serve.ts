// The sidecar's server mode (NOTES.md -> S01).
//
// Godot starts this with an argument array and a pipe. Contract:
// - stdout carries exactly one line, the handshake:
//   {"type":"ready","protocol":1,"port":<port>,"token":"<hex>"}
//   Godot then connects to ws://127.0.0.1:<port>/ with
//   "Authorization: Bearer <token>". Nothing else is ever written to stdout.
// - stderr carries logs (never session content).
// - When stdin closes (Godot quit or crashed, on any OS), the sidecar exits.
//   Launched sessions keep running on their own.
import crypto from 'node:crypto'
import { startServer } from './server.ts'
import { Registry } from './registry.ts'
import { stderrLog, type Log } from './log.ts'
import { PROTOCOL_VERSION } from './protocol.ts'
import type { Provider } from './provider.ts'

/** How long shutdown may take before the process exits anyway. */
const SHUTDOWN_GRACE_MS = 3000

export async function serve(providers: Provider[], log: Log = stderrLog): Promise<void> {
  const token = crypto.randomBytes(32).toString('hex')
  const registry = new Registry(providers, log)
  const server = await startServer({ registry, token, log })

  let stopping = false
  const stop = async (why: string) => {
    if (stopping) return
    stopping = true
    log.info(`stopping: ${why}`)
    setTimeout(() => process.exit(0), SHUTDOWN_GRACE_MS).unref()
    await Promise.allSettled([server.close(), ...providers.map((p) => p.shutdown())])
    process.exit(0)
  }

  // Exit with the parent. 'end' covers a clean close, 'close' and 'error'
  // cover the pipe breaking; ignored or closed stdin means nobody owns us.
  process.stdin.on('end', () => void stop('stdin closed'))
  process.stdin.on('close', () => void stop('stdin closed'))
  process.stdin.on('error', () => void stop('stdin error'))
  process.stdin.resume()
  process.on('SIGINT', () => void stop('interrupted'))
  process.on('SIGTERM', () => void stop('terminated'))

  process.stdout.write(JSON.stringify({ type: 'ready', protocol: PROTOCOL_VERSION, port: server.port, token }) + '\n')
  log.info(`listening on 127.0.0.1:${server.port}`)
}
