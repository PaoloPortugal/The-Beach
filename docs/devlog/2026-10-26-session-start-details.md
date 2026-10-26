# Session details: no beacon for outside sessions, a quicker bridge

Features: S08, W04, S02, S01

## Where it came from

Two details the user reported on 2026-10-26, after S02 merged:

1. An island for a session started outside the game (S08) that rises
   mid-game got W04's green new-island beacon and edge arrow. The
   player didn't ask for that session, so it isn't news.
2. After confirming in the terminal, the world kept saying "confirm"
   for a while before the island came.

## No beacon for outside sessions

`SessionIslands._place` now gives the beacon (and so the arrow, which
follows `unvisited`) only to a created session that isn't
`origin: external`. The world suite checks one rising with neither.

## The wait after the confirm

What the session waits for: it counts as up when our channel bridge
connects back (or at its first hook), and Claude Code starts the bridge
only after its startup dialogs. Godot makes the island as soon as
`session.created` arrives, so the wait is between the confirm and the
bridge connecting.

Measured on Windows, Claude Code 2.1.309:
- The game's log of the last start: "came up 15155 ms after launch",
  the user's time at the dialog included. Claude Code kept no debug log
  and the run folder is removed at the end, so nothing splits that.
- `claude -p` with a probe MCP server that logs its start and messages
  (haiku, twice in the project folder with `godot-ai` configured, once
  alone with `--strict-mcp-config`): the server starts 2.2-2.8 s after
  launch and the handshake (`server/discover`, answered "not found",
  then `initialize`) takes under 0.1 s. Another server that is slow to
  connect doesn't hold ours up.
- Our bridge took about 1 s from start to answering `initialize`:
  `main.ts` loaded the whole sidecar (TypeScript stripped at load) for
  every mode. Each mode now loads only its own code (dynamic imports;
  the bridge's table moved to `providers/bridges.ts` so it doesn't load
  the providers): 0.24 s, from source and from the bundle alike. The
  hook relay, run once per hook, gains the same.

The rest isn't known: in an interactive start, how long Claude Code
takes between the confirm and starting the bridge. The log now says
when the first status line arrives ("first status line N ms after
launch"; C08's relay, run once Claude Code draws its screen) next to
"came up N ms after launch". A live start will show the gap; what to
do about it waits for that. (First tried with SessionStart; docs-sync
caught that our hook's matcher, `^(clear|resume)$`, leaves out a
launch, so it would never have logged for a New session.)

The security review asked for two more things, both done: the relay
exits 0 even if its own code fails to load, and a test builds the
bundle and runs its relay, bridge and serve modes (`bundle.test.ts`),
so an import esbuild can't resolve fails a test instead of the shipped
executable.

## Also

NOTES S01 → Process still said `serve` takes one flag; it takes
`--program-path` too since S02.

## Tests

- `tests/world/world_test.gd`: an outside session's island rising with
  no beacon or arrow.
- `sidecar/test/bundle.test.ts`: the bundle is one file with every
  import inside it; its relay exits 0 with nothing on stdout, its
  bridge answers `initialize`, its serve prints the ready line.
