# The Claude Code workflow

Features: tooling (.claude/skills/, .claude/agents/)

## The request

The user asked for "an agentic workflow for this project" (2026-10-03).
Three readings were put to them: a dev workflow for our sessions, a
product feature (the world driving multi-agent work), or Claude running
in CI. **They chose the dev workflow**, with all four suggested pieces:
a skill for landing a feature, a docs-sync reviewer, a skill for running
the tests, and a security reviewer.

## What was built

- **`/verify`**: runs the sidecar typecheck and tests, imports the Godot
  project and runs each suite on its own, compares NOTES.md's suite list
  with `tests.yml`, and reads the branch's CI run with `gh`.
- **`/land <ID>`**: walks NOTES.md's "When a feature lands", runs the
  three checks, commits the docs, pushes the branch and hands it over
  with the live-check steps in `tests/live/checklist.txt`.
- **`docs-sync`** subagent (read-only): index vs Systems sections,
  provider scope stated, guide vs NOTES, flows after S02/Protocol
  changes, dev-log table, CREDITS, the codename, Current focus, NOTES
  suites vs CI.
- **`security-reviewer`** subagent (read-only): the diff against
  Principles, Security rules, Multi-provider rules, Platforms and
  Conventions, including that every safety behaviour has a test.

## Choices made along the way

- **They point at NOTES.md, they don't copy it.** The checklist, the
  security rules and the test commands are read from NOTES.md every time.
  A copy would go stale, and the commands already exist in two places
  (NOTES.md and `tests.yml`); `/verify` and `docs-sync` check that those
  two agree instead of adding a third.
- **No test script.** A script would be a third copy of the suite list,
  and it would have to work on all three systems. The skill tells Claude
  to run the commands from NOTES.md one at a time.
- **The reviewers can't edit.** Their tools are Read, Grep, Glob and
  read-only Bash, so a review never changes the branch it is reviewing.
  `/land` makes the fixes, or brings a finding to the user if fixing it
  would mean making a design decision.
- **Named `security-reviewer`**, not `security-review`, so it doesn't
  clash with Claude Code's built-in `/security-review`, which reviews
  against general security issues rather than this project's rules.
- **Things the user keeps:** merging and pushing `main`, starting CI runs
  (Actions minutes), live checks with the real `claude`, and any
  decision about provider scope or design. The skills stop and ask
  rather than decide these.
- **No codename** in the new files, so the renaming list doesn't grow.

## Checked

`/verify`'s steps were run by hand on Windows before the branch was
handed over (results in the hand-over message). The skills and subagents
load when a Claude Code session starts, so the first real use of
`/land` will be the next feature.
