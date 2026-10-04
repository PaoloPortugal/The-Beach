# 7. When our side fails

[All diagrams](../../flows.md)

> **Status:** Built and verified for hanging, erroring and offline hooks (S02). NOTES.md → Architecture → Security rules → Fail safe.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant Sidecar
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
    end

    Claude->>Sidecar: any hook
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: Claude Code's own behaviour#59; our hook settings and timeouts: providers/claude/hooks.ts
        alt sidecar hangs
            Note over Claude,Sidecar: No reply: Claude Code waits for the hook's timeout<br/>(keep reporting hooks short)
        else sidecar errors
            Sidecar-->>Claude: error
            Note over Claude: Treated as "no decision", immediately
        else sidecar offline
            Note over Claude,Sidecar: Connection refused: treated as "no decision", immediately
        end
    end
    Claude->>User: normal behaviour: the terminal asks
    Note over User,Claude: Nothing is ever allowed because our side failed.<br/>Hooks resume when the sidecar comes back.
```

If the user's settings only allow other hook URLs (`allowedHttpHookUrls`),
no hook ever arrives and nothing reports an error. The sidecar notices when
a world message sent while the orchestrator is idle brings no hook within
10 s, and sends `session.notice` (`hooks_unavailable`); chat still works
through the bridge.
