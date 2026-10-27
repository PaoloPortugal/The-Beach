# D01: fishing, designed

Features: D01, C15, A05

The first of the downtime activities (NOTES → Concept → Downtime) to be
designed with the user. Nothing is built yet. The agreed design is in
NOTES → D01.

## What was offered and chosen

- **Core loop.** I offered three loops and recommended A:
  - *A, cast and bite:* one press on the real bite, 10-40 s a catch.
    Easy to drop, but it is Animal Crossing's loop and code-town's
    (dev log 2026-10-23-similar-projects).
  - *B, set lines:* rods planted at the water's edge and collected
    minutes later. It fits waiting literally, but leaves little to do
    while you wait.
  - *C, active reeling.*

  **The user chose C.** For the fight I offered a line-tension fight
  shown mostly in the world (recommended, so the view stays on the sea
  and the beacons) or a Stardew-like catch bar; **the user chose the
  catch bar.**
- **Where, and what decides the catch:** my recommendation, any water's
  edge with the catch set by biome, water depth, time of day and
  weather, plus fish shadows you can see in W08's clear shallows. The
  user took it as a placeholder, to be replaced or joined by real fish
  swimming about once there are models. A hand net while diving was
  offered for later; not decided.
- **Agents:** the catch does not depend on agent activity (my
  recommendation, chosen). A bonus while agents work was turned down
  because it would reward spending tokens to fish.
- **Leaving mid-fight** (asked because reeling clashes with "never
  punish you for leaving"): the fish gets away and nothing else is lost
  (recommended, chosen). Rejected: the fish waiting on the line for a
  while (odd on a rod you walked away from), and a pause key (gamey,
  easy to abuse).
- **A05 during a fight:** the count pulses once and sits next to the
  bar when an agent starts waiting mid-fight (recommended, chosen),
  since your eyes are on the bar. No in-game sound, nothing paused.
- **ID:** a new **D** prefix for downtime (recommended, chosen); scope
  core (world only).

## The hotbar comes first

While I was writing this up, the user asked for an inventory first: a
simple hotbar that holds the tools, switched with the mouse wheel or the
number keys. For now that's the fishing rod; the bug net comes later.
Decided with it (user's, my recommendations unless noted): slot 1 is
empty hands, the rod is slot 2; the hotbar shows when you switch and
fades out when idle (the user's pick over always shown); ID **C15**.
It is designed and built on its own branch (NOTES → C15).
