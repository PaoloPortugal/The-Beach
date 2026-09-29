// The providers shipped in the sidecar. Each lives in its own folder here and
// is the only place its tool's name may appear (NOTES.md -> Multi-provider
// rules).
import type { Provider } from '../provider.ts'
import { ClaudeProvider } from './claude/index.ts'
import { runBridge } from './claude/bridge.ts'

export function builtInProviders(): Provider[] {
  return [new ClaudeProvider()]
}

/** `bridge <provider>` modes: a provider's CLI starts these over stdio. */
export const bridgeModes: Record<string, () => Promise<void>> = {
  claude: () => runBridge(process.env, {
    input: process.stdin,
    output: process.stdout,
    log: (m) => process.stderr.write(`[bridge] ${m}
`),
  }),
}
