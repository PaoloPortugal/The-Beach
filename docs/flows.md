# Flows

Step-by-step diagrams of how the pieces talk to each other, for the Claude
provider on the CLI route, one file per flow in
[`diagrams/sequence/`](diagrams/sequence/). They show the behaviour
verified by the M0 integration spike (dev log 2026-09-29-claude-cli-spike).
NOTES.md stays the source of truth: when S02 or the Protocol section
changes, update the matching flow in the same branch. The component
diagram, which shows the pieces themselves, is in NOTES.md → Architecture.

GitHub draws the Mermaid blocks as diagrams. Arrows between World and
Sidecar are protocol messages (NOTES.md → Protocol); arrows from Claude
Code are hooks (HTTP, with the session's token; `SessionStart` goes
through Relay, our executable run as a command hook,
[flow 9](diagrams/sequence/09-clear-or-resume.md), and so does the
status line, Relay in `statusline` mode,
[flow 12](diagrams/sequence/12-token-usage.md)); Bridge is our channel
bridge (NOTES.md → S02).

The terminal and the world are two windows onto the same session: you can
switch between them at any point, and whichever answers first wins.
Transcript is Claude Code's session file, which the sidecar follows
read-only for the things no hook reports (NOTES.md → S02). If the user
turned transcripts off in Claude Code, the Transcript steps don't happen
and the world waits for the next hook instead (NOTES.md → S02 → When
transcripts are off).

## How to read these

Time runs top to bottom; each arrow is one message, numbered in order.
- **Blue box, "Ours":** the parts we build (World, Sidecar, Bridge,
  Relay). **Grey box, "Claude Code, the user's own":** the install and its
  transcript, which we only launch, watch and read. **User** stands
  outside both.
- **Amber band:** the step the flow is about, with a note naming the code
  that does it.
- **Status line** at the top of each file: built or planned, the features
  (IDs from NOTES.md → Feature index) and the NOTES section to read.
- **Solid arrow:** a message. **Dashed arrow:** the reply to an earlier
  request.
- **Requests always get a reply, and every reply is drawn**, even when it
  says nothing. Two kinds of requests: hooks (Claude Code asks the sidecar
  "anything to add?"; the usual answer is "nothing to add") and commands
  from the world (answered `ok` or `error`).
- **Announcements get no reply:** "this happened" messages, such as protocol
  events to the world, chat or verdicts passed along through the bridge,
  and new lines in the transcript.
- Boxes are notes, or group steps: `loop` repeats, `alt` / `else` are
  alternatives, `opt` happens only sometimes, `par` / `and` happen at the
  same time.

## The flows

| # | Flow | Features |
|---|------|----------|
| 0 | [Starting up](diagrams/sequence/00-starting-up.md) | S01, S07, S08, S02, C14, C17 |
| 1 | [Create a session](diagrams/sequence/01-create-a-session.md) | S02, S03, C12 |
| 2 | [A chat turn](diagrams/sequence/02-chat-turn.md) | S02, C02 |
| 3 | [A permission prompt](diagrams/sequence/03-permission-prompt.md) | S02, C05 |
| 4 | [A clarifying question](diagrams/sequence/04-clarifying-question.md) | S02, C05 |
| 5 | [A subagent](diagrams/sequence/05-subagent.md) | S02, A02, C04 |
| 6 | [Stopping](diagrams/sequence/06-stopping.md) | S02 |
| 7 | [When our side fails](diagrams/sequence/07-our-side-fails.md) | S02 |
| 8 | [Resuming a stored session](diagrams/sequence/08-resume-stored-session.md) | S04, C12 |
| 9 | [/clear or /resume: another conversation in the session](diagrams/sequence/09-clear-or-resume.md) | S02 |
| 10 | [A plan to approve](diagrams/sequence/10-plan-approval.md) | C07, S02 |
| 11 | [A prompt's other options](diagrams/sequence/11-prompt-options.md) | C05, C06 |
| 12 | [Token usage: the transcript and the status line relay](diagrams/sequence/12-token-usage.md) | C08, S02, C12 |
| 13 | [Sign-in needed](diagrams/sequence/13-sign-in-needed.md) | S06, S02 |
| 14 | [Coming back after a restart](diagrams/sequence/14-reattach-after-restart.md) | S07, S01, W12, C14, W04 |
| 15 | [A session back with its hook port taken (read-only)](diagrams/sequence/15-read-only-mode.md) | S07 |
| 16 | [Sessions started outside the game (read-only)](diagrams/sequence/16-outside-sessions.md) | S08, C10, W12 |
| 17 | [Choosing Claude Code by hand](diagrams/sequence/17-program-set-by-hand.md) | S02, C10, S03 |

**Adding a flow:** a new file `diagrams/sequence/NN-<slug>.md` starting
with `# NN. Title`, the link back here and the status line, then the
diagram. Copy an existing file's header: `autonumber`, a box for each side
present (blue `rgba(47,111,191,0.12)` for ours, grey `rgba(128,128,128,0.14)`
for Claude Code), and one amber band (`rect rgba(255,193,7,0.18)`) with
its code note. The colours are see-through so they read in GitHub's light
and dark themes. Then add a row above.
