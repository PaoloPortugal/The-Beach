// Sidecar entry point: picks the mode of the one executable (NOTES.md ->
// Architecture -> Platforms). The server mode's contract is in serve.ts.
import { serve, serveOptions } from './serve.ts'
import { stderrLog } from './log.ts'
import { bridgeModes, builtInProviders } from './providers/index.ts'
import { runLauncher } from './launch/launcher.ts'
import { runRelay } from './launch/relay.ts'

// Modes of the one executable: the server (default); `launch`, which a
// terminal runs to start a session's program; `bridge <provider>`, which
// a provider's CLI starts as its channel bridge; `relay <file>`, which a
// provider's CLI runs as a command hook; and `statusline <file>`, which it
// runs as its status line (C08: the same relay, to its own endpoint).
async function main(argv: string[]) {
  const [mode, ...rest] = argv
  if (mode === undefined || mode === 'serve') {
    // --no-outside-sessions: the player turned off sessions started outside
    // the game (S08); --program-path <provider>=<path>: a program set by hand (S02).
    await serve(builtInProviders(), undefined, serveOptions(rest))
    return
  }
  if (mode === 'launch') {
    process.exitCode = await runLauncher(rest)
    return
  }
  if (mode === 'relay' || mode === 'statusline') {
    // A command hook or status line: forwards its input to the server.
    // Always exit 0, at once (stdin may still be open after a timeout), and
    // print nothing: a failure here must never block the provider's CLI,
    // and a status line's stdout is shown in its terminal.
    await runRelay(rest, process.stdin, (m) => process.stderr.write(`[${mode}] ${m}\n`))
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
