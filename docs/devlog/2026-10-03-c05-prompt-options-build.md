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

## Live check (in progress, 2026-10-03, the user, `claude` 2.1.288)

`tests/live/checklist.txt`: the fake's steps, then the spike's prompts
with the real `claude` in `garden-live`.

- **The checklist overlay** got too long for the window: it now scrolls
  with the mouse wheel (over the list, or while walking) and Page Up /
  Page Down. A first version measured lines without their spacing, so
  the end was off screen; fixed.
- **Step 10, PowerShell:** with another command (one file written
  outside the project, in Claude's scratchpad) Claude Code suggested a
  `PowerShell(<the command>)` rule in `localSettings`, a kind not seen in
  the spike, so it got the plain label. The terminal offered to allow
  that file. Picked in the world, the rule landed in
  `.claude/settings.local.json` as the button said. The user accepted
  the plain label: it works and doesn't loosen anything.
- **Step 6, Bash, no auto option:** the terminal offered "Yes, and
  switch to auto mode", the world didn't. The checklist had the user
  Shift+Tab to Manual before the first message, so the sidecar never
  saw the session in Auto, which is when C06's rule starts offering it.

### Looking for a signal that auto is available (user's pick)

Asked whether to remember auto per machine, keep the rule, or look for
a real signal first, the user chose to look. Found (docs and `claude
-p` 2.1.288 probes, 2026-10-03):

- No hook says whether auto is available. `SessionStart` and
  `InstructionsLoaded`, the hooks before the first message, carry no
  `permission_mode` (probed; the docs' examples agree).
- In a terminal on 2.1.283 or later, a session with no mode set starts
  in auto, and in Manual when auto isn't available (docs). That would be
  a signal, but nothing reports the starting mode before the first
  message.
- The transcript's `permission-mode` entries (undocumented) are first
  written with the first message, after any Shift+Tab. `~/.claude.json`
  only has undocumented feature-flag caches. Neither is usable.
- `disableAutoMode: "disable"` in a settings file is documented and
  does stop `--permission-mode auto` (the session started in `default`).
  But availability also depends on the model, provider and server, so
  the setting can only say "off".
- **A `PermissionRequest` hook's `setMode auto` is applied even when
  `disableAutoMode` is `"disable"`**, in `--settings` and in the
  project's `.claude/settings.local.json`: the next call came with
  `permission_mode: auto` and ran without a prompt. (Managed settings
  not tried.) So Claude Code won't catch a wrong offer: sending a switch
  to auto where it isn't available gets around the user's setting.

*Decided (user's, 2026-10-03):* **keep the rule**: offer the switch only
once the session was seen in Auto, the only proof we trust. The gap is
recorded in NOTES.md → Watch items → Auto availability. Rejected:
remembering auto per machine (my first recommendation, made before the
probe; I had wrongly assumed Claude Code would refuse a switch to auto
where it's off), which could switch to auto where the terminal
wouldn't.

### Draft bug report for Claude Code (for the user to file)

> **PermissionRequest hook can switch to auto mode when
> `disableAutoMode` is "disable"**
>
> Version: Claude Code 2.1.288, Windows 11.
>
> Steps: in a project, set `{"permissions": {"disableAutoMode":
> "disable"}}` in `.claude/settings.local.json` (also reproduced with
> `--settings`). Register a `PermissionRequest` command hook (matcher
> `*`) that answers `{"hookSpecificOutput": {"hookEventName":
> "PermissionRequest", "decision": {"behavior": "allow",
> "updatedInput": <tool_input>, "updatedPermissions": [{"type":
> "setMode", "mode": "auto", "destination": "session"}]}}}`. Run
> `claude -p 'Run these two Bash commands separately: npm pkg set
> description=one, then npm pkg set description=two.'`.
>
> Expected: the `setMode auto` update is refused (as
> `--permission-mode auto` is: that session starts in `default`), and
> the second command asks for permission.
>
> Seen: the second command's `PreToolUse` reports `permission_mode:
> "auto"` and it runs without a permission request. A hook can thus
> enable a mode that settings disable.
