# D02: bug catching, designed

Features: D02, D01, C15, C11

The second downtime activity designed with the user, right after fishing
(dev log 2026-10-27-d01-fishing-design). Nothing is built yet. The
agreed design is in NOTES → D02.

## Taken as settled, as for fishing

I proposed these without asking, and the user didn't object:
- the ID D02 and the scope core (world only);
- the net as the hotbar's slot 3;
- catches independent of agents;
- a miss costs only that bug;
- placeholder shapes until there are models;
- catches go into the shared collection.

## Offered and chosen

- **Core loop.** I offered three:
  - *A, stalk and swing* (recommended, chosen).
  - *B, a swing followed by a timing minigame.* Rejected: it would
    play like fishing twice, with another overlay your eyes stay on.
  - *C, a chase as the main loop.* Rejected as the main loop: longer,
    takes you away from the agents, and harder to tune. It is kept
    for a few rare bugs.

  With code-town already doing bug catching (dev log
  2026-10-23-similar-projects), I offered stealth as what sets ours
  apart: sprinting or landing nearby scares bugs off, and crouching
  (W11) lets you creep up.
- **Sneaking:** the user took it, and added that players need to see
  when they're making noise: "a little noise meter when holding the
  net, like botw's one".
  - *Where it sits:* I recommended above the hotbar. **The user chose
    the bottom-right corner, like BotW's,** above C08's usage limits.
  - *The weather covers your noise* (recommended, chosen): wind and
    rain raise the meter's floor, like BotW's ambient sound, which goes
    with fewer bugs out in the rain.
- **The use button**, for every tool: **left click**. Recommended and
  chosen, so E keeps its one meaning from C11 ("act on what the
  crosshair is on"). Rejected: E for both (two meanings), and right
  click (unusual for a main action). It is recorded in D01 too.
