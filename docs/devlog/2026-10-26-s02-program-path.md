# S02: Claude Code set by hand

Features: S02, C10, Protocol (Architecture → Platforms → Finding `claude`)

## Where it came from

Platforms promised a setting to point at `claude` by hand from the
start, for an install the lookup misses (a folder only the shell
adds, a custom location) or to pick one of several. The login-shell
lookup (dev log 2026-10-22-login-shell-path) covered most of the
misses; the user decided then that the setting comes next, on its own
branch once S08 had merged, since both touch `main.ts`, `serve.ts`,
`sidecar_client.gd` and the settings menu.

## Decided

- *User's, 2026-10-22:* scope **capability**, a generic "program path"
  rather than a Claude-only setting: `hello` says what each provider
  found, a client command sets or clears a path the sidecar checks, a
  serve flag applies it at start, and Settings has a row per provider
  by its own name with Browse and Reset. A path set by hand skips every
  other lookup, the login shell included.
- *User's approval of the protocol, 2026-10-26* (NOTES.md → Protocol →
  Provider capabilities → `program_path`): the capability
  `program_path {program}`, `program` on the provider's `hello` entry,
  the event `provider.program`, the command `client.set_program_path
  {provider, path | null}` answered `ok {program}`, and the error code
  `invalid_program`.
- Part of the approved protocol: **the path set by hand is the only one
  used.** When it stops working the game says why and uses no other
  `claude`: the user chose this one, and quietly running a different
  one would be a silent action on their behalf (Principles).
- *User's, 2026-10-26:* Claude Code installed **inside WSL** stays out
  of this branch, recorded in Known issues and next steps as a platform
  of its own (paths, hooks over WSL2's network, transcripts in the
  distro, each crossing its own review).

## How it's built

**Sidecar.** `checkClaudePath` (`find.ts`) runs the checks in order,
each with a message for the player: a full path, a file, on Windows an
`.exe` (npm's `claude.cmd` needs a shell, so it is never run), then
`--version` with an argument array and the clean environment,
answering as Claude Code at the minimum version or newer. `findClaude`
with an override tries only it and wraps a failure as "The Claude Code
set in Settings doesn't work: <why> Choose it again, or reset it."

`ClaudeProvider` keeps the path set by hand, declares `program_path
{program: 'claude'}`, and reports each look through `watchProgram`
(the registry turns it into `provider.program`, the same answer only
once, and keeps the latest for `hello`). `setProgramPath` checks a new
path before taking it (refused: `invalid_program`, the old one
stays); `null` clears it and looks as usual at once. A counter
(`programRun`) stops a look begun before a change from reporting the
old setting's answer.

`serve --program-path <provider>=<path>` (once per provider) is
applied before the restore, so a session taken back uses it. At start
a path that fails is kept and reported not found; the start goes on.

**Godot.** `SidecarClient.program_paths` comes from the settings
file's `[programs]` section and goes into `serve --program-path` (in a
fixed order). `set_program_path` sends the command and saves only on
`ok` (the file's other sections kept); `provider_program` reads what a
provider found. `SettingsMenu` adds a row in Game per provider with
the capability: the status text, Browse… (the system's native picker,
`*.exe` only on Windows, starting in the found program's folder),
Reset (greyed out unless set by hand), "Checking…" while the sidecar
answers, and a refusal in red, "Not changed: <why>".

## Choices made while building (told to the user)

- **When it looks.** With no path set, `claude` is looked for at
  start only when the sidecar asks it something then anyway (outside
  sessions on, sessions to take back); otherwise at the first session
  start. So the row can say "Not looked for yet", and the Godot suites
  (outside sessions off, their own sessions folder) never run the real
  `claude`. A path set at start is checked at once.
- **Unknown providers in `--program-path` are ignored** (warned in the
  log), not refused: refusing would stop the sidecar from starting over
  an old setting, for example after a provider is removed.
- **Every command's provider messages follow its reply.** The registry
  holds `provider.program` while any command runs, not only
  `client.set_program_path`, so a launch that finds the program
  missing answers first and the event follows, like the session events
  already did.
- **Reset to defaults** in Settings leaves a program set by hand alone:
  it is saved by `SidecarClient`, not `Settings`, and has its own
  Reset.

## Tests

- `sidecar/test/program-path.test.ts`: each check and its message, a
  `.cmd` never run on Windows; the path set by hand the only one tried,
  the login shell not asked; the command answered then
  `provider.program`; refusals keeping the setting; `not_supported`
  and `unknown_provider`; `program` in a later `hello`; a deleted path
  failing a launch with why and reported not found; Reset; the same
  answer not sent twice; a stale look not reported; the serve flags
  (parsing, applied before the restore, a failing path kept, unknown
  providers ignored). `outside.test.ts` and `conversations.test.ts`
  follow the new capability and event.
- `tests/core/sidecar_client_test.gd`: the start arguments, sorted and
  after `--no-outside-sessions`; `provider.program` kept and announced;
  a refusal from the real sidecar ("That isn't a full path.") not
  kept or saved; accepted, saved with the other settings kept; cleared
  as `null` and removed from the file; no sidecar.
- `tests/world/world_test.gd` (`_settings`): through a stand-in
  sidecar, no row without the capability, a row by the provider's
  name, not looked for yet, found, set by hand with Reset enabled, not
  found in red, a refusal with no sidecar, the row gone with its
  provider; with the real sidecar, its Claude Code row, "Checking…",
  and the refusal of a path that isn't a full one; with the fake
  provider, no row.
- Live check: `tests/live/checklist.txt` (the user's).
