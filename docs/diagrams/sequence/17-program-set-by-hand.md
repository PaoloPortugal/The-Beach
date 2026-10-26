# 17. Choosing Claude Code by hand

[All diagrams](../../flows.md)

> **Status:** Built (S02, C10). NOTES.md → S02 → The program set by hand, Protocol → Provider capabilities and notices → `program_path`, C10, Architecture → Platforms → Finding `claude`.

```mermaid
sequenceDiagram
    autonumber
    actor User

    box rgba(47,111,191,0.12) Ours
        participant World as World (Godot)
        participant Sidecar
    end

    box rgba(128,128,128,0.14) Claude Code, the user's own
        participant Claude as claude (the chosen file)
    end

    Note over World: Settings → Game: a row per provider with program_path#59;<br/>its program from hello or provider.program (path and version, or why not)
    User->>World: Browse… and pick a file (the system's picker)
    Note over World: the row says "Checking…"
    World->>Sidecar: client.set_program_path {provider: claude, path}
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/find.ts (checkClaudePath), index.ts (setProgramPath)<br/>commands.ts (provider messages held until the reply)
        Note over Sidecar: a full path? a file? on Windows an .exe?<br/>(a .cmd is never run)
        Sidecar->>Claude: --version (argument list, clean environment, 15 s)
        Claude-->>Sidecar: "2.1.300 (Claude Code)"
        alt every check passes, version 2.1.284 or newer
            Sidecar-->>World: ok {program: {path, version, set_by_hand: true}}
            Sidecar->>World: provider.program (the same, kept for the next hello)
            Note over World: saved in settings.cfg [programs]#59; the row shows it, "set by hand"
        else a check fails
            Sidecar-->>World: error invalid_program (which check, in the player's words)
            Note over World: "Not changed: …" in red#59; the previous setting stays
        end
    end
    opt Reset
        World->>Sidecar: client.set_program_path {provider: claude, path: null}
        Note over Sidecar: looks for claude as usual at once<br/>(PATH, install folders, on macOS and Linux the login shell last)
        Sidecar-->>World: ok {program: {path, version, set_by_hand: false}} or {path: null, message}
        Sidecar->>World: provider.program
        Note over World: removed from settings.cfg
    end
    opt the next start of the game
        World->>Sidecar: start it with serve --program-path claude=path
        Note over Sidecar: checked the same way before listening#59;<br/>failing, it's kept and reported not found, the start goes on
    end
    opt the chosen file stops working (moved, deleted, too old)
        World->>Sidecar: session.create
        Note over Sidecar: the same checks on this file only:<br/>no PATH, no install folders, no login shell
        Sidecar-->>World: error provider_error "The Claude Code set in Settings doesn't work: … Choose it again, or reset it."
        Sidecar->>World: provider.program {path: null, set_by_hand: true, message}
        Note over World: the row shows why, in red#59; no other claude is used
    end
```

**When the sidecar looks.** Each time it needs `claude` (a launch or
resume, asking which sessions run for the stored list, S07's restore and
S08's poll) and right after a path is set or cleared. With nothing set,
nothing at start runs `claude` unless the sidecar already asks it
something then (outside sessions on, sessions to take back), so the row
may say "Not looked for yet" until the first session starts.

**Sessions already running** keep the `claude` they were started with;
the choice is for sessions started or resumed after it.
