# When transcripts are off

Features: S02, S04 (docs)

The user pointed out that some people keep Claude Code's transcript
saving off, while some of our features depend on transcripts, and asked
for the user to decide and for what breaks to be written down.

## What Claude Code offers (docs, checked 2026-09-29)

- `CLAUDE_CODE_SKIP_PROMPT_HISTORY` (environment variable, or `env` in
  settings) skips writing transcripts and prompt history in any mode.
- `--no-session-persistence` does the same but only with `-p`
  (non-interactive), so it doesn't apply to our sessions.
- `cleanupPeriodDays` only sets how long transcripts are kept: default 30
  days, minimum 1; `0` is a validation error.

## What depends on transcripts

The live fallback for Esc and a terminal "No" (no hook fires for either),
chat history for `session.get_history`, listing and resuming stored
sessions (S04), history when attaching to outside sessions later, and
probably future token-usage capabilities. Chat, streaming, tool calls,
subagents, permissions and questions answered in the world, and stopping
from the world all run on hooks and the bridge and keep working.

## Decision (user's)

Claude Code's own setting is the only control. Rejected: an app setting
("Use my Claude Code setting" / "Don't save for sessions started here",
applied per session through the environment), with or without a
per-session toggle at creation. The app detects a session without a
transcript and shows what's limited; it never forces saving back on and
never writes its own copy of the conversation to disk (added to Private
by default).

## Bug found in passing

The S02 spike built its clean environment by dropping every variable
starting with `CLAUDE`. That would also drop a user's
`CLAUDE_CODE_SKIP_PROMPT_HISTORY` and quietly turn transcripts back on.
Clean child environments now says to remove a named list of session
markers only.

## Open

What hooks send as `transcript_path` when transcripts are off, and how
the world is told (a protocol addition): both settled when building S02.
