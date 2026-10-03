# C05 reopened: the terminal's other prompt options (in progress)

Features: C05, C06, S02

## Decided (user's, 2026-10-03)

- **Offer them.** The terminal's prompts offer more than Yes/No ("Yes,
  and don't ask again for: npm test *", "Yes, allow all edits during
  this session", ...). The world offers them too, settings-file rules
  included: Claude Code writes the rule; the world only passes on a
  choice the user could make in the terminal, over our secured route.
  "We don't strip away any capabilities we are able to offer."
- **Hold the hooks** of every prompt that needs it: "we put in the work
  wherever it stays truer to the vanilla experience."
- **Source: Claude's own suggestions** (my recommendation): offer exactly
  the entries Claude Code puts in each prompt's `permission_suggestions`,
  worded by entry type to match the terminal. Options with no entry stay
  terminal-only. Rejected: a hand-built per-tool catalog (re-implements
  Claude Code, breaks silently when its dialogs change).
- **Card: a terminal-style list** (my recommendation): one button per
  line in the terminal's order and words, "Yes", the extra options,
  "No" (which still opens the note and Send). Replaces the Allow/Deny
  row.
- **Protocol: one general list** (my recommendation): a permission's
  `options` replace C06's `modes`; "Yes, and switch to auto mode" becomes
  one option among them.

## From the docs (code.claude.com/docs/en/hooks, permissions, permission-modes; 2026-10-03)

- `permission_suggestions` entries are permission updates (`addRules`,
  `replaceRules`, `removeRules`, `setMode`, `addDirectories`,
  `removeDirectories`), each with a `destination` (`session`,
  `localSettings`, `projectSettings`, `userSettings`). **No labels.** A
  hook can echo one back as `updatedPermissions` (allow only).
- "The `permission_suggestions` array isn't an exact list of the options
  you see": edit dialogs build their own options, settings can hide some,
  and some options have no entry ("Yes, and switch to auto mode").
- "Don't ask again" lasts: Bash and WebFetch permanently per repository
  (`.claude/settings.local.json` at the repository root), file edits until
  the session ends, WebSearch permanently per repository.
- Options with no hook equivalent: "No, and block reads outside the
  working directories from now on" (writes a user setting on a deny);
  "Yes, and allow Claude to edit files in this project's .claude folder
  for this session".

## Probe (claude 2.1.288, `claude -p`, default mode, unattended)

A scratch script ran `claude -p` with `PermissionRequest` (matcher `*`)
and `PreToolUse` HTTP hooks to a local logger answering `{}` (no
decision, so print mode refused each call), in a temp git repository.
What each prompt's hook carried:

| Prompt | `permission_suggestions` |
|--------|--------------------------|
| Bash `npm --version` | addRules `Bash(npm --version)` allow, localSettings |
| Bash `git status && npm test` | addRules `Bash(npm test *)` allow, localSettings (only the part needing approval) |
| Bash `cd <outside> && node -e "1"` | addRules `Read(//c/…/outside-xyz/**)` and `Bash(node -e "1")` allow, localSettings (one entry, two rules) |
| Edit / Write in the folder | setMode acceptEdits, session |
| Write in `.claude/agents/` | setMode acceptEdits, session (the terminal's option differs, per the docs) |
| Read outside the folder | addRules `Read(//c/…/outside-xyz/**)` allow, **session** |
| WebFetch example.com | addRules `WebFetch(domain:example.com)` allow, localSettings |
| WebSearch | addRules `WebSearch` (whole tool) allow, localSettings |
| PowerShell `Get-ChildItem \| Out-File list.txt` | addDirectories (the working folder), session; setMode acceptEdits, session |

Every prompt had at most one or two entries. Print mode may differ from
the interactive terminal; the live session checks the same prompts.

Next: a live session with the user at the terminal, screenshots of each
dialog, to take the terminal's words per entry type and see whether the
terminal shows one option per entry.
