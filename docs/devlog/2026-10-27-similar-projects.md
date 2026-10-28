# Similar projects (third look)

Features: docs

The user asked for the usual look at projects like ours, four days after
the second (2026-10-23-similar-projects). Read from READMEs, GitHub
metadata and recent commit titles only; no code was read. Star counts
are from 2026-10-27.

## The ones we knew

Little moved since 2026-10-23. Pixel Agents is at ★9,934, Agent Office
★823 (from 797), Agent Quest ★164; none of them has a new commit on its
default branch. code-town, AgentVille, Tide Commander, agent-flow,
Agentis and codemoo's Agent World are unchanged.

**Antics** (antics.gg, which agent-flow's README points to) now loads:
it hosts multiplayer browser games built with AI coding agents, through
an MCP server. Not a project like ours; off the list.

## New ones

| Project | What it is | How it reaches Claude Code |
|---|---|---|
| [Agents World](https://github.com/ysfxjo55/agents-world) (★6, new 2026-10-26, AGPL-3.0) | A local web app with a 3D world: **every project an island**, every session a building, a robot that works, waits or sleeps. A "Cozy Night Village" theme, desktop alerts when a task finishes (and to a phone through ntfy), a chat page, manager agents, an overnight research lab. Terminal sessions show up too | Reads the session files; chatting runs **`claude -p --output-format stream-json`**, with access modes up to `--dangerously-skip-permissions`. Codex, OpenCode and Antigravity too |
| [Agent World](https://github.com/kalarav-tops/agent-world) (kalarav-tops, ★0, new 2026-10-06, MIT) | 3D, **every session an island** ("continent"); subagents are scientists who walk to the station for their current tool (a workbench to edit, a microscope to read, a terminal to run commands, a help desk to ask). A launch tower starts sessions | Transcripts, read-only by default; replies run `claude -p --resume --fork-session`; answering permission prompts needs its **hooks merged into `~/.claude/settings.json`** |
| [Agent4D](https://github.com/burn001/agent4d) (★1, new 2026-10-25, Apache-2.0) | A read-only 3D viewer and **replayer** (0.5×–32×, a scrubbable timeline): Flow, Planet (projects as round orbital islands) and Voxel Office views | Transcripts only |
| [Claude Dungeon](https://github.com/thousandsky2024/claude-pixel-agent-web) (★17, quiet since March, MIT) | Each session a pixel-art knight in a dungeon | Transcripts only |
| agent-world-viewer (wojacklabs) | A "cozy vibe visualizer" in three.js, [shown in April](https://discourse.threejs.org/t/claude-code-visualizer/91054) | Unknown; the repository is now gone (404) |

Smaller ones seen: claude-watch and claude-code-visualizer (dashboards),
tracetree, agent-watch. No Steam or itch.io game turned up.

### What moved

- **Islands are common now.** Agents World, kalarav-tops' Agent World
  and Agent4D's Planet view all draw sessions or projects as islands,
  as code-town did: four in the last month. The island picture alone no
  longer sets us apart.
- **Agents World is the closest yet**: 3D, cozy, an island per project,
  terminal sessions brought in, chat, several providers. A day old, but
  moving fast.

### How we still differ

- **Anthropic's terms.** Every interactive one does something we ruled
  out: driving `claude -p` itself (Agents World, Agent World), offering
  skip-permissions (Agents World), editing the user's settings (Agent
  World's hook). Agent4D and Claude Dungeon only watch.
- **A desktop game.** All the new ones are browser apps; none has walking,
  downtime, biomes or weather, and none is on Steam or itch.io.

## Ideas worth a look (not decided)

Recorded for the user to weigh; none adopted. Ideas only, no code; if
code is ever copied, its licence notice must be kept and recorded
(Agents World is AGPL-3.0, which would bind the whole game).

1. **Replaying a session** (Agent4D): watch an old island's work play
   back, near S08's read-only islands.
2. **Stations by tool** (kalarav-tops' Agent World): an agent walks to
   the place for what it's doing, a cheap way to read activity at a
   glance.
3. **Alerts on the phone** (Agents World, through ntfy).
