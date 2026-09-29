# Agent Office (a similar project)

Features: docs (S02, A05, W07, security rules)

The user found [Agent Office](https://github.com/AgentSystemLabs/agent-office)
(MIT, TypeScript, three.js; about 365 stars, active on 2026-09-29) and asked
for a review. It's a cartoon 3D office where a team sits Claude Code, Codex
and OpenCode workers at desks, with live shared terminals, voice, a
whiteboard, GitHub issue and PR boards, git worktrees per worker and
minigames. It runs as a web server, locally or deployed to a cloud machine.

## How it differs from ours

- **Product.** A multiplayer team office on a server, used in a browser.
  Ours is a single-player desktop game (itch.io, likely Steam), running
  only on the user's machine. The user was discouraged at first, then
  decided (their words, roughly) to keep building to their own vision:
  theirs is a different product, and ours can offer different value.
- **The terminal.** They host each agent in their own terminal (a PTY,
  `node-pty`) mirrored into the browser, and people type into it. That
  avoids channels, and they catch Esc from a progress signal Claude Code
  prints. Permission prompts only change a worker's status; people answer
  them by typing in the shared terminal. We rejected typing keystrokes
  (dev log 2026-09-29-claude-cli-route) and answer permissions and
  questions from the world instead (C05, `questions`).
- **Hook token.** They pass it in the agent's environment, which every
  command Claude runs inherits. Ours stays in the per-session settings
  file.
- **Claude sign-in.** With accounts, their server runs `claude auth login`
  for each person and accepts pasted `claude setup-token` tokens. Our
  principles and Anthropic's terms rule that out for us (Watch items →
  Anthropic's terms).

## Borrowed (ideas only, no code)

1. **A session stuck at startup** → planned in S02: a session notice when
   the bridge hasn't connected in time (they use a missing `SessionStart`
   hook).
2. **Token usage from the transcript**, with Claude Code's own cost total
   at session end → Deferred ideas (a `usage` capability).
3. **"Go to whoever has waited longest"** → recorded under W07 as a
   possible feature, not planned (user's decision).
4. **Environment cleaning by narrow families** → done in S02 (user's
   decision): named markers plus `CLAUDE_CODE_SESSION_`,
   `CLAUDE_CODE_CHILD_`, `CLAUDE_CODE_MESSAGING_` and `CLAUDE_CODE_BRIDGE_`,
   each checked against the env-vars docs (every documented member is set
   by Claude Code itself). Security rules updated.
5. **`CLAUDE_EFFORT`**, which their list removes and ours missed, is now
   removed; the user's own setting, `CLAUDE_CODE_EFFORT_LEVEL`, passes
   through.

Not borrowed: hosting the terminal, handling Claude sign-ins, the hook
token in the environment, and the team features (accounts, voice,
deployment, GitHub boards). If we ever copy their code rather than ideas,
their MIT notice must be kept and recorded.
