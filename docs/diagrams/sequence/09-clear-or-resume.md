# 9. /clear or /resume: another conversation in the session

[All diagrams](../../flows.md)

> **Status:** Built (S02). NOTES.md → S02 → Following the conversation.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
        participant Relay as Relay (our executable)
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
        participant Log as Transcript
    end

    User->>Claude: /clear (or /resume an earlier conversation)
    Note over Claude: Same process, same folder, same bridge:<br/>another session id and its transcript.
    rect rgba(255,193,7,0.18)
        Note over Relay,Claude: launch/relay.ts: exec form, no shell, always exits 0
        Claude->>Relay: SessionStart (source clear or resume, the new session_id):<br/>a command hook, exec form, no shell#59; JSON on stdin
        Relay->>Sidecar: POST /hook with the session's token (from the relay file)
    end
    Sidecar->>Log: poll the followed transcript: no continued-in
    Note over Sidecar: Our token, a UUID, a transcript in the same folder:<br/>followed. native_id switches#59; the old id becomes stored (resumable).
    alt source resume
        Sidecar->>Log: read the resumed transcript's chat (slash commands left out)<br/>and tool calls
        Note over Sidecar: that chat becomes the session's history
        Sidecar->>World: session.updated (native_id, title if it changed), session.notice (conversation_resumed)
    else source clear
        Note over Sidecar: the history starts empty
        Sidecar->>World: session.updated (native_id, title null if it had one), session.notice (conversation_cleared)
    end
    Sidecar-->>Relay: nothing to add
    Relay-->>Claude: exit 0, nothing on stdout
    Note over Claude: /resume waited for the hook (at most 5 s)#59;<br/>/clear didn't.
    World->>Sidecar: session.get_history
    Sidecar-->>World: ok (the history): replaces the world's chat
    User->>Claude: next message (typed in the terminal or sent from the world)
    Sidecar->>World: the turn as usual (flow 2), from the new transcript too
```

The island stays. After `/clear` the world's chat window clears, and
the notice says the earlier conversation can be brought back with
`/resume`; after `/resume` the chat becomes the
resumed conversation's (NOTES.md → S02 → Following the conversation).

**If the relay fails** (it always exits 0, so Claude Code carries on),
the world learns of the switch at the new conversation's first hook
instead: a `UserPromptSubmit` with the new `session_id` goes through the
same checks, and it counts as `/resume` if the new transcript holds a
reply from Claude, else `/clear`.

**A moved conversation.** If the followed transcript gets a
`continued-in` entry instead (the conversation went on in another
session, which agent view used to do), the sidecar sends
`session.notice` (`conversation_moved`) and ignores the new session's
hooks: the terminal handles everything. From then on `message.send`,
`permission.respond` and `interrupt.request` get `error`
(`provider_error`, "This conversation moved to another Claude Code
session; continue it in the terminal."). Separately, whenever the bridge
isn't connected, `message.send` and `permission.respond` get
`provider_error` saying the world can't reach the conversation right
now, rather than losing the message.
