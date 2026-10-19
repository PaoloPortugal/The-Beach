# 15. A session back with its hook port taken (read-only)

[All diagrams](../../flows.md)

> **Status:** Built (S07). NOTES.md → S07 → If the old port is taken.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
        participant Agents as claude agents --json
        participant Log as Transcript
    end

    Note over Sidecar: Taken back (flow 14), but another program has its hook port:<br/>its hook token, bridge and relay files aren't taken (anything<br/>posted with its token: 401)
    Sidecar->>World: session.snapshot (read_only: true#59; capabilities: permission_modes,<br/>usage and model_info#59; notices: reattached_read_only)
    Note over World: no message box: "Read-only: use its terminal."
    Claude-xSidecar: HTTP hooks: to the program on the old port, never us<br/>(Claude Code waits on each until it answers or times out)
    User->>Claude: types, answers its prompts
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Log: providers/claude/transcript.ts (followAll)<br/>providers/claude/transcript-hooks.ts (TranscriptHooks)<br/>providers/claude/session.ts (searchTranscript, onAgent)<br/>providers/claude/index.ts (askWatched)
        opt no transcript yet (nothing prompted before the restart)
            loop every second for a minute, then every 10 s, until written
                Sidecar->>Log: look for it (findOwn: this project's working folder only)
            end
            Note over Sidecar: found: read from its start
        end
        loop every 250 ms
            Sidecar->>Log: read new entries (and new subagents' files)
        end
        Log->>Sidecar: the user's message → as UserPromptSubmit (and its permissionMode)
        Sidecar->>World: message.started, message.completed (user), agent.state_changed working
        Log->>Sidecar: a reply → as MessageDisplay, whole (and its model)
        Sidecar->>World: message.started, message.completed (no deltas), session.updated model
        Log->>Sidecar: a tool_use → as PreToolUse
        Sidecar->>World: tool.started
        loop every 5 s, one at a time for every read-only session
            Sidecar->>Agents: which conversation, and what status, for its claude pid?
            Agents-->>Sidecar: sessionId, status
        end
        Note over Sidecar: status waiting (a prompt in the terminal): agent waiting, reason input#59;<br/>busy or idle again: back to working or idle
        Sidecar->>World: agent.state_changed waiting
        Log->>Sidecar: tool_result → as PostToolUse
        Sidecar->>World: tool.finished
        Log->>Sidecar: turn_duration → as Stop
        Sidecar->>World: agent.state_changed idle
        opt /clear or /resume in the terminal
            Agents-->>Sidecar: another sessionId
            Note over Sidecar: switched once this project's transcript of it is there:<br/>new when first seen (/clear): all of it news#59; else (/resume):<br/>from its end, its past the history#59; another project's: never found
            Sidecar->>World: session.updated native_id, session.notice
        end
    end
```

**Shown, a moment late, from the transcript:** your messages, its
replies (whole, not streamed), tool calls and subagents (each from its
own file under `<session>/subagents/`, tied to its Agent call by its
`.meta.json`), the turn's end (Claude Code's `turn_duration` entry), Esc
and a terminal "No", the permission mode (its `permission-mode` entries
and each prompt's `permissionMode`), the model (each reply's), and token
usage and context (no percent or account limits: those need the status
line). A session busy at the restart stays working until then. One with
no transcript yet at the restart has it looked for (every second for a
minute, then every 10 s; only a file with this project's working folder)
until Claude Code writes it, and read from its start.

**Shown from `claude agents --json`** (every 5 s, one call for all
read-only sessions, only while there are any): waiting on the user in
the terminal, and `/clear` and `/resume`. With agent view off, neither.

**Not from the world:** chat (`message.send` gets `not_supported`),
answers to prompts, questions and plans, and the stop
(`interrupt.request` gets `not_supported`). Subagents already running at
the restart aren't shown. Ending the session with `/exit` and resuming
it from the world gives it everything again.

**The program on the old port** gets the session's hooks, token and tool
input included, and could answer them (NOTES.md → Security rules → Known
gap). The world takes nothing from it: the session's token isn't
accepted on our port, and its relays and bridge are left pointing where
they were.
