# C12: model, effort and mode at launch

Features: C12, C06, S02, S03, S04

Until now a session started from the world ran with Claude Code's own
model, effort level and permission mode, and the only way to change
them was in the terminal (`/model`, Shift+Tab). C06 had decided "no
launch picker" on purpose (2026-10-02).

## The design (user's, 2026-10-12)

The user reversed that: the game should be able to set them, since
Claude Code offers no other way from outside. Decided:
- **Three selectors**, Model, Effort and Mode, on the create panel and
  the Resume page, under Biome.
- **Model:** Default or Opus, Sonnet, Haiku, Fable, as Claude Code's
  aliases (`--model opus`), so always the newest of each.
- **Effort:** Default or Low to Max (`--effort`). No ultracode for now.
- **Mode:** Default or the Shift+Tab four (`--permission-mode`). Never
  Bypass or Don't ask, as C06.
- **Each at Default every time** the panel opens: Default passes no
  flag, so Claude Code's own choice stays the norm.
- **The chat header shows model and effort** beside the mode.
- **Scope: capability** (`launch_options`, `launch`, `model_info`).

## How it's built

The provider announces its lists in `hello` (`launch_options`), so
Godot builds the rows from data and a provider without them shows none.
The sidecar checks every id against the provider's list before
launching (`invalid_message`): the lists are the allowlist, so Godot
can't ask for `bypassPermissions` or an arbitrary `--model` string
even if it tried. The flags go after our own, as separate arguments
(no shell). Each pick resets to Default on open; a stored session of
another provider resumes with Default throughout.

For the header, a new session capability `model_info`: `model` and
`effort`, each a `{id, label}` choice, null until known, changed by
`session.updated`. The sidecar turns Claude's ids into the user's words
("Opus 5.5", "Haiku 4.5", "(1M context)").

## Where the model comes from (probes, 2026-10-13)

The decision said the model would come from the transcript and the
`PostModelSwitch` hook. Probing `claude -p` 2.1.296 (with Haiku; never
Fable, no access):
- `--model` at launch fires no `PostModelSwitch`, and `SessionStart`
  had no `model` in `-p`.
- A resume without `--model` fires `PostModelSwitch` with source
  `resume`, restoring the conversation's model; with `--model`, none.
- `effort.level` shows on `Stop` (and every hook).
- `--model haiku --permission-mode plan` answered with
  `claude-sonnet-5-5` and no `PostModelSwitch`: Claude Code's
  documented plan-mode upgrade. A transcript reply's model is what
  answered that turn, not the session's model.

So the transcript was dropped as a source (my call, to confirm with the
user): the model comes from `SessionStart`'s `model`, the status line's
`model.id` and `PostModelSwitch`, as the terminal shows it; the effort
from the orchestrator's hooks' `effort.level` and the status line.
Known limit: with the user's own status line, a new session's model may
stay unknown until it changes; the header then shows the effort alone.

## Tests

`sidecar/test/launch-options.test.ts`: the lists (no Bypass, Don't ask
or ultracode), the flags (none for Default) on create and resume,
refusals, the model and effort from each source, the registry dropping
them without `model_info`, the schema. The world test: the selectors on
both pages and their reset, the `launch` sent or left out, the header's
words, and the fake provider's "Opus 5.5 · High effort" live.
