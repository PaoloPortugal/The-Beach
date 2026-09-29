# Claude Agent Island Visualizer

## Concept

A 3D working environment, built in Godot 4, that visualizes Claude Code
sessions and their subagents as a game world you physically walk around in.
This isn't just a passive monitor — it's meant to be an actual place to work:
create sessions, resume old ones, and chat with the orchestrator, all from
inside the 3D world.

## World design

- **Setting:** a beach/ocean world. Each **Claude Code session** is
  represented as an **island**.
  - Creating a new session → an island rises out of the ocean (this doubles
    as the "new session" animation/feedback).
  - Ending a session → its island sinks and is removed.
- **Grouping:** islands belonging to the same project/repo cluster together
  into an **archipelago**. Unrelated projects get their own area of ocean.
- **Travel:** islands within an archipelago are connected by **walkable
  bridges** for physical, on-foot movement between nearby islands.
  - Additionally, since this is meant to be a productivity app, there needs
    to be a **teleport menu** that instantly jumps you to a given session's
    island — you shouldn't have to walk across the whole world just to talk
    to an orchestrator. Bridges are for the feel/exploration of the world;
    the teleport menu is for actually getting work done quickly.
- **Future expansion (not v1, but design for it):** other terrain/biome types
  (hills, mountains, etc.), still connected via the same walkable-bridge
  system. The "connect regions with bridges" mechanic should be built as a
  general system from the start, not hardcoded to beaches, even though
  beaches are the only biome in v1.

## Agents

- **Orchestrator:** sits at the center of its island (e.g. bigger logo
  model at a beach desk / under an umbrella). Walking up to it opens the
  chat panel for that session — this is the primary way you interact with
  Claude from inside the world.
- **Subagents:** appear as small Claude-logo-on-little-PC models scattered
  on the island's sand.
  - Spawn in when the orchestrator spawns them, disappear/power down when
    they finish.
  - Should have a visible state indicator: working / waiting on user input
    (e.g. permission prompt) / done.
- **Permission prompts:** ideally surfaced visually on the relevant
  island/agent so a waiting agent visibly draws your attention.

## Scaling to many agents

Expect a handful of agents at once in practice. For v1, the only thing to
actually build is:

- **Procedural placement.** Agents get positioned on the island via a
  simple algorithm (ring/spiral/grid with jitter) rather than hardcoded
  desk spots. Handles up to ~20-30 agents per island fine.

The sidecar's data model and event schema should still avoid assuming a
fixed max agent count, so none of the below require a rework later. But
none of the below are committed work — they're just options to have on
hand if/when agent counts actually become a problem:

- **Island growth:** island mesh/footprint scales up (or subdivides into a
  mini-archipelago of its own) past some agent-count threshold, to keep
  density reasonable.
- **LOD/culling:** far-away or long-idle agents collapse into a simplified
  representation (stacked PCs, a counter badge) and expand when
  approached/clicked. This would be the mechanism for true "unlimited"
  agents, avoiding ever rendering hundreds of full models at once.
- **Overflow structure:** past some count, a "server rack" building
  appears representing "N more agents working," clickable to list them
  instead of spawning N more 3D models.

## Entertainment / downtime features

While an agent is working, you're often just waiting. Part of the point of
having a physical world is giving you something to do during that time:
parkour courses with fun movement mechanics, minigames scattered around the
world, etc. Specifics (which minigames, where they live, how they're
unlocked) are intentionally undecided for now — treat this as a planned
feature category, not something to design or build yet. Worth keeping in
mind when designing player movement (e.g. don't make movement so plain that
it can't support parkour later) but not worth scoping further at this
stage.

## Architecture

- **Godot 4 (GDScript):** the world, player movement, island/bridge
  generation, agent models and state visuals, and the in-world chat UI.
- **Sidecar process (Node or Python):** runs AI coding sessions and
  forwards their activity to Godot as events. For now this means Claude
  Code specifically, via the Claude Agent SDK (or by spawning `claude`
  directly), listening to Claude Code hook events (subagent spawn, tool
  use, finish, permission requests), and reading/resuming existing
  sessions from `~/.claude/projects/*.jsonl`.
- **Transport:** local WebSocket between sidecar and Godot.
  - Sidecar → Godot: session created/ended, subagent spawned/finished,
    state changes, permission requests.
  - Godot → sidecar: user chat messages, permission approve/deny,
    "create new session" / "resume session" commands.
- One session ID maps to one island; this should be the core unit in both
  the sidecar's data model and Godot's scene structure.

### Multi-provider design (Claude only for now, but don't hardcode it in)

This project is being built for Claude only, and all near-term effort
should go into making the Claude integration good. But it should be built
so that adding support for other AI coding tools later (Codex, Cursor,
etc.) is a matter of writing a new adapter, not a rewrite:

- The sidecar should define a provider-agnostic internal event
  vocabulary (session started/ended, subagent spawned/finished, state
  changed, permission requested, message sent/received) and have a
  "Claude provider" module that translates Claude Code's hooks/SDK
  events into that vocabulary. Godot only ever sees the generic events,
  never Claude-specific ones.
- Avoid naming generic systems after Claude (e.g. internal event types,
  the WebSocket protocol, Godot's scene/class names for "agent" or
  "session") — keep Claude-specific naming confined to the provider
  module. ("Claude Agent Island Visualizer" as a project name is fine to
  keep for now regardless.)
- Don't actually build a second provider now — just don't let the
  architecture assume there's only ever going to be one.

## Session integration notes

- Claude Code stores session transcripts as JSONL under
  `~/.claude/projects/<project-slug>/<session-id>.jsonl`, resumable via
  `claude --resume <id>`. Sessions created through the Agent SDK use the
  same store, so anything this app creates should be resumable from a
  terminal, and old CLI sessions should be listable/resumable from this
  app.
- As of research done in Sept 2026, the Claude **desktop app** does NOT
  read from `~/.claude/projects/` — it keeps a separate session store, and
  there's no supported way to register a session into it or launch it into
  a specific folder from outside. Don't rely on desktop-app integration;
  the terminal/JSONL store is the actual integration point.

## Chat panel

Since this is meant to be an actual working environment (not just a
visualizer), the in-world chat panel is a core feature, not an
afterthought:

- Needs streaming responses, readable code block rendering, and some form
  of tool-call log.
- Godot's `RichTextLabel` uses BBCode, not Markdown — rendering Claude's
  Markdown output well will take real translation/formatting work. This is
  probably the single biggest UX risk in the project; consider prototyping
  it early rather than last.

## Art direction

- Low-poly style.
- Assets either self-made or downloaded from existing free/CC0 packs
  (e.g. Kenney.nl-style asset packs) — **never AI-generated.**
- Kenney's asset packs (free, low-poly, CC0) are a plausible source for
  terrain/environment art, leaving custom modeling effort focused on the
  Claude-logo-on-PC agent models.

## Open questions / decisions still needed

1. Data model / event schema between sidecar and Godot (session → island,
   agent → model, state → visual) — needs to be nailed down concretely
   before building either side.
2. Archipelago clustering: strictly by repo path, or should there be a way
   to manually name/arrange projects?
3. Teleport menu UX: sorted/grouped how (by project? recency? custom
   pinning?), and whether a minimap is still wanted alongside it for the
   on-foot bridge-walking side of travel.
4. Whether/how to support chatting with subagents directly, or keep
   subagent interaction to read-only status display for now (chat is
   orchestrator-only in the current design).
5. Whether the app should run sessions itself, attach to sessions already
   running elsewhere, or both.

## Suggested first milestone (v1 slice)

- One archipelago, one island, one orchestrator.
- Sidecar starts a single Claude Code session via the Agent SDK and
  forwards hook events over WebSocket.
- Godot: static beach island, orchestrator model, walk-up-to-chat
  interaction, and a plain-text (not yet fully Markdown-rendered) chat
  panel wired to the sidecar.
- Subagents render as simple logo-on-PC models placed via basic
  ring/spiral placement, appearing/disappearing with spawn/finish events.

Not in this slice: bridges, the teleport menu, multiple islands/archipelagos,
minigames/parkour, chat markdown rendering polish, and any second AI
provider. Goal of this slice is to prove the Godot ↔ sidecar ↔ Claude Agent
SDK pipeline end-to-end, using the generic event vocabulary described above
even though only the Claude provider exists yet.
