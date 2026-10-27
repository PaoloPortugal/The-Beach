# C16: multi-language support, designed

Features: C16, C10, D01, S01, C05, C06, C07, C09, A05

The user's ask (2026-10-27): "we're adding on more and more text the
user sees (species names, information, alongside everything we already
have in ui) and we need a way to make the translation possible and
scalable." Designed with the user; nothing is built and no string is
converted. The agreed design is in NOTES → C16.

## The survey

- Our text comes from Labels and Buttons set in code or `.tscn`
  (menus, settings, the sessions menu, the chat panel's chrome),
  text drawn with `draw_string` (crosshair, hotbar, sessions ring,
  big map, D01's fishing HUD), data tables (biome names, D01's
  species) and the sidecar's notices and errors (a `code` plus an
  English `message`; Godot already shows its own text for known codes).
- Not ours: chat content, tool names and inputs, session titles,
  project names, paths, model and product names.
- Two things found that shape the design. **No control sets
  `auto_translate_mode`:** once any translation is loaded, every Label
  whose text matches a key is translated, chat content included, so
  content controls must turn it off (and a test checks it). **English
  grammar written into code:** D01's catch card (on branch
  `d01-fishing`) picks "a/an" in code, A05's count picks its plural
  with `if n == 1`, and `_ago` fixes English word order ("%d min
  ago"); none of them translates.

## Offered and chosen

All my recommendations were taken; the user added one note.

- **gettext PO** over CSV. Godot 4.6+ CSV has plurals and contexts
  too, so the choice was about workflow: a file per language merges in
  git and works with Poedit and Weblate, which suits an open-source
  game with community translators.
- **English text as keys**, with contexts, over stable ids: readable
  code, English as the free fallback, tests unchanged; the cost is
  fuzzy translations after an English edit, which is the right
  behaviour anyway.
- **Groundwork now, first language near release:** all UI is still a
  placeholder (user's, 2026-10-01), so translating it now would go
  stale.
- **Translators (the user's note):** AI-assisted translations are
  allowed, but each is reviewed by a human before it ships. My
  suggestion had been human translators with AI only as unshipped
  drafts.
- **Automatic (system language) by default,** a Language row in C10.
- **Noto Sans (OFL)** with per-script fallbacks once a non-Latin
  language comes; the OFL needed the user's OK (Platforms → Fonts).
- **No right-to-left in the first wave:** the drawn HUDs would need
  mirroring by hand.
- **The sidecar stays English;** Godot translates by code. Rejected:
  sending the locale to the sidecar, two translation systems.
- **Permission choices translated by option id,** the AI tool's own
  parts verbatim. Rejected: English to match the terminal exactly.
- **Debug commands stay English.**
- **Mods:** only the outline (their own PO files, checked as
  untrusted text), since mod support is undesigned.

## Checked

Godot's docs read raw from godot-docs master and the engine's class
reference: internationalizing games, localization with spreadsheets
and gettext, pseudolocalization, fonts; `FontFile.allow_system_fallback`
(default on), `Node.auto_translate_mode`, the template generator's
patterns (`tr()`, `text =` assignments, `NO_TRANSLATE` and
`TRANSLATORS:` comments). Not yet checked on 4.7.2 itself: whether
template generation runs headless, and loading a `.po` from outside
`res://` at runtime.
