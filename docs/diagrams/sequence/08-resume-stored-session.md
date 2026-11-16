# 8. Resuming a stored session (S04)

[All diagrams](../../flows.md)

> **Status:** Built (S04, C12). NOTES.md → S04, S02 → Model, effort and mode at launch.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Store as Transcripts
        participant Agents as claude agents --json
        participant Claude as Claude Code (terminal)
    end

    User->>World: hold Tab, click the ring's +, Resume a session…<br/>(only this page asks)
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Store: providers/claude/store.ts (read-only), running.ts
        World->>Sidecar: session.list_stored (optionally one project)
        Sidecar->>Agents: which sessions run on this machine? (meanwhile;<br/>argument list, clean environment, 5 s at most)
        Agents-->>Sidecar: the ids of live sessions with a process<br/>(if it can't tell, e.g. agent view off, nothing is left out)
        Store->>Sidecar: each new or changed file's first and last 64 KiB<br/>(read-only, in the background): folder, where it started, name,<br/>first message. Unchanged ones (same size and time) come from the cache
        Sidecar-->>World: ok { sessions } (terminal sessions, newest first,<br/>none that are running here<br/>or that Claude Code says run in another terminal)
    end
    User->>World: pick one
    World->>Sidecar: session.resume (native_id, launch: model, effort, mode picked)
    Sidecar->>Agents: still running in a terminal?
    Agents-->>Sidecar: the live sessions' ids
    opt it still runs
        Sidecar-->>World: error provider_error, reason still_running ("still running in a<br/>terminal ... type /exit in it"); nothing opens, and it stops here
    end

    Store->>Sidecar: its whole transcript: the chat and tool calls so far<br/>(subagents' calls from their own transcripts)
    Sidecar->>Claude: open a terminal with our launcher: claude --resume <id><br/>in the session's folder, with our hooks and channel<br/>(and --model / --effort / --permission-mode if picked)
    Sidecar-->>World: ok { session }
    Note over Claude,Sidecar: From here it's flow 1: the confirmation, the bridge<br/>connects, session.created. The session keeps its id.
    World->>Sidecar: session.get_history
    Sidecar-->>World: ok { messages, tools } (the earlier chat and tool calls,<br/>then what's new)
```

The Resume page has the same Model, Effort and Mode choices as Add a
session (C12); a choice not offered in `hello`'s `launch_options` is
refused before anything opens. Resumed without a model picked, Claude
Code restores the conversation's own model and fires `PostModelSwitch`
(source `resume`), which the sidecar reads for the chat header; with
`--model` it fires none (NOTES.md → S02 → Model, effort and mode at
launch).
