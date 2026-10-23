# Similar projects (second look)

Features: docs (S08, Deferred ideas, Watch items → Anthropic's terms)

The user asked for a new search for projects like ours, and whether
past research was recorded. It mostly wasn't: only Agent Office has its
own entry (2026-09-29-agent-office). The 2026-10-12 round, Agent World
and Pixel Agents, left only its decisions in NOTES.md (below). This entry
records both rounds. Read from READMEs, GitHub metadata and recent
commit titles only; no code was read. Star counts are from 2026-10-23.

## The earlier round (2026-10-12)

Reconstructed from NOTES.md and the commit that recorded it (7a989c4);
the research itself wasn't written down at the time.

- **[Agent World](https://github.com/codemoo/agent-world)** (★17, alpha,
  quiet since April). A 2D RPG village for live `claude` processes on a
  Mac: repos are buildings, permission prompts queue at an info desk,
  tool use shows as icons overhead. Finds sessions with `ps` and `lsof`
  (from claude-control) and an opt-in PreToolUse hook it installs under
  `~/.claude/plugins/` for Allow / Deny. Its changed-files view gave the
  **changed-files board** idea (Deferred ideas; user's).
- **[Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents)**
  (then pablodelucca/pixel-agents). A 2D pixel office as a VS Code
  extension. Copilot CLI being the most-requested provider in its issues
  put **GitHub Copilot CLI** on our provider roadmap (user's).
- **What it changed:** both already show every session on the machine,
  so the user brought read-only islands for sessions started outside the
  game forward into the public release ("we shouldn't offer less"; built
  as S08, 2026-10-22). The downtime direction (fishing, bug catching,
  parkour) was also set "after looking at similar projects".

## This round (2026-10-23)

| Project | What it is | How it reaches Claude Code |
|---|---|---|
| [code-town](https://github.com/JuanLouTech/code-town) (★0, new 2026-10-03, MIT) | A cozy three.js island in the browser: folders are farms, sessions villagers, subagents gnomes | Drives sessions through the **Agent SDK** with the installed `claude`; terminal sessions show up as visitors |
| [Pixel Agents](https://github.com/pixel-agents-hq/pixel-agents) (★9.9k, moved to pixel-agents-hq, v1.5.0) | 2D pixel office: VS Code extension, or a browser app via `npx` | Installs its hooks **into `~/.claude/settings.json`**; transcripts as a fallback; a browser terminal to launch and drive agents |
| [Agent Office](https://github.com/AgentSystemLabs/agent-office) (★797) | 3D team office in the browser | A terminal (PTY) per agent, mirrored to the browser |
| [AgentVille](https://github.com/StrSimon/AgentVille) (★1) | 2D isometric dwarf village; desktop app or `npx` | One hook for Claude Code and Codex; allow / deny from an inbox |
| [Agent Quest](https://github.com/FulAppiOS/Agent-Quest) (★163, MIT) | 2D fantasy village dashboard | Transcripts, optional hooks; Claude Code and Codex |
| [Tide Commander](https://github.com/deivid11/tide-commander) (★74) | Orchestration suite with a 3D battlefield view | Headless `claude` (`stream-json`), or tmux |
| [Agentis](https://github.com/gpu-cli/agentis) (★2, quiet since March, MIT) | Replays transcripts as a 2D world: repos are islands | Transcripts only; Kenney art |
| [agent-flow](https://github.com/patoles/agent-flow) (★1.7k) | Live node graph of agent activity; not a game | Hooks |

Smaller ones seen: codemap, agent-village, claude-code-agent-visualizer,
the JetBrains Pixel Office port. agent-flow's README now points to
"Antics" (antics.gg), which didn't load. No Steam or itch.io game turned
up; itch.io's claude-code tag holds only tools.

### What moved since the first look

- **code-town is nearly our concept**, on the web: an island, fishing
  (rarer fish off the pier), bug catching, a field guide of finds,
  digging, beachcombing, coins for hats and a go-kart, a kart time trial,
  picross. A session is talked to through a bubble over the villager
  (chat, `/btw`, stop), where permissions, questions and plans also
  appear; the full transcript opens as a notebook. A terminal session
  can be brought onto the island once closed in the terminal. It shares
  our downtime plan almost item for item.
- **Agent Office went game-like:** first person, maps (a space station,
  a castle), a drive out of town, a sky on the real clock, footsteps by
  surface, and a beacon, banner and alarm over a worker that needs you.
  It added Cursor and Pi workers.
- **Pixel Agents is heading the same way.** Its roadmap's second stage is
  "actually a game": health bars for rate limits and token budgets,
  furniture that does things, an office per project. It now drives
  agents from a browser terminal too.
- **Codex is common:** AgentVille, Agent Quest, Tide Commander and Agent
  Office all support it; we put it after the commercial release.

### How we still differ

- **The only one inside Anthropic's terms by design.** Each of the others
  does at least one thing we ruled out: editing the user's Claude Code
  settings (Pixel Agents, Agent World, AgentVille), driving Claude
  through the Agent SDK on a subscription (code-town; Deliberate
  limitations → No Agent SDK), or hosting or typing into the terminal
  (Agent Office, Pixel Agents, Tide Commander; dev log
  2026-09-29-claude-cli-route). We launch the unmodified CLI with
  per-session flags only.
- **A desktop game**, not a browser app or IDE panel: Godot, low-poly 3D,
  many islands, biomes and weather, sold on Steam and offered on itch.io.
  Only AgentVille ships a desktop app, and it is a dashboard.

## Ideas worth a look (not decided)

Recorded for the user to weigh; none adopted. Ideas only, no code; if
code is ever copied, its licence notice must be kept and recorded.

1. **Context and plan limits at a glance**: AgentVille's 5-hour and weekly
   limits, Agent Quest's context gauge over each hero. Near C08's usage.
2. **Bringing a terminal session over** once the player closes it there
   (code-town): close to S07 and S08's territory.
3. **The downtime plan's edge**: with code-town already doing fishing and
   bug catching, what makes ours ours (biomes, weather, the sea floor,
   other islands) matters more.
