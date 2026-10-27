# S08: the flag check read the island mid-build

Features: S08, W01, C14 (tests/world/world_test.gd)

`world_test.gd` failed once (Linux, Godot 4.7.2, branch d01-fishing after
merging main, 2026-10-27) with `FAIL S08: o1's flag stands on its island,
near the edge (r 21.5)`, island seed 1389393775, Beach. A re-run passed.
The game was fine: the test read the flag while its island was still
being built.

## Cause

Session islands are built in the background (C14): the ground is made on
a worker thread, then added a step a frame. The first step
(`_add_ground`) hands the built grid to the generator, so from then on
`surface_height` reads the built mesh instead of `height_at`. The flag
went up before that, on `height_at` (from `set_read_only` when the island
is placed), and is placed again only in the last step (`_add_rest`), in
the same frame `built` is emitted. For the steps in between, about five
frames, the flag stands where `height_at` put it while `surface_height`
already reads the mesh.

The check ran two frames after the sessions were applied. Usually the
worker hadn't finished by then, so flag and ground both used `height_at`
and it passed. When the worker finished sooner, the check landed in
the window and failed.

Reproduced with seed 1389393775, Beach, by stepping a background
island frame by frame with the flag on it:

| Frame | Ground | Flag (r, y) | `surface_height` there |
|-------|--------|-------------|------------------------|
| 1-7   | being made | 21.5, 1.113 | 1.113 (`height_at`) |
| 8-12  | grid in, steps left | 21.5, 1.113 | 1.098 (the mesh) |
| 13    | built  | 22.0, 0.888 | 0.888 |

Once built it stands on the mesh, a little further out (r 22.0). r 21.5
in the failure is the `height_at` spot: it was read inside frames 8-12.

## Not a game bug

The island stays at `SessionIslands.BUILDING_Y`, 100 m below the deepest
seabed, until `built`, and only then rises. Nobody can see the flag
during those frames, and it is right before `built` fires. A
`set_landings` or `set_read_only` mid-build places it on whatever ground
the generator has then, and `_add_rest` places it again anyway. So the
code is unchanged and the tolerance stays at 0.01 m.

"Island seed" printed twice was o1 and o2. The test's sessions share a
provider, start time and project, the island memory's key (W12), so o2
gets the biome and seed just remembered for o1, and the two islands are
the same. Neither island was built again.

## Fix

The test checks that each island has the mark two frames in, as before.
It then waits until both islands are built before checking where the
flag stands.
