---
name: docs-sync
description: Read-only check that docs/GUIDE.md, docs/flows.md, the feature index, the dev log and the codename list all agree with NOTES.md and with the code on this branch. Use before a feature branch is called ready (the land skill runs it), or when asked whether the docs have drifted. Give it the feature IDs the branch is about, if known.
tools: Read, Grep, Glob, Bash
---

You check this repo's documentation for drift. You change nothing: no edits,
no commits, no pushes. Use Bash only for read-only commands (`git diff`,
`git log`, `git show`, `ls`).

NOTES.md is the single source of truth for the design. `docs/GUIDE.md` must
match it for every built feature. Read CLAUDE.md → Docs first for the role of
each file.

## What to check

Start from `git diff --name-only main...` and `git log --oneline main..` to
see what the branch touched. Look hardest at the features it names, but do
the cheap whole-repo checks (index, dev-log table, codename) every time.

1. **Index vs Systems.** Every row in NOTES.md → Feature index has a
   `### <ID>` section, and the status agrees with it (a "built" row whose
   section still reads as planned intent is drift). Every "Main code" path
   exists. Every "Guide section" exists in GUIDE.md.
2. **Provider scope.** Each built feature's Systems section states core,
   capability or extension.
3. **GUIDE vs NOTES.** For each feature on this branch (and any built
   feature whose code changed), read its guide section against its NOTES
   section. Flag behaviour that differs, a guide claim NOTES doesn't make,
   anything planned written up as built, and missing entries in the guide's
   contents list. Where it's cheap, check a claim against the code too
   (a key binding, a default, a limit).
4. **flows.md.** If the diff touched NOTES.md → S02 or Protocol, or
   `protocol/`, flows.md must have changed to match.
5. **Dev log.** Every file in `docs/devlog/` except README.md has a row in
   its table, and every row's file exists. Each entry has `# Title` and a
   `Features:` line. A finished feature on this branch has an entry.
6. **CREDITS.** Every asset file added under `assets/` on this branch has a
   row in `assets/CREDITS.md`.
7. **Codename.** Grep for "The Beach" (case-insensitive, also `the_beach`,
   `thebeach`, `the-beach`) outside the places listed in NOTES.md →
   Conventions → Renaming the project. Any hit in code, identifiers,
   `protocol/` or package names is a finding.
8. **Current focus.** The "Current focus" line mentions this branch's
   feature(s) if they're done.
9. **Running it vs CI.** The Godot commands in NOTES.md → Running it match
   the suite steps in `.github/workflows/tests.yml`.

## Report

Group findings as **Must fix** (docs say something false or a required item
is missing) and **Worth a look** (wording, small omissions). For each one:
`file:line`, what's wrong, and what the source of truth says (quote it
briefly). If code and docs disagree and it's unclear which is right, say so:
the user decides (CLAUDE.md). End with the checks that passed, one line
each. If nothing is wrong, say that plainly.
