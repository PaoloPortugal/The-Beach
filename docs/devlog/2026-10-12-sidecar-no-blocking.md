# The sidecar without blocking: stored sessions and short names

Features: S04, C08

Two Watch items, fixed at the user's request (2026-10-12), each a way
the sidecar stopped handling everything else (replies, hook relays,
permission requests) while it waited on the disk or on Windows.

## S04: listing stored sessions

`session.list_stored` read transcripts newest first until 200 were
listed, synchronously: 0.8-0.95 s for 181 of them on a dev machine
(2026-10-09), seen as a 3 s wait in the world test (dev log
2026-10-09-world-test-waits). Only a sidecar's first listing reads every
file (the provider's `StoredCache`), but nothing else was handled
during it.

Now `listStored` is async: `fs.promises` for the folders, the files'
times (each folder's at once) and each file's first and last 64 KiB
(`describeAsync`, sharing its parsing with the synchronous `describeAs`,
which `findStored` still uses for the one file it reads on resume). The
cache's reader is async too. Measured on this machine's own store: a
first listing of 191 transcripts took about 0.66 s, and the event loop
never waited more than 7 ms at a time. Listing again from the cache:
about 50 ms. Test: other work (`setImmediate` turns) runs while a
listing of 34 files reads.

Left synchronous: a resumed session's history (`readHistory`), bounded
at 64 MiB, read once per resume.

## C08: a slow short-name answer

On Windows, a path component Windows hashes the short name of
(`AB2761~1` for `a b`) is asked of Windows PowerShell. That ran through
`spawnSync`, blocking the sidecar for about a second (a few under load,
at most 10 s). Past 10 s there was no answer, and `askWindowsOnce` kept
it for the run like any other, so if it was for a folder in every
session's relay path, no session got a status line until the sidecar
restarted. Seen only on CI (dev log 2026-10-09-c08-askwindows-flaky).

The Watch item offered two fixes: don't keep a timed-out answer, or ask
in the background. Both, since either alone falls short. Not keeping
alone means every session start blocks again for up to 10 s on a loaded
machine. Asking in the background alone still keeps a missing answer.

- `askWindows` runs PowerShell through `execFile` (`runInBackground`),
  with the same fixed script, folder, cleaned environment, `shell:
  false` and 10 s timeout. `execFile` kills it past that and says so
  (`killed`), which `askWindowsTimed` reports as `timedOut`.
- `askOnce` keeps each folder's pending answer. An answer, or Windows
  saying it has none (a volume without short names), stays for the run.
  One that timed out is dropped, so the next session asks again. Two
  sessions starting at once share one ask.
- `shortPath`, `shellCommand`, `ourStatusLine` and the provider's
  `writeSettings` are async. A session's start waits for the answer, as
  before, but the sidecar handles everything else meanwhile.

Nothing about what is trusted changed: the answer is still accepted only
if it is the very same file, on the same drive, every component safe.
The real-Windows tests (hostile folder names run nothing; the command
string reaches us as exactly three arguments in Git Bash, Windows
PowerShell and PowerShell 7) pass through the new runner. New tests:
other work runs while Windows is asked; a real process past its timeout
is stopped and said to be (and one that exits, fails or is missing
isn't); a timed-out answer is asked again, others kept, asks under way
shared.
