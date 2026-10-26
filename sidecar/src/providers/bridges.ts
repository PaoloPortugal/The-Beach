// The `bridge <provider>` modes: a provider's CLI starts these over stdio, one
// per session. Kept apart from the providers (index.ts), so a bridge loads
// only its own code and is up sooner (NOTES.md -> S02 -> Starting up).
import { runBridge } from './claude/bridge.ts'

export const bridgeModes: Record<string, () => Promise<void>> = {
  claude: () => runBridge(process.env, {
    input: process.stdin,
    output: process.stdout,
    log: (m) => process.stderr.write(`[bridge] ${m}
`),
  }),
}
