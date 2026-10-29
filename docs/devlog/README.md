# Dev log

The long history of the project: why things are the way they are, decisions
and the alternatives we rejected, bugs found and dead ends. Not for routine
reading; look things up by feature ID.

## Format

- One file per entry: `YYYY-MM-DD-<slug>.md`.
- It starts with `# Title`, then a `Features: W01, A02` line (or `tooling` /
  `docs`).
- Write an entry when a feature or fix is finished. When a design decision
  was the user's, say so and record the reason they gave.
- Add every entry to the table below.

## Entries

| Date       | Entry | Features |
|------------|-------|----------|
| 2026-09-28 | [Project setup](2026-09-28-project-setup.md) | docs, tooling |
| 2026-09-28 | [Provider scopes](2026-09-28-provider-scopes.md) | docs |
| 2026-09-28 | [Godot MCP plugin](2026-09-28-godot-mcp.md) | tooling |
| 2026-09-29 | [Switch to godot-ai](2026-09-29-godot-ai.md) | tooling |
| 2026-09-29 | [Event schema v1](2026-09-29-event-schema.md) | docs |
| 2026-09-29 | [Sidecar language](2026-09-29-sidecar-language.md) | docs |
| 2026-09-29 | [Claude CLI route](2026-09-29-claude-cli-route.md) | docs |
| 2026-09-29 | [Principles and security rules](2026-09-29-principles-security.md) | docs |
| 2026-09-29 | [Claude CLI integration spike](2026-09-29-claude-cli-spike.md) | S02 |
| 2026-09-29 | [NOTES.md sanity check](2026-09-29-notes-sanity-check.md) | docs |
| 2026-09-29 | [License](2026-09-29-license.md) | docs |
| 2026-09-29 | [Privacy check](2026-09-29-privacy-check.md) | tooling |
| 2026-09-29 | [Markdown → BBCode spike](2026-09-29-markdown-spike.md) | C03 |
| 2026-09-29 | [Windows, macOS and Linux](2026-09-29-multi-platform.md) | docs |
| 2026-09-29 | [When transcripts are off](2026-09-29-transcripts-off.md) | S02, S04 |
| 2026-09-29 | [Sidecar core](2026-09-29-sidecar-core.md) | S01 |
| 2026-09-29 | [Agent Office (a similar project)](2026-09-29-agent-office.md) | docs |
| 2026-09-29 | [Windows terminals and S02 checkpoint 1](2026-09-29-windows-terminals.md) | S02 |
| 2026-09-29 | [S02: permissions, questions, stopping, transcript, notices, history](2026-09-29-s02-relay-questions-stop.md) | S02 |
| 2026-09-30 | [M1 world feel](2026-09-30-m1-world-feel.md) | W01, W02, W03, A01, C01, C02 |
| 2026-09-30 | [Island, ocean and first-person movement](2026-09-30-island-ocean-movement.md) | W01, W02, W03 |
| 2026-09-30 | [Placeholder orchestrator and walking up to chat](2026-09-30-orchestrator-walk-up-chat.md) | A01, C01, C02, W08 |
| 2026-09-30 | [Chat panel, quick session start, an island per session](2026-09-30-chat-panel-session-islands.md) | C02, S03, W01, W03, A01 |
| 2026-09-30 | [Subagents, placement and state markers](2026-09-30-subagents-placement-markers.md) | A02, A03, A04 |
| 2026-10-01 | [Agent view off, /clear followed](2026-10-01-agent-view-clear.md) | S02 |
| 2026-10-01 | [Answering permissions and questions in the world](2026-10-01-c05-answer-card.md) | C05 |
| 2026-10-01 | [M1 review, /resume in the terminal, SessionStart relay](2026-10-01-m1-review.md) | C02, S01, S02, C05 |
| 2026-10-01 | [C03: Markdown in the chat and the bubble](2026-10-01-c03-markdown.md) | C03, C02 |
| 2026-10-01 | [The sessions menu: start, resume, go to](2026-10-01-sessions-menu.md) | S03, S04, W07 |
| 2026-10-01 | [S05: no ending from the game; a quit warning](2026-10-01-s05-quit-warning.md) | S05, W07 |
| 2026-10-02 | [W05: clusters of islands by repository](2026-10-02-w05-clusters.md) | W05, S03, W07 |
| 2026-10-02 | [Starting: Claude Code closing before it's up](2026-10-02-start-exit.md) | S02, S03 |
| 2026-10-02 | [Sessions as tabs in one terminal window](2026-10-02-terminal-tabs.md) | S02, S03 |
| 2026-10-02 | [Sessions named like Claude Code names them](2026-10-02-titles.md) | S02, S03, S04 |
| 2026-10-02 | [Continuous integration on three systems](2026-10-02-ci.md) | (tooling) |
| 2026-10-02 | [A05: the attention cue](2026-10-02-a05-attention.md) | A05, W07 |
| 2026-10-02 | [Anthropic's terms, a paid Steam release, and OpenCode](2026-10-02-terms-steam.md) | docs |
| 2026-10-02 | [W07 proper: a fixed order, and timing every wait](2026-10-02-w07-proper.md) | W07, A05, C05 |
| 2026-10-02 | [C04: the tool-call log](2026-10-02-c04-tool-log.md) | C04, S02 |
| 2026-10-02 | [C06 + C07: decisions and the modes/plan spike](2026-10-02-c06-c07-spike.md) | C06, C07, S02 |
| 2026-10-03 | [C06 + C07: permission modes and plan approval, built](2026-10-03-c06-c07-build.md) | C06, C07, S02 |
| 2026-10-03 | [C05 reopened: the terminal's other prompt options](2026-10-03-c05-prompt-options-spike.md) | C05, C06, S02 |
| 2026-10-03 | [C05 reopened: the terminal's other prompt options, built](2026-10-03-c05-prompt-options-build.md) | C05, C06, S02 |
| 2026-10-03 | [The world test's flaky checks](2026-10-03-world-test-flaky.md) | tooling |
| 2026-10-03 | [Any error fails a Godot suite](2026-10-03-script-errors-fail-tests.md) | tooling |
| 2026-10-03 | [The Claude Code workflow](2026-10-03-dev-workflow.md) | tooling |
| 2026-10-03 | [Diagrams restyled](2026-10-03-diagrams.md) | docs |
| 2026-10-03 | [C04's input limits counted in bytes](2026-10-03-c04-input-bytes.md) | C04, S02 |
| 2026-10-03 | [One read budget for a resumed history](2026-10-03-c04-read-budget.md) | C04, S04 |
| 2026-10-03 | [The tool log's markup checks cover results and Details](2026-10-03-c04-markup-checks.md) | tooling |
| 2026-10-03 | [C08 token usage: research and spike](2026-10-03-c08-usage-spike.md) | C08, S02 |
| 2026-10-07 | [W04: islands rise and sink](2026-10-07-w04-rise-sink.md) | W04, W01, W05, A05 |
| 2026-10-07 | [Built features' status lines match the index](2026-10-07-notes-status-lines.md) | docs |
| 2026-10-07 | [The quit warning's list scrolls](2026-10-07-s05-quit-scroll.md) | S05 |
| 2026-10-07 | [W04's edge-arrow check was flaky](2026-10-07-w04-arrow-check-flaky.md) | tooling |
| 2026-10-07 | [W06: bridges, wedges and the maps](2026-10-07-w06-bridges.md) | W06, W05, W04, W07 |
| 2026-10-08 | [The performance pass: far bridges, a coarse seabed, nothing past the fog](2026-10-08-perf-pass.md) | W01, W06, C02 |
| 2026-10-08 | [S06: sign-in needed](2026-10-08-s06-sign-in.md) | S06, S02, C02, A05 |
| 2026-10-08 | [C08 token usage, built](2026-10-08-c08-usage.md) | C08, S02 |
| 2026-10-08 | [W08: swimming and the seabed](2026-10-08-w08-swimming.md) | W08, W01, W02, W03, W04, W06, W07 |
| 2026-10-08 | [W08 follow-ups: dolphin jump, shelf colours, sea floor](2026-10-08-w08-tuning.md) | W08, W01, W03 |
| 2026-10-08 | [W09: day, night and the weather](2026-10-08-w09-day-night.md) | W09, W02, W08, W01, A01 |
| 2026-10-08 | [W10: kinds of island](2026-10-08-w10-biomes.md) | W10, W01, W03, W06, W04, W09, A04, S03 |
| 2026-10-08 | [C09: debug commands](2026-10-08-c09-commands.md) | C09, W09 |
| 2026-10-09 | [Three flaky world-test checks: the missing folder, the S06 warning, W04's arrow](2026-10-09-world-test-waits.md) | tooling |
| 2026-10-09 | [C09's console checks waited on physics frames](2026-10-09-c09-console-check-flaky.md) | tooling |
| 2026-10-09 | [W05/W06: clusters that grow without limit](2026-10-09-w05-unbounded-clusters.md) | W05, W06 |
| 2026-10-09 | [S04: Resume on its own page, and a kept listing](2026-10-09-s04-resume-page.md) | S04, S03, W07, W05, W08, W10 |
| 2026-10-09 | [C08: the short-name tests on a slow Windows runner](2026-10-09-c08-askwindows-flaky.md) | C08, tooling |
| 2026-10-10 | [W11: crouch and slide](2026-10-10-w11-crouch-slide.md) | W11, W03, W08 |
| 2026-10-12 | [CI: only on main](2026-10-12-ci-main-only.md) | tooling |
| 2026-10-12 | [C10: the settings menu](2026-10-12-c10-settings.md) | C10, A05, W03, W04, W09, C01, S03 |
| 2026-10-12 | [The second performance pass: the Mobile renderer](2026-10-12-perf-pass-2.md) | Performance, Rendering, C10, W09, C09 |
| 2026-10-12 | [W10: the mountain bugs (torches in the air, ziplines through bridges)](2026-10-12-w10-mountain-bugs.md) | W10, W09, W06 |
| 2026-10-12 | [The sidecar without blocking: stored sessions and short names](2026-10-12-sidecar-no-blocking.md) | S04, C08 |
| 2026-10-12 | [The sessions ring](2026-10-12-sessions-ring.md) | W07, S03, S04 |
| 2026-10-12 | [The crosshair](2026-10-12-crosshair.md) | C11, C01, W10, C10 |
| 2026-10-12 | [A02: the report throw](2026-10-12-report-throw.md) | A02 |
| 2026-10-12 | [Sessions running elsewhere, and reattaching after a restart](2026-10-12-live-sessions.md) | S04, S05, S07, A02, C06 |
| 2026-10-13 | [C12: model, effort and mode at launch](2026-10-13-c12-launch-pickers.md) | C12, C06, S02, S03, S04 |
| 2026-10-13 | [S07: reattaching to running sessions](2026-10-13-s07-reattach.md) | S07, S05, S02, S04 |
| 2026-10-19 | [W12: islands kept across restarts](2026-10-19-w12-islands-kept.md) | W12, S07, W05, W06, W10 |
| 2026-10-22 | [S02: finding claude through the login shell](2026-10-22-login-shell-path.md) | S02 |
| 2026-10-22 | [S08: read-only islands for sessions started outside the game (research)](2026-10-22-s08-outside-sessions-research.md) | S08, S07, S04, W05, W12 |
| 2026-10-22 | [S08: read-only islands for sessions started outside the game (the build)](2026-10-22-s08-outside-sessions.md) | S08, S07, C10, W12, Protocol |
| 2026-10-22 | [C13: the pause menu](2026-10-22-c13-pause-menu.md) | C13, C10, S05, W03, A05, C01 |
| 2026-10-23 | [Similar projects (second look)](2026-10-23-similar-projects.md) | docs |
| 2026-10-26 | [C02: a long chat no longer jitters while it's laid out](2026-10-26-c02-chat-jitter.md) | C02, C03 |
| 2026-10-26 | [S02: Claude Code set by hand](2026-10-26-s02-program-path.md) | S02, C10, S03, Protocol |
| 2026-10-26 | [Session details: no beacon for outside sessions, a quicker bridge](2026-10-26-session-start-details.md) | S08, W04, S02, S01 |
| 2026-10-26 | [C14: the main menu](2026-10-26-c14-main-menu.md) | C14, C13, S07, W01, W04 |
| 2026-10-27 | [Island smoothing](2026-10-27-island-smoothing.md) | W01, W06, W08, W12 |
| 2026-10-27 | [D01: fishing, designed](2026-10-27-d01-fishing-design.md) | D01, C15, A05 |
| 2026-10-27 | [C15: the hotbar](2026-10-27-c15-hotbar.md) | C15, D01 |
| 2026-10-27 | [D02: bug catching, designed](2026-10-27-d02-bug-catching-design.md) | D02, D01, C15, C11 |
| 2026-10-27 | [D03: the collection, designed](2026-10-27-d03-collection-design.md) | D03, D01, D02, the hub |
| 2026-10-27 | [D04: parkour, designed (and W13's new moves, D05's plunger gun)](2026-10-27-d04-parkour-design.md) | D04, W13, D05, W03, W11, W04, W06, the hub |
| 2026-10-27 | [C16: multi-language support, designed](2026-10-27-c16-localisation-design.md) | C16, C10, D01, S01, C05, C06, C07, C09, A05 |
| 2026-10-27 | [S08: the flag check read the island mid-build](2026-10-27-s08-flag-check-flaky.md) | S08, W01, C14 |
| 2026-10-27 | [D01: fishing](2026-10-27-d01-fishing.md) | D01, C15, D03, W01, W02, W06, W08, C11, C16 |
| 2026-10-27 | [W06: an island could rise through a bridge](2026-10-27-w06-island-under-bridge.md) | W06, W12, W05, W10 |
| 2026-10-27 | [Merge log](2026-10-27-merge-log.md) | docs |
| 2026-10-27 | [Trimming NOTES.md and the last spike](2026-10-27-docs-trim.md) | docs |
| 2026-10-27 | [Similar projects (third look)](2026-10-27-similar-projects.md) | docs |
| 2026-10-27 | [The questions for Anthropic, refreshed](2026-10-27-anthropic-questions.md) | docs |
| 2026-10-27 | [D01: the fight](2026-10-27-d01-fight.md) | D01, A05, W03 |
| 2026-10-28 | [D01: the fight's runs, arrow and view](2026-10-28-d01-fight-runs.md) | D01 |
| 2026-10-28 | [S01: retrying the sidecar's start, and restarting it](2026-10-28-s01-start-retry.md) | S01 |
| 2026-10-28 | [C17: the game's opening](2026-10-28-c17-opening.md) | C17, S01, C14 |
| 2026-10-29 | [Faster headless suites: --fixed-fps 60](2026-10-29-test-speed.md) | tooling |
