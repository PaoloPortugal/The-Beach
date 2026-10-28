# The Beach: user's guide

How to use the app. Only features that are already built are described
here; each section is labelled with its feature ID.

## Contents

- [Running it](#running-it)
- [The main menu (C14)](#the-main-menu-c14)
- [The sessions menu (S03, S04, W07)](#the-sessions-menu-s03-s04-w07)
- [Quitting the game (S05)](#quitting-the-game-s05)
- [Sessions coming back after a restart (S07)](#sessions-coming-back-after-a-restart-s07)
- [Islands kept across restarts (W12)](#islands-kept-across-restarts-w12)
- [Sessions started outside the game (S08)](#sessions-started-outside-the-game-s08)
- [The islands and the ocean (W01, W02, W04)](#the-islands-and-the-ocean-w01-w02-w04)
- [Kinds of island (W10)](#kinds-of-island-w10)
- [Clusters (W05)](#clusters-w05)
- [Bridges and the maps (W06)](#bridges-and-the-maps-w06)
- [Moving around (W03)](#moving-around-w03)
- [Crouching and sliding (W11)](#crouching-and-sliding-w11)
- [Swimming and the sea floor (W08)](#swimming-and-the-sea-floor-w08)
- [Day, night and the weather (W09)](#day-night-and-the-weather-w09)
- [The crosshair (C11)](#the-crosshair-c11)
- [The hotbar (C15)](#the-hotbar-c15)
- [Fishing (D01)](#fishing-d01)
- [Talking to the orchestrator (C01)](#talking-to-the-orchestrator-c01)
- [The chat (C02)](#the-chat-c02)
- [Formatting in the chat (C03)](#formatting-in-the-chat-c03)
- [What Claude did: the tool calls (C04)](#what-claude-did-the-tool-calls-c04)
- [Answering Claude's requests (C05)](#answering-claudes-requests-c05)
- [Permission modes and plans (C06, C07)](#permission-modes-and-plans-c06-c07)
- [Model, effort and mode at launch (C12)](#model-effort-and-mode-at-launch-c12)
- [Token usage (C08)](#token-usage-c08)
- [Subagents (A02, A03, A04)](#subagents-a02-a03-a04)
- [When something waits for you (A05)](#when-something-waits-for-you-a05)
- [When you need to sign in again (S06)](#when-you-need-to-sign-in-again-s06)
- [The pause menu (C13)](#the-pause-menu-c13)
- [Settings (C10)](#settings-c10)
- [Debug commands (C09)](#debug-commands-c09)
- [The sidecar (S01)](#the-sidecar-s01)
- [Claude Code sessions (S02)](#claude-code-sessions-s02)

## Running it

There's no download yet. For now, open the project in Godot 4.7.2 and
press F5: the game opens on the main menu (below); click **Play** and
you arrive on a wooden platform in the open sea. Hold Tab and click
the + to start a session.

The game picks its graphics mode by itself. If it won't start or looks
wrong, you can force the simpler mode by starting it with
`--rendering-method gl_compatibility`; it looks nearly the same, but
without the sun's shadows.

## The main menu (C14)

The game opens on the main menu, titled "The Beach" (a working name).
Behind it the world is already there, dimmed, and the view circles
slowly high above the islands; sessions come back and their islands
rise while you're on it.

- **Play** takes you in: the view glides down to your character, and
  you can move once it's there. You never wait for anything first; an
  island still coming back may rise a moment later. If the island you
  stood on sank while you were on the menu (its session ended), Play
  puts you on the platform.
- **Settings** opens the settings (see Settings (C10)). Esc there takes
  you back to the main menu.
- **Credits** shows who made what: every asset with its source and
  licence (including which visuals were written in code by Claude),
  and that the game is made with Godot Engine. **Show Godot licences**
  under that shows Godot's licence and those of the parts every Godot
  game includes. Scroll to read it; links open in your browser. **Back** or
  Esc returns to the menu.
- **Quit** closes the game, asking first if sessions are still running
  (see Quitting the game (S05)).

To come back to it, press Esc and choose **Main menu** (see The pause
menu (C13)): the view rises back above the islands. Your sessions keep
running, and Play puts you back where you were.

## The sessions menu (S03, S04, W07)

**Hold Tab** anywhere (except while chatting) to bring up the sessions
ring: your running sessions arranged in a circle around a big **+**.
Move the mouse toward a session and **let go of Tab** to go straight to
its island, in front of its orchestrator (if the island is still rising,
once it's up). Only the direction counts, so you don't have to land
exactly on it. The ring has its own pointer, a white dot, held to the
ring as if on a spring: it stops giving at the edge and springs back
when you ease off (it reaches out further over a cluster's sessions when
they fan out). Letting go with the pointer in the middle, or pressing
**Esc**, just closes the ring, so a quick tap of Tab does nothing; so
does switching to another window while holding Tab. What you point at
stays selected while the mouse is still, even if another session comes
or goes meanwhile. While
no session is running, "Hold Tab for sessions" reminds you at the bottom
of the screen. The ring's icons are a first version, like the rest of
the game's screens for now.

- **The house at the top** takes you back to the spawn platform,
  wherever you are, in the water too. It's always there.
- **Each session** shows the kind of island it has (palm tree, tree,
  mountain, snowflake or cactus: see Kinds of island below), with a
  coloured edge for what it's doing: blue working, grey idle, orange
  waiting for you (pulsing), red stopped. A session counts as working
  while any of its subagents works, even if its orchestrator is idle.
  Point at one and the middle shows its name, its project and what it's
  doing.
- **A cluster's sessions sit together** as one stretch of the ring, with
  a small gap before the next cluster and the cluster's name outside it
  (see Clusters below). The order stays put, so you always find a session
  in the same place: clusters in the order of their places around the
  platform, and each cluster's sessions in the order of their islands.
- **With more than 12 sessions**, the busiest clusters each fold into a
  single piece showing how many sessions it holds ("9 ▸"). Point at it
  for a moment (or click it) and its sessions fan out in an arc (at
  most half a circle) just outside the ring; point at one there and let go of Tab. Pointing
  anywhere else folds it back.
- **A session still starting** shows as a faded piece with three dots;
  you can't go to it yet.
- **Click the + in the middle** (while still holding Tab) to open the
  panel for starting or resuming a session (below). You can let go of Tab
  once it's open.

Sessions are named the way Claude Code names them. A new one shows as
"New session" until your first message, which names it for now. If you
typed that message in the terminal, a moment later Claude Code gives the
session a short title of its own, and that replaces it. Claude Code
doesn't do this for messages sent from the game, so a session you start
chatting with in the game keeps its first message as its name. If you rename it with `/rename` in the terminal, that name
is used instead, everywhere in the game. The Resume list uses the same
names as Claude Code's own `/resume` list.

### Starting or resuming a session

The **+** opens **Add a session**. **Esc** goes back a page, and closes
the panel from Add a session; **Tab** closes it from any page. This panel
is still a quick first version, a placeholder: it will be designed
properly later.

**Cluster** says which cluster a session you start or resume joins (see
Clusters below). **Automatic (by repository)**, the choice each time the
panel opens, puts it with the other sessions of its git repository. You
can pick one of the running clusters instead, or **New cluster** to give
it a cluster of its own.

Under that, **Biome** says what kind of island it gets (see Kinds of
island below): **Random**, the choice each time the panel opens, or a
beach, forest, mountain, snowy or desert island.

Then **Model**, **Effort** and **Mode** say what Claude Code starts
with; each is **Default** every time the panel opens (see Model, effort
and mode at launch below).

If the game couldn't find Claude Code, **+ New session…** and **▸
Resume a session…** are greyed out, and under them it says why in red
and where to fix it (**Settings → Providers**; see Choosing Claude Code
yourself, in Claude Code sessions (S02)). They come back as soon as it's
found.

- **+ New session…** opens your system's own folder picker (File
  Explorer on Windows, the usual open panel on macOS and Linux) to
  choose the project folder you want to work in. Cancelling it takes you
  back to Add a session. While it's open, the panel waits with a note: if the
  picker ends up hidden behind the game (this can happen on Windows),
  switch to it (Alt+Tab or the taskbar), press **Cancel** (or Tab) to
  get back to the game, or Esc to go back to Add a session; choosing a
  folder in it afterwards does nothing.
  If your system has no picker of its own, the game shows its own.
- **▸ Resume a session…** lists your earlier Claude Code sessions, newest
  first, with their project and how long ago you last used them. Type in
  the search box to filter them by title or project. Each time the page
  opens, the list takes about a second ("Loading…"), a little longer the
  first time after the game starts. Click one to pick it
  up again where you left off: its chat comes back too. Only sessions
  started in a terminal are listed (not ones from the VS Code extension
  or the Claude desktop app), and only as far back as Claude Code keeps
  them (30 days by default). Sessions still running in a terminal aren't
  listed, so a conversation doesn't run twice; if one is resumed anyway
  (it started running while the list was open), the note says to continue
  it in its terminal, or type `/exit` there and resume it again. This
  needs Claude Code's agent view (and a recent Claude Code): if you've
  turned agent view off, running sessions are listed and can be resumed,
  so check a session isn't open in a terminal before you resume it.
- **✕ Stop waiting for the session starting** shows while a session is
  starting, so you can start another.

Starting or resuming opens Claude Code in a terminal, and
a note at the top of the screen tells you to confirm there (see Claude
Code sessions below). If nothing has happened after two minutes it says
"Still starting; check the terminal, or stop waiting in the sessions menu (hold Tab, click +)."
Once you've confirmed, the session's island rises out of the seabed, and
once it's up you're taken to it, right in front of its orchestrator
(unless you've turned that off in the settings: Settings (C10)).

If the session can't start, the note says why. If Claude Code closes
before it's ready (for example you chose not to trust the folder, or
closed its window), the note says "The session didn't start." straight
away.

One session starts at a time. While one is starting, the panel has
**✕ Stop waiting for the session starting**: it lets you start another.
If the first one does come up later, its island rises and it joins the
ring, but you aren't taken there.

## Quitting the game (S05)

Sessions don't end when you quit: they keep running in their terminal
windows, and come back to the world when you start the game again
(S07, below). So if you close the game (the window, or **Quit game** in the
pause menu) while sessions are running, it asks first. It lists them with what each is doing (scroll the list if
there are many), and reminds you that to end a session you type `/exit`
in its terminal. **Quit** closes the game anyway; **Back to the game**
(or Esc) returns you to where you were. With no session running, the
game just closes. Sessions started outside the game (S08) don't count:
quitting the game changes nothing for them.

On a computer shared with other accounts, the dialog also suggests
ending sessions with `/exit` before quitting: while the game is
closed, another account could reach them (a running session keeps
sending what it does to the game's port, and whatever listens there
could answer it).

The game can't end sessions for you: Claude Code has no clean way to do
that from outside.

## Sessions coming back after a restart (S07)

Sessions the game started come back when you start it again, as long
as they're still running in their terminals: their islands rise
behind the main menu within a moment, while the game looks for
them (C14), their chat holds the conversation so far, and
chatting, answering prompts and questions work from the world again.
Whatever happened while the game was closed (a reply, `/clear`,
`/resume`) is there too. A prompt or question that was open when you
quit stays in the terminal: answer it there.

Sessions started by a version of the game from before this feature
don't come back; while they run they aren't listed under Resume either
(with Claude Code's agent view on, as above). Sessions you started
yourself are shown read-only (see Sessions started outside the game
(S08)).

**"This session started before the game restarted, so it's read-only
here."** This notice means another program took the game's connection
point while it was closed, so the world can't drive the session any
more, only watch it. Its island still comes back, with a grey flag on
it like the islands of sessions started outside the game (S08), and its chat shows
"Read-only: use its terminal." where you'd type. You see what happens
in the terminal a moment late: your messages, its replies (whole, not
word by word), tool calls and subagents, its permission mode, model and
token usage, and the island waiting while it asks you something there.
`/clear` and `/resume` in its terminal are followed within a few
seconds (with Claude Code's agent view on). Everything else, chatting,
answering prompts, questions and plans, and stopping it, happens in
the terminal. Subagents already running when the game restarted don't show,
and with Claude Code's transcripts turned off, only the waiting and the
switches show. The session may also feel slow in its terminal, waiting
on that program at each step. To get everything back, end it with
`/exit` and resume it from the world. The program that took the
connection point gets what the session reports (your prompts, its tool
calls) and could answer its permission prompts, so on a computer shared
with other accounts, end the session with `/exit`.

## Islands kept across restarts (W12)

A session that comes back after a restart gets its own island back: the
same kind of island with the same shape and props, in the same cluster,
under the same name, in the same order as before. Bridges are built
again between them, usually as they were.

If some sessions ended while the game was closed, nothing is left
empty: the islands that come back close up towards the platform, in
their order, and whole clusters close up their slices of sea the same
way. A cluster you made by hand comes back as one made by hand; one made
for a repository still takes that repository's new sessions.

The game keeps this in a small file of its own, `islands.json`, in
Godot's user data folder for the game; it lists each running session's
island and its project folder, never what's said. On macOS and Linux
only you can read it, and a session's entry goes once it's ended.
Sessions started outside the game are in it too, with their session
id (S08). One that disappears during a game stays until the game next
starts, in case its app restarts it, and goes then if it isn't
running; turning them off removes theirs at once. If
the file is missing or damaged, the islands come back as new ones (a
kind picked at random), each joining
its repository's cluster after those that were kept. A session that
was slow to come back, arriving after the world had already appeared,
also comes back as a new island.

## Sessions started outside the game (S08)

Every Claude Code session running on your computer gets an island, not
only the ones the game started: a `claude` you typed in a terminal, the
Claude desktop app's sessions, your editor's (e.g. VS Code), and
background sessions still working or waiting on you. They join their repository's
cluster like any other, and come back as they were after a restart
(W12), even if the Claude desktop app restarted them meanwhile. When
its app restarts one during a game, it rises again with its kind and
shape, but may stand in another spot of its cluster. Short `claude -p` runs and programs built on the Agent SDK
don't get one, and nor do finished background sessions.

The world can only **watch** these sessions. A tall grey flag near the
island's edge marks them (and any other island you can't drive from
the world, S07), and a little grey flag marks them on the minimap and
the big map too. Their chat shows what's said, the tool calls,
subagents, token usage and whether they're working or waiting on you,
a moment late, and says "Read-only: use its own window." where you'd
type: chatting, answering prompts and questions, and stopping it happen
in the window it runs in. When the session ends there, its island
sinks.

The game asks Claude Code which sessions are running every 5 seconds
while its window is in front, every 10 seconds in the background. To
see only the game's own sessions, turn off **Show sessions started
outside the game** in Settings → Game: their islands sink at once and
are forgotten, and rise again as new islands when you turn it back on.
They never get the green beam or arrow of a new island: you didn't
start them.

This needs Claude Code's agent view. With agent view turned off, no
outside sessions are shown, and the setting is greyed out with "Sessions
started outside the game can't be shown: agent view is off in Claude
Code." beside it in red.

## The islands and the ocean (W01, W02, W04)

Each session has its own small low-poly island: a flat spot in the
middle where its orchestrator sits, and around it, on a beach island,
dunes and a sandy beach. There are other kinds too (see Kinds of island
below). Islands are made by the game, so no two look the same.

When a session starts, its island rises out of the seabed, which takes a few
seconds; if you started it from the sessions menu, you're taken there
(the settings' Game tab can turn that off). A green light beam stands
over a new session's island (not one started outside the game) until
you've been on it, and while the island is off-screen a green arrow at
the edge of the screen points to it, with its project's name and how far
it is. (The beam and arrow are a first version, like the rest of the
game's screens for now.) Islands of sessions that were already running
when the game connected rise too (behind the main menu, if it is up),
with no beam.
When a session ends, its orchestrator and subagents
disappear at once. If you're standing on its island, or on
one of its bridges, the empty island stays until you leave it (walk
away over a bridge, swim away, or go to another session or the
platform); then it sinks back into the seabed and is gone. If you're
on the main menu when it ends, or open the menu while you're standing
on an island whose session has ended, it sinks straight away, and Play
puts you on the platform. Islands of the same project sit
together in a cluster (below), and bridges join them to each other and,
for the 8 clusters nearest it, to the platform (W06); the sessions ring (hold Tab) takes you straight to
any of them. The ocean has gentle waves and fades into haze at the
horizon. The water is clear over the shallows and deepens to dark blue
over deep water, so you can see the sea floor (see Swimming and the sea
floor below). To keep the game smooth, islands and bridges lost in the
haze aren't drawn at all, and the steep slopes under the water are
plainer than the land.

## Kinds of island (W10)

An island is one of five kinds, picked in the sessions menu when you
start or resume a session (**Biome**), or at random:

- **Beach**: low and sandy, with dunes, palm trees and tropical plants,
  and sand castles, starfish and shells by the water.
- **Forest**: grassy and a little higher, with trees, pines and bushes.
- **Mountain**: a meadow 20 m up among rocky spires 60-70 m high, snow
  on their tops, and pines. Its beach is under a cliff: a **zipline**
  takes you up. Look at its post on the beach from close by and press
  **E** to ride up; at the top, E on the post takes you back down. You can look
  round while you ride. The zipline stands at the foot of one of the
  valleys up to the meadow, away from the bridges: a new mountain's
  zipline appears once its bridges are up, and if a bridge later comes
  in where it stands, it moves to another valley once nobody is riding
  it.
- **Snowy**: snow, grey rock and snowy pines.
- **Desert**: orange sand, cacti, dry shrubs and red rocks.

Every kind keeps a flat middle for its orchestrator and a narrow beach
round the edge, so you can always swim ashore; above the beach, the
higher kinds rise to a ledge (the mountain's at the top of its cliff),
and from it a few clear valleys lead up to the middle. Islands stand at different heights: a bridge meets each
island at its ledge (a beach island's sand), so a bridge between a low
island and a high one climbs, with steps where it's steep. Trees, palms, rocks
and cacti are solid; bushes, plants, shrubs and the things on the sand
you can walk through. Nothing
grows where a bridge comes in. On the minimap and the big map, an
island is coloured by its kind (an empty one stays grey). Like the rest of the world's look for
now, the trees and rocks are simple placeholders.

Which kind you get is up to you, or chance: it means nothing about the
session, and it isn't remembered, so a resumed session gets the menu's
choice again (Random unless you pick one), and sessions started
outside the game get a random one the first time. A session that comes back after a
restart, or one started outside the game seen before (after a
restart, or restarted by its app), keeps
its kind (see Islands kept across restarts
above).

## Clusters (W05)

Sessions working on the same project share a **cluster**: their islands
sit close together, about 100 m apart. The first 8 clusters each have
their own slice of sea fanning out from the platform, like a slice of
cake: a cluster's first island is the closest to the platform, and
later ones fill the slice outward, as many as you start, never into a
neighbouring slice.

A 9th cluster, and any after it, is put far out at sea, 2 km or more from
the platform. It starts with one island, and later ones gather round
that one, spreading away from the platform.

A session joins its project's cluster on its own. "Same project" means
the same git repository, including its worktrees (for example a
repository and the worktrees Claude Code makes under `.claude/worktrees`).
A folder that isn't in a git repository gets a cluster of its own. A new
cluster is named after the repository's folder; if the name is taken, a
number is added ("game 2"). To put a session somewhere else, choose a
running cluster or **New cluster** in the sessions menu's + panel before starting
or resuming it (a new cluster you ask for is named after the session's
folder).

Clusters last only while they have sessions: when a cluster's last
session ends, it's gone from the ring at once, and its place around the
platform is free again once its last island has sunk. Sessions that
come back after a restart keep their cluster (W12); otherwise the game
doesn't remember clusters after it closes.

A cluster shows in the sessions ring, as its own stretch of the ring
with its name, and on the maps (W06); nothing on the islands says which cluster
they're in yet.

## Bridges and the maps (W06)

Wooden bridges join the islands of a cluster, and a long bridge runs
from the platform out to each of the 8 clusters nearest it, so you can
walk to all of them. A
cluster's bridges make a single path between its islands: each new
island gets a bridge to the nearest one. A bridge appears a moment
after its island has risen and goes as soon as the island starts sinking. If that
leaves part of a cluster cut off, a new bridge joins it back on; the
other bridges stay where they are. If an island comes up where a
bridge passes, that bridge goes as soon as the island starts rising
(if you're standing on it, you drop into the sea). The rest of the
cluster is joined back around it if a bridge can go there, else once
it's up, when the new island is bridged in its place. The bridges have
rails, so you can't walk off them, but you can jump over a rail into
the sea (and swim to a beach to get out). Seen from about 70 m away, a bridge is drawn more
simply, with a smooth deck and one rail a side instead of every plank;
up close it has all its planks again.

A cluster far out at sea (the 9th and later) has bridges between its
own islands but none back to the platform: go there with the sessions
ring (hold Tab) or by clicking it on the big map.

A cluster with a huge number of islands (about 160 for one of the 8
near clusters, about 70 for a far one) can start to reach into another
cluster's sea; nothing stops it yet.

The **minimap** in the top left shows the cluster you're in or nearest
to: its islands (an empty one is grey, a little grey flag marks one
you can only watch), its bridges, the platform when
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
| Crouch, or slide at a sprint | hold Ctrl |
| Swim (in deep water) | W A S D, toward where you look |
| Swim up / down | Space / Ctrl |
| Look around | mouse |
| Pause menu: resume, settings, main menu, quit (frees the mouse pointer) | Esc (Esc again closes it and locks the pointer again) |
| Sessions ring: go to a session or the platform | hold Tab, point, let go (Esc cancels) |
| Start or resume a session | hold Tab, click the + in the middle (Esc goes back a page; Tab closes it) |
| Big map (M or Esc closes it) | M |
| Chat: look at the orchestrator from close by | E (Esc closes the chat) |
| Ride a mountain's zipline: look at its post from close by | E |
| Take a tool from the hotbar (C15) | 1, 2, … or the mouse wheel |
| Fish, with the rod in hand (D01) | hold left click, let go to cast; hold left click to reel in; left click on the bite to hook it, then hold to reel and move the mouse against the fish |
| Debug commands (debug builds only) | T |

The keys follow their position on the keyboard, so on other layouts
(such as AZERTY) use the keys in the same place.

Jumps are forgiving: pressing jump just before you land, or just after
you step off an edge, still counts. Walk into the sea and once it's too deep to stand, you
swim (below).

## Crouching and sliding (W11)

Hold Ctrl to crouch: you get lower (to about 60 % of your height) and
walk at half speed. Let go to stand up again. Under something low you
stay crouched until you've walked out from under it.

Crouch while sprinting and you slide: a burst of speed that fades to a
crouch in about a second on flat ground. On gentle downhill slopes a slide
lasts longer, and from about 13° it speeds up; uphill it stops sooner.
You can steer it a little: hold W and turn with the mouse. Let go of Ctrl to get up.

Jump during a slide for a long, fast jump: you keep the slide's speed in
the air. Land still holding Ctrl and you slide on, but without a new
burst; the next burst comes after a moment on the ground.

In the water, Ctrl swims down instead.

## Swimming and the sea floor (W08)

Out of your depth, you swim. You float at the surface with your head just
above the waves. W A S D swim toward where you're looking, so look down
and press W to dive; Space takes you up and Ctrl down, and Shift swims
faster. There's no air to run out of: stay under as long as you like.
Under the water everything turns blue and fades out after a few dozen
metres.

Swim up fast enough and you leap out of the water like a dolphin, then
splash back in. Only a sprint does it: hold Shift with Space, or with W
while looking steeply up. Swimming up at the normal speed just brings you
to the surface.

The sea floor is everywhere. It's shallow around the platform, and
further out there are winding sandbanks, deeper water and trenches, all
dotted with mounds and hollows. It's sandy where it's shallow and gets
darker and greyer the deeper it goes. Each island sits on its own
shallow shelf, which drops away steeply to the sea floor and darkens with
it, so the two match where they meet. A new session's island rises out of the seabed, and an ended
one sinks back into it, and you can watch both through the water.
After a jump far out to sea, the floor fills in around you over a second
or so, nearest first; the far part is hidden by the haze anyway.

You get out of the water by swimming to a beach and walking up it. You
can't climb or leap onto the platform or a bridge from the water: their
decks are too high. To get back to
the platform from anywhere, hold Tab, point at the house at the top of
the sessions ring and let go, or click the platform on the big map (M).

## Day, night and the weather (W09)

The sun crosses the sky: it rises in the east, climbs high in the south
and sets in the west. A whole day and night takes 28 minutes, 14
of daylight and 14 of night, and every time you start the game it's
mid-morning. As the sun goes down the sky turns gold and orange, and
the moon comes up opposite it.

The night is moonlit, not dark: you can still find your way and swim by
the blue moonlight, the stars come out, and the islands light up. Each
island has a few torches round its edge and a lamp on the
orchestrator's desk, so you can see islands from afar and chat in a warm
pool of light. Chat bubbles and the menus read just as well at night.

The weather changes on its own, slowly: mostly clear, now and then
cloudy, rainy, windy (the waves run faster) or a thunderstorm, with
heavy rain, wind and the odd flash of lightning far away. The lightning
is soft and rare: a short brightening of the sky, never a white-out, at
most one every 10 to 20 seconds. Rain makes rings on the water, and
stops when you dive under. The weather is only for the look: it never
means anything about your sessions.

For now it's all silent; sounds come later. To turn lightning off, open
the settings (Esc, then **Settings**) and untick **Lightning in storms**.

## The crosshair (C11)

A small white ring sits in the middle of the screen. When you look at
something you can use and you're close enough, it grows and says what
**E** does under it: **E  Talk** on an orchestrator, **E  Zipline up**
or **down** on a zipline's post. Press E then to do it. E only acts on
what the crosshair is on: looking away, or from too far, it does
nothing. Nothing works through a wall.

The crosshair hides while you're in the chat, a menu, the sessions ring
or the map. If you'd rather not see the ring, turn off **Crosshair** in
the settings' Game tab; the words still appear when you look at
something, and E still works. Like the rest of the look for now, it's a
placeholder.

## The hotbar (C15)

The tools you carry sit in a row of slots at the bottom of the screen:
**1 Hands** (nothing in your hands) and **2 Rod**, the fishing rod. Press
a slot's number to take that tool, or turn the mouse wheel to step
through them; past the last slot it goes round to the first. The held
slot is outlined in white.

The hotbar shows when you switch and fades out a moment later. It does
nothing while you're in the chat, a menu, the sessions ring or the map.
You start each game with empty hands.

The rod fishes (see [Fishing](#fishing-d01)); the bug net comes later.
The hotbar's look is a placeholder.

## Fishing (D01)

Something to do while your agents work. Take the rod (press **2**) and
it shows at the bottom right of the screen. Fish from any water's edge:
a shore, a bridge or the platform.

**Casting.** Hold the left mouse button: a small meter under the
crosshair fills in about a second, and stays full. Let go to throw the
bobber where you look: the fuller the charge, the harder the throw. A
short tap lands it about 4 m out and a full charge about 22 m, looking
straight ahead; aim higher to throw further, up to about 29 m, where the
line runs out and the bobber drops. You can't cast while swimming.

**The bobber** is a little ball on your line. In the water it floats on
the waves. On land (an island, a bridge's deck, the platform) it lands
and rolls; it's harmless there, but no fish comes to it. Trees, rocks,
plants and people don't get in its way, only the ground does. The line
sags when it's slack and runs straight when it's pulled tight; slack
over land, it lies on the ground rather than through it.

**Reeling in.** Hold the left mouse button while the bobber is out to
reel it in slowly; let go to stop. Reeling drags the bobber toward you
without lifting it: through the water, or rolling over land, and if it
catches on an edge it hops over. When it reaches the platform, a
bridge's end or a steep shore from the water, the line lifts it out. Let go while
it's in the water and it stays there, and the wait for a fish starts
again: so if you threw too far, reel it back a little.

**Fish shadows.** In the clear shallows round the islands you'll see
dark fish shapes wandering just under the surface. Cast near one and
that fish starts toward your bobber within a second or so of it
settling.

**The bite.** Otherwise wait: after a few seconds (4 to 12) a fish
comes to a bobber resting in the water. Its shadow swims up to the
bobber and nibbles once or a few times, each nibble a small dip of the
bobber. Then it bites: the bobber plunges under with a splash ring, and
a gold **!** shows under the crosshair for a second and a half. **Click
then** to hook it, and keep holding: the fight starts.

- Click on a nibble, or before it gets there, and you scare it off:
  **Too soon: it swam off**. Keep holding and you reel in.
- Miss the bite and **It got away**; keep waiting and another comes.

**The fight.** Holding the left button reels the fish in; bring it all
the way to you to land it. While a fish is on the hook the mouse moves
the rod, and the view turns with the rod (and follows the fish when it
swims far to a side). The fish drags the tip of your rod, and your view
with it, toward its side. An **arrow** beside the crosshair points the
other way: move the mouse that way to hold the rod against the fish.
The arrow fades as you do. Holding against it takes some of its pull,
tires it out faster and turns its head round toward you, so it comes
in. Leave the rod on the fish's side and your reeling hardly gains,
and the line strains.

- Every few seconds the fish makes a **run**: it rises near the
  surface, throwing up spray as it goes, and pulls hard away and to a
  side, jerking the rod and the view its way. **Let go** of the
  button: the reel gives it line and the line stays tight. A run tires
  the fish fast, more so with the rod held against it, which can turn
  it and end the run sooner. Between runs it pulls weaker: **reel
  then**.
- The **rod bends** the harder the line pulls. Near its limit the line
  pulls straight and **trembles**, and the view shakes a little.
  Reeling into a run, or with the rod on the fish's side, and **The
  line snapped**: the fish is gone (and so is the bobber, but you get
  it back for the next cast).
- Walking away while you reel tows the fish, and strains the line like
  reeling harder: fine with a tired fish, a snapped line with one that
  pulls.
- When the fish **swims toward you**, the line goes slack: keep
  reeling. Left slack for a couple of seconds, **It slipped off the
  hook**.
- If it takes out all your line (30 m), the line snaps too.
- The **shadow** shows where the fish is, and the bobber is pulled
  under there. Close to you, the fish is pulled up out of the water,
  hanging from the line, just before you land it.

Shallows fish are small and quick to land (about ten seconds); drop-off
fish fight harder (twenty seconds or more); open sea fish are strong
and tire slowly (most of a minute). Bigger fish of a kind
pull harder. If an agent starts waiting during a fight, the "sessions
waiting" count in the corner pulses once; nothing pauses.

**Moving and leaving.** You can walk about while the line is out: it
pays out up to 30 m. Further than that, you drag the bobber after you,
and the fish on the line swims off (in a fight, see walking away
above). Taking another tool, opening the
chat, a menu, the sessions ring or the map, swimming, or riding a
zipline reels in at once, in a fight too. The only thing you lose is the fish on the
line: there's no bait, streak or record to lose.

**A catch** (a fish landed) shows a card high on the screen with the fish and
its size, for example "You caught a Drop-off fish!" and "34 cm", marked
**New** the first time you catch that species.

**What bites** depends on where and when you fish: the water under the
bobber (the shallows by an island, the drop-off where the shelf ends,
or the open sea), the kind of the nearest island, the time of day and
the weather. For now there are only three placeholder species, one for
each water, which bite at any time and in any weather: **Shallows
fish**, **Drop-off fish** and **Open sea fish**. Fishing never depends
on what your agents are doing.

Every catch is kept (each species, how many, the biggest and the first)
for the collection that comes later. The rod, the bobber, the shadows,
the splash, the meter, the "!", the fight's arrow and the card are
placeholders.

## Talking to the orchestrator (C01)

In the middle of each island, an AI agent sits at a desk: the
**orchestrator** of that session, the one you talk to. For now it's a
plain stand-in figure.

Walk up to it and look at it: the crosshair grows and says **E  Talk**
(see The crosshair (C11)). Press E to open the chat:
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

**The chat** (E, looking at the orchestrator) shows the whole conversation:
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
below), the model and effort it runs with, such as **Opus 5.5 · High
effort** (see Model, effort and mode at launch below), and how many
tokens it uses (see Token usage below).

Above the box, a line says what the orchestrator is doing: working, or
waiting for you. If a reply stopped for a reason Claude Code reports (a
usage limit, the service busy or failing, a reply too long, ...), the
line says so and what to do. When it waits on a permission, a question or a plan, a
card above that line lets you answer it (see below). Only the latest 200
messages are shown at once. A long chat appears newest first, and the
older messages fill in above it over a moment while the view stays
put.

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
available), unless you pick a mode when you start it (see Model, effort
and mode at launch below).

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

## Model, effort and mode at launch (C12)

When you start or resume a session (hold Tab, click **+**), three
choices under Biome say what Claude Code starts with:
- **Model:** **Default** (Claude Code's own choice), **Opus**,
  **Sonnet**, **Haiku** or **Fable**, each the newest of its kind.
- **Effort:** how hard Claude thinks: **Default**, **Low**, **Medium**,
  **High**, **Extra high** or **Max**.
- **Mode:** the permission mode (see above): **Default** (Claude Code's
  own choice), **Manual**, **Accept edits**, **Plan** or **Auto**.

Each goes back to **Default** every time the panel opens, so a choice
only counts for the session you start with it. They work the same on
the Resume page. Picking one is the same as starting `claude` with it
yourself; the terminal shows the result, and the game never changes your
Claude Code settings. Bypass permissions and Don't ask aren't offered.

**In the chat**, beside the mode at the top right, you see the
session's model and effort, for example **Opus 5.5 · High effort**.
They appear once Claude Code tells the game, and follow any change you
make in the terminal (for example with `/model`). In Plan mode Claude
Code may answer with a stronger model than the one you picked (it does
this on purpose for planning). If you use your own status line in
Claude Code, a new session's model may only show once you switch
models.

## Token usage (C08)

The world shows how much a session is using, so you don't have to look
in the terminal. These are the orchestrator's own tokens: subagents'
aren't counted yet. There's no cost in dollars.

**In the chat's header**, next to the model and the mode, for example
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

When a subagent finishes, it stands up and throws a sheet of paper, its
report, to whoever asked for the work, which gives a little bob as it
lands; then the subagent and its desk disappear. It all takes about a
second, from near or far. (Claude already has the report by the time
the world shows it, so the orchestrator may start on it just before the
paper lands.) If it's asked to carry on later, it comes back to its
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
  any session waits for you. Hold Tab for the sessions ring to go there:
  the waiting ones have a pulsing orange edge.
- **In another window:** if you're in the terminal or another program
  when something starts waiting, the game's taskbar button flashes (on
  macOS its Dock icon bounces) and a short chime plays. While you're in
  the game, there's no flash and no chime: the beacon and the count are
  enough.
- **While you're fighting a fish** (with the rod), a new wait makes the
  count pulse once, since your eyes are on the line. Nothing pauses:
  drop the rod (press 1) to go, and you lose only that fish.

To turn the chime off, open the settings (Esc, then **Settings**), go
to **Sound** and untick **Sound when waiting**; the game remembers it.

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

## The pause menu (C13)

Press **Esc** to open the pause menu: the screen dims, the mouse pointer
is free, and you stop moving. (If the chat, the sessions menu or the
map is open, Esc closes that first.) It has four buttons:

- **Resume** (or Esc) takes you back to the game.
- **Settings** opens the settings (below). Esc there takes you back to
  the pause menu.
- **Main menu** takes you back to the main menu (see The main menu
  (C14)); your sessions keep running.
- **Quit game** closes the game. If sessions are still running, it asks
  first, as closing the window does (see Quitting the game (S05));
  **Back to the game** there leaves you in the pause menu.

The game doesn't stop while it's open: your sessions keep working, and
the day and the weather carry on.

## Settings (C10)

Open the pause menu (**Esc**) and choose **Settings**; Esc goes back to
the pause menu. Every
change takes effect at once and is remembered; **Reset to defaults**
puts everything back.

- **Graphics:** the window (windowed, borderless fullscreen or
  fullscreen), vsync, a frame-rate cap, the render scale (draw the world
  at a lower resolution for speed; the text stays sharp), shadow quality
  (high, low or off), anti-aliasing, and lightning in storms on or off.
  - *Anti-aliasing (MSAA)* smooths the jagged, stair-stepped edges of
    shapes: off (the default), 2×, 4× or 8×. Higher is smoother and
    slower; on a fast computer, try 4×.
  - *Screen-space anti-aliasing* (off, FXAA or SMAA; SMAA by default)
    smooths the whole picture a little, at a small cost, and blurs it a
    little. SMAA is the sharper of the two; on a slow computer, turning
    it off makes the game a little faster.

  On computers that run the game in its simpler compatibility mode
  there are no shadows and no screen-space anti-aliasing, so those two
  are greyed out.
- **Controls:** mouse sensitivity and field of view.
- **Sound:** the chime when something waits on you while you're in
  another window (see When something waits for you (A05)).
- **Game:** whether starting a session takes you to its island. Turned
  off, you stay where you are; its green beacon and the arrow at the
  screen's edge show where it rose. And **Crosshair**: off hides the
  ring in the middle of the screen; what E does still shows when you
  look at something (see The crosshair (C11)). And **Show sessions
  started outside the game** (on by default): off, only the game's own
  sessions have islands (see Sessions started outside the game (S08)).
  Greyed out, with the reason in red, when Claude Code's agent view is
  off; your choice is kept for when it's back on.
- **Providers:** settings for the AI tools the game runs. **Claude
  Code**: which Claude Code the game runs, with **Browse…** to choose it
  yourself, **Look again** to look for it now and **Reset** to let the
  game find it again (see Choosing
  Claude Code yourself, in Claude Code sessions (S02)). Reset to
  defaults leaves this one alone. While no tool has anything to set, the
  tab says so.

## Debug commands (C09)

For trying things out while developing, in builds made for debugging
(running from the Godot editor or a debug export; not in a release).
Press **T** while walking around: a line opens at the bottom left with
the "/" already typed. Type the rest and press **Enter** to run it, or
**Esc** to close it. **Up** and **Down** bring back what you ran before.
The answer shows above the line for a few seconds.

- **/time set noon** jumps to a time of day: `midnight`, `sunrise`,
  `day` (the mid-morning you start at), `noon`, `sunset`, `night`, or
  minutes and seconds from midnight on the 28-minute day, like `7m`
  (sunrise), `21m` (sunset) or `10m22s`.
- **/time add 2m** moves the time on; **/time query** says what time it
  is; **/time speed 2** makes days go twice as fast (14 minutes),
  **/time speed 0** stops the clock (the weather still changes), and
  **/time speed 1** puts them back to normal (28).
- **/weather storm** changes the weather at once (`clear`, `cloudy`,
  `rain`, `windy`, `storm`); after that it goes on changing by itself
  as usual, a few minutes later. **/weather query** says what it is.
- **/lightning** makes lightning strike now, whatever the weather.
- **/help** lists them.

These are separate from the chat: a "/" you type in the chat box is
part of your message to the session, as before.

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
  conversations. For each session it starts it keeps a small folder in
  your app data folder (`The Beach/agent-sessions/`: where the session
  runs and how to reach it, never what's said), so the session can come
  back after a restart; the folder goes when the session ends.

If the sidecar can't start or stops unexpectedly, the game notices; for
now that only shows in the game's log, and a message on screen comes with
the world. The sidecar file ships next to the game's own executable;
reinstalling the game restores it if it goes missing.

## Claude Code sessions (S02)

The world runs **Claude Code**, Anthropic's coding assistant, as your AI
tool. Parts of the world described here are still being built: chatting
(C02), the tool-call log (C04), answering prompts and questions (C05),
the permission mode and plans (C06, C07), choosing the model, effort
and mode at launch (C12) and token usage (C08) work,
but stopping from the world doesn't have a button yet, so use the
terminal for that.

**What you need.** Claude Code installed on your computer (version
2.1.284 or newer), signed in with your own account. The game never sees
your login and never changes Claude Code.

**If Claude Code isn't found.** The game looks for Claude Code as soon
as it starts, in the background, and again each time you start or
resume a session, so an update or a move is noticed. It looks where the
installers put Claude Code. If it isn't found, you can't start or resume
a session (see Starting or resuming a session) until it is: install it
and press **Look again**, or choose it yourself (below). On macOS and Linux, if you installed it with npm under a
Node version manager (nvm, fnm, Volta, asdf, mise), a game started from
the Dock or an app menu can't see it at first. The game then asks your
shell, the way a terminal starts it, which folders it searches, and
looks there too, once each time the game runs (and again when you press
Look again). This takes a moment and
runs your shell's startup files without showing you a window: nothing
can answer a question they ask, and if they take more than 10 seconds
the game gives up and says Claude Code wasn't found. On Windows this
isn't needed.

**Choosing Claude Code yourself.** If the game can't find Claude Code,
or finds a different one from the one you want, choose it in **Settings
→ Providers → Claude Code**. The row shows which one the game uses (where it
is and its version, and "set by hand" if you chose it), or in red why
there's none. Right after the game starts it may say "Looking for it…"
for a moment.
- **Browse…** opens your system's file picker. Choose the Claude Code
  program itself: on Windows that's `claude.exe` (an npm `claude.cmd`
  won't do; the picker only shows `.exe` files), on a drive of this
  computer, not a network folder. The row says
  "Checking…" while the game makes sure it's a full path to a program
  that answers as Claude Code 2.1.284 or newer. If it isn't, the reason
  shows in red ("Not changed: …") and the one you had stays.
- **Look again** looks for Claude Code now, for example after you've
  installed it while the game runs; the row says "Looking…" until it
  knows. If you chose one yourself, it checks that one again (say, after
  putting it back) and looks nowhere else.
- **Reset** forgets your choice and lets the game find Claude Code as
  usual again, at once. It's greyed out while nothing is chosen.
- Only your choice is remembered: what the game finds by itself is
  looked for again each time, so it never sticks to an old copy.
- Your choice is remembered and used for every session you start or
  resume from then on; sessions already running keep theirs. It's the
  **only** one the game uses: if you move, delete or downgrade it, the
  row and the next session you start say why it doesn't work ("The
  Claude Code set in Settings doesn't work: …"), and the game never
  quietly runs another one. Choose it again, or press Reset.

Claude Code installed inside WSL isn't supported on Windows: install
the Windows version.

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
