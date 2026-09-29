# CLAUDE.md

Working rules for this repo. Read `NOTES.md` first every session.

## Docs

- `NOTES.md`: developer reference and **single source of truth for the design**.
- `docs/GUIDE.md`: user's guide, built features only, written from NOTES.md.
- `docs/devlog/`: history of decisions, bugs and dead ends. Look up by feature ID.
- `docs/flows.md`: step-by-step diagrams of how the pieces talk. Update it
  with any change to NOTES.md → S02 or Protocol.
- `README.md`: pitch and setup for newcomers.
- `assets/CREDITS.md`: source and license of every asset.

**The guide must always match NOTES.md.** Any feature change, even a tweak,
updates its NOTES section, its index row and its guide section in the same
branch before merging. Then write the dev-log entry. Follow the
"When a feature lands" checklist in NOTES.md.

## How we work

- **Ask before deciding anything that shapes the design**: open questions,
  the event schema, UX feel, art direction. Give a recommendation with
  trade-offs, then wait. For implementation details with an obvious
  conventional choice, go ahead and say what you picked.
- **One branch per feature**, small reviewable commits. Say when a feature
  is ready; the user reviews before it merges to `main`.
- **The user changes things between sessions.** Re-read a file before
  editing it. If code and docs disagree, ask which is right.
- Keep the "Current focus" line at the top of NOTES.md's next-steps section
  current.

## Hard rules

- "The Beach" is a temporary codename: docs, README and window title only,
  never in code identifiers, class names or the protocol. Every place it
  appears is listed in NOTES.md → Conventions → Renaming the project.
- Decide every new feature's provider scope (core / capability / extension)
  before building it, and keep Claude naming where NOTES.md → Multi-provider
  rules allows it.
- Art is low-poly, made by the user or CC0 (e.g. Kenney), **never
  AI-generated**. Don't create art assets unless asked for a placeholder.
  Record every asset in `assets/CREDITS.md`.
- Don't move or rename anything in the Godot project without asking.
- Follow NOTES.md → Principles and Security rules. Security and fail-safe
  behaviour are tested, not assumed.
