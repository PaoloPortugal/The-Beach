# The sessions menu: start, resume, go to

Features: S03, S04, W07

The first feature of the "many sessions" milestone (the user's choice
after C03). S04's sidecar side (listing and resuming stored sessions) had
been built with S02 but nothing in the world used it. Built on branch
`s04-resume`.

## Decisions (the user's)

- **One menu, opened from anywhere**, for starting a session, resuming a
  stored one and going to a running one. Rejected: giving the "New
  session" post a menu (you'd have to walk back to the platform), and a
  second post for resuming.
- **Tab** opens and closes it (physical key, like the other controls).
- **Newest first with a search box**, like Claude Code's own `/resume`
  list.
- **Running sessions are listed too**, so the menu doubles as a basic
  teleport (W07). Sorting, grouping and a minimap stay open (open
  question 3).
- **The post is removed.** The platform is now just the spawn point.
- **The menu is a placeholder** and must be properly designed later
  (the user asked for this to be noted explicitly). It is in NOTES'
  "All UI is a placeholder" line, the S03, S04 and W07 sections and the
  guide.

My own choices: the post's status sign became a notice at the top centre
of the screen, and a "Press Tab for sessions" hint shows while no session
runs (nothing on screen otherwise tells a new user about Tab).

## What was built

- `world/sessions_menu/sessions_menu.gd` / `.tscn` (`SessionsMenu`, a
  `CanvasLayer`): the panel, the search box, the lists, the hint and the
  notice. It reads Tab and Esc in `_input`, not `_unhandled_input`: the
  focused search box would otherwise take Tab to move the focus, and the
  player's Esc would free the mouse first. It doesn't open while the
  player's controls are off (chatting). The folder picker is still
  Godot's own `FileDialog` (the native one hid behind the game on
  Windows, M1); cancelling it returns to the menu. The stored list is
  asked for from every provider each time the menu opens, merged and
  sorted by `updated_at`; a reply from an earlier opening is ignored.
- `world/sessions_menu/session_launcher.gd` (`SessionLauncher`): the
  post's start logic, now for `session.create` and `session.resume`, one
  at a time, with the same messages ("Starting…", the
  `confirm_in_terminal` text, "Still starting" after 120 s, refusals,
  "The session didn't start.").
- `world/platform/session_post.gd` and the post's nodes are gone;
  `world.gd` wires the menu: the launcher's `session_started` and the
  menu's `go_to` both call `teleport`.
- Fake provider (`sidecar/test/dev-fake.ts`): three stored sessions to
  resume, each coming back with a two-message chat; a running one isn't
  listed. `test/dev-fake.test.ts` covers it.
- `tests/world/world_test.gd`: the menu replaces the post (hint, Tab and
  Esc, the picker and its cancel, a refused folder); with
  `--sidecar-dev-fake` it also lists, searches and resumes a stored
  session and goes to a running one.

## Bug: no controls after choosing a folder

At the first live try, the player lost the camera for good once the
picker closed and the island appeared. Godot's picker hides itself
before it reports the folder, and the menu's panel was already hidden,
so `close()` took the menu for closed and never gave the controls back;
Tab then couldn't open the menu (it needs the controls). Fixed with the
menu's own open flag. The world test missed it because it called the
launcher directly; it now picks the folder through the picker's button.

## The system's folder picker, again

The user asked for the system's picker (File Explorer on Windows) with
all three platforms in mind, although M1 dropped it: on Windows,
alt-tab hid it behind the game, which waited for it forever. Options I
gave: a waiting note with Cancel (recommended), the same plus a button
to switch to Godot's picker, or native only as in M1. **The user chose
the waiting note with Cancel**: Cancel or Esc gives the controls back
and a late answer is ignored. Where the system has no picker, Godot's
is used.

The user also asked for a way to keep the picker from being hidden at
all. Godot's source (4.7.2 and master) explains the M1 trap: the
picker's helper window is created without an owner, so Windows doesn't
keep it above the game. GDScript can't reach that window. The "no
focus" window flag looked like a way to stop the game from coming in
front, but in Godot it also makes the window always-on-top, which would
bury the picker for good. So the note tells you where to find a hidden
picker (it has its own taskbar button). The real fix belongs in Godot.
I first suggested contributing it; before that, the user asked whether
it really is a bug. A proper search found it already reported (#104670,
"Native FileDialog isn't transient", where a maintainer describes this
exact symptom and the platform maintainer agrees to emulate blocking)
and an open fix by that maintainer (#114512, not merged yet), which
would fix our case with no change on our side. Nothing to file; we wait
for a release with it (NOTES → Watch items). The user asked
that this work on Linux and macOS too: the code is Godot's
cross-platform call with a fallback to Godot's picker, and per Godot's
source only Windows has the bug (macOS uses a sheet on the game window,
Linux's portal gets the game window as parent). Untested there.

## Live check

Passed with the user and the real `claude` (2026-10-01), every step of
`tests/live/checklist.txt`: the menu, the system's picker and its
Cancel, the picker hidden behind the game, a new session, `/exit`, the
Resume list and its search, a resume with the earlier chat and Claude
remembering it, the Running list, and jumping between two sessions.

The first attempt ended abruptly while a fourth session was coming up:
the game and Claude desktop both closed, and Claude desktop wouldn't
reopen until Windows was restarted. Not our bug. Windows' event logs
(AppXDeploymentServer, AppModel-Runtime) show that at 19:42:56 Windows
started updating the Claude desktop package (2.16120 to 2.19675) with
the option that force-closes the running app. The game had been started
with the Run button in Claude desktop's terminal, so it ran inside
Claude desktop's app container and was closed with it: Godot's log
stops with no error and no exit lines. Claude desktop couldn't reopen
while its package was being replaced (93 s). No crash report, display
driver reset or low-memory event for Godot. Since then the game is
started from a separate terminal (or F5 in the editor) for live checks.

## Open

- `npm test` in `sidecar/` has one failure that also happens without
  these changes: "relay mode: every failure still exits 0 … and quickly"
  takes about 5.6 s on this machine (a timing limit), so it isn't from
  this branch.
