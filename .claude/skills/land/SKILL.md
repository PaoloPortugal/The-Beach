---
name: land
description: Finish a feature branch for the user's review by walking NOTES.md's "When a feature lands" checklist (Systems section, index row, GUIDE, flows, CREDITS, dev log, Current focus), then running the verify skill and the docs-sync and security reviewers. Use when a feature or fix is built and about to be called ready, or when the user says /land <ID>.
argument-hint: <feature ID, e.g. C06> [more IDs]
---

# Land a feature

Feature(s): $ARGUMENTS. If none were given, infer them from the branch name
and the diff, and say which you picked.

The goal is a branch the user can review and merge without spotting drift
between the code and the docs. You never merge to `main` and never push
`main` (CLAUDE.md, and the user does that push).

## 1. Gather

- `git diff --stat main...` and `git log --oneline main..` for what the
  branch changed.
- NOTES.md: the `### <ID>` section(s), the feature index, "When a feature
  lands", and whatever Architecture / Protocol / Conventions parts the diff
  touched.
- `docs/GUIDE.md`: the feature's section, if it has one, and the contents list.
- `docs/devlog/README.md`, and earlier entries for these IDs (grep `Features:`).

Re-read each file right before editing it: the user changes things between
sessions.

## 2. Walk the checklist

Read the checklist from NOTES.md → "When a feature lands" (don't use a
remembered copy) and do every item in order. For each one, either make the
edit or say why it doesn't apply. Things that are easy to get wrong:

- **Systems section**: replace the planned intent with how it works now,
  and state the **provider scope** (core / capability / extension). If the
  scope was never decided, stop and ask the user. Don't pick one.
- **Index row**: status wording matches the others ("built",
  "built (UI placeholder)", "placeholder built", …), plus guide section and
  main code paths that exist (check them).
- **GUIDE.md**: plain language for a player, built behaviour only, nothing
  planned. Add it to the contents list. Then re-read the guide section
  against the NOTES section, sentence by sentence.
- **Flow diagrams**: required if S02 or Protocol changed (CLAUDE.md): the
  matching file in `docs/diagrams/sequence/`, following the header
  `docs/flows.md` describes. A new flow also gets a row there. If a
  component was added or moved, update the component diagram in NOTES.md
  → Architecture.
- **CREDITS.md**: every new file under `assets/` (check the diff) has a row.
  Never AI-generated.
- **Dev log**: `docs/devlog/YYYY-MM-DD-<slug>.md` in the format in
  `docs/devlog/README.md`, plus its row in that table. Record decisions and
  rejected alternatives. **Only say a decision was the user's if it was, and
  give the reason they gave.** If you don't know the reason, ask; don't
  invent one.
- **Current focus**: update the line at the top of "Known issues and next
  steps".
- The codename rule (NOTES.md → Conventions → Renaming the project): no new
  appearances outside the listed places.

## 3. Check

Run these. The two reviewers are read-only and can run in parallel:
1. the `verify` skill;
2. the `docs-sync` subagent, given the feature IDs;
3. the `security-reviewer` subagent, if the diff touches `sidecar/`,
   `core/`, `protocol/`, anything that launches processes or handles
   session content, or `.github/`.

Fix what they find, or bring a finding to the user if fixing it would be a
design decision. Re-run whichever check covered the fix.

## 4. Hand over

Commit the docs in small commits (docs separate from code, like the
history: "Docs: <ID> built; …"). Push the branch. Then tell the user:
- what the feature does, in two or three lines;
- the check results (suites, a CI run if there is one, reviewer findings and what you did
  about each);
- what still needs a **live check** by the user, with the steps written to
  `tests/live/checklist.txt` (`godot --path . -- --checklist`);
- that it's ready for their review.
