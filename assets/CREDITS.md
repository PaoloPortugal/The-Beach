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
| `world/ocean/ocean.gdshader` | Claude (Claude Code) | Shader. The ocean (W02, 2026-09-30): waves and flat shading. Rewritten for W08 (2026-10-08): see-through, tinted by depth, an underside. |
| `world/island/island_generator.gd`, `world/island/island.gd` | Claude (Claude Code) | Generated islands (W01, 2026-09-30): height field, flat-shaded triangles, colours by height. Shelf and drop-off added for W08. |
| `world/seabed/seabed.gd` | Claude (Claude Code) | Generated sea floor (W08, 2026-10-08). |
| `world/bridges/bridge.gd` | Claude (Claude Code) | Placeholder bridges (W06, 2026-10-07): planks, posts and rails from boxes and quads. |
| `world/platform/spawn_platform.tscn` | Claude (Claude Code) | Placeholder spawn platform: one wooden-coloured box. |
| `world/ocean/ocean.tscn` | Claude (Claude Code) | The ocean's plane mesh, for the shader above. |
| `agents/orchestrator/orchestrator.tscn` | Claude (Claude Code) | Placeholder orchestrator (A01, 2026-09-30): boxes, capsules and spheres. |
| `agents/subagent/subagent.tscn` | Claude (Claude Code) | Placeholder subagent (A02, 2026-09-30): primitives. |
| `agents/state_marker.gd` | Claude (Claude Code) | Placeholder state markers (A03, 2026-09-30). |
| `agents/attention_beacon.gd` | Claude (Claude Code) | Placeholder beacon (A05, 2026-10-02; W04's green one too). |
| `world/minimap.gd`, `world/world_map.gd` | Claude (Claude Code) | Placeholder maps drawn in code (W06, 2026-10-07). |
