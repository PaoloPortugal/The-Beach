# 11. A prompt's other options (C05, C06)

[All diagrams](../../flows.md)

> **Status:** Built (C05, C06). NOTES.md → S02 → Prompt options.

The terminal's prompts offer more than Yes and No ("Yes, and don't ask
again for: npm test \*", "Yes, and switch to auto mode", ...). The world
offers the ones it can (NOTES.md → S02 → Prompt options).

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

    Claude->>Sidecar: PreToolUse (e.g. Bash#59; permission_mode)
    Sidecar-->>Claude: empty reply (no decision)
    par Claude Code asks in both places
        Claude->>User: permission dialog in the terminal (its own options)
    and
        Claude->>Bridge: permission request
        Bridge->>Sidecar: permission request
    and
        Claude->>Sidecar: PermissionRequest (permission_suggestions)
    end
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/prompt-options.ts (which options)<br/>session.ts (holds the hook)
        Note over Sidecar: prompt-options.ts keeps the suggestions that allow<br/>no more than the terminal ("suggested"), and adds<br/>"Yes, and switch to auto mode" ("auto") on Bash in<br/>Manual or Accept edits once auto was seen.
        Note over Sidecar: Options left: the PermissionRequest hook is held open.<br/>None: it's answered at once, and this is flow 3.
    end
    Sidecar->>World: permission.requested (options: [{option, label, kind?, parts?}, ...])
    Note over World: each option ours by its kind, translated, its parts word for word<br/>(SidecarText, C16 step 6)#59; without a kind, its label as it is
    alt an option picked in the world
        User->>World: e.g. "Yes, and don't ask again for: npm --version"
        World->>Sidecar: permission.respond (allow, option)
        Sidecar-->>World: ok
        Sidecar-->>Claude: reply to the held hook: allow, the input echoed back,<br/>updatedPermissions = the option's entries as Claude Code suggested them
        Note over Claude: Claude Code writes the rule or switches the mode itself.<br/>The terminal's dialog and the relayed request close themselves.
        Sidecar->>World: permission.resolved (by app)
        Claude->>Sidecar: PostToolUse (permission_mode: maybe changed)
        Sidecar-->>Claude: nothing to add
        Sidecar->>World: session.updated (mode, if it changed), tool.finished
    else Yes or No, in the world or the terminal
        Note over Sidecar: As in flow 3 (Yes or No from the world goes<br/>through the bridge). When the call ends (tool.finished),<br/>the held hook is let go with nothing to add.
    end
```

If the held hook is gone (Claude Code stopped waiting on it) or the
option isn't one of the prompt's, an answer with an option gets `error`
(`provider_error`, "This prompt can't be answered that way right
now. Answer Yes or No, or answer in the terminal."). A prompt already
shown without options (its hook came after the 1 s wait) keeps none.
