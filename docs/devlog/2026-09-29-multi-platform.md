# Windows, macOS and Linux

Features: docs (affects S01, S02, S03, S04, C03)

The user set a new requirement: the app must support Windows, macOS and
Linux. Everything so far had been built and verified on Windows 11 only,
so the architecture was reviewed for platform assumptions.

## Already portable

Claude Code runs on macOS 13+, Windows 10 1809+ and common Linux
distributions, with the same `~/.claude` layout; the docs (checked
2026-09-29) list no OS limits for hooks, channels or the permission relay.
Godot 4.7 exports to all three. The protocol, loopback networking, tokens
and argument-array launching are platform-neutral. Line endings are
already normalised to LF in `.gitattributes`. The Markdown spike is plain
GDScript apart from its system-font list.

## Found and decided

1. **Terminal windows.** The spike used `wt.exe` (Windows Terminal, not on
   every Windows 10). macOS's Terminal.app can't be handed a program and
   its arguments directly (the usual routes are AppleScript or a
   generated script, i.e. a shell string), and Linux has no standard
   terminal. *Decided (user's):* a per-OS default with fallbacks and a
   setting to pick another. To keep "no shell strings", the terminal only
   runs our launcher with a session file's path, and the launcher starts
   `claude` with an argument array. Rejected: one fixed terminal per OS
   (strands Linux users and iTerm2 users); making the user configure it
   on first run (clunky).
2. **Node on users' machines.** Claude Code no longer needs Node, but the
   sidecar and channel bridge do. *Decided (user's):* build the sidecar
   into one self-contained executable per platform, which also runs as
   the bridge and the launcher. Rejected: requiring users to install Node
   (extra step, version drift, PATH trouble on macOS).
3. **WSL.** Claude Code on Windows can run natively or inside WSL, where
   its transcripts, hooks and bridge sit across the WSL boundary.
   *Decided (user's):* native Windows only in v1, with a clear message;
   revisit after v1.
4. **Testing.** *The user's situation:* only Windows is available for now,
   and no CI yet. Recorded as a watch item; the README says it has only
   been tested on Windows.

Recommended and recorded without needing a decision (conventional
choices): Godot starts the sidecar and the sidecar exits when its pipe
from Godot closes (Windows has no graceful stop signal); find `claude` in
PATH and the documented install locations, since GUI apps on macOS and
Linux don't get the shell's PATH, and never start npm's `claude.cmd`
wrapper (it needs a shell); build paths with path functions and never
decode transcript folder names; follow transcripts by polling; ship the
UI's fonts rather than relying on system fonts (which font is still open:
most monospace fonts are OFL, not CC0). Code signing (Apple notarization
needs a paid developer account) is a watch item for the first public
release.

## Game side (same day)

The user added that the game itself must not depend on one platform's
graphics API (e.g. DirectX), noting that many games let players choose
between APIs. Checked Godot 4.7.2's defaults for this project: Forward+,
Vulkan on Windows and Linux, Metal on macOS, falling back to Direct3D 12
and then OpenGL automatically. So nothing requires DirectX.

- *Decided (user's):* build for Forward+ and keep the world usable on the
  Compatibility renderer (OpenGL 3.3) for old GPUs and awkward drivers.
  Rejected: Forward+ only (locks out machines without Vulkan, Metal or
  D3D12) and Compatibility only (fewer effects).
- *Decided (user's):* no graphics API or renderer menu; selection stays
  automatic, with Godot's command-line flags as the escape hatch.
  Rejected for now: a settings choice applied on restart.

Conventional rules recorded with it: Godot shading language only,
physical-key movement and Ctrl/Cmd auto-remap, exact-case `res://` paths
and `user://` for saves, HiDPI on, export presets for all three, and no
native plugins without builds for all three.

## Steam (same day)

The user plans to ship on Steam, though it isn't certain, and asked
whether Steam can install the game with its Node dependency. Yes: Steam
installs the uploaded build folder per OS, and the sidecar executable
(Node included) is just a file in it. Steam also helps with updates and
offers per-OS launch options, which covers choosing a renderer without an
in-game menu. Recorded as a watch item, with what's specific to an app
that starts other programs: Linux sandboxing (Steam Linux Runtime,
Flatpak Steam) may block launching the terminal and `claude`; Steam's
environment and overlay hooks must be stripped from launched processes
(added to Clean child environments); the native Linux build must be used
rather than Proton; and Steam's AI content disclosure probably applies to
showing Claude's replies. No architecture change.

## itch.io (same day)

The user confirmed the game will be offered on itch.io (Steam stays
likely). Nothing itch-specific is needed to build for it, but browser
downloads are marked as coming from the internet, so code signing
matters more there (SmartScreen on Windows, Gatekeeper blocking
un-notarized macOS apps), and macOS/Linux builds must keep their
executable flag (`butler` and the itch app keep it; hand-unpacked zips
may not, so the game should check the sidecar's). itch.io also becomes the
fallback home for the Linux build if Steam's sandboxing blocks launching
the terminal. Recorded as a watch item.

## Result

NOTES.md gained a Principles line and an Architecture → Platforms section;
Security rules (terminals get no command lines), S02 Launch, Layout,
Running it, M1, Watch items and Deliberate limitations were updated, plus
`docs/flows.md` (create a session), the README requirements and the
guide's Running it placeholder. No protocol changes.
