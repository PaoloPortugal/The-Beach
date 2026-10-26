# 0. Starting up

[All diagrams](../../flows.md)

> **Status:** Built (S01, S07, S08, S02, C14). NOTES.md → S01, S07, S08, S02 → The program set by hand, C14, Protocol and Architecture → Security rules.

```mermaid
sequenceDiagram
    autonumber

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
    end

    rect rgba(255,193,7,0.18)
        Note over World,Sidecar: sidecar/src/serve.ts (handshake), server.ts (the checks)<br/>Godot: core/sidecar/sidecar_client.gd
        World->>Sidecar: start it (argument list, pipe for stdin/stdout/stderr#59;<br/>serve --no-outside-sessions if the player turned them off, S08#59;<br/>--program-path provider=path for each program set by hand, S02)
        Sidecar->>Sidecar: check each program set by hand, or start looking for it<br/>in the background (S02, flow 17)<br/>take back sessions still running (S07, flow 14)<br/>and find those started outside the game (S08, flow 16)
        Sidecar->>Sidecar: new random token, listen on 127.0.0.1 (free port)
        Sidecar->>World: stdout: one line {ready, protocol, port, token}
        World->>Sidecar: WebSocket connect, Authorization: Bearer token
        Sidecar-->>World: accepted (no Origin, right Host and token)
    end
    Sidecar->>World: hello (protocol version, providers,<br/>each with its launch_options, C12,<br/>its own capabilities and notices, S08,<br/>and the program it found, once it has looked, S02)
    loop each live session
        Sidecar->>World: session.snapshot
    end
    Sidecar->>World: sync.completed
    opt the game's window isn't focused
        World->>Sidecar: client.set_focus false (and on every change after)
    end
    World->>Sidecar: client.set_outside_sessions (the setting, S08: a change<br/>lost while reconnecting comes through#59; no change is ignored)
    Note over World,Sidecar: From here on: commands up, events down.<br/>Every command's reply comes before the events it causes.
    alt the connection drops, the sidecar still runs
        World->>Sidecar: connect again with the same token
        Sidecar->>World: hello, snapshots, sync.completed
    else the game quits or crashes
        Note over World,Sidecar: The pipe closes#59; the sidecar exits.<br/>Sessions it launched keep running in their terminals<br/>and come back at the next start (flow 14).
    end
```

Meanwhile the game shows the main menu over the world (C14; S07's
loading cover before it, now unused), and Play isn't held back for
the sync. Islands of sessions taken back wait for the first
`sync.completed`, then come back as they were, from the game's
`islands.json` (W12, [flow 14](14-reattach-after-restart.md)), rising
behind the menu once each one's ground is made on a worker thread.

A connection without the token, with an `Origin` header (any web page), or
with the wrong `Host` is refused before it starts. Events whose `seq` a
snapshot already covered are ignored; a gap in `seq` makes the world ask
for `session.get_snapshot`.
