# W06: an island could rise through a bridge

Features: W06, W12, W05, W10

`bridges_test`'s "no bridge over another island's land" failed now and
then (once in six runs, then again on the D01 branch the same day; NOTES
→ Watch items). Found while D01 was waiting for the user's live check,
working on my own while the user was away.

## The cause

The check now prints the culprit. Looping the test, it failed 2 times
in 15 runs (once in the demo, once in the crowd), both the same way:
an island's bridge to the platform passing 20.8 m from another island's
middle, well inside its land. `BridgeNetwork.add` checked a new bridge
against the regions already there, but never checked existing bridges
against a region that came later. In the tests a cluster's islands are
built off the main thread and rise in any order: when a further island
rose first, it was bridged straight to the platform, and the nearer one
rose under that bridge. The same happens in play after a restart (W12
adds islands one a frame, but each rises once built off the main
thread, in any order) and when a new session takes the nearer
spot a sunk island left, under the bridge that patched the gap.

## The fix (my pick, for the user's review)

A region that comes under a bridge takes that bridge's place: the
bridge goes, and its group is patched the way a sinking already is
(`_patch`, shared with `remove`), now through the new region. Every other
bridge stays. Rejected:
- keeping new islands' spots clear of bridges: it changes W05/W06's
  layout, and spots no longer fill nearest first;
- bridging a cluster only once its islands are all up: covers restarts,
  not a spot refilled in play.

It means a bridge can now go when an island rises, not only when one
sinks, which the user's re-linking rule (2026-10-07: every bridge still
standing stays, so nothing moves under you) didn't foresee. Islands
joined the tree only once risen, so an island still rose through the
bridge for its 3 s and the bridge went at the end.

## The user's decision (2026-10-27)

Keep the rule, and free the bridge as soon as the rise starts. A player
on it drops into the sea, which is fine now that a bridge's rails can
be jumped over anyway (D01's branch). `BridgeNetwork.make_way`, called from
`SessionIslands._rise` with the island's centre and reach, frees every
bridge over its land and patches the groups that cuts round it; until
the island is added, no bridge may cross it (`_blocked`, checked in
`_best_link`), so a group with no way round stays in pieces for the
3 s. `add` then patches those groups again, through the island when
it's theirs; `remove` calls it off if the island sinks before it rose.
`on_bridge_of` only looks at bridges still in the tree, so an empty
island whose bridge went sinks as if you'd left it.

One knock-on: `_tell_landings` ran for every island, so a rising one
was told it had no landings and its zipline (W10, which waits for its
bridges) was placed early. It now skips islands not yet in the tree.
That was already possible before, whenever another island's bridges
came while one was rising.
A bridge of another cluster (where clusters reach each other, W06's
known limits) is patched within its own cluster, without the new
island, and may come back over it.

## Tested

The tree's own test adds a region under a bridge (it takes its place;
the rest stay; gone again, the cut is patched as before) and regions
out of order (the same row, every bridge clear). Without the fix the
first of those fails (the suite stops at its first failure; the
out-of-order case would fail too: hub-r2 is made first, over r0 and r1). The bridges test then passed 20 runs in a row,
and every suite passed on Windows (the sidecar's typecheck and tests,
every Godot suite one at a time).

After the user's decision, the tree's test also makes way for a region
(the bridge over it goes at once, none crosses it meanwhile; added, it's
joined through it) and calls one off (patched as before). In the demo,
after the sinking, a new session rises on a sunk island's spot with a
bridge laid across it from the platform: as the rise starts the bridge
is gone and none crosses the spot, the island isn't in the tree yet;
once risen it's joined, and the layout checks pass. Every suite passed
again on Windows (the sidecar's typecheck and tests, every Godot suite
one at a time).
