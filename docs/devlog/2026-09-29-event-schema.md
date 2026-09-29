# Event schema v1

Features: docs (protocol; shapes S01, S02, A02, A03, C02, C04, C05)

## Decisions

- **Session ownership (open question 5), user's:** the app will eventually
  both run its own sessions and attach to ones running elsewhere. v1 only
  runs sessions started from inside the app. The schema had to allow
  attaching without using it.
- **Snapshot + changes.** On connect the sidecar sends a full snapshot per
  session, then only changes. This one mechanism covers Godot restarting in
  v1 and attaching later, so attaching needs no schema change. Chat history
  is fetched on demand instead of being in the snapshot, since it can be
  large.
- **Sidecar-made session IDs**, with the provider's ID as `native_id`: a new
  session exists before Claude assigns its UUID, and other providers may have
  none.
- **Agents as a tree** (`role` + `parent`), user approved. Costs nothing now
  and handles nested subagents.
- **State enum**, user approved: `working`, `waiting`, `idle`, `done`,
  `error`, with per-role use documented. The user asked whether subagents can
  be idle; they can't in Claude Code (a subagent does one task, returns its
  result and finishes), but they can wait on a permission prompt, error, and
  be resumed after finishing. So `idle` is orchestrator-only and `done`
  subagent-only. Rejected: one enum per role (more to maintain, and a future
  provider's subagents might really idle).
- **Extensions as `ext.<provider>.<name>`**, user approved over a provider
  field: routing is a prefix check and deleting a provider is easy to grep.
- **One integer protocol version**, user approved; Godot refuses a mismatch.
  Enough while both sides ship from one repo.
- **`agent.finished` dropped** from the design's vocabulary: a state change to
  `done` says the same thing, and since subagents can be resumed, "finished"
  isn't final anyway.

## Visual idea (user's)

A finished subagent runs to whoever called it with a paper on its head,
throws the report to it and disappears. This is presentation only, recorded
in A02; the enum is unchanged.

## Checked against the Agent SDK docs

The user asked for extra care on integration work, since they can't review
it from experience. The schema was checked against the current Agent SDK
docs (hooks, permissions, subagents, sessions, streaming, user input).

Confirmed: subagents nest (3 deep, 20 at once by default), finished
subagents can be resumed (not the built-in Explore/Plan ones), permission
callbacks can wait indefinitely, stored sessions can be listed and read,
and messages sent mid-turn are queued.

Added, user approved:
- **`session.interrupt` (core).** Every coding agent can be stopped; the
  first draft had no way to do it.
- **`questions` capability.** Claude's AskUserQuestion (1–4 questions, 2–4
  options each, multi-select, free text) arrives through the same callback
  as permissions but needs its own UI. A capability rather than core,
  because other providers may lack structured questions. Answers are per
  item in order, not keyed by question text as the SDK does; the provider
  maps them.

Noted, no schema change: subagents run in the background by default, so
the orchestrator can be `idle` while subagents work; subagent text arrives
as whole messages, not deltas. "Allow always" is deferred to C05.
