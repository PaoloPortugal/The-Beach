# Agent view off, /clear followed

Features: S02

Fixes the S02 known gap "Continued conversations cut the world off"
(found 2026-09-30). The decided fix assumed Claude Code restarts the
channel server in the same process; a live probe showed something else,
and the user changed the decision.

## What Left at an empty prompt really is

A temporary sidecar change rewrote the bridge token in `mcp.json` after the
first connect, and logged which token each bridge connection presented.
Claude Code 2.1.285, Windows, `C:\Users\paolo\sandbox\notes-app`:

- After `continued-in` (11:29:01.0), a connection came with the **new**
  token at +4.0 s and another with the same new token at +4.4 s (refused,
  single-use). The original bridge stayed connected the whole run (3 min+).
- The process list explained it. Left opens **agent view** (Claude Code's
  docs: "agent view"; not a subagents window). It started a supervisor,
  `claude daemon run --origin transient`, which spawned two new
  `claude.exe` processes under `--bg-pty-host`:
  `--session-id <new> --fork-session --resume <old transcript> --settings
  <ours> --mcp-config <ours> --permission-mode auto` (the continued
  conversation) and `--session-id <other> --settings <ours> --mcp-config
  <ours> --agent claude --inherit-permission-mode auto` (unknown; never
  wrote a transcript). Neither had `--dangerously-load-development-channels`.
  So it isn't a re-read of `mcp.json`: new processes read it at their
  start, both at once, and either could have won the rotated token.
- The original `claude` (old session id) kept running with its bridge; the
  terminal was attached to the background copy. World messages sent down
  the old bridge landed only as a `queue-operation` in the old transcript.
- Docs (agent-view page) say launch flags `--mcp-config` and `--settings`
  carry over and the session keeps its id; live, it got a new id. Agent
  view can be turned off with `disableAgentView: true` or
  `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`.
- The /clear in that run happened inside the background copy
  (`sessionKind: "bg"` in its transcript), so it didn't count.

## Decision (user, 2026-10-01)

- **Agent view off for sessions started from the world:**
  `disableAgentView: true` in our per-session `--settings` file (the
  user's own settings untouched). Rotation and accepting a second bridge
  were dropped.
- **If a conversation still moves** (`continued-in` in the followed
  transcript): notice `conversation_moved`, the moved conversation's hooks
  are ignored (the terminal handles everything), and `message.send`,
  `permission.respond` and `interrupt.request` answer `provider_error`
  with a clear message instead of losing it.
- **Always:** with no live bridge, `message.send` / `permission.respond`
  say so ("The world can't reach this conversation right now ...").
- **/clear is followed on the same island** (the user: same repo and
  working folder, so the island still houses related work): new event
  `session.updated` (only changed fields; `native_id` for now; user chose
  it over putting the id in the notice or re-sending a snapshot) and
  notice `conversation_cleared`, wording as proposed.

## How it works

`ClaudeSession.ownConversation`: a hook whose `session_id` isn't the
followed one first polls the transcript (a `continued-in` is written
before the moved session starts). If the conversation moved, or the id
isn't a UUID, it's ignored; if its `transcript_path` is in another folder
than the first hook's, ignored and logged; otherwise it's /clear: switch
`native_id`, emit `session.updated` and the notice, tell the provider
(the new id is live, the old one becomes a stored, resumable session).
Hooks without a `session_id` count as the followed conversation.

## Checks

- `node:test`: 145 pass (new `conversations.test.ts`: /clear followed,
  other-folder hook ignored, moved conversation, no bridge; schema;
  `continued-in` parsing; settings). Typecheck clean. Godot headless:
  `session_store_test` (new `session.updated` check), `sidecar_client_test`,
  `world_test` pass. `dev:fake` gained a `clear` word.
- `claude -p` with `disableAgentView` in `--settings`: accepted, runs.
- Live with the user (11:55–11:59): the session came up; Left, `/bg`
  (not recognised) and `/fork` (asked for arguments) started no
  background session and no new process; `/clear` in the foreground
  session started a new transcript in the same process with no new
  bridge connection; the world got `session.updated` and the notice,
  then the next turn; a world message after it reached the new
  conversation and was answered.
- Not checked: `/fork <prompt>` with an argument while agent view is off.
  If it still moves the conversation, the `conversation_moved` path
  covers it.
- Note: the 2026-10-01 probe's background session (`96033ade…`) and its
  supervisor were still running when this was written; the user stops it
  from `claude agents`.
