# One read budget for a resumed history

Features: C04, S04 (sidecar/src/providers/claude/store.ts)

Found in a review (2026-10-03). `readHistory` skipped a main transcript
over 64 MiB, but `readSubagents` then read every
`subagents/agent-*.jsonl` beside it, each up to 64 MiB and with no total.
It all runs synchronously, on `/resume` (the `SessionStart` hook) and when
a stored session is resumed from the world, so a session with many large
subagent transcripts could block the sidecar's event loop for a long time.
Fail-safe still held (the hooks time out and Claude Code goes on as
usual), but the world froze meanwhile.

## Fix

One budget for the whole history, the same 64 MiB: the main transcript
takes its size from it, then subagent transcripts are read in name order
while they fit; one that doesn't is skipped (later, smaller ones can
still fit). A skipped subagent's calls are missing from the log; its
Agent call still shows. `readHistory` takes the budget as a parameter, so
the tests use small files.

Rejected: reading asynchronously. `readHistory` is called from hook
handlers and the resume command that expect it synchronous; making it
async is a larger change, and the budget already bounds the stall to what
reading the main transcript alone could cost before.

## Tests added

- The size skip: a subagent too big for what's left is skipped, a later
  one still read; the main transcript's size counts; a main transcript
  over the budget gives no history.
- A subagent transcript without its `.meta.json`: its calls at the top,
  with no parent call (NOTES described it; untested until now).
