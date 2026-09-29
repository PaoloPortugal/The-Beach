# Privacy check before going public

Features: tooling

The user plans to make the repo public and asked for a check of the files
and the full history for sensitive information.

## Scan (all 37 commits, every file version)

- No secrets: no API keys, tokens, private keys, bearer tokens or long hex
  strings. The spike's tokens were random per run and only ever lived in
  git-ignored run files.
- No machine paths (`C:\Users\...`, `AppData`) in any committed file.
- `.mcp.json` (committed with the old godot_mcp plugin, later removed) only
  held `http://127.0.0.1:3000/mcp`, no token.
- Git-ignored and never committed: `.godot/`, `spikes/claude-cli/logs/`
  (session content), `spikes/claude-cli/runs/` (tokens), `node_modules/`.
- Personal details present by choice: name and dev name in `LICENSE`,
  GitHub username in the README clone URL.

## Personal email on every commit: kept, by choice

All commits carry the user's personal Gmail address as author. The user
first chose to hide it: the history was rewritten to GitHub's noreply
address and force-pushed. Then, on learning that GitHub may keep old
commits reachable by exact ID after a rewrite (per GitHub's docs, until
Support purges them), and since the address is already public on the
user's other repos, the user decided to keep it public and asked to roll
back. The original history was restored from a bundle taken before the
rewrite (same commit IDs, `dadc774`) and force-pushed again, and the
repo's git config was reset to the user's normal address.

Merged local branches (docs/provider-scope, setup/*, tooling/*), deleted
before the rewrite and never pushed, stay deleted.
