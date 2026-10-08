# The Beach: user's guide

How to use the app. Only features that are already built are described
here; each section is labelled with its feature ID.

## Contents

- [Running it](#running-it)
- [The sessions menu (S03, S04, W07)](#the-sessions-menu-s03-s04-w07)
- [Quitting the game (S05)](#quitting-the-game-s05)
- [The islands and the ocean (W01, W02, W04)](#the-islands-and-the-ocean-w01-w02-w04)
- [Clusters (W05)](#clusters-w05)
- [Bridges and the maps (W06)](#bridges-and-the-maps-w06)
- [Moving around (W03)](#moving-around-w03)
- [Swimming and the sea floor (W08)](#swimming-and-the-sea-floor-w08)
- [Talking to the orchestrator (C01)](#talking-to-the-orchestrator-c01)
- [The chat (C02)](#the-chat-c02)
- [Formatting in the chat (C03)](#formatting-in-the-chat-c03)
- [What Claude did: the tool calls (C04)](#what-claude-did-the-tool-calls-c04)
- [Answering Claude's requests (C05)](#answering-claudes-requests-c05)
- [Permission modes and plans (C06, C07)](#permission-modes-and-plans-c06-c07)
- [Token usage (C08)](#token-usage-c08)
- [Subagents (A02, A03, A04)](#subagents-a02-a03-a04)
- [When something waits for you (A05)](#when-something-waits-for-you-a05)
- [When you need to sign in again (S06)](#when-you-need-to-sign-in-again-s06)
- [The sidecar (S01)](#the-sidecar-s01)
- [Claude Code sessions (S02)](#claude-code-sessions-s02)

## Running it

There's no download yet. For now, open the project in Godot 4.7.2 and
press F5: you arrive on a wooden platform in the open sea. Press Tab
to start a session.

The game picks its graphics mode by itself. If it won't start or looks
wrong, you can force the simpler mode by starting it with
`--rendering-method gl_compatibility`; it looks nearly the same, but
without the sun's shadows.

## The sessions menu (S03, S04, W07)

This is a quick first version, a placeholder: the menu will be designed
properly later.

Press **Tab** anywhere (except while chatting) to open the sessions menu;
**Tab** or **Esc** closes it. While no session is running, "Press Tab for
sessions" reminds you at the bottom of the screen. Type in the search box
at the top to filter the lists by title, project or cluster.

Under the search box, **Cluster** says which cluster a session you start
or resume joins (see Clusters below). **Automatic (by repository)**, the
choice each time the menu opens, puts it with the other sessions of its
git repository. You can pick one of the running clusters instead, or
**New cluster** to give it a cluster of its own.

Sessions are named the way Claude Code names them. A new one shows as
"New session" until your first message, which names it for now. If you
typed that message in the terminal, a moment later Claude Code gives the
session a short title of its own, and that replaces it. Claude Code
doesn't do this for messages sent from the game, so a session you start
chatting with in the game keeps its first message as its name. If you rename it with `/rename` in the terminal, that name
is used instead, everywhere in the game. The Resume list uses the same
names as Claude Code's own `/resume` list.

- **+ New session…** opens your system's own folder picker (File
  Explorer on Windows, the usual open panel on macOS and Linux) to
  choose the project folder you want to work in. Cancelling it takes you
  back to the menu. While it's open, the menu waits with a note: if the
  picker ends up hidden behind the game (this can happen on Windows),
  switch to it (Alt+Tab or the taskbar), or press **Cancel** (or Esc) to
  get back to the game; choosing a folder in it afterwards does nothing.
  If your system has no picker of its own, the game shows its own.
- **⌂ Platform** takes you back to the spawn platform, wherever you are,
  in the water too.
- **Running** lists the sessions running now, grouped under their
  cluster's name, with what each is doing
  (working, waiting for you, stopped, idle). A session counts as working
  while any of its subagents works, even if its orchestrator is idle. Click one to go straight to
  its island, in front of its orchestrator (if the island is still
  rising, once it's up). The order stays put, so
  you always find a session in the same place: clusters in the order
  of their places around the platform, and each cluster's sessions in
  the order of their islands.
- **Resume** lists your earlier Claude Code sessions, newest first, with
  their project and how long ago you last used them. Click one to pick it
  up again where you left off: its chat comes back too. Only sessions
  started in a terminal are listed (not ones from the VS Code extension
  or the Claude desktop app), and only as far back as Claude Code keeps
  them (30 days by default).

Starting or resuming opens Claude Code in a terminal, and
a note at the top of the screen tells you to confirm there (see Claude
Code sessions below). If nothing has happened after two minutes it says
"Still starting; check the terminal, or stop waiting in the menu (Tab)."
Once you've confirmed, the session's island rises out of the seabed, and
once it's up you're taken to it, right in front of its orchestrator.

If the session can't start, the note says why. If Claude Code closes
before it's ready (for example you chose not to trust the folder, or
closed its window), the note says "The session didn't start." straight
away.

One session starts at a time. While one is starting, the menu has
**✕ Stop waiting for the session starting**: it lets you start another.
If the first one does come up later, its island rises and it's listed
under Running, but you aren't taken there.

## Quitting the game (S05)

Sessions don't end when you quit: they keep running in their terminal
windows, but the game can no longer see or reach them. So if you close
the game while sessions are running, it asks first. It lists them with
what each is doing (scroll the list if there are many), and reminds you
that to end a session you type `/exit` in its terminal. **Quit** closes
the game anyway; **Back to the game** (or Esc) returns you to where you
were. With no session running,
the game just closes.

The game can't end sessions for you: Claude Code has no clean way to do
that from outside.

## The islands and the ocean (W01, W02, W04)

Each session has its own small low-poly beach island: a flat spot in the
middle where its orchestrator sits, dunes around it, and a sandy beach.
Islands are made by the game, so no two look the same.

When a session starts, its island rises out of the seabed, which takes a few
seconds. A green light beam stands over a new session's island until
you've been on it, and while the island is off-screen a green arrow at
the edge of the screen points to it, with its project's name and how far
it is. (The beam and arrow are a first version, like the rest of the
game's screens for now.) Sessions that were already running when the
game connected are simply there. When a session ends, its orchestrator and subagents
disappear at once. If you're standing on its island, or on
one of its bridges, the empty island stays until you leave it (walk
away over a bridge, swim away, or go to another session or the
platform); then it sinks back into the seabed and is gone. Islands of the same project sit
together in a cluster (below), and bridges join them to each other and
to the platform (W06); the sessions menu (Tab) takes you straight to
any of them. The ocean has gentle waves and fades into haze at the
horizon. The water is clear over the shallows and deepens to dark blue
over deep water, so you can see the sea floor (see Swimming and the sea
floor below). To keep the game smooth, islands and bridges lost in the
haze aren't drawn at all, and the steep slopes under the water are
plainer than the land.

## Clusters (W05)

Sessions working on the same project share a **cluster**: their islands
sit close together, about 100 m apart. Each cluster has its own slice of
sea fanning out from the platform, like a slice of cake: its first
island is the closest to the platform, and later ones fill the slice
outward, so a cluster never grows into another.

A session joins its project's cluster on its own. "Same project" means
the same git repository, including its worktrees (for example a
repository and the worktrees Claude Code makes under `.claude/worktrees`).
A folder that isn't in a git repository gets a cluster of its own. A new
cluster is named after the repository's folder; if the name is taken, a
number is added ("game 2"). To put a session somewhere else, choose a
running cluster or **New cluster** in the sessions menu before starting
or resuming it (a new cluster you ask for is named after the session's
folder).

Clusters last only while they have sessions: when a cluster's last
session ends, it's gone from the menu at once, and its place around the
platform is free again once its last island has sunk. The game doesn't remember them after it closes.

A cluster shows in the sessions menu, as a heading in the Running list,
and on the maps (W06); nothing on the islands says which cluster
they're in yet.

## Bridges and the maps (W06)

Wooden bridges join the islands of a cluster, and a long bridge runs
from the platform out to each cluster, so you can walk everywhere. A
cluster's bridges make a single path between its islands: each new
island gets a bridge to the nearest one. A bridge appears once its
island has risen and goes as soon as the island starts sinking. If that
leaves part of a cluster cut off, a new bridge joins it back on; the
other bridges stay where they are. The bridges have rails, and you can't
run or jump off them. Seen from about 70 m away, a bridge is drawn more
simply, with a smooth deck and one rail a side instead of every plank;
up close it has all its planks again.

There's room for 16 clusters with bridges, and for 10 islands in each
of the 8 clusters nearest the platform. Beyond that, an island is put
far out at sea with no bridge; go there with the sessions menu (Tab).

The **minimap** in the top left shows the cluster you're in or nearest
to: its islands (an empty one is grey), its bridges, the platform when
it's close, and you as a white arrow pointing the way you face, with
north at the top. It hides while the chat, the sessions menu or the big
map is open.

Press **M** for the **big map** of the whole world. It opens on you,
showing your cluster; drag it with the mouse, or use W A S D or the
arrow keys, to look around, and the mouse wheel zooms in and out. Each
cluster's name is over its islands, and zoomed in, each island shows its
session's title and what it's doing (working, waiting for you, idle or
stopped). Click an island to go there, or the platform to go back to
it. The world carries on while the
map is open; you just don't move. M or Esc closes it. (The bridges and
the maps are a first version, like the rest of the game's look for now.)

## Moving around (W03)

You see the world through your character's eyes.

| Do this | Key |
|---------|-----|
| Walk | W A S D |
| Sprint | hold Shift |
| Jump | Space |
| Swim (in deep water) | W A S D, toward where you look |
| Swim up / down | Space / Ctrl |
| Look around | mouse |
| Free the mouse pointer | Esc (click in the game to take it back) |
| Sessions menu: start, resume or go to a session or the platform | Tab (Tab or Esc closes it) |
| Big map (M or Esc closes it) | M |
| Chat, next to the orchestrator | E (Esc closes the chat) |

The keys follow their position on the keyboard, so on other layouts
(such as AZERTY) use the keys in the same place.

Jumps are forgiving: pressing jump just before you land, or just after
you step off an edge, still counts. Walk into the sea and once it's too deep to stand, you
swim (below).

## Swimming and the sea floor (W08)

Out of your depth, you swim. You float at the surface with your head just
above the waves. W A S D swim toward where you're looking, so look down
and press W to dive; Space takes you up and Ctrl down, and Shift swims
faster. There's no air to run out of: stay under as long as you like.
Under the water everything turns blue and fades out after a few dozen
metres.

The sea floor is everywhere. It's shallow around the platform, and
further out there are sandbanks, deeper water and trenches. Each island
sits on its own shallow shelf, which drops away steeply to the deep sea
floor. A new session's island rises out of the seabed, and an ended
one sinks back into it, and you can watch both through the water.

You get out of the water by swimming to a beach and walking up it. You
can't climb onto the platform or a bridge from the water. To get back to
the platform from anywhere, choose **⌂ Platform** in the sessions menu
(Tab), or click the platform on the big map (M).

## Talking to the orchestrator (C01)

In the middle of each island, an AI agent sits at a desk: the
**orchestrator** of that session, the one you talk to. For now it's a
plain stand-in figure.

Walk up to it and **Press E to chat** appears. Press E to open the chat:
it fills most of the screen and frees your mouse pointer, and you can't
walk while it's open. Press Esc to close it and carry on walking. If the
session ends while the chat is open, the chat closes.

## The chat (C02)

**Above the orchestrator's head** floats a small window with the last
thing it said, facing you wherever you stand. It fills in as the reply
arrives and shows the newest four lines; the full text is in the chat.
It's part of the world, so it gets smaller as you walk away and hills
can hide it. From about 60 m away, where it's too small to read, it
isn't shown.

**The chat** (E, next to the orchestrator) shows the whole conversation:
your messages on the right, the orchestrator's on the left, including
what was said in the terminal. Replies appear as they're written. You can
select text to copy it. Type in the box at the bottom: **Enter** sends,
**Shift+Enter** starts a new line. Your message shows up once the session
has it; if it can't be sent, the chat says so and gives your text back.
What you type stays in the box if you close the chat and come back to
the same session; opening another session's chat starts with an empty
box (or with that session's message that didn't arrive: see When you
need to sign in again, below). If a message couldn't be sent after you
moved to another session's chat, its own chat says so when you go back,
and gives it back.

At the top right, next to "Esc to close", the chat shows the session's
permission mode, such as **Mode: Auto** (see Permission modes and plans
below), and how many tokens it uses (see Token usage below).

Above the box, a line says what the orchestrator is doing: working, or
waiting for you. If a reply stopped for a reason Claude Code reports (a
usage limit, the service busy or failing, a reply too long, ...), the
line says so and what to do. When it waits on a permission, a question or a plan, a
card above that line lets you answer it (see below). Only the latest 200
messages are shown at once. A long chat appears newest first, and the
older messages fill in above it over a moment.

## Formatting in the chat (C03)

Messages are formatted the way Claude writes them (Markdown): headings,
**bold**, *italic*, lists, task lists, tables, quotes and `code`. Your
own messages are formatted the same way.

Each **code block** gets its own dark panel with its language at the top
and a **Copy** button. Long lines scroll sideways (Shift+wheel) instead
of wrapping. While Claude is still writing a block, it's marked
"writing…".

**Links** are blue; hover over one to see where it goes. Clicking one
asks first, showing the full address, and only opens it in your browser
if you confirm. Only web and email links can be clicked. Images in
messages are never downloaded: you see their description instead.

The window above the orchestrator's head is formatted too, in a simpler
way: code shows in a monospace font, and links can't be clicked there.

## What Claude did: the tool calls (C04)

This is a placeholder look: it will be designed properly later.

Under a message, a grey line like **▸ 5 tool calls** sums up what Claude
did after it: reading files, running commands, starting subagents. It
also says how many are still running, failed or were denied, for
example "▸ 3 tool calls (1 failed)". It updates as Claude works.

Click the line to open it (**▾**). Each call shows how it went
(running, ok, failed or denied), what it was ("Run: npm test"), and a
line about how it ended when there is one, such as an error. **Details**
shows exactly what Claude sent the tool. Click the line again to fold
it.

A subagent's work is folded inside the call that started it, with its
own "▸ 3 tool calls" line, so the list stays about the orchestrator's
own steps.

The log includes calls from before the world was watching: when you
resume a stored session, its calls are read back from Claude Code's own
records along with the chat. A call that never got a
result there (Claude Code was closed in the middle of it) shows as
failed, "No result was recorded.". On a very long session, the oldest
calls may come back without their Details.

## Answering Claude's requests (C05)

When Claude, or one of its subagents, asks your permission or asks you a
question, a card with an orange border appears in the chat, just above
the message box. It says who is asking. If several are waiting, you see
the oldest first, with "1 of 3 waiting"; the next one shows once you've
answered. You can still answer in the terminal instead: whichever you
answer first counts, and the card goes away.

**A permission.** The card shows what Claude wants to do (for example
"Run: npm install"). **Details** shows exactly what it would run or
change. Below that, the choices are listed one per line, like the
terminal's prompt:
- **Yes** allows it this once.
- Many prompts have more ways to say yes, the same ones the terminal
  offers there, for example **Yes, and don't ask again for: npm test \***
  (saved in the project's Claude Code settings, so Claude won't ask
  for it again), **Yes, allow reading from … during this session**, or
  **Yes, and switch to auto mode** (see Permission modes and plans
  below). Each one says exactly what it does.
- **No** opens the note field below it: type why you said no or what to
  do instead (or leave it empty) and press **Send**. Claude gets the
  note as your next message. As in Claude Code's own prompt, only a "no"
  takes a note: if you change your mind and pick a "yes", the note
  isn't sent.

The world never offers more than the terminal does. Sometimes it offers
a little less: Claude Code doesn't tell the world everything its own
prompt can do. For example, where the terminal offers "don't ask again
for: npm \*", the world may offer only the exact command, such as
"npm --version", and a few prompts have no extra choice at all in the
world. For those, answer in the terminal.

**A plan** to approve comes on the same card; see Permission modes and
plans below.

**A question.** Questions come one at a time ("Question 1 of 2").
Click an option to answer and move on to the next. When you may pick
several, tick them and press **Next**. To answer in your own words, type
in **Other…** and press **Next**. **Back** takes you to an earlier
question. On the last one, nothing is sent until you press **Send**.

The answer buttons and Send only work with a click: no key presses them, so
pressing Enter in the chat can never answer for you. If you close the
chat, the card keeps what you've typed or picked so far. If an answer
can't be delivered, the card says why; answer in the terminal then.

## Permission modes and plans (C06, C07)

Claude Code's **permission mode** sets how freely Claude may work
before it asks you. In the terminal, Shift+Tab moves between four:
- **Manual:** Claude asks before it edits files or runs commands that
  change things.
- **Accept edits:** Claude edits files without asking, but still asks
  before running commands.
- **Plan:** Claude looks around and writes a plan, without changing
  anything, then asks you to approve it.
- **Auto:** Claude rarely asks at all.

A new session starts in Claude Code's own choice (Auto where it's
available).

**The current mode** shows at the top right of the chat, for example
**Mode: Auto**. It appears with the session's first message. If you
switch with Shift+Tab in the terminal, the chat shows the new mode the
next time you send a message or Claude does something.

**Switching from the world.** The world offers the same switches as the
terminal, at the same moments, and nothing more:
- On a prompt to run a command, in Manual or Accept edits, if the
  session has been in Auto before: **Yes, and switch to auto mode**
  allows it and switches the session to Auto.
- On a prompt to edit a file, when the terminal offers it: **Yes, and
  switch to accept edits (…) for this session**.
- When you approve a plan (below).

At any other time, switch with Shift+Tab in the terminal. A switch only
lasts for this session: your Claude Code settings aren't changed.

**Plans.** In Plan mode, when Claude has a plan ready, it appears in the
chat as its own message across the whole width, marked **Plan**. It
stays in the chat as a record, whatever you answer, and a resumed
session shows its earlier plans too. The card under the chat says "The
orchestrator has a plan for you to approve:" and offers the terminal's
own choices:
- **Yes, and use auto mode** (or **Yes, auto-accept edits** if the
  session hasn't been in Auto): Claude goes ahead in that mode.
- **Yes, manually approve edits:** Claude goes ahead in Manual mode,
  asking before each change.
- **No, keep planning:** opens the note field. Say what to change (or
  leave it empty) and press **Send**: Claude reworks the plan.

While a plan waits, the line above the message box says so. You can
answer in the terminal instead: whichever answers first counts. As on
the other cards, these buttons only work with a click.

## Token usage (C08)

The world shows how much a session is using, so you don't have to look
in the terminal. These are the orchestrator's own tokens: subagents'
aren't counted yet. There's no cost in dollars.

**In the chat's header**, next to the mode, for example
**Context 34% · ↑ 2.1M in · ↓ 48k out**:
- **Context:** how full the conversation's context window is after
  Claude's latest step. When the world can't get the percentage (see
  below), it shows the number of tokens instead, such as **Context
  62k**.
- **↑ in:** every token sent to Claude in this conversation so far,
  including the earlier messages Claude Code sends again with each step
  (most of them come from its cache).
- **↓ out:** every token Claude has written, its thinking included.

Hold the mouse over it to see the exact figures. It appears with
Claude's first step and starts over after `/clear`; a resumed
conversation shows its totals so far.

**After each turn** (from one of your messages to the next), a small dim
line says how many tokens Claude wrote for it, for example **↓ 1.2k
tokens**. While Claude works, the line sits at the end of the chat and
goes up after each step it takes.

**Your plan's limits.** With a Claude Pro or Max plan, the bottom-right
corner of the screen shows how much of your 5-hour and weekly limits
you've used and when each starts over, for example **5-hour 74% ·
resets 3:40 PM   Weekly 94% · resets Fri 9:00 AM**. It's the same for
every session, since the limits are your account's (when sessions of
more than one AI tool report limits, each tool gets its own line,
starting with its name, with its limits in that tool's own words), and
stays on screen while you chat or look at
the maps. It appears after Claude's first step in any session, and a
limit is hidden once its time to start over has passed, until a session
hears the new figures.

Numbers are rounded: 950, 1.2k, 34k, 1.1M.

**Where the figures come from.** The token counts come from Claude
Code's own record of the conversation (its transcript). The context
percentage and your plan's limits come from Claude Code's **status
line**: the game sets one for its sessions that only passes the figures
on and shows nothing, so in those sessions the terminal's status line
stays empty, and Claude Code also hides the hints under it ("esc to
interrupt"). If you have your own status line in your Claude Code
settings, the game keeps yours: that session's header then shows the
context in tokens, without a percentage, and it adds nothing to the
corner (which still shows what your other sessions report). The game
looks for your status line when a session starts or resumes, so one you
add or remove meanwhile counts from the session's next start. If your
transcripts are off, only the status line's figures show.

## Subagents (A02, A03, A04)

When the orchestrator hands work to **subagents**, they appear around it
on its island: smaller stand-in figures, each at a little desk with a
computer, facing the orchestrator. The first ones sit in a ring about
10 m out; more rings are added as more of them arrive. Each one keeps its
place while it works.

When a subagent finishes, its desk goes and it walks back to whoever
asked for the work, a sheet of paper over its head, and disappears when
it gets there. If it's asked to carry on later, it comes back to its
desk. Subagents that finished before you opened the world aren't shown.

**What they're doing** shows as a small sign above each agent, the
orchestrator included:
- a spinning **yellow diamond**: working;
- a bouncing **orange "!"**: waiting for you (answer it in the chat or
  the terminal);
- a **red "×"**: something went wrong, or it was stopped. A subagent
  stays like this for about 10 seconds, then disappears;
- nothing: the orchestrator is done with its turn and it's your move.

## When something waits for you (A05)

When an agent needs you (a permission, a question, or anything else it
can't go on without), the game makes sure you notice, even from far
away or from another window. This is a first version: the look is a
placeholder.

- **A light beacon:** a tall orange pillar of light rises from the
  waiting agent, pulsing slowly. You can see it across the ocean, from
  other islands and from the starting platform. It fades away once
  you've answered, in the game or in the terminal.
- **A count:** "2 sessions waiting" in the top-right corner, as long as
  any session waits for you. Open the sessions menu (Tab) to go there:
  the Running list says which ones are "waiting for you".
- **In another window:** if you're in the terminal or another program
  when something starts waiting, the game's taskbar button flashes (on
  macOS its Dock icon bounces) and a short chime plays. While you're in
  the game, there's no flash and no chime: the beacon and the count are
  enough.

To turn the chime off, open the sessions menu (Tab) and untick **Sound
when waiting** at the bottom; the game remembers it.

## When you need to sign in again (S06)

The game never asks for your login: signing in happens only in Claude
Code itself. When Claude Code can't use your account, for example
because your login expired, you signed out, or there's a problem with
the account or its billing, the game tells you and points you to the
terminal:

- **In the chat,** a notice at the top in Claude Code's own words, such
  as "Claude Code needs you to sign in again: run /login in its
  terminal.", and the line above the box says "Waiting for you to sign
  in, in the terminal."
- **In the world,** the orchestrator waits for you like for a
  permission: its orange "!", the light beacon and the "sessions
  waiting" count (see When something waits for you, above).

Go to that session's terminal and sign in (`/login`), or do what it
asks. Then send your message again. The notice goes away once Claude
Code says you're signed in, or as soon as Claude answers again.

While Claude Code can't use your account, a message you send from the
game may never reach it. If a message hasn't shown up in the chat after
about 15 seconds, the line above the box says "Your message hasn't
reached the session. Check its terminal, then send it again." and your
text goes back in the box (only if the box is empty: otherwise when you
next open the chat with it empty). If you clear it, it stays clear; if
you go to another session's chat and come back without sending or
changing it, it comes back. The warning goes when you send again or Claude Code picks a
message up. If your message turns up after all, the text put back in the
box goes too, unless you changed it, so it isn't sent twice. A message
you type in the terminal counts too: after it, the text put back goes,
so copy it first if you still want to send it. (Messages you send while
Claude is busy wait for its turn to end, so they don't get this
warning.)

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
tool. Parts of the world described here are still being built: chatting
(C02), the tool-call log (C04), answering prompts and questions (C05),
the permission mode and plans (C06, C07) and token usage (C08) work,
but stopping from the world doesn't have a button yet, so use the
terminal for that.

**What you need.** Claude Code installed on your computer (version
2.1.284 or newer), signed in with your own account. The game never sees
your login and never changes Claude Code.

**Starting a session.** When you start a session for a project folder, a
terminal opens with Claude Code in it. On Windows, with Windows Terminal,
each session is a tab in one window kept for the game's sessions (your
other terminal windows are left alone); close that window and the next
session opens a new one. Elsewhere, each session gets its own window for
now. Claude Code asks you there
to confirm that it may connect to the game (every time, while this
connection is an early-access feature of Claude Code), and the first time
in a folder, whether you trust that folder. Until you answer, the world
tells you to confirm in the terminal. Once you have, the session's island
rises out of the seabed.

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
- When Claude has a plan for you to approve, approve it or send it back
  with a note in either place.
- **Stop** from the world stops Claude before its next step (the current
  reply or command finishes first); anything it was waiting on you for is
  declined. Pressing Esc in the terminal stops it at once.

How often Claude asks for permission depends on the permission mode you
use in Claude Code: in Auto it rarely asks at all (see Permission modes
and plans).

**Only in the terminal.** Claude Code's own startup questions, its slash
commands (such as `/model` or `/clear`), and switching permission mode
(Shift+Tab) except where a prompt or plan offers it. Ending a session
is `/exit` in the terminal for now.

**Starting over with `/clear`.** If you type `/clear` in the terminal,
Claude starts a fresh conversation in the same session. It stays on the
same island, and the chat window clears right away, with a note that a
new conversation started, and the session is a "New session" again
until your next message names it. The earlier conversation isn't lost:
`/resume` in the terminal brings it back.

**Switching with `/resume`.** If you type `/resume` in the terminal and
pick an earlier conversation, the island stays and the chat changes to
that conversation's right away, with a note saying so, and the session
takes that conversation's name. Messages from the world then go to that
conversation.

**Not available in sessions started from the world.** Claude Code's
agent view (pressing Left at an empty prompt), `/bg` and `/fork`. They
would move your conversation to a background session the world can't
follow, so the game turns them off for its own sessions; your other
Claude Code sessions are unaffected. If a conversation ever does move
anyway, the chat says so: carry on in the terminal, since messages and
answers from the world can't reach it.

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
If the world can't reach the session at all for a moment, sending from
the world says so instead of losing your message; use the terminal.
