# The questions for Anthropic, refreshed

Features: docs (release.md → Anthropic's terms, Watch items → Channels
are a research preview)

The user had never sent the two drafts from 2026-10-02-terms-steam: it
wasn't clear where to send them. Looking at turning our bridge into a
plugin (to get off the development flag) made the answers urgent, so
the user asked for the drafts to be refreshed against today's docs and
terms. They supersede the 2026-10-02 drafts.

## What was rechecked (2026-10-27)

- **Contacts.** Claude Code's legal page still sends "questions about
  permitted authentication methods for your use case" to contact sales;
  the channels docs still ask for preview feedback on the
  anthropics/claude-code issues. The plan stands: the email through the
  contact-sales form, the channel question as a public issue.
- **The allowlist route was wrong.** NOTES.md guessed the plugin
  directory form might get our channel onto the allowlist. It can't:
  the allowlist is the channel plugins in `claude-plugins-official`,
  and that marketplace "doesn't take submissions through the directory
  portal"; the docs say to ask "an Anthropic partner contact" about a
  listing. A channel in our own marketplace, or the community one,
  still needs the development flag. So the listing question moves into
  the email (sales is where a partner contact comes from), and the
  issue asks whether independent developers have any route.
- **Terms.** The legal page's points the email answers are unchanged:
  running Claude Code in a product needs the Commercial Terms; the
  binary unmodified; users authenticate themselves; no paying for,
  reselling or intermediating usage; plain-text mention of Claude Code
  only. It also says Pro and Max limits "assume ordinary, individual
  usage": the email now says the app adds no automation of its own.
- **The channel protocol.** The channels docs now note that Claude
  Code's v2 MCP client runtime doesn't register a channel server that
  negotiates MCP revision 2026-07-28. Ours answers with 2025-11-25 or
  older (`MCP_VERSIONS` in `sidecar/src/providers/claude/bridge.ts`),
  so it isn't affected; don't move it to the new revision while that
  holds.

## Sending them

The email is the user's to send: the contact-sales form wants a
company, website, job title and phone (a solo developer fills in their
own name and GitHub profile), and the page now says sales only takes
large deals, so the user tries its purchasing-agent chat first (it can
forward to sales). A screen recording goes with it.

In the end the user sent it through claude.ai's Product Support chat
(Get help → Send us a message), the route Anthropic's support assistant
named for an individual without a company; after some back and forth
the bot passed it to a human agent, who replies by email. The assistant
also gave the user a brief to fill in, so what was sent is a shorter
message (below, "What was sent"), not the email draft; it keeps the
Commercial Terms question.

The GitHub question went out differently. anthropics/claude-code only
takes issues through its templates, and the open
[#82571](https://github.com/anthropics/claude-code/issues/82571)
("No way for a user to allow third-party channel plugins for inbound
notifications") already asks for a route onto the allowlist, with other
channel developers adding their cases. So, with the user's approval, a
comment there
([2026-10-27](https://github.com/anthropics/claude-code/issues/82571#issuecomment-6457478814))
describes our case and asks the draft's first two questions; the third
was left out. The issue draft below was not posted.

Seen while checking:
[#105326](https://github.com/anthropics/claude-code/issues/105326)
(2026-10-27): since 2026-10-25 a Windows Max user's channels, even with
the development flag, are skipped as "channels feature is not currently
available", apparently a server-side switch. Ours still registered in
the user's latest session (2026-10-27, Claude Code's MCP log for
world-bridge). Record the answers in `docs/release.md` → Anthropic's
terms.

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
- Users sign in through your own flow, with their own subscription or API key. The app never sees, stores or passes on credentials or session tokens, and it offers no Claude login of its own.
- It only uses documented features: hooks, supplied through a per-session `--settings` file (the user's own settings files are never edited); a local channel (an MCP server) for chat and the permission relay; and reading the local transcripts under `~/.claude/projects` for history and resuming.
- The app never approves anything on its own and never picks a permission mode for the user. Claude Code's permission mode stays the user's choice, including `auto`, in which Claude Code itself decides most actions. When Claude Code asks for permission, the answer comes from the user, in the app or in the terminal. Messages are only ever sent because the user typed them.
- It adds no automation of its own: no scheduled or background prompts, no agents started without the user. Usage is the same individual use as working in the terminal, just through a different interface.
- The channel has no external endpoint: its only sender is the app itself, authenticated with secret tokens at each step, and the permission relay is gated the same way.
- Everything stays on the user's machine. The app's local servers only listen on loopback and require secret tokens. It has no telemetry and makes no network calls of its own.
- The app doesn't use Claude or Anthropic names or logos in its name or branding. It says in plain text that it requires Claude Code, and that it isn't affiliated with or endorsed by Anthropic.

**Questions**

1. Is this use acceptable under your terms when the user is on a Pro or Max subscription: an end user signed in to the unmodified Claude Code binary, using it through a third-party local interface they control? And is that answer the same for a paid Steam release?
2. For the paid Steam release, is agreeing to your Commercial Terms the right step, and is there anything else you'd need from us?
3. The app's chat and permission answers depend on its channel, which today runs with `--dangerously-load-development-channels`, since custom channels aren't on the channel allowlist during the research preview. Your docs say an official-marketplace listing is coordinated through an Anthropic partner contact. Could the app's channel be considered for one, packaged as a plugin, and who should I talk to about it?

(A related technical question, whether a released app may rely on the development flag in the meantime, I've raised on the Claude Code GitHub repository, where the channels documentation asks for feedback: https://github.com/anthropics/claude-code/issues/82571.)

A short screen recording is attached showing a session being started, a chat, a permission prompt answered in the world, and the same session in its terminal. I'm happy to share the source code or more detail.

Thank you for your time.

Kind regards,
[Your name]
[Contact email]

## Draft: GitHub issue (the channel flag; not posted, see above)

**Where:** https://github.com/anthropics/claude-code/issues/new (pick the feature request or question template if one is offered; public)

**Title:** Channels: how should a third-party desktop app ship a custom channel?

---

**Context**

I'm building a desktop app that launches the user's own Claude Code CLI and gives them a different interface to it: they chat with the session and answer its permission prompts from the app, and can switch to the terminal at any time. The app's channel is a local MCP server (stdio) that declares the `claude/channel` capability and the permission relay. It connects back to the app over loopback with a per-session token. It's started with `--mcp-config` and `--dangerously-load-development-channels server:<name>`, and the user confirms the development-channel dialog at every launch.

That works well for development. The channels docs describe the development flag as the way to test a channel you're building, though. Plain `--channels` only accepts the channel plugins in `claude-plugins-official` during the research preview, and the docs say a channel published to your own marketplace still needs the development flag.

**Questions**

1. Is it acceptable for a released app to rely on `--dangerously-load-development-channels` while channels are in research preview, or is that flag meant for development only?
2. The docs point to an Anthropic partner contact for an official-marketplace listing. Is there a route for independent developers to get a channel onto the allowlist, or is one planned?
3. Is there a rough expectation of how the flag and the allowlist will work once channels leave the research preview, so apps can plan for it?

Thanks. Channels and the permission relay are exactly what this kind of app needs.

## What was sent (Product Support, 2026-10-27)

Hi, I'm an individual developer [plan and company details left out of this copy], asking whether my app is a permitted use of Claude Code.

It's a desktop game where each Claude Code session appears as an island. It launches the user's own installed, unmodified `claude` CLI in a normal terminal window. Users sign in through Claude Code's own flow with their own subscription or API key; the app never sees or stores credentials, and all usage is billed to the user. The app passes hooks in a per-session settings file and talks to the session through a local channel: a stdio MCP server on the same machine, loaded with `--dangerously-load-development-channels`. It only sends what the user types or chooses; nothing is automated. The source will be free on GitHub (MIT), with paid builds on Steam: players buy the app, never Claude usage.

1. Is this a permitted use for Pro and Max users, including the paid Steam release? The legal page says running Claude Code in a product requires the Commercial Terms. Does that apply to an app that launches the user's own install rather than preinstalling it, for the free release, the paid one, or both? If it does, is agreeing to them through a Claude Console account the right step, with players staying on their own Consumer Terms?
2. During the research preview, is there a path for a third-party channel to be approved beyond the development flag?

Thank you.
