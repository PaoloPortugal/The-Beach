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

## Review fixes (2026-10-22)

The security review found no blockers; fixed:
- `islands.json` holds running sessions' project paths, so it's now
  owner-only off Windows, like the sidecar's run folders: created empty,
  restricted, then written (Godot can't change a file's mode while it's
  open on macOS), through `islands.json.tmp` renamed over.
- Entries are checked strictly: text at most 256 characters, numbers
  within 32 bits; tests for each kind of damaged entry and another
  version.
- Nothing tested that the suites stay off the user's file: removing the
  line in `tests/error_watch.gd` passed every test, and a sync's
  `keep_only` would then wipe the user's islands. `clusters_test.gd` now
  checks the path first.
- `tests/world/layout_demo.gd` run as the main scene wrote its fake
  sessions into the real file; it keeps its own now.
- Two games at once overwrite each other's entries: recorded as an open
  point (layout only).

Dead end: GDScript has no octal literals (`0o600` is a parse error); the
test compares against `FileAccess.UNIX_READ_OWNER | UNIX_WRITE_OWNER`.

Second review pass: `tests/live/ring_demo.gd` (and any run with
`--sidecar-dev-fake`) still used the real file, and a sync there would
drop the real sessions' entries; such runs now use
`user://dev-fake-islands.json`. The text cap went from 256 to 4096 so a
long project path doesn't lose its island. The owner-only check runs
only off Windows: unproven until CI runs again.

Live check passed with the user (2026-10-22); merged to `main`.
