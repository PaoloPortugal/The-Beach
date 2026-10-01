// Sidecar entry point: picks the mode of the one executable (NOTES.md ->
// Architecture -> Platforms). The server mode's contract is in serve.ts.
import { serve } from './serve.ts'
import { stderrLog } from './log.ts'
import { bridgeModes, builtInProviders } from './providers/index.ts'
import { runLauncher } from './launch/launcher.ts'
import { runRelay } from './launch/relay.ts'

// Modes of the one executable: the server (default); `launch`, which a
// terminal runs to start a session's program; `bridge <provider>`, which
// a provider's CLI starts as its channel bridge; and `relay <file>`, which
// a provider's CLI runs as a command hook.
async function main(argv: string[]) {
  const [mode, ...rest] = argv
  if (mode === undefined || mode === 'serve') {
    if (rest.length > 0) throw new Error(`unexpected arguments: ${rest.join(' ')}`)
    await serve(builtInProviders())
    return
  }
  if (mode === 'launch') {
    process.exitCode = await runLauncher(rest)
    return
  }
  if (mode === 'relay') {
    // A command hook: forwards the hook to the server. Always exit 0, at
    // once (stdin may still be open after a timeout): a failure here must
    // never block the provider's CLI.
    await runRelay(rest, process.stdin, (m) => process.stderr.write(`[relay] ${m}\n`))
    process.exit(0)
  }
  if (mode === 'bridge') {
    // A provider's channel bridge, started by that provider's CLI.
    const run = bridgeModes[rest[0] ?? '']
    if (!run || rest.length !== 1) throw new Error('bridge mode needs a provider name')
    await run()
    return
  }
  throw new Error(`unknown mode ${JSON.stringify(mode)}`)
}

// process.argv is [executable, script, ...args] under node and, in the
// packaged executable, [executable, executable, ...args]: arguments start at 2.
main(process.argv.slice(2)).catch((e: unknown) => {
  stderrLog.error(e instanceof Error ? e.message : String(e))
  process.exit(1)
})
