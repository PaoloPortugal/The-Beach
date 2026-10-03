# C05 reopened: the terminal's other prompt options, built

Features: C05, C06, S02

The decisions, the `claude -p` probe and the live pairing with the
terminal are in
[2026-10-03-c05-prompt-options-spike](2026-10-03-c05-prompt-options-spike.md)
(all approved by the user). This entry is the build on branch
`c05-prompt-options`.

## What changed

- **Protocol** (core scope): a permission's optional `options`
  (`[{option, label}]`, the provider's order) and `permission.respond`'s
  optional `option` (allow only) replace C06's `modes` and `mode` on
  permissions. Plans keep their `modes`. The protocol stays version 1:
  Godot and the sidecar ship together, so nothing outside them reads it
  yet (NOTES.md → Protocol).
- **Sidecar.** `prompt-options.ts` turns a `PermissionRequest`'s
  `permission_suggestions` into options: one `suggested` option for all
  the offerable entries, then `auto` (C06's switch) on Bash prompts in
  Manual or Accept edits once auto was seen. It drops anything that could
  allow more than the terminal (deny/ask/replace/remove rules, every mode
  but Accept edits on a file edit outside `.claude`, unknown
  destinations) and labels the rest in the terminal's words where the
  live check showed the same effect, else with a plain description.
  `PermissionRequest` is now registered for every tool (matcher `*`);
  a prompt's hook is held only while it has options, and answered at once
  with no decision otherwise.
- **The relay waits for the hook.** The options arrive on the
  `PermissionRequest` hook a few ms after the channel's relay, so a
  relayed prompt now waits for both its call's `PreToolUse` and that hook
  (either order) before it's shown. After `PERMISSION_MATCH_MS` it's
  shown with what's known; that was 300 ms for `PreToolUse` alone and is
  now 1000 ms (S02 → Permissions has why). A hook that comes after the
  prompt was shown without options is answered at once and the prompt
  keeps none, so the world never shows choices it can't honour. A stop
  flushes and declines waiting relays.
- **Answering.** An option answers the held hook with `allow`, the input
  echoed as `updatedInput`, and the option's entries as
  `updatedPermissions`, exactly as Claude Code suggested them: Claude Code
  writes the rule or switches the mode itself. Without a held hook the
  answer is refused ("This prompt can't be answered that way right now.
  Answer Yes or No, or answer in the terminal.").
- **Godot.** The C05 card's permission part is a vertical list, like the
  terminal: "Yes", each option, "No" (No toggles the note and Send, as
  Deny did). `PermissionModes.allow_choice` went with C06's button.
- **Fake and try-claude.** The fake's `permission` offers "Yes, and
  don't ask again for: npm install" and, in Manual or Accept edits, the
  switch to auto. `try:claude`'s `/switch` became `/option [id] <option>`.

## Picked by me, for review

- **Option ids `suggested` and `auto`.** One id for the suggestions,
  since the terminal shows one line for them all.
- **The generic labels' wording** for kinds not seen live, e.g. "Yes,
  and always allow mcp__x__y (saved in this project's
  .claude/settings.local.json)". A stopgap (user's): NOTES.md → Watch
  items → Prompt options not seen live lists what to check.
- **The 1000 ms wait.** Long enough for a slow hook; a hook that never
  comes (blocked by `allowedHttpHookUrls`) only delays the card by that.
- **Long labels aren't clipped:** a long Bash rule shows in full on a
  wrapping button, since the label is what will be saved.
- **Full-width list rows** for Yes, the options and No, while plan
  choices (C07) keep their shrink-to-text buttons.

## Tests

`prompt-options.test.ts` (every live-table row, what's dropped, the
generic labels) and updates to the permissions (both arrival orders, a
missing hook, a stop while waiting, the same agent's call only),
modes-plans, protocol, hooks, transcript and dev-fake suites: 206
sidecar tests, typecheck clean. Godot: `world_test.gd` and
`session_store_test.gd` cover the card's list, Yes/option/No commands
and the note, with and without the fake.

Seen while testing, not from this branch: `world_test.gd` without the
fake failed once in six runs ("the panel shows the chat so far"), and
`main`'s last CI run failed it on macOS ("Esc closes the chat"). Flagged
as its own task.

## Live check

Not yet: `tests/live/checklist.txt` has the fake's steps and, with the
real `claude`, the spike's prompts in `garden-live`, picking options
from the world and checking `.claude/settings.local.json`.
