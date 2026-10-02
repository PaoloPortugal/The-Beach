# Sessions as tabs in one terminal window

Features: S02, S03 (Architecture → Terminal windows)

## The request

After the S03 start-exit live check the user asked that sessions not
each open their own terminal window, but be tabs in Windows Terminal.

## Decisions (user's, 2026-10-02)

- Which window: **one window of the sessions' own** (my
  recommendation), not the user's most recent Windows Terminal window
  (fewer windows, but sessions would mix with the user's own tabs, e.g.
  the one the game was started from).
- Other systems: tabs where the terminal has a clean way to open one,
  else a window each.

## What changed

The launcher already ran `wt -w new new-tab …`: `-w new` forced a new
window every time. It now names the window: `wt -w agent-sessions
new-tab …` (`WT_WINDOW` in `launch/terminal.ts`). wt opens a window by
that name the first time and adds tabs to it afterwards; closed, the
next session opens it again. Nothing else changes: each tab still runs
our launcher with only a session file's path, and the launcher's
`launcher.pid` check (S03 start-exit) doesn't depend on the window. The
classic-console fallback has no tabs.

## macOS and Linux

Not changed. Looking at what each terminal offers, "one window of their
own" is only clean on Windows Terminal: Terminal.app would need faked
keystrokes (ruled out), iTerm2 and kitty/WezTerm need the sidecar to
remember which window is the sessions', and GNOME Terminal, Konsole and
xfce4-terminal add tabs to the window last used. None of it can be
tested here, so it's Open question 9, with a window each meanwhile.

## Tests

`launch.test.ts` checks the wt arguments. `npm test`: all pass but the
relay timing check that already flakes.

## Live check

To do.
