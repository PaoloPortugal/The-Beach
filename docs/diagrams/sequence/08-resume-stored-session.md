# 8. Resuming a stored session (S04)

[All diagrams](../../flows.md)

> **Status:** Built (S04). NOTES.md → S04.

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
        Note over Sidecar,Store: providers/claude/store.ts (read-only)
        World->>Sidecar: session.list_stored (optionally one project)
        Sidecar->>Agents: which sessions run on this machine? (meanwhile;<br/>argument list, clean environment, 5 s at most)
        Agents-->>Sidecar: the live sessions' ids (none if agent view is off)
        Store->>Sidecar: each new or changed file's first and last 64 KiB<br/>(read-only, in the background): folder, where it started, name,<br/>first message. Unchanged ones (same size and time) come from the cache
        Sidecar-->>World: ok { sessions } (terminal sessions, newest first,<br/>none that are running here<br/>or that Claude Code says run in another terminal)
    end
    User->>World: pick one
    World->>Sidecar: session.resume (native_id)
    Sidecar->>Agents: still running in a terminal?
    Agents-->>Sidecar: the live sessions' ids
    Note over World,Sidecar: If it runs: error provider_error ("still running in a<br/>terminal ... type /exit in it") and nothing opens

    Store->>Sidecar: its whole transcript: the chat and tool calls so far<br/>(subagents' calls from their own transcripts)
    Sidecar->>Claude: open a terminal with our launcher: claude --resume <id><br/>in the session's folder, with our hooks and channel
    Sidecar-->>World: ok { session }
    Note over Claude,Sidecar: From here it's flow 1: the confirmation, the bridge<br/>connects, session.created. The session keeps its id.
    World->>Sidecar: session.get_history
    Sidecar-->>World: ok { messages, tools } (the earlier chat and tool calls,<br/>then what's new)
```
