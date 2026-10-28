# S01: retrying the sidecar's start, and restarting it

Features: S01

Step 1 of three on branch `s01-start-retry` (the user's order,
2026-10-28): retry a start that fails in a way that can pass; then
restart the sidecar if it dies in play; then a loading bar at the
game's start. The design is NOTES → S01 → Start retry; step 2 is
below (NOTES → S01 → Restart, When it can't be started).

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
- Until the first `sync.completed`, a closed connection is a failed
  attempt too (`_starting`). The docs-sync review found the first
  version retried only `connect_to_url` failing at once, which on
  127.0.0.1 hardly happens; a refused connection went to the old
  reconnect branch and looped with no attempt counted.
- From the security review: a retry whose process can't be ended (a
  failed kill) fails the start instead of risking two sidecars; the wait
  is read with its index clamped; and an `expect()` never used up fails
  the suite, so a leftover can't hide a later real error. Noted, not
  changed: each attempt is a new sidecar run, so S02's login-shell
  lookup can start once per attempt (it ends itself after 10 s), and
  `stop()` can block the main thread up to 3 s per attempt that sent a
  handshake, as it already could once.
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
at once, a bad handshake, connections refused (each: three attempts, each process ended
before the next starts, none left, `failed` once with its reason),
stopped during the wait (nothing started after), another protocol
version and nothing at `--sidecar=<path>` (failed at once, no retry),
a start that fails once then works (the dev fake sidecar; ready, no
`failed`), and a good handshake whose connect fails at once (the first
sidecar ended, the next ready). Not covered: a kill that fails (it
can't be made to on demand).

# Step 2: restarting the sidecar in play

## Decided (the user's, 2026-10-28)

- The sidecar must always be running. A start, first or a restart,
  gives up within a minute or two (the start's attempts, about 102 s at
  most).
- If the first start fails, the game quits: "without sidecar there's no
  experience". If a restart in play fails, a notice says so and asks
  you to quit.
- After a restart, sessions keep their ids ("Sidecar keeps ids"), so a
  restart is a plain resync: islands, chat, cards and W12 stay.

## How

- `SidecarClient._restart()` runs when the sidecar dies in play, or a
  reconnect to a running one fails at once: it emits `restarting`,
  stops what's left and runs the start's attempts again. A sidecar that
  dies again within `STEADY_S` (60 s) of being up goes on with the
  attempts of the start that brought it up instead of counting from one,
  so one that keeps dying ends in `failed` within the same bound instead
  of restarting forever. `has_synced` (did any start reach a sync) and
  `failure` (the last reason) are for the world.
- `SidecarLost` (`world/sidecar_lost.gd`, a placeholder): `failed`
  before any sync shows the reason in `OS.alert` and quits with exit
  code 1; `failed` after one covers the world with a notice whose one
  button, Quit, goes through `QuitGuard.request_quit` ("Back to the
  game" brings the notice back).

## Found on the way: new ids on every restart

The first build restarted fine, but the new sidecar's registry gave
every session a new `randomUUID`: to Godot, every session had ended and
a new one appeared, so each island sank and rose again (W12 keeps the
biome and seed, not the spot) and an open chat closed. The user's
choice: the sidecar keeps each session's id.

- A session the game launched writes its protocol id to its run
  folder's `session.json` (`session_id`, optional, so the record's
  version stays 1); the sidecar that takes it back passes it to the
  registry's `adopt`. A folder from before, or whose `session_id` isn't
  a UUID, gets a new id, written back, so the next restart keeps that.
- A session started outside the game (S08) has no run folder: its id is
  `derivedId(provider, native_id)`, a version-8 UUID from SHA-256 of
  both, the same on every run. Not a secret: `native_id` is in the
  snapshot already, and an id opens nothing: every connection needs its
  token (NOTES → Security rules → Authenticate every connection).
  Hashed rather than used as is so every id looks the same and two providers can't collide. An outside session that
  switched conversations since its island came up gets a different id
  at the restart (sinks and rises again); left as is.
- The registry refuses an id already in use: that session isn't taken
  back (logged), its folder left for a later start. Two folders with the
  same `session_id` (a copied folder) can't make two islands share one.
- **The chat after a restart.** With the same ids the world no longer
  fetches the chat again, so what was said while the sidecar was down
  would be missing, and live messages and the transcript's name the
  user's turns differently (a prompt id against the entry's uuid), so
  merging would show them twice. Once a restart has synced,
  `ChatController` fetches each loaded chat again and replaces ours,
  keeping what arrived since (`SessionStore.begin_chat_replace`, as for
  a `/clear` switch); an empty answer (transcripts off) keeps ours. My
  call, an implementation detail of "chat stays".

## Tests

`tests/core/sidecar_client_test.gd`: the restart on the real sidecar
(killed in play: synced again, a new process; killed again soon after:
the next attempt; a reconnect failing at once while it still runs,
from the security review: the old process ended before the new one
appears, ready, no `failed`) and on the dev fake one killed each time
it's up (failed once, after three). `tests/world/world_test.gd` (`_sidecar_lost`
on stand-in clients: the message box and quit at a failed first start,
the notice, Quit through the quit guard, Back to the game; and
`_restart_chat`: each loaded chat fetched again once, an empty history
keeping ours). `sidecar/test/reattach.test.ts`: the id written at
launch, kept across two sidecar runs for a launched and an outside
session, an old folder's new id written back, one in use refused, a bad
`session_id` dropped. `tests/core/session_store_test.gd`: a restart's
resync with the same ids removes and adds nothing and keeps the chat.
The dev fake has no reattach, so Godot's side is on stand-ins; the
live checklist has the real restart (kill the sidecar in Task Manager).

Review follow-ups: a restart opens the hook-port gap (Security rules →
Known gap) for the moment between the old sidecar's death and the new
one's bind; written down, not closed. Not built (the user's call):
clearing open cards as soon as `restarting` fires, rather than at the
resync.
