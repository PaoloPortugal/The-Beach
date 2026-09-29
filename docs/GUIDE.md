# The Beach: user's guide

How to use the app. Only features that are already built are described
here; each section is labelled with its feature ID.

## Contents

- [Running it](#running-it)
- [The sidecar (S01)](#the-sidecar-s01)

## Running it

Nothing is playable yet. Once it is, this section will explain how to
open the world on Windows, macOS or Linux.

## The sidecar (S01)

The game comes with a small helper program called the **sidecar**. The
game starts it for you in the background and it closes when the game
closes, even if the game crashes. You never need to start it yourself, and
no window opens for it.

The sidecar is what will run your AI coding sessions and pass what they're
doing to the world. For now it only connects to the game; running
sessions arrives with the Claude provider (S02).

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
