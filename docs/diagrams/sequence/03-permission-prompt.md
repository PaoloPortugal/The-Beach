# 3. A permission prompt

[All diagrams](../../flows.md)

> **Status:** Built (S02, C05). NOTES.md → S02, C05.

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
        participant Log as Transcript
    end

    Claude->>Sidecar: PreToolUse (e.g. Bash)
    Sidecar-->>Claude: empty reply (no decision)
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/hooks.ts (pairs the prompt with its call)<br/>bridge-server.ts (the relayed request)
        par Claude Code asks in both places
            Claude->>User: permission dialog in the terminal
        and
            Claude->>Bridge: permission request (request ID, tool, input preview)
            Bridge->>Sidecar: permission request
        and
            Claude->>Sidecar: PermissionRequest (permission_suggestions)
        end
        Note over Sidecar: Tied only to the open tool call whose input the preview shows<br/>(its agent, summary, input)#59; waits for that call's PreToolUse<br/>and PermissionRequest, in either order, up to 1 s#59; no such call by then:<br/>shown as the orchestrator's, from the preview.
        opt the prompt has no options (flow 11)
            Sidecar-->>Claude: reply to PermissionRequest: no decision (the terminal asks as usual)
        end
        Sidecar->>World: permission.requested (ID = request ID, asked_at = now,<br/>options if any), agent → waiting (permission)
    end
    alt answered in the world
        User->>World: Yes or No
        World->>Sidecar: permission.respond
        Sidecar-->>World: ok
        Sidecar->>Bridge: verdict (request ID)
        Bridge->>Claude: verdict: terminal dialog closes
        Sidecar->>World: permission.resolved (by app)<br/>(deny: also tool.finished denied, since no hook comes for it)
        Note over Claude: A deny from the world lets Claude continue its turn.
    else allowed in the terminal
        User->>Claude: allow
        Claude->>Sidecar: PostToolUse for that call
        Sidecar-->>Claude: nothing to add
        Sidecar->>World: permission.resolved (by external)
    else "No" in the terminal
        User->>Claude: No
        Note over Claude: No hook fires: the turn is interrupted silently.
        Claude->>Log: "User rejected tool use", then "interrupted"
        Log->>Sidecar: new lines (the sidecar follows the file)
        Sidecar->>World: permission.resolved (by external), agent → idle
    end
```

In the world, "Yes or No" and "picks options or types an answer"
([flow 4](04-clarifying-question.md)) happen on the card in the chat panel (NOTES.md → C05): one
request at a time, oldest first; it moves on when `permission.resolved`
or `question.resolved` arrives, whichever side answered.

Picking one of the prompt's other options goes through its held hook
instead ([flow 11](11-prompt-options.md)). If a prompt still has a held hook when its call ends
(`tool.finished`), the hook is let go with nothing to add.

The "No" line names the call's `tool_use_id`, so the sidecar resolves that
exact prompt and closes the call as `denied`. When transcripts are off, a
terminal "No" is only noticed when the orchestrator's turn ends or the user
sends the next message: its prompts resolve as deny, by external. A
subagent's prompt resolves when that subagent stops.
