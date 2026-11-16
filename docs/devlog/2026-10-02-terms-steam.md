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
  better contacts now. (The drafts were later
  removed; see docs/release.md → Anthropic's terms for the outcome.)
- An automated Anthropic agent the user talked to pointed at the
  channels reference's advice to gate inbound messages by sender. We
  already do: the game is the only sender and is authenticated at each
  step (NOTES.md → S02 → Sender gating, added here).
- Not legal advice; Anthropic's written answer is the only certainty.
