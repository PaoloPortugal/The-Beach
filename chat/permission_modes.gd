class_name PermissionModes
extends RefCounted
## Godot's own words for permission modes (C06, the [code]permission_modes[/code]
## capability) and for the choices that switch to them (C07's plan card; a
## permission prompt's switch is one of its options, worded by the provider,
## C05). The protocol carries the provider's own mode ids; ids we don't know
## show as they are. Ours are translated (C16): by id, with literal strings
## (the ids look like keys, so a [code]# TRANSLATE[/code] line would skip them).

## A mode's name: ours for the ids we know, translated under "permission
## mode", else the id.
static func name_of(mode: String) -> String:
	match mode:
		"default":
			return TranslationServer.translate("Manual", "permission mode")
		"acceptEdits":
			return TranslationServer.translate("Accept edits", "permission mode")
		"plan":
			return TranslationServer.translate("Plan", "permission mode")
		"auto":
			return TranslationServer.translate("Auto", "permission mode")
	return mode


## The button that approves a plan and switches to [param mode], in the
## words of Claude Code's own plan prompt where it has them.
static func plan_choice(mode: String) -> String:
	match mode:
		"auto":
			return TranslationServer.translate("Yes, and use auto mode")
		"acceptEdits":
			return TranslationServer.translate("Yes, auto-accept edits")
		"default":
			return TranslationServer.translate("Yes, manually approve edits")
	# TRANSLATORS: approving a plan and switching to a permission mode: our name for it ("Plan"), or the provider's id as it is.
	return Languages.fill(TranslationServer.translate("Yes, and switch to {mode} mode"), {"mode": name_of(mode)})
