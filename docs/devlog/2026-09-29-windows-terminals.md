# Windows terminals and S02 checkpoint 1

Features: S02

S02's first checkpoint (the terminal launcher opening a real `claude`)
failed at first: `claude` came up, then exited 0.2 s later. Two bugs in the
generic terminal launcher, both Windows-only and invisible to the unit
tests, which fake the terminals.

## Windows Terminal was never found

The Microsoft Store installs `wt.exe` as an *app execution alias* in
`%LOCALAPPDATA%\Microsoft\WindowsApps`. Node's `fs.stat` fails on those
with EACCES (and `existsSync` says false), so both the PATH search and the
known-location check missed it and the launcher fell back to the classic
console. `lstat` does see the alias (as a symbolic link) and starting it
works. Fix: on Windows, a file that `stat` refuses with EACCES but
`lstat` reports as a link counts as a program. A Windows-only test checks
the real alias when Windows Terminal is installed.

## The console fallback had no console

The fallback started the launcher itself, detached, so Windows gave it a
new console window. But the sidecar spawns with ignored stdio, so the
launcher's stdin and stdout were NUL, not that window, and `claude`
inherited them. Without a terminal `claude` isn't interactive: it
connected its MCP servers (so our bridge said "ready") and exited.
Reopening the console from inside the launcher (`\\.\CONIN$`) failed with
EBADF. Fix: start the launcher through `%SystemRoot%\System32\conhost.exe
-- <argv>`, which gives it a real console; its child then sees TTYs.

Both paths were checked for real (no fakes): the actual `openTerminal`
and launcher, a folder name with a space, and arguments with a space, `"`,
`;` and `%PATH%`. The program had a TTY and got every argument intact.

Considered and left out: making the launcher refuse to start a program
without a TTY. The launcher tests run it with ignored stdio, so it would
need a test-only switch, and a session without a terminal already ends
cleanly (`session.ended`).

## Checkpoint 1 results

Claude Code 2.1.284 on Windows 11, in an empty folder, run twice:
- Prompts: folder trust, then the development-channel confirmation. On
  the second launch in the same folder, only the confirmation: it appears
  at every launch.
- The bridge starts only after the dialogs; the session came up when the
  user answered (8 s after launch with prompt answers).
- A world message arrived as `<channel source="world-bridge"
  sender="user">` and Claude replied within a second.
- `/exit` closed the bridge and the sidecar sent `session.ended`
  (`exited`).
- The transcript was written under `~/.claude/projects/` with the session
  ID we passed, so the launched `claude` didn't inherit this session's
  markers.
