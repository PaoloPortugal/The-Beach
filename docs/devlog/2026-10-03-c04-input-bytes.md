# C04's input limits counted in bytes

Features: C04, S02 (sidecar/src/history.ts, providers/claude/hooks.ts, store.ts)

Found in a review (2026-10-03). `fitInputs` capped one `session.get_history`
answer at 8 MiB of tool inputs so it stays under the 32 MiB Godot's
WebSocket client accepts (S01), but it measured `JSON.stringify(input).length`:
UTF-16 code units, not bytes. Godot's limit is in bytes, and CJK takes 3
bytes a character, an emoji 4 (2 units). A history full of non-ASCII edits
could pass 32 MiB: Godot drops the message, the command ends `disconnected`,
and the chat panel's history fetch fails the same way on every retry, so
that session's chat never loads.

`INPUT_MAX` (64 KiB, the largest input forwarded live from the hooks and
read from a transcript) had the same mismatch. It only decides what is
sent, so it was never a failure, but it is documented as a size, so it is
bytes now too.

## Fix

`jsonBytes` in `history.ts`: `Buffer.byteLength(JSON.stringify(v), 'utf8')`,
used by `fitInputs` and both `INPUT_MAX` checks. Tests with multi-byte
inputs (`history.test.ts`, `hooks.test.ts`); both fail with the old measure.
The old `fitInputs` test used only `x`, so it couldn't tell.

## Not fixed

Messages have no byte budget: 5000 at most, and a resumed transcript up to
64 MiB. Very long replies could still pass 32 MiB. Left as the Watch item
(Large chat histories): paging the history is the fix if it happens.
