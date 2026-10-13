# 15. A session back with its hook port taken (limited)

[All diagrams](../../flows.md)

> **Status:** Built (S07). NOTES.md → S07 → If the old port is taken.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
        participant Relay as Relay (our executable)
        participant Bridge as Bridge (in Claude Code)
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
        participant Log as Transcript
    end

    Note over Sidecar: Taken back (flow 14), but another program has its hook port:<br/>relay.json and status.json now name our new port, with its old token.
    Sidecar->>World: session.snapshot (capabilities: usage and model_info only;<br/>notices: reattached_limited#59; found late: a session.notice right after)
    Claude-xSidecar: HTTP hooks: to the program on the old port, never us<br/>(any posted to us with its token are that program's: dropped)
    User->>World: a message
    World->>Sidecar: message.send
    Sidecar->>Bridge: chat
    Sidecar-->>World: ok
    Bridge->>Claude: the message (channel)
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Log: providers/claude/transcript.ts (followAll)<br/>providers/claude/transcript-hooks.ts (TranscriptHooks)<br/>providers/claude/session.ts (searchTranscript, limitedSwitch)
        opt no transcript yet (nothing prompted before the restart)
            loop every second for a minute, then every 10 s, until written
                Sidecar->>Log: look for it (findStored: this project's working folder only)
            end
            Note over Sidecar: found: read from its start
        end
        loop every 250 ms
            Sidecar->>Log: read new entries (and new subagents' files)
        end
        Log->>Sidecar: the user's message → as UserPromptSubmit
        Sidecar->>World: message.started, message.completed (user), agent.state_changed working
        Log->>Sidecar: a reply → as MessageDisplay, whole
        Sidecar->>World: message.started, message.completed (no deltas)
        Log->>Sidecar: a tool_use → as PreToolUse
        Sidecar->>World: tool.started
    end
    Claude->>Bridge: a permission prompt (relay)
    Bridge->>Sidecar: permission_request
    Note over Sidecar: tied only to the call whose input its preview shows<br/>(a cut-short preview waits the full 1 s);<br/>none by then: shown from the preview
    Sidecar->>World: permission.requested (no options), agent.state_changed waiting
    User->>World: Yes or No
    World->>Sidecar: permission.respond
    Sidecar->>Bridge: verdict
    Sidecar-->>World: ok
    Log->>Sidecar: tool_result → as PostToolUse
    Sidecar->>World: tool.finished
    Log->>Sidecar: turn_duration → as Stop
    Sidecar->>World: agent.state_changed idle
    opt /clear or /resume
        Claude->>Relay: SessionStart
        Relay->>Sidecar: POST /hook (relay.json: the new port)
        Note over Sidecar: followed as usual (flow 9) once its transcript folder is known<br/>(the program on the old port has the token too)#59; before that, only to<br/>this project's transcript: /resume at once, /clear once written
    end
```

**What still works:** chat from the world, Yes and No on permission
prompts (the channel's relay), `/clear` and `/resume` followed, token
usage and the model (the status line relay). **From the transcript, a
moment late:** the user's messages, replies (whole, not streamed), tool
calls and subagents (each from its own file under
`<session>/subagents/`, tied to its Agent call by its `.meta.json`), the
turn's end (Claude Code's `turn_duration` entry), Esc and a terminal
"No". A session busy at the restart stays working until then. One with
no transcript yet at the restart has it looked for (every second for a
minute, then every 10 s; only a file with this project's working
folder) until Claude Code writes it, and read from its start.

**Left to the terminal:** prompt options, questions, plans, the current
mode, the stop (`interrupt.request` gets `not_supported`), sign-in
notices and the `hooks_unavailable` check. Subagents already running at
the restart aren't shown. Ending the session with `/exit` and resuming
it from the world gives it everything again.

**The program on the old port** gets the session's hooks, token and tool
input included, and could answer them (NOTES.md → Security rules → Known
gap). Hooks posted to our new port with the session's token can only
come from it, so they're dropped (a forged prompt gets an empty answer:
neither shown nor allowed); only what the two relays post is taken
there, `SessionStart` (`/hook`) and the status line (`/status`). A
`/clear` or `/resume` is followed only into the project's transcript
folder once that's known, and before that only to a transcript of this
project that Claude Code wrote (a `/resume`'s at once, a `/clear`'s once
written), so that program can't switch the world to another project's
conversation.
