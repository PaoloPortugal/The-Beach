# C16: the groundwork and the menus

Features: C16, C10, C13, C14, C17, S01, S03, S04, S05, W10

Steps 1 and 2 of C16's migration order (NOTES → C16): the language
setting, content kept out of translation, the template and its tests,
and the menus' text made translatable. Built over two sessions
(2026-10-28 and 2026-10-29). No real language ships yet: that waits
until the UI stops being a placeholder (the 2026-10-27 design).

## Decided (user's, 2026-10-28)

1. **Scope:** this branch is the groundwork and the menus. The drawn
   HUDs, the chat panel's chrome, D01 and the later steps come on
   their own branches.
2. **The template comes from our own extractor**, and a test fails
   while it's out of date. Godot 4.7.2 can't write a POT headless: its
   template generator is the editor's, and
   `GDScriptEditorTranslationParserPlugin` isn't exposed to scripts
   (checked). The 2026-10-27 design had left this open ("through
   Godot's template generation if 4.7 runs it headless, else a small
   extractor in the tests").
3. **Marking with `# TRANSLATE` comments:** every string on a marked
   line, `# TRANSLATE: ctx` for a context; strings that look like keys
   (no uppercase letter, no space, nothing outside ASCII) left out. The
   user picked this after asking for the trade-offs against `tr()` at
   every place the text is used.
4. **No `en.po`:** the template is the English base.

## My picks (said so in NOTES)

- File-only references in the template (`#: world/x.gd`, no line
  numbers), so moving code doesn't churn it.
- A language's own name for the Language row: its PO entry msgctxt
  "language", msgid "This language's name, in this language", else
  Godot's English name for it.
- `Languages.fill` (one pass over `{name}`s) instead of
  `String.format`, so a session title holding "{n}" stays as it is.
- Biome names under the context "biome", session states under
  "session state".
- The opening's text included with the menus; Godot's licences in the
  credits stay English (legal text).
- Text without a letter ("…", "30", "{reason}") is never in the
  template: there's nothing to translate.
- FXAA and SMAA are in the template too (marked): they show on a
  selector's face, and a language may write them its own way.

## How it went

- The first session built `Languages`, the setting, the Language row,
  the menus' text through `tr()`/`tr_n()` and the content marks, and
  stopped before anything ran (commit 0ba5911).
- The extractor (`tests/locale/pot.gd`) is a small GDScript tokenizer:
  enough to tell strings (escapes, `r"…"`, `"""…"""`, `&"…"`; `^"…"`
  node paths left out) from comments, `=` from `==` and `:=`, and a
  call's arguments. It also parses and checks PO files and renders the
  made-up language `zz`, every entry `⟦English⟧`.
- One line had to change for it: the credits' licence toggle indexed
  `_buttons["Godot licences"]` on its marked line, which would have put
  the dictionary key in the template.
- A `.po` loads from `user://` at runtime on 4.7.2 (the made-up
  language does, through `ResourceLoader`): the design's open question
  for mods, answered.
- The world test's walk passed at once, so it got a check of its own:
  a Label the template lacks is found, a content one isn't.

## Found on the way

- `godot --headless --import` didn't exit this session after finishing:
  the godot-ai editor plugin, with its MCP server running, seems to
  keep the editor up. Stopping it by hand after "Editor layout ready"
  was enough; the import had finished.
- A SceneTree script that fails to compile (a warning treated as an
  error, in `pot.gd`) leaves headless Godot running forever, and
  `write_pot.gd` without the error watch would start its sidecar on the
  user's own sessions folder (it showed one of theirs read-only before
  it was stopped). `write_pot.gd` now installs `tests/error_watch.gd`
  like the suites.

## Tests

`tests/locale/locale_test.gd` (new suite, in NOTES → Running it and
CI) and the world test's `_languages`; NOTES → C16 lists what each
checks. What they can't: how the menus look in a longer language
(pseudolocalization, by eye, later) and the real fonts for other
scripts (step 7).
