# W06: an island could rise through a bridge

Features: W06, W12, W05

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
standing stays, so nothing moves under you) didn't foresee; NOTES → W06
marks it open for the user. Islands join the tree only once risen, so
an island still rises through the bridge for its 3 s and the bridge
goes at the end; freeing it as the rise starts is the user's call too.
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
