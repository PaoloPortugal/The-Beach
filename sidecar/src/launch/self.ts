// How to start this same sidecar in another mode (launcher, channel bridge):
// the packaged executable runs directly; from source or the bundle, it's
// node plus the entry script.
import path from 'node:path'
import sea from 'node:sea'

export function selfCommand(mode: string, ...args: string[]): string[] {
  if (sea.isSea()) return [process.execPath, mode, ...args]
  const entry = process.argv[1]
  if (!entry) throw new Error('cannot tell which script is running')
  return [process.execPath, path.resolve(entry), mode, ...args]
}
