// Which git repository a project folder belongs to (W05: sessions of the
// same repository share a cluster). Read from the `.git` files themselves,
// without running git: a worktree's `.git` file points to its git folder,
// whose `commondir` points to the main repository's. Generic: any provider.
import fs from 'node:fs'
import path from 'node:path'
import type { Project } from './protocol.ts'

/**
 * The repository's main folder (the one holding the shared `.git` folder),
 * the same for all its worktrees; or null outside git or if unreadable.
 */
export function findRepo(folder: string): string | null {
  try {
    for (let dir = path.resolve(folder); ; dir = path.dirname(dir)) {
      const dotGit = path.join(dir, '.git')
      const stat = fs.statSync(dotGit, { throwIfNoEntry: false })
      if (stat?.isDirectory()) return dir
      if (stat?.isFile()) return fromGitFile(dir, dotGit)
      if (path.dirname(dir) === dir) return null
    }
  } catch {
    return null
  }
}

/** A worktree's or submodule's `.git` file: `gitdir: <its git folder>`. */
function fromGitFile(dir: string, file: string): string | null {
  const m = /^gitdir:\s*(.+?)\s*$/m.exec(fs.readFileSync(file, 'utf8'))
  if (!m) return null
  const gitDir = path.resolve(dir, m[1]!)
  const commonFile = path.join(gitDir, 'commondir')
  // A submodule has no commondir: its own git folder is its repository.
  const common = fs.existsSync(commonFile)
    ? path.resolve(gitDir, fs.readFileSync(commonFile, 'utf8').trim())
    : gitDir
  return path.basename(common) === '.git' ? path.dirname(common) : common
}

/** A copy of the project with `repo` filled in when it's in a repository. */
export function withRepo(project: Project): Project {
  const { repo: _ignored, ...rest } = project
  const repo = findRepo(rest.path)
  return repo ? { ...rest, repo } : rest
}
