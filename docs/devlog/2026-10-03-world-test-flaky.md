# The world test's flaky checks

Features: tooling (tests/world/world_test.gd; C01, C02, C04)

`world_test.gd` failed now and then, seen on 2026-10-03: locally on
Windows (without the fake) "the panel shows the chat so far" once in six
runs, then an out-of-bounds error from the next check; on GitHub Actions,
main's "Merge C06 + C07" run (macOS) "Esc closes the chat". The game was
fine; the test read state before it had settled.

## Causes

- **Physics frames don't follow input.** `_press` goes through
  `Input.parse_input_event`, and Godot handles queued events once per
  main-loop iteration. `_frames(n)` counts physics frames, and an
  iteration that ran late does several physics steps back to back
  (up to `max_physics_steps_per_frame`). So after a slow frame, both of
  `await _frames(2)` could pass before Esc or E was seen. The macOS
  failure.
- **The chat panel builds older messages over frames** (C03's build
  budget, 8 ms a frame, at least one message at once). Opening the chat
  with two messages built the newest at once; on a slow frame the older
  one came a process frame later, after the check. The Windows failure.
- **The same, hidden:** after `load_history`, the panel lays itself out
  again deferred and over frames, so `panel.tool_fold("u1")` could still
  be null two physics frames later. The resulting `SCRIPT ERROR` aborted
  `_tool_log` mid-way, skipping its last two checks, and the suite still
  printed PASS. Not seen in 20 runs of the old file; it showed once the
  other waits had changed the timing.
- **Two events read as one** (with the fake): the live plan check waited
  for the card (`plan.asked`) and then read the status, which follows the
  next event (`agent.state_changed`), sometimes a frame later.
- **A shared file:** the A05 checks used one settings file in `user://`,
  so runs side by side deleted each other's. It is now per process.

## Checked

Under load (three runs at a time, Windows), the old file failed 3 of 20
runs, every time with the reported "chat so far" failure; the fixed one
none of that kind.

## The fix

Each check that follows an input, a deferred call, a reply or a layout
now waits on its condition with `_until` (bounded, so a real failure
still fails): the chat opening and closing on E and Esc, the panel
having built every message, the re-layout after `load_history`, the
menu closing, the system picker's deferred answer, the prompt showing
before E, the ended session's island going, the plan card and the status
together. Checks that something did
*not* happen (Esc closed only the link's question; the picker's late
answer is ignored) wait with the new `_settle()`: two process frames,
one whole iteration, so the event or deferred call has been handled.
Physics checks (landing, walking, jumping, the sea, teleporting) keep
their frame counts: there, physics frames are the unit. Nothing checked
was dropped or loosened.

Not changed: the suites still pass when a `SCRIPT ERROR` cuts a
coroutine short; only reading the output catches it.
