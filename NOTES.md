# The Beach: developer notes

Read this first every session. It is the single source of truth for the
design; keep it current and short.

- `NOTES.md` (this file): what the project is, where it's going, how it works.
- `docs/GUIDE.md`: user's guide for built features. Must always match this file.
- `docs/devlog/`: long history, decisions, rejected alternatives, bugs. Look up by feature ID.
- `docs/flows.md`: step-by-step diagrams (create a session, chat, permission,
  question, subagent, stop, failure). Derived from this file; update together.
- `CLAUDE.md`: working rules. `README.md`: pitch and setup.
- `assets/CREDITS.md`: source and license of every asset.

## Concept

A 3D working environment in Godot 4 that shows AI coding sessions as a
world you walk around in. It is a place to **work**, not a passive monitor:
you create sessions, resume old ones and chat with the orchestrator, all
from inside the world.

**World.** A beach and ocean world. Each session is an **island**: a new
session rises out of the ocean and an ended one sinks. Islands from the same
project cluster into an **archipelago** joined by walkable bridges, and
unrelated projects get their own stretch of ocean. Bridges are for
exploration and feel; a **teleport menu** is for getting work done quickly.
Other biomes (hills, mountains) come later, so region connection is a
general system, not a beach-specific one.

**Agents.** The **orchestrator** sits at the centre of its island (a bigger
model at a beach desk or under an umbrella). Walking up to it opens the
chat panel. **Subagents** are small models at little PCs on the sand.
They spawn when the orchestrator spawns them and, when they finish, run
their report back to whoever called them and disappear. They show working,
waiting on you, done or error (A03). An agent waiting on a permission
prompt or a question should visibly draw your attention. The agents'
look was planned as the AI tool's logo; that is open question 7 (branding).

**Terminal and world together.** Each session is a normal `claude` running
in a terminal window, and the world is a second window onto it: you can
chat, answer prompts and questions, or stop it in either place, and switch
at any time (S02).

**Downtime.** You spend a lot of time waiting on agents, so the world should
eventually give you something to do: parkour and minigames. These aren't
designed yet (see Known issues and next steps → Deferred ideas).

**Principles (user's).**
- **A pretty interface over the real thing, nothing more.** We touch as
  little of what the AI tool provides as possible: we launch it, watch it
  through its documented extension points and pass the user's own input to
  it. We never modify, bundle or re-implement it, never handle its logins,
  and never rely on undocumented behaviour when a documented way exists.
- **Never harm the user through poor quality.** No vulnerabilities, no
  silent actions on the user's behalf, no data leaving the machine. When
  our side fails, the tool must fall back to its own normal behaviour (e.g.
  the terminal asks the question), never to "allowed". See Architecture →
  Security rules.
- **Free public release** is the goal, so everything must hold up on other
  people's machines, not just the developer's.
- **Windows, macOS and Linux are all first-class.** Every feature is
  designed for all three from the start; nothing may assume one OS's
  terminal, paths, shell or installed tools. See Architecture → Platforms.

**Art direction.** Low-poly. Assets are made by the user or come from CC0 packs
such as Kenney, **never AI-generated**. Kenney packs are the likely source
for terrain and environment, which leaves custom modelling effort for the
agent models (their look: open question 7).

## Feature index

Prefixes: **W** world (islands, ocean, bridges, travel, player movement),
**A** agents (orchestrator, subagents, states, placement), **C** chat panel
and in-world UI, **S** sidecar and session management. v1 = part of the
v1 slice.

| ID  | Feature                                   | Status  | Guide section | Main code |
|-----|-------------------------------------------|---------|---------------|-----------|
| W01 | Beach island (v1)                         | planned | n/a           | n/a       |
| W02 | Ocean (v1)                                | planned | n/a           | n/a       |
| W03 | Player movement (v1)                      | planned | n/a           | n/a       |
| W04 | Island rise / sink                        | planned | n/a           | n/a       |
| W05 | Archipelagos (project clustering)         | planned | n/a           | n/a       |
| W06 | Bridges (region connection)               | planned | n/a           | n/a       |
| W07 | Teleport menu                             | planned | n/a           | n/a       |
| A01 | Orchestrator (v1)                         | planned | n/a           | n/a       |
| A02 | Subagents spawn / despawn (v1)            | planned | n/a           | n/a       |
| A03 | Agent state indicators                    | planned | n/a           | n/a       |
| A04 | Procedural agent placement (v1)           | planned | n/a           | n/a       |
| A05 | Permission attention cue                  | planned | n/a           | n/a       |
| C01 | Walk up to chat (v1)                      | planned | n/a           | n/a       |
| C02 | Chat panel, plain text and streaming (v1) | planned | n/a           | n/a       |
| C03 | Markdown rendering                        | planned | n/a           | n/a       |
| C04 | Tool-call log                             | planned | n/a           | n/a       |
| C05 | Permission approve / deny                 | planned | n/a           | n/a       |
| C06 | Permission mode control                   | planned | n/a           | n/a       |
| C07 | Plan approval                             | planned | n/a           | n/a       |
| S01 | Sidecar and WebSocket server (v1)         | built   | S01           | `sidecar/src/`, `core/sidecar/` |
| S02 | Claude provider (v1)                      | built   | S02           | `sidecar/src/providers/claude/`, `sidecar/src/launch/` |
| S03 | Create session from the world             | planned | n/a           | n/a       |
| S04 | List and resume stored sessions           | sidecar side built (branch) | n/a | `sidecar/src/providers/claude/store.ts` |
| S05 | End session                               | planned | n/a           | n/a       |

## When a feature lands

- [ ] Update its `### <ID>` section in Systems (planned intent → how it works),
      including its provider scope.
- [ ] Update its index row: status, guide section, main code.
- [ ] Add or update its `<ID>` section in `docs/GUIDE.md` in plain language,
      and add it to the guide's table of contents.
- [ ] Reread the guide section against this file.
- [ ] Update Architecture / Protocol / Conventions if it touched them, and
      `docs/flows.md` if it changed how the pieces talk.
- [ ] Record any new assets in `assets/CREDITS.md`.
- [ ] Write a dev-log entry and add it to `docs/devlog/README.md`.
- [ ] Update "Current focus".

## Architecture

Overview (GitHub draws this Mermaid block as a diagram). Everything runs on
the user's machine; only Claude Code itself talks to Anthropic. Step-by-step
flows are in `docs/flows.md`.

```mermaid
flowchart TB
    godot["<b>Godot</b><br/>world, agents, chat UI"]

    subgraph sidecar["Sidecar (TypeScript on Node)"]
        direction LR
        core["<b>Generic core</b><br/>session registry,<br/>WebSocket server"]
        provider["<b>Claude provider</b><br/>the only Claude-specific part"]
        core <--> provider
    end

    subgraph machine["On the user's machine, per session"]
        direction LR
        bridge["<b>Channel bridge</b><br/>ours: tiny MCP server"]
        term["<b>Terminal running claude</b><br/>user's own install and login"]
        store[("<b>Transcripts</b><br/>~/.claude/projects")]
        term <-->|"starts it,<br/>stdio"| bridge
        term -->|writes| store
    end

    anthropic(["Anthropic servers"])

    godot <-->|"WebSocket, protocol v1:<br/>events down, commands up"| core
    provider -->|"launches with our<br/>settings and flags"| term
    term -->|"hooks over local HTTP:<br/>what is happening"| provider
    provider -.->|"hook replies:<br/>question answers, stop"| term
    bridge <-->|"chat in, permission<br/>prompts and answers"| provider
    provider -->|"watches live, reads<br/>history and stored sessions"| store
    term <--> anthropic
```

- **Godot** (GDScript): the world, player movement, island and bridge
  generation, agent models and state visuals, in-world chat UI.
- **Sidecar** (TypeScript on Node, open question 6): runs sessions and
  forwards their activity to Godot as generic events. It owns the session
  registry. Shipped as one self-contained executable per platform, so users
  don't need Node; Godot starts it (see Platforms).
- **Provider**: translates one AI tool's native events into the generic
  vocabulary. Only the **Claude provider** exists. It launches the user's
  own, unmodified `claude` CLI in a terminal window, receives its hook
  events over local HTTP, talks to it through our channel bridge, and
  reads its transcript under `~/.claude/projects/` (live, for what hooks
  don't report, and for history and resuming). See S02.
- **One session ID = one island.** It is the core unit in both the sidecar's
  data model and Godot's scene tree.

**Security rules.** Our local entry points (the WebSocket server, the hook
endpoint, the bridge connection) can approve tool use and send messages
into a session, so they are as sensitive as the user's keyboard. Every
feature that touches them follows these rules, and each is tested:
- **Loopback only.** Every server binds to `127.0.0.1`, never `0.0.0.0`.
- **Authenticate every connection.** The sidecar makes random secret
  tokens at start: one for Godot's WebSocket, and per launched session one
  for its hooks (sent as a header) and one for its bridge. Requests
  without the right token are rejected. Loopback alone isn't enough: any
  local program could connect.
- **Reject browsers.** Web pages can open connections to `localhost`, and
  browsers always send an `Origin` header. Godot's WebSocket client never
  sends one (its source, and a live Godot 4.7.2, checked in S01), so the
  WebSocket server refuses any request that has an `Origin` header, even
  with the right token, and any `Host` other than `127.0.0.1:<port>`
  (DNS rebinding). A malicious site can't drive a session.
- **Nothing is approved without the user.** Permissions, questions and
  messages go to the session only as the direct result of the user's
  action in the world. No auto-approve rules, no permissive permission
  modes chosen for the user, no "allow always" without an explicit choice.
- **Fail safe.** If the sidecar or Godot is down, slow or crashes, the
  session must fall back to Claude Code's own terminal prompts, never to
  allowing. (Verified for hanging, erroring and offline hooks: S02.)
- **No shell strings.** Processes are launched with argument arrays, never
  by building a shell command from text, so a project path or session name
  can't inject commands. This includes terminal windows: a terminal is only
  ever given the fixed path of our launcher and the path of a session file,
  never a command line with session data in it (see Platforms).
- **Clean child environments.** Launched processes get the user's normal
  environment minus the variables Claude Code sets inside its own sessions
  (e.g. `CLAUDECODE`, `CLAUDE_CODE_CHILD_SESSION`, session IDs and tokens),
  which could carry another session's values. Remove a named list of
  those markers plus a few **narrow families** by prefix (user's decision,
  S02), only where every documented variable in the family is one Claude
  Code sets itself: `CLAUDE_CODE_SESSION_`, `CLAUDE_CODE_CHILD_`,
  `CLAUDE_CODE_MESSAGING_`, `CLAUDE_CODE_BRIDGE_` (checked against the
  env-vars docs, 2026-09-29). Never everything starting with `CLAUDE`: user
  configuration such as `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_EFFORT_LEVEL` and
  `CLAUDE_CODE_SKIP_PROMPT_HISTORY` (transcripts off) must pass through,
  or we'd silently undo the user's choices. (The S02 spike stripped every
  `CLAUDE*` variable; don't copy that.) The same goes for anything a store client
  injects into the game (e.g. Steam's `LD_PRELOAD` overlay hooks and its
  `Steam*` variables). The lists are in `sidecar/src/providers/claude/env.ts`
  and `sidecar/src/launch/env.ts`, with a test that user settings survive.
- **Treat all session content as untrusted.** Model output, tool output and
  file content can contain anything: escape it before it becomes BBCode (no
  injected `[url]` or `[img]`), never open links or run anything from it
  without a user click, and never pass it back into the session as if the
  user typed it.
- **Private by default.** Transcripts and events stay on the machine: no
  telemetry, no network calls except those Claude Code makes itself. We
  only read the user's Claude files, never write them, and never edit the
  user's settings (per-session `--settings` instead). We never save our
  own copy of a session's conversation to disk, so a user who turned
  Claude Code's transcripts off keeps nothing on disk because of us.
- **Few, pinned dependencies.** Every sidecar dependency is justified,
  version-pinned with a lockfile, updated deliberately, and under a license
  that allows redistribution in an MIT project.

**Multi-provider rules.** Only Claude is built, and near-term effort goes into
making it good, including Claude-only features (e.g. model choice, usage,
context window). Adding another tool (Codex, Cursor, ...) must still only need a
new adapter plus, optionally, its own extension UI. Every feature has one of
three **provider scopes**:
- **Core:** every provider must support it (sessions, agents, messages,
  permissions). Generic events; each provider translates into them.
- **Capability:** a generic concept that not every provider has (e.g. model
  choice, token usage, context-window fill). Generic events, gated by a
  capability the provider declares for the session; Godot shows the UI only
  when it's declared. Prefer this over an extension whenever the concept
  plausibly exists elsewhere.
- **Extension:** truly unique to one provider. Namespaced by provider in the
  protocol, and handled in Godot by that provider's own UI module, so that
  removing a provider means deleting its folders and nothing else.

Naming: Claude-specific names appear only in the sidecar's Claude provider
module, the Claude extension namespace of the protocol, and Godot's Claude UI
module. Everything else is named generically. Don't build a second provider;
just don't assume there will only be one. The exact capability and extension
format is in Protocol → Capabilities and Extensions.

**Platforms (user's decision, 2026-09-29).** Windows, macOS and Linux, all
first-class (dev log 2026-09-29-multi-platform). Claude Code itself runs on
all three (macOS 13+, Windows 10 1809+, common Linux distributions), with
the same `~/.claude` layout. What differs, and how we handle it:
- **Terminal windows.** A generic **terminal launcher** in the sidecar
  (not Claude-specific: any CLI provider runs in a terminal) opens the
  user's terminal on a per-OS default, with fallbacks and a setting to pick
  another: Windows Terminal, then the classic console (started through
  `conhost.exe`, so the program gets a real console) on Windows;
  Terminal.app (iTerm2 selectable) on macOS; the first installed of the
  common ones (GNOME Terminal, Konsole, xfce4-terminal, kitty, Alacritty,
  WezTerm, …) on Linux. The terminal runs our **launcher** (a mode of the
  sidecar executable) with only a session file's path; the launcher reads
  the arguments from that file and starts the provider's CLI with an
  argument array in the same terminal. So no terminal ever gets a command
  line built from text, even where the terminal only accepts a script
  (macOS). If no terminal can be opened, the world says so.
- **Node runtime.** The sidecar is built into one self-contained
  executable per platform and shipped with each Godot export. The same
  executable runs as the channel bridge (Claude Code starts it by absolute
  path) and as the launcher, so nothing needs Node installed.
- **Starting and stopping.** Godot starts the sidecar with an argument
  array and a pipe; the sidecar exits when that pipe closes, which covers
  Godot quitting or crashing on every OS (Windows has no graceful stop
  signal). Launched `claude` sessions keep running on their own.
- **Finding `claude`.** Apps started from the macOS Dock or a Linux menu
  don't get the user's shell PATH. Look in PATH, then the documented
  install locations (native installer `~/.local/bin`, Homebrew, WinGet,
  apt/dnf, npm global), with a setting to point at it by hand, and a clear
  message when it isn't found. On Windows, start `claude.exe` directly: an
  npm `claude.cmd` wrapper needs a shell, so find the real executable
  behind it instead.
- **Paths.** Build them with the platform's path functions, never by
  joining strings with `/` or `\`. Never decode the transcript folder
  names under `~/.claude/projects` (the encoding loses information, and
  case sensitivity differs by OS): use `transcript_path` from hooks, and
  read a stored session's working directory from inside its transcript.
- **Watching files.** Follow transcripts by polling their size, not with
  OS file-watch events, which behave differently on each platform.
- **Fonts.** Don't rely on system fonts being present; ship the fonts the
  UI needs (the Markdown spike's monospace list is a stand-in). Which
  fonts is open: most good monospace fonts are under the OFL, not CC0, so
  ask before adding one.
- **WSL.** Only native Windows Claude Code in v1 (see Deliberate
  limitations).
- **Testing.** Only Windows is available to test on for now; see Watch
  items → Untested on macOS and Linux.

The game (Godot) follows the same rule:
- **Rendering (user's decision).** Built for **Forward+**, with Godot's
  default drivers: Vulkan on Windows and Linux, Metal on macOS. No
  graphics API is required: when the first choice fails, Godot falls back
  to Direct3D 12 and then to the **Compatibility renderer** (OpenGL 3.3)
  on its own (`fallback_to_d3d12`, `fallback_to_opengl3`, both on by
  default; checked in 4.7.2). The world must stay usable under
  Compatibility: every effect we use needs a plain fallback there (e.g.
  simpler water and lighting), and both renderers get checked. No graphics
  menu: selection is automatic only; for driver trouble, Godot's
  `--rendering-driver` / `--rendering-method` command-line flags are the
  escape hatch (goes in the guide once there's something to run). If the
  game ships on Steam, those become Steam launch options (e.g. "Play
  (OpenGL)") that Steam offers at start (Watch items → Steam).
- **Shaders** are written in Godot's shading language only, never
  API-specific code, so they work under every driver.
- **Input.** Movement uses physical key positions (WASD works on AZERTY
  and other layouts); shortcuts use Godot's Ctrl/Cmd auto-remap so they
  follow each OS's convention.
- **Paths.** `res://` paths must match the file's exact case (Windows
  forgives a wrong case, Linux and exported games don't); settings and
  saves go under `user://`, which Godot maps to each OS's usual place.
- **Display.** HiDPI stays on (`allow_hidpi`, the default); UI scales
  with the screen rather than assuming a size. Linux runs on X11 and
  Wayland.
- **Exports and plugins.** Export presets for Windows, macOS and Linux.
  No GDExtension or native plugin in the game unless it ships builds for
  all three (the Godot AI addon is an editor-only dev tool).

**Layout.** The Godot project is the repo root (`project.godot`). Other
top-level folders sit beside it:

| Path | Role |
|------|------|
| `project.godot`, `icon.svg` | Godot project (4.7, GDScript, no .NET). Version pinned in `.godotrc`. |
| `assets/` | Art and audio, plus `CREDITS.md`. |
| `sidecar/` | Sidecar, TypeScript on Node 22.21.0, built into one executable per platform that will also run as the channel bridge and the terminal launcher (S02). Has a `.gdignore` so Godot doesn't scan it. Files below. |
| `core/`, `tests/` | Godot code (by domain) and headless tests; see the folder table below. |
| `protocol/` | Shared event schema, `events.schema.json` (see Protocol). Has a `.gdignore`. |
| `docs/` | User's guide, flow diagrams (`flows.md`) and dev log. |
| `spikes/` | Throwaway prototypes (M0), each with a dev-log entry, kept as references and deleted once their feature is built. `claude-cli/` (Node, for S02) has a `.gdignore`; `markdown/` (Godot, for C03) is visible to Godot so its demo scene runs. |
| `addons/godot_ai/` | Dev tool, not a feature: third-party editor plugin (godot-ai, MIT) that lets Claude Code drive the Godot editor over MCP. See Running it. Don't edit it by hand; it self-updates and checks its files against a signed manifest. It adds the `_mcp_game_helper` autoload to `project.godot` (game-side screenshots and logs over Godot's debugger channel only; inert in the editor, stripped from exports). |

**Godot folders (user's decision: by domain).** Scenes and scripts for a
thing sit together; a provider's UI lives only under `providers/<id>/`, so
removing a provider means deleting its folders.

| Path | Role |
|------|------|
| `core/` | Generic, provider-neutral code. `core/sidecar/`: the sidecar client (autoload `Sidecar`). `core/sessions/`: `SessionStore`, Godot's copy of every live session, kept up to date from the events. |
| `world/`, `agents/`, `chat/` | World, agent and chat-panel scenes and scripts (as W, A and C features land). |
| `providers/<id>/` | One provider's own UI module (extensions). |
| `tests/` | Headless test scripts, mirroring the folders above. Not shipped. |

**Sidecar files** (`sidecar/`):

| Path | Role |
|------|------|
| `src/main.ts` | Entry point: picks the executable's mode. |
| `src/serve.ts` | Server mode: handshake, stdin lifetime. |
| `src/server.ts` | WebSocket server and its security checks. |
| `src/registry.ts` | Session registry: state, `seq`, event checks. |
| `src/commands.ts` | Runs commands from Godot. |
| `src/protocol.ts` | Protocol types and schema validation. |
| `src/provider.ts` | The provider interface. |
| `src/launch/` | Generic: terminal launcher, `launch` mode, clean environments. |
| `src/providers/` | One folder per provider. `claude/`: finding `claude` and launching it (`index.ts`), a running session (`session.ts`), the channel bridge, the hook endpoint and translation, the transcript follower (S02), stored sessions (S04). |
| `test/` | `node:test` suites, the fake provider, `dev-fake.ts` and `try-claude.ts`. Not shipped. |
| `scripts/` | Build and packaging. |
| `licenses/` | Node's license text, for the shipped notices. |

## Protocol

The contract between Godot and the sidecar, over a local WebSocket. It has
a generic core, capability-gated optional features and provider-namespaced
extensions (see Multi-provider rules), and must not assume a maximum number of agents
per session. The full schema is `protocol/events.schema.json` (JSON Schema,
so the sidecar and tests can validate against it); this section is the
overview. **Version 1.**

**Messages.** One JSON object per WebSocket message, with a `type`:
- Types are `noun.verb`. Events (sidecar → Godot) are past tense
  (`session.created`); commands (Godot → sidecar) are imperative
  (`session.create`).
- Every command has an `id`. The sidecar answers `ok` (with an optional
  `result`) or `error` (`code`, `message`) carrying the same `id`. An `error`
  without `id` is a protocol-level error. Error codes are listed in the
  schema (`error.code`).
- **Replies come first.** Events a command causes (e.g. `session.created`
  after `session.create`, `session.ended` after `session.end`) are sent
  after its reply, never before.
- Every session-scoped event has `session` and `seq`, a per-session counter.
  A gap in `seq` means Godot missed something and sends
  `session.get_snapshot`.

**Starting.** Godot starts the sidecar with a pipe. The sidecar's stdout
carries exactly one line, `{"type":"ready","protocol":1,"port":…,"token":…}`;
Godot connects to `ws://127.0.0.1:<port>/` with `Authorization: Bearer
<token>`. One client at a time: a new connection replaces the old one
(close code 4000). Messages from Godot are limited to 4 MiB.

**Connecting.** The sidecar sends `hello` (protocol version, providers), one
`session.snapshot` per live session, then `sync.completed`. Godot refuses a
protocol version it doesn't know. A snapshot is a session's full state
(agents, states, pending permissions, capabilities); after it, only changes
follow. This covers Godot restarting in v1 and attaching to outside
sessions later (open question 5): both are "send a snapshot, then changes".
Chat history isn't in the snapshot; Godot asks for it with
`session.get_history`. An event whose `seq` is not above the last one Godot
has for that session (e.g. from a snapshot) is stale and ignored.

**IDs.** The sidecar makes an opaque `session` ID. The provider's own ID
(e.g. Claude's session UUID) is `native_id`, null until assigned. `origin` is
`app` (started here) or `external` (attached; not in v1). Agents are keyed by
`agent` within their session.

**Agents** form a tree: `role` is `orchestrator` or `subagent`, and `parent`
is the agent that spawned it (null for the orchestrator). Agents stay in the
session after finishing; Godot decides what to show. **States:**

| State | Orchestrator | Subagent | Meaning |
|---|---|---|---|
| `working` | ✓ | ✓ | thinking or running tools |
| `waiting` | ✓ | ✓ | needs the user; `reason` says why (`permission`, `question`, `input`, ...) |
| `idle` | ✓ | | turn finished, the user's move |
| `done` | | ✓ | result returned; may be resumed (back to `working`) |
| `error` | ✓ | ✓ | failed or interrupted |

The orchestrator never becomes `done`: the session ending is `session.ended`.

**Core vocabulary.**

| Sidecar → Godot | Godot → sidecar |
|---|---|
| `hello`, `sync.completed`, `ok`, `error` | `session.create`, `session.resume`, `session.list_stored` |
| `session.snapshot`, `session.created`, `session.ended`, `session.notice` | `session.end`, `session.get_snapshot`, `session.get_history` |
| `agent.spawned`, `agent.state_changed` | `message.send` |
| `message.started`, `message.delta`, `message.completed` | `permission.respond` (`allow` / `deny`, optional `note`) |
| `tool.started`, `tool.finished` | |
| `permission.requested`, `permission.resolved` | |

- `session.snapshot` places an island as is; `session.created` plays the rise
  animation.
- Messages stream as `started` → `delta`s → `completed`, whose `text` is the
  full Markdown and replaces the deltas. User messages are events too, so
  text typed in the terminal shows up in the world.
- `permission.resolved` has `by`: `app` or `external` (answered in the
  terminal).
- `session.notice` tells the user something about a session that isn't an
  agent's state: a `code` (Godot shows its own text for codes it knows)
  and an English fallback `message`. One per code (a new one replaces
  it); the snapshot lists them in `notices`. Codes: `transcripts_off`,
  `hooks_unavailable`. *(Shape accepted by the user, 2026-09-29, to be
  revisited if the world needs more.)*

**Capabilities.** A session declares `capabilities`, keyed by name, each with
its own config object (e.g. `"usage": {}`). A capability's events use its
name as the noun (e.g. `usage.updated`) and are only sent when declared.
Each one is added to the schema and listed here:
- **`questions`**: an agent asks the user clarifying questions, a set of
  1+ items, each with options and optional multi-select (Claude's
  AskUserQuestion). `question.asked` / `question.resolved` (`by`: `app` or
  `external`) and the command `question.answer` (per-item chosen labels or
  typed text, or one free `response` instead). A pending question may also
  show in the provider's own interface (the terminal); whichever side
  answers first wins. Pending ones are in the
  snapshot's `questions`; the agent is `waiting` with reason `question`.
- **`interrupt`**: the user can stop what the session is doing; the session
  stays open. Command `interrupt.request`. Config
  `{ "immediate": true | false }`: `false` means the stop happens at the
  session's next step (e.g. before its next tool call), not mid-reply, so
  Godot can say "stopping after this step".

**Extensions.** A session lists its `extensions` (e.g. `["claude"]`).
Extension messages are `ext.<provider>.<name>` in either direction, carry
`session`/`seq` or `id` like core messages, and are routed in Godot by
prefix to that provider's UI module. Their payload schemas go in
`protocol/ext/<provider>.schema.json`.

## Systems

### W01 Beach island
*Planned (v1).* A static beach island, one per session. In v1 there is
exactly one. Later islands are created and removed dynamically (W04).

### W02 Ocean
*Planned (v1).* The ocean surrounding the islands. Unrelated projects get
their own area of it (W05).

### W03 Player movement
*Planned (v1).* On-foot movement for walking up to agents. Keep it capable
enough to support parkour later; don't make it so plain that it rules parkour out.

### W04 Island rise / sink
*Planned.* A new session makes an island rise out of the ocean; this doubles
as the "new session" feedback. An ended session makes its island sink, and
the island is then removed.

### W05 Archipelagos
*Planned.* Islands of the same project/repo cluster into an archipelago.
Whether that goes strictly by repo path or allows manual naming and arranging is
open question 2.

### W06 Bridges
*Planned.* Walkable bridges connect islands within an archipelago, for
physical movement and the feel of the world. Build it as a general
"connect regions" system, not beach-specific, so that future biomes (hills,
mountains) plug into it.

### W07 Teleport menu
*Planned.* Instantly jumps to a session's island, so you never have to walk
across the world to reach an orchestrator. Sorting, grouping and whether to
add a minimap are open question 3.

*Possible feature, not planned (from Agent Office):* a "go to whoever has
waited longest" shortcut that jumps straight to the agent that has been
waiting longest on a permission or question.

### A01 Orchestrator
*Planned (v1).* A bigger model at the centre of its island, at a beach
desk or under an umbrella (look: open question 7). It's the main way you
interact with a session (see C01).

### A02 Subagents
*Planned (v1).* Small models at little PCs on the island's sand. They
appear when the orchestrator spawns them. When one finishes (`done`), it
runs to the agent that called it (its `parent`) with a paper on its head,
throws the report to it, and disappears. A resumed subagent (back to
`working`) reappears. Chat is orchestrator-only for now; whether to talk to
subagents directly is open question 4.

### A03 Agent state indicators
*Planned.* A visible state on each agent, from the protocol's state enum
(see Protocol): working, waiting on the user (e.g. a permission prompt),
idle (orchestrator), done (subagent) or error.

### A04 Procedural agent placement
*Planned (v1).* Agents are positioned by a simple algorithm (ring, spiral
or grid with jitter) rather than hardcoded spots, and it handles about 20–30 per
island. Nothing may assume a fixed maximum agent count. Options for larger
counts are in Deferred ideas.

### A05 Permission attention cue
*Planned.* A pending permission prompt or question is shown on the
relevant island and agent, so a waiting agent visibly draws your attention.

### C01 Walk up to chat
*Planned (v1).* Walking up to an orchestrator opens the chat panel for its
session.

### C02 Chat panel
*Planned (v1: plain text).* A core feature, not an afterthought, because this
is a working environment. It needs streaming responses. v1 renders plain text
wired to the sidecar.

### C03 Markdown rendering
*Planned. Scope: core* (it renders the generic `message` text). Godot's
`RichTextLabel` uses BBCode, not Markdown, so the chat panel translates.
Prototyped in the M0 spike (`spikes/markdown/`, dev log
2026-09-29-markdown-spike); the user's decisions, verified there:
- **Converted in Godot by our own GDScript**, from the Markdown the
  protocol already carries. No protocol change, no dependency.
- **A message is a stack of controls.** Consecutive prose blocks share one
  RichTextLabel (selection runs across paragraphs); each **code block is
  its own panel**: read-only, monospace, language label, Copy button,
  syntax colours, horizontal scroll instead of wrapping. Quotes nest.
- **Escaping (Security rules).** Every `[` in message text becomes `[lb]`;
  links are `[url=<index>]` into a table, so no message text sits inside a
  tag. Only http(s)/mailto links are clickable, and only after a
  confirmation showing the full address; images are never loaded. Keep the
  spike's fuzz test when building this.
- **Streaming.** Re-parse the whole text after each line batch; keep
  unchanged parts and update the growing one in place (about 2 ms per
  batch). An unclosed code fence shows as a block marked "writing…".

To solve when building: rendering a long history at once is slow (about
80 ms per typical reply, 0.7 s for a 25 KB one, mostly RichTextLabel and
CodeEdit layout), so build history lazily. Gaps and details are in the dev
log.

### C04 Tool-call log
*Planned.* Some form of log of the tool calls the session made, visible from
the chat panel.

### C05 Permission approve / deny
*Planned.* Answer permission requests from inside the world. They are
sent to the sidecar as approve/deny.

### C06 Permission mode control
*Planned (after v1). Scope: capability `permission_modes`* (other tools have
similar approval modes). The user's wish: switch permission modes from the
world. What the CLI route allows (Claude docs, checked 2026-09-29):
- **Choose the mode at launch:** a mode picker when creating or resuming a
  session (`--permission-mode`).
- **Switch while answering a prompt:** "allow, and switch to mode X", like
  the terminal's own "Yes, and switch to auto mode". The `PermissionRequest`
  hook's allow reply carries `updatedPermissions: [{ type: "setMode", mode,
  destination: "session" }]`.
- **Always show the current mode:** every hook carries `permission_mode`,
  so switches made in the terminal (Shift+Tab) show up too.

Not possible: switching at an arbitrary moment with no prompt open (only
Shift+Tab in the terminal; typing keystrokes was rejected). Safety rules:
only on an explicit user choice, `session` destination only (never written
to settings files), current mode always visible with plain descriptions.
Claude Code refuses `setMode` to `bypassPermissions` unless the session was
launched with bypass available, which we never do. Protocol fields are
added when this is built.

### C07 Plan approval
*Planned (after v1). Scope: capability `plans`* (plan modes exist in other
tools too). Approve or reject a plan from the world, as well as in the
terminal. In the terminal, when Claude finishes planning, it shows the plan
and offers: **Yes, and use auto mode** (or "auto-accept edits"), **Yes,
manually approve edits**, and **No, keep planning** (tell Claude what to
change). This runs through Claude's `ExitPlanMode` tool, which Claude Code
treats like `AskUserQuestion` (it needs a person), and hooks receive the
plan's Markdown (`tool_input.plan`). Intended design, the same as for
clarifying questions (S02): the plan shows in both places, the
`PermissionRequest` hook is held, first answer wins. Approve → `allow`
with the input echoed back plus the matching `setMode` (see C06); keep
planning → `deny` with the user's feedback as the message. **Untested:**
needs a short spike before it's built. Rendering the plan depends on C03.

### S01 Sidecar and WebSocket server
*Built (v1). Scope: core.* The sidecar process that hosts the session
registry and the local WebSocket server Godot connects to, and Godot's
client for it. It speaks only the generic protocol; providers plug in
through `sidecar/src/provider.ts`. No provider ships yet (S02 adds Claude),
so on its own it serves an empty world. Dev log 2026-09-29-sidecar-core.

**Sidecar** (`sidecar/src/`, TypeScript on Node 22.21.0, pinned in
`package.json`):
- **Server** (`server.ts`): the Security rules above, all tested: loopback
  only, a new 32-byte token per start (compared in constant time), `Origin`
  refused, `Host` checked, `/` only, 4 MiB message limit.
- **Registry** (`registry.ts`) owns each session's state and `seq`, so a
  snapshot always matches the events sent. Providers report through a
  `SessionHost` (`announce`, `emit`, `end`); every event is checked against
  the schema, the session's declared capabilities and extensions, and its
  state (known agents, pending permissions and questions, `idle` only for
  the orchestrator and `done` only for subagents). Events that don't fit are
  dropped and logged without using up a `seq`, so a provider bug never
  reaches Godot as nonsense or a false gap.
- **Commands** (`commands.ts`): every message from Godot is checked against
  the schema (Ajv) and must be a command. Project paths must be absolute
  existing folders. A session's events are held while a command for it is
  answered, so replies come first. A session exists from `session.create`
  but only appears in snapshots, and accepts commands, once its provider
  announces it (`session_starting` before that); one that never comes up
  still gets `session.ended`. Unexpected provider errors reach Godot as
  `provider_error` without details (those stay in the log).
- **Process** (`serve.ts`, `main.ts`): the startup handshake on stdout,
  logs on stderr (never session content, since Godot may keep them in its
  log files), and exit when stdin closes, which covers Godot quitting or
  crashing on every OS (verified on Windows, including a hard kill of
  Godot). `main.ts` picks the executable's mode; S02 adds the bridge and
  launcher modes.
- **Packaging** (`scripts/`): esbuild bundles to one CommonJS file (Node's
  single-executable feature runs only CommonJS), which is injected into the
  official Node binary for each platform (`win-x64`, `linux-x64`,
  `linux-arm64`, `darwin-x64`, `darwin-arm64`). Other platforms' Node
  binaries are downloaded from nodejs.org, checked against its SHA-256
  list, and cached. `THIRD_PARTY_LICENSES.txt` (bundled packages and Node)
  ships next to the executable. About 86 MB.

**Godot** (`core/sidecar/sidecar_client.gd`, autoload `Sidecar`): starts
the sidecar, reads the handshake in a thread, connects with the token and
raises the inbound buffer to 32 MiB (Godot's default of 64 KiB would drop
a long reply). It tracks `seq` per session: stale events are dropped, and a
gap sends `session.get_snapshot` once. If the connection drops while the
sidecar runs, it reconnects; if the sidecar dies, it reports failure
(`failed` signal). It stops the sidecar by closing the pipe, killing it
only if it hasn't exited after 3 s. stderr is drained continuously so the
sidecar never stalls on a full pipe. On Windows, Godot starts it without a
console window. Which sidecar runs: next to the game executable in exports;
`node sidecar/src/main.ts` in the editor; `-- --sidecar=<path>` or
`-- --sidecar-dev-fake` override it (see Running it).

**Session store** (`core/sessions/session_store.gd`, `SessionStore`,
built with S02): a plain class (no autoload) that the world
creates and `attach`es to the client. It applies every event to its copy
of each session (the protocol's session object, plus the chat so far and a
tool-call log, capped at 2000 messages and 500 calls per session) and emits
fine-grained signals (`session_added` with `created` for the rise
animation, `agent_changed`, `message_changed`, `permissions_changed`,
`questions_changed`, `notices_changed`, ...). Extension messages pass
through untouched (`extension_event`) for the provider's UI module.
`load_history` puts `session.get_history`'s messages before the live ones.
A snapshot (resync) replaces the state but keeps the chat. After a
reconnect, sessions without a snapshot ended meanwhile and are removed;
the client's `sync_started` signal (on `hello`) marks where a reconnect's
snapshots begin. It's the Godot handler for `session.notice`.

Not yet: the sidecar isn't restarted if it dies (sessions it launched keep
running, but the world loses them); export presets that copy the executable
next to the game come with the first export.

### S02 Claude provider
*Built (v1). Scope: core* (a provider; sessions declare the `questions`
and `interrupt` capabilities, no extension yet). Code:
`sidecar/src/providers/claude/` (`index.ts` finds and launches `claude`,
`session.ts` runs one session, `hooks.ts` and `hook-server.ts`, `bridge.ts`
and `bridge-server.ts`, `transcript.ts`) and the generic
`sidecar/src/launch/`. Diagrams: `docs/flows.md`. Dev logs:
2026-09-29-claude-cli-spike, -windows-terminals,
-s02-relay-questions-stop. The only place Claude-specific names may
appear. It drives the user's own installed `claude` (minimum 2.1.284),
signed in with their own account; our code never reads, stores or passes
on Claude credentials, and never modifies or bundles Claude Code.

**Launch.** A terminal window opens through the terminal launcher
(Architecture → Platforms) and starts `claude` in the project folder with:
- `--session-id <uuid>` (it becomes `native_id`) and `--name`, or
  `--resume <id>` for a stored session (S04; the id stays the same);
- `--settings <file>`: our hooks for this session only, so the user's own
  settings files are never edited;
- `--mcp-config` plus `--dangerously-load-development-channels
  server:world-bridge`: our channel. Custom channels need this flag while
  channels are a research preview;
- a **clean environment** (Security rules): inherited session markers make
  `claude` treat itself as nested and stop saving transcripts.

No permission mode is chosen for the user (C06 will let them pick one at
launch); every hook carries `permission_mode`. With the common `auto` mode
Claude Code rarely asks for permission at all.

**Starting up: confirm in the terminal** (user's decision, idea from Agent
Office). Claude Code shows folder trust the first time in a folder, and the
development-channel confirmation **at every launch** (checkpoint 1). Its
bridge only starts after those dialogs, so until it connects we hear
nothing and can't tell why. The `session.create` / `session.resume` reply
carries `notice: confirm_in_terminal` ("Confirm in the Claude Code
terminal to start this session.") for Godot's "starting" placeholder; if
nothing has come up after about two minutes, Godot says "Still starting;
check the terminal" on its own (it knows when it asked). The island is only
created once the session is ready (`session.created`); how the world shows
a session waiting to start is decided when building the game (user's
decision). The session counts as up when the bridge connects, or at its
first hook; it counts as gone if neither happens within 15 min (the user
chose Exit at a dialog).

**Talking to the session: the channel bridge.** A channel is an MCP server
Claude Code starts as a subprocess; ours is the sidecar executable in
`bridge claude` mode (our own few MCP messages, not the SDK; Watch items).
It connects back to the sidecar over loopback with the session's token.
- **Chat:** the world's message is pushed as a channel event wrapped in
  `<channel source="world-bridge" ...>`; Claude treats it as the user's
  and replies normally (no reply tool). The optional `prompt` of
  `session.create` is sent this way once the session is up.
- **Permission relay:** Claude Code sends each permission prompt to the
  bridge (with a five-letter `request_id`) while the terminal shows its
  dialog; a verdict from the world closes that dialog.

**Seeing the session: HTTP hooks** posted to one loopback endpoint per
sidecar (`POST /hook`, a token per session, `Origin` and foreign `Host`
refused, 16 MiB limit), always answered at once with no decision (except
questions and stops, below). Timeouts: 5 s for hooks that only report, 2 s
for `MessageDisplay`, 24 h for the question hook. Translation (Claude Code
2.1.284's payloads, which differ from the docs in places):
- `UserPromptSubmit` → a user message: typed in the terminal, or from the
  world (unwrapped from the channel tag). Two kinds Claude Code injects are
  not user messages (the orchestrator goes back to working): a
  `<task-notification>` when a background task ends (its status ends a
  subagent stopped from the terminal), and a **subagent hand-back**
  `<agent-message from="…">` carrying a subagent's final report. Injected
  prompts reuse the user's `prompt_id`, so it names a message only once.
- `MessageDisplay` → assistant text in batches of whole lines (`delta`
  holds only the new text; the final batch completes the message).
- `PreToolUse` / `PostToolUse` / `PostToolUseFailure` → tool calls, with a
  one-line summary ("Run: npm install", paths relative to the project);
  inputs over 64 KiB aren't forwarded. A call that is never run gets no
  hook of its own (denied, stopped, or a question answered with free
  text), so the sidecar closes it as `denied`.
- `SubagentStart` / `SubagentStop` → subagents. `SubagentStart` doesn't
  name the parent: it's the agent whose `Agent` tool call came just
  before (paired by agent type, oldest first). Subagents run in the
  background by default, so the orchestrator is often `idle` while they
  work. Claude Code's **internal helper agents** fire hooks with no
  `SubagentStart`: anything from an agent never seen starting is ignored.
- `Notification`: `elicitation_dialog`, `elicitation_url_dialog` and
  `agent_needs_input` → `waiting` (reason `input`) until it moves again
  (from the docs; not yet seen live). `permission_prompt` and
  `idle_prompt` add nothing.
- `Stop` → orchestrator `idle` (completing any reply cut short);
  `StopFailure` → `error` with the error type.
- Not registered: `SessionStart` (can't be an HTTP hook) and `SessionEnd`
  (it also fires for `/clear` while `claude` keeps running). A session
  ends when its bridge's connection closes (Claude Code exited).

**Filling the gaps: the transcript.** Esc and a "No" in the terminal fire
no hook, but Claude Code writes them to the transcript within the second.
The sidecar follows the `transcript_path` the hooks name, read-only, from
its end, every 250 ms (moving to the new file after `/clear`): a tool
result with `toolUseResult: "User rejected tool use"` resolves that call's
prompt as denied (by external), and `[Request interrupted by user]` (Esc,
or after a "No") leaves the orchestrator idle, its running calls closed as
interrupted. The line format isn't a documented interface (Watch items),
so it's used for status only; without it, the fallback is the next hook or
message.

**Permissions** (C05's sidecar side). The relayed prompt names no tool
call or agent, so the sidecar ties it to the open call of that tool whose
input the relay's preview shows (else the newest without a prompt),
waiting up to 300 ms for its `PreToolUse` (it arrives on the other
connection about 100 ms earlier). The world gets `permission.requested`
(id = `request_id`) with the right agent, summary and input, and the agent
is `waiting` (reason `permission`). `permission.respond` sends the verdict
down the bridge. Resolved: in the world (`by: app`); "Yes" in the
terminal through the call's `PostToolUse`; "No" through the transcript
(`by: external`); and, as a fallback, when the agent's turn ends or the
user types next. A `note` follows the verdict as the user's next chat
message (user's decision): it arrives before Claude's next step, and
Claude follows it (checkpoint 2). If that ever changes: hold
`PermissionRequest` for plain prompts too and put the note in the deny's
`message`.

**Clarifying questions (`questions` capability).** `PermissionRequest` is
registered for `AskUserQuestion` only and held open while **the terminal
shows the question too**; whichever side answers first wins (spike run 3;
holding `PreToolUse` instead hid it from the terminal, rejected). The
question's id is its `tool_use_id`. Answered in the world: the held hook
returns `allow` with `answers` keyed by question text (a multi-select's
labels joined with ", "), or, for a free reply, a deny carrying the
user's words, which Claude reads as the answer. Answered in the terminal:
its `PostToolUse` arrives and the sidecar releases the held hook
(`by: external`). If Claude Code drops the held hook, or the turn ends,
the question resolves by external.

**Stopping (`interrupt` capability, `immediate: false`).** A stop answers
the next `PreToolUse` of each agent busy when it was asked with
`continue: false` **and** a deny (`continue: false` alone still let the
call run). The stop lands before the next tool call, not mid-reply or
mid-command; the terminal shows "The user stopped this from the app."
No hook follows, so the sidecar sets the states: the orchestrator `idle`,
a subagent `error` with reason `interrupted` (user's decision). Calls
issued in the same batch as the stopped one still arrive, so a stopped
agent's calls are stopped too until a new turn; the user's next turn is
never caught. Pending prompts are denied and held questions declined when
the stop is asked, or they'd block it (user's decision, for now; it never
allows anything). A stop with nothing running does nothing.

**Session notices.** `transcripts_off`: no file at `transcript_path` a
second after the first reply (with `CLAUDE_CODE_SKIP_PROMPT_HISTORY`, hooks
still name a path but nothing is written). `hooks_unavailable`: a world
message sent while the orchestrator is idle brings no hook within 10 s
(most likely the user's `allowedHttpHookUrls`, which makes hooks vanish
with no error; chat still works).

**When transcripts are off (user's decision: Claude Code's setting is the
only control).** We offer no setting of our own and never force saving
back on (e.g. never `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE`);
`cleanupPeriodDays` only shortens how long they're kept. **The world shows
only a short disclaimer** (user's decision), the `transcripts_off`
notice. For development, what's limited:
- **Esc and a terminal "No"** aren't seen until the next hook or message;
  the world labels such states as possibly out of date rather than
  guessing. A world answer to a prompt the terminal already closed is
  dropped by Claude Code, harmlessly.
- **Chat history** is only what the sidecar saw (as always for a session
  started here), and it's lost if the sidecar restarts.
- **Resuming** isn't possible, and the session isn't listed (S04).
- **Attaching** (later) shows nothing from before we joined.

**History.** `session.get_history` returns the completed messages the
sidecar saw through the hooks since launch (for a resumed session, first
what the transcript held), in memory only, at most 5000.

**Fail-safe (verified).** With the hook endpoint hanging, erroring or
offline, Claude Code fell back to its own terminal prompts every time and
nothing was allowed; hooks resume when it comes back.

**Terminal-only on this route.** No documented way exists to do these
from outside, so they stay in the terminal. Typing keystrokes into the
terminal was considered and rejected (dev log 2026-09-29-claude-cli-route).
- An immediate stop (the world's stop lands at the next step; Esc in the
  terminal is immediate).
- Prompts only the terminal shows: folder trust, MCP server consent, the
  development-channel confirmation.
- Built-in slash commands, session-changing ones (`/model`, `/compact`,
  `/clear`, `/permissions`, ...) and screens (`/context`, `/usage`, ...).
  Model, effort, name and permission mode can be chosen at launch
  instead. World messages starting with `/` reach Claude as plain text.
- Switching permission mode with no prompt open (C06 covers switching at
  launch and while answering a prompt).
- Ending the session: `session.end` answers `not_supported` until S05
  decides how; `/exit` in the terminal ends it.

**Known gaps.**
- `/clear` starts a new Claude conversation in the same terminal (new
  session id and transcript): the sidecar follows the new transcript, but
  the world keeps the old chat and `native_id`.
- A subagent's final report isn't sent to the world (no protocol field;
  A02's "throws the report" could use it).
- Parallel spawns of the same agent type may pair with the wrong task.
- Not yet seen live: questions and permission prompts from subagents,
  and the `Notification` waiting cases.

**Verified.** The spike (three runs); checkpoint 1 (launch, chat, `/exit`,
startup dialogs; two Windows terminal bugs fixed); checkpoint 2 with the
user (permissions in both places, a note, all three question kinds, the
stop and its terminal wording, Esc before and during a reply, a terminal
"No", history, `/exit`); and `claude -p` probes, which need no channel
(hook translation with real payloads, the stop's batch behaviour,
transcripts off, `allowedHttpHookUrls`, `--resume`).

### S03 Create session
*Planned.* A "create new session" command from Godot; the sidecar launches
a `claude` terminal (see S02). Attaching to sessions the user started
themselves comes later (open question 5, decided); it uses the same hooks
and channel, which such a session would need to be started with.

### S04 List and resume sessions
*Planned (after v1).* Claude Code stores transcripts as JSONL under
`~/.claude/projects/<project-slug>/<session-id>.jsonl`, resumable with
`claude --resume <id>`. Sessions launched from this app are ordinary CLI
sessions in the same store, so they are resumable from a terminal, and old
CLI sessions can be listed and resumed here (launched with `--resume`).
The Claude desktop app's own sessions also write transcripts there; whether
they should be listed and resumed here is to check when building S04 (see
Deliberate limitations). Sessions run with transcripts off leave nothing to
list or resume (S02 → When transcripts are off), and Claude Code deletes
transcripts after `cleanupPeriodDays` (30 by default), so the list only
reaches that far back.
*Sidecar side built with S02 (the world's list and resume UI come later;
a resume from the world hasn't been run live yet, only `--resume` itself
with `claude -p`):* `providers/claude/store.ts` lists
`<CLAUDE_CONFIG_DIR or ~/.claude>/projects/*/<uuid>.jsonl`, newest first
(at most 200), reading only each file's first and last 64 KiB: project
from `cwd`, title from the newest `custom-title` (our `--name`, or a
`/rename`) else the first user message, `updated_at` from the file time.
Transcripts record where a session was started (`entrypoint`: `cli`,
`sdk-cli`, `claude-vscode`, `claude-desktop`); only `cli` ones are listed
for now (user's decision, 2026-09-29); VS Code and desktop sessions are
possible later. Sessions running here are
left out and can't be resumed twice. `session.resume` launches `claude
--resume <id>` in the session's project folder with our hooks and channel
(refused with a readable error if the session or its folder is gone), and
its chat so far is read from the transcript: user messages (typed, or from
the world: those are stored with `isMeta`, so they're recognised by our
channel tag) and the text of Claude's replies; tool calls, thinking,
subagents and injected context are left out. Also: `session.create`'s
optional `prompt` is now sent as world chat once the session is up.
Probed with two `claude -p` runs (2.1.284): `--resume <id>` keeps the
session id (our `native_id`) and writes on in the same transcript, the
resumed session remembers the earlier turns, and the history reader reads
all four messages back. `claude -p` sessions are stored as `sdk-cli`, so
they aren't listed.

### S05 End session
*Planned.* Ending a session removes it from the registry and sinks its
island (W04). Claude Code offers no documented way to close a session from
outside, so until S05 decides how, `session.end` gets `not_supported` for
Claude sessions (user's decision, S02); `/exit` in the terminal still ends
a session and sinks its island (its channel bridge closes).

## Conventions

- **A new feature** first gets its provider scope decided (core, capability
  or extension; see Multi-provider rules), stated in its Systems section. If
  it's unclear, ask the user.
- **A new event type** needs: its scope (core, capability name, or
  extension namespace), a schema entry in `protocol/`, a line in the Protocol
  section, the provider translation in the sidecar, and a Godot handler (in
  the provider's UI module if it's an extension).
- **A new asset** needs a row in `assets/CREDITS.md` (source, author,
  license). CC0 or made by the user only; never AI-generated.
- **Provider-specific code** stays in its provider module (sidecar) or UI
  module (Godot); anything shared is named generically.
- **Privacy in git.** The repo will be public. Never commit secrets,
  session logs, tokens or machine-specific paths; spike logs and run files
  are git-ignored for that reason. Commit author emails are the user's
  normal address, public by choice (dev log 2026-09-29-privacy-check).
- **License.** The project is MIT (`LICENSE`). Third-party parts keep their
  own licenses: `addons/godot_ai/` (MIT, its own `LICENSE`) and the assets in
  `assets/CREDITS.md`. Don't add code or dependencies whose license forbids
  redistribution in an MIT project.

### Renaming the project

"The Beach" is a codename. It appears in:
- `project.godot`: `config/name` (also the window title)
- `README.md`: title
- `NOTES.md`: title
- `CLAUDE.md`: codename rule
- `docs/GUIDE.md`: title
- `docs/devlog/`: past entries (historical; leave them)

It must not appear in code identifiers, class names, the protocol or package
names. Add to this list if it ever has to appear anywhere new.

## Running it

There's no world yet (the first scene comes with W01), but the sidecar
and Godot's client run. Needs Node **22.21.0** (pinned; packaging refuses
any other version) and Godot 4.7.2.

In `sidecar/`:
- `npm ci` once, then `npm test` (all suites) and `npm run typecheck`.
- `npm run dev:fake`: the sidecar with a scripted fake provider, for
  building the world without Claude. Chat drives it: a message containing
  `permission`, `question`, `agents [n]` or `notice` acts out that part of
  a session (a prompt to answer, a question, n background subagents, a
  notice); anything else is echoed back. A stop from the world ends what's
  running. `test/dev-fake.test.ts` plays every scenario.
- `npm run try:claude -- <empty folder>`: the sidecar with the real Claude
  provider, driven like Godot would. It opens a terminal with `claude`
  (confirm the development channel there), prints every event with the
  time since launch, and sends each typed line as world chat. Lines
  starting with `/` act like the world's buttons: `/allow` and `/deny` (a
  permission; the latest unless an id is given; text after it is sent as
  a note), `/answer <label>` (a
  question; `A|B` for multi-select), `/reply <text>` (free answer),
  `/stop`, `/history`. Use a neutrally named folder: Claude once guessed
  this repo's path from a test folder's name and wrote there.
- `npm run build`: the bundle, `dist/sidecar.cjs`. To run the process tests
  against it or a packaged executable, set `SIDECAR_CMD` to a JSON array,
  e.g. `SIDECAR_CMD='["dist/win-x64/sidecar.exe"]' node --test test/process.test.ts`.
- `npm run package` (this platform) or `npm run package -- --target
  linux-x64` (downloads that platform's Node once): `dist/<target>/`.
  macOS executables must be signed on a Mac before they run
  (`codesign --sign -`; see Watch items → Code signing).

In Godot, the `Sidecar` autoload starts the sidecar from source (`node`
must be on PATH). Godot's command line after `--` can change that:
`--sidecar-dev-fake` (the fake provider) or `--sidecar=<path>` (a packaged
executable). Headless smoke test, from the repo root:

```
godot --headless --path . --script res://tests/core/sidecar_client_test.gd
godot --headless --path . --script res://tests/core/sidecar_client_test.gd -- --sidecar-dev-fake
godot --headless --path . --script res://tests/core/session_store_test.gd -- --sidecar-dev-fake
```

**Godot AI (dev tool).** The `addons/godot_ai` editor plugin
([hi-godot/godot-ai](https://github.com/hi-godot/godot-ai), MIT) lets Claude
Code drive the open editor. It needs [uv](https://docs.astral.sh/uv/) (the
client runs a Python bridge through `uvx`). Chain: Claude Code → `godot-ai
attach` (stdio) → local Python server (authenticated HTTP, port 8000) → editor
plugin (authenticated WebSocket, port 9500, loopback only). Per machine:
- Set Editor Settings → Plugins → `godot_ai/mcp_client_scope` to `local`,
  then press **Configure** next to Claude Code in the Godot AI dock. The
  client entry pins versions and machine paths, so it isn't tracked in the repo.
  Without the `claude` CLI on PATH, Configure can only write **user** scope
  (`~/.claude.json` → `mcpServers`); move the `godot-ai` entry by hand into
  `projects["<repo path>"].mcpServers`, which is what local scope is. Recheck
  after plugin updates, since they re-pin the entry.
- Telemetry off: set Editor Settings → Plugins → `godot_ai/telemetry_enabled`
  to off, and the user environment variable `GODOT_AI_DISABLE_TELEMETRY=true`.
  Apps only see a new environment variable after they restart, and Godot
  launched from Godot Hub inherits the Hub's environment, so restart the Hub.
- Update with the dock's **Update** button, never by copying files over it.
- Port clash: the server's HTTP port (default 8000) is often taken on
  Windows by Docker or WSL. Change Editor Settings → Plugins → `godot_ai`
  → Http Port (or the dock's port picker), and the `--port` in the client
  entry to match (Configure rewrites it); restart Claude Code to reconnect.

## Open questions

1. ~~**Event schema.**~~ *Decided:* version 1 is in Protocol and
   `protocol/events.schema.json`.
2. **Archipelago clustering.** Strictly by repo path, or can projects be
   manually named or arranged?
3. **Teleport menu UX.** Sorted or grouped how (project, recency, custom
   pinning)? Is a minimap still wanted for on-foot travel alongside it?
4. **Subagent chat.** Chat with subagents directly, or keep them read-only
   status for now (orchestrator-only chat, as currently designed)?
5. ~~**Session ownership.**~~ *Decided (user's):* both, eventually. v1 only
   launches sessions from inside the app; attaching to sessions already
   running elsewhere comes later. The event schema must allow for attaching
   (joining a session partway through) even though v1 doesn't use it.
6. ~~**Sidecar language.**~~ *Decided (user's):* TypeScript on Node. Chosen
   while the Agent SDK was the plan (its TypeScript version is the more
   complete one). It still fits the CLI route: channels are MCP servers and
   Anthropic's channel examples use the TypeScript MCP SDK.
7. **Agent look and branding.** The agents were planned as "logo" models
   (the AI tool's logo on a little PC). Anthropic's terms don't allow using
   their logos in a product without permission (Watch items → Claude
   branding), so a public release needs an original look. Decide before
   modelling the agents (A01, A02).
8. **The M1 world's feel** (W01, W02, W03, A01, C01, C02). To settle
   before building them; my recommendations (2026-09-29), for the user
   to decide when M1 starts:
   - *Camera:* third person, orbiting with the mouse, over the shoulder
     (you see your character for parkour later, and the agents around
     you).
   - *Movement:* `CharacterBody3D` with walk, sprint and jump from the
     start, plus coyote time and jump buffering (keeps parkour possible).
   - *Island:* a generated low-poly mesh (code, so it can grow and change
     per session later), dressed with Kenney props.
   - *Ocean:* a flat-shaded low-poly water shader with gentle waves.
   - *Props:* Kenney Pirate Kit (CC0, 70 models, including islands, boats
     and characters), plus Nature Kit and Furniture Kit if they fit.
   - *Orchestrator:* a plain placeholder at a desk until question 7 is
     settled.
   - *Opening the chat:* walk close, "Press E to chat" appears, E opens the
     panel and frees the mouse, Esc closes it.
   - *Chat panel:* a screen-space panel on the right, with the world
     still visible and running behind it.

## Known issues and next steps

**Current focus:** M1. S01 and S02 are built (S02 passed both review
checkpoints, the second a live run with the user); S02's branches merge to
`main` with the user's approval. Next is the M1 world (W01, W02, W03, A01,
C01, C02), which needs the user's calls on camera, movement, island,
ocean, props and the chat panel first (open question 8).

*Handoff (2026-09-30).* The sidecar side of v1 is done: the Claude
provider (S02), S04's list and resume, the scripted `dev:fake` for
building the world without `claude`, and Godot's `SessionStore`, the data
layer the world and chat panel will read. 139 `node:test` checks and 3
Godot headless tests. `try:claude` drives a real session like the world
would (NOTES → Running it). Parts can be checked against a real `claude`
without the user through `claude -p` (dev log
2026-09-29-s02-relay-questions-stop).

**Checkpoint 1 passed (2026-09-29)** with `npm run try:claude -- <empty
folder>` from `sidecar/`: a Windows Terminal tab opened with `claude`, a
world message reached Claude and it replied, `/exit` ended the session,
and the transcript was written under `~/.claude/projects/` with our
session ID (so no session markers were inherited). Startup prompts are in
S02 → Starting up. It first failed on two Windows terminal bugs, now fixed
(dev log 2026-09-29-windows-terminals).

**Checkpoint 2 passed (2026-09-29)**, a live run with the user at the
terminal (Claude Code 2.1.284, Windows, the session in default permission
mode, since the user's usual `auto` mode asks for nothing): a prompt
reached the world 0.2 s after its tool call and was allowed there (the
terminal dialog closed); a deny with a note stopped Claude before its next
command; single-choice, multi-select and free-text answers from the world
all reached Claude; a stop from the world denied the next call and nothing
ran after it; Esc during a reply and "No" in the terminal reached the
world through the transcript; history was complete; `/exit` ended the
session. One gap found and fixed: a question answered with free text left
its tool call open (Claude Code sends no hook for it). Re-checked in a
second session: the stop (the terminal shows "The user stopped this from
the app."), Esc before any output and mid-reply (after 23 streamed
batches; the partial message is completed), and "No" on a dialog.

**Next:** the M1 world (see Current focus).

### Milestones

**M0 Setup.** Docs and scaffold, event schema, and two throwaway spikes:
- **Claude CLI integration spike (S02).** *Done 2026-09-29, three runs
  against a real `claude`: launch, hooks, channel chat, permission relay,
  questions in both places, stopping, Esc and "No" via the transcript, and
  fail-safe behaviour. Results in S02 and the dev log
  (2026-09-29-claude-cli-spike); code in `spikes/claude-cli/`.*
- **Markdown → BBCode spike (C03).** *Done 2026-09-29: parser and view in
  GDScript, safe escaping (fuzz-tested), code-block panels, streaming by
  line batches. Results in C03 and the dev log (2026-09-29-markdown-spike);
  code in `spikes/markdown/`.*

**M1 v1 slice.** The goal is to prove the Godot ↔ sidecar ↔ `claude` CLI pipeline
end-to-end with the generic vocabulary, even though only the Claude provider
exists.
- One archipelago, one island, one orchestrator (W01, W02, A01).
- Sidecar launches one `claude` CLI session in a terminal, turns its hook
  events into generic events over WebSocket, and relays chat and permission
  answers through a channel (S01, S02). Built for all three platforms
  (terminal launcher, packaged sidecar, Godot starting it), tested on
  Windows.
- Walk up to chat with a plain-text chat panel wired to the sidecar (W03, C01,
  C02).
- Subagents as simple placeholder models with ring or spiral placement,
  appearing and disappearing on spawn and finish events (A02, A04).
- Permission prompts and questions can still be answered in the terminal
  in v1; answering them in the world is C05 and the `questions` capability.
- Not in v1: bridges, teleport menu, multiple islands or archipelagos,
  minigames and parkour, Markdown polish, any second provider.

**After v1.** The remaining features in the index. They are not ordered yet.

### Deferred ideas (not features yet)

- **Token usage and cost** (a `usage` capability). Recipe from Agent Office:
  every assistant entry in the transcript records the API's token usage and
  model, subagent transcripts sit next to it, and Claude Code appends its
  own cost total when a session ends, which is the figure to trust. Read
  only, like the rest of the transcript (S02). Not available when
  transcripts are off.
- **Agent scaling**, only if agent counts become a problem:
  - *Island growth:* the island footprint grows, or subdivides into a
    mini-archipelago, past some agent count.
  - *LOD / culling:* far or long-idle agents collapse into a simple
    stand-in (stacked PCs, a counter badge) and expand when approached or
    clicked. This is the route to "unlimited" agents.
  - *Overflow structure:* a "server rack" building stands for "N more agents
    working" and can be clicked to list them.
- **Other biomes:** hills, mountains, joined by the same bridge system (W06).
- **Minigames and parkour** for downtime. Which ones, where they are and how
  they unlock are all undecided on purpose.
- **Commands from the world** (probably a capability). Skills and custom
  commands could be sent through as requests, since Claude can run most
  skills itself (not guaranteed; skills marked user-only won't run that
  way; untested). Built-ins with a launch-time equivalent could be offered
  at session creation or resume. Other built-ins stay terminal-only (S02),
  and the world should say so instead of sending them to Claude as text.

### Watch items

- **Anthropic's terms (public release).** The app is meant for free public
  release (maybe donations later). Per Claude Code's legal and compliance
  docs (checked 2026-09-29): third parties may not offer claude.ai login,
  route requests through Free/Pro/Max credentials, or collect, store or
  intermediate Claude credentials; this doesn't prevent a user signing in
  to the **unmodified** Claude Code binary with their own subscription.
  Hence the CLI route (S02): each user installs and signs in to Claude Code
  themselves; we never bundle, modify or authenticate it. Recheck the terms
  before each release; for certainty, ask Anthropic (the page points to
  their sales contact).
- **Claude branding.** Same page: a product may say in plain text that it
  runs Claude Code, but may not use the Claude Code or Anthropic names or
  logos in its own name or logo, or suggest Anthropic built or endorses it.
  Other use of their logos needs written permission. This affects the "logo
  model" agents (A01, A02) in a public release.
- **Hook URL allowlists.** If a user's or organisation's settings define
  `allowedHttpHookUrls`, our HTTP hooks only run if their URL is on it. The
  sidecar should detect missing hook events and explain this.
- **Own MCP code in the bridge.** *Decided (user's, S02):* the channel
  bridge speaks the few MCP messages it needs itself instead of using the
  official MCP SDK, which pulls in 94 packages, including a web server we
  don't use. **Re-evaluate** (user's instruction) whenever the bridge's MCP
  handling grows: if we keep adding to it, switch to the SDK rather than
  re-implement what Anthropic already maintains.
  *MCP's 2026-07-28 revision* drops the `initialize` handshake and lets a
  server send notifications only inside a request or a client-opened
  subscription, which is how channel messages would have to travel. The
  bridge speaks the older handshake, exactly like the official SDK (1.31.0,
  up to 2025-11-25), and Claude Code 2.1.284 falls back to it. Recheck on
  Claude Code updates: if it stops accepting older servers, or channels
  move to subscriptions, adopt the SDK once it supports the new revision.
- **Transcript format.** Esc and terminal "No" are only visible in the
  transcript, whose line format isn't a documented interface. It is used
  for status only, parsed defensively, and re-checked on Claude Code
  updates; if it changes, the world falls back to inferring from the next
  event.
- **Channels are a research preview.** Chat and permission answers from the
  world depend on them (S02). Flags and protocol may change, custom channels
  need `--dangerously-load-development-channels` (confirmed by the user at
  startup), and Team/Enterprise organisations block channels unless an
  admin enables them. Pro/Max users without an organisation can use them.
- **Markdown → BBCode rendering (C03)** was the biggest UX risk. The
  spike shows it works; what's left is the cost of rendering long
  histories at once (see C03).
- **Untested on macOS and Linux.** Everything verified so far (S02, C03)
  ran on Windows 11 only, and only Windows is available to test on. The
  launch flow (terminal launcher, finding `claude`, the channel
  confirmation) must be checked on a real Mac and a Linux desktop before a
  release claims them; until then, say so in the README.
- **Code signing (public release).** macOS blocks apps that aren't signed
  and notarized (Gatekeeper), which needs an Apple Developer account (99
  USD a year); unsigned Windows apps get a SmartScreen warning. Both apply
  to the Godot export and the sidecar executable, and matter most for
  itch.io's browser downloads. Decide before the first public release.
  The sidecar is a Node binary with our script injected, which breaks
  Node's own signature (Windows: "signature seems corrupted"; macOS: won't
  run until re-signed, which needs a Mac). Release builds should strip it
  and sign with ours (S01).
- **Large chat histories.** `session.get_history` answers in one message;
  Godot's client accepts up to 32 MiB (S01). A very long session could
  exceed that; paging the history is the fix if it happens.
- **Steam (likely, not certain).** The user plans to ship on Steam
  (depots per OS, updates through SteamPipe; the bundled sidecar ships as
  ordinary game files). Things to check before relying on it:
  - *Linux sandboxing:* native Linux games may run inside the Steam Linux
    Runtime container, and Flatpak installs of Steam are sandboxed; either
    may stop the game from seeing or starting the user's terminal and
    `claude`. Needs a test; if it does, the Linux build is offered on
    itch.io only.
  - *Environment:* Steam's variables and overlay hooks must not reach the
    launched terminal and `claude` (Security rules → Clean child
    environments).
  - *Proton:* Steam must not run the Windows build through Proton on
    Linux (it would try to start Windows programs); ship the native Linux
    build.
  - *AI disclosure:* Steam's content survey asks about AI, including
    live-generated content shown in the game; Claude's replies probably
    count, and the answer must describe our safeguards.
  - *Signing:* games installed by Steam don't trigger SmartScreen; check
    Valve's current macOS signing and notarization requirements (see Code
    signing).
  - *Steam features* (achievements, overlay) are optional; they'd need a
    GDExtension with builds for all three platforms (e.g. GodotSteam).
  - *Testing:* nothing Steam-specific is needed while building. Valve
    reviews the build and store page before release (it launches, matches
    the page), and Steam Deck Verified is optional. The risks above are
    tested by installing a build from a private Steam branch on each OS,
    which needs a Steamworks account (one-time fee per app); the Linux
    runtime part can be tried earlier, since that runtime is free.
- **itch.io (certain).** The game will be offered on itch.io, uploaded
  per OS with itch's `butler` tool (patch updates; the itch app updates
  players automatically). Nothing itch-specific is needed to build for
  it, but browser downloads differ from Steam installs:
  - *Signing matters more:* downloaded files carry the browser's
    "from the internet" mark, so unsigned Windows builds get SmartScreen's
    warning and un-notarized macOS builds are blocked by Gatekeeper until
    the user allows them in System Settings (see Code signing).
  - *Executable permissions:* macOS and Linux builds, including the
    sidecar executable, must keep their executable flag. `butler` and the
    itch app keep it; a zip unpacked by hand may not, so the game should
    check the sidecar's flag at start and restore it or explain.
  - *Linux:* a plain download runs outside Steam's sandboxing, so itch.io
    is the fallback home for the Linux build if Steam's sandboxing blocks
    launching the terminal and `claude`.
- **`icon.svg`** is Godot's default icon (CC BY 4.0, not CC0). It is a
  placeholder to replace.
- **Before making the repo public:** re-run the history scan for secrets,
  personal data and machine paths (dev log 2026-09-29-privacy-check).
- **Godot AI plugin:** its auth doesn't protect against a compromised process
  running as the same user, and on Windows it claims no isolation from other
  local accounts (per its security model). Telemetry is on by default
  upstream; we opt out per machine.

### Deliberate limitations

- **No Claude desktop app integration.** The desktop app runs its own
  sessions with its own session list, and offers no supported way for us to
  launch into it or watch its sessions. It does interoperate with the CLI
  (docs, checked 2026-09-29): `/resume` in the desktop app picks up CLI
  sessions, including ones this app launched, and `/desktop` in a terminal
  moves a CLI session into the desktop app and exits the CLI (which ends
  our link to it). Its sessions also write transcripts under
  `~/.claude/projects/`. The CLI and that store are our integration point.
- **No Agent SDK (not in the near future).** Driving Claude through the
  Agent SDK gives more control (an immediate stop, word-by-word streaming,
  no terminal window), but Anthropic's terms expect SDK apps to use an API key
  (billed per token) rather than the user's subscription. We use the CLI
  route instead (S02). Revisit only if Anthropic confirms subscription use
  is fine for this kind of app, or an API-key option is wanted.
- **Claude is the only provider.** Near-term effort goes into making Claude
  good; the architecture stays open for more providers.
- **No WSL in v1 (user's decision).** On Windows, only a native Windows
  `claude` is supported. Claude Code inside WSL keeps its transcripts,
  hooks and channel bridge on the Linux side of the WSL boundary, which is
  a separate project. If no native `claude` is found, the world says that
  native Windows Claude Code is required. Revisit after v1.
