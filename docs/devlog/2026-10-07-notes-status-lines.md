# Built features' status lines match the index

Features: docs (A01, A02, A03, A04, A05, C01, C02, S03, S04, S05)

The docs-sync reviewer found (2026-10-07) that ten built features'
sections in NOTES.md → Systems still opened with `*Planned.*` (or
`*Planned (v1).*`, `*Planned (after v1).*`, ...), while the
feature index and later blocks of the same sections said they were
built. Each opening status line now matches its index row (built,
placeholder built, minimal version built, quick version built, quit
warning built), with the build date from the dev log and the section's
scope (core for all ten). The original planned intent stays as the
description, and the Decided and Built blocks are unchanged.

Then, at the user's request, the planned text that read oddly after a
"built" line was reworded, with no decision changed:
- **S04:** "whether to list the desktop app's sessions is to check when
  building S04" now says only CLI sessions are listed for now (the
  user's decision of 2026-09-29, already in the section).
- **S05:** no longer "until S05 decides how" (it decided: not from the
  game for now). Its island sinking (W04) stays: W04 was merged the same
  day, before this branch.
- **C02:** "v1 renders plain text" is now past tense, with messages
  rendered as Markdown since C03; the index row is "Chat panel and
  streaming (v1)".
- **A02:** the intent's report throw notes that the placeholder walks
  there and shrinks away with no throw yet.
- **One label per section:** the later Built blocks of A01–A05, C01, C02
  and S03–S05 repeated the new opening status; they are now headed
  "How it works." ("The quit warning." for S05, none for S03 and S04),
  and any scope note or user's quote in them moved to the opening line.
