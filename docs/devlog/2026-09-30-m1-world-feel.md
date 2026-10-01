# M1 world feel

Features: W01, W02, W03, A01, C01, C02

## Decisions (user's)

Open question 8, settled against my recommendations of 2026-09-29:

- **Camera: first person**, not the third-person over-the-shoulder camera
  I recommended (that was to see your character for parkour later).
- **Movement** as recommended: `CharacterBody3D`, walk, sprint and jump,
  coyote time and jump buffering.
- **Island:** generated in code as recommended, and the user added some
  randomness, e.g. Perlin-style noise, so islands differ. The method is
  to look into when W01 is built.
- **Ocean:** flat-shaded low-poly water with gentle waves, as recommended.
- **Orchestrator:** a plain placeholder at a desk, as recommended.
- **Opening the chat:** "Press E to chat", E opens, Esc closes, as
  recommended.
- **Chat panel:** in the world, popping out of the agent and always
  facing you, instead of the screen-space panel on the right I
  recommended. Details are defined when C02 is built.

Still open: the props (Kenney Pirate, Nature and Furniture kits were the
suggestion).
