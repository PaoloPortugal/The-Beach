# 16. Sessions started outside the game (read-only)

[All diagrams](../../flows.md)

> **Status:** Built (S08). NOTES.md → S08, Protocol → Provider capabilities and notices, C10.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal, desktop app, IDE)
        participant Agents as claude agents --json
        participant Log as Transcript
    end

    User->>Claude: starts a session outside the game
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Log: providers/claude/index.ts (restore, poll, outsideFrom)<br/>providers/claude/running.ts (parseAgents, agentViewOff)<br/>providers/claude/store.ts (findTranscript)
        Note over Sidecar: at start (part of the restore, before sync.completed, so W12<br/>brings its island back standing), then the shared poll:<br/>every 5 s with the game focused, 10 s in the background
        Sidecar->>Agents: which sessions run?
        Agents-->>Sidecar: each: sessionId, pid, status, cwd, kind, startedAt, name
        Note over Sidecar: left out: the game's own (its run folders' pids, its session ids),<br/>no live pid, no cwd or a folder that isn't there
        Sidecar->>Log: its transcript (this cwd's only): entrypoint?
        alt entrypoint sdk-cli (claude -p, an Agent SDK program)
            Note over Sidecar: never shown
        else no transcript yet (not at start, nor just after turning it on)
            Note over Sidecar: wait one listing (a claude -p writes it at once)
        else a terminal, the desktop app, an IDE, a background session
            Sidecar->>World: session.snapshot (session.created just after turning it on)<br/>origin external, read_only: true, notices: outside_read_only
        end
    end
    Note over World: the island in its repository's cluster, with the grey flag#59;<br/>chat: "Read-only: use its own window."
    Note over Sidecar,Log: from here as a read-only session of S07's (flow 15):<br/>chat, tool calls, subagents and usage from the transcript,<br/>waiting, /clear and /resume from claude agents
    User->>Claude: chats, answers, stops it (only there)
    opt it exits
        Sidecar->>Agents: which sessions run?
        Agents-->>Sidecar: its pid no longer listed
        Sidecar->>World: session.ended exited (the island sinks)
        Note over World: W12 keeps its entry until the next start#59; its app relaunching it<br/>(same session id) finds it: it rises with its biome and seed
    end
    opt the player turns it off (Settings → Game)
        World->>Sidecar: client.set_outside_sessions false
        Sidecar-->>World: ok
        Sidecar->>World: session.ended user, each (islands sink, W12 forgets them)
        Note over World: W12 also forgets those kept after they went (forget_outside)
        Note over Sidecar: stops asking, unless S07's read-only sessions need it#59;<br/>at the next start: serve --no-outside-sessions, and claude isn't asked<br/>unless a session of the game's own is to be taken back
    end
    opt turned on again
        World->>Sidecar: client.set_outside_sessions true
        Sidecar-->>World: ok
        Sidecar->>Agents: which sessions run? (at once)
        Agents-->>Sidecar: the list
        Sidecar->>World: session.created, each (islands rise, as new ones)
    end
    opt agent view is off
        Sidecar->>Agents: which sessions run?
        Agents-->>Sidecar: refused: "… is disabled by …"
        Sidecar->>World: provider.notice outside_sessions_off (once#59; in hello afterwards)
        Note over Sidecar: outside sessions end#59; no more looking this launch
        Note over World: Settings: the toggle greyed out, shown off, the notice in red#59;<br/>the saved choice kept
    end
```

**Which sessions:** every live one Claude Code lists except `claude -p`
runs and Agent SDK programs: terminals, the Claude desktop app, IDEs,
and background sessions still working or blocked. Not finished
background sessions. A session held by a second copy of the game is
shown read-only here too.

**Not from the world:** chat, answers to prompts, questions and plans,
and the stop, as in flow 15. Nothing of the session is written by
the sidecar: no run folder, no hook token (the game's `islands.json`
keeps its island, W12).
