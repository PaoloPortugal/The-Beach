# W04's edge-arrow check was flaky

Features: tooling (tests/world/world_test.gd; W04)

The world test's "behind you: an arrow at the edge, with its project and
distance" failed 3 of 4 local runs on Windows (2026-10-07, both with
and without the fake). It also failed in main's CI run 37621906938
("Merge W04") on windows-latest. When it failed, `pointers.shown()` was
empty and the arrow's label had no text. The arrow existed but was
hidden. The game was fine: the test read the arrows before they had
been updated.

## Cause

`NewIslandPointers` places, shows and hides its arrows in `_process`.
The test turned the player (`player.rotation.y += PI`), then waited
`_frames(3)`, which are physics frames. h3's island had just been built
(`session.created`), so that frame ran long and the next main-loop
iteration caught up several physics steps in a row before any
`_process`. Instrumented, every failing run showed **0 process frames**
during the wait. At that moment `_edge()`, called directly, returned an
edge position, `is_position_behind` was true and the rotation had stuck.
So the arrow simply hadn't been updated since the player faced the
island. It is the same trap as 2026-10-03-world-test-flaky, with
`_process` instead of input.

Ruled out:
- The player overwriting the turn: there is no stored yaw, and mouse
  look calls `rotate_y` directly.
- The 64x64 headless window's margin: `margin()` is 16 px there, and the
  edge it gave was right.

## The fix

The three W04 waits that read state kept by `_process` now use
`_settle()` (two process frames) instead of `_frames(3)`:
- facing the island, no arrow (this check passed vacuously before:
  nothing had been updated)
- turned away, the arrow and its label
- on arrival, `unvisited`, the beacon and the arrow cleared (cleared in
  `SessionIslands._process`, freed in `NewIslandPointers._process`)

Nothing checked was dropped or loosened, and the game code didn't
change. NOTES → Running it now says that state kept by `_process` is
read after process frames.

## Checked

With the fix, the world test passed 6 of 6 runs plain and 6 of 6 with
`-- --sidecar-dev-fake` on Windows, one suite at a time. Before the fix,
4 of 4 instrumented runs failed.
