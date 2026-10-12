# The sessions ring

Features: W07, S03, S04

The proper sessions menu, the next focus after the sidecar fixes. The
placeholder (three pages: Sessions with the Running list, Add a session,
Resume a session) only had to work (user's, 2026-10-01).

## The design (user's, 2026-10-12)

The user described it after the ability wheel in The Legend of Zelda:
Tears of the Kingdom, with pictures of that and Genshin Impact's quick
menu: hold Tab and the running sessions sit in a circle; pointing at
one grows it and shows its name; letting go of Tab on it teleports you
there. A cluster's sessions sit together. A fixed house segment at the
top goes to the platform, and a big plus in the middle opens the
session-create menu.

I first offered four layouts (list and detail, restyled pages, a
full-screen board) and other choices; the user dismissed those and
described the ring instead. I then asked about the parts the
description left open, each with a recommendation; the user took every
recommendation:
- **The plus**: a click while holding Tab opens it; letting go in the
  middle only closes the ring. Rejected: letting go on it (every quick
  tap of Tab would open the create menu, as the pointer starts in the
  middle), and letting go on it only after the pointer has left the
  middle (works, but it's unclear why it sometimes does nothing).
- **Many sessions**: past about 12, the busiest clusters fold into one
  segment each that fans out when pointed at. Rejected: always one
  segment per session (too thin to hit past about 16), and a second
  outer ring (a long move to reach, hard to aim).
- **A segment's picture**: the island's biome, with the state as a
  coloured rim. Rejected: the title's initials (all "New session" ones
  look alike) and a state icon alone (two working sessions look alike).
- **Resume, search and Stop waiting** move to the plus's panel; a
  starting session shows as a faded segment. Rejected: Stop waiting as
  that segment's action, and typing to filter the ring (awkward while
  holding Tab).
- **Icons**: drawn in code as placeholders until real ones (the user's
  or CC0). Rejected for now: a Kenney pack (may not cover every biome)
  and waiting for the user's own.

Other choices I made and stated without asking: pointing goes by
direction from the middle, not by touching a segment; the world keeps
going while the ring shows (no slow motion); clusters keep W07's fixed
order (2026-10-02).

## How it's built

`SessionRing` (`world/sessions_menu/session_ring.gd`) is a full-window
`Control` drawn in `_draw`: segments as polygons along arcs, a 6 px
state rim, icons from `RingIcons`, text with an outline. It rebuilds
its segments every frame while it shows, so it never misses a session
coming, going or being renamed; with at most a dozen or two segments
that's cheap. `SessionsMenu` keeps the Tab key: pressed, the ring; while
the ring shows it takes the mouse, the left button, Tab's release and
Esc. The old first page is gone; Add a session is now the panel's first
page and holds Stop waiting.

The fold limit is a variable (`max_segments`) so the world test can
fold h1 and h2's cluster without starting 13 islands.

Two things the screenshots caught (rendered from a scratch script, the
ring alone with made-up sessions):
- `set_anchors_preset` kept zero offsets, so the ring had no size and
  its middle sat in the window's corner. The tests passed anyway, since
  they point relative to the ring's own middle; now
  `set_anchors_and_offsets_preset`.
- Cluster names centred on a point just outside the rim overlapped the
  segments on the left and right sides; now each is pushed sideways by
  half its width, and they hide while a fan shows (a 9-session fan
  covered them).

Two notices said "the menu" or "Running": "Still starting; … stop
waiting in the sessions menu (hold Tab, click +)." and "Stopped waiting.
If that session starts later, it joins the sessions ring."

## Tests

The world test: the empty ring (⌂ only, at the top, pointing at the
middle), a quick tap and Esc doing nothing, a click on the plus opening
the create panel, a starting session's faded segment that can't be
pointed at, h1 and h2 as their cluster's arc, the middle's text,
pointing by direction from beyond the rim, folding and fanning out,
and letting go on a session or the platform; the platform from the sea
(W08) and Esc (C10) through the ring; and, with the fake provider, a
new session, a rename and a resumed session in the ring. Its helpers
now hold and release an action (`_hold`, `_release`) and click at a
point (`_click_at`).

What the tests can't see: the mouse itself, the look, and how the
pulse and the fan feel. That's the live check.

## Review fixes

From the docs-sync and security reviews before handing it over:
- Tab let go in another window never reaches the game, so the ring
  stayed open after an Alt+Tab. It now closes without acting when the
  window loses focus; tested, and a step in the live check.
- A session arriving or ending mid-hold rebuilt the segments and
  pointed again by direction, so a still pointer could end up on a
  different session. What is pointed at now stays until the pointer
  moves or it's gone; tested with a starting segment arriving, which
  shifts the pointer's old spot onto the neighbouring session.
- The fan's hit zone compared against the fixed 26° even when the
  fanned segments were narrower; it now uses the segment's own width.
- A test that the click on the plus only opens the panel: no picker,
  no start, no notice.
- `warp_mouse` may do nothing under Wayland: a Watch item (only Windows
  to test on).
- Docs that still said "sessions menu (Tab)", "Platform" in the menu or
  S03's "quick version" now name the ring and the create panel.
- Not changed: a long or right-to-left title can overflow the middle
  circle (cosmetic, older than this branch; the UI pass will redo it).

## Many clusters

The user asked what happens with a lot of clusters. Folding can't go
below one segment per cluster, so past about 12 clusters the ring
crowds (20 clusters: 11° segments, names overlapping), and a big
cluster's fan gets thin (4.5° at 40 sessions). Offered: a second level
("+N clusters" fanning out clusters) and fans in rows; accepting it for
now; or type-to-search while holding Tab. The user's call: a Watch item,
left to the UI pass (NOTES → Watch items → A ring with many clusters).

## The ring demo

The user checked the ring with real Claude and asked for a fake
provider setup showing everything else: `tests/live/ring_demo.tscn`
starts 12 sessions in four projects through the fake sidecar, with every
biome, waiting and working sessions, and keys for folding (F2) and a
starting session (F3). It sends the state-setting messages 3 s after the
naming ones: sent at once, the naming turn's end set the session idle
again over the question's waiting. The live check's steps now follow
the demo.
