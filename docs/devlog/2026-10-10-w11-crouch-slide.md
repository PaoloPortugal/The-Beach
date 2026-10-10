# W11: crouch and slide

Features: W11, W03, W08

The user asked for crouching and sliding (2026-10-08), as a step from
W03's movement towards parkour. The design was settled the day before
building (NOTES.md → W11 → Decided): hold Ctrl; 1.1 m at 2.5 m/s; a
momentum slide where slopes matter; a slide jump that keeps its speed,
with a short wait before the next slide.

## What was built

All in `Player`; the numbers not in the decisions are my picks.

- **A separate `crouch` action** on the same physical Ctrl as
  `swim_down`, rather than one action for both, so the settings menu can
  rebind them apart later.
- **Crouching** shrinks the capsule from the top (feet stay put) and
  eases the eyes down. Standing up checks the room with `test_move` and
  waits for it. The capsule shape is duplicated in `_ready`, since its
  height now changes.
- **The slide's physics.** A constant friction, not a drag proportional
  to speed: with drag, a slope's pull balances out at a low speed (about
  4.5 m/s on 10°), so a slide could never "keep its speed downhill".
  Gravity along the slope is scaled by 4 so that downhill outweighs the
  friction from about 13° (roughly keeping speed on 10°, gaining on
  steeper); without the scale, no slope under 45° would beat the 8.5
  m/s² the flat fade needs. A 20 m/s cap keeps the mountain's long
  slopes sane.
- **Slide jump.** A jump (or an edge) while sliding sets a "momentum"
  flag until landing: in the air you steer at the speed you have instead
  of the air slowing you to walking or sprinting speed (12 m/s² would
  take away most of the slide in one jump). Normal jumps are unchanged.
- **Chaining.** The decision said "about 0.5 s before the next slide". A
  slide jump is in the air for about 1.1 s, so a plain 0.5 s timer would
  have run out in the air and allowed endless bursts. The wait counts
  only on the ground, and only the burst waits: landing with Ctrl held
  still slides, at the speed you have, and slows. Flagged for the user's
  review.

## Testing

`world_test.gd` → `_crouch_slide`, on its own test ground 500 m above
the world (a floor, a bar 1.2 m up, a 20° slope), so the measurements
don't depend on island terrain. The swim test now presses `crouch` with
`swim_down`, as the real key does, and checks you don't crouch.

## Two flaky checks, already fixed on `main`

While building, W04's "facing it: no arrow" failed twice and C09's "T
opens the console" failed in a run from Git Bash; neither is touched by
this branch. I took them for timing races and gave C09's checks
`_settle()`. Merging `main` showed both were already fixed there
(2026-10-09-world-test-waits: the arrow failed when the random new
island was a mountain, which starts deeper; 2026-10-09-c09-console-check-flaky),
so the merge keeps `main`'s fixes. The arrow check's failure message
from this branch, which prints what was shown and where, is kept.

## Live check

Passed (user's, 2026-10-10: "everything seems alright"), with my picks
confirmed: the burst's wait counted on the ground only, downhill gaining
from about 13°, 20 m/s top speed.
