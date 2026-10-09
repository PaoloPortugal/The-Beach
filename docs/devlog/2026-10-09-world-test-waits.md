# Two world-test waits: the missing folder and the S06 warning

Features: tooling (tests/world/world_test.gd; S03, S04, S06)

While checking the C09 console fix (2026-10-09-c09-console-check-flaky),
"a missing folder is refused, and the notice says so" failed in two of
three plain world-test runs run side by side on Windows. Looking into it,
"live: the next one arrives, and the warning goes" failed once with
the fake. The game was fine both times; the test read too early.

## The missing folder: queued behind the menu's listings

Timed in the test, the refusal took **3.05 s** in a plain run on its own,
against about 20 ms with the fake. Logging each `session.list_stored`
showed the cause: the menu asks for the stored sessions each time it
opens. The test opens it five times within about a second, and each
listing blocked the sidecar for about 0.75 s. Then `session.create`'s
reply waited behind four of them. `listStored` (providers/claude/store.ts)
reads the newest 200 transcripts synchronously, 64 KiB from each end, so
nothing else is handled meanwhile. Run alone in Node on the dev
machine's 181 transcripts (310 MB), it took 0.8-0.95 s. Under load, the
queue passed the check's 5 s wait.

So it depends on the machine: CI's runners have no transcripts, and the
fake's listing is instant.

The fix waits up to 20 s for the refusal, the same as the wait for the
sidecar being up. The check is about the refusal and its text, not its
speed. The stall itself is real outside the test: opening and closing the
menu quickly queues one listing per open, and meanwhile hook relays and
permission requests wait. It's a sidecar change and not decided, so it's
a Watch item in NOTES (Listing stored sessions blocks the sidecar), with
two possible fixes: a cache by size and mtime, or async reads.

## The S06 warning: the turn just starting

With the fake, the check read "Working…" where it expected no status.
The test waited until the last message contained "hello again" and the
orchestrator was idle, then 40 physics frames. But the fake shows your
own message first and only then starts the turn, so the wait passed on
your message and the idle state from before the turn began. The turn
then started during the frames. The warning had gone; the turn was just
starting.

It now waits for the reply's end (`> hello again` and "(This is the fake
provider.)", idle), then past the pickup timeout on a real timer
(`pickup_timeout + 0.2` s) and `_settle()`. So a warning that came back
would show. Nothing checked was dropped.

## Checked

With both fixes on Windows, the world test passed alone, plain and with
`-- --sidecar-dev-fake`. Then 12 runs, three at a time (6 plain, 6 with
the fake): both checks passed every time, and 11 of the 12 passed
whole. The other one (plain) failed a third, unrelated check: W04's
"facing it: no arrow, the beacon shows it" (the 64x64 headless window
leaves a 32x32 px area that counts as on screen). It wasn't looked into
here.
