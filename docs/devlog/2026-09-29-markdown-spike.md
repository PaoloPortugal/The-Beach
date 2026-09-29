# Markdown → BBCode spike

Features: C03 (also C02; protocol unchanged)

Throwaway M0 spike in `spikes/markdown/`, Godot 4.7.2 on Windows 11.
Question: can the chat panel render Claude's Markdown well, especially code
blocks, safely and fast enough to stream?

## Decisions (the user's, before building)

- **Convert in Godot, with our own GDScript.** The protocol already sends
  Markdown (`message.completed.text`), so it stays unchanged and
  provider-neutral, and there's no new dependency. Rejected: pre-parsing in
  the sidecar (changes protocol v1, adds a dependency) and a third-party
  Godot addon (another dependency whose escaping we'd have to audit).
- **Code blocks as separate panels**, not inside the RichTextLabel: a
  read-only CodeEdit with a language label, Copy button, syntax colours and
  horizontal scroll instead of wrapping.
- **Spike in `spikes/markdown/`.** The `.gdignore` moved from `spikes/` into
  `spikes/claude-cli/` so Godot sees the new spike.

## What was built

- `md_parser.gd`: Markdown → blocks (headings, paragraphs, nested bullet /
  numbered / task lists, fenced code, nested quotes, GFM tables, rules) and
  inline Markdown → BBCode (code spans, bold, italic, strikethrough, links,
  autolinks, bare URLs), with CommonMark's emphasis rules.
- `md_view.gd`: one message as a stack of controls. Consecutive prose
  blocks share one RichTextLabel (selection runs across paragraphs); code,
  quotes and rules are their own nodes. Streaming: re-parse the whole text
  after each batch, keep unchanged segments, update the growing one in
  place.
- `demo.tscn`: samples, panel width slider, simulated streaming, timings,
  and a `-- --bench` mode that prints timings without the editor attached.
- `tests.gd`: 74 headless checks (below). `bench.gd` and `list_lab.tscn`:
  measurements and a BBCode comparison, kept as evidence.

## Findings

1. **Safe by construction.** Every `[` in message text becomes `[lb]`, so
   the only tags in the output are ours; links are `[url=<index>]` into a
   table, so no URL text ever sits inside a tag. Only http(s) and mailto
   are clickable; other schemes (`javascript:`, `file:`, relative) show as
   grey text. Images are never loaded, only their alt text. A click opens
   a confirmation showing the full address; hovering shows it too. A fuzz
   test (3,000 random inputs) checks that no other tag ever appears.
2. **Streaming is cheap.** Only the growing segment is touched: 2.2 ms
   average, 6.2 ms worst per batch on the typical sample, and the streamed
   result matches a full render (tested for every sample).
3. **Full renders are not.** Parsing is fast (about 1 ms per 2.5 KB), but
   building the controls isn't: a typical 2.5 KB reply takes about 60 ms
   plus 20 ms layout; a 25 KB reply about 530 ms plus 160 ms, even without
   the debugger. Most of it is RichTextLabel laying out its text when it
   enters the tree at the real width (about 8 ms per prose segment), then
   CodeEdit (about 4 ms per block). `RichTextLabel.threaded` cut prose from
   390 to 150 ms on the long reply. Fine for one live message; loading a
   long history at once would freeze. C03 should build history lazily
   (visible messages first, or a few segments per frame), consider
   `threaded`, and try a cheaper read-only code view (a RichTextLabel in a
   horizontal scroll costs a fraction of a CodeEdit).
4. **Nested lists need nested `[ul]` tags.** `[indent]` around `[ul]` lost
   the marker and added blank lines; an empty wrapper `[ul]` added a blank
   line per nested item. What works: one `[ul bullet=...]` per item, kept
   open while its children are written. That also gives per-item markers:
   task boxes, and numbering that continues after a code block splits a
   list ("1." … code … "2.", common in Claude's step-by-step answers).
5. **CodeEdit quirks.** It swallows the mouse wheel even with nothing to
   scroll, so the chat stopped scrolling over code: plain wheel is now
   forwarded to the chat's ScrollContainer (shift+wheel still scrolls the
   code sideways). With `scroll_fit_content_height`, its horizontal
   scrollbar covered the last line: padded while the bar shows.
6. **Line breaks.** A single newline inside a paragraph is shown as a line
   break (GitHub-comment style), not joined as CommonMark does; it reads
   better in chat.
7. **An unclosed fence** (normal mid-stream) renders as a code block marked
   "writing…".

## Known gaps

Setext headings, indented (4-space) code blocks, HTML, reference links,
footnotes, table column alignment, lazy quote continuation. A changed
bullet character doesn't start a new list, and a blank line doesn't end
one (so a list "starting at 5" after a blank continues the numbering, as
in CommonMark). `__init__` outside backticks renders as bold "init"
(CommonMark does too). Syntax colouring is a small keyword list for
GDScript, Python, JS/TS/JSON and shell. Task-box markers sit slightly
right of bullets. Not tested: right-to-left text, CJK, emoji fonts,
macOS/Linux fonts (the monospace font is a SystemFont list).

## Result

Rendering Claude's Markdown in Godot works and looks right, and the
"biggest UX risk" is now a known amount of work: port the parser and view
into the real chat panel, fix the full-render cost for history, and keep
the security tests. No protocol changes needed.
