// Sidecar entry point: picks the mode of the one executable (NOTES.md ->
// Architecture -> Platforms). The server mode's contract is in serve.ts.
import { serve } from './serve.ts'
import { stderrLog } from './log.ts'
import { bridgeModes, builtInProviders } from './providers/index.ts'
import { runLauncher } from './launch/launcher.ts'

// Modes of the one executable: the server (default); `launch`, which a
// terminal runs to start a session's program; and `bridge <provider>`, which
// a provider's CLI starts as its channel bridge.
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
