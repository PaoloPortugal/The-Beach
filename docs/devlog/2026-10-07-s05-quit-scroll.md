# The quit warning's list scrolls

Features: S05

## The bug

The user's report (2026-10-07): with the W06 layout demo's 64 made-up
sessions, the quit warning listed every session in one tall text, grew
past the bottom of the window, and the Quit button couldn't be reached.
There was no way to scroll.

## The fix

The dialog's text was the `ConfirmationDialog`'s own `dialog_text`, which
only grows. `QuitGuard` now builds it from three labels: the header ("N
sessions are still running:"), the list in a `ScrollContainer`, and the
hint about `/exit`. `_fit()` sizes it: the dialog is 560 px wide (or the
window's width less a 16 px margin each side), the labels are measured at that
width less the panel's margins, and the list gets the height the rest
leaves, scrolling for more. It refits whenever its text changes and when
the window is resized. In a window too short for even the header and
hint, it keeps its bottom on screen, so the buttons stay visible.

Picked as the conventional fix, no design question (placeholder UI):
the header and hint stay put and only the list scrolls, so the count and
the `/exit` hint are always shown.

Two things that cost a try each: a wrapped `Label`'s minimum height
depends on its width, so a label has to be given its width (and
`update_minimum_size()`) before the dialog is measured, or the stale
heights from a narrower layout are used; and the labels sit inside the
panel's margins, so measuring them at the dialog's full width wrapped one
line short and the buttons ended up just off screen.

## Tests

The world test's `_quit_many` lists 64 sessions in windows of 1152x648,
640x360 and 320x180 and checks Quit and Back to the game are inside the
window; in the two larger ones, that the list scrolls and the hint is
still there. The test window is 64x64, narrower than the button row
alone, so the test resizes it and puts it back.
