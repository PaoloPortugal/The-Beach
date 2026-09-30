# Placeholder orchestrator and walking up to chat

Features: A01, C01, C02, W08

## Built

- **A01, placeholder:** Godot primitives (capsule, sphere, box desk) in
  the island's middle, per the decision to use a plain stand-in until the
  agent look is settled (open question 7). No art assets.
- **C01:** a chat zone on the orchestrator, "Press E to chat", E opens and
  Esc closes, with the player's controls off while the chat is open.

The player now spawns 6 m in front of the orchestrator instead of on the
island's centre, where the desk stands.

## Esc has two jobs

The player's Esc frees the mouse; the chat's Esc closes the chat and
recaptures it. The chat reads input in `_input` and marks Esc handled, so
the player (`_unhandled_input`) never sees it while the chat is open.
Checked in the running game: after Esc the chat is closed, the mouse is
captured and the controls are back.

## Headless Godot has no mouse

The first version of the test checked the mouse mode and failed: under
`--headless`, `Input.mouse_mode` always reads visible, whatever was set.
The headless test now checks the rest (zone, prompt, open, no walking
while open, close) and the mouse is checked in the running game through
godot-ai's key input.

## Decisions (user's)

- **C02's direction, revised:** a small window above each orchestrator,
  always visible and facing you, shows its latest message; E opens the
  full chat panel (history and message box) over almost the whole screen.
  This replaces the whole panel living in the world. The C01 stand-in was
  switched to a near-full-screen panel to match.
- **Sea respawn stays** for now (W03). Swimming and a seabed with varied
  depths are a new planned feature, W08.
