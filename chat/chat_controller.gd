class_name ChatController
extends Node
## Walk up to chat (C01). Near an orchestrator, "Press E to chat" appears;
## E opens its chat panel, frees the mouse and pauses the player's
## controls; Esc closes it again. The panel is a stand-in until C02: an
## empty panel over almost the whole screen.

signal chat_opened(orchestrator: Orchestrator)
signal chat_closed(orchestrator: Orchestrator)

@export var player: Player

## Orchestrators the player is standing near, most recent last.
var _near: Array[Orchestrator] = []
var _open: Orchestrator = null

@onready var _prompt: Label = $Prompt/Label
@onready var _panel: Control = $Prompt/Panel


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("orchestrators"):
		watch(node)
	_refresh_prompt()


func watch(orchestrator: Orchestrator) -> void:
	orchestrator.player_entered.connect(_on_entered)
	orchestrator.player_exited.connect(_on_exited)


func is_open() -> bool:
	return _open != null


func prompt_visible() -> bool:
	return _prompt.visible


func _on_entered(orchestrator: Orchestrator) -> void:
	_near.erase(orchestrator)
	_near.append(orchestrator)
	_refresh_prompt()


func _on_exited(orchestrator: Orchestrator) -> void:
	_near.erase(orchestrator)
	_refresh_prompt()


# _input, not _unhandled_input, so Esc closes the chat before the player
# sees it (the player's Esc frees the mouse).
func _input(event: InputEvent) -> void:
	if _open != null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif _open == null and not _near.is_empty() and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		open(_near.back())


func open(orchestrator: Orchestrator) -> void:
	_open = orchestrator
	_panel.visible = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_prompt()
	chat_opened.emit(orchestrator)


func close() -> void:
	var was := _open
	_open = null
	_panel.visible = false
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_prompt()
	chat_closed.emit(was)


func _refresh_prompt() -> void:
	_prompt.visible = _open == null and not _near.is_empty()
