# S08: read-only islands for sessions started outside the game (research)

Features: S08, S07, S04, W05, W12

## Why

The user's order (2026-10-13): after W12, islands for every session on
the machine, not only the ones the game launched (Deferred ideas →
Read-only islands for sessions started outside the game). Read-only,
because only launch flags give a session our hooks and channel, and we
never edit the user's settings. This is the research before the design
decisions; nothing is built yet. Working ID S08 (the next free S).

## What `claude agents --json` gives (2026-10-22, `claude` 2.1.308)

From the agent-view docs (raw `agent-view.md`, read in the browser; the
sandbox's `curl` can't reach it) and probes on this machine:
- **It lists every live session**, interactive ones included, and
  background sessions still working or blocked even when their process
  has exited. `--all` adds finished background sessions; `--cwd <path>`
  limits it to one folder. The docs call it the supported way to read
  session state from outside; the files under `~/.claude/jobs/` aren't.
- **Fields** (documented): always `cwd`, `kind` (`interactive` or
  `background`), `startedAt` (Unix ms); for background sessions `id`
  (short) and `state` (`working`, `blocked`, `done`, `failed`,
  `stopped`); while the process lives, `pid` and `status` (`busy`,
  `waiting`, `idle`); while waiting, `waitingFor` (`permission prompt`,
  `input needed`, `sandbox request`, `worker request`, `dialog open`);
  when set, `sessionId` and `name` (an interactive session's default
  display name until it's named). Probed: the same keys, no others.
  Since 2.1.296 nothing about the JSON changed (the docs' change table).
- **It lists more than terminals.** Here it listed the Claude desktop
  app's Code sessions (this one included). Transcripts carry an
  `entrypoint`: `cli` (a terminal, and the game's own sessions),
  `claude-desktop`, `claude-vscode`, `sdk-cli` (`claude -p` and Agent
  SDK programs). `kind` doesn't tell these apart; the transcript does.
- **The game's own sessions are listed too** (their `--settings` turns
  agent view off only for themselves): S07 already knows them by the
  `pid` our launcher spawned, so they'd be filtered out by that.
- **Cost:** about 0.67 s wall and 0.7 s CPU per call (5 runs, Windows,
  three sessions listed). Every 5 s that's about 14 % of one core;
  every 10 s, 7 %. Agent view itself refreshes its waiting count about
  every 10 s while focused. It doesn't start the supervisor (`claude
  daemon status`: not running, after many calls).
- **Agent view off** (`disableAgentView` or
  `CLAUDE_CODE_DISABLE_AGENT_VIEW`): it exits 1 with "'claude agents
  --json' is disabled by CLAUDE_CODE_DISABLE_AGENT_VIEW." (or the
  setting). Nothing to list then; `running.ts` already fails soft on it.
- **No way to send from outside.** `claude attach`, `logs`, `stop`,
  `respawn` and `rm` exist for background sessions only; replying is
  the agent-view peek panel, not a command. So read-only stays the
  ceiling (Watch items → Attaching to sessions started outside the
  game), except that `claude stop <id>` could stop a *background* one.

## The transcript

Each listed session's transcript is where S07's read-only mode already
looks: `~/.claude/projects/<project>/<sessionId>.jsonl` (found here
for desktop sessions too). S07's reader (`transcript-hooks.ts`, the
`findOwn` wait for a transcript not written yet, `/clear` and `/resume`
followed by `sessionId` per `pid`) covers chat, tool calls, usage and
titles. Not a documented interface (Watch items → The transcript in
S07's read-only mode).

## What's left to decide (for the user)

1. Which sessions get islands: terminals only (`cli`), or also the
   desktop app and IDEs, and whether `sdk-cli` (short `-p` runs and SDK
   programs) and finished background sessions show.
2. How they look and where: mixed into their repository's cluster, or
   set apart (a mark, a cluster of their own).
3. How often to poll, and whether only while the game has focus.
4. Agent view off: no outside islands, silently or with a notice.
5. The chat window: read-only like S07's, and whether to offer anything
   (stop for background sessions, "continue in the game" by resuming
   once it ends).
6. Scope: a capability (`outside_sessions`) a provider declares, with
   Claude names only inside the Claude provider.

## Decided (user's, 2026-10-22; my recommendations)

1. **Which:** every live session except `sdk-cli` (short `-p` runs and
   SDK programs would flash islands): terminals, the desktop app, IDEs,
   and background sessions still working or blocked. Not finished
   background sessions (no `--all`).
2. **Where and how:** in its repository's cluster like any session
   (W05, kept across restarts by W12), with a visible mark and a
   read-only line in the chat (rejected: a cluster of their own;
   unmarked).
3. **Polling:** every 5 s while the game has focus, every 10 s in the
   background (rejected: 10 s always; 5 s always).
4. **Agent view off:** a notice once per launch saying why outside
   sessions can't be shown (rejected: silent, log only).
5. **The mark covers S07's read-only sessions too** (user's addition):
   a session of ours that came back read-only because its hook port was
   taken (S07 → If the old port is taken; snapshot `read_only: true`)
   gets the same mark, so every island you can't control from the
   world looks the same. The mark follows `read_only`, not where the
   session was started.

Still open: the chat window's offer and the provider scope (points 5 and 6 above).
