# W12: islands kept across restarts

Features: W12, S07, W05, W06, W10

## What

After S07 brought running sessions back after a restart, each island
came back as a new one: a random biome and seed, in whatever order the
snapshots arrived, so clusters and shapes shuffled at every start. W12
gives a session taken back its island as it was: biome, seed (so the
same shape and props), cluster and order.

## Decisions

The user's (2026-10-19):
- **Saved by the game, not the sidecar.** Its own file in Godot's user
  data (`user://islands.json`). The sidecar stays game-agnostic and the
  protocol doesn't change. Rejected: an opaque blob the sidecar keeps in
  the run folder and hands back in the snapshot.
- **Gaps close up.** Islands of sessions that ended while the game was
  closed leave no hole: the rest keep their order and move inward, and
  whole clusters close up their wedges the same way. This was against my
  recommendation (keep every exact spot, holes left for new sessions to
  fill).
- **Bridges are rebuilt, not saved.** Islands are added in saved order,
  each bridged to its nearest (W06), which gives the same tree in the
  usual case. Rejected: saving each bridge's ends.
- Filed as its own feature, W12, scope core.

Mine (put to the user for review):
- **The key** is provider, `started_at` and the project's path. These
  stay the same across a restart and a `/clear`; `native_id` doesn't
  (a `/clear` changes it), and the world's session id is per run. For
  that, the sidecar now announces a launched session's `started_at` as
  the launch time its run folder keeps (before, a new session announced
  a slightly later time than the one a restart reported, so the key
  would never have matched).
- **A session with nothing saved** (a missing or damaged file, or one
  launched before W12) is placed after the saved ones, joining its
  repository's cluster if that came back, else a new cluster after them.

## How

- `IslandMemory` (`world/island_memory.gd`): reads and writes the file.
  A damaged file or entry is ignored (parsed with `JSON.new().parse`, so
  no engine error); JSON numbers are turned back into ints on load.
- `SessionStore` gained a `syncing` flag and a `synced` signal.
  `SessionIslands` holds snapshots of sessions already running that
  arrive while syncing, and on `synced` places them in saved order, then
  the rest, and drops entries of sessions that didn't come back.
- `SessionClusters.restore` remakes a saved cluster with its name and
  repository (so new sessions of that repository still join it), mapping
  the saved cluster id to this run's, so several islands share it.
- `Island` keeps its rolled seed in `island_seed`, which is saved.
- The test suites point `IslandMemory.file` at their own file
  (`tests/error_watch.gd`), deleted at each suite's start.

## Open point

A session found after the sidecar's restore wait (S07) arrives after
`sync.completed`, when its entry has already been dropped as one that
didn't come back: it comes back as a new island. Low likelihood (the
restore takes at most 8 s); recorded in NOTES.md → W12.
