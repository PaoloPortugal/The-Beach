class_name Interactable
extends Node3D
## Something E (interact) acts on (C11): the crosshair picks the one you
## look at, within [member reach] and not behind anything, and shows its
## [member hint] under the circle; E then emits [signal used]. Put one
## where the crosshair should aim, as the child of what it belongs to (an
## orchestrator, a zipline): that thing's own colliders don't block it.

## E was pressed with the crosshair on it.
signal used(player: Player)

## What the hint under the crosshair says after the key ("Talk"), in
## English: the crosshair translates it under the context "hint" (C16;
## mark the string [code]# TRANSLATE: hint[/code]).
var hint := ""
## How far from the camera it can be used, metres.
var reach := 3.0
## How far from its middle the crosshair still counts as on it, metres.
var radius := 0.5
## Off while it can't be used.
var enabled := true


func _init(p_hint := "", p_reach := 3.0, p_radius := 0.5) -> void:
	hint = p_hint
	reach = p_reach
	radius = p_radius
	name = "Interactable"


func _ready() -> void:
	add_to_group("interactables")
