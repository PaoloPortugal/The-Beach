# Sidecar core (S01)

Features: S01 (protocol: error codes and ordering rules written down; no
version change)

First M1 feature. The user chose to start M1 with the sidecar, as the
riskiest part and the one everything else depends on. Built on branch
`s01-sidecar`: the generic core and Godot's client, with no provider yet
(S02 adds Claude).

## Decisions (user's)

- **Packaging: Node's single-executable feature (SEA).** Keeps the decided
  runtime (TypeScript on Node). Rejected: Bun compile and Deno compile. Both
  cross-compile more easily, but they swap the runtime and reopen open
  question 6, and their Node compatibility is less proven for child
  processes and stdio MCP.
- **Validation: Ajv against `protocol/events.schema.json`.** The schema is
  the rule at runtime, so code and schema can't drift apart. Rejected:
  hand-written checks (zero dependencies, but they drift silently).
- **Godot layout: by domain** (`core/`, `world/`, `agents/`, `chat/`,
  `providers/<id>/`, `tests/`). Deleting a provider means deleting its
  folders. Rejected: by file type (a provider spread across folders), and
  leaving Godot out of S01.

## Conventional choices made along the way

- Dependencies: `ws` and `ajv` at runtime (6 packages in all, MIT and
  BSD-3-Clause, notices shipped); `typescript`, `esbuild`, `postject` and
  types for development. Pinned exactly, lockfile committed. `date-time` is
  checked by a small custom format instead of adding `ajv-formats`.
- Node 22.21.0 pinned (`engines`): the SEA blob must be made by the same
  Node version as the binary it goes into. Development runs TypeScript
  directly (Node 22.18+ strips types); `tsc` only type-checks.
- The handshake is one JSON line on stdout. Passing the token as a
  command-line argument was not considered: other local programs can read
  arguments.
- One client at a time; a new authenticated connection replaces the old
  one (Godot reconnecting).
- Tests with `node:test` (built in).

## Found while building

1. **Godot sends no `Origin` header** (its WebSocket client source, and
   confirmed live: a real Godot 4.7.2 connects while any `Origin` is
   refused). So the rule is simply "any Origin is a browser". Added a
   `Host` check against DNS rebinding.
2. **Godot's default inbound buffer is 64 KiB**, too small for a long reply
   or a chat history. The client raises it to 32 MiB; recorded as a watch
   item (large histories).
3. **Ordering bug caught by a test:** `session.ended` went out before the
   `ok` for `session.end`, because the provider ended the session inside
   the command. The registry now holds a session's events while any command
   for it is being answered. Overlapping commands keep holding until all
   are answered.
4. **Ajv strict mode** rejects the schema's `oneOf: [{required: …}]` in
   `question.answer` (valid JSON Schema). Only `strictRequired` is turned
   off.
5. **SEA runs CommonJS only** (Node 22 docs), so esbuild bundles to one
   `.cjs`. Code cache is off so one build machine can make executables for
   the other platforms.
6. **Windows pipe end-of-file in Godot:** after the sidecar exits,
   `FileAccess.get_line()` on its stderr pipe reports `ERR_FILE_CANT_READ`
   and never sets `eof_reached()`. The reader thread looped forever and
   Godot hung on quit. It now stops on any read error.
7. **Injecting into `node.exe` breaks its signature** ("signature seems
   corrupted"), and macOS binaries must be re-signed on a Mac. Added to the
   code-signing watch item.
8. Godot starts child processes on Windows with `CREATE_NO_WINDOW` (engine
   source), so no console window appears for the sidecar.

## Verified

- 41 `node:test` checks: security (loopback only, token near-misses,
  Origin, Host, paths, plain HTTP, message limit, token never logged),
  schema agreement (the command list matches the schema), sessions with a
  fake provider (ordering, seq, snapshots, capability and extension
  gating, dropped provider mistakes, error codes), and the process contract
  (one stdout line, exit on stdin close, exit without a pipe).
- The process tests also pass against the bundle and the packaged Windows
  executable.
- Godot headless smoke test with the source, the packaged executable, and
  the fake provider (a full chat turn streamed through Godot), including
  reconnecting after a dropped connection.
- Killing Godot outright (`taskkill /F`) ends the sidecar.

## Not tested

macOS and Linux (packaging for them is written but not run: it downloads
Node binaries, and nothing can run them here); the non-headless Godot
editor run (F5).
