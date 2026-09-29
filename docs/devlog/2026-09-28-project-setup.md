# Project setup

Features: docs, tooling

## What was set up

The user had already created the Godot project at the repo root (Godot 4.7,
pinned to 4.7.2-stable no-.NET in `.godotrc`, containing only
`project.godot` and the default `icon.svg`). It was left untouched. Added
around it:

- `CLAUDE.md`, `README.md`, `NOTES.md`, `docs/GUIDE.md`, this dev log.
- `sidecar/`: an empty folder with a `.gdignore` so Godot skips it.
- `assets/CREDITS.md`.
- `.gitignore` extended for Node, env files and OS/editor files.

## Decisions

- **Codename "The Beach"** (user's decision): the project name will change,
  so it's used only where a human-readable name is needed (docs, window
  title) and kept out of code identifiers, class names and the protocol.
  Its locations are listed in NOTES.md → Conventions → Renaming the project.
  It replaces DESIGN.md's working name "Claude Agent Island Visualizer".
- **Sidecar language left open** (user's decision). The brief assumed Node,
  but the user wants to investigate first, so no package was created. It is
  tracked as open question 6.
- **Feature ID prefixes** W (world), A (agents), C (chat and in-world UI),
  S (sidecar and sessions).
- The Godot project stays at the repo root; non-Godot folders sit beside it.

## Where DESIGN.md went

DESIGN.md was the one-off design brief for the first session. All of its
content moved into NOTES.md. The user approved this mapping and the original
file was retired (deleted).

| DESIGN.md section | Now in NOTES.md |
|---|---|
| Concept | Concept |
| World design: session = island, rise and sink | Concept; W01, W04 |
| World design: archipelagos | Concept; W05; open question 2 |
| World design: bridges, teleport menu | Concept; W06, W07 |
| World design: future biomes, general bridge system | W06; Deferred ideas |
| Agents: orchestrator, walk up to chat | Concept; A01, C01 |
| Agents: subagents, spawn and power down | Concept; A02 |
| Agents: state indicators | A03 |
| Agents: permission prompts shown visually | A05 (plus C05 for answering) |
| Scaling: procedural placement, no fixed max | A04; Protocol |
| Scaling: island growth, LOD, overflow rack | Deferred ideas |
| Entertainment / downtime | Concept; W03 (movement must allow parkour); Deferred ideas |
| Architecture: Godot, sidecar, transport, session = island | Architecture; Protocol |
| Multi-provider design | Architecture (multi-provider rules); S02; Conventions. Later revised; see [Provider scopes](2026-09-28-provider-scopes.md) |
| Session integration: JSONL store, resume | S04 |
| Session integration: desktop app not supported | S04; Deliberate limitations |
| Chat panel: streaming, code blocks, tool log | C02, C03, C04 |
| Chat panel: BBCode risk, prototype early | C03; Watch items; Milestone M0 |
| Art direction | Concept; Conventions; `assets/CREDITS.md` |
| Open questions 1–5 | Open questions |
| Suggested first milestone (v1 slice) | Milestones → M1, "(v1)" tags in the index |
