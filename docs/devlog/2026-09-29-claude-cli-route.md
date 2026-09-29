# Claude CLI route instead of the Agent SDK

Features: docs (S02, S03, S04; protocol unchanged)

## Problem

The plan was for the sidecar to run sessions through the Claude Agent SDK.
Claude Code's legal and compliance docs (checked 2026-09-29) say apps
built on the Agent SDK should use an API key, billed per token, and that
third parties may not offer claude.ai login or route requests through
Free/Pro/Max credentials. The user wants people to use their own
subscriptions, and plans a free public release (maybe donations later).

## Decision (user's)

Drop the Agent SDK for now and drive the user's own `claude` CLI instead.
The same docs say the credential restrictions don't prevent a user signing
in to the unmodified Claude Code binary with their own subscription. The
user asked whether this route can launch the CLI or only attach to one they
started; it can launch it (S02), and attaching comes later as planned.

How it works (details in NOTES.md → S02): the sidecar opens a terminal
running `claude` with per-session `--settings` (HTTP hooks to the
sidecar), `--session-id`, and our channel (a local MCP server) loaded via
`--dangerously-load-development-channels`. Hooks cover seeing the session;
the channel covers sending chat messages and answering permission prompts
(permission relay, first answer wins between terminal and world).

## Costs of this route

- No documented way to interrupt from outside, so `session.interrupt`
  can't be supported yet.
- Clarifying questions stay in the terminal.
- Assistant text arrives line by line (`MessageDisplay` hook), not word by
  word.
- Channels are a research preview: flags may change, custom channels need
  the development flag with a confirmation prompt (so the terminal must be
  visible), and Team/Enterprise organisations block them by default.

## Rejected

- **Agent SDK with the user's subscription:** the terms point SDK apps to
  API keys; too uncertain for a public release. Kept in NOTES.md →
  Deliberate limitations as a path not taken in the near future.
- **Agent SDK with an API key:** per-token billing on top of users'
  subscriptions; not what the user wants.

## Found along the way

The terms also restrict using Claude Code or Anthropic names and logos in
a product's own name or logo. Recorded as a watch item, since the agents
are "logo models".

## Follow-up: questions and stopping (same day)

The user asked whether we could type into the terminal what it expects,
to stop the agent and answer multiple-choice questions. Documented hook
features cover both instead:
- **Questions:** a `PreToolUse` hook on `AskUserQuestion` waits for the
  answer from the world and returns it in `updatedInput` with
  `permissionDecision: "allow"`. So the `questions` capability is supported
  on this route after all.
- **Stopping:** any hook can return `continue: false`. The sidecar answers
  the next hook call that way, so the stop happens at the next step rather
  than instantly. User approved moving interrupt from core to an
  `interrupt` capability (`interrupt.request`, config `immediate`), since not
  every route can stop instantly.

Rejected for now: typing keystrokes into the terminal. The sidecar would
have to own the terminal's input through a pseudo-terminal, and then either
draw the terminal itself or leave it invisible (but the terminal must show
the channel confirmation, folder trust and MCP consent prompts). The key
sequences for menus aren't a documented interface and can change between
Claude Code versions without notice, and a keystroke landing in the wrong
state could type or approve something unintended. The one keystroke worth
keeping in mind is Esc for an immediate stop, if the soft stop turns out to
be too slow in practice.

## Correction: the channel is started by Claude Code

While drawing the architecture overview: the channels reference says
Claude Code spawns each channel server as a subprocess and talks to it over
stdio. So the channel can't live inside the sidecar process; it is a tiny
"channel bridge" script that `claude` starts and that connects back to the
sidecar locally. NOTES.md → S02 and the Architecture diagram say so.
