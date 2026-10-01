# Island, ocean and first-person movement

Features: W01, W02, W03

The first playable scene: a generated island, the ocean and the player
(`world/`). Built to the decisions in 2026-09-30-m1-world-feel.

## Island (W01)

A seeded height field (Perlin noise from `FastNoiseLite`), not a sculpted
mesh or Kenney's island models, so islands differ and can later grow or
change per session. The shoreline noise is sampled around a circle so the
outline closes without a seam.

First version, found by looking at it from above: shoreline noise at
±60 % and dunes that ran on past the shoreline gave ragged islands with
holes, lagoons and stray islets. Now ±45 % (about ±30 % in practice) and
the dunes fade out before the beach.

**Vertex colours are sRGB.** The island first rendered pure white with no
visible shading: `StandardMaterial3D` reads vertex colours as linear
unless `vertex_color_is_srgb` is on, so the sand palette came out far too
bright and blew out. With it on, plus less sky ambient (0.6 energy, 0.5
sky contribution), the low-poly faces read.

## Ocean (W02)

Flat shading from `dFdx`/`dFdy` of `VERTEX` in the fragment shader, which
Compatibility supports. The 600 m plane's edge showed as a band at the
horizon: the procedural sky's dark "ground" below the horizon was visible
past it. Fixes: the plane (now 800 m) follows the camera in whole cells;
depth fog completes before its edge; the sky's horizon and ground colours
equal the fog colour. Exponential fog couldn't hide the edge without
greying the island too.

## Movement (W03)

`JumpAssist` is a separate `RefCounted` so coyote time and buffering are
unit-tested without physics. The world test also runs the real scene
headless: landing, walking, jumping and the sea respawn. In the editor, a
real W key press moved the player, and Esc freed the mouse.

`godot-ai`'s `input_map_manage` can only bind key labels, not physical
keys (NOTES → Platforms: movement uses physical keys), so the actions were
written into `project.godot` by hand. The open editor keeps its own copy
of the project settings: reload the project before changing settings in
the editor, or its next save drops the actions.

## Compatibility renderer

Rendered one frame under each renderer with a throwaway script. Under
Compatibility (4.7.2, AMD Radeon, OpenGL 3.3) any directional shadow
turned the island pure white: every shadow mode, and even with the sun at
0.3 energy; with shadows off it matches Forward+. The world turns sun
shadows off under Compatibility. NOTES → Watch items.

## Open

- Falling in the sea respawns you on the middle of the island; a
  placeholder, to revisit with the user.
- Props (Kenney kits) still to decide.
