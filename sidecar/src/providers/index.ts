// The providers shipped in the sidecar. Each lives in its own folder here and
// is the only place its tool's name may appear (NOTES.md -> Multi-provider
// rules). None yet: the Claude provider arrives with S02.
import type { Provider } from '../provider.ts'

export function builtInProviders(): Provider[] {
  return []
}
