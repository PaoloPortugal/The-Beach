# S01: retrying the sidecar's start

Features: S01

Step 1 of three on branch `s01-start-retry` (the user's order,
2026-10-28): retry a start that fails in a way that can pass; then
restart the sidecar if it dies in play; then a loading bar at the
game's start. The design is NOTES → S01 → Start retry.

## Why

In a live test the game logged "The sidecar didn't start in time." The
client started the sidecar once: no handshake within 20 s, and it gave
up for the whole run. The sidecar's stderr lines just before that error
in the run's log would say why it was slow; that log wasn't at hand, so
the likely cause stays a guess: a cold first start (Node loading the
bundle, the first look for Claude Code and its running sessions, an
antivirus scan of a new executable).

## Decided (the user's, 2026-10-28)

- Retry when the handshake times out, the sidecar exits while starting,
  the handshake is bad, or connecting fails.
- Three attempts in all, 2 s then 5 s between them, each waiting longer
  for the handshake: 20 s, 30 s, 45 s.
- Each retry ends the stuck process first, so there are never two
  sidecars.
- No retry for a missing executable, a protocol version mismatch, or
  `OS.execute_with_pipe` failing: those won't pass by trying again.
- Retries go to the log only; `failed` is emitted once, after the last.
- `stop()` keeps closing the pipe and killing after 3 s.
- `LoadingCover` (unused since C14, kept) waits past all the attempts.

## How

- `start()` resets the attempt and calls `_launch()`, one attempt.
  The failures that can pass go through `_start_failed()`, which logs a
  warning, calls `stop()`, and sets a time to try again; `status` stays
  `STARTING` meanwhile, so `start()` does nothing and the loading cover
  doesn't lift. `stop()` clears that time, so stopping during the wait
  cancels the next attempt.
- `_connect()` now returns its error: during a start it's a retry,
  while reconnecting to a running sidecar it still fails (step 2's).
- `START_TIMEOUT_S` (102 s) is the longest start, a constant folded from
  the two arrays; `LoadingCover.TIMEOUT_S` is it plus 10 s.

## Found on the way

- **An early exit logged an engine error.** A sidecar that exits before
  the handshake leaves an empty line, and `JSON.parse_string("")` logs
  "Parse JSON failed" as an error, before the client's own message. Fine
  when that was the end anyway; wrong once it's retried, and the suites
  fail on any error. Parsed with a `JSON` instance now, which doesn't log.
- **A missing `--sidecar=<path>` depended on the OS.** On Windows
  `OS.execute_with_pipe` fails at once (with an engine error, "Could not
  create child process"); on Linux and macOS the fork succeeds and the
  child's exec fails, which would read as "stopped while starting" and be
  retried three times. The path is now checked first, as the exported
  game's own executable already was, and fails at once everywhere.
- **The error watch had no way to expect an error.** The final failure is
  a `push_error`, which fails a suite. `ErrorWatch.expect(text)` lets the
  next error containing that text pass, once.
- Freeing a client in a test right after it became ready reported
  "Object is locked and can't be freed"; the test stops it and uses
  `queue_free()`.

## Tests

`tests/core/sidecar_client_test.gd`, on fake sidecars
(`tests/core/fake_sidecar.mjs`, run with Node) with the attempts
shortened to 0.5, 0.7 and 0.9 s and the waits to 0.2 and 0.3 s:
slow (three attempts, each waiting its own time, `failed` once), exits
at once, a bad handshake (each: three attempts, each process ended
before the next starts, none left, `failed` once with its reason),
stopped during the wait (nothing started after), another protocol
version and nothing at `--sidecar=<path>` (failed at once, no retry),
and a start that fails once then works (the dev fake sidecar; ready, no
`failed`). Not covered by a fake: the WebSocket connect failing
(`connect_to_url` on 127.0.0.1 doesn't fail on demand); it takes the
same path as a bad handshake.
