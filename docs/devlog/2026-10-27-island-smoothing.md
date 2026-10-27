# Island smoothing

Features: W01, W06, W12

## Where it came from

After C14's live check islands were made off the main thread (their
ground on a worker), but the user still saw islands arriving hitch
behind the main menu and mid-game, and asked (2026-10-26) to smooth
them: pay first-time costs up front, spread an island's main-thread
work over frames, and build an island's props once instead of once and
again for the torches.

## How it was measured

`tests/live/timing/time_world.gd` runs the real world scene in a window
(main menu up, vsync off, the fake provider, its own islands file) and
sends six sessions' snapshots, one biome each, 140 frames apart, then
prints the median, the 95th percentile, the worst frame, the frames
round each snapshot and each island's `built`, and every frame over 2.5
times the median. `time_finish.gd` times an island's main-thread steps
alone. During the work they carried temporary prints (each step, each
part of `SessionIslands._place`, the render's CPU and GPU time, where
in the frame the time went); those are gone. Runs on a busy machine
gave 200-330 ms frames everywhere and were thrown away.

## What was found and done

- **An island's finish all at once** was 18-30 ms. Now `_finish_steps`
  adds it a step a frame: the ground, the collision's faces, the
  collision, the props, the torches, the rest (2-8 ms each).
- **Props built twice.** The torches cleared props near them after the
  props were built, which rebuilt them. Their spots are now cleared
  first (`IslandProps.without_near`).
- **A biome's first props** cost 16-100 ms: each kind's mesh was made
  the first time it was used. `IslandProps.warm_up` makes them all on a
  worker (`commit_to_arrays`; the `ArrayMesh` is made on the main thread
  when first asked for). The props step is now about 2.5 ms on every
  island.
- **Shaders built again.** A warm-up that added one of each thing and
  freed it didn't help the first orchestrator (still 50-70 ms to add):
  a `StandardMaterial3D`'s shader is freed with the last material using
  it, so the state marker's unshaded parts and the beacon's see-through
  one were compiled again (about 30 ms). `WarmUp` now keeps every
  material it made in a static list for good; the first orchestrator's
  add went to 2 ms. One shared ground material for every island helps
  the same way.
- **The first message bubble** took 24.7 ms to add, and its first frame
  about 40 ms more before anything was drawn (its fonts, its
  SubViewport's first text). The warm-up now adds a bubble showing some
  Markdown too. The first snapshot's frame went from 75 ms to 16.5 ms.
- **The island memory's writes** (W12) were 7-9 ms on the main thread,
  one per island placed. Now one worker task writes the newest text,
  looping while a newer one waits; `load_file`, a switch to another
  file and `SessionIslands` leaving the tree wait for it (`flush`).
  `clusters_test` flushes before it deletes or writes the file by hand.
- **Bridges** were about 0.5 ms a metre on the main thread (51 ms for a
  102 m bridge). Sessions' bridges are now made on a worker, on a
  stand-in bridge of their own out of the tree (a body comes with any
  `Node3D` we'd make there, so it's made on the main thread and handed
  over), and added a few frames later. An island's `_bridge` call went
  from 54 to 3.8 ms.
- **A leak.** `clusters_test` reported 8 `GodotBody3D` RIDs leaked at
  exit: an island freed before its props step never added its
  `IslandProps` (a `StaticBody3D` made with the island), so nothing
  freed it. The island now frees them itself when they're not in the
  tree.

## Found by the suites and the reviews

- **Meshes made on a worker.** The first warm-up made the props'
  `CylinderMesh`, `SphereMesh` and `BoxMesh` on its worker, and each
  makes a RenderingServer mesh. In the performance test that raced with
  the state marker's mesh made on the main thread ("Attempting to
  initialize the wrong RID": the headless renderer's mesh list isn't
  thread-safe). The primitives' arrays are now made first, on the main
  thread (`_collecting`: a pass of `_arrays` that only gathers them into
  `_shapes`), and the task only reads them. The task is also waited for
  if the game quits while it runs (`IslandProps.finish_warm_up`, from
  `WarmUp._exit_tree`; security review).
- **Tests that leaned on timing.** world_test applied two sessions'
  snapshots at once and expected the first one's island to get the
  bridge to the platform; their islands are made on two worker tasks
  that finish in either order (since C14), and it failed once in about
  eight runs. The second snapshot now waits for the first island. The
  new-island arrow check aimed at an island still out of sight, being
  made, which an island built in one frame used to hide; it now waits
  for `built`.
- **The memory's writer** (security review): a writer task cut short by
  an error would have left its "writing" flag set and no later save
  would start another; waiting for a finished task now clears it. Tests
  added for switching files mid-write and for the islands leaving the
  tree waiting for the last write, and NOTES W12 now says a crash (not
  a quit) can lose the newest write. `time_world.gd` refuses to run
  without `--sidecar-dev-fake`.

## Measured after (2026-10-27, a window, behind the menu)

Median 9.7 ms, 95th percentile 18.2 ms, worst 21.1 ms, no frame over
2.5 times the median. The first ~150 frames are 15-19 ms with no island
yet (the menu camera's first view, GPU bound), so the first island's
16-18 ms frames are that, not the island. Before this work: the first
snapshot's frame 75 ms, a biome's first island 16-100 ms in its props
step, bridges up to 51 ms. The warm-up itself costs about 60 ms in one
frame while the world loads behind the menu (the orchestrator's
shaders and the bubble's text): one hitch there instead of one per
first-of-its-kind island.
