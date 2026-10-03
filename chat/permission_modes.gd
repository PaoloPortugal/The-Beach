class_name PermissionModes
extends RefCounted
## Godot's own words for permission modes (C06, the [code]permission_modes[/code]
## capability) and for the choices that switch to them (C07's plan card, an
## allow that switches). The protocol carries the provider's own mode ids;
## ids we don't know show as they are.

## The modes' names, by id.
const NAMES := {
	"default": "Manual",
	"acceptEdits": "Accept edits",
	"plan": "Plan",
	"auto": "Auto",
}

## Approving a plan and switching to a mode, in the words of Claude Code's
## own plan prompt.
const PLAN_CHOICES := {
	"auto": "Yes, and use auto mode",
	"acceptEdits": "Yes, auto-accept edits",
	"default": "Yes, manually approve edits",
}


## A mode's name: ours for the ids we know, else the id.
static func name_of(mode: String) -> String:
	return NAMES.get(mode, mode)


## The button that approves a plan and switches to [param mode].
static func plan_choice(mode: String) -> String:
	return PLAN_CHOICES.get(mode, "Yes, and switch to %s" % _mode_words(mode))


## The button that allows a permission and switches to [param mode]
## (Claude Code's own Bash prompt says "Yes, and switch to auto mode").
static func allow_choice(mode: String) -> String:
	return "Allow and switch to %s" % _mode_words(mode)


# "auto mode", "accept edits mode"; an unknown id as it is, plus "mode".
static func _mode_words(mode: String) -> String:
	return "%s mode" % (NAMES[mode].to_lower() if NAMES.has(mode) else mode)
