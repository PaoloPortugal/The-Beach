# 2. A chat turn

[All diagrams](../../flows.md)

> **Status:** Built (S02, C02; tool calls in between: C04). NOTES.md → S02, C02.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
        participant Bridge
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
    end

    User->>World: types a message at the orchestrator
    World->>Sidecar: message.send
    Sidecar-->>World: ok
    Sidecar->>Bridge: chat text
    Bridge->>Claude: channel event
    Claude->>Sidecar: UserPromptSubmit (text wrapped in a channel tag)
    Sidecar-->>Claude: nothing to add
    Sidecar->>World: message.started / .completed (role user, unwrapped)
    Sidecar->>World: agent.state_changed orchestrator → working
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/hooks.ts (translation)<br/>Godot: chat/message_bubble.gd, chat_panel.gd
        loop each batch of finished lines
            Claude->>Sidecar: MessageDisplay (message_id, delta, final)
            Sidecar-->>Claude: empty reply, instantly
            Sidecar->>World: message.started (first batch), message.delta,<br/>message.completed (final batch: the full text)
        end
    end
    Claude->>Sidecar: Stop
    Sidecar-->>Claude: nothing to add
    Sidecar->>World: orchestrator → idle (and completes any reply<br/>whose final batch never came)
```

A message typed in the terminal arrives the same way, as plain text
without the channel tag. A `<task-notification>` or subagent hand-back
prompt is not a user message (see [flow 5](05-subagent.md)). Tool calls in between are
`tool.started` / `tool.finished` ([flow 5](05-subagent.md) shows them); the world files
each under the latest message, folded into one line (C04).

**Titles** (NOTES.md → S02 → Titles). While the session has no name, the
first user message's line names it: a `session.updated` (title) along
with its `message.completed`. Claude Code's own title (`ai-title`) and a
`/rename` (`custom-title`) come as transcript lines the sidecar follows;
each change of the title shown is another `session.updated` (title).
