# S02: Claude Code set by hand

Features: S02, C10, S03, Protocol (Architecture → Platforms → Finding `claude`)

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
  Provider capabilities and notices → `program_path`): the capability
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
provider found. `SettingsMenu` adds a row in Game (Providers since: below) per provider with
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
  `claude`. A path set at start is checked at once. (Replaced at the
  live check: see Looked for at start, below.)
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

## Found in the live check: a settings menu past the screen

The user found the settings menu too long to use. Measured headless:
the panel was 2016-4997 px tall on Graphics, Controls and Sound, and
right only on Game. The tabs keep the panel as tall as the tallest tab,
hidden ones included (C10, so it doesn't jump), and a hidden tab's
wrapping labels have no width, so the row's path label wrapped at every
character. S08's notice label beside it already had a minimum width.
Fixed by giving the row's two wrapping labels a minimum width (300 px);
the world test now checks the panel stays under 600 px on every tab,
with a long message and a refusal shown (it failed with heights up to
4997 px before the fix).

## Moved to a Providers tab (user's, live check)

The user asked for the program rows in a tab of their own. Settings
now has a fifth tab, Providers, with a row per provider that has the
`program_path` capability, and "Nothing to set for the AI tools in
use." while none has one. "Show sessions started outside the game"
stays in Game (my pick: it decides which islands the world shows, not
which program a provider runs). Found while checking: with that toggle
on, "Not looked for yet" doesn't show at start, because listing the
running sessions runs `claude` and so finds it; the live checklist's
first step says so. The world test opens Providers for the rows and
checks the line.

## Looked for at start, Look again, no session without a program (user's, live check)

The user asked why a session can be started when Claude Code isn't
found: the game should know before. Decided with the user (my
recommendations, approved 2026-10-26):
- **The sidecar looks at every start**, in the background, whatever
  the outside-sessions toggle says. Asked to weigh how efficient that
  is, I timed five looks on the user's machine with the sidecar's own
  code: 8-14 ms for the file checks, 95-113 ms for `claude --version`,
  about 0.1 s in all. The sidecar remembers what it found while it
  runs, so S08's 5 s poll doesn't rerun `--version`; on macOS and Linux
  the login shell can add up to 10 s once per run, in the background.
- **What's found is not saved**, only a path chosen by hand (already
  saved in `[programs]` and given at start). A saved find would go
  stale when Claude Code updates or moves and save at most 0.1 s.
- **Starting is greyed out only when no provider can start a session**
  (the user's refinement: today that's Claude alone). New and Resume
  in Add a session, with each provider's message in red and where to
  choose it.
- **Look again**, a new command `client.find_program {provider}`
  answered `ok {program}`, found or not, then `provider.program` if it
  changed. The user asked whether Browse still adds anything if the
  look always finds it; it doesn't always (an install outside the
  usual places, two installs, a failed login shell), and without it a
  failed look leaves no way out from inside the game, so it stays.

Choices made while building (told to the user):
- **Looks share**: one that comes while another runs for the same
  setting gets its answer, so the look at start, the restore and the
  first poll run `--version` once. One that has ended isn't reused, so
  a launch still finds it afresh. Look again doesn't share and asks the
  login shell again, since the player may have just installed it.
- **No look at start under a Godot suite** (`SIDECAR_TEST_SESSIONS_DIR`
  set): the real-sidecar suites would otherwise run the real `claude
  --version`, and on macOS and Linux CI the runner's login shell.
- The row says "Looking for it…" until the first answer instead of "Not
  looked for yet", and "Looking…" during Look again; with no sidecar,
  "Couldn't look: <why>".
- A new session uses the first provider that can start one; the ring's
  ➕ still opens the panel, which says why it can't.

## Security review (2026-10-26)

No blockers. Fixed: a malformed key in the settings file's
`[programs]` (hand-edited, e.g. `my-tool`) became a `--program-path`
the sidecar refuses, so it wouldn't start and the Settings row (filled
from `hello`) couldn't be reached to reset it; Godot now leaves such
keys out. Also fixed: control characters in a path (an unexpected error
instead of "That isn't a full path.") and, on Windows, network and
root-relative paths (`\\host\share\…` would be reached over the
network at each start); only a drive of this computer is taken. Added
a test that a launch after a path is set runs that path. Recorded, not
changed: the settings file is trusted as the user's own, and two
choices sent at once could end with the slower one (Godot sends one at
a time). The `.cmd` check only runs on a Windows host.

**Second pass, after the look at start and Look again.** No blockers.
Fixed:
- A path set at start was checked before the sidecar listened. A
  hanging one (a `claude.exe` on a mapped network drive gone offline:
  `--version` up to 15 s, then the restore's own look up to 8 s) could
  run past Godot's 20 s handshake, and Reset needs the sidecar, so
  only editing `settings.cfg` would get the game back. The setting now
  takes effect at once and its check runs in the background like any
  look; the restore shares it.
- An older look could report after Look again: the look at start still
  waiting on the login shell, the player installs Claude Code and
  presses Look again, it's found, then the older look says not found
  and greys out Add a session. Look again now counts as a change, so
  older looks don't report.
- Tests for two claims that had none: `serve` turns off the look at
  start only under a suite (`serveDefaults`), and the login shell is
  asked again only on Look again (the provider takes the "forget" as an
  option in tests).
- Any error looking at a path (no access, say), not only "none",
  reads as "There's no program at that path." instead of a generic
  failure that left the row stale.
- Godot leaves out a `[programs]` path with a quote or a control
  character (hand-edited), which Windows' command line could split
  into another argument and so stop the sidecar from starting.

Recorded, not changed: a mapped network drive or a `subst` drive
passes the "drive of this computer" check (it needs a Windows API to
tell; the player's own choice, and it can no longer hold up the
start). `provider.program` waits while any command is answered, not
only the program ones, so a program found during a long
`session.create` shows a little later; harmless.

## Tests

- `sidecar/test/program-path.test.ts`: each check and its message, a
  `.cmd` never run on Windows; the path set by hand the only one tried,
  the login shell not asked; the command answered then
  `provider.program`; refusals keeping the setting; `not_supported`
  and `unknown_provider`; `program` in a later `hello`; a deleted path
  failing a launch with why and reported not found; Reset; the same
  answer not sent twice; a stale look not reported; the serve flags
  (parsing, applied before the restore, a failing path kept, unknown
  providers ignored); the look at start (in the background, none under
  a suite, `serveDefaults`, none twice with a path set, a hanging path
  set at start not holding it up); Look again outranking an older look;
  the login shell asked again only on Look again; looks shared, a fresh one not;
  `client.find_program` (not found then found, the same answer not
  sent again, a path set by hand checked again when gone and back,
  `not_supported`, `unknown_provider`, `invalid_message`).
  `outside.test.ts` and `conversations.test.ts` follow the new
  capability and event.
- `tests/core/sidecar_client_test.gd`: the start arguments, sorted and
  after `--no-outside-sessions`, a path with a quote or a control
  character left out; `provider.program` kept and announced;
  a refusal from the real sidecar ("That isn't a full path.") not
  kept or saved; accepted, saved with the other settings kept; cleared
  as `null` and removed from the file; no sidecar; `find_program` sent
  and its answer kept, which providers can start a session, the real
  sidecar refusing `client.find_program` for an unknown provider (the
  fake one: `not_supported`).
- `tests/world/world_test.gd` (`_settings`): through a stand-in
  sidecar, in the Providers tab: no row without the capability (the
  "Nothing to set" line instead), a row by the provider's
  name, still looking, Look again there, found, set by hand with Reset
  enabled, not found in red, a refusal and Look again with no sidecar,
  the row gone with its provider; with the real sidecar, its Claude
  Code row, "Checking…", and the refusal of a path that isn't a full
  one; with the fake provider, no row. And (W07's part) Add a session
  greyed out with why, set by hand or not, and back once found.
- Live check: `tests/live/checklist.txt` (the user's): passed with the
  user, 2026-10-26, on Windows (the real claude.exe moved away and back
  for part D). Merged to `main` the same day.

## Later fix: the PATH test on Linux and macOS (2026-10-27)

"A path set by hand is the only one tried" failed outside Windows: its
fake `claude` was written with mode 0644, and the PATH lookup
(`findOnPath` → `isProgram`) wants an exec bit there, as intended. It
passed on the user's Windows machine, and CI had been paused since. The
test now marks the fake `chmod 0o755`, and first checks (outside
Windows) that `findOnPath` skips it while it isn't executable, so the
exec-bit check is tested, not only worked around. The code is unchanged.
Found in a cloud session on Linux; security review: no findings.
