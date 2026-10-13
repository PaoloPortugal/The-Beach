# Sessions running elsewhere, and reattaching after a restart

Features: S04, S05, S07, A02, C06

## The problem

After the game restarts, the sessions it started keep running in their
terminals, but the new sidecar doesn't know them, so they were listed
under Resume, and resuming one opened a second terminal on the same
conversation while the first `claude` still ran (S05's known issue, seen
live 2026-10-02). The same happens with a session the user started in a
plain terminal. Open question 5 had said such a session should be
attached to, not resumed; this was the research into how.

## The research (2026-10-12, `claude` 2.1.296)

- **`claude agents --json` lists live sessions.** The agent-view docs
  call it the supported way to read session state from outside Claude
  Code. It lists every live session on the machine, interactive ones
  included, with its `sessionId`, its state (`busy`, `waiting` and on
  what, `idle`) and, while its process is alive, its `pid`; background
  sessions whose process exited are listed without one. It takes about
  0.8 s. It refuses when the user turned agent view off
  (`disableAgentView`, `CLAUDE_CODE_DISABLE_AGENT_VIEW`), but sessions
  the game started are listed although their own `--settings` turn agent
  view off: that setting is per session. It doesn't start Claude Code's
  background supervisor (`claude daemon status` said "not running"
  after many calls).
- **An interactive `claude` doesn't read a changed `--settings` file
  again.** Probe: a `PreToolUse` hook in a `--settings` file wrote "A"
  to a file; the settings file was then changed to write "B", and the
  running session kept writing "A". `claude -p` the same. The settings
  docs only promise reloading user, project, local and managed settings.
  Header values in HTTP hooks can only take environment variables, also
  fixed at launch. So a running session's HTTP hooks stay pinned to the
  port and token it was launched with until it exits.
- **Our executable starts in 0.4-0.6 s** (2.3 s cold), measured. Sending
  every hook through our relay program (which could read a changing
  address from a file) would cost that dozens of times per reply, and
  some hooks have 2 s limits. That rules out relaying every hook.
- The bridge (channel) connects once with a one-time token from its
  environment and never retries; the `SessionStart` and status line
  relays read their relay files on every run, so they can follow a new
  sidecar if their folder survives.

## The decisions (user's, 2026-10-12)

I laid out three routes; the user chose (a) and (b), not (c):
- **(a) Leave running sessions out of Resume, and refuse to resume
  them.** Built on this branch (below).
- **(b) Reattach the sessions the game started** after a restart: S07,
  designed in NOTES, not built. Run folders move from the system temp
  folder to the user's app data folder under `The Beach/agent-sessions/`
  (the user wanted a recognizable name, so the working name, listed in
  Conventions → Renaming the project); temp was rejected because Windows
  Storage Sense and Linux tmp cleaners can delete a long-running
  session's files. The bridge reconnects, reading where to from its run
  folder with a fresh one-time token from each sidecar. The hook port is
  kept (option A): the sidecar asks for the same port each start and
  accepts the old sessions' tokens; when that port is taken, the session
  still reattaches in a degraded mode (chat, Yes/No through the channel,
  replies from the transcript; streaming, prompt options, questions,
  plans, mode, stop and sign-in notices left to the terminal), which
  NOTES documents. Rejected: relaying every hook (startup time, above).
- **(c) Attaching sessions started outside the game:** not now. They
  have none of our hooks or channel, which only launch flags give, and
  we never edit the user's settings. Kept as a deferred idea (read-only
  islands from `claude agents --json` and the transcript) and a watch
  item (a documented way to attach with full control).

Also decided that day:
- **Reattached sessions' islands are already standing** when the world
  loads, no rise (W04): the rise keeps meaning a new session; many
  rising each time the game starts would say nothing.
- **Subagents stay read-only** (Open questions → 4): vanilla Claude Code
  only lets you talk to a subagent in its terminal (the agents panel
  below the prompt); from the world the only route would be asking the
  orchestrator to pass a message on with `SendMessage`, reworded by
  Claude and costing a turn. Not vanilla. (A02's subagents don't change.)
- **Launch pickers** (next branch, scope capability): Model, Effort and
  Mode on the create panel and the Resume page, each starting at
  "Default" (no flag) every time; Mode offers the Shift+Tab four, never
  Bypass or Don't ask. This reverses C06's "no launch picker"; the
  user's reason: it's the only way to set them from the game until
  Claude Code offers one. Details in NOTES → Current focus.

## How (a) is built

`providers/claude/running.ts` runs `claude agents --json` the way
`--version` is run: the `claude` we found, an argument array, no shell,
the clean launch environment, at most 5 s and 4 MiB of output.
`parseRunning` keeps the session ids whose entry has a numeric `pid`
and a UUID `sessionId`; anything else gives nothing. `listStored` asks
it alongside reading the store and drops the running ones;
`session.resume` asks again and refuses one that runs ("That session is
still running in a terminal. Continue it there, or type /exit in it and
resume it again."), before any terminal opens. It fails soft: with agent
view off, an older `claude`, an error or an unexpected answer, nothing
is left out and the reason is logged.

Tests (`running.test.ts`, `store.test.ts`): parsing (pids, exited
background sessions, bad shapes), a fake answer leaving a session out,
refusing its resume with no terminal opened, listing and resuming it
again once it exits, and listing everything when it can't tell. Checked
against the real `claude` 2.1.296: a running terminal session was left
out and its resume refused; on `main` the same session was listed and
resumed.

## The reviews

The security review found nothing blocking; I fixed what it raised:
the time and output limits and an answer that's no list are now tested
with stand-ins for `claude` (a script named `agents`, run by `node`), a
`claude` that can't start at all (execFile throwing at once instead of
reporting) fails soft too, Windows `\r\n` is split properly in the
logged reason, and a test checks the command gets the clean environment
(a session's markers gone, `CLAUDE_CONFIG_DIR` kept). It also noted that
each listing ran `claude --version` (finding `claude`, up to 15 s per
candidate) before `claude agents`: the `claude` found last is now reused
for asking, while a launch still finds it afresh. Not finding `claude`
is now logged like the other reasons (docs-sync).

For S07 it raised two points, now in NOTES → S07 → To settle before
building: a remembered hook port is easier for another program (even
another account's) to take while the game is closed and answer
`PermissionRequest` hooks, which reopens the kept-port decision for the
user; and run folders are untrusted input for the next sidecar.

The docs check caught the guide still saying the list is quick after
the first time (every listing now takes about 0.8 s for `claude
agents`), the agent-view caveat leaving out that resume isn't refused
either, flow 08's notes, and S07 sitting before S06 in NOTES.

## Found along the way

- **The hook port after the game quits** (Watch items): sessions keep
  sending HTTP hooks to our loopback port after the sidecar is gone.
  Another local program could take the port and answer a
  `PermissionRequest` with "allow" (Claude Code sends the token; it
  doesn't check the server). Low risk; S07's kept port shortens the gap
  but doesn't close it.
- **Seven empty `sidecar-session-*` folders** were left in `%TEMP%` from
  2026-10-08 (two batches, 9:37 and 21:10). Empty, so the files were
  cleaned and only the folders stayed; likely sidecars that ended
  without their full cleanup. S07's start-up sweep of stale run folders
  will cover this; not chased further.

## The kept port, settled (user's, 2026-10-13)

The security review had left one question for the user: keep S07's hook
port, or give each launch a fresh one. I recommended keeping it. A
running session keeps sending hooks to its launch-time port whatever
the next sidecar does, and listening ports are visible to every local
account while the game runs, so a fresh port doesn't protect the
sessions left running after a quit. All it would do is put every
reattached session in the degraded mode. Keeping the port only makes it
a little easier to aim at in advance. If the port is taken, the sidecar
picks a random one, so new sessions aren't exposed. What does close the
gap is ending the sessions.

The user kept the port, with three additions: the sidecar takes the
port first thing at start; the quit warning tells people on a computer
shared with other accounts to `/exit` their sessions before quitting;
and the risk is written down (Security rules → Known gap: hooks that
outlive the sidecar, and the watch item). The user also asked for the
vulnerability itself to be documented, since Claude Code's side looks
unintentional and might be worth reporting to Anthropic: an HTTP hook
can't check who answers it, so whatever takes the port can read the
session and answer "allow", or rewrite a command with `updatedInput`.
Rejected: a fresh port per launch.
