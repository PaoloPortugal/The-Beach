# W05/W06: clusters that grow without limit

Features: W05, W06

Clusters can now grow without limit. The 8 wedges round the platform
take any number of islands, and a 9th and later cluster goes far out
as a real cluster with bridges of its own. Before this, an inner wedge
held at most 10 islands, because the outer ring of 8 wedges overlapped
its outer half. A cluster's 11th island, or a 17th cluster, went to a
lone far spot with no bridge.

## Decided (user's, 2026-10-09)

The user's intent: "a cluster [should] be able to expand outwards
basically infinitely, with its cone expanding more and more outwards,
doing something to make sure it doesn't collide with another cluster.
Once the maximum amount of clusters near the main island are reached,
only then is the new cluster sent far off."

- **8 near wedges (45° each), now unlimited.** The outer ring of 8 is
  dropped, so near clusters go from 16 to 8: "most users won't be
  running more than 8 repos at a time". Rejected: keeping the outer ring
  (that ring is what capped the inner wedges).
- **A 9th and later cluster goes far.** It starts with a single island
  far away and grows by bridging out from that one. It's a real cluster
  with bridges within itself but no bridge to the platform (teleport by
  the sessions menu or the big map, as before). Rejected: W06's lone far
  spots with no bridges.
- **A near wedge growing into a far cluster's area** is left alone for
  now and the near future, since it takes a huge number of sessions.
  It's recorded as a known limit (W05, W06) and a watch item.

## Mine, for the user to confirm

- **Where far clusters start:** on rings from 2000 m, about 1200 m
  apart both along a ring and between rings (10 on the first, 16 on the
  second). That keeps their areas apart until about 70 islands each. I
  widened W06's far rings (200 m apart) because those held single
  islands, not growing clusters.
- **How a far cluster grows:** its islands take the nearest free spots
  of a triangular grid 100 m apart (the wedges' spacing) through its
  first island, only on the side away from the platform. So it fans
  outward, away from the near wedges. Ties go to the spot furthest out,
  then to one side. A grid instead of the wedges' scan, because there is
  no wedge to scan, and a grid packs the most islands at a fixed
  distance from the first.

## What was built

- `SessionClusters`: slots 0-7 are the wedges, with no island limit;
  slots 8 and up are far clusters (`is_far`), at `far_spot(slot - 8)`
  plus `_far_spots`. The per-island far spots (`_far`, `is_bridged`,
  `INNER_ISLANDS`, `OUTER_START`) are gone. A held island keeps its
  index, so its spot, as before. A far cluster with only held islands
  keeps its slot.
- `BridgeNetwork.add(..., with_hubs = false)` makes a group hubless:
  its tree leaves the platform out, so its first island gets no bridge,
  later ones join the nearest, and a cut is patched within the group.
- `SessionIslands` bridges every island, a far cluster's without the
  platform. The minimap shows a far cluster like a near one (it showed
  just the one island before). The big map puts each cluster's name over
  all its islands.
- The layout demo now has 8 near clusters (one of 16 islands, reaching
  about 640 m) and 12 far ones (one of 6), still 64 sessions in 20
  clusters, now 52 bridges.

## Measured

With a quick script, not kept: a wedge's 10th island is about 530 m
out, its 50th about 1120 m, its 100th about 1560 m. Its 161st comes
within 100 m of a far cluster's first island (about 1970 m out). That's
a bit under the "roughly 180" estimated before building. Far clusters
of the first two rings, all growing at once, first come within 100 m of
each other at 70 islands each.

## Tests

- clusters test: 120 islands in each of the 8 wedges and 60 in each of
  26 far clusters, never closer than 100 m. Wedge spots stay inside
  their wedges and fill outward. A far cluster's islands fill nearest
  its first one first, and away from the platform. The 9th cluster goes far, a near cluster's 31st
  island stays in its wedge, a held far island keeps its spot, and
  a freed far cluster's place is reused.
- bridges test: a hubless group in the tree test. In the demo, every
  near island is joined to the platform and no far one is, and every
  far cluster's islands are joined to each other only. That still holds
  after islands sink, one of them far. The minimap shows a far cluster's
  islands.

## Bugs on the way

- The first run failed with `Biome` not found: this checkout's class
  cache predated W10, and `godot --import` fixed it.
- My first "fills outward" check compared distances from the platform.
  A wide row's side spots are further out than the next row's middle,
  so the check now uses the distance along the wedge's middle, which is
  what the scan orders by.
