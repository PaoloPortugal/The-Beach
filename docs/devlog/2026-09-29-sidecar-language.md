# Sidecar language

Features: docs (S01, S02)

## Decision (user's)

TypeScript on Node (open question 6). The evidence, from the Agent SDK
hooks docs: the TypeScript SDK supports several hook events the Python SDK
doesn't, including SessionStart/SessionEnd, StopFailure (turn ended by an
API error), PostCompact and MessageDisplay, plus options such as
`permissionPrompts`. Python was the alternative; nothing we need is
Python-only.
