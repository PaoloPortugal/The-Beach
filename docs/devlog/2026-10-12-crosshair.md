# The crosshair

Features: C11, C01, W10, C10

Until now E acted on whatever you stood near: the orchestrator's chat
zone (a 2.5 m sphere, C01) showed "Press E to chat" at the bottom of the
screen, and a zipline post (W10) showed "E: zipline up" floating over
it within 2 m. Two things near each other meant guessing which E would
pick, and every new thing to use would need its own prompt.

## The design (user's, 2026-10-12)

The user asked for a crosshair: a small circle in the middle of the
screen that grows when you look at something you can use and are close
enough, with what E does under it. I asked about the open details, each
with a recommendation; the user took every one:
- **E acts only on what the crosshair is on.** Rejected: a crosshair for
  looks only, with E still acting on whatever is near (the circle and E
  could then disagree).
- **The old prompts go.** "Press E to chat" and the zipline's floating
  labels are replaced by the hint under the circle. Rejected: keeping
  them beside it, two ways of saying the same thing.
- **A ring at rest, a bigger ring on a target** (1.5 px to 5.5 px radius
  in 0.1 s, white with a dark outline). Rejected: a dot that turns into
  a ring.
- **The hint:** "E  Talk", "E  Zipline up", "E  Zipline down", the key
  named from the `interact` binding so another layout or a later rebind
  shows the right one.
- **Hidden without the controls** (chat, menus, the sessions ring, the
  map).
- **A setting** in the Game tab, "Crosshair", on by default. Off hides
  the ring only: aiming and the hint stay, so E still works and still
  tells you what it does (my pick). Rejected: no setting.
- **Scope: core**, world only.

## How it's built

An `Interactable` node (hint, reach, radius, `used` signal) marks what
can be used; the `Crosshair` picks the one nearest the view's middle,
in front, within its reach (from the camera) and within its radius of
the view's line, with a ray to it that may only hit its own parent's
colliders (so the orchestrator's desk doesn't block its own "Talk").
E is read by the crosshair alone and emitted on the target.

Reaches: the orchestrator 3.5 m (about where its 2.5 m zone let you
talk, counted from the camera instead of the feet), a zipline post 3 m
(its 2 m across the ground, plus the height to the camera).

## What went

The orchestrator's `ChatZone` (an `Area3D`) and its
`player_entered`/`player_exited` signals; the chat's "Press E to chat"
`Label`, `prompt_visible` and the list of nearby orchestrators; the
zipline's `Label3D` prompts, its nearest-end check and its own E
handling; and the player's `player` group, which only that check used.
The user was told about the deleted nodes when the code landed.

## Bugs on the way

- **The key's name, headless.** Naming the physical key with
  `DisplayServer.keyboard_get_keycode_from_physical` errors under the
  headless display server (the tests). Headless, the crosshair names the
  physical key as on a US keyboard instead; a real window asks the
  layout.
- **Tests that pressed E by standing near.** The chat, zipline and
  fake-provider tests walked up and pressed E; they now turn the player
  to face the target first (`_face`).

## Not checked headless

How it looks: the ring's size, the outline on bright sand and sky, at
night. A screenshot of the ring and "E  Talk" looked right; the rest is
the live check.
