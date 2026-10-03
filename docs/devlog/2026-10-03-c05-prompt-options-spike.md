# C05 reopened: the terminal's other prompt options

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

## Live (claude 2.1.288, the user at the terminal, default mode)

A logger answered every `PermissionRequest` (matcher `*`) with no
decision, so the terminal asked as usual; the user screenshot each
dialog. Same nine prompts; the hooks carried the same suggestions as in
print mode.

| Step | The terminal's extra option | The hook's suggestion | Same effect? |
|------|------------------------------|-----------------------|--------------|
| 1 Bash `npm --version` | "Yes, and don't ask again for: npm \*" | `Bash(npm --version)`, localSettings | **No**: the terminal saved `Bash(npm *)` (run 2) |
| 2 Bash `git status && npm test` | "Yes, and don't ask again for: npm test \*" | `Bash(npm test *)`, localSettings | yes |
| 3 Edit a.txt | "Yes, and switch to accept edits (auto-approve file edits and common file commands) for this session (shift+tab)" | setMode acceptEdits, session | yes |
| 4 Read outside | "Yes, allow reading from /c/Users/…/outside-live during this session" | `Read(//c/…/outside-live/**)`, session | yes |
| 5 Bash `cd <outside> && node -e "1"` | "Yes, and allow access to /c/…/outside-live and \"node -e \\"1\\"\" commands" | one entry, two rules, localSettings | yes (one option for the entry) |
| 6 Write `.claude/agents/x.md` | "Yes, and allow Claude to edit files in this project's .claude folder for this session" | setMode acceptEdits, session | **No**: the terminal's choice left the mode at default (run 2) |
| 7 WebFetch | "Yes, and don't ask again for example.com"; No reads "No, and tell Claude what to do differently (esc)" | `WebFetch(domain:example.com)`, localSettings | yes |
| 8 WebSearch | "Yes, and don't ask again for Web Search commands in ~\AppD…" (cut off) | `WebSearch`, localSettings | yes |
| 9 PowerShell | "Yes, and always allow access to C:\…\garden-live from this project" | addDirectories (the folder) + setMode acceptEdits, both session | **No**: the mode stayed default, nothing was written to settings files or `~/.claude.json` (run 2) |

- **One extra option per prompt**, plus "Yes, and switch to auto mode" on
  Bash only (as C06 does; not on PowerShell, as the docs say). It stands
  for all the entries together (steps 5 and 9).
- Run 2 picked the extra option on steps 1, 6 and 9; repeats of 1 and 6
  then didn't ask. `.claude/settings.local.json` got only `Bash(npm *)`;
  every later hook still reported `default` mode.
- So echoing the suggestion matches the terminal in six of nine; in the
  other three the terminal applies something the hook doesn't report: a
  wider Bash prefix (1), a `.claude`-only session allowance (6), and
  apparently the folder only, without the mode switch (9).

## Decided after the live run (user's, 2026-10-03)

**Never allow more than the terminal** (my recommendation; the
alternatives were offering every suggestion as it is, which would switch
to Accept edits where the terminal doesn't, or only kinds seen to match,
which drops Bash's "don't ask again"). Each option is labelled by exactly
what it does. Where we know a suggestion allows more than the terminal's
option (a mode switch on writes in a `.claude` folder, and on PowerShell
prompts) that part is left out, and the option too if nothing is left.
Bash's "don't ask again" saves the hook's narrower rule, with the exact
rule on the button.

**Why we offer what we offer** (asked by the user to be recorded):
- The aim is the terminal's choices, no more and no less. The world only
  knows what the hook tells it; the terminal's dialog sometimes does
  things the hook never reports, so an exact copy isn't possible.
- Where the two agree (six of the nine prompts tried), the world offers
  the same choice with the same effect, worded like the terminal.
- Where they differ, the world offers **less, never more**: a narrower
  Bash rule (`npm --version` where the terminal saves `npm *`; the
  terminal's prefix logic is undocumented, and copying it would be
  re-implementing Claude Code), no extra option on `.claude` writes (the
  only suggestion is a mode switch that would allow every edit), and
  PowerShell's folder access for the session without the mode switch.
  Allowing less only means Claude asks again later; allowing more would
  be acting beyond what the user chose, which the Principles forbid.
- Every button says exactly what it does, even where the terminal's
  wording differs, so the user is never told one thing while another
  happens. The terminal keeps its full options for anything the world
  can't offer.

## Protocol and wording (approved by the user, 2026-10-03)

- **Protocol:** a permission's optional `options` (`{option, label}`, in
  the provider's own order: the extra ways to allow) replace C06's
  `modes`; `permission.respond`'s optional `option` (allow only, one of
  them) replaces `mode`. Core scope: any tool's prompt can have them.
  Labels come from the provider; Godot shows them as they are. A mode
  change still comes as `session.updated` (`permission_modes`). Plans
  keep their `modes`.
- **Card:** Yes, the options, No (No keeps the note and Send).
- **Fixed "Yes" and "No"** (my recommendation): the terminal's No on
  WebFetch reads "No, and tell Claude what to do differently (esc)", but
  it does the same, and the note field covers it. Rejected: sending the
  Yes/No words per prompt too.
- **Prompts not seen yet** (MCP tools, other tools, other settings
  files): offered with an honest label built from what the entry does
  and where it's saved (my recommendation), rather than terminal-only
  until checked. Mode switches in them are still dropped. **A stopgap**
  (user's, 2026-10-03): each such kind is to be checked live later and
  given the terminal's own wording, to stay truer to the terminal; NOTES
  keeps the list.
- **Mode switches** from a suggestion are kept only on file edits outside
  a `.claude` folder (seen to match the terminal); Bypass and Don't ask
  are never offered.
- **Holding:** a prompt's hook is held whenever it has options; prompts
  without any are answered at once, as before.
