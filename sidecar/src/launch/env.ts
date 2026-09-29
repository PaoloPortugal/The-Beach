// Clean child environments (NOTES.md -> Security rules): a launched program
// gets the user's normal environment minus a named list of variables that
// belong to someone else (another tool's session, a store client). Never a
// prefix wipe: user configuration must pass through untouched.

export type Env = Record<string, string | undefined>

/**
 * Variables a store client injects into the game that must not reach the
 * user's own programs. Untested so far (no Steam build yet): see NOTES.md ->
 * Watch items -> Steam.
 */
export const STORE_CLIENT_VARIABLES: readonly string[] = [
  'SteamAppId', 'SteamGameId', 'SteamOverlayGameId', 'SteamClientLaunch',
  'SteamEnv', 'SteamNoOverlayUIDrawing', 'ENABLE_VK_LAYER_VALVE_steam_overlay_1',
]

/** Library preloads from a store overlay; other entries in LD_PRELOAD are kept. */
const OVERLAY_PRELOAD = /gameoverlayrenderer/i

/**
 * Returns a copy of `env` without the `remove` names. Names compare
 * case-insensitively on Windows, where environment names are.
 */
export function cleanEnv(env: Env, remove: readonly string[], platform: NodeJS.Platform = process.platform): Record<string, string> {
  const fold = platform === 'win32' ? (k: string) => k.toUpperCase() : (k: string) => k
  const drop = new Set(remove.map(fold))
  const out: Record<string, string> = {}
  for (const [k, v] of Object.entries(env)) {
    if (v === undefined || drop.has(fold(k))) continue
    out[k] = v
  }
  if (platform !== 'win32' && out.LD_PRELOAD !== undefined) {
    const kept = out.LD_PRELOAD.split(/[:\s]+/).filter((p) => p && !OVERLAY_PRELOAD.test(p))
    if (kept.length > 0) out.LD_PRELOAD = kept.join(':')
    else delete out.LD_PRELOAD
  }
  return out
}
