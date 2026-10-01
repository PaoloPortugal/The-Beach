# Subagents, placement and state markers

Features: A02, A03, A04

## Decisions (user's)

Asked before building, each with a recommendation; the user took all
four recommendations:

- **Look (A02):** a smaller orchestrator (the same primitives at about
  60 %) at a little box PC. Rejected: a bare capsule (reads less like an
  agent at work) and Kenney props now (pulls the props question, open
  question 8, into M1). Open question 7 (the real look) stays open.
- **Placement (A04):** rings of fixed slots from about 10 m out, 3 m
  apart, a little jitter, facing the orchestrator; a freed slot is
  reused. Rejected: a golden-angle spiral (even at any count, but less
  orderly, and slots shift meaning as it grows) and a jittered grid
  (awkward on a round island, needs a front).
- **Coming and going (A02):** pop in at the PC; when done, walk in a
  straight line to the parent with a paper over the head and shrink
  away there. Not in M1: the throw, and path-finding. Rejected for now:
  plain pop in / pop out, and the full version with a thrown paper.
- **State markers (A03), pulled into M1 in a minimal form:** a yellow
  spinning diamond for working, a bouncing orange "!" for waiting, a red
  "×" for error, nothing for idle and done; an errored subagent stays
  about 10 s, then goes.

Scope: core. It reads only the generic agent tree.

## Built

- `agents/agent_placement.gd`: slot → position (rings, seeded jitter).
- `agents/subagent/`: the placeholder, popping in, walking back, leaving.
- `agents/state_marker.gd`: the markers, on subagents and the
  orchestrator.
- `agents/island_agents.gd`: one per island, follows the store; made by
  `SessionIslands` (new `agents()`).
- The orchestrator's message anchor moved from 2.3 m to 2.45 m so the
  bouncing "!" doesn't run into the bubble.

My picks (implementation details): only the PC is solid, so a walking
subagent never pushes the player; slots in the sea are skipped until the
rings pass any shore, so there is still no maximum; a subagent on a
slope stands at the lower of the two ground heights (its feet, its PC),
sinking in a little rather than floating; a walk gives up after 20 s;
the walker follows its parent if it moves, and falls back to the
orchestrator if the parent is itself leaving.

## Checks

- Headless (`tests/world/world_test.gd`): placement (ring sizes, spacing
  at least 2 m over 80 slots, outside the chat zone, stable, no
  maximum); by hand in the store: snapshot rules, three subagents at
  their own slots on the sand facing the orchestrator, the "!", a done
  one walking to its parent subagent and going, a freed slot reused, one
  resumed mid-walk going back to its PC, an error lingering then going
  and coming back to its old slot on resume, the orchestrator's marker.
  With `--sidecar-dev-fake`: "agents 3" in the chat brings three that
  all walk back and go, then the orchestrator's summary.
- Screenshots under Forward+ and Compatibility: 24 subagents on two
  rings, all three markers, a walking subagent. The first paper (a flat
  slab at head height) was nearly invisible from the side; it is now a
  little bigger and tilted.
- Live with the user and the real `claude` 2.1.284: the first run had
  one of two parallel Explore subagents linger by the orchestrator. The
  sidecar was ruled out first: a `claude -p` probe logging every hook,
  its payloads replayed through `HookTranslator`, and a `try:claude` run
  (interactive) all gave `done` for both, 0.5 to 1.5 s apart. (Claude
  Code shows hand-backs in the transcript as "Another Claude session
  sent a message: <agent-message …>", but the hook's prompt has no such
  prefix; `parseHandback` is fine.) The cause was the walk: each step
  was capped at the distance left to 1.4 m, so with 32-bit positions the
  last step could land a hair short, and the walker crept on until the
  20 s give-up. Arriving now allows a centimetre, and the tests fail if
  a walk needs the give-up (they had allowed 10 s and 30 s, which hid
  it). The second live run: both walked back and went.
- The same run found that Left in the terminal (Claude Code's subagents
  view) continues the conversation in a new session and cuts the world
  off; recorded in NOTES → S02 → Known gaps.
