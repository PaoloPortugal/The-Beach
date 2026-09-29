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
