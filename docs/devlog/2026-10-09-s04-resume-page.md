# S04: Resume on its own page, and a kept listing

Features: S04, S03, W07, W05, W08, W10

## Why

While fixing a flaky world-test check (2026-10-09-world-test-waits), we
found that listing the stored sessions blocks the sidecar: `listStored`
reads the newest 200 transcripts synchronously, 0.8-0.95 s for 181 on a
dev machine. The sessions menu asked for them each time it opened, so
opening and closing it fast queued a listing per open, and chat replies,
hook relays and permission requests waited behind them.

## The user's decisions (2026-10-09)

- **Resume gets its own page.** The user's idea: "+ Add session…" asks
  whether to start a new session or resume an old one. It fits their
  future design for the sessions menu. Only the Resume page asks the
  sidecar, so opening the menu asks it nothing.
- **Esc goes back a page** (recommended, chosen): Resume → Add a
  session → Sessions → closed. Tab closes it from any page. Rejected:
  Esc closing everything with a "← Back" row; Esc back plus a Back row.
- **The Cluster and Biome selectors move to Add a session**
  (recommended, chosen); they only matter when adding. Rejected: staying
  on the first page.
- **The listing is built when Resume first opens** (recommended,
  chosen), so a sidecar's first Resume takes about a second. Rejected:
  warming the cache at start, which would stall the sidecar for that
  second just after launch, while sessions may be reconnecting.

## What was built

- `SessionsMenu` has three pages (`Page.MAIN`, `ADD`, `RESUME`) in the
  same panel. The header says which, and which keys work there. The
  search box shows on the first page (filters Running) and on Resume
  (filters the stored sessions), cleared on each page change. The
  selectors show on Add and Resume, keeping their choices between the
  two. They're reset only when the menu opens, as before. The A05 sound
  toggle stays on the first page.
- **Esc while the system's folder picker is open** first stayed the
  exception (it closed the menu, as Cancel does: the user's 2026-10-01
  way out of a picker lost behind the game). The user asked for it to go
  back a page too, if the safety net stays: Esc now stops waiting and
  shows Add a session again, like cancelling the picker; Cancel and Tab
  still close the menu and give the controls back, and the lost picker's
  late answer is ignored either way (world test checks both).
  Cancelling either picker returns to Add a session.
- The sidecar's `StoredCache` (`providers/claude/store.ts`), held by the
  Claude provider, keeps each transcript's description while its size
  and modification time stay the same. It forgets files no longer there.
  A file that couldn't be read isn't kept, so a transcript locked
  mid-write on Windows is tried again next time rather than hidden.
  Timed on the dev machine's 181 transcripts: 784 ms the first time,
  47-56 ms after (182 file stats, nothing read). The protocol is
  unchanged.
- Since opening the menu no longer lists anything, the world test's
  missing-folder wait is back to 5 s.

## Checked

- Sidecar: three new store tests, the same list with and without the
  cache (unchanged, renamed, deleted, new files), a file whose read
  failed not kept and listed on the next call, and the provider keeping
  it between calls with a change showing.
- World test: the first page offers Add session and the platform, with
  no selectors and no listing asked for. Add a session shows New and
  Resume with the selectors. Resume asks once and keeps the choices. Esc
  goes back a page each time and closes from the first page. Tab closes
  from any page. The menu opens on its first page. Waiting for the
  system's picker, Esc goes back to Add a session and Cancel closes the
  menu, and the picker's late answers are ignored. With the fake: the
  menu and Add session ask nothing, Resume lists newest first, and a
  resumed session is under Running and not under Resume.
- *Live check passed (2026-10-09)* with the user, in a real window, by
  the live checklist (its S04 steps, since removed from it): the three
  pages, Esc and Tab, Resume's listing and a rename showing, and the
  picker hidden behind the game (Esc, Cancel, a late folder).
