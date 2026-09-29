# S02: permissions, questions, stopping, transcript, notices, history

Features: S02

Built unattended on stacked branches after the first S02 part was merged
(the user approved that merge): `s02-permissions` → `s02-questions` →
`s02-interrupt` → `s02-transcript` → `s02-notices` → `s02-history` →
`s02-live-tools`. None of it has run against a real `claude` yet: every
launch shows the development-channel confirmation, which needs the user.
Everything was built from the spike's recorded payloads and timings and
tested end to end with a stand-in for Claude Code (a real hook endpoint and
bridge socket, a schema-checking Godot-side client). 130 tests.

## Permission relay

- **Source: the channel's relay, not the `PermissionRequest` hook.** The
  spike logs show the relayed prompt (with the `request_id` the verdict
  needs) arriving about 100 ms after the tool call's `PreToolUse`, and the
  `PermissionRequest` hook a few ms after that. The relay can be answered
  from the world; the hook can't (holding it would hold up the terminal's
  own answer). So the hook isn't registered for plain permissions.
- **Tying it to a tool call.** The relay names no tool call or agent. The
  sidecar picks the open call of the same tool whose input the relay's
  `input_preview` shows (JSON, differently spaced, maybe cut short:
  compared without whitespace, prefix allowed), else the newest open call
  of that tool without a prompt, waiting up to 300 ms for a late
  `PreToolUse` (it comes on the other connection). Considered: always the
  newest call; rejected, since an already-allowed long-running call of the
  same tool would be picked.
- **Resolving.** World allow/deny → `permission.resolved` (app); a deny
  also closes the call as `denied`, since the spike showed no hook at all
  for a call denied from the world. Terminal "Yes" → the call's
  `PostToolUse`/`PostToolUseFailure`. Terminal "No" → the transcript
  (below), or as a fallback the turn ending / the user's next message.
- A `note` with the answer is refused (`not_supported`): the verdict
  carries no text. Open question for the user.

## Questions

`PermissionRequest` is registered for `AskUserQuestion` only and held open
(24 h timeout) until either side answers, as in spike run 3. The question's
id is the call's `tool_use_id` from the `PreToolUse` just before. The hook
server grew an abort signal so a held hook Claude Code drops (timeout,
exit) resolves the question. Unverified and flagged for the live run:
multi-select answers joined with ", ", and a free response sent as a deny
with the user's words.

## Stopping

The spike's recipe (`continue: false` plus a deny on the next
`PreToolUse`). Decisions: the orchestrator goes idle, a stopped subagent
`error` / `interrupted` (NOTES → Protocol; `flows.md` said `done` and was
changed; flagged for the user). Pending prompts and held questions are
declined when the stop is asked, or they'd block it.

**Bug found in review:** the first version kept the stop armed while
anything was busy, so with a background subagent still working, the user's
next turn was stopped too. Now the stop applies to the agents busy when it
was asked, each once. The regression test was checked to fail on the old
code.

## Transcript follower

The spike's transcript has exactly what hooks miss. A "No" is a tool
result with `is_error`, `toolUseResult: "User rejected tool use"` and
`toolDenialKind: "user-rejected"` naming the call's `tool_use_id`, followed
by `[Request interrupted by user for tool use]`; Esc is `[Request
interrupted by user]`. The follower polls the file the hooks name, from its
end, and moves to the new file after `/clear`. The parser was run over the
whole spike transcript: it finds exactly its one "No" and two
interruptions.

## Transcripts off and notices

Probed with `claude -p` (no channel, so no confirmation prompt) and hooks
pointed at a local listener: with `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1`,
hooks still name a `transcript_path`, but nothing is ever written there;
with saving on, the file exists by the `Stop` hook. So: no file a second
after the first reply means transcripts are off. The `session.notice`
event (code plus English fallback, one per code, in the snapshot's
`notices`) is drafted for the user's approval.

## Also found

- A live run showed Claude Code injecting a **subagent hand-back**
  (`<agent-message from="…">[Subagent hand-back]…`) as a prompt reusing the
  user's `prompt_id`: it became a fake user message with a duplicate id.
  Now recognised, and a `prompt_id` names a message only once.
- An `Agent` call denied or stopped before its subagent started stayed
  queued and could pair with a later subagent. Fixed in review.
- Bridge `request_id`s are five lowercase letters without "l"; a test using
  `late0` was correctly refused by the bridge server.
