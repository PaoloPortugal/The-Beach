// The providers shipped in the sidecar. Each lives in its own folder here and
// is the only place its tool's name may appear (NOTES.md -> Multi-provider
// rules).
import type { Provider } from '../provider.ts'
import { ClaudeProvider } from './claude/index.ts'

export function builtInProviders(): Provider[] {
  return [new ClaudeProvider()]
}
