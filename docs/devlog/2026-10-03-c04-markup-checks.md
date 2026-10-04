# The tool log's markup checks cover results and Details

Features: tooling (tests/world/world_test.gd; C04)

Found in a review (2026-10-03). Tool text is untrusted (Security rules),
and `chat/tool_fold.gd` puts the summary, the result line and the
Details text in plain `Label`s. The world test only had markup in the
summary, so a change that moved the result or Details into a
`RichTextLabel` (for colour, say) would have passed.

Now the result carries `[color=red]...[/color]` and the input `[i]...[/i]`,
both checked as written, and the test checks the open fold, Details
shown, holds no `RichTextLabel` at all: the check that actually fails if
someone switches a node to BBCode. No change to the game.
