# S02: finding claude through the login shell

Features: S02 (Architecture → Platforms → Finding `claude`)

## Where it came from

Looking into Claudian, the Obsidian plugin that embeds Claude Code
(YishenTu/claudian, 2.3.28, 2026-10-22). Its Claude provider drives
Claude Code through the Agent SDK, which runs on the user's
subscription sign-in by default. Anthropic's legal page says products
built on the Agent SDK should use API keys, so that route stays
rejected for us (Deliberate limitations → No Agent SDK). One piece of
it is unrelated to the SDK: its process code reads the PATH from the
user's login shell (`core/process/loginShellPath.ts`), because an app
started from the Dock or a menu doesn't get it.

## The gap

Our finder looked in PATH, then the installers' fixed folders. A
`claude` installed with npm under nvm, fnm, Volta, asdf or mise sits in
a folder only the shell profile adds, so a game started from the Dock,
a menu or Steam missed it, and the setting to point at it by hand
promised in Platforms was never built.

## Decided (user's, 2026-10-22)

- **Ask the login shell, last.** Only after every other place fails
  (cheaper, and most players never trigger it), never with a path set
  by hand, never on Windows (apps there get the full PATH).
- **The path set by hand comes next, on its own branch** after S08
  merges, as a capability ("program path" in `hello`, a client command,
  a serve flag, a Settings row per provider). Recorded in Known issues
  and next steps.

Rejected: guessing version managers' folders without a shell (several
Node versions side by side, and the list goes stale); only the manual
setting (players with nvm would all have to find it).

## How it's built

`findClaude` (`sidecar/src/providers/claude/find.ts`): when no
candidate works, `$SHELL` (else the account's shell; only an absolute
path) runs `-i -l -c` with a fixed script: a mark, `printenv PATH`, a
mark. `printenv` gives a colon-joined PATH in every shell, fish too; the
marks fence it off from whatever the profile prints. Interactive as
well as login because nvm's installer writes to `~/.bashrc`, which a
non-interactive shell skips (the guard at its top returns at once).

Differences from Claudian's version, on purpose:
- It runs only as a last resort, at most once per run (the answer,
  even an empty one, is kept), not at every start.
- Our clean environment, not the whole inherited one.
- Its own process group. Once both marks are in, we stop reading at
  once (a background job the profile started may keep the pipe open)
  and hang the group up, as closing a terminal does. On the 10 s
  timeout, on output over 64 KB, or if the sidecar exits first, the
  whole group is killed, so a stuck profile leaves nothing behind.
- Folders with control characters are dropped.
- The PATH is used only to look up `claude`, then checked like any
  candidate; it never reaches the sessions or anything else we start.

Security: the shell gets an argument array with constant text, so
nothing a project or session holds can reach it (Security rules → No
shell strings, now naming it). It does run the user's startup files
unseen, the same ones they run each time they open a terminal. With no
input and no controlling terminal, a question in them goes unanswered
and the shell carries on.

## Review (security-reviewer and docs-sync, 2026-10-22)

No blockers. Fixed from it: the lookup ran again on every retry of
finding `claude` while nothing was found (each launch, and the running
sessions' poll every 5 s), so it is now asked once per run; a flood
cancelled the timeout without killing the group, so it is killed now;
a group still running when the sidecar exits is killed; a successful
lookup now hangs up its group; and a test now checks that `findClaude`
gives the shell the clean environment and the home folder. Docs: Steam
and macOS not claimed as working until checked, tcsh added to the
Watch item, and the guide no longer says a profile's question makes it
give up (it goes unanswered). The npm `claude` is the native binary
(`bin/claude.exe` plus per-platform packages, 2.1.308), not a Node
script, so a version manager's `node` isn't needed to run it.

## Checks

- `sidecar/test/login-shell.test.ts`: parsing (banners, relative and
  repeated folders, control characters, an unfinished answer), choosing
  the shell, and, with fake shells (POSIX only), the whole lookup: a
  stuck profile and a flood each killed with their whole group, a
  background job hung up and not waited for, a missing or failing
  shell; and `findClaude` giving the shell the clean environment and
  the home folder, asking once per run, asking last, not at all when a
  candidate works, on Windows or with a path set by hand, and saying
  "too old" for an old one found this way.
- The POSIX tests can't run on Windows and CI is paused, so they ran on
  Linux in WSL (Arch, Node 22.21.0 from nodejs.org, checksum checked):
  14/14, plus the whole sidecar suite there. By hand there: a real bash
  with an nvm-style `~/.bashrc` behind its interactive guard found the
  fake `claude` in 98 ms.
- Not checked: macOS, zsh, fish, tcsh, and a Steam launch on Linux
  (Watch items).
