class_name QuitGuard
extends CanvasLayer
## Closing the game while sessions run (S05; user's decision, 2026-10-01).
## The game can't end a session cleanly (Claude Code offers no way from
## outside; NOTES → Watch items), and quitting doesn't end them either:
## they keep running in their terminals, out of the world's reach until
## the game starts again (S07). So closing the window with sessions
## running asks first, listing them with what they're doing, and says how
## to end them in their terminals. With none
## running, the game just quits. A PLACEHOLDER, like all UI for now.
## The list scrolls once it's taller than the window allows, so the
## buttons always stay on screen, however many sessions run.

## The dialog's width, unless the window is narrower.
const WIDTH := 560.0
## Room kept between the dialog and the window's edges.
const MARGIN := 16.0
## What to do, under the list (user's wording). They come back when the
## game starts again (S07); the second paragraph says how to close the gap
## of hooks that outlive the game (NOTES → Security rules → Known gap).
const FOOTER := "Quitting won't end them: they keep running in their terminals, and come back when you start the game again. To end one, type /exit in its terminal.\n\nOn a computer shared with other accounts, end them with /exit before quitting: while the game is closed, another account could reach them."

var store: SessionStore
var player: Player
## Ends the game; tests replace it.
var quit: Callable = func() -> void: get_tree().quit()

var _dialog := ConfirmationDialog.new()
var _header := Label.new()
## The sessions, one per line, in [member _scroll].
var _list := Label.new()
var _scroll := ScrollContainer.new()
var _footer := Label.new()
## The mouse mode and controls to give back on "Back to the game".
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _controls_before := true


func _init() -> void:
	layer = 10 # above the menu and the chat
	_dialog.title = "Quit"
	_dialog.ok_button_text = "Quit"
	_dialog.cancel_button_text = "Back to the game"
	for l: Label in [_header, _list, _footer]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	var box := VBoxContainer.new()
	for c in [_header, _scroll, _footer]:
		box.add_child(c)
	_dialog.add_child(box)
	# Cancel, Esc and the close button all end in canceled.
	_dialog.confirmed.connect(func() -> void: quit.call())
	_dialog.canceled.connect(_give_back)
	add_child(_dialog)


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_viewport().size_changed.connect(func() -> void:
		if is_asking():
			_fit())


func setup(p_store: SessionStore, p_player: Player) -> void:
	store = p_store
	player = p_player
	for sig in [store.session_added, store.session_removed, store.agent_changed, store.agent_added]:
		sig.connect(func(_a = null, _b = null) -> void:
			if is_asking():
				_show())
	store.session_changed.connect(func(_id: String, fields: Array) -> void:
		if "title" in fields and is_asking():
			_show())


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
	_dialog.popup()
	_show()


func is_asking() -> bool:
	return _dialog.visible


## The dialog's text as shown, for tests.
func shown_text() -> String:
	var parts := [_header.text, _list.text, _footer.text].filter(func(t: String) -> bool: return t != "")
	return "\n".join(parts)


func dialog() -> ConfirmationDialog:
	return _dialog


## The list's scroll, for tests.
func list_scroll() -> ScrollContainer:
	return _scroll


## The dialog's text: a header, the sessions still running (one per line)
## and what to do.
func _show() -> void:
	var n := store.sessions.size()
	var lines: Array[String] = []
	for id in store.sessions:
		var s: Dictionary = store.sessions[id]
		var project: Dictionary = s.get("project", {})
		lines.append("    " + SessionsMenu.row(SessionsMenu.display_title(s.get("title")), SessionsMenu.project_name(project), SessionsMenu.state_text(store.activity(id))))
	_list.text = "\n".join(lines)
	if n == 0:
		_header.text = "No sessions are running any more."
		_footer.text = ""
	else:
		_header.text = "1 session is still running:" if n == 1 else "%d sessions are still running:" % n
		_footer.text = FOOTER
	_scroll.visible = n > 0
	_footer.visible = n > 0
	_fit()


## Sizes the dialog to its text, but no bigger than the window: the list
## gets the height the rest leaves, and scrolls if it needs more.
func _fit() -> void:
	var room := get_viewport().get_visible_rect().size
	var title := float(_dialog.get_theme_constant("title_height"))
	var width := maxf(minf(WIDTH, room.x - 2 * MARGIN), 1.0)
	# Wrapped labels measure their height at their width: the dialog's,
	# less its panel's margins.
	var inner := maxf(width - _dialog.get_theme_stylebox("panel").get_minimum_size().x, 1.0)
	for l: Label in [_header, _list, _footer]:
		l.size.x = inner
		l.update_minimum_size()
	_scroll.custom_minimum_size.y = 0
	_dialog.min_size = Vector2i(int(width), 0)
	_dialog.reset_size()
	var free := room.y - 2 * MARGIN - title - float(_dialog.get_contents_minimum_size().y)
	if _scroll.visible:
		_scroll.custom_minimum_size.y = clampf(_list.get_minimum_size().y, 0.0, maxf(free, 0.0))
	_dialog.reset_size()
	# Centred, below its title bar; in a window too short even for that,
	# the bottom stays on screen, so the buttons do.
	var at := ((room - Vector2(_dialog.size)) / 2 + Vector2(0, title / 2)).max(Vector2(0, title))
	at.y = minf(at.y, room.y - MARGIN - _dialog.size.y)
	_dialog.position = Vector2i(at)



func _give_back() -> void:
	player.controls_enabled = _controls_before
	Input.mouse_mode = _mouse_before
