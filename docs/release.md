# Public release

Plans and checks for releasing the game publicly: Anthropic's terms and
branding, code signing, the stores, exports and the repo going public.
Moved out of NOTES.md → Watch items (2026-10-27, the user's) since
they're not needed every session; NOTES.md stays the source of truth for
the design and links here. Nothing here is built yet. Update it when one
of these is decided or done, and reread it before a release.

- **Anthropic's terms (public release).** *Plan (user's, 2026-10-02):*
  free and open source (MIT) on GitHub, **paid on Steam** (NOTES.md → Principles).
  Per Claude Code's legal and compliance docs (rechecked 2026-10-02):
  third parties may not offer claude.ai login, route requests through
  Free/Pro/Max credentials, or collect, store or intermediate Claude
  credentials; this doesn't prevent a user signing in to the
  **unmodified** Claude Code binary with their own subscription. Hence the
  CLI route (NOTES.md → S02): each user installs and signs in to Claude Code
  themselves; we never bundle, modify or authenticate it. What this means
  for the paid release:
  - *Commercial Terms:* "preinstalling or running Claude Code in your
    products" requires agreeing to Anthropic's Commercial Terms, on two
    conditions we meet: the binary is unmodified, and each user signs in
    and pays with their own credentials. A paid Steam app is clearly a
    product, so expect to agree to them (likely through a Claude Console
    account) before the Steam release.
  - *Never intermediate Claude usage:* players buy the app, not Claude.
    No bundled Claude credit, no edition "with Claude included", no
    trial on our key: each player pays Anthropic directly.
  - *Automated access:* the Consumer Terms forbid "automated or
    non-human means" except with an API key or where Anthropic permits
    it. Our reading: we add no automation. The user types every message
    and makes every choice; we never approve anything or pick a
    permission mode. A mode the user sets (e.g. `auto`, where Claude
    Code's own checks decide) is Claude Code's feature, and we don't
    override it. Hooks and channels are documented for this kind of use
    (Anthropic's fakechat demo is a localhost chat UI).
  - *Ask Anthropic* (the channel question asked 2026-10-27 as a comment
    on anthropics/claude-code#82571; the email still to send, by the
    user). Both messages are drafted in the dev log (2026-10-27-anthropic-questions, refreshed
    against the docs and terms that day; they replace the
    2026-10-02-terms-steam drafts); if they wait long, recheck the
    contacts and terms before sending. The routes: the terms questions
    (is the subscription use fine, free and paid; is the Commercial
    Terms step the right one) and asking for an official-marketplace
    listing for our channel go by email through the contact-sales form,
    which the legal page names for "questions about permitted
    authentication methods" and which is where a partner contact comes
    from. The channel-flag question (Channels are a research preview,
    in NOTES.md → Watch items) goes as a public issue on
    anthropics/claude-code,
    where the channels docs ask for feedback; no terms questions there.
    Other contacts found: support@anthropic.com (account help, not
    rulings), marketing@anthropic.com (permission to use their names or
    logos), notices@anthropic.com (formal legal notices only). Record
    the answers here. Recheck the terms before each release.
- **Claude branding.** Same page: a product may say in plain text that it
  runs Claude Code, but may not use the Claude Code or Anthropic names or
  logos in its own name or logo, or suggest Anthropic built or endorses it.
  Other use of their logos needs written permission. This affects the "logo
  model" agents (NOTES.md → A01, A02) in a public release, and the Steam store page:
  "Requires Claude Code" in plain text is fine; the name, capsule art,
  logo and trailer must not use their names or logos. The agents get
  the user's own custom models instead (NOTES.md → Open questions → 7, 2026-10-12).
- **Code signing (public release).** macOS blocks apps that aren't signed
  and notarized (Gatekeeper), which needs an Apple Developer account (99
  USD a year); unsigned Windows apps get a SmartScreen warning. Both apply
  to the Godot export and the sidecar executable, and matter most for
  itch.io's browser downloads. Decide before the first public release.
  The sidecar is a Node binary with our script injected, which breaks
  Node's own signature (Windows: "signature seems corrupted"; macOS: won't
  run until re-signed, which needs a Mac). Release builds should strip it
  and sign with ours (NOTES.md → S01).
- **Steam (planned, paid).** *User's plan (2026-10-02):* sell the game
  on Steam while the source stays free on GitHub (depots per OS, updates
  through SteamPipe; the bundled sidecar ships as ordinary game files).
  Anthropic's side of a paid release is under Anthropic's terms (above)
  and NOTES.md → Watch items → Channels are a research preview. Things
  to check before
  relying on it:
  - *Third-party account:* the store page must say "Requires 3rd-Party
    Account": Claude Code with the player's own plan or API key. Saying
    so plainly also heads off refunds.
  - *Licences:* MIT allows selling builds. Every asset and dependency
    must allow commercial use (CC0 Kenney packs do; the placeholder
    Godot icon, CC BY, is replaced before release; `assets/CREDITS.md`).
  - *Linux sandboxing:* native Linux games may run inside the Steam Linux
    Runtime container, and Flatpak installs of Steam are sandboxed; either
    may stop the game from seeing or starting the user's terminal and
    `claude`. Needs a test; if it does, the Linux build is offered on
    itch.io only.
  - *Environment:* Steam's variables and overlay hooks must not reach the
    launched terminal and `claude` (NOTES.md → Security rules → Clean child
    environments).
  - *Proton:* Steam must not run the Windows build through Proton on
    Linux (it would try to start Windows programs); ship the native Linux
    build.
  - *AI disclosure:* Steam's content survey asks about AI, including
    live-generated content shown in the game; Claude's replies probably
    count, and the answer must describe our safeguards (the player's own
    session; nothing approved without them). Since Valve's January 2026
    form (per developer guides; recheck in Steamworks), coding assistants
    used while developing need no disclosure, and our art is never
    AI-generated, so there is no pre-generated content to declare.
  - *Signing:* games installed by Steam don't trigger SmartScreen; check
    Valve's current macOS signing and notarization requirements (see Code
    signing).
  - *Steam features* (achievements, overlay) are optional; they'd need a
    GDExtension with builds for all three platforms (e.g. GodotSteam).
  - *Testing:* nothing Steam-specific is needed while building. Valve
    reviews the build and store page before release (it launches, matches
    the page), and Steam Deck Verified is optional. The risks above are
    tested by installing a build from a private Steam branch on each OS,
    which needs a Steamworks account (one-time fee per app); the Linux
    runtime part can be tried earlier, since that runtime is free.
- **itch.io (certain).** The game will be offered on itch.io, uploaded
  per OS with itch's `butler` tool (patch updates; the itch app updates
  players automatically). Nothing itch-specific is needed to build for
  it, but browser downloads differ from Steam installs:
  - *Signing matters more:* downloaded files carry the browser's
    "from the internet" mark, so unsigned Windows builds get SmartScreen's
    warning and un-notarized macOS builds are blocked by Gatekeeper until
    the user allows them in System Settings (see Code signing).
  - *Executable permissions:* macOS and Linux builds, including the
    sidecar executable, must keep their executable flag. `butler` and the
    itch app keep it; a zip unpacked by hand may not, so the game should
    check the sidecar's flag at start and restore it or explain.
  - *Linux:* a plain download runs outside Steam's sandboxing, so itch.io
    is the fallback home for the Linux build if Steam's sandboxing blocks
    launching the terminal and `claude`.
- **Export presets (when we make them):** leave out `tests/`, including
  the live-check checklist overlay (`tests/live/`); `world.gd` only loads
  it with `--checklist`, but it shouldn't ship (user's, M1 review).
- **`icon.svg`** is Godot's default icon (CC BY 4.0, not CC0). It is a
  placeholder to replace.
- **Before making the repo public:** re-run the history scan for secrets,
  personal data and machine paths (dev log 2026-09-29-privacy-check).
