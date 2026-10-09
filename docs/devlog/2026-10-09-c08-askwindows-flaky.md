# C08: the short-name tests on a slow Windows runner

Features: C08, tooling (sidecar/src/launch/shell-command.ts, sidecar/test/usage.test.ts)

Two `main` runs on 2026-10-09 (37864539718 and 37964506946) failed on
`windows-latest` and passed on rerun. Both times "askWindows, for real: a
hostile folder name runs nothing, and any answer is that very folder"
failed with `$(New-Item PWNED): Windows answers on a volume with short
names`, actual `null`. The second time "the command string, run by the
real shells, reaches us as exactly our three arguments, whatever the
paths" failed too: `a command for paths with spaces, separators and
accents`, actual `null`.

## Cause: PowerShell started slower than askWindows waits

The hostile-name test failed after 10049 ms and 10346 ms: one ask, ended
by `askWindows`' own `spawnSync` timeout of 10 s, which comes back as no
answer. The shell test took 28.8 s, against 3-6 s when it passes: its
asks for the hashed names (`a b`, the mixed-case temp folder, ...) went
through the default `shortPath`, with the same 10 s, and one ran out, so
there was no command.

On the passing runs before them the hostile test's three asks took
2.7-7.9 s together, so up to a few seconds each. On the dev machine one
ask takes 0.7-1.3 s idle and 1.9-4.9 s with every core busy (16 busy
Node loops). CI's runner has fewer cores, and `node --test` runs the
test files side by side. So it's slowness, not a hang: Windows
PowerShell starting, plus the COM object, sometimes passing 10 s.

## The fix: the tests wait longer, the checks stay

`askWindows` takes a `timeout` (default `ASK_TIMEOUT_MS`, still 10 s).
A timeout of 0 or less means the default, since `spawnSync` reads 0 as
no limit and a hung PowerShell would then freeze the sidecar; the unit
test checks the default is passed and is between 0 and 10 s, and that 0
and -1 fall back to it (the security review's note: comparing the
timeout with its own constant alone would have passed at 0). The tests that ask the real
Windows give it 30 s: the hostile-name test directly, the short-names
probe and the shell test through a `shortPath` that asks with 30 s
(`shellCommand`'s `shortPath` option). The same code runs, the same
assertions are made: the same folder by file identity, nothing named
`PWNED` anywhere, always the System32 PowerShell, exactly three
arguments in every shell. The hostile test now logs each ask's time,
and its failure says how long it waited. The shell test's limit went
from 120 s to 600 s, since it asks a dozen times.

Rejected: raising the sidecar's 10 s. The ask blocks the sidecar
(`spawnSync`) while a session starts, and a missing answer only means no
status line (transcript only). Not seen outside CI, so it's a Watch item
in NOTES (A slow short-name answer is kept for the run): the missing
answer is kept for the run like any other, so a shared folder's timeout
would mean no status line for every session until the sidecar restarts.

## Checked

The branch's first CI run failed on Linux: the new unit-test line asked
without the test's `env`, so with no `SystemRoot` `askWindows` returned
before running anything. It passes the `env` now, and passed locally
with `SystemRoot` unset.

`npm run typecheck` and `npm test` in `sidecar/` on Windows; the two
tests passed with every core busy too.
