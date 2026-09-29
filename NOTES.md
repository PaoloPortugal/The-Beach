# The Beach: developer notes

Read this first every session. It is the single source of truth for the
design; keep it current and short.

- `NOTES.md` (this file): what the project is, where it's going, how it works.
- `docs/GUIDE.md`: user's guide for built features. Must always match this file.
- `docs/devlog/`: long history, decisions, rejected alternatives, bugs. Look up by feature ID.
- `CLAUDE.md`: working rules. `README.md`: pitch and setup.
- `assets/CREDITS.md`: source and license of every asset.

## Concept

A 3D working environment in Godot 4 that shows AI coding sessions as a
world you walk around in. It is a place to **work**, not a passive monitor:
you create sessions, resume old ones and chat with the orchestrator, all
from inside the world.

**World.** A beach and ocean world. Each session is an **island**: a new
session rises out of the ocean and an ended one sinks. Islands from the same
project cluster into an **archipelago** joined by walkable bridges, and
unrelated projects get their own stretch of ocean. Bridges are for
exploration and feel; a **teleport menu** is for getting work done quickly.
Other biomes (hills, mountains) come later, so region connection is a
general system, not a beach-specific one.

**Agents.** The **orchestrator** sits at the centre of its island (a bigger
logo model at a beach desk or under an umbrella). Walking up to it opens the
chat panel. **Subagents** are small logo-on-a-little-PC models on the sand.
They spawn when the orchestrator spawns them and power down when they
finish, showing working, waiting-on-you or done. An agent that waits on a
permission prompt should visibly draw your attention.

**Downtime.** You spend a lot of time waiting on agents, so the world should
eventually give you something to do: parkour and minigames. These aren't
designed yet (see Known issues and next steps → Deferred ideas).

**Art direction.** Low-poly. Assets are made by the user or come from CC0 packs
such as Kenney, **never AI-generated**. Kenney packs are the likely source
for terrain and environment, which leaves custom modelling effort for the
logo-on-PC agent models.

## Feature index

Prefixes: **W** world (islands, ocean, bridges, travel, player movement),
**A** agents (orchestrator, subagents, states, placement), **C** chat panel
and in-world UI, **S** sidecar and session management. v1 = part of the
v1 slice.

| ID  | Feature                                   | Status  | Guide section | Main code |
|-----|-------------------------------------------|---------|---------------|-----------|
| W01 | Beach island (v1)                         | planned | n/a           | n/a       |
| W02 | Ocean (v1)                                | planned | n/a           | n/a       |
| W03 | Player movement (v1)                      | planned | n/a           | n/a       |
| W04 | Island rise / sink                        | planned | n/a           | n/a       |
| W05 | Archipelagos (project clustering)         | planned | n/a           | n/a       |
| W06 | Bridges (region connection)               | planned | n/a           | n/a       |
| W07 | Teleport menu                             | planned | n/a           | n/a       |
| A01 | Orchestrator (v1)                         | planned | n/a           | n/a       |
| A02 | Subagents spawn / despawn (v1)            | planned | n/a           | n/a       |
| A03 | Agent state indicators                    | planned | n/a           | n/a       |
| A04 | Procedural agent placement (v1)           | planned | n/a           | n/a       |
| A05 | Permission attention cue                  | planned | n/a           | n/a       |
| C01 | Walk up to chat (v1)                      | planned | n/a           | n/a       |
| C02 | Chat panel, plain text and streaming (v1) | planned | n/a           | n/a       |
| C03 | Markdown rendering                        | planned | n/a           | n/a       |
| C04 | Tool-call log                             | planned | n/a           | n/a       |
| C05 | Permission approve / deny                 | planned | n/a           | n/a       |
| S01 | Sidecar and WebSocket server (v1)         | planned | n/a           | n/a       |
| S02 | Claude provider (v1)                      | planned | n/a           | n/a       |
| S03 | Create session from the world             | planned | n/a           | n/a       |
| S04 | List and resume stored sessions           | planned | n/a           | n/a       |
| S05 | End session                               | planned | n/a           | n/a       |

## When a feature lands

- [ ] Update its `### <ID>` section in Systems (planned intent → how it works),
      including its provider scope.
- [ ] Update its index row: status, guide section, main code.
- [ ] Add or update its `<ID>` section in `docs/GUIDE.md` in plain language,
      and add it to the guide's table of contents.
- [ ] Reread the guide section against this file.
- [ ] Update Architecture / Protocol / Conventions if it touched them.
- [ ] Record any new assets in `assets/CREDITS.md`.
- [ ] Write a dev-log entry and add it to `docs/devlog/README.md`.
- [ ] Update "Current focus".

## Architecture

```
Godot 4 (GDScript)  <--local WebSocket-->  sidecar       -->  provider(s)
world, player, agents,     generic core +    session registry,   Claude provider:
chat UI, provider UI       capabilities +    WebSocket server    Agent SDK, hooks, JSONL store
                           extensions
```

- **Godot** (GDScript): the world, player movement, island and bridge
  generation, agent models and state visuals, in-world chat UI.
- **Sidecar** (language TBD, open question 6): runs sessions and forwards their activity to Godot
  as generic events. It owns the session registry.
- **Provider**: translates one AI tool's native events into the generic
  vocabulary. Only the **Claude provider** exists; it uses the Claude Agent
  SDK (or spawns `claude`), listens to Claude Code hook events (subagent
  spawn, tool use, finish, permission requests) and reads and resumes sessions
  from `~/.claude/projects/*.jsonl`.
- **One session ID = one island.** It is the core unit in both the sidecar's
  data model and Godot's scene tree.

**Multi-provider rules.** Only Claude is built, and near-term effort goes into
making it good, including Claude-only features (e.g. model choice, usage,
context window). Adding another tool (Codex, Cursor, ...) must still only need a
new adapter plus, optionally, its own extension UI. Every feature has one of
three **provider scopes**:
- **Core:** every provider must support it (sessions, agents, messages,
  permissions). Generic events; each provider translates into them.
- **Capability:** a generic concept that not every provider has (e.g. model
  choice, token usage, context-window fill). Generic events, gated by a
  capability the provider declares for the session; Godot shows the UI only
  when it's declared. Prefer this over an extension whenever the concept
  plausibly exists elsewhere.
- **Extension:** truly unique to one provider. Namespaced by provider in the
  protocol, and handled in Godot by that provider's own UI module, so that
  removing a provider means deleting its folders and nothing else.

Naming: Claude-specific names appear only in the sidecar's Claude provider
module, the Claude extension namespace of the protocol, and Godot's Claude UI
module. Everything else is named generically. Don't build a second provider;
just don't assume there will only be one. The exact capability and extension
format is part of the event schema (open question 1).

**Layout.** The Godot project is the repo root (`project.godot`). Other
top-level folders sit beside it:

| Path | Role |
|------|------|
| `project.godot`, `icon.svg` | Godot project (4.7, GDScript, no .NET). Version pinned in `.godotrc`. |
| `assets/` | Art and audio, plus `CREDITS.md`. |
| `sidecar/` | Sidecar (empty until its language is chosen). Has a `.gdignore` so Godot doesn't scan it. |
| `protocol/` | Shared event schema *(pending, see open question 1)*. |
| `docs/` | User's guide and dev log. |
| `addons/godot_ai/` | Dev tool, not a feature: third-party editor plugin (godot-ai, MIT) that lets Claude Code drive the Godot editor over MCP. See Running it. Don't edit it by hand; it self-updates and checks its files against a signed manifest. It adds the `_mcp_game_helper` autoload to `project.godot` (game-side screenshots and logs over Godot's debugger channel only; inert in the editor, stripped from exports). |

The Godot folder layout (scenes, scripts) and the sidecar file table get
filled in as the v1 features land.

## Protocol

The contract between Godot and the sidecar, over a local WebSocket. It has
a generic core, capability-gated optional features and provider-namespaced
extensions (see Multi-provider rules), and must not assume a maximum number of agents
per session. The concrete schema is **not settled yet** (open question 1);
once it is, it will be written here and in `protocol/events.schema.json`.

Vocabulary from the design:
- **Sidecar → Godot:** session created / ended, subagent spawned / finished,
  agent state changed, permission requested, messages (streamed).
- **Godot → sidecar:** user chat message, permission approve / deny,
  create session, resume session.

## Systems

### W01 Beach island
*Planned (v1).* A static beach island, one per session. In v1 there is
exactly one. Later islands are created and removed dynamically (W04).

### W02 Ocean
*Planned (v1).* The ocean surrounding the islands. Unrelated projects get
their own area of it (W05).

### W03 Player movement
*Planned (v1).* On-foot movement for walking up to agents. Keep it capable
enough to support parkour later; don't make it so plain that it rules parkour out.

### W04 Island rise / sink
*Planned.* A new session makes an island rise out of the ocean; this doubles
as the "new session" feedback. An ended session makes its island sink, and
the island is then removed.

### W05 Archipelagos
*Planned.* Islands of the same project/repo cluster into an archipelago.
Whether that goes strictly by repo path or allows manual naming and arranging is
open question 2.

### W06 Bridges
*Planned.* Walkable bridges connect islands within an archipelago, for
physical movement and the feel of the world. Build it as a general
"connect regions" system, not beach-specific, so that future biomes (hills,
mountains) plug into it.

### W07 Teleport menu
*Planned.* Instantly jumps to a session's island, so you never have to walk
across the world to reach an orchestrator. Sorting, grouping and whether to
add a minimap are open question 3.

### A01 Orchestrator
*Planned (v1).* A bigger logo model at the centre of its island, at a beach
desk or under an umbrella. It's the main way you interact with a session
(see C01).

### A02 Subagents
*Planned (v1).* Small logo-on-a-little-PC models on the island's sand. They
appear when the orchestrator spawns them and power down or disappear when
they finish. Chat is orchestrator-only for now; whether to talk to
subagents directly is open question 4.

### A03 Agent state indicators
*Planned.* A visible state on each agent: working, waiting on user input
(e.g. a permission prompt) or done.

### A04 Procedural agent placement
*Planned (v1).* Agents are positioned by a simple algorithm (ring, spiral
or grid with jitter) rather than hardcoded spots, and it handles about 20–30 per
island. Nothing may assume a fixed maximum agent count. Options for larger
counts are in Deferred ideas.

### A05 Permission attention cue
*Planned.* A pending permission prompt is shown on the relevant island
and agent, so a waiting agent visibly draws your attention.

### C01 Walk up to chat
*Planned (v1).* Walking up to an orchestrator opens the chat panel for its
session.

### C02 Chat panel
*Planned (v1: plain text).* A core feature, not an afterthought, because this
is a working environment. It needs streaming responses. v1 renders plain text
wired to the sidecar.

### C03 Markdown rendering
*Planned.* Godot's `RichTextLabel` uses BBCode, not Markdown, so rendering
the model's Markdown well (especially readable code blocks) takes real
translation work. It is **probably the biggest UX risk in the project**, so it
gets prototyped early as a throwaway spike, before its full build.

### C04 Tool-call log
*Planned.* Some form of log of the tool calls the session made, visible from
the chat panel.

### C05 Permission approve / deny
*Planned.* Answer permission requests from inside the world. They are
sent to the sidecar as approve/deny.

### S01 Sidecar and WebSocket server
*Planned (v1).* The sidecar process that hosts the session registry and the
local WebSocket server Godot connects to. It speaks only the generic
protocol.

### S02 Claude provider
*Planned (v1).* Starts a Claude Code session via the Claude Agent SDK and
translates its hook/SDK events into generic events. It is the only place
Claude-specific names may appear.

### S03 Create session
*Planned.* A "create new session" command from Godot. Whether the app only
runs sessions itself, attaches to sessions already running elsewhere, or both
is open question 5.

### S04 List and resume sessions
*Planned.* Claude Code stores transcripts as JSONL under
`~/.claude/projects/<project-slug>/<session-id>.jsonl`, resumable with
`claude --resume <id>`. Sessions created through the Agent SDK use the same
store, so sessions made in this app are resumable from a terminal, and old
CLI sessions can be listed and resumed here. The Claude **desktop app** does
not use this store (see Deliberate limitations).

### S05 End session
*Planned.* Ending a session removes it from the registry and sinks its
island (W04).

## Conventions

- **A new feature** first gets its provider scope decided (core, capability
  or extension; see Multi-provider rules), stated in its Systems section. If
  it's unclear, ask the user.
- **A new event type** needs: its scope (core, capability name, or
  extension namespace), a schema entry in `protocol/`, a line in the Protocol
  section, the provider translation in the sidecar, and a Godot handler (in
  the provider's UI module if it's an extension).
- **A new asset** needs a row in `assets/CREDITS.md` (source, author,
  license). CC0 or made by the user only; never AI-generated.
- **Provider-specific code** stays in its provider module (sidecar) or UI
  module (Godot); anything shared is named generically.

### Renaming the project

"The Beach" is a codename. It appears in:
- `project.godot`: `config/name` (also the window title)
- `README.md`: title
- `NOTES.md`: title
- `CLAUDE.md`: codename rule
- `docs/GUIDE.md`: title
- `docs/devlog/`: past entries (historical; leave them)

It must not appear in code identifiers, class names, the protocol or package
names. Add to this list if it ever has to appear anywhere new.

## Running it

Nothing runs yet. Once it does: start the sidecar (commands depend on
open question 6), then open `project.godot` in Godot 4.7.2 and press F5.

**Godot AI (dev tool).** The `addons/godot_ai` editor plugin
([hi-godot/godot-ai](https://github.com/hi-godot/godot-ai), MIT) lets Claude
Code drive the open editor. It needs [uv](https://docs.astral.sh/uv/) (the
client runs a Python bridge through `uvx`). Chain: Claude Code → `godot-ai
attach` (stdio) → local Python server (authenticated HTTP, port 8000) → editor
plugin (authenticated WebSocket, port 9500, loopback only). Per machine:
- Set Editor Settings → Plugins → `godot_ai/mcp_client_scope` to `local`,
  then press **Configure** next to Claude Code in the Godot AI dock. The
  client entry pins versions and machine paths, so it isn't tracked in the repo.
- Telemetry off: set the user environment variable
  `GODOT_AI_DISABLE_TELEMETRY=true`.
- Update with the dock's **Update** button, never by copying files over it.

## Open questions

1. **Event schema.** The data model between sidecar and Godot (session →
   island, agent → model, state → visual). It must be nailed down before
   building either side. *Next up.*
2. **Archipelago clustering.** Strictly by repo path, or can projects be
   manually named or arranged?
3. **Teleport menu UX.** Sorted or grouped how (project, recency, custom
   pinning)? Is a minimap still wanted for on-foot travel alongside it?
4. **Subagent chat.** Chat with subagents directly, or keep them read-only
   status for now (orchestrator-only chat, as currently designed)?
5. **Session ownership.** Does the app run sessions itself, attach to
   sessions already running elsewhere, or both?
6. **Sidecar language.** Node, Python or something else? The design left
   Node or Python open; the user is investigating. Only the Claude provider
   depends heavily on this (it needs a Claude Agent SDK or the `claude` CLI).

## Known issues and next steps

**Current focus:** settle the event schema (open question 1), including the
capability and extension format. The sidecar language (open question 6) is
under investigation. Then: the Markdown → BBCode spike (C03).

### Milestones

**M0 Setup.** Docs and scaffold, event schema, Markdown → BBCode spike.

**M1 v1 slice.** The goal is to prove the Godot ↔ sidecar ↔ Agent SDK pipeline
end-to-end with the generic vocabulary, even though only the Claude provider
exists.
- One archipelago, one island, one orchestrator (W01, W02, A01).
- Sidecar starts one Claude Code session via the Agent SDK and forwards hook
  events over WebSocket (S01, S02).
- Walk up to chat with a plain-text chat panel wired to the sidecar (W03, C01,
  C02).
- Subagents as simple logo-on-PC models with ring or spiral placement,
  appearing and disappearing on spawn and finish events (A02, A04).
- Not in v1: bridges, teleport menu, multiple islands or archipelagos,
  minigames and parkour, Markdown polish, any second provider.

**After v1.** The remaining features in the index. They are not ordered yet.

### Deferred ideas (not features yet)

- **Agent scaling**, only if agent counts become a problem:
  - *Island growth:* the island footprint grows, or subdivides into a
    mini-archipelago, past some agent count.
  - *LOD / culling:* far or long-idle agents collapse into a simple
    stand-in (stacked PCs, a counter badge) and expand when approached or
    clicked. This is the route to "unlimited" agents.
  - *Overflow structure:* a "server rack" building stands for "N more agents
    working" and can be clicked to list them.
- **Other biomes:** hills, mountains, joined by the same bridge system (W06).
- **Minigames and parkour** for downtime. Which ones, where they are and how
  they unlock are all undecided on purpose.

### Watch items

- Markdown → BBCode rendering (C03) is the biggest UX risk.
- `icon.svg` is Godot's default icon (CC BY 4.0, not CC0). It is a
  placeholder to replace.
- **Godot AI plugin:** its auth doesn't protect against a compromised process
  running as the same user, and on Windows it claims no isolation from other
  local accounts (per its security model). Telemetry is on by default
  upstream; we opt out per machine.

### Deliberate limitations

- **No Claude desktop app integration.** As of research in Sept 2026, the
  desktop app keeps its own session store, doesn't read
  `~/.claude/projects/`, and offers no supported way to register a session or
  launch into a folder from outside. The terminal/JSONL store is the
  integration point.
- **Claude is the only provider.** Near-term effort goes into making Claude
  good; the architecture stays open for more providers.
