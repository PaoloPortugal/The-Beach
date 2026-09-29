// Variables Claude Code sets inside its own sessions (in its tools, hooks and
// MCP servers, and in apps that host it). If the sidecar was started from
// inside a Claude Code session (e.g. during development), a launched claude
// would inherit them, treat itself as nested (no transcript) and see another
// session's IDs and tokens (dev log 2026-09-29-claude-cli-spike, finding 13).
//
// Named variables plus a few narrow families, never a broad wipe: user
// settings such as CLAUDE_CONFIG_DIR, CLAUDE_CODE_SKIP_PROMPT_HISTORY,
// CLAUDE_CODE_EFFORT_LEVEL, CLAUDE_CODE_DISABLE_TERMINAL_TITLE or
// ANTHROPIC_BASE_URL must pass through (NOTES.md -> Security rules -> Clean
// child environments).

/**
 * Whole families. Every documented variable in them is set by Claude Code
 * itself (env-vars docs, checked 2026-09-29), so a marker added to one later
 * is caught too. Idea from Agent Office (dev log 2026-09-29-agent-office).
 */
export const CLAUDE_SESSION_MARKER_PREFIXES: readonly string[] = [
  'CLAUDE_CODE_SESSION_',   // CLAUDE_CODE_SESSION_ID; seen: _ATTENDED
  'CLAUDE_CODE_CHILD_',     // CLAUDE_CODE_CHILD_SESSION
  'CLAUDE_CODE_MESSAGING_', // _SOCKET, _TOKEN
  'CLAUDE_CODE_BRIDGE_',    // CLAUDE_CODE_BRIDGE_SESSION_ID (Remote Control)
]

export const CLAUDE_SESSION_MARKERS: readonly string[] = [
  // Documented as set by Claude Code.
  'CLAUDECODE',
  // Not documented, seen inside a Claude Code session hosted by the desktop
  // app (2026-09-29): identify that host session or connect to it.
  'CLAUDE_CODE_ENTRYPOINT',
  'CLAUDE_CODE_EXECPATH',
  'CLAUDE_CODE_HOST_SESSION_ID',
  // The host session's effort. The user's own setting is
  // CLAUDE_CODE_EFFORT_LEVEL, which passes through.
  'CLAUDE_EFFORT',
  'CLAUDE_CODE_SSE_PORT',
  'CLAUDE_CODE_DESKTOP_APP_VERSION',
  'CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH',
  'CLAUDE_CODE_ACCOUNT_UUID',
  'CLAUDE_CODE_ORGANIZATION_UUID',
  'CLAUDE_AGENT_SDK_VERSION',
  'CLAUDE_PID',
  'AI_AGENT',
]
