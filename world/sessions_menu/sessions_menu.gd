class_name SessionsMenu
extends CanvasLayer
## The sessions menu (S03, S04, a first W07): Tab opens it anywhere you're
## not chatting. "New session…" picks a project folder; the sessions
## running now are listed to jump to their island; stored ones, newest
## first, to resume. A search box filters both. A PLACEHOLDER, like all UI
## for now (user's, 2026-10-01): it only has to work, and gets a proper
## design later.
##
## The folder picker is the system's own (File Explorer on Windows; user's
## decision, 2026-10-01), or Godot's, drawn in the game window, where the
## system has none (e.g. Linux without the desktop portal). The system's
## is a separate window that alt-tab can hide behind the game (seen on
## Windows, M1), and Godot can't bring it back or close it, so while it's
## open the menu says so and offers Cancel (or Esc): that gives the
## controls back, and whatever the lost picker answers later is ignored.

## The player asked to go to a running session's island.
signal go_to(session_id: String)
## The system's folder picker was asked for (tests watch this).
signal native_picker_shown(directory: String)

const HEADING_COLOUR := Color(1, 1, 1, 0.55)

@export var player: Player

## Use the system's folder picker. Off where the system has none, and in
## headless runs; tests may turn it on with [member show_native] replaced.
var native_picker := DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
## Shows the system's picker in a folder and calls back
## (ok: bool, paths: PackedStringArray, filter: int); returns an Error.
var show_native: Callable = _show_native

var store: SessionStore
var sidecar: SidecarClient
var launcher := SessionLauncher.new()

## Stored sessions from every provider, newest first.
var _stored: Array = []
## "" once listed; else what to say instead of the list.
var _stored_status := ""
## Bumped on each open so a late reply from an earlier one is ignored.
var _listing := 0
## Open, with the panel or the folder picker showing. Its own flag: the
## picker hides itself before it says which folder was chosen, so by then
## neither shows, and close() must still give the controls back.
var _open := false
## Waiting for the system's picker to answer.
var _waiting := false
## Bumped on each ask and on Cancel, so a late answer is ignored.
var _asking_folder := 0
## Where the system's picker opens: the home folder, then the last choice.
var _last_dir := ""

@onready var _panel: Control = $Panel
@onready var _search: LineEdit = $Panel/Layout/Search
@onready var _list: VBoxContainer = $Panel/Layout/Scroll/List
@onready var _hint: Label = $Hint
@onready var _notice: Label = $Notice
@onready var _dialog: FileDialog = $Dialog
@onready var _wait_note: Control = $Panel/Layout/Waiting
@onready var _lists: Array[Control] = [$Panel/Layout/Search, $Panel/Layout/Scroll]


func _ready() -> void:
	add_child(launcher)
	_panel.visible = false
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	# Cancel, Esc and the close button all end in canceled.
	_dialog.dir_selected.connect(func(path: String) -> void:
		close()
		launcher.create(path))
	_dialog.canceled.connect(func() -> void:
		_panel.visible = true
		_search.grab_focus())
	# Start in the user's home folder; afterwards it remembers the last one.
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	if not home.is_empty() and DirAccess.dir_exists_absolute(home):
		_dialog.current_dir = home
		_last_dir = home
	$Panel/Layout/Waiting/Cancel.pressed.connect(close)
	launcher.status_changed.connect(func(text: String) -> void:
		_notice.text = text
		_notice.visible = not text.is_empty()
		_refresh_hint())
	_notice.visible = false


## Call once, after SessionIslands is connected to the store.
func setup(p_store: SessionStore, p_sidecar: SidecarClient) -> void:
	store = p_store
	sidecar = p_sidecar
	launcher.setup(store, sidecar)
	for sig in [store.session_added, store.session_removed]:
		sig.connect(func(_id: String, _rest = null) -> void:
			_refresh_hint()
			if is_open():
				_fill())
	_refresh_hint()


func is_open() -> bool:
	return _open


func open() -> void:
	if is_open():
		return
	_open = true
	_panel.visible = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_search.text = ""
	_search.grab_focus()
	_list_stored()
	_fill()
	_refresh_hint()


func close() -> void:
	if not is_open():
		return
	_open = false
	_stop_waiting()
	_panel.visible = false
	_dialog.hide()
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_hint()


func picker() -> FileDialog:
	return _dialog


## Whether the menu is waiting for the system's folder picker.
func waiting_for_picker() -> bool:
	return _waiting


func hint_visible() -> bool:
	return _hint.visible


func notice_text() -> String:
	return _notice.text if _notice.visible else ""


## Filters the list, as typing in the search box does.
func search(text: String) -> void:
	_search.text = text
	_fill()


## The list's entries as shown, top to bottom: headings and buttons.
func entries() -> Array[String]:
	var out: Array[String] = []
	for child in _list.get_children():
		if not child.is_queued_for_deletion():
			out.append(child.text)
	return out


## Presses the entry whose text begins with [param text].
func choose(text: String) -> void:
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.text.begins_with(text):
			child.pressed.emit()
			return


# _input, not _unhandled_input: Tab would otherwise move the focus in the
# search box, and Esc would free the mouse before the menu closes.
func _input(event: InputEvent) -> void:
	if _dialog.visible:
		return # the picker handles its own keys
	if event.is_action_pressed("sessions_menu") or _panel.visible and event.is_action_pressed("ui_cancel"):
		if _panel.visible:
			get_viewport().set_input_as_handled()
			close()
		elif player.controls_enabled:
			get_viewport().set_input_as_handled()
			open()


func _list_stored() -> void:
	_listing += 1
	var run := _listing
	_stored = []
	_stored_status = "Loading…"
	var providers: Array = sidecar.providers
	if providers.is_empty():
		_stored_status = "Not connected to the sidecar yet."
		return
	var left := [providers.size()]
	var failed: Array[String] = []
	for p in providers:
		var id := sidecar.send_command("session.list_stored", {"provider": p["provider"]}, func(reply: Dictionary) -> void:
			if run != _listing:
				return
			if reply.get("type") == "error":
				failed.append(str(reply.get("message", "")))
			else:
				_stored.append_array(reply.get("result", {}).get("sessions", []))
			left[0] -= 1
			if left[0] == 0:
				_stored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["updated_at"] > b["updated_at"])
				_stored_status = "" if failed.is_empty() else "Couldn't list stored sessions: %s" % "; ".join(failed)
				if _panel.visible:
					_fill())
		if id.is_empty():
			_stored_status = "Not connected to the sidecar."
			return


func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	_add_button("+ New session…", _pick_folder)
	if not launcher.pending.is_empty():
		_add_button("✕ Stop waiting for the session starting", func() -> void:
			launcher.stop_waiting()
			_fill())

	var running: Array[Array] = [] # [label, id]
	for id in store.sessions:
		var s: Dictionary = store.sessions[id]
		var label := row(display_title(s.get("title"), s.get("project", {})), project_name(s.get("project", {})), state_text(store.activity(id)))
		if query.is_empty() or label.to_lower().contains(query):
			running.append([label, id])
	if not running.is_empty():
		_add_heading("Running")
		for r in running:
			_add_button(r[0], func() -> void:
				close()
				go_to.emit(r[1]))

	_add_heading("Resume")
	if not _stored_status.is_empty():
		_add_heading(_stored_status)
		return
	var shown := 0
	for st in _stored:
		var label := row(display_title(st.get("title"), st["project"]), project_name(st["project"]), _ago(st["updated_at"]))
		if not query.is_empty() and not label.to_lower().contains(query):
			continue
		shown += 1
		_add_button(label, func() -> void:
			close()
			launcher.resume(st["provider"], st["native_id"]))
	if shown == 0:
		_add_heading("Nothing to resume." if query.is_empty() else "No match.")


func _pick_folder() -> void:
	if native_picker:
		_asking_folder += 1
		var ask := _asking_folder
		# The answer may come from another thread; handle it on the main one.
		var err: Error = show_native.call(_last_dir, func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			_on_native_answer.call_deferred(ask, ok, paths))
		if err == OK:
			_set_waiting(true)
			native_picker_shown.emit(_last_dir)
			return
		push_warning("System folder picker unavailable (%s); using Godot's" % error_string(err))
		native_picker = false
	_panel.visible = false
	_dialog.popup_centered_ratio(0.6)


func _show_native(directory: String, callback: Callable) -> Error:
	return DisplayServer.file_dialog_show("Choose the session's project folder", directory, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(), callback)


func _on_native_answer(ask: int, ok: bool, paths: PackedStringArray) -> void:
	if ask != _asking_folder or not _waiting:
		return # cancelled from the menu meanwhile, or the menu closed
	_set_waiting(false)
	if not ok or paths.is_empty():
		_search.grab_focus() # cancelled in the picker: back to the menu
		return
	_last_dir = paths[0]
	close()
	launcher.create(paths[0])


func _stop_waiting() -> void:
	if _waiting:
		_asking_folder += 1
		_set_waiting(false)


func _set_waiting(on: bool) -> void:
	_waiting = on
	_wait_note.visible = on
	for c in _lists:
		c.visible = not on


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HEADING_COLOUR)
	_list.add_child(label)


func _add_button(text: String, on_press: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	_list.add_child(button)


func _refresh_hint() -> void:
	_hint.visible = store != null and store.sessions.is_empty() and not is_open() and not launcher.busy()


## One session as "title · project · detail".
static func row(name: String, project: String, detail: String) -> String:
	return "%s   ·   %s   ·   %s" % [name, project, detail]


static func display_title(t: Variant, _project: Dictionary) -> String:
	if t is String and not t.is_empty():
		return t
	return "Untitled session"


static func project_name(project: Dictionary) -> String:
	if project.has("name"):
		return project["name"]
	return str(project.get("path", "")).get_file()


## A session's [method SessionStore.activity] in words.
static func state_text(activity: String) -> String:
	match activity:
		"working":
			return "working"
		"waiting":
			return "waiting for you"
		"error":
			return "stopped"
	return "idle"


## "just now", "5 min", "3 h", "2 d" since an ISO time.
static func _ago(iso: String) -> String:
	var then := Time.get_unix_time_from_datetime_string(iso.substr(0, 19))
	var s := maxf(0.0, Time.get_unix_time_from_system() - then)
	if s < 60:
		return "just now"
	if s < 3600:
		return "%d min ago" % int(s / 60)
	if s < 86400:
		return "%d h ago" % int(s / 3600)
	return "%d d ago" % int(s / 86400)
