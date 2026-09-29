# The Beach

*(working title)*

A 3D world where your AI coding sessions are islands. Each Claude Code
session rises out of the ocean as an island. Its orchestrator sits at a beach
desk in the middle, and the subagents it spawns show up as little
logo-on-PC models on the sand. Walk up to the orchestrator to chat with it,
approve permission prompts and start or resume sessions, all without
leaving the world.

> **Status:** early development. Nothing is playable yet; see
> [NOTES.md](NOTES.md) for the plan.

## What you'll be able to do

- Start new sessions and resume old ones; each one is an island.
- Walk between islands of the same project over bridges, or teleport straight
  to the one you need.
- Chat with a session's orchestrator from an in-world panel.
- See at a glance which agents are working, finished, or waiting on you.

## Requirements

- [Godot](https://godotengine.org/download) **4.7.2** (standard build; .NET is
  not needed)
- Sidecar runtime: *to be decided*
- [Claude Code](https://docs.claude.com/en/docs/claude-code) installed and
  signed in

## Setup

```bash
git clone https://github.com/PaoloPortugal/The-Beach.git
```

1. Start the sidecar in `sidecar/` *(not implemented yet)*.
2. Open Godot, choose **Import**, and select `project.godot` at the repo root.
3. Press **F5** to run.

## Docs

- [docs/GUIDE.md](docs/GUIDE.md): how to use it.
- [NOTES.md](NOTES.md): design and developer reference.
- [docs/devlog/](docs/devlog/README.md): why things are the way they are.
