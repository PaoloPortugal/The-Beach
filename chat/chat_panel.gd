class_name ChatPanel
extends PanelContainer
## The full chat panel (C02), opened by walking up to an orchestrator (C01):
## the session's chat so far, streaming as it arrives, and a message box.
## Pending permission prompts and questions are answered on its card
## (C05, [PendingCard]). Messages are rendered as Markdown (C03,
## [MarkdownView]). Message text is untrusted (NOTES.md → Security rules):
## the Markdown converter escapes all of it, and a link opens only after a
## confirmation showing its full address.

## Messages shown at once; older ones stay in the store.
const MAX_SHOWN := 200
const USER_COLOUR := Color(0.16, 0.33, 0.5)
const AGENT_COLOUR := Color(0.15, 0.17, 0.22)
const FONT_SIZE := 18
## Time spent building older messages per frame when a chat is laid out.
## Rendering Markdown costs tens of milliseconds per message (C03), so the
## newest are built first and the rest a few per frame, above them.
const BUILD_BUDGET_USEC := 8000

## Our own text for the notices we know; others show the sidecar's message.
const NOTICE_TEXT := {
	"transcripts_off": "This session isn't saving transcripts, so parts of it may not show here.",
	"hooks_unavailable": "This session isn't reporting what it does. Chat still works.",
	"conversation_cleared": "A new conversation started in this session (/clear). The earlier one can be brought back with /resume in the terminal.",
	"conversation_resumed": "This session switched to an earlier conversation (/resume). The chat now shows that conversation.",
	"conversation_moved": "This conversation moved to another Claude Code session. Continue it in the terminal; messages from here can't reach it.",
}

## Notices about the session switching conversations.
const SWITCH_NOTICES := ["conversation_cleared", "conversation_resumed"]

var store: SessionStore
var sidecar: SidecarClient
## The session shown, or "" when closed.
var session_id := ""

var _rows := {} # message id → its MarkdownView
var _rebuild_queued := false
## Older messages still to build, newest first.
var _to_build: Array[String] = []
## Bumped on each layout so a stale build stops.
var _build_run := 0
var _link_dialog: ConfirmationDialog
var _link_url := ""
var _send_error := ""

@onready var _title: Label = $Layout/Header/Title
@onready var _notices: Label = $Layout/Notices
@onready var _scroll: ScrollContainer = $Layout/Scroll
@onready var _messages: VBoxContainer = $Layout/Scroll/Messages
@onready var _pending: PendingCard = $Layout/Pending
@onready var _status: Label = $Layout/Status
@onready var _input: TextEdit = $Layout/Compose/Input


func _ready() -> void:
	$Layout/Compose/Send.pressed.connect(send)
	_input.gui_input.connect(_on_input_key)
	# Links in messages are untrusted: never open one without the user
	# seeing the full address and confirming.
	_link_dialog = ConfirmationDialog.new()
	_link_dialog.title = "Open link?"
	_link_dialog.ok_button_text = "Open in browser"
	_link_dialog.confirmed.connect(func() -> void: OS.shell_open(_link_url))
	add_child(_link_dialog)


## Connects to the store. Call once, before opening.
func setup(p_store: SessionStore, p_sidecar: SidecarClient) -> void:
	store = p_store
	sidecar = p_sidecar
	_pending.setup(store, sidecar)
	store.message_changed.connect(_on_message_changed)
	store.messages_replaced.connect(func(id: String) -> void:
		if id == session_id:
			_rebuild())
	for sig in [store.agent_changed, store.permissions_changed, store.questions_changed, store.notices_changed]:
		sig.connect(func(id: String, _rest = null) -> void:
			if id == session_id:
				_refresh_status())


func open(p_session_id: String) -> void:
	session_id = p_session_id
	_send_error = ""
	visible = true
	_rebuild()
	_pending.show_session(session_id)
	_refresh_status()
	_input.grab_focus()


func close() -> void:
	session_id = ""
	visible = false
	_link_dialog.hide()
	_pending.show_session("")
	_clear()


## What the message box holds.
func draft() -> String:
	return _input.text


func set_draft(text: String) -> void:
	_input.text = text


## The text of each message shown, oldest first, as displayed (without
## formatting; see [method MarkdownView.shown_text]).
func shown_messages() -> Array[String]:
	var out: Array[String] = []
	for row in _messages.get_children():
		out.append((row.get_meta("view") as MarkdownView).shown_text())
	return out


## Whether older messages are still being built.
func is_loading() -> bool:
	return not _to_build.is_empty()


## The address a link asks to open, or "" when not asking.
func link_asked() -> String:
	return _link_url if _link_dialog.visible else ""


## Shows the confirmation for a clicked link; it opens only if confirmed.
func ask_open_link(url: String) -> void:
	_link_url = url
	_link_dialog.dialog_text = "This link came from the message. Open it?

%s" % url
	_link_dialog.popup_centered()


## Closes a link's confirmation without opening it.
func cancel_link() -> void:
	_link_dialog.hide()


## The card for pending permission prompts and questions.
func pending_card() -> PendingCard:
	return _pending


func status_text() -> String:
	return _status.text


## Sends the message box's text to the session.
func send() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty() or session_id.is_empty():
		return
	var id := sidecar.send_command("message.send", {"session": session_id, "text": text}, func(reply: Dictionary) -> void:
		if reply.get("type") == "error":
			_send_error = "Couldn't send: %s" % reply.get("message", "")
			# Give the text back, unless something new was typed meanwhile.
			if _input.text.is_empty():
				_input.text = text
			_refresh_status())
	if id.is_empty():
		_send_error = "Not connected to the sidecar."
		_refresh_status()
		return
	_send_error = ""
	_input.text = ""
	_refresh_status()


# Enter sends; Shift+Enter is a new line.
func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and not key.shift_pressed \
			and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER):
		_input.accept_event()
		send()


func _on_message_changed(id: String, message: String) -> void:
	if id != session_id or _rebuild_queued:
		return
	var m: Dictionary = store.session(id)["messages"].get(message, {})
	if m.is_empty():
		return
	var at_end := _at_end()
	if _rows.has(message):
		_rows[message].set_markdown(_display(m))
	elif _to_build.has(message):
		return # built later, from the store as it is then
	elif store.session(id)["message_order"].back() == message:
		_add_row(m)
		if _messages.get_child_count() + _to_build.size() > MAX_SHOWN:
			if not _to_build.is_empty():
				_to_build.pop_back()
			else:
				var first := _messages.get_child(0)
				_rows.erase(first.get_meta("message"))
				first.free()
	else:
		# An older message (history arriving): lay everything out again,
		# once for the whole batch.
		_rebuild_queued = true
		_rebuild.call_deferred()
		return
	if at_end:
		_scroll_to_end()


func _rebuild() -> void:
	_rebuild_queued = false
	_clear()
	if session_id.is_empty():
		return
	var s := store.session(session_id)
	_title.text = _session_title(s)
	var all := store.messages(session_id)
	for m in all.slice(maxi(0, all.size() - MAX_SHOWN)):
		_to_build.push_front(m["message"])
	_build_run += 1
	_build_some()
	_scroll_to_end()
	if not _to_build.is_empty():
		_build_rest(_build_run)


## Builds queued messages, newest first, each above the ones built so far,
## for about [constant BUILD_BUDGET_USEC]; always at least one.
func _build_some() -> void:
	var start := Time.get_ticks_usec()
	while not _to_build.is_empty():
		var m: Dictionary = store.session(session_id)["messages"].get(_to_build.pop_front(), {})
		if not m.is_empty():
			_add_row(m, 0)
		if Time.get_ticks_usec() - start > BUILD_BUDGET_USEC:
			break


## Builds the rest a few per frame. Rows appear above what's on screen, so
## the view keeps its place: at the end if it was there, else by the
## distance from the end.
func _build_rest(run: int) -> void:
	while not _to_build.is_empty():
		var bar := _scroll.get_v_scroll_bar()
		var from_end := bar.max_value - bar.value
		var at_end := _at_end()
		await get_tree().process_frame
		if run != _build_run:
			return
		_build_some()
		await get_tree().process_frame
		if run != _build_run:
			return
		if at_end:
			_scroll.scroll_vertical = int(bar.max_value)
		else:
			_scroll.scroll_vertical = int(bar.max_value - from_end)


func _clear() -> void:
	_rows.clear()
	_to_build.clear()
	_build_run += 1
	for child in _messages.get_children():
		child.free()


## Adds a message's row at the end, or at [param at] when given.
func _add_row(m: Dictionary, at := -1) -> void:
	var user: bool = m["role"] == "user"
	var style := StyleBoxFlat.new()
	style.bg_color = USER_COLOUR if user else AGENT_COLOUR
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_stretch_ratio = 3.0
	var view := MarkdownView.new()
	view.font_size = FONT_SIZE
	view.link_clicked.connect(ask_open_link)
	bubble.add_child(view)
	view.set_markdown(_display(m))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = 1.0
	var row := HBoxContainer.new()
	row.set_meta("message", m["message"])
	row.set_meta("view", view)
	# Yours on the right, the agent's on the left.
	if user:
		row.add_child(spacer)
		row.add_child(bubble)
	else:
		row.add_child(bubble)
		row.add_child(spacer)
	_messages.add_child(row)
	if at >= 0:
		_messages.move_child(row, at)
	_rows[m["message"]] = view


func _display(m: Dictionary) -> String:
	if m["text"].is_empty() and not m["complete"]:
		return "…"
	return m["text"].strip_edges()


func _at_end() -> bool:
	var bar := _scroll.get_v_scroll_bar()
	return bar.value >= bar.max_value - bar.page - 8.0


func _scroll_to_end() -> void:
	# The new size is only known after the next layout pass.
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _refresh_status() -> void:
	if session_id.is_empty():
		return
	var s := store.session(session_id)
	var lines: PackedStringArray = []
	var notices: Array = s.get("notices", [])
	# Of the notices about switching conversations, only the latest holds.
	var switches := notices.filter(func(n: Dictionary) -> bool: return n["code"] in SWITCH_NOTICES)
	for n in notices:
		if n["code"] in SWITCH_NOTICES and n != switches.back():
			continue
		lines.append(NOTICE_TEXT.get(n["code"], n["message"]))
	_notices.text = "\n".join(lines)
	_notices.visible = not lines.is_empty()
	if not _send_error.is_empty():
		_status.text = _send_error
		return
	var agent := store.orchestrator(session_id)
	match agent.get("state", ""):
		"working":
			_status.text = "Working…"
		"waiting":
			match agent.get("reason"):
				"permission":
					_status.text = "Waiting for a permission: answer it above or in the terminal."
				"question":
					_status.text = "Waiting for an answer: answer the question above or in the terminal."
				_:
					_status.text = "Waiting for you in the terminal."
		"error":
			_status.text = "Stopped."
		_:
			_status.text = ""


static func _session_title(s: Dictionary) -> String:
	if s.get("title") is String and not s["title"].is_empty():
		return s["title"]
	var project: Dictionary = s.get("project", {})
	if project.has("name"):
		return project["name"]
	return str(project.get("path", "")).get_file()
