class_name SessionsMenu
extends CanvasLayer
## The sessions menu (S03, S04, a first W07): Tab opens it anywhere you're
## not chatting. Its first page lists the sessions running now by cluster
## (W05) to jump to their island, with "Platform" back to the spawn
## platform (W08) and "Add session…". That page asks where a session goes:
## the cluster selector (by its repository unless changed) and the biome
## selector (W10, Random unless changed), then "New session…" picks a
## project folder and "Resume a session…" lists the stored ones, newest
## first. Only that last page asks the sidecar for them (user's,
## 2026-10-09): listing reads the transcripts. Esc goes back a page, Tab
## closes it. A search box filters the running or the stored list. A
## PLACEHOLDER, like all UI for now (user's, 2026-10-01): it only has to
## work, and gets a proper design later.
##
## The folder picker is the system's own (File Explorer on Windows; user's
## decision, 2026-10-01), or Godot's, drawn in the game window, where the
## system has none (e.g. Linux without the desktop portal). The system's
## is a separate window that alt-tab can hide behind the game (seen on
## Windows, M1), and Godot can't bring it back or close it, so while it's
## open the menu says so and offers Cancel (or Tab): that gives the
## controls back, and whatever the lost picker answers later is ignored.
## Esc stops waiting too, back on Add a session, as cancelling the picker
## does (user's, 2026-10-09).

## The player asked to go to a running session's island.
signal go_to(session_id: String)
## The player asked to go to the spawn platform (W08).
signal go_to_platform
## The system's folder picker was asked for (tests watch this).
signal native_picker_shown(directory: String)

const HEADING_COLOUR := Color(1, 1, 1, 0.55)

## The menu's pages: the running sessions, adding one, the stored ones.
enum Page { MAIN, ADD, RESUME }

const TITLES := {Page.MAIN: "Sessions", Page.ADD: "Add a session", Page.RESUME: "Resume a session"}
const CLOSE_HINTS := {Page.MAIN: "Tab or Esc to close", Page.ADD: "Esc to go back, Tab to close", Page.RESUME: "Esc to go back, Tab to close"}

@export var player: Player

## Use the system's folder picker. Off where the system has none, and in
## headless runs; tests may turn it on with [member show_native] replaced.
var native_picker := DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
## Shows the system's picker in a folder and calls back
## (ok: bool, paths: PackedStringArray, filter: int); returns an Error.
var show_native: Callable = _show_native

var store: SessionStore
var sidecar: SidecarClient
var clusters: SessionClusters
var launcher := SessionLauncher.new()
## How many times the stored sessions were asked for (tests watch this).
var listings_asked := 0

## Stored sessions from every provider, newest first.
var _stored: Array = []
## "" once listed; else what to say instead of the list.
var _stored_status := ""
## Bumped on each page shown and on closing, so a late reply from an
## earlier listing is ignored.
var _listing := 0
## The page showing.
var _page := Page.MAIN
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
@onready var _title: Label = $Panel/Layout/Header/Title
@onready var _close_hint: Label = $Panel/Layout/Header/Close
@onready var _search: LineEdit = $Panel/Layout/Search
@onready var _list: VBoxContainer = $Panel/Layout/Scroll/List
@onready var _hint: Label = $Hint
@onready var _notice: Label = $Notice
@onready var _dialog: FileDialog = $Dialog
@onready var _wait_note: Control = $Panel/Layout/Waiting
@onready var _cluster_row := HBoxContainer.new()
@onready var _cluster := OptionButton.new()
@onready var _biome_row := HBoxContainer.new()
@onready var _biome := OptionButton.new()
@onready var _scroll: Control = $Panel/Layout/Scroll


func _ready() -> void:
	add_child(launcher)
	_panel.visible = false
	# The cluster selector, under the search box.
	var label := Label.new()
	label.text = "Cluster:"
	_cluster_row.add_child(label)
	_cluster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cluster.focus_mode = Control.FOCUS_NONE
	_cluster_row.add_child(_cluster)
	$Panel/Layout.add_child(_cluster_row)
	$Panel/Layout.move_child(_cluster_row, _search.get_index() + 1)
	# The biome selector (W10), under the cluster's.
	var biome_label := Label.new()
	biome_label.text = "Biome:"
	_biome_row.add_child(biome_label)
	_biome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_biome.focus_mode = Control.FOCUS_NONE
	_biome.add_item("Random")
	_biome.set_item_metadata(0, Biome.RANDOM)
	for kind: int in Biome.NAMES:
		_biome.add_item(Biome.NAMES[kind])
		_biome.set_item_metadata(_biome.item_count - 1, kind)
	_biome_row.add_child(_biome)
	$Panel/Layout.add_child(_biome_row)
	$Panel/Layout.move_child(_biome_row, _cluster_row.get_index() + 1)
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	# Cancel, Esc and the close button all end in canceled.
	_dialog.dir_selected.connect(func(path: String) -> void:
		var cluster := cluster_choice()
		var biome := biome_choice()
		close()
		launcher.create(path, cluster, biome))
	_dialog.canceled.connect(func() -> void:
		_panel.visible = true)
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
func setup(p_store: SessionStore, p_sidecar: SidecarClient, p_clusters: SessionClusters) -> void:
	store = p_store
	sidecar = p_sidecar
	clusters = p_clusters
	launcher.setup(store, sidecar)
	launcher.clusters = clusters
	clusters.changed.connect(_fill_clusters)
	for sig in [store.session_added, store.session_removed]:
		sig.connect(func(_id: String, _rest = null) -> void:
			_refresh_hint()
			if is_open():
				_fill())
	store.session_changed.connect(func(_id: String, fields: Array) -> void:
		if "title" in fields and is_open():
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
	_fill_clusters()
	_cluster.select(0) # back to automatic each time
	_biome.select(0) # and to Random
	_show(Page.MAIN)
	_refresh_hint()


func close() -> void:
	if not is_open():
		return
	_open = false
	_stop_waiting()
	_listing += 1
	_panel.visible = false
	_dialog.hide()
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_hint()


func picker() -> FileDialog:
	return _dialog


## The page showing.
func page() -> Page:
	return _page


## Whether the cluster and biome selectors show (adding a session).
func pickers_visible() -> bool:
	return _cluster_row.visible and _biome_row.visible


## Back a page, as Esc does: from the stored sessions to adding one, from
## there to the running ones, and from those closed.
func back() -> void:
	match _page:
		Page.RESUME:
			_show(Page.ADD)
		Page.ADD:
			_show(Page.MAIN)
		_:
			close()


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


## The page's entries as shown, top to bottom: headings and buttons.
func entries() -> Array[String]:
	var out: Array[String] = []
	for child in _list.get_children():
		if not child.is_queued_for_deletion():
			out.append(child.text)
	return out


## The cluster selector's choices as shown, top to bottom.
func cluster_choices() -> Array[String]:
	var out: Array[String] = []
	for i in _cluster.item_count:
		out.append(_cluster.get_item_text(i))
	return out


## Picks the cluster selector's choice shown as [param text].
func choose_cluster(text: String) -> void:
	for i in _cluster.item_count:
		if _cluster.get_item_text(i) == text:
			_cluster.select(i)


## The biome selector's choices as shown, top to bottom (W10).
func biome_choices() -> Array[String]:
	var out: Array[String] = []
	for i in _biome.item_count:
		out.append(_biome.get_item_text(i))
	return out


## Picks the biome selector's choice shown as [param text].
func choose_biome(text: String) -> void:
	for i in _biome.item_count:
		if _biome.get_item_text(i) == text:
			_biome.select(i)


## What the biome selector says: a [enum Biome.Kind] or
## [constant Biome.RANDOM].
func biome_choice() -> int:
	return int(_biome.get_item_metadata(_biome.selected)) if _biome.selected >= 0 else Biome.RANDOM


## What the cluster selector says: a [SessionClusters] choice.
func cluster_choice() -> String:
	return str(_cluster.get_item_metadata(_cluster.selected)) if _cluster.selected >= 0 else SessionClusters.AUTOMATIC


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
	if event.is_action_pressed("sessions_menu"):
		if _panel.visible:
			get_viewport().set_input_as_handled()
			close()
		elif player.controls_enabled:
			get_viewport().set_input_as_handled()
			open()
	elif _panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# Waiting for a system picker that may be lost behind the game, Esc
		# stops waiting (its late answer is ignored) and shows Add a session
		# again, like cancelling the picker (user's, 2026-10-09).
		if _waiting:
			_stop_waiting()
		else:
			back()


func _show(page: Page) -> void:
	_page = page
	_listing += 1
	_title.text = TITLES[page]
	_close_hint.text = CLOSE_HINTS[page]
	_search.text = ""
	if page == Page.RESUME:
		_list_stored()
	_set_waiting(false)
	_fill()


func _list_stored() -> void:
	_listing += 1
	var run := _listing
	_stored = []
	_stored_status = "Loading…"
	var providers: Array = sidecar.providers
	listings_asked += 1
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
				_fill())
		if id.is_empty():
			_stored_status = "Not connected to the sidecar."
			return


func _fill() -> void:
	for child in _list.get_children():
		child.queue_free()
	match _page:
		Page.MAIN:
			_fill_running()
		Page.ADD:
			_add_button("+ New session…", _pick_folder)
			_add_button("▸ Resume a session…", func() -> void: _show(Page.RESUME))
		Page.RESUME:
			_fill_stored()


func _fill_running() -> void:
	var query := _search.text.strip_edges().to_lower()
	_add_button("+ Add session…", func() -> void: _show(Page.ADD))
	_add_button("⌂ Platform", func() -> void:
		close()
		go_to_platform.emit())
	if not launcher.pending.is_empty():
		_add_button("✕ Stop waiting for the session starting", func() -> void:
			launcher.stop_waiting()
			_fill())

	var running: Array[Array] = [] # [cluster name, [[label, id]...]]
	for cid in clusters.ids():
		var cluster := clusters.cluster_name(cid)
		var rows: Array[Array] = []
		for id in clusters.sessions(cid):
			var s: Dictionary = store.session(id)
			var label := row(display_title(s.get("title")), project_name(s.get("project", {})), state_text(store.activity(id)))
			if query.is_empty() or label.to_lower().contains(query) or cluster.to_lower().contains(query):
				rows.append([label, id])
		if not rows.is_empty():
			running.append([cluster, rows])
	if not running.is_empty():
		_add_heading("Running")
		for group in running:
			_add_heading("▸ " + group[0])
			for r in group[1]:
				_add_button(r[0], func() -> void:
					close()
					go_to.emit(r[1]))
	elif not query.is_empty():
		_add_heading("No match.")


func _fill_stored() -> void:
	if not _stored_status.is_empty():
		_add_heading(_stored_status)
		return
	var query := _search.text.strip_edges().to_lower()
	var shown := 0
	for st in _stored:
		var label := row(display_title(st.get("title"), "Untitled session"), project_name(st["project"]), _ago(st["updated_at"]))
		if not query.is_empty() and not label.to_lower().contains(query):
			continue
		shown += 1
		_add_button(label, func() -> void:
			var cluster := cluster_choice()
			var biome := biome_choice()
			close()
			launcher.resume(st["provider"], st["native_id"], cluster, biome))
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
		return # cancelled in the picker: back to the menu
	_last_dir = paths[0]
	var cluster := cluster_choice()
	var biome := biome_choice()
	close()
	launcher.create(paths[0], cluster, biome)


func _stop_waiting() -> void:
	if _waiting:
		_asking_folder += 1
		_set_waiting(false)


# Shows the page's parts, or only the note while waiting for the picker.
func _set_waiting(on: bool) -> void:
	_waiting = on
	_wait_note.visible = on
	_search.visible = not on and _page != Page.ADD
	_cluster_row.visible = not on and _page != Page.MAIN
	_biome_row.visible = not on and _page != Page.MAIN
	_scroll.visible = not on
	if _search.visible:
		_search.grab_focus()


## The cluster selector: automatic, each running cluster, a new one. Keeps
## the choice while it still exists.
func _fill_clusters() -> void:
	var keep := cluster_choice()
	_cluster.clear()
	_cluster.add_item("Automatic (by repository)")
	_cluster.set_item_metadata(0, SessionClusters.AUTOMATIC)
	for cid in clusters.ids():
		_cluster.add_item(clusters.cluster_name(cid))
		_cluster.set_item_metadata(_cluster.item_count - 1, cid)
	_cluster.add_item("New cluster")
	_cluster.set_item_metadata(_cluster.item_count - 1, SessionClusters.NEW)
	_cluster.select(0)
	for i in _cluster.item_count:
		if str(_cluster.get_item_metadata(i)) == keep:
			_cluster.select(i)
	if is_open():
		_fill()


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


## A session's title (S02 -> Titles), or [param none] while it has none: a
## running one is new until its first message names it.
static func display_title(t: Variant, none := "New session") -> String:
	if t is String and not t.is_empty():
		return t
	return none


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
