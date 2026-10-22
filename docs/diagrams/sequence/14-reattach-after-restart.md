# 14. Coming back after a restart

[All diagrams](../../flows.md)

> **Status:** Built (S07, W12). NOTES.md → S07 Reattach to running
> sessions, W12 Islands kept across restarts.

```mermaid
sequenceDiagram
    autonumber

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
        participant Bridge as Bridge (in Claude Code)
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as Claude Code (terminal)
        participant Log as Transcript
    end

    Note over Claude,Bridge: Launched by the last game, still running.<br/>Its run folder (app data, agent-sessions/) holds session.json,<br/>the launcher's and claude's process ids, bridge.json, holder.pid.
    World->>Sidecar: start it (flow 0)#59; the world stays covered (LoadingCover)
    rect rgba(255,193,7,0.18)
        Note over World,Claude: sidecar/src/serve.ts (restoreSessions, at most 8 s), providers/claude/index.ts (restore, takeOver), run-folder.ts<br/>world/session_islands.gd (_on_synced), world/island_memory.gd, world/session_clusters.gd (restore)
        Sidecar->>Sidecar: hook server on the kept port (hook-port.json), first thing
        Sidecar->>Sidecar: list agent-sessions/: skip folders whose holder is alive (another game),<br/>delete those whose launcher exited, check every field of session.json
        Sidecar->>Claude: claude agents --json
        Claude-->>Sidecar: the running sessions: id, process id, busy / waiting / idle
        Note over Sidecar: Ours if its launcher is alive and Claude Code lists its process<br/>(launcher alone when agents can't answer). Not listed: folder deleted.
        Sidecar->>Log: read the conversation so far (chat, tool calls, usage, titles)
        Sidecar->>Sidecar: accept its old hook token#59; write holder.pid (ours now),<br/>relay.json and status.json (our hook port, its old token),<br/>and bridge.json (our bridge port, a fresh one-time token and proof)<br/>all before it's adopted: a file it can't write leaves nothing half taken<br/>(its hooks on another port than ours: only holder.pid, read-only, flow 15)
        Sidecar->>World: stdout ready, then hello
        Sidecar->>World: session.snapshot (in Claude Code's state, its chat, started_at = its launch time)
        Note over World: Its island waits (W12): the sync's snapshots aren't all in.
        Sidecar->>World: sync.completed
        World->>World: look each up in user://islands.json, read at start<br/>(keyed by provider, started_at, project path)
        World->>World: place the waiting islands: saved ones by slot, then index,<br/>each with its biome, seed and cluster (gaps closed)#59; then any with nothing saved
        World->>World: bridge each to its nearest (W06), in that order
        World->>World: rewrite islands.json: entries of sessions that didn't come back dropped
    end
    Note over World: The cover lifts: its island is standing (no rise).
    World->>Sidecar: session.get_history
    Sidecar-->>World: ok (the conversation so far)
    loop every 2 s while not connected
        Bridge->>Bridge: read bridge.json (a token not tried yet#59; each is tried once)
    end
    Bridge->>Sidecar: connect, hello with the token
    Sidecar-->>Bridge: welcome with the proof
    Note over Bridge: The proof must match its bridge.json's (constant time):<br/>any other program on the port is dropped.
    Note over Sidecar: From now on the bridge closing says Claude Code exited<br/>(until then, its launcher exiting does).
    Claude->>Sidecar: hooks as before, to the kept port with the old token
    Note over World,Claude: Chat, prompts and questions work from the world again (flows 2 to 13).
```

**The session's state** comes from `claude agents --json` (busy is
working, waiting is waiting for input, idle) until its next hook says
otherwise. A prompt or question open at the restart stays in the
terminal: its held hook died with the old sidecar, and Claude Code fell
back to its own dialog.

**`/clear` or `/resume` while the game was closed:** Claude Code lists
the session under its new id, which the world follows, and the run
folder's record is rewritten with it.

**The kept port taken** (another program got it while the game was
closed): the sidecar listens on another port, the session comes back
anyway, read-only, with the `reattached_read_only` notice: none of
its hooks, relays or bridge is taken, and it's seen from its transcript
and `claude agents` (flow 15).

**Its island (W12):** the game keeps each island's biome, seed, cluster
and spot in `user://islands.json`, written as islands are placed and
sessions end. A missing or damaged file, or a session with no entry,
gives a new island as before. A session found after the restore wait
arrives after `sync.completed`, when its entry was already dropped:
it comes back as a new island (NOTES.md → W12, Open points).

**When nothing comes back:** a folder whose session ended is deleted,
one that can't be read is left alone, and a restore that fails or takes
longer than 8 s never stops the start (the world shows what's there; a
session found later arrives on its own as a `session.snapshot`).
The cover lifts on the first `sync.completed`, the sidecar failing, or
after 30 s.
