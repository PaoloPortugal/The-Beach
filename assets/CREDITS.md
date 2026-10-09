# Asset credits

Every asset in the project, with its source and license. Allowed: made by the
project's author, or CC0 (e.g. Kenney). Never AI-generated.

| File | Source | Author | License | Notes |
|------|--------|--------|---------|-------|
| `assets/audio/attention.ogg` | [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds), `question_002.ogg` | Kenney | CC0 | A05's chime. Picked by the user. |
| `icon.svg` (repo root) | Godot default project icon | Andrea Calabró (Godot logo) | CC BY 4.0 | Placeholder. Not CC0; replace before release. |

## Shaders and code-generated visuals

Shaders, and placeholder or generated visuals built in code (meshes from
primitives or vertices, colours, drawn maps), written by Claude
(Anthropic's model, through Claude Code). They are listed so nobody
mistakes them for hand-made work. They are code, not drawn or generated
images, and the user doesn't count them as AI art, but some people might.
Every new one Claude writes or rewrites gets a row.

| File | Written by | Notes |
|------|------------|-------|
| `world/ocean/ocean.gdshader` | Claude (Claude Code) | Shader. The ocean (W02, 2026-09-30): waves and flat shading. Rewritten for W08 (2026-10-08): see-through, tinted by depth, an underside. W09 (2026-10-08): wave speed from the wind, rain rings. |
| `world/sky/sky.gdshader` | Claude (Claude Code) | Shader. The sky (W09, 2026-10-08): gradient, sun and moon discs, stars. |
| `world/sky/clouds.gd`, `world/sky/rain.gd`, `world/sky/lightning_bolt.gd` | Claude (Claude Code) | Generated weather (W09, 2026-10-08): low-poly clouds from flattened blobs, rain streaks (particles), a lightning bolt ribbon. |
| `world/sky/night_light.gd` | Claude (Claude Code) | Placeholder night lights (W09, 2026-10-08): torches and a desk lamp from primitives, with a warm light. |
| `world/island/island_generator.gd`, `world/island/island.gd`, `world/island/biome.gd` | Claude (Claude Code) | Generated islands (W01, 2026-09-30): height field, flat-shaded triangles, colours by height. Shelf and drop-off added for W08; underwater colours from the sea floor's (2026-10-08). Biomes (W10, 2026-10-08): forest, mountain, snowy and desert shapes and palettes, rock on steep slopes. Tall mountains (2026-10-09): a cliff up to a high meadow among spires. |
| `world/island/island_props.gd` | Claude (Claude Code) | Placeholder props (W10, 2026-10-08): trees, pines, snowy pines, bushes, rocks, cacti and shrubs from Godot's primitive meshes, flat-shaded with vertex colours. The beach's palms, tropical plants, sand castles, starfish and shells (2026-10-09). |
| `world/island/zipline.gd` | Claude (Claude Code) | Placeholder zipline (W10, 2026-10-09): two posts and a cable from cylinders, flat-shaded with vertex colours. |
| `world/seabed/seabed.gd` | Claude (Claude Code) | Generated sea floor (W08, 2026-10-08). Warped noise, mounds and a colour gradient by depth added the same day (W08 follow-ups). |
| `world/bridges/bridge.gd` | Claude (Claude Code) | Placeholder bridges (W06, 2026-10-07): planks, posts and rails from boxes and quads. Steps on steep bridges (W10, 2026-10-08). |
| `world/platform/spawn_platform.tscn` | Claude (Claude Code) | Placeholder spawn platform: one wooden-coloured box. |
| `world/ocean/ocean.tscn` | Claude (Claude Code) | The ocean's plane mesh, for the shader above. |
| `agents/orchestrator/orchestrator.tscn` | Claude (Claude Code) | Placeholder orchestrator (A01, 2026-09-30): boxes, capsules and spheres. |
| `agents/subagent/subagent.tscn` | Claude (Claude Code) | Placeholder subagent (A02, 2026-09-30): primitives. |
| `agents/state_marker.gd` | Claude (Claude Code) | Placeholder state markers (A03, 2026-09-30). |
| `agents/attention_beacon.gd` | Claude (Claude Code) | Placeholder beacon (A05, 2026-10-02; W04's green one too). |
| `world/minimap.gd`, `world/world_map.gd` | Claude (Claude Code) | Placeholder maps drawn in code (W06, 2026-10-07). |
