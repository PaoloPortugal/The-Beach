class_name QuitGuard
extends CanvasLayer
## Closing the game while sessions run (S05; user's decision, 2026-10-01).
## The game can't end a session cleanly (Claude Code offers no way from
## outside; NOTES → Watch items), and quitting doesn't end them either:
## they keep running in their terminals, out of the world's reach. So
## closing the window with sessions running asks first, listing them with
## what they're doing, and says to end them in their terminals. With none
## running, the game just quits. A PLACEHOLDER, like all UI for now.

var store: SessionStore
var player: Player
## Ends the game; tests replace it.
var quit: Callable = func() -> void: get_tree().quit()

var _dialog := ConfirmationDialog.new()
## The mouse mode and controls to give back on "Back to the game".
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _controls_before := true


func _init() -> void:
	layer = 10 # above the menu and the chat
	_dialog.title = "Quit"
	_dialog.ok_button_text = "Quit"
	_dialog.cancel_button_text = "Back to the game"
	_dialog.dialog_autowrap = true
	_dialog.min_size = Vector2i(560, 0)
	# Cancel, Esc and the close button all end in canceled.
	_dialog.confirmed.connect(func() -> void: quit.call())
	_dialog.canceled.connect(_give_back)
	add_child(_dialog)


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)


func setup(p_store: SessionStore, p_player: Player) -> void:
	store = p_store
	player = p_player
	for sig in [store.session_added, store.session_removed, store.agent_changed, store.agent_added]:
		sig.connect(func(_a = null, _b = null) -> void:
			if is_asking():
				_dialog.dialog_text = warning())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


## Quits, or asks first if sessions are running.
func request_quit() -> void:
	if store.sessions.is_empty():
		quit.call()
		return
	if is_asking():
		return
	_mouse_before = Input.mouse_mode
	_controls_before = player.controls_enabled
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_dialog.dialog_text = warning()
	_dialog.popup_centered()


func is_asking() -> bool:
	return _dialog.visible


## The dialog's text: the sessions still running, and what to do.
func warning() -> String:
	var n := store.sessions.size()
	if n == 0:
		return "No sessions are running any more."
	var lines: Array[String] = []
	lines.append("1 session is still running:" if n == 1 else "%d sessions are still running:" % n)
	for id in store.sessions:
		var s: Dictionary = store.sessions[id]
		var project: Dictionary = s.get("project", {})
		lines.append("    " + SessionsMenu.row(SessionsMenu.display_title(s.get("title"), project), SessionsMenu.project_name(project), SessionsMenu.state_text(store.activity(id))))
	lines.append("")
	lines.append("Quitting won't end them: they keep running in their terminals, and the game can't reach them any more. To end one, type /exit in its terminal.")
	return "\n".join(lines)


func dialog() -> ConfirmationDialog:
	return _dialog


func _give_back() -> void:
	player.controls_enabled = _controls_before
	Input.mouse_mode = _mouse_before
