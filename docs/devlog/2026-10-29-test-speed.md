# Faster headless suites: --fixed-fps 60

Features: tooling

The user asked whether the headless Godot suites (NOTES → Running it),
about 12 minutes locally, could be faster without checking less.

## What was slow

Per-section timing in the world test (its `time` lines) showed that
nearly all of it was waiting: headless Godot still runs in real time,
physics at 60 steps a second, so every `_frames(n)` and every animation
the test waits out costs real seconds. `_fishing` alone took 146 s
(about 8,000 physics frames of fights), `_main_menu` 20 s, `_swimming`
18 s, `_crouch_slide` 13.5 s. World generation (`_biomes`, ~3.5 s) and
the fake provider's turns (`_live`, ~18 s) were the only real work.

## What changed

`--fixed-fps 60` on every suite (user's choice, 2026-10-29: all suites,
not only the world ones, so the commands stay alike). Each frame is one
1/60 s step and the next starts at once. Measured on the developer's
Windows machine, one run at a time:

| Suite | Before | After |
|---|---|---|
| World (3 runs) | 255 / 257 / 258 s | 41 / 28 (D01 flake) / 40 s |
| World, fake provider (3 runs) | 179 (D01 flake) / 306 / 298 s | 79 / 79 / 79 s (live section paced, below) |
| Sidecar client | 38 s | 24 s |
| Sidecar client, fake provider | 30 s | 25 s |
| Bridges | 48 s | 24 s |
| Session store, clusters, performance, Markdown | 16, 4, 11, 3 s | about the same |

Every suite passed with the flag, but for D01's known flaky check (below). The physics frames each
world-test section took were the same with and without it: the checks
see the same frames.

Three world checks timed with the wall clock, which usually runs slower
than the game under the flag: C17's "fades into the menu after its
card's time" failed (0.3 s), and the agents' two `took < 1800` checks
(the thrower gone in about 1.3 s; all throwing to the orchestrator and
going) would have passed whatever happened. All three now read the
game's clock, `_game_ms()` (a long `SceneTreeTimer`'s time left), and
read the same as before without the flag (3.0 s, 1267 ms). So does the
D01 fight's time, shown in a check's message only. The sidecar's timeouts use
the wall clock (`SidecarClient._now()`), so its waits are unchanged.

## Found in the security review

- `_until`'s timeouts were in real seconds, so under the flag a wait on
  an animation allowed several times its game time: C17's "the first
  island rising lifts it" (1.5 s) would have passed through the
  island-wait cap (about 5.5 s of game time) even with the rising
  ignored. `_until` now bounds its wait in game time, as before the
  flag; `_until_wall` keeps real seconds for the real sidecar and the
  islands' worker-thread ground.
- The chat's pickup timeout (S06) is a game timer racing the fake
  provider's turns in the live section (0.5 s there): under the flag a
  slow runner could flake. That section now keeps the game's clock to
  the wall clock (`_pace`, an `OS.delay_msec` each frame when the game
  is ahead), so it runs as before; it's mostly sidecar time anyway.
- CI hasn't run with the flag (Actions minutes are paused): when it's
  back on, run the workflow by hand on all three systems first.

## Trade-offs

- With the flag a frame never runs several physics steps in a row, as a
  slow frame does in real time (see `_settle`'s comment). Headless runs
  no longer meet that case; the live checks do.
- Outside the paced live section, a check that something did *not*
  come from the sidecar, made after a number of frames, covers less
  wall time. None was found that relies on it.
- D01's flaky "reeling drags it through the water, not up" isn't about
  frame pacing: it failed both ways (0.20 m without the flag, 0.19 m
  with it, once each in about a dozen runs). Its own fix is a separate
  branch.

## Rejected

- `Engine.time_scale`: changes physics steps, so the checks would see
  different frames.
- Running suites in parallel: they share the test sessions folder and
  `user://` test files (two world tests at once broke D01's saved
  catches during these measurements).
- Shorter test-only animation waits: little left to gain once the
  waiting is gone.
