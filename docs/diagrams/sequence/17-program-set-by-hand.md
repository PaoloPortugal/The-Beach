# 17. Choosing Claude Code by hand

[All diagrams](../../flows.md)

> **Status:** Built (S02, C10, S03, C16). Godot words each reason
> (`core/sidecar/sidecar_text.gd`, NOTES.md → C16 → How the codes work). NOTES.md → S02 → The program set by hand, Protocol → Provider capabilities and notices → `program_path`, C10, Architecture → Platforms → Finding `claude`.

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

    opt the game starts (nothing set by hand)
        World->>Sidecar: start it with serve
        Note over Sidecar: ready at once#59; looks for claude in the background<br/>(PATH, install folders, on macOS and Linux the login shell last)<br/>none under a test suite
        Sidecar->>Claude: --version
        Sidecar->>World: provider.program {provider, program: {path, version, set_by_hand: false}<br/>or {path: null, set_by_hand: false, message, reason, details}}
        Note over World: until then the row says "Looking for it…"
    end
    Note over World: Settings → Providers: a row per provider with program_path#59;<br/>its program from hello or provider.program (path and version, or why not)
    opt no provider's program found
        Note over World: sessions menu: "+ New session…" and "▸ Resume a session…" greyed out,<br/>why in red (worded by its reason, else the message)<br/>and "Or choose it yourself in Settings → Providers."
    end
    opt Look again
        User->>World: Look again
        Note over World: the row says "Looking…"
        World->>Sidecar: client.find_program {provider: claude}
        Note over Sidecar: looks afresh (the login shell asked again)#59;<br/>set by hand: only that file is checked again#59;<br/>a look begun before it no longer reports
        Sidecar-->>World: ok {program} (found or not)
        Sidecar->>World: provider.program (only if the answer changed)
        Note over World: the row shows it#59; the sessions menu greys out or back in
    end
    User->>World: Browse… and pick a file (the system's picker)
    Note over World: the row says "Checking…"
    World->>Sidecar: client.set_program_path {provider: claude, path}
    rect rgba(255,193,7,0.18)
        Note over Sidecar,Claude: providers/claude/find.ts (checkClaudePath), index.ts (setProgramPath, findProgram)<br/>serve.ts (the look at start), registry.ts and commands.ts (provider messages held until the reply)
        Note over Sidecar: a full path? (on Windows on a drive, not a network path)<br/>a file? on Windows an .exe?<br/>(a .cmd is never run)
        Sidecar->>Claude: --version (argument list, clean environment, 15 s)
        Claude-->>Sidecar: "2.1.300 (Claude Code)"
        alt every check passes, version 2.1.284 or newer
            Sidecar-->>World: ok {program: {path, version, set_by_hand: true}}
            Sidecar->>World: provider.program (the same, kept for the next hello#59;<br/>not sent if the answer is the same as the last)
            Note over World: saved in settings.cfg [programs]#59; the row shows it, "set by hand"
        else a check fails
            Sidecar-->>World: error invalid_program (which check, in the player's words,<br/>and its reason: no_file, wrapper, too_old, ...)
            Note over World: "Not changed: …" in red#59; the previous setting stays
        end
    end
    opt Reset
        World->>Sidecar: client.set_program_path {provider: claude, path: null}
        Note over Sidecar: looks for claude as usual at once<br/>(PATH, install folders, on macOS and Linux the login shell last)
        Sidecar-->>World: ok {program: {path, version, set_by_hand: false}} or {path: null, set_by_hand: false, message, reason, details}
        Sidecar->>World: provider.program
        Note over World: removed from settings.cfg
    end
    opt the next start of the game
        World->>Sidecar: start it with serve --program-path claude=path
        Note over Sidecar: set at once, checked the same way in the background<br/>(the ready line doesn't wait, the restore shares the check)#59;<br/>failing, it's kept and reported not found, the start goes on
    end
    opt the chosen file stops working (moved, deleted, too old)
        World->>Sidecar: session.create
        Note over Sidecar: the same checks on this file only:<br/>no PATH, no install folders, no login shell
        Sidecar-->>World: error provider_error "The Claude Code set in Settings doesn't work: … Choose it again, or reset it."<br/>(reason set_path_broken)
        Sidecar->>World: provider.program {path: null, set_by_hand: true, message,<br/>reason: set_path_broken, details: {why, ...}}
        Note over World: the row shows why, in red#59; no other claude is used
    end
```

**When the sidecar looks.** At start, in the background; each time it
needs `claude` (a launch or resume, asking which sessions run for the
stored list, S07's restore and S08's poll); right after a path is set
or cleared; and on Look again. Looks that come while one runs share
its answer, so `--version` runs once at start. What it finds is not
saved, only a path set by hand.

**Sessions already running** keep the `claude` they were started with;
the choice is for sessions started or resumed after it.
