# C02: a long chat no longer jitters while it's laid out

Features: C02 (Full panel), C03 (History is built lazily)

## The bug

Opening the chat of a session with a long history, the view shook for a
few seconds: it jumped up and back down while the older messages filled
in above the newest ones. Scrolled up, what you were reading slid about
the same way.

## The cause

Since the lazy history (C03), `_build_rest` builds the older messages a
few per frame, each batch above the rest, and then put the scroll back:
it noted the distance from the end, waited a frame, built a batch,
waited another frame, then set `scroll_vertical`. The container grew in
the frame the batch was built and the frame was drawn with the view
pushed off the end; it came back one frame later. And a row's height
isn't final when it's added: its `RichTextLabel` wraps its text over the
next frames, so the range kept growing after the correction, and after
the last batch nothing corrected it at all.

## The fix

`chat/chat_panel.gd` keeps the place in the same frame the range
changes. While a chat is laid out, `_keep` (`NONE`, `END`, `FROM_END`)
says what to keep; the vertical scroll bar's `changed` signal, which
fires when its range changes, before the frame is drawn, calls
`_keep_place`, which puts the view back at the end or at the noted
distance from it. The bar's `value_changed`, when it's not from
`_keep_place` (a `_keeping` flag), means you scrolled: `_note_place`
switches to `END` if you're at the end, else to `FROM_END` with the new
distance. `_rebuild` sets `END`; `_build_rest` builds the rest, then
waits `SETTLE_FRAMES` (4) more frames for the wrapped text to settle
before going back to `NONE`. A new layout or `_clear` stops it.

## Tests

Two new per-frame checks in `tests/world/world_test.gd`, after "then
all of it, in order": the view at the end in every frame while a long
chat is built (frames off the end: **89 with the old code, 0 now**),
and, scrolled up 300 px while it's built, the same distance from the
end in every frame and after it settles. The world suite passes.
