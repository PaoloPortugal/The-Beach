# Anthropic's terms, a paid Steam release, and OpenCode

Features: docs (NOTES.md → Principles; Watch items → Anthropic's terms,
Claude branding, Channels are a research preview, Steam; C06; Deferred
ideas → Provider roadmap)

## Why

The user found OpenCode and asked whether it made our sidecar wasted
work. It doesn't: OpenCode is its own coding agent, not a Claude Code
wrapper. Its server can't drive the `claude` CLI, and Anthropic blocked
third-party tools from using Pro/Max sign-ins (OpenCode dropped Claude
subscription sign-in in v1.3.0). Our route, the user's own unmodified
`claude` signed in by the user, is the one the terms explicitly allow.
Claude on an API key already works through it too. The user's decision:
Claude now, Codex later, OpenCode last as the "bring your own model and
key" provider (Deferred ideas → Provider roadmap).

The user then asked whether anything we do breaks Anthropic's rules, and
said the plan is now to **sell the game on Steam while the source stays
free on GitHub**. NOTES still said "free public release (maybe donations
later)".

## What was checked (2026-10-02)

- **Claude Code legal and compliance page:** the subscription rules (no
  claude.ai login offered by us, no routing Free/Pro/Max credentials, no
  handling credentials; a user signing in to the unmodified binary is
  fine). New for a paid release: "preinstalling or running Claude Code in
  your products" requires the Commercial Terms, with two conditions we
  already meet (unmodified binary, each user's own credentials and
  billing). Branding rules unchanged.
- **Consumer Terms:** "automated or non-human means" is forbidden except
  with an API key or where Anthropic permits it. Our reading is that we
  add no automation; the user corrected one point of my summary: the app
  never auto-approves, but if the user sets a permission mode such as
  `auto`, Claude Code's own checks decide and we don't override that.
  That is Claude Code's feature, chosen by the user.
- **Channels docs:** plain `--channels` only accepts allowlisted
  channels during the preview; the development flag is described as for
  testing. Not a rule we break, but the largest risk for a paid release.
- **Steam** (developer guides, not the Steamworks docs, which need an
  account): third-party account notice on the store page; Valve's
  January 2026 AI form exempts coding assistants and asks about
  live-generated content, which Claude's replies probably are.

The user asked whether a permission mode picker (C06) is legally allowed.
It is: documented flags, as if the user typed them. Our C06 safety rules
are our own design, not legal limits. Whether to ever offer bypass mode
is left for C06 (recommendation: no).

## Outcome

- NOTES updated: the release plan (Principles), the paid-release points
  under Anthropic's terms, Steam store page branding, the channel flag to
  settle before Steam, Steam's account notice, licences and AI form, and
  C06's note on bypass.
- Two messages to Anthropic were drafted for the user to send, framed
  honestly as free on GitHub and paid on Steam, since an answer about a
  free app wouldn't cover a paid one. The user doubted a sales form was
  the right place; it is the contact the legal page names for sign-in
  questions, and no dedicated address for developers' terms questions
  turned up. So the user agreed to split it: the terms questions by
  email through contact-sales, the channel-flag question as a public
  issue on anthropics/claude-code. Then the user decided to leave
  sending them until before the public release, without looking for
  better contacts now. The drafts are below; recheck the contacts and
  the terms before sending, and record the answers under Anthropic's
  terms.
- An automated Anthropic agent the user talked to pointed at the
  channels reference's advice to gate inbound messages by sender. We
  already do: the game is the only sender and is authenticated at each
  step (NOTES.md → S02 → Sender gating, added here). The email gained a
  line saying so.
- Not legal advice; Anthropic's written answer is the only certainty.

## Draft: email to Anthropic (terms questions)

**To:** Anthropic, via https://www.anthropic.com/contact-sales

**Subject:** Permitted authentication question: an open-source app that launches users' own Claude Code

---

Hello,

Your Claude Code legal and compliance page (https://code.claude.com/docs/en/legal-and-compliance) directs questions about permitted authentication methods for a given use case here, so I'm writing with one. I'm an independent developer building a desktop app (working title "The Beach") that works alongside Claude Code, and I'd like a preliminary view on whether it complies with your terms before I release it. I understand the paid release may require me to agree to your Commercial Terms, and I'm happy to do so.

**What it is**

A 3D world, built in Godot, where each Claude Code session appears as an island. The user can start or resume sessions, chat with them and answer their permission prompts from inside the world, and switch to the session's normal terminal at any time.

**Release plan**

The source will be free and open source (MIT) on GitHub. I plan to sell builds on Steam. Players would be buying the app, not Claude: each player installs and signs in to Claude Code themselves and pays Anthropic directly under their own plan or API key. I won't resell, bundle or pay for Claude usage on anyone's behalf.

**How it works with Claude Code**

- It launches the user's own installed, unmodified `claude` CLI in a normal terminal window on their own machine. Claude Code is never bundled, patched or re-implemented.
- Users sign in through your own flow, with their own subscription or API key. The app never sees, stores or passes on credentials or session tokens.
- It only uses documented features: hooks, supplied through a per-session `--settings` file (the user's own settings files are never edited); a local channel (an MCP server) for chat and the permission relay; and reading the local transcripts under `~/.claude/projects` for history and resuming.
- The app never approves anything on its own and never picks a permission mode for the user. Claude Code's permission mode stays the user's choice, including `auto`, in which Claude Code itself decides most actions. When Claude Code asks for permission, the answer comes from the user, in the app or in the terminal. Messages are only ever sent because the user typed them.
- The channel has no external endpoint: its only sender is the app itself, authenticated with secret tokens at each step, and the permission relay is gated the same way.
- Everything stays on the user's machine. The app's local servers only listen on loopback and require secret tokens. It has no telemetry and makes no network calls of its own.
- The app doesn't use Claude or Anthropic names or logos in its name or branding. It says in plain text that it requires Claude Code, and that it isn't affiliated with or endorsed by Anthropic.

**Questions**

1. Is this use acceptable under your terms when the user is on a Pro or Max subscription: an end user signed in to the unmodified Claude Code binary, using it through a third-party local interface they control? And is that answer the same for a paid Steam release?
2. For the paid Steam release, is agreeing to your Commercial Terms the right step, and is there anything else you'd need from us?

(A separate technical question, about shipping a custom channel while channels are in research preview, I've raised on the Claude Code GitHub repository, where the channels documentation asks for feedback.)

A short screen recording is attached showing a session being started, a chat, a permission prompt answered in the world, and the same session in its terminal. I'm happy to share the source code or more detail.

Thank you for your time.

Kind regards,
[Your name]
[Contact email]

## Draft: GitHub issue (the channel flag)

**Where:** https://github.com/anthropics/claude-code/issues/new (pick the feature request or question template if one is offered; public)

**Title:** Channels: how should a third-party desktop app ship a custom channel?

---

**Context**

I'm building a desktop app that launches the user's own Claude Code CLI and gives them a different interface to it: they chat with the session and answer its permission prompts from the app, and can switch to the terminal at any time. The app's channel is a local MCP server (stdio) that declares the `claude/channel` capability and the permission relay. It connects back to the app over loopback with a per-session token. It's started with `--mcp-config` and `--dangerously-load-development-channels server:<name>`, and the user confirms the development-channel dialog at every launch.

That works well for development. The channels docs describe the development flag as the way to test a channel you're building, though, and plain `--channels` only accepts channels on Anthropic's allowlist during the research preview.

**Questions**

1. Is it acceptable for a released app to rely on `--dangerously-load-development-channels` while channels are in research preview, or is that flag meant for development only?
2. Is there, or will there be, a path for a third-party channel to be accepted by `--channels`? For example, is the plugin directory submission form the route onto the channel allowlist, and would a channel need to be packaged as a plugin for that?
3. Is there a rough expectation of how the flag and the allowlist will work once channels leave the research preview, so apps can plan for it?

Thanks. Channels and the permission relay are exactly what this kind of app needs.
