# 10. A plan to approve (C07)

[All diagrams](../../flows.md)

> **Status:** Built (C07, S02). NOTES.md → S02 → Permission modes and plans, C07.

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
        participant Log as Transcript
    end

    Note over Claude: In plan mode, Claude presents its plan.
    Claude->>Sidecar: PreToolUse ExitPlanMode (the plan's Markdown in its input)
    Sidecar-->>Claude: nothing to add
    Sidecar->>World: message.started + message.completed (kind plan, id tool_use_id:plan),<br/>tool.started (Present the plan)
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/session.ts holds the ExitPlanMode hook open
        par Claude Code asks, and we hold the plan open
            Claude->>User: the plan and its choices in the terminal
        and
            Claude->>Sidecar: PermissionRequest ExitPlanMode (held open)
            Sidecar->>World: plan.asked (modes in the terminal's order, asked_at = now),<br/>agent → waiting (plan)
        end
    end
    alt approved in the world
        User->>World: Yes, and use auto mode (or another Yes)
        World->>Sidecar: plan.answer (approve, mode)
        Sidecar-->>World: ok
        Sidecar-->>Claude: reply to the held hook: allow, the plan's input echoed back,<br/>setMode (that mode, this session only)
        Note over Claude: The terminal's dialog closes#59; the mode switches.
        Sidecar->>World: plan.resolved (approved, by app), agent → working
        Claude->>Sidecar: PostToolUse ExitPlanMode (permission_mode: the new mode)
        Sidecar-->>Claude: nothing to add
        Sidecar->>World: session.updated (mode), tool.finished ok
    else sent back from the world
        User->>World: No, keep planning (and a note)
        World->>Sidecar: plan.answer (approve: false, note)
        Sidecar-->>World: ok
        Sidecar-->>Claude: reply to the held hook: deny with the note<br/>(or "The user wants to keep planning…")
        Sidecar->>World: plan.resolved (rejected, by app),<br/>tool.finished denied (no hook comes for it)
        Note over Claude: Claude plans again, still in plan mode.
    else approved in the terminal
        User->>Claude: Yes (in a mode)
        Claude->>Sidecar: PostToolUse ExitPlanMode
        Sidecar-->>Claude: nothing to add
        Sidecar->>World: session.updated (mode), plan.resolved (approved, by external),<br/>tool.finished ok
        Sidecar-->>Claude: reply to the held hook: nothing to add<br/>(Claude Code no longer waits on it)
    else "No, keep planning" in the terminal
        User->>Claude: No, and what to change
        Claude->>Log: the refusal
        Log->>Sidecar: new lines (the sidecar follows the file)
        Sidecar->>World: plan.resolved (rejected, by external)
        Sidecar-->>Claude: reply to the held hook: nothing to add
    end
```

Plans have no channel relay, so the held hook is the only way to answer
one from the world (NOTES.md → S02 → Permission modes and plans). The
plan's message stays in the chat whatever the answer; the card in the
chat panel (NOTES.md → C07) goes when `plan.resolved` arrives, whichever
side answered. A terminal "No" is also caught by the turn ending (for
example with transcripts off). If Claude Code drops the held hook
(`claude` exited), the plan resolves as rejected, by external. A stop
from the world sends held plans back.
