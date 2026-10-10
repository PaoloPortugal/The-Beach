# C09's console checks waited on physics frames

Features: tooling (tests/world/world_test.gd; C09)

The world test's "C09: Esc closes it" failed once on GitHub Actions
(windows-latest, run 37933128611, branch w05-unbounded-clusters,
2026-10-09). It passed locally and on `main`. The game was fine: the
test read the console before the key had been handled.

## Cause

The same trap as 2026-10-03-world-test-flaky. After `_press("debug_console")`
and `_press("ui_cancel")` the test waited `_frames(2)`, two physics
frames. `_press` queues its events through `Input.parse_input_event`, and
Godot handles them once per main-loop iteration. On a slow runner, one
late iteration runs several physics steps in a row, so both frames can
pass before Esc is seen. NOTES → Running it already says a check after an
input waits on its condition. These two checks, new in C09, didn't.

## The fix

Both waits now use `_until` on the condition the check reads (open and
the player stopped; closed and the player free again), with a 2 s
timeout, like the sessions menu's Tab and Esc checks. Nothing checked
was dropped or loosened, and the game code didn't change.

The rest of the file was checked for the same pattern. Every other
`_press` is followed by `_until` or `_settle`. The `Input.action_press`
holds (walking, jumping, swimming) set the action's state at once and
are read in `_physics_process`, so physics frames are right for them.

## Checked

On Windows, the world test passed plain and with `-- --sidecar-dev-fake`,
one at a time, and C09's checks passed in 12 more runs, three at a time
(6 plain, 6 with the fake). In one batch of three plain runs, two failed
a different check, "a missing folder is refused, and the notice says
so": the sidecar's refusal didn't come within that check's 5 s wait. It
didn't happen again in six more plain runs. That is the menu's real
`session.create` reply under heavy load, unrelated to C09. It's left as
it is and noted here in case it comes back.
