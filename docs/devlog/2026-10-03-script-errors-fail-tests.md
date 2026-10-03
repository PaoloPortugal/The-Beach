# Any error fails a Godot suite

Features: tooling (tests/error_watch.gd, every Godot suite)

## The problem

A GDScript runtime error (`SCRIPT ERROR`) aborts only the function it
happens in. If that function was awaited, the caller gets null and
carries on. So a suite could print PASS and exit 0 with its later checks
never run. Seen 2026-10-03: `_tool_log` in `world_test.gd` hit a Nil
`.visible` (dev log 2026-10-03-world-test-flaky), and only reading the
output caught it. Worse, an error in a suite's own entry function (no
caller to return to) means `quit` is never called: the run hangs until
CI's 8-minute step timeout.

## Options

- **(a) CI reads the output**: each workflow step tees Godot's output
  and fails on `SCRIPT ERROR`. No GDScript change, but a local run
  still prints PASS.
- **(b) A Logger in the suites** (Godot 4.5+, `OS.add_logger`). It sees
  every error as it is logged, so a local run fails too.
- Both, with (a) as a backstop. It would catch little more: an error
  before the logger is installed is a parse error, which already exits 1.

**The user chose (b)**, and to fail on engine errors and `push_error`
too, not only script errors. That costs nothing today: none of the seven
runs logs an error, locally or on CI's three systems (checked in main's
latest green run). Warnings still don't count: `sidecar_client_test`
expects its reconnect warning.

## How it works

`tests/error_watch.gd` extends `Logger`. Each suite preloads it (no
`class_name`: it's test code) and creates it as a member, before
`_initialize`. `_log_error` ignores `ERROR_TYPE_WARNING`. For anything
else it counts the error and calls `quit(1)`: directly on the main thread,
deferred from any other. The run therefore ends at the end of that
iteration, with no further checks running in a broken state and no hang.
It also prints one FAIL line, deferred, because printing from inside a
logger logs again. The suites' PASS line also checks `_errors.ok()`.
Without that, a suite whose last steps are synchronous (clusters,
Markdown) would call `quit(0)` after the error in the same iteration and
override the 1. `clusters_test` used to call `quit(1 if _failed else 0)`;
it now quits with 1 unless it passed. Nothing checked was changed.

Probed on 4.7.2 headless before wiring it in: an error in a synchronous
call, in an awaited coroutine, in the suite's entry coroutine, from
`push_error`, from another thread and from `_finalize` (after PASS) each
end with exit 1 and the FAIL line; a warning alone still passes.

## Checked

- All seven runs in NOTES.md → Running it pass, with the same number of
  `ok` checks as before (Markdown: 74 passed).
- A deliberate Nil `.visible` access in each suite, inside an awaited
  coroutine where the suite has one (`_command` in the core suites,
  `_tool_log` in the world test) and in a synchronous test function
  otherwise. All seven runs exit 1 with the FAIL line. Then it was removed.
- The same injection without the watch: the world test printed PASS and
  exited 0 with 185 of its 196 checks run; the clusters test hung.
