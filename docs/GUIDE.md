# The Beach: user's guide

How to use the app. Only features that are already built are described
here; each section is labelled with its feature ID.

## Contents

- [Running it](#running-it)
- [The sidecar (S01)](#the-sidecar-s01)
- [Claude Code sessions (S02)](#claude-code-sessions-s02)

## Running it

Nothing is playable yet. Once it is, this section will explain how to
open the world on Windows, macOS or Linux.

## The sidecar (S01)

The game comes with a small helper program called the **sidecar**. The
game starts it for you in the background and it closes when the game
closes, even if the game crashes. You never need to start it yourself, and
no window opens for it.

The sidecar is what runs your AI coding sessions and passes what they're
doing to the world (see Claude Code sessions below).

It keeps things private and safe:

- It only accepts connections from the game on your own computer, using a
  secret that changes every time it starts. Other programs and web pages
  can't connect to it.
- It sends nothing over the internet and keeps no copy of your
  conversations.

If the sidecar can't start or stops unexpectedly, the game notices; for
now that only shows in the game's log, and a message on screen comes with
the world. The sidecar file ships next to the game's own executable;
reinstalling the game restores it if it goes missing.

## Claude Code sessions (S02)

The world runs **Claude Code**, Anthropic's coding assistant, as your AI
tool. The world itself isn't built yet, so you can't start a session from
inside the game; this section describes how sessions will behave.

**What you need.** Claude Code installed on your computer (version
2.1.284 or newer), signed in with your own account. The game never sees
your login and never changes Claude Code.

**Starting a session.** When you start a session for a project folder, a
terminal window opens with Claude Code in it. Claude Code asks you there
to confirm that it may connect to the game (every time, while this
connection is an early-access feature of Claude Code), and the first time
in a folder, whether you trust that folder. Until you answer, the world
tells you to confirm in the terminal. Once you have, the session's island
appears.

**Two windows onto one session.** The terminal and the world show the same
session, and you can use either at any time:
- Chat with Claude from the world or type in the terminal; both show up in
  both places.
- When Claude asks permission to do something (run a command, edit a
  file), answer in the world or in the terminal. If you deny from the
  world, you can add a note saying why or what to do instead; Claude reads
  it before carrying on.
- When Claude asks you a question with options, answer in either place,
  pick several options when allowed, or type your own answer.
- **Stop** from the world stops Claude before its next step (the current
  reply or command finishes first); anything it was waiting on you for is
  declined. Pressing Esc in the terminal stops it at once.

How often Claude asks for permission depends on the permission mode you
use in Claude Code: in its `auto` mode it rarely asks at all.

**Only in the terminal.** Claude Code's own startup questions, its slash
commands (such as `/model` or `/clear`), and switching permission mode
outside a prompt. Ending a session is `/exit` in the terminal for now.

**Transcripts.** Claude Code saves each conversation (its transcript) on
your computer; the game reads it to notice things like Esc and to show
earlier chats. If you've turned transcript saving off in Claude Code, the
world tells you once that some features may not work as intended; it
still works, but may be slow to notice what you did in the terminal. The
game never turns saving back on and never keeps its own copy of your
conversations on disk.

**If the world stays quiet.** If a company or personal setting in Claude
Code blocks the game from following the session, the world says so. You
can still chat from the world; answer Claude's prompts in the terminal.
