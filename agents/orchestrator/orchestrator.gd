class_name Orchestrator
extends Node3D
## A session's orchestrator (A01): a plain placeholder at a desk until its
## look is decided (open question 7). Its chat zone tells the world when
## the player is close enough to chat (C01). Its state marker (A03) sits
## between its head and its message bubble.

signal player_entered(orchestrator: Orchestrator)
signal player_exited(orchestrator: Orchestrator)

## The session this orchestrator belongs to; empty until sessions reach
## the world.
var session_id := ""

@onready var _zone: Area3D = $ChatZone


func _ready() -> void:
	_zone.body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			player_entered.emit(self))
	_zone.body_exited.connect(func(body: Node3D) -> void:
		if body is Player:
			player_exited.emit(self))


## Shows the orchestrator's state over its head (A03).
func show_state(state: String) -> void:
	$StateMarker.show_state(state)


## Just above the orchestrator's head, where its latest message will float
## (C02).
func message_anchor() -> Vector3:
	return $MessageAnchor.global_position
