// W05: which repository a project folder belongs to, worktrees included,
// read from the .git files alone; and sessions carry it as project.repo.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { findRepo, withRepo } from '../src/repo.ts'
import { connect, testServer } from './helpers.ts'
import { FakeProvider } from './fake-provider.ts'

/** main/ (a repository with main/src), wt/ (its worktree), sub/ (a submodule of main), plain/. */
function layout() {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'repo-test-')))
  const main = path.join(root, 'main')
  fs.mkdirSync(path.join(main, '.git', 'worktrees', 'wt'), { recursive: true })
  fs.mkdirSync(path.join(main, 'src', 'deep'), { recursive: true })
  fs.writeFileSync(path.join(main, '.git', 'worktrees', 'wt', 'commondir'), '../..\n')
  const wt = path.join(root, 'wt')
  fs.mkdirSync(path.join(wt, 'lib'), { recursive: true })
  fs.writeFileSync(path.join(wt, '.git'), `gitdir: ${path.join(main, '.git', 'worktrees', 'wt')}\n`)
  // A submodule's .git file is relative, and its git folder has no commondir.
  fs.mkdirSync(path.join(main, '.git', 'modules', 'sub'), { recursive: true })
  const sub = path.join(main, 'sub')
  fs.mkdirSync(sub)
  fs.writeFileSync(path.join(sub, '.git'), 'gitdir: ../.git/modules/sub\n')
  const plain = path.join(root, 'plain')
  fs.mkdirSync(plain)
  return { root, main, wt, sub, plain }
}

test('the repository of a folder, its subfolders and its worktrees', () => {
  const l = layout()
  try {
    assert.equal(findRepo(l.main), l.main)
    assert.equal(findRepo(path.join(l.main, 'src', 'deep')), l.main, 'a subfolder')
    assert.equal(findRepo(l.wt), l.main, 'a worktree belongs to the main repository')
    assert.equal(findRepo(path.join(l.wt, 'lib')), l.main, 'and so does its subfolder')
    assert.equal(findRepo(l.sub), path.join(l.main, '.git', 'modules', 'sub'), 'a submodule is its own repository')
    assert.equal(findRepo(path.join(l.root, 'gone')), null, 'a missing folder')
    fs.writeFileSync(path.join(l.plain, '.git'), 'not a pointer')
    assert.equal(findRepo(l.plain), null, 'an unreadable .git file')
  } finally {
    fs.rmSync(l.root, { recursive: true, force: true })
  }
})

test('withRepo fills repo in and never keeps one it was given', () => {
  const l = layout()
  try {
    assert.deepEqual(withRepo({ path: l.wt, name: 'wt' }), { path: l.wt, name: 'wt', repo: l.main })
    assert.deepEqual(withRepo({ path: l.plain, repo: l.main }), { path: l.plain })
  } finally {
    fs.rmSync(l.root, { recursive: true, force: true })
  }
})

test('a session in a worktree carries its repository', async () => {
  const l = layout()
  const s = await testServer([new FakeProvider()])
  const c = await connect(s.port, s.token)
  try {
    await c.sync()
    const reply = await c.command({ type: 'session.create', provider: 'fake', project: { path: l.wt, repo: '/elsewhere' } })
    assert.equal(reply.type, 'ok', JSON.stringify(reply))
    const created = await c.next('session.created')
    const project = (created.session as { project: Record<string, unknown> }).project
    assert.deepEqual(project, { path: l.wt, name: 'wt', repo: l.main })
    assert.deepEqual(c.invalid, [], 'every message matched the schema')
  } finally {
    await c.close()
    await s.close()
    fs.rmSync(l.root, { recursive: true, force: true })
  }
})
