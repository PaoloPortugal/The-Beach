# W10: the mountain bugs (torches in the air, ziplines through bridges)

Features: W10, W09, W06

The two mountain bugs the user saw on 2026-10-09 (Watch items), fixed
at their request (2026-10-12).

## Torches in the air

Cause, as guessed: torches stood at `IslandGenerator.height_at` on the
cliff's lip, but the island's mesh is a jittered 2 m grid sampling that
function, so on an 18 m cliff the triangles under a point can be well
below it. Measured on 40 mountain seeds (160 torches, at height_at's
lip): up to 2.0 m off the mesh, median 0.76 m, 154 of 160 more than
10 cm off. The zipline's posts, by the lip too: up to 0.64 m, median
0.02 m, 19 of 80 more than 10 cm.

Fix: `IslandGenerator.surface_height(x, z)`, the built mesh's height.
`build()` keeps the grid and its coarse blocks; the function finds the
triangle under the point among the 3x3 nearby cells (a coarse block's
when the block is coarse), using the same diagonal split as the mesh
(`_cell_triangles`, now shared with `_add_cell`), and interpolates its
plane. Checked against a brute-force search over `build()["faces"]`:
12,160 points on 40 seeds, on and off the cliff, no mismatch. Torches
now look for the lip on the mesh and stand on it; the zipline's posts
stand on it. The world test builds 12 mountains and checks every torch
and post against the collision faces: at most 0.000 m off (1.704 m
without the fix, so the check catches it).

## Ziplines through bridges

Cause, as guessed: the zipline stood at the first valley's mouth, fixed
with the island, and a bridge lands wherever its neighbour lies. Both
run roughly outward from the island's middle, so they clash when they
point the same way. Measured (400 seeds, random bridge directions): a
bridge through the cable on 4.0 % of mountains with one bridge, 5.5 %
with two, 7.8 % with three.

Options put to the user:
- *The zipline moves* (recommended, picked): to another valley's mouth
  when a landing comes near its cable. Bridges stay straight between
  island middles, and the change stays in mountain code. Its cost: a
  landmark can move after you've seen it.
- *The bridge shifts sideways* along the shoulder: the zipline never
  moves, but the bridge comes in at an angle, could land by a spire or
  on a valley's slope, and the shared bridge landing gets a mountain
  exception.
- *Placed once at rise*: simplest, but a neighbour arriving later can
  still bring a bridge through it.

How: bridges come and go (a sinking island's bridges go and the pieces
are patched), so after every `bridges.add` / `remove`,
`SessionIslands._tell_landings` gives each island with a zipline its
bridges' near ends (`Island.set_landings`). `IslandGenerator.zipline_room`
measures, in plan, how close the cable comes to each bridge's middle
line (2 m inside the landing, straight out by the island's radius);
`zipline_valley` keeps the current valley while that's at least 3 m
(`BRIDGE_CLEAR`: 1.8 m past the 2.4 m deck's edge), else takes the
first clear one of the 3, else the roomiest. In the same 400-seed run,
a clear valley was found every time. While someone rides, nothing
moves; `Zipline.ride_ended` (deferred) places it again. `zipline_ends`
takes the valley's index.

The props cleared under the old cable stay cleared, a bare strip down
the cliff: the user's choice (2026-10-12) over laying the props out
again.

Tests: a world-test check on 12 seeds (a landing beside the cable moves
it to a clear valley; one elsewhere, none, or one beside another valley
doesn't), and in the world, the risen mountain's cable clears its
bridges, and a landing put on its cable mid-ride moves it only after the
ride.

## Not done

Bridges also land at `height_at`'s lip (`SessionIslands._shore_point`),
so their ends could sit off the mesh like the torches did. Not seen as
a bug (a bridge's end overruns and its posts sink), so left alone.
