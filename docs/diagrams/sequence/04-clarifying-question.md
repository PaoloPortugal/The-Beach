# 4. A clarifying question

[All diagrams](../../flows.md)

> **Status:** Built (S02, C05). NOTES.md → S02, C05.

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
    end

    Claude->>Sidecar: PreToolUse AskUserQuestion
    Sidecar-->>Claude: nothing to add
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/session.ts holds the hook open (hook-server.ts)
        par Claude Code asks, and we hold the question open
            Claude->>User: question in the terminal
        and
            Claude->>Sidecar: PermissionRequest AskUserQuestion (held open)
            Sidecar->>World: question.asked (asked_at = now), agent → waiting (question)
        end
    end
    alt answered in the world
        User->>World: picks options or types an answer
        World->>Sidecar: question.answer
        Sidecar-->>World: ok
        Sidecar-->>Claude: reply to the held hook: allow + answers
        Note over Claude: The terminal's question closes as answered.
        Sidecar->>World: question.resolved (by app)
    else answered in the terminal
        User->>Claude: answer
        Claude->>Sidecar: PostToolUse AskUserQuestion (with the answer)
        Sidecar-->>Claude: nothing to add
        Sidecar-->>Claude: reply to the held hook: nothing to add<br/>(Claude Code no longer waits on it, so the sidecar tidies up)
        Sidecar->>World: question.resolved (by external)
    end
```

A free-text `response` from the world is sent as a deny carrying the
user's words. If Claude Code drops the held hook (it timed out, or
`claude` exited), or the turn ends with the question open (Esc), the
question resolves by external.
