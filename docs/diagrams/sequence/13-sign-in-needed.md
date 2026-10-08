# 13. Sign-in needed

[All diagrams](../../flows.md)

> **Status:** Built (S06, S02). NOTES.md → S06; S02 → Seeing the session.

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
    Claude->>Sidecar: UserPromptSubmit
    Sidecar-->>Claude: nothing to add
    Sidecar->>World: message.started / .completed (role user),<br/>orchestrator → working
    Note over Claude: The API call fails: the login expired or was signed out<br/>(401), the account is on hold, billing, ...
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/hooks.ts (SIGN_IN_ERRORS)<br/>Godot: chat/chat_panel.gd, agents/state_marker.gd,<br/>agents/attention_beacon.gd, world/attention.gd
        Claude->>Sidecar: StopFailure (error "authentication_failed")
        Sidecar-->>Claude: nothing to add
        alt an account error
            Sidecar->>World: session.notice sign_in_needed, unless the same one is up<br/>(the provider's message: "… run /login in its terminal.")
            Sidecar->>World: agent.state_changed orchestrator → waiting (sign_in)
            Note over World: The chat shows the notice as sent and "Waiting for you<br/>to sign in, in the terminal."; the "!", beacon and count show.
        else any other error
            Sidecar->>World: agent.state_changed orchestrator → error<br/>(its type if generic, else unknown)
            Note over World: The chat says what stopped the turn, else "Stopped."
        end
    end
    User->>Claude: /login (signs in, in the terminal only)
    alt Claude Code reports it
        Claude->>Sidecar: Notification (auth_success)
        Sidecar-->>Claude: nothing to add
    else the next call goes through
        User->>World: sends again
        Note over World,Claude: Steps 2 to 8 again, then
        Claude->>Sidecar: PreToolUse or Stop
        Sidecar-->>Claude: nothing to add
    end
    Sidecar->>World: session.notice_cleared sign_in_needed (once)
    Sidecar->>World: orchestrator → idle (if it was still waiting on sign_in)
```

The world never handles a login: it only says where to sort it out
(NOTES.md → Principles). `auth_success` comes from the docs and hasn't
been seen live yet, so a call going through also clears the notice.
Failing again the same way keeps the notice that is up; another account
error replaces its text.

**A message that never arrives.** Without a working account Claude Code
may drop a channel message unseen (seen with an invalid API key): steps
4 and 5 happen, but no `UserPromptSubmit` follows, so nothing comes back.
The world's chat panel watches each message it sends while the
orchestrator isn't busy; if no user message arrives (and the
orchestrator doesn't start working) within 15 s, it says the message
hasn't reached the session and puts the text back in the box (once:
when the box is empty, else on reopening the chat with it empty). If a
user message arrives after all, the warning goes, and so does that text
if the box still holds just it.
