class_name SessionPost
extends Node3D
## A quick way to start a session from the world (S03, temporary until S03
## is designed): a signpost on the spawn platform. Near it, "Press E to
## start a session" appears; E opens a folder picker, and the chosen
## folder becomes the new session's project. The picker is Godot's own,
## drawn inside the game window: the system's would be a separate window
## that alt-tab can hide behind the game, leaving it stuck waiting (it
## happened on Windows). The sign above says
## how starting is going: the session only counts once it's up (the user
## may first have to confirm in its terminal), and only then does the world
## make its island (see SessionIslands).

## The session we asked for is up; its island exists by now.
signal session_started(session_id: String)

## After this long, "Starting" becomes "Still starting; check the terminal".
const STILL_STARTING_S := 120.0

## Our own text for the start notices we know; others show the sidecar's.
const NOTICE_TEXT := {
	"confirm_in_terminal": "Confirm in the terminal to start this session.",
}

@export var player: Player

var store: SessionStore
var sidecar: SidecarClient
## The session being started, or "".
var pending := ""

var _near := false
var _asking := false
var _asked_at := 0.0
var _still_said := false

@onready var _zone: Area3D = $Zone
@onready var _status: Label3D = $Status
@onready var _prompt: Label = $Prompt/Label
@onready var _dialog: FileDialog = $Dialog


func _ready() -> void:
	_zone.body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			_near = true
			_refresh_prompt())
	_zone.body_exited.connect(func(body: Node3D) -> void:
		if body is Player:
			_near = false
			_refresh_prompt())
	# Cancel, Esc and the close button all end in canceled.
	_dialog.dir_selected.connect(func(path: String) -> void:
		_done_asking()
		create(path))
	_dialog.canceled.connect(_done_asking)
	# Start in the user's home folder; afterwards it remembers the last one.
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	if not home.is_empty() and DirAccess.dir_exists_absolute(home):
		_dialog.current_dir = home
	_say("")
	_refresh_prompt()


## Call once. Connect SessionIslands to the store before this, so a new
## session's island exists by the time [signal session_started] fires.
func setup(p_store: SessionStore, p_sidecar: SidecarClient) -> void:
	store = p_store
	sidecar = p_sidecar
	store.session_added.connect(func(id: String, _created: bool) -> void:
		if id == pending:
			pending = ""
			_say("")
			session_started.emit(id))
	# A session that never comes up ends before the store ever sees it.
	sidecar.event_received.connect(func(msg: Dictionary) -> void:
		if msg["type"] == "session.ended" and msg["session"] == pending:
			pending = ""
			_say("The session didn't start."))
	sidecar.failed.connect(func(reason: String) -> void: _say(reason))


func status_text() -> String:
	return _status.text


func prompt_visible() -> bool:
	return _prompt.visible


func picker() -> FileDialog:
	return _dialog


## Asks the sidecar for a new session in the folder [param path].
func create(path: String) -> void:
	if not pending.is_empty():
		_say("A session is already starting.")
		return
	if sidecar.providers.is_empty():
		_say("Not connected to the sidecar yet.")
		return
	# Only one provider exists for now; choosing one is for S03 proper.
	var provider: String = sidecar.providers[0]["provider"]
	var id := sidecar.send_command("session.create", {"provider": provider, "project": {"path": path}}, _on_create_reply)
	_say("Starting…" if not id.is_empty() else "Not connected to the sidecar.")


func _on_create_reply(reply: Dictionary) -> void:
	if reply.get("type") == "error":
		_say("Couldn't start a session: %s" % reply.get("message", ""))
		return
	var result: Dictionary = reply.get("result", {})
	pending = result.get("session", "")
	_asked_at = Time.get_ticks_msec() / 1000.0
	_still_said = false
	var notice: Dictionary = result.get("notice", {})
	if not notice.is_empty():
		_say(NOTICE_TEXT.get(notice["code"], notice["message"]))


func _process(_delta: float) -> void:
	if not pending.is_empty() and not _still_said and Time.get_ticks_msec() / 1000.0 - _asked_at > STILL_STARTING_S:
		_still_said = true
		_say("Still starting; check the terminal.")


func _unhandled_input(event: InputEvent) -> void:
	if _near and not _asking and player.controls_enabled and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_ask_folder()


func _ask_folder() -> void:
	_asking = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_prompt()
	_dialog.popup_centered_ratio(0.6)


func _done_asking() -> void:
	_asking = false
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_prompt()


func _say(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func _refresh_prompt() -> void:
	_prompt.visible = _near and not _asking
