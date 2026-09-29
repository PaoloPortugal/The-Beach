# Principles and security rules

Features: docs

## Decision (user's)

The user stated the vision: touch as little of what Claude provides as
possible and simply provide a pretty interface for using it; never create
an app with vulnerabilities or one that damages the user through poor
quality. The app is meant for free public release. Recorded as Principles
in NOTES.md → Concept.

## Result

NOTES.md → Architecture → Security rules turns that into checkable rules.
The reasoning: the CLI route adds local entry points (sidecar WebSocket,
hook endpoint, bridge connection) that can approve tool use and send
messages into a session, so they are as sensitive as the user's keyboard.
Main risks addressed: other local programs or malicious web pages
connecting to localhost (tokens, loopback only, Origin check), the app
approving things on its own (nothing without a user action; fail safe to
the terminal), command injection when launching `claude` (argument arrays),
BBCode injection from model or file output (escape), and data leaving the
machine (no telemetry, read-only access to Claude's files).

The integration spike now also checks fail-safe behaviour and hook token
headers. CLAUDE.md points to the rules.
