class_name Orchestrator
extends Node3D
## A session's orchestrator (A01): a plain placeholder at a desk until the
## user's custom models come (open question 7). Looked at from close enough, the
## crosshair offers to talk to it ([member talk]; C01, C11). Its state marker (A03) sits
## between its head and its message bubble. A lamp on its desk lights up
## at night (W09).

## The session this orchestrator belongs to; empty until sessions reach
## the world.
var session_id := ""
## What the crosshair aims at to talk to it (C11): its body and head,
## from as far as its chat zone used to reach (C01).
var talk := Interactable.new("Talk", 3.5, 0.7)


func _ready() -> void:
	var lamp := NightLight.lamp()
	lamp.position = Vector3(0.62, 0.8, 0.62) # the desk's front corner
	add_child(lamp)
	talk.position = Vector3(0, 1.2, -0.2)
	add_child(talk)


## Shows the orchestrator's state over its head (A03).
func show_state(state: String) -> void:
	$StateMarker.show_state(state)


## Just above the orchestrator's head, where its latest message will float
## (C02).
func message_anchor() -> Vector3:
	return $MessageAnchor.global_position
