# The Beach

*(working title)*

A 3D world where your AI coding sessions are islands. Each Claude Code
session rises out of the ocean as an island. Its orchestrator sits at a beach
desk in the middle, and the subagents it spawns show up as little figures at
their PCs on the sand. Walk up to the orchestrator to chat with it, answer
permission prompts and questions, and start or resume sessions, all without
leaving the world. Every session is also a normal Claude Code terminal, so
you can switch between the world and the terminal whenever you like.

> **Status:** early development. Nothing is playable yet; see
> [NOTES.md](NOTES.md) for the plan.

## What you'll be able to do

- Start new sessions and resume old ones; each one is an island.
- Walk between islands of the same project over bridges, or teleport straight
  to the one you need.
- Chat with a session's orchestrator from an in-world panel.
- See at a glance which agents are working, finished, or waiting on you.
- Switch to the session's terminal at any point and back again.

## Requirements

- **Windows, macOS or Linux.** All three are supported by design; so far
  it has only been tested on Windows. On Windows, Claude Code must be the
  native Windows install (not inside WSL).
- [Claude Code](https://code.claude.com/docs) installed and signed in with
  your own account. The app uses Claude Code's channels (a research
  preview): available on Pro and Max plans, while Team and Enterprise
  organisations need an admin to enable them.

To build from source you also need:

- [Godot](https://godotengine.org/download) **4.7.2** (standard build; .NET is
  not needed)
- [Node.js](https://nodejs.org) **22.21.0** to build the sidecar. Released
  builds include the sidecar, so players don't need Node.

## Setup

```bash
git clone https://github.com/PaoloPortugal/The-Beach.git
```

1. In `sidecar/`, run `npm ci` (and `npm test` to check it works).
2. Open Godot, choose **Import**, and select `project.godot` at the repo root.
3. Press **F5** to run. Godot starts the sidecar itself (from source, so
   `node` must be on your PATH). There's no world to see yet.

More commands (packaging, the fake provider, tests) are in
[NOTES.md → Running it](NOTES.md#running-it).

## Docs

- [docs/GUIDE.md](docs/GUIDE.md): how to use it.
- [NOTES.md](NOTES.md): design and developer reference.
- [docs/flows.md](docs/flows.md): diagrams of how the pieces talk.
- [docs/devlog/](docs/devlog/README.md): why things are the way they are.

## License

[MIT](LICENSE). Third-party parts keep their own licenses: the
`addons/godot_ai` editor plugin (MIT, see its `LICENSE`) and the assets
listed in [assets/CREDITS.md](assets/CREDITS.md).

Not affiliated with or endorsed by Anthropic. Claude and Claude Code are
Anthropic's; this app runs your own installed copy of Claude Code.
