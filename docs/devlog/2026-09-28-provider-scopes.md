# Provider scopes

Features: docs

## Decision (user's)

DESIGN.md said Godot should only ever see provider-agnostic events. The user
changed this: the project will include Claude-specific features, such as
choosing the model, checking usage and the context window, that other
providers may not have. The goal is to be scalable to new providers, not to
hide Claude everywhere. The user also asked that every new feature be
checked for whether it's Claude-exclusive or provider-agnostic.

## Result

Every feature has a provider scope (NOTES.md → Architecture → Multi-provider
rules):
- **Core:** all providers, generic events.
- **Capability:** a generic concept some providers lack; generic events gated by
  a capability the provider declares.
- **Extension:** unique to one provider; namespaced events and a
  provider-specific Godot UI module.

The rule is to prefer a capability over an extension when the concept
plausibly exists elsewhere, so a new provider gets the feature for free.
Claude naming is now allowed in three places (sidecar provider module,
protocol extension namespace, Godot Claude UI module) instead of one. The
exact capability and extension format is settled with the event schema.

Rejected: keeping Godot strictly provider-agnostic. That would force Claude-only
features to be either dropped or awkwardly generalised.
