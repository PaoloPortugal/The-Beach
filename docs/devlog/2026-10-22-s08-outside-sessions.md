# S08: read-only islands for sessions started outside the game (the build)

Features: S08, S07, C10, W12, Protocol

Built on `s08-outside-sessions` the day it was designed (research and
the first decisions: 2026-10-22-s08-outside-sessions-research). Every
live Claude Code session on the machine now gets a read-only island:
terminals, the desktop app, IDEs and background sessions still working.
NOTES.md → S08 has how it works.

## Decided while building (user's, 2026-10-22)

- **The mark is a grey flag** on a pole near the island's edge, a
  placeholder from primitives (`world/island/read_only_flag.gd`), on
  every island whose snapshot has `read_only`, S07's too. The first one
  (a 3.6 m pole, a pale grey pennant) vanished against the sky in the
  renders; a darker, bigger pennant across the edge still sat under the
  treetops from the sea. The user asked for it way taller: now a 9 m
  pole with a 1.7 × 2.8 m dark grey pennant, which shows from across the
  sea. The user approved it from renders near, at 45 m and at 90 m
  ("reads well"). Credited as Claude-made (AI-written code) in `assets/CREDITS.md`,
  at the user's request, until real art replaces it.
- **The mark on the maps** (2026-10-23, user's pick of three): a
  little grey flag where the island's flag stands, on the minimap and
  the big map (10 px, up to 20 px zoomed in), with a dark edge so it
  shows on sand, snow and sea. Rejected: a dashed outline (too like the
  big map's hover outline); the flag plus "read-only" in the big map's
  titles (longer labels, fewer fit). Checked from renders (the minimap,
  the big map, zoomed in) before the live check. The user asked for it
  to be marked a placeholder: the assets will change, maybe the design.
- **The wording:** the notice `outside_read_only`, "This session was
  started outside the game, so it's read-only here. Use its own window
  to chat with it."; the provider notice `outside_sessions_off`,
  "Sessions started outside the game can't be shown: agent view is off
  in Claude Code." Both as drafted.
- **The chat line per origin:** S07's stays "Read-only: use its
  terminal."; an outside session says "Read-only: use its own window."
  (it may be in an app or an IDE).
- **A toggle** (new): Settings → Game → "Show sessions started outside
  the game", on by default. Off: the sidecar ends each outside session
  (`session.ended`, reason `user`: islands sink, W12 forgets them) and
  stops asking unless S07's read-only sessions need it. On: it asks at
  once and announces them as `session.created`, so they rise at once.
- **Agent view off:** the toggle is greyed out and shown off, with the
  notice in red beside it; the saved choice is kept. The notice shows
  only there, not on screen (replacing the design's "a notice once per
  launch").

## My picks

- **Protocol:** an outside session is an ordinary snapshot with
  `origin: external` and `read_only: true`. The new pieces are all
  additive: a provider's own `capabilities` (`outside_sessions`) and
  `notices` in `hello`, `provider.notice`, `client.set_focus`, and
  `client.set_outside_sessions`. The setting also reaches the sidecar
  before it starts (`serve --no-outside-sessions`, read by
  `SidecarClient` from `user://settings.cfg`), so with it off no outside
  island appears even for a moment at start.
- **One shared poll** for S07's read-only sessions and S08, paced by
  focus (5 s / 10 s); `askWatched` became `poll`.
- **`findOwn` finds any entrypoint** (`findTranscript`): `findStored`
  only finds what can be listed under Resume, which misses desktop and
  IDE transcripts and ones with nothing said yet. It also reads the
  `entrypoint` that filters out `sdk-cli`.
- **A session with no transcript waits one listing**, except at start
  and just after the setting is turned on: a `claude -p` writes its
  transcript at once, so it's caught as `sdk-cli` by the second look
  instead of flashing an island.
- **A second game's sessions show read-only here:** the first game
  drives them; here they're just sessions this game didn't start.
- **A background session needs a live `pid`** (entries without one are
  dropped by `parseAgents`): one whose process has exited has nothing to
  follow by process id.
- **`waitingFor` is parsed but not shown yet**; the world shows only
  "waiting".
- **The suites never show the developer's real sessions:** the error
  watch writes a settings file of its own with the setting off and
  points `SidecarClient.settings_file` at it.

## The reviews

The security review (2026-10-22) found, all fixed:
- the sidecar's process tests started real sidecars with outside
  sessions on, so they read the developer's own running sessions: they
  now start with `--no-outside-sessions`;
- with the setting off the sidecar still ran `claude agents` once at
  start: now it doesn't when it has no session of its own to take
  back, so no Godot suite runs `claude` either (agent view off is
  found once the setting is turned on);
- nothing tested that `serve --no-outside-sessions` turns them off:
  `serveOptions` and `prepare` came out of `serve.ts` and are tested;
- the quit warning counted outside sessions and gave them `/exit`
  advice that doesn't apply: they're left out (S05);
- U+061C (Arabic letter mark) wasn't stripped from names: it is.

Noted, not changed: outside sessions' paths and start times go into
`islands.json` like any running session's (written down in S08 and the
guide); `findTranscript` is synchronous, run per not-yet-shown session
on each poll (small; revisit if it shows up in profiling). The
docs-sync check found stale text in S07's watch item, W10, W12 and
flow 16; fixed.

## The live check (2026-10-23)

- **Step 14 failed** (turned back on after a start with it off: no
  islands rose). The sidecar log: `can't look for sessions started
  outside the game: Command failed: …claude.exe agents --json`, with no
  message from `claude`. The user quit within seconds, before the next
  poll (5 s) would have asked again. Not reproduced: the same path
  against the real `claude` (a probe: started off, then turned on)
  answered in under a second and offered all three sessions as rising
  ones; `claude agents --json` took 0.8 to 1.1 s here. Now a failure
  without a message says whether it timed out or which exit code it
  gave, and the log says when it answers again, so the next live check
  tells them apart.
- **Biomes not kept** (the user's): between two runs, two outside
  islands came back as they were and the third (the desktop app's)
  with another biome. The desktop app relaunches a session's process:
  this session, started the day before, showed a process started that
  morning in `claude agents`. W12's key has the start, so the session
  looked new. Now kept under a second key too, provider and
  `native_id` (the same across a relaunch). The user asked for outside
  islands to keep "the same information as regular islands", so their
  entries also outlive the setting turned off (and a start with it off)
  until a start that shows them finds them gone; one that rises later
  gets its biome and seed back.

## Open points

- An Agent SDK program found before its transcript is written, and still
  without one at the next listing, shows as an island, and never ends
  unless Claude Code stops listing it.

## Tests

`sidecar/test/outside.test.ts` (new, 20 tests), `running.test.ts`
(the new fields, agent view off), the clusters test (`_w12_outside`: kept like the game's own), the world test (the flag, the marks on both maps, the chat
line and notice, the setting with and without the notice), the sidecar
client test (provider notices and capabilities, focus, the serve
arguments). Sidecar 327/327, every Godot suite passes. Live check
pending (`tests/live/checklist.txt`).
