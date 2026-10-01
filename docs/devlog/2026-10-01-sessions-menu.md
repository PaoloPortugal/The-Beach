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

## Open

- Not yet live-checked with the real `claude`: a resume from the world
  has never run live (only `claude -p --resume`, S04).
- `npm test` in `sidecar/` has one failure that also happens without
  these changes: "relay mode: every failure still exits 0 … and quickly"
  takes about 5.6 s on this machine (a timing limit), so it isn't from
  this branch.
