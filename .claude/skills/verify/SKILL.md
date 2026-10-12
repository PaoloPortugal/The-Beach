---
name: verify
description: Run every automated test locally (sidecar typecheck and tests, then each Godot suite), check the CI list still matches NOTES.md, and read this branch's CI run with gh. Use before saying a feature or fix is ready, after any change to sidecar/, core/, world/, agents/, chat/ or tests/, or when asked to run the tests.
---

# Verify

Runs what CI runs, on this machine, and reports pass/fail per suite. Never
runs the real `claude` (that is the user's live check, not this).

## 1. The commands come from NOTES.md

Read NOTES.md → **Running it** now; it is the source of truth for the test
commands. Don't use a remembered list: suites get added.

Then compare its Godot command list with the steps in
`.github/workflows/tests.yml` (the `godot` job, after "Import the project").
If one has a suite the other lacks, report it as a finding. Don't fix it
silently: say which side looks right and why.

## 2. Sidecar

In `sidecar/`:
- `npm ci` only if `node_modules/` is missing or `package-lock.json` changed
  on this branch (`git diff --name-only main... -- sidecar/package-lock.json`).
- `npm run typecheck`
- `npm test`

## 3. Godot

Find Godot: `$GODOT` if set, else `godot` on PATH (on Windows that may be a
`godot.cmd` shim, which PowerShell runs and Git Bash's `command -v` misses).
Check `godot --version` shows the version in `.godotrc`. If Godot can't be
found, say so and stop here. Don't download it.

From the repo root:
1. `godot --headless --path . --import` (needed once after a fresh checkout,
   or when class names show as "Could not find type").
2. Each command from NOTES.md → Running it, **one at a time**, so a failure
   names its suite. Give each up to 8 minutes, like CI does.

The exit code is the result. Every suite installs `tests/error_watch.gd`, so
any logged error already exits with 1 (NOTES.md → Running it → "Any error
fails a suite"); warnings are expected and don't count. Most suites end with a
`PASS <suite>` line; the Markdown test ends with `N passed, 0 failed`. A
suite that exits 0 without its closing line is a failure too. Quote the first failing lines; don't
paraphrase them. If the branch adds a suite, check it installs the error
watch (the file's header shows how).

## 4. CI

CI runs only on pushes to `main` and by hand (NOTES.md → Running it →
Continuous integration), so a feature branch usually has no run: the local
suites above are its check. If a run exists for the branch (started by
hand): `gh run list --branch <branch> --limit 3`, and for a failed run,
`gh run view <id> --log-failed`. After a merge, read `main`'s run the same
way. Don't trigger a run yourself: the repo's Actions minutes are limited.
If another system matters for this change (macOS above all), suggest the
user starts one.

## 5. Report

A short table: suite | result | time. Then the failures with quoted output,
then any NOTES/CI list mismatch. Say plainly what wasn't run (no Godot, not
pushed yet) and why. Never call a skipped suite a pass.

What this can't check: looks, the mouse, both renderers, and the real
`claude`. If the change touches any of those, say a live check is still
needed and offer to write its steps into `tests/live/checklist.txt`.
