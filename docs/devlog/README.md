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
| 2026-10-03 | [The tool log's markup checks cover results and Details](2026-10-03-c04-markup-checks.md) | tooling |
