class_name ChatController
extends Node
## Walk up to chat (C01) and the chat itself (C02). Near an orchestrator,
## "Press E to chat" appears; E opens its chat panel, frees the mouse and
## pauses the player's controls; Esc closes it again. Every orchestrator
## also gets a bubble above its head with its latest message.

signal chat_opened(orchestrator: Orchestrator)
signal chat_closed(orchestrator: Orchestrator)

const BUBBLE := preload("res://chat/message_bubble.tscn")

@export var player: Player

var store: SessionStore
var sidecar: SidecarClient

## Orchestrators the player is standing near, most recent last.
var _near: Array[Orchestrator] = []
var _open: Orchestrator = null
var _bubbles := {} # session id → MessageBubble
var _history := {} # session id → "asking" or "loaded"

@onready var _prompt: Label = $Prompt/Label
@onready var _panel: ChatPanel = $Prompt/Panel


func _ready() -> void:
	for node in get_tree().get_nodes_in_group("orchestrators"):
		watch(node)
	_refresh_prompt()


## Connects to the sessions. Call once, before any session's orchestrator
## is watched.
func setup(p_store: SessionStore, p_sidecar: SidecarClient) -> void:
	store = p_store
	sidecar = p_sidecar
	_panel.setup(store, sidecar)
	store.message_changed.connect(func(id: String, _message: String) -> void:
		if _bubbles.has(id):
			_show_latest(id))
	store.messages_replaced.connect(func(id: String) -> void:
		if _bubbles.has(id):
			_show_latest(id))
	# Another conversation in the session (/clear, /resume): its chat, as
	# the sidecar has it, replaces ours.
	store.session_changed.connect(func(id: String, fields: Array) -> void:
		if "native_id" in fields:
			_reload_history(id))


func watch(orchestrator: Orchestrator) -> void:
	orchestrator.player_entered.connect(_on_entered)
	orchestrator.player_exited.connect(_on_exited)
	orchestrator.tree_exiting.connect(_forget.bind(orchestrator))
	var id := orchestrator.session_id
	if id.is_empty() or store == null:
		return
	var bubble: MessageBubble = BUBBLE.instantiate()
	orchestrator.add_child(bubble)
	bubble.global_position = orchestrator.message_anchor()
	_bubbles[id] = bubble
	_show_latest(id)
	_fetch_history(id)


func is_open() -> bool:
	return _open != null


func prompt_visible() -> bool:
	return _prompt.visible


func panel() -> ChatPanel:
	return _panel


## The bubble above a session's orchestrator, or null.
func bubble(session_id: String) -> MessageBubble:
	return _bubbles.get(session_id)


func _on_entered(orchestrator: Orchestrator) -> void:
	_near.erase(orchestrator)
	_near.append(orchestrator)
	_refresh_prompt()


func _on_exited(orchestrator: Orchestrator) -> void:
	_near.erase(orchestrator)
	_refresh_prompt()


# An orchestrator left the world (its session ended).
func _forget(orchestrator: Orchestrator) -> void:
	_near.erase(orchestrator)
	_bubbles.erase(orchestrator.session_id)
	if _open == orchestrator:
		close()
	_refresh_prompt()


# _input, not _unhandled_input, so Esc closes the chat before the player
# sees it (the player's Esc frees the mouse).
func _input(event: InputEvent) -> void:
	if _open != null and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# Esc while a link's confirmation is up closes only that.
		if not _panel.link_asked().is_empty():
			_panel.cancel_link()
		else:
			close()
	elif _open == null and not _near.is_empty() and player.controls_enabled and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		open(_near.back())


func open(orchestrator: Orchestrator) -> void:
	_open = orchestrator
	_fetch_history(orchestrator.session_id)
	_panel.open(orchestrator.session_id)
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_prompt()
	chat_opened.emit(orchestrator)


func close() -> void:
	var was := _open
	_open = null
	_panel.close()
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_prompt()
	chat_closed.emit(was)


func _refresh_prompt() -> void:
	_prompt.visible = _open == null and not _near.is_empty()


# The chat so far isn't in the snapshot: fetch it once per session. If
# that fails (an error, or no connection), opening the chat tries again.
func _fetch_history(id: String) -> void:
	if id.is_empty() or _history.has(id):
		return
	_history[id] = "asking"
	var sent := sidecar.send_command("session.get_history", {"session": id}, func(reply: Dictionary) -> void:
		if reply.get("type") == "ok":
			_history[id] = "loaded"
			store.load_history(id, reply["result"]["messages"], reply["result"].get("tools", []))
		else:
			_history.erase(id))
	if sent.is_empty():
		_history.erase(id)


func _reload_history(id: String) -> void:
	sidecar.send_command("session.get_history", {"session": id}, func(reply: Dictionary) -> void:
		if reply.get("type") == "ok":
			_history[id] = "loaded"
			store.replace_history(id, reply["result"]["messages"], reply["result"].get("tools", [])))


## Whether a session's chat history has been loaded.
func history_loaded(id: String) -> bool:
	return _history.get(id) == "loaded"


# The orchestrator's newest reply goes in its bubble.
func _show_latest(id: String) -> void:
	var main: String = store.orchestrator(id).get("agent", "")
	var s := store.session(id)
	var order: Array = s.get("message_order", [])
	for i in range(order.size() - 1, -1, -1):
		var m: Dictionary = s["messages"][order[i]]
		if m["role"] == "assistant" and m["agent"] == main:
			_bubbles[id].show_text(m["text"])
			return
	_bubbles[id].show_text("")
