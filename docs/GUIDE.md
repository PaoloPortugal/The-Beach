# The Beach: user's guide

How to use the app. Only features that are already built are described
here; each section is labelled with its feature ID.

## Contents

- [Running it](#running-it)
- [The island and the ocean (W01, W02)](#the-island-and-the-ocean-w01-w02)
- [Moving around (W03)](#moving-around-w03)
- [Talking to the orchestrator (C01)](#talking-to-the-orchestrator-c01)
- [The sidecar (S01)](#the-sidecar-s01)
- [Claude Code sessions (S02)](#claude-code-sessions-s02)

## Running it

There's no download yet. For now, open the project in Godot 4.7.2 and
press F5: you arrive on an island you can walk around, facing a stand-in
for the AI agent at a desk. You can't chat with it yet.

The game picks its graphics mode by itself. If it won't start or looks
wrong, you can force the simpler mode by starting it with
`--rendering-method gl_compatibility`; it looks nearly the same, but
without the sun's shadows.

## The island and the ocean (W01, W02)

The world is a small low-poly beach island in the ocean: a flat spot in
the middle, dunes around it, and a sandy beach. Islands are made by the game, so no two look the
same; for now you get a new one every time you start the game. The ocean
around it has gentle waves and fades into haze at the horizon.

## Moving around (W03)

You see the world through your character's eyes.

| Do this | Key |
|---------|-----|
| Walk | W A S D |
| Sprint | hold Shift |
| Jump | Space |
| Look around | mouse |
| Free the mouse pointer | Esc (click in the game to take it back) |
| Chat, next to the orchestrator | E (Esc closes the chat) |

The keys follow their position on the keyboard, so on other layouts
(such as AZERTY) use the keys in the same place.

Jumps are forgiving: pressing jump just before you land, or just after
you step off an edge, still counts. You can wade into the shallows; go
too deep and you're put back in the middle of the island.

## Talking to the orchestrator (C01)

In the middle of the island, an AI agent sits at a desk: the
**orchestrator**, the one you talk to. For now it's a plain stand-in
figure.

Walk up to it and **Press E to chat** appears. Press E to open the chat:
it fills most of the screen and frees your mouse pointer, and you can't
walk while it's open. Press Esc to close it and carry on walking. The
chat itself (your conversation and a box to type in) isn't there yet.

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
