# NOTES.md sanity check

Features: docs

The user asked for a review of the whole project, focused on NOTES.md, for
stale, wrong or irrelevant information, together with the C07 reference fix
(it pointed at "C04's questions"; C04 is the tool-call log).

## Wrong

- **Desktop app.** Deliberate limitations said the Claude desktop app keeps
  its own session store and doesn't read `~/.claude/projects/`. This session
  runs in the desktop app and its transcript is in that folder, and the docs
  (checked 2026-09-29) say the desktop app can `/resume` CLI sessions and
  `/desktop` moves a CLI session into it. Rewritten: still no way for us to
  launch into or watch desktop sessions, but they interoperate with the CLI.
  S04 notes that listing desktop sessions is to check when it's built.

## Stale

- Protocol and schema said terminal-typed text and terminal answers show up
  "once attaching exists"; with the CLI route they do in v1.
- S02 said the provider never passes a permission mode; C06 now allows the
  user to pick one at launch.
- M0 still described the integration spike as a plan; replaced by a summary.
- Security rules still said "the spike checks" fail-safe behaviour; it's
  verified. The hook-token wording implied environment-variable headers,
  which the design no longer depends on.
- The layout table didn't list `spikes/` or `docs/flows.md`.
- The Concept didn't mention the user's goal of switching freely between
  the world and the terminal; added.
- README: outdated Claude Code docs link, "TypeScript on Node" as a runtime
  requirement (now Node.js), no mention of channels' plan requirements, no
  link to the flow diagrams.

## Needed a decision (recorded as open question 7)

The agents were still described as "logo" models in the Concept, A01, A02,
M1 and the README, although Anthropic's terms don't allow using their logos
without permission (asked on 2026-09-29, not yet answered). Descriptions
now say "models at little PCs", and open question 7 tracks the look.
