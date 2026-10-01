# Answering permissions and questions in the world

Features: C05

The last M1 feature: the Godot UI for permission prompts and the
`questions` capability. The sidecar side was built with S02.

## Decisions (user, 2026-10-01)

Asked as the four questions in NOTES → C05, with my recommendations:
- *Where:* a card in the chat panel between the chat and the message box,
  covering subagents' requests (naming the agent). As recommended.
- *Permission card:* summary, Details, optional note, Allow and Deny, no
  keyboard shortcut for Allow. As recommended.
- *Questions:* **one item at a time**, not my recommendation (every item
  on one card). Follow-up: a click on a single-choice option moves on
  (not Next/Back only, which I recommended, nor a review step); "Other…"
  kept per item; **no** "Reply in your own words instead" (the free
  `response`), so the UI never sends one.
- *Several pending:* one at a time, oldest first, "1 of 3 waiting". As
  recommended.

My pick, to confirm at review: on the last item a single-choice click
only selects, and Send answers, so a misclick never reaches Claude.

## How it's built

- `SessionStore.pending()`: the store keeps `pending_order`, so requests of
  both kinds come out in arrival order. A snapshot can't say which kind
  came first; its permissions are taken as older.
- `PendingCard` (`chat/pending_card.gd`), built in code, added to
  `chat_panel.tscn` as `Layout/Pending`. It re-lays itself out only when
  the request on top changes, so typing in the note or "Other…" survives
  unrelated store signals. Notes and question progress are keyed by
  session and request, kept while the chat is closed.
- Allow, Deny and Send are `FOCUS_NONE`: a focused button would otherwise
  fire on Enter or Space.
- `dev:fake`'s question now has two items (one choice, then a
  multi-select) so the step-by-step flow can be driven.

## Checks

- `node:test` 145 pass, typecheck clean (dev:fake test answers both
  items).
- Godot headless: `session_store_test` (pending order across kinds, a
  resync keeps it), `world_test` (card by hand: order and count, Allow
  without focus, BBCode in a summary shown as written, a refused answer,
  the next request after one answered in the terminal, a subagent named,
  auto-advance, checkboxes, Back, "Other…", progress across closing the
  chat, Send; with `--sidecar-dev-fake`: a permission allowed and a
  two-item question answered on the card), `sidecar_client_test`, all
  with and without the fake.
- Screenshots of the card (permission with Details, question items 1
  and 2) from a throwaway windowed script. Found and fixed: `choose()` on
  a checkbox didn't tick it on screen (a real click did).
- The user tried it in the game with `--sidecar-dev-fake`: Godot logged
  "freed ... while a signal is being emitted" on clicking an option or
  Back (the card redrew itself inside the button's signal and freed the
  button). Fixed with `remove_child` + `queue_free`; the world test now
  clicks through the buttons' signals (Godot errors don't fail it, so
  read its output). Re-checked by the user: works.
- Not yet: the Compatibility renderer. Unticked checkboxes are faint in
  Godot's default theme.

## Live check (user, `claude` 2.1.285, 2026-10-01)

Passed, no Godot errors. Two dead ends on the way:
- The first run asked for `node --version`, `echo hello` and `date`.
  Claude Code runs read-only commands without asking, even in default
  mode, so no permission card came up; Claude then "asked" through
  AskUserQuestion, which tested the question card instead. The redo used
  `mkdir`, a Write and `rmdir`, which always ask.
- A subagent told to ask through AskUserQuestion couldn't: Claude Code
  doesn't give subagents that tool. Only their permission prompts reach
  the card (checked: a subagent's Write named it).

Checked: Details and Allow; Deny with a note on a Write, after which
Claude made the file under the name in the note (Claude Code adds to
the deny that the user's next message may hold a correction); "Yes" in
the terminal took the card away; the two-item question (option click
moving on, Back, Other…, checkboxes, Send); `/exit`. The user confirmed
my pick: on the last item a click only selects and Send answers.

## Note on Deny only (user, after the live check)

The card offered the note with Allow too. The user asked to match Claude
Code, whose prompt takes text only on No: the note and a Send button are
locked until Deny is pressed; Send denies with the note; Allow answers
at once and never sends it (a typed note is kept, locked). The user
also asked that if Claude Code ever lets a channel deny with a message,
we drop the follow-up-message workaround and use theirs (NOTES → Watch
items). The world test clicks through it (locked, Deny unlocks, Allow
locks again keeping the note, Send denies); screenshots of the three
states from a throwaway windowed script.
