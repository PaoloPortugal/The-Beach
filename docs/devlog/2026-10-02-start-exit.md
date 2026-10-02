# Starting: Claude Code closing before it's up

Features: S02, S03

Found by the user in W05's live check (2026-10-02): declining folder
trust in a new session's terminal closes Claude Code, but the game kept
waiting. Until our bridge connects (after the startup dialogs) the
sidecar hears nothing, so it only gave up after its 15-minute startup
timeout, and since one session starts at a time the sessions menu was
blocked for that long. The same happened when refusing the development
channel or closing the terminal window. Built on branch `s03-start-exit`.

## The fix

The launcher (the sidecar mode the terminal runs, which starts `claude`
and stays its parent) writes its process id to `launcher.pid` in the
session's private folder, first thing, before even reading the session
file, so a broken launch file is caught too once its message is closed.
While the session starts, the Claude provider checks every second that
the process still exists (`process.kill(pid, 0)`; only ESRCH counts as
gone). When it's gone the session ends with the usual `exited` reason, so
the protocol doesn't change and the game says "The session didn't
start." The 15-minute timeout stays for a terminal that never ran the
launcher. A reused process id would only mean falling back to it.

Alternatives I considered: an "exited" marker file written by the
launcher (misses a closed window, which kills the launcher before it can
write), or the launcher connecting back over loopback with a token (more
machinery for the same answer).

## Stop waiting (the user's choice)

I offered detection alone or detection plus a button; the user chose
both. The sessions menu shows "✕ Stop waiting for the session starting"
while a start is under way. It only frees the game's launcher: the
sidecar isn't told, so a session that comes up later is an ordinary
running session (its island appears, nobody is taken there). Ending a
starting session from the game would have needed `session.end` to work
before a session is up, which it doesn't (`session_starting`).

## Tests

`launch.test.ts`: the launcher records its id and is seen as gone after
it exits; `launcherGone` is false while it runs, before anything is
recorded, and for a damaged file. `bridge.test.ts`: a session whose
launcher exits ends long before the startup timeout. `world_test.gd`:
the menu's Stop waiting frees the launcher. `npm test`: 160 of 161 pass;
the one failure is the relay timing check that already failed before.

## Live check

Not done yet.
