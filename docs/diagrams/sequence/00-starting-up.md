# 0. Starting up

[All diagrams](../../flows.md)

> **Status:** Built (S01, S07). NOTES.md → S01, S07 and Architecture → Security rules.

```mermaid
sequenceDiagram
    autonumber

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
    end

    rect rgba(255,193,7,0.18)
        Note over World,Sidecar: sidecar/src/serve.ts (handshake), server.ts (the checks)<br/>Godot: core/sidecar/sidecar_client.gd
        World->>Sidecar: start it (argument list, pipe for stdin/stdout/stderr)
        Sidecar->>Sidecar: take back sessions still running (S07, flow 14)
        Sidecar->>Sidecar: new random token, listen on 127.0.0.1 (free port)
        Sidecar->>World: stdout: one line {ready, protocol, port, token}
        World->>Sidecar: WebSocket connect, Authorization: Bearer token
        Sidecar-->>World: accepted (no Origin, right Host and token)
    end
    Sidecar->>World: hello (protocol version, providers,<br/>each with its launch_options, C12)
    loop each live session
        Sidecar->>World: session.snapshot
    end
    Sidecar->>World: sync.completed
    Note over World,Sidecar: From here on: commands up, events down.<br/>Every command's reply comes before the events it causes.
    alt the connection drops, the sidecar still runs
        World->>Sidecar: connect again with the same token
        Sidecar->>World: hello, snapshots, sync.completed
    else the game quits or crashes
        Note over World,Sidecar: The pipe closes#59; the sidecar exits.<br/>Sessions it launched keep running in their terminals<br/>and come back at the next start (flow 14).
    end
```

Until the first `sync.completed` (or a failure, or 30 s) the world is
covered (`world/loading_cover.gd`), so islands of sessions taken back
are standing from the first frame (S07).

A connection without the token, with an `Origin` header (any web page), or
with the wrong `Host` is refused before it starts. Events whose `seq` a
snapshot already covered are ignored; a gap in `seq` makes the world ask
for `session.get_snapshot`.
