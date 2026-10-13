# 12. Token usage: the transcript and the status line relay

[All diagrams](../../flows.md)

> **Status:** Built (C08, S02). NOTES.md → C08 Token usage.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
        participant Relay as Relay (our executable, statusline mode)
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
        participant Shell as Its shell (Git Bash, PowerShell or sh)
        participant Log as Transcript
    end

    Note over Sidecar: Launch (flow 1): read, never write, the user's settings<br/>and the project's .claude/settings(.local).json
    alt none sets a status line, and every path can be made safe
        Note over Sidecar: --settings also sets statusLine: our executable's path,<br/>statusline, the relay file's path (no session data)
    else the user's own status line, or an unsafe path
        Note over Sidecar: no status line of ours: the transcript's figures only
    end
    User->>Claude: a message (typed, or from the world: flow 2)
    Sidecar->>World: message.started (user), usage.updated (a new turn, 0 tokens)
    loop each API call
        Claude->>Log: assistant entries, each with its call's usage (one message id)
        Sidecar->>Log: follow: count each message id once (subagents' left out)
        Sidecar->>World: usage.updated (totals, context, the turn's output tokens)
        rect rgba(255,193,7,0.18)
            Note over Shell,Relay: launch/shell-command.ts (the command string)<br/>launch/relay.ts (prints nothing, gives up after 2 s, always exits 0)
            Claude->>Shell: run the status line (debounced 300 ms):<br/>the one command string through a shell#59; JSON on stdin
            Shell->>Relay: our executable, statusline, the relay file
            Relay->>Sidecar: POST /status with the session's token (from the relay file)
            Sidecar-->>Relay: 200, nothing
            Relay-->>Claude: exit 0, nothing on stdout: the terminal's status row stays empty
        end
        Note over Sidecar: only for the followed conversation (session_id):<br/>context_window (% and size), rate_limits (5-hour, weekly)<br/>as limits five_hour (5-hour) and seven_day (Weekly), the last of each kept
        Sidecar->>World: usage.updated (context %, the plan's limits as a list), if they changed
        Sidecar->>World: session.updated (model, effort: model.id and effort.level, C12), if they changed
    end
    Note over World: the header: context and totals#59; the turn's hint at its end#59;<br/>the plan's limits in the corner (a line per provider, the latest of each id<br/>across its sessions, by its label, in its order)
```

**History.** `session.get_history` gives each user message its turn's
output tokens (`turn_tokens`), and the snapshot has the session's
`usage`, so a reopened chat or a reconnect shows the same figures. A
resumed conversation is counted from its transcript (flow 8, flow 9);
`/clear` starts the counts over and keeps the plan's limits.

**If the relay fails** (it always exits 0, prints nothing and gives up
after 2 s), Claude Code carries on and the world keeps the transcript's
figures and the last status line figures it had. A limit whose reset
time has passed is hidden in the world.

**The one exception to "No shell strings"** (NOTES.md → Security
rules): Claude Code runs a status line only through a shell. The
command string holds only our own fixed paths and the mode word, as
unquoted short paths on Windows (the same in Git Bash and PowerShell)
and POSIX single quotes elsewhere. It goes as soon as Claude Code can
run a status line without a shell (NOTES.md → Watch items).

**Model and effort** (C12): the same status line input carries
`model.id` and `effort.level`; the sidecar sends them as `session.updated`
for the chat header. Without our status line, the model comes from
`SessionStart` and `PostModelSwitch`, the effort from the orchestrator's
hooks (NOTES.md → S02 → Model, effort and mode at launch).
