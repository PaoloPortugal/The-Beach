# Claude CLI integration spike

Features: S02 (also S01, A02, C02, C05; protocol unchanged)

Throwaway M0 spike in `spikes/claude-cli/` (hub standing in for the
sidecar, channel bridge, self-test). Claude Code 2.1.284 on Windows 11, in
Windows Terminal, in an empty temp folder. Two sessions; the user accepted
the startup prompts and answered in the terminal when asked. Everything
else was driven through the hub's control API. The self-test (19 checks:
auth, browser-origin rejection, stop, question hold, hang mode, bridge in
both directions) passes without a real session.

## Worked as documented

- Launch with per-session `--settings` hooks, `--mcp-config`,
  `--dangerously-load-development-channels`, `--session-id` (the ID we chose
  is the one hooks report) and `--name`.
- Chat from the world through the channel; Claude answers normally.
- Assistant text via `MessageDisplay` (line batches), turn end via `Stop`
  (with the final text).
- Tool calls via `PreToolUse` / `PostToolUse`, keyed by `tool_use_id`.
- Subagents: `SubagentStart` / `SubagentStop` with `agent_id` and
  `agent_type`; their tool hooks carry `agent_id`; the stop carries the
  report.
- Permission relay: approve and deny from the world; approving closed the
  terminal dialog.
- Questions: answered from the world through a held `PreToolUse` hook, or
  handed to the terminal with an empty reply.
- Fail-safe: with the hook server hanging, erroring or offline, Claude Code
  asked in the terminal every time and nothing ran. Hooks resumed when the
  server came back.

## Findings

1. `SessionStart` doesn't support HTTP hooks (command hooks only). The
   sidecar knows the session started from the launch and the bridge.
2. World messages reach `UserPromptSubmit` wrapped in `<channel ...>`;
   typed ones are plain. The sidecar unwraps for display.
3. The user's default permission mode is `auto`, and the session used it.
   We never pass a mode. Hooks carry `permission_mode`.
4. A "No" in the terminal interrupts the turn with **no hook at all**, and
   the relay isn't told the request closed. The world must infer it.
5. The transcript file the hooks point to never appeared during the session;
   see 13 for why.
6. Claude Code runs internal helper agents (e.g. suggesting a next step)
   that fire `SubagentStop` and even tool hooks, with an empty
   `agent_type` and no `SubagentStart`. Ignore agents never seen starting.
7. A finished background subagent wakes the orchestrator with a synthetic
   `<task-notification>` user prompt. Not a user message.
8. `SubagentStart` doesn't name the parent. Inferred from the `Agent` tool
   call just before; needs a recheck with parallel spawns.
9. **Safety:** `continue: false` from `PreToolUse` stops the session but
   still runs that tool call. Fixed by also returning
   `permissionDecision: "deny"`; verified in run 2 (the tool didn't run).
10. No `Stop` hook after a hook-caused stop.
11. A stop inside a subagent stops only that subagent, which then gets no
    `SubagentStop`; only the `<task-notification>` shows it ended.
12. A hanging hook makes Claude wait its full timeout each time (30 s in
    the spike). Reporting hooks need short timeouts.
13. No transcript was written. Not our flags: the hub was started from
    inside a Claude Code session (by the assistant's Bash tool), so the
    launched `claude` inherited `CLAUDE_CODE_CHILD_SESSION` and other
    session variables, treated itself as nested, and turned transcript
    saving off (the terminal said so; the user noticed). Won't happen when
    the user starts the app, but it showed the launched process inherited
    another session's variables, so the sidecar must launch with a clean
    environment. Added to NOTES.md → Security rules.

Also: a deny from the world lets Claude continue its turn; a terminal "No"
interrupts it. `allowedHttpHookUrls` can block our hooks (watch item). The
MCP SDK pulls in 94 packages (watch item).

## Not tested

Parallel subagent spawns (parent inference), nested subagents, compaction
events, `StopFailure`, a question hook timing out, Team/Enterprise
channel policy, macOS/Linux terminals.

## Result

No protocol changes needed. S02 in NOTES.md now describes the verified
behaviour and the inference rules for the gaps.
