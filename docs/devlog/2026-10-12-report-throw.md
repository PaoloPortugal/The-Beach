# A02: the report throw

Features: A02

## The problem (user's, 2026-10-12)

A finished subagent walked its report back to whoever called it, at
3 m/s with a paper over its head: 3 s from the first ring (10 m out),
more from the outer ones, up to the 20 s give-up. But Claude Code hands
a subagent's result to its caller before the world hears it's done (the
`SubagentStop` hook), so the orchestrator was already working with a
report the world still showed on its way. The user saw it live: the
orchestrator moving on before the paper arrived.

The lag itself can't be fixed: the world only learns of the report once
it has been delivered. The user's idea was to make it short: cut the
walk, and have the subagent toss the paper in an arc to the
orchestrator.

## The decisions

I asked about three details, each with a recommendation; the user took
all three:
- **Flight time:** the same 0.6 s from any distance, the arc higher for
  farther throws, so every report lands about 1 s after `done`.
  Rejected: longer the farther (natural, but the outer rings lag more);
  about 0.3 s (barely reads as a throw from far away).
- **The thrower:** stands up at its PC, a quick wind-up, throws, and
  shrinks away with its PC once the paper lands. Rejected: throwing
  from its seat; lingering a second or two after.
- **The catch:** the caller (the orchestrator, or a parent subagent
  still at its PC) bobs as the paper lands. Rejected: nothing; the paper
  staying on its desk a few seconds.

## How it's built

`Subagent.report_to(catch_at, on_caught)`: a tween stands it up 8 cm
turned to the catcher (0.15 s), leans it back and forward (0.2 s), then
lets the paper go as `top_level` so it flies in world space. Each frame
the paper moves along the line to the catcher's head (followed if it
moves) plus `4·t·(1−t)` times the arc height (a quarter of the
distance, at least 1 m), spinning. On landing the paper is put back on
its head, hidden, the catcher's `bob()` runs, and the subagent shrinks
with its PC. `Orchestrator` and `Subagent` both have `catch_point()` and
`bob()`; the orchestrator's bob lifts its body and head from their
resting heights, so a bob cut short by another can't leave it raised.

What went: the walk (its speed, arrival distance, 20 s give-up, the
ground callable used to stand on the terrain), and the PC shrinking at
once on `done` (it now goes with the subagent). A resumed subagent mid-
throw is back at its PC with the paper put away, as before.

## Checking it

The world test's subagent checks now cover the throw, the arc, the bob,
the time to gone (about 1.25 s; checked under 1.8 s), a resume
mid-throw, and three thrown to the orchestrator at once. Screenshots in
the real renderer (a scratch script; saving a PNG mid-throw stalls the
game for 0.8 s, so the images were kept in memory and saved at the end)
showed three papers arcing over a snowy island, where the white paper
is hard to see against the snow: placeholder, like the rest of the
agents' look until the user's models (open question 7).
