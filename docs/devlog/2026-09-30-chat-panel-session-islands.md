# Chat panel, a quick session start, and an island per session

Features: C02, S03, W01, W03, A01

## Decisions (user's)

Asked before building C02, with recommendations:

- **How a session reaches the world.** I suggested a launch flag
  (`-- --project=<folder>`) or a "start" step at the orchestrator. The
  user chose otherwise: an island is only made once its session is
  confirmed up (after folder trust and the channel confirmation in the
  terminal); the player starts on a fixed square in the middle of the
  water; a quick "create session" feature, to be designed better later;
  when the session is up, make a random island and teleport the player
  there (also temporary, until bridges and travel are designed).
- **The floating message:** streams, last 4 lines (as recommended).
- **Look:** a bubble in the world (smaller with distance, hidden by
  terrain) and a dark translucent full panel with chat bubbles (as
  recommended).

My picks for the quick start (implementation details, said to the user):
a signpost on the platform with "Press E to start a session", the
system's folder picker, the status on a label above the sign, one session
starting at a time, islands on rings of six 180 m out, and falling in the
sea as the way back to the platform.

## Built

- `world/platform/`: the spawn platform and `SessionPost` (S03, quick).
- `world/session_islands.gd`: an island and orchestrator per live
  session; the world teleports you to one you started.
- `chat/message_bubble.*` and `chat/chat_panel.*` (C02), wired through
  `ChatController` to `SessionStore`; `SessionStore.orchestrator()`.
- The world test now runs sessions applied to the store by hand, and with
  `--sidecar-dev-fake` a real start from the post and a chat turn.

## Black stripes on islands away from the origin

The first screenshots of a session's island (under Forward+) had large
black, striped triangles near the camera. Ruled out one at a time with a
scratch script that renders the world and saves PNGs: not the ocean
(hidden), not the bubble (removed), not lighting (the same with shadows
off and with the sun off, where the rest of the sand turned blue-grey
from the sky light but the black stayed). The same island seed from the
same view was clean at the origin and broken at x = 180 m. Turning off
the depth pre-pass (`override.cfg`) fixed it: the pre-pass and the colour
pass disagreed on the island's depth, so the colour pass skipped those
pixels and they kept the cleared black. Seen on an AMD Radeon under
Vulkan (Godot 4.7.2). The pre-pass is now off for every GPU in
`project.godot` (NOTES → Watch items). Rejected: adding AMD to Godot's
per-vendor pre-pass list (other GPUs can't be tested here) and building
islands at the origin in world coordinates (W04 will move them anyway).

A false lead first: the scratch script moved the player 10 m forward at
the same height, into a dune, and the view from inside the terrain looked
like the same bug. Another: hand-made sessions in the scratch script
vanished when the sidecar finished connecting, which is correct (the
store drops sessions the sidecar doesn't have after a sync); scratch
scripts now wait for the sidecar first.

## The folder picker: native, then Godot's own

First version: the system's native picker (`use_native_dialog`). A native
`FileDialog` never becomes visible as a Godot window; it only reports
back through `dir_selected` and `canceled` (Godot's source), so the post
gave the controls back on those. In the live test with the user, alt-tab
while the Windows picker was open left the game stuck: tabbing back
showed the game, not the picker, and the game kept waiting for it (the
log showed no error; the process was still responding). Godot can't
reliably bring a native dialog back or close it, so the post now uses
Godot's own picker, drawn inside the game window, where alt-tab can't
lose it and Esc cancels it. It starts in the home folder. The test now
opens and cancels it headlessly.
