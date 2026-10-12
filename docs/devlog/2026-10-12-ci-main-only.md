# CI: only on main

Features: tooling (.github/workflows/tests.yml)

The user's request (2026-10-12): "we're using way too many minutes, make
it so the tests run only on a push to main", as macOS already was.

## What changed

- `on.push.branches: [main]`: a push to any other branch no longer
  starts a run. The docs-only `paths-ignore` stays, and so does Run
  workflow by hand (any branch), which never runs on its own; kept so a
  branch can still be checked on macOS or Linux before merging when it
  matters.
- Both matrices are a plain list of the three systems: with only `main`
  and runs by hand left, the expression that dropped macOS elsewhere had
  nothing left to choose.
- NOTES.md → Running it → Continuous integration, and the `verify` and
  `land` skills: a feature branch's check is the local suites; read
  `main`'s run after a merge.

## Cost

A run on all three is about 44 minutes (macOS 30 of them). Before, each
branch push also cost about 14 (Windows and Linux); a feature with a
handful of pushes spent more on its branch than on its merge.
