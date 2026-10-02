# S05: no ending from the game; a quit warning

Features: S05, W07

## Can the game end a session?

S05 was "end a session from the world". Claude Code documents no way to
end an interactive session from outside (checked 2026-10-01): a hook's
`"continue": false` stops the turn, not the session; `SessionEnd` only
reports an exit; a channel can push messages and answer permission
prompts but can't close the session or send slash commands. So every way
left works on the process.

I offered three: `/exit` stays the only way (the game just points to
it), closing the session's terminal, or a kill. The user first chose
`/exit` only, then asked that quitting the game offer to close all
attached sessions, warning only if some are working, by closing their
terminals; then set the rule: **always the least abrupt way that doesn't
make the player close the terminal**, and later **nothing that injects
keystrokes**.

Probed on Windows with a throwaway interactive `claude` 2.1.287 and a
`SessionEnd` hook: one Ctrl+C console event (`GenerateConsoleCtrlEvent`,
delivered as a signal, not through the input buffer, unlike a Ctrl+C
keypress) ended the idle session cleanly, and the hook ran. The busy
case wasn't finished (my own tool permissions stopped the second
signal). The user asked whether Ctrl+C counts as keystrokes: no, it's
the Windows counterpart of `kill -INT`. But Node can only kill a process
on Windows, so the event needs a native helper: PowerShell compiling
`kernel32` calls (slow, and it looks like malware to antivirus) or a
small C helper (a build step for the Windows export). macOS and Linux
would send signals from the sidecar, untested.

**The user's decision:** drop ending sessions for now and keep it as a
watch item, to build if Claude Code offers a clean way (NOTES → Watch
items → Ending a session from the game). Build only a warning on quit.

## The quit warning

Quitting doesn't end sessions (they run in their own terminals; the
sidecar just goes away), so the warning says that, and how to end them.
`QuitGuard` turns off Godot's automatic quit; on the window's close
request with sessions running it shows a dialog listing them ("title ·
project · what it's doing", kept current) with Quit and Back to the
game. My choices: it shows whenever any session runs, busy or not
(the user's words were "still active sessions"), and a second close
request while it's open is ignored.

"What it's doing" is now the whole session's activity, subagents
included (`SessionStore.activity`): the user had seen sessions shown as
idle while their orchestrator waited on a subagent's report. The Running
list uses it too.

## Also found

After a restart, sessions still running from before are listed under
Resume (the new sidecar doesn't know them), and resuming one would
likely run the conversation twice. The user chose to test it first,
then decide: step 5 of the live check. **Confirmed live (2026-10-02):**
resuming it opens a fresh terminal resuming the same conversation while
the old one still runs. The user's decision: fix it with attaching to
sessions already running (Open questions → 5), recorded as a known
issue in S05.

The crash in the sessions menu's first live check, the same day, was a
Windows update of Claude desktop (see 2026-10-01-sessions-menu); since
then the game is started from a separate terminal for live checks.
