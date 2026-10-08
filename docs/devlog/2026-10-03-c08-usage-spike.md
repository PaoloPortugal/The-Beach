# C08 token usage: research and spike

Features: C08, S02

## Decided (user's, 2026-10-03)

- **Token usage next**, as recommended, ahead of W04.
- **Figures:** context fill, token counts, plan limits, and "the little
  hints of how many tokens a certain action is taking" (as in the Claude
  desktop app): per reply/turn, and live while working. No dollar cost.
- **Placement:** per-session figures in the chat panel's header, plan
  limits once in a corner (placeholder UI).
- **Turn hints count output tokens** (thinking included), like the
  terminal spinner's "↓ 1.2k tokens" (my recommendation). Summing input
  across a turn's API calls counts the cached history again on every
  call and gives meaningless totals; context fill covers input.
- **Live counter: the orchestrator's only** for now; subagents'
  transcripts aren't followed live yet.
- **Capability `usage`**, feature ID C08.
- **Sources: the transcript and the status line, with a narrow
  exception to "No shell strings".** After the spike (below) the user
  first chose to wait for exec form (transcript only: no context %, no
  plan limits), then, once the trade-off was explained plainly (plan
  limits matter most to a subscriber; their weekly limit stood at 94%),
  allowed the exception: "test it thoroughly and document it. If we can
  offer a more secure way in the future we do it (when claude offers
  exec)". Recorded in Security rules, C08 and Watch items. A user's own
  status line is kept; their sessions get transcript figures only.

## Where usage can come from (2026-10-03, Claude Code 2.1.289)

- **Transcript.** Every assistant entry has `message.usage`
  (`input_tokens`, `output_tokens`, `cache_read_input_tokens`,
  `cache_creation_input_tokens`, `output_tokens_details.thinking_tokens`,
  ...) and `message.model`. One API message is written as several
  entries (one per content block) that **repeat the same usage**: 5708
  multi-entry messages across this machine's transcripts, no difference
  between entries. Count each `message.id` once. Written when each API
  call finishes, so a live count moves per step, not per word.
- **`cost-state` entry** (undocumented): `totalCostUSD`, per-model
  `modelUsage`, durations, lines changed. Written near the end of a
  transcript (on exit), so not live. Not used: no cost wanted.
- **Status line input** (documented, code.claude.com/docs/en/statusline):
  `cost.total_cost_usd`, `context_window` (`used_percentage`,
  `context_window_size`, token counts, `current_usage`),
  `rate_limits.five_hour` / `seven_day` (`used_percentage`, `resets_at`;
  Pro and Max only, after the first response), `session_id`,
  `transcript_path`, `model`. Claude Code's cost figure is an estimate at
  list price and "isn't relevant for billing" for subscribers
  (docs, costs page).

## Spike: a status line through `--settings`

A recorder script (Node, writes stdin to a file) as the status line of
an interactive `claude` started in an already-trusted sandbox folder,
with no channel (so no confirmation to click).

1. **Exec form (`command` + `args`): not supported.** A summary of the
   settings reference claimed `args` runs the status line without a
   shell; the raw page says no such thing, and 2.1.289 ignores `args`:
   `/usr/bin/bash: line 1: C:/Program: No such file or directory`
   (exit 127; `--debug-file`). The command always goes to a shell: Git
   Bash on Windows when installed, else PowerShell (docs); `sh` elsewhere.
2. **Shell form works.** Short (8.3) paths with no spaces or quotes ran
   in Git Bash: 8 calls in 8 s, one after each API call (~1.5 s apart)
   plus one at start. A status line from per-session `--settings` takes
   effect (the user has none of their own).
3. **Payload for this account:** context window 1,000,000 (Sonnet 5.5),
   `used_percentage` an integer, `rate_limits` present from the first
   response (5-hour 74%, weekly 94%).
4. **Precedence:** the highest settings file that defines `statusLine`
   wins whole (settings docs), so a per-session one would replace the
   user's own; managed settings would win over ours.

Proposed and **allowed** (after first being declined, above): a status
line command built only from our own fixed paths (executable, relay
file), unquoted short paths on Windows and POSIX quoting elsewhere,
falling back to transcript-only when a path can't be made safe.
Rejected alternatives: running the user's own status line from ours
(would need their command string in a shell we start, and
re-implementing settings precedence); always replacing the user's
status line (overrides their choice).

Also learned: Windows Terminal reads `;` in its arguments as a new-tab
separator; the first spike launch had one in its prompt and opened an
error tab. The sidecar never passes text to `wt` (Security rules), so
this only affects hand-run spikes.
