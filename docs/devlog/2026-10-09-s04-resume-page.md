# S04: Resume on its own page, and a kept listing

Features: S04, S03, W07, W05, W10

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
- **Kept, deliberately:** while the system's folder picker is open, Esc
  still closes the menu and gives the controls back, as Cancel does. It's
  the user's 2026-10-01 way out of a picker lost behind the game, so it
  stays the exception to Esc going back. Cancelling either picker returns
  to Add a session.
- The sidecar's `StoredCache` (`providers/claude/store.ts`), held by the
  Claude provider, keeps each transcript's description while its size
  and modification time stay the same. It forgets files no longer there.
  A file that couldn't be read isn't kept, so a transcript locked
  mid-write on Windows is tried again next time rather than hidden.
  Timed on the dev machine's 181 transcripts: 784 ms the first time,
  47-56 ms after (182 file stats, nothing read). The protocol is
  unchanged.
- Since the menu's opens no longer list anything, the world test's
  missing-folder wait is back to 5 s.

## Checked

- Sidecar: two new store tests, the same list with and without the
  cache (unchanged, renamed, deleted, new files), and the provider
  keeping it between calls with a change showing.
- World test: the first page offers Add session and the platform, with
  no selectors and no listing asked for. Add a session shows New and
  Resume with the selectors. Resume asks once and keeps the choices. Esc
  goes back a page each time and closes from the first page. Tab closes
  from any page. The menu opens on its first page. With the fake: the
  menu and Add session ask nothing, Resume lists newest first, and a
  resumed session is under Running and not under Resume.
- Not yet: a live look at the pages in a real window (headless only).
