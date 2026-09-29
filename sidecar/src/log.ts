// Logging goes to stderr only: stdout carries the startup handshake to Godot.
// Never log session content (messages, tool input, file text, tokens): Godot
// may keep this output in its own log files, and we never keep a copy of a
// conversation on disk (NOTES.md -> Security rules -> Private by default).

export interface Log {
  info(msg: string): void
  warn(msg: string): void
  error(msg: string): void
}

export const stderrLog: Log = {
  info: (m) => process.stderr.write(`[sidecar] ${m}\n`),
  warn: (m) => process.stderr.write(`[sidecar] warning: ${m}\n`),
  error: (m) => process.stderr.write(`[sidecar] error: ${m}\n`),
}

export const silentLog: Log = { info() {}, warn() {}, error() {} }
