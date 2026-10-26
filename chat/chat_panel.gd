class_name ChatPanel
extends PanelContainer
## The full chat panel (C02), opened by walking up to an orchestrator (C01):
## the session's chat so far, streaming as it arrives, and a message box.
## Pending permission prompts and questions are answered on its card
## (C05, [PendingCard]). Messages are rendered as Markdown (C03,
## [MarkdownView]); after each one, the tool calls that followed it fold
## into one line (C04, [ToolFold]). The header shows the session's permission
## mode (C06, when the session declares [code]permission_modes[/code]), and
## beside it the model and effort level (C12, [code]model_info[/code]); a plan
## waiting for approval (C07) is a full-width message, answered on the card.
## Token usage (C08, when the session declares [code]usage[/code]): context
## and totals in the header, beside the mode, and each turn's output tokens
## in a dim line at its end, going up while the orchestrator works.
## Message text is untrusted (NOTES.md → Security rules):
## the Markdown converter escapes all of it, and a link opens only after a
## confirmation showing its full address.

## Messages shown at once; older ones stay in the store.
const MAX_SHOWN := 200
const USER_COLOUR := Color(0.16, 0.33, 0.5)
const AGENT_COLOUR := Color(0.15, 0.17, 0.22)
const PLAN_BORDER := Color(0.45, 0.55, 0.7)
const DIM := Color(0.6, 0.64, 0.7)
## What a read-only session shows instead of the message box (S07; the user's choice, 2026-10-19).
const READ_ONLY_TEXT := "Read-only: use its terminal."
## And a session started outside the game (S08), which may be in an app or
## an IDE rather than a terminal (the user's choice, 2026-10-22).
const OUTSIDE_READ_ONLY_TEXT := "Read-only: use its own window."
const FONT_SIZE := 18
## Time spent building older messages per frame when a chat is laid out.
## Rendering Markdown costs tens of milliseconds per message (C03), so the
## newest are built first and the rest a few per frame, above them.
const BUILD_BUDGET_USEC := 8000
## Frames the view keeps its place after the last row is built, while
## wrapped text settles its height.
const SETTLE_FRAMES := 4

## Our own text for the notices we know; others show the sidecar's message.
const NOTICE_TEXT := {
	"transcripts_off": "This session isn't saving transcripts, so parts of it may not show here.",
	"hooks_unavailable": "This session isn't reporting what it does. Chat still works.",
	"conversation_cleared": "A new conversation started in this session (/clear). The earlier one can be brought back with /resume in the terminal.",
	"conversation_resumed": "This session switched to an earlier conversation (/resume). The chat now shows that conversation.",
	"conversation_moved": "This conversation moved to another Claude Code session. Continue it in the terminal; messages from here can't reach it.",
	# S07: deliberately general (user's wording), so it never goes out of date.
	"reattached_read_only": "This session started before the game restarted, so it's read-only here. Use its terminal, or /exit it and resume it from the world for full control.",
	# S08 (user's wording, 2026-10-22).
	"outside_read_only": "This session was started outside the game, so it's read-only here. Use its own window to chat with it.",
}

## Notices about the session switching conversations.
const SWITCH_NOTICES := ["conversation_cleared", "conversation_resumed"]

## What stopped a turn, for the error reasons any provider may report
## (Protocol → state_reason); any other says only "Stopped.". The
## sign_in_needed notice has no text of ours: the provider's message says
## what to do in its own window (S06).
const STOP_TEXT := {
	"rate_limit": "Stopped: a usage or rate limit was reached. See the terminal.",
	"overloaded": "Stopped: the AI service is overloaded. Try again in a moment.",
	"server_error": "Stopped: the AI service had an error. Try again in a moment.",
	"invalid_request": "Stopped: the AI service refused the request. See the terminal.",
	"model_not_found": "Stopped: the model isn't available. Pick another in the terminal.",
	"max_output_tokens": "Stopped: the reply reached its length limit.",
}

var store: SessionStore
var sidecar: SidecarClient
## The session shown, or "" when closed.
var session_id := ""

var _rows := {} # message id → its MarkdownView
var _hints := {} # message id → the turn hint under it (C08)
## The tool-call log as laid out ([method SessionStore.tool_tree]), the
## calls placed in it, and each message's fold (id → [ToolFold]; "" for the
## calls before the first message, shown only when every message is).
var _tree := {}
var _placed := {}
var _folds := {}
var _rebuild_queued := false
## Older messages still to build, newest first.
var _to_build: Array[String] = []
## Bumped on each layout so a stale build stops.
var _build_run := 0
## While a chat is being laid out, the view keeps to the end, or to its
## distance from the end once scrolled up, in the same frame the rows
## grow: rows built above it and text settling its height don't move it.
enum Keep { NONE, END, FROM_END }
var _keep := Keep.NONE
var _from_end := 0.0
var _keeping := false # the scroll is being set by _keep_place
var _link_dialog: ConfirmationDialog
var _link_url := ""
var _send_error := ""
## How long a sent message may take to show up in the chat before the
## panel says it wasn't picked up (S06). A var for tests.
var pickup_timeout := 15.0
## Sessions with a sent message being watched (session → its timer's
## token), those whose message wasn't picked up (session → its text), and
## of those, the ones whose text was given back already (once only).
var _watching := {}
var _not_picked_up := {}
var _given_back := {}
var _watch_count := 0
## The session the message box's text was typed for: one box serves every
## chat, kept while closed, emptied on opening another session's.
var _box_session := ""

@onready var _title: Label = $Layout/Header/Title
@onready var _mode: Label = $Layout/Header/Mode
@onready var _model: Label = $Layout/Header/Model
@onready var _usage: Label = $Layout/Header/Usage
@onready var _notices: Label = $Layout/Notices
@onready var _scroll: ScrollContainer = $Layout/Scroll
@onready var _messages: VBoxContainer = $Layout/Scroll/Messages
@onready var _pending: PendingCard = $Layout/Pending
@onready var _status: Label = $Layout/Status
@onready var _input: TextEdit = $Layout/Compose/Input
@onready var _compose: HBoxContainer = $Layout/Compose
## Instead of the message box for a read-only session (S07).
var _read_only_hint: Label


func _ready() -> void:
	$Layout/Compose/Send.pressed.connect(send)
	_read_only_hint = Label.new()
	_read_only_hint.text = READ_ONLY_TEXT
	_read_only_hint.add_theme_color_override("font_color", DIM)
	_read_only_hint.visible = false
	$Layout.add_child(_read_only_hint)
	_input.gui_input.connect(_on_input_key)
	var bar := _scroll.get_v_scroll_bar()
	bar.changed.connect(_keep_place)
	bar.value_changed.connect(func(_v: float) -> void:
		if _keep != Keep.NONE and not _keeping:
			_note_place())
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
	store.tool_changed.connect(_on_tool_changed)
	store.tools_loaded.connect(func(id: String) -> void:
		if id == session_id and not _rebuild_queued:
			_rebuild_queued = true
			_rebuild.call_deferred())
	store.session_changed.connect(func(id: String, _fields: Array) -> void:
		if id == session_id:
			_refresh_header())
	# A sent message is picked up when a user message arrives, or the
	# orchestrator starts working (S06).
	store.message_changed.connect(func(id: String, message: String) -> void:
		if store.session(id).get("messages", {}).get(message, {}).get("role") == "user":
			_picked_up(id))
	store.agent_changed.connect(func(id: String, _agent: String) -> void:
		if store.orchestrator(id).get("state") == "working":
			_picked_up(id))
	store.session_removed.connect(func(id: String, _reason: String) -> void:
		_watching.erase(id)
		_not_picked_up.erase(id)
		_given_back.erase(id))
	store.usage_changed.connect(func(id: String) -> void:
		if id == session_id and not _rebuild_queued:
			_refresh_usage()
			_refresh_hints())
	for sig in [store.agent_changed, store.permissions_changed, store.questions_changed, store.plans_changed, store.notices_changed]:
		sig.connect(func(id: String, _rest = null) -> void:
			if id == session_id:
				_refresh_status())


func open(p_session_id: String) -> void:
	session_id = p_session_id
	_send_error = ""
	visible = true
	if session_id != _box_session:
		# A text given back and not sent comes back on returning there.
		if _given_back.has(_box_session) and _input.text == _not_picked_up.get(_box_session):
			_given_back.erase(_box_session)
		_input.text = ""
		_box_session = session_id
	_give_back(session_id)
	_rebuild()
	_pending.show_session(session_id)
	_refresh_status()
	if not _read_only():
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
		if row.has_meta("view"):
			out.append((row.get_meta("view") as MarkdownView).shown_text())
	return out


## The tool calls' fold after a message ("": before the first), or null.
func tool_fold(message: String) -> ToolFold:
	return _folds.get(message)


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


## The header's mode text ("Mode: Auto"), or "" when it isn't shown.
func mode_text() -> String:
	return _mode.text if _mode.visible else ""


## The header's model text ("Opus 5.5 · High effort"), or "" when it isn't
## shown (C12).
func model_text() -> String:
	return _model.text if _model.visible else ""


## The header's usage text ("Context 34% · ↑ 2.1M in · ↓ 48k out"), or ""
## when it isn't shown.
func usage_text() -> String:
	return _usage.text if _usage.visible else ""


## The turn hints shown, oldest first, each [code][message id, text][/code]:
## the message whose row it ends.
func turn_hints() -> Array:
	var out := []
	for row in _messages.get_children():
		var hint: Label = _hints.get(row.get_meta("message", ""))
		if hint and hint.visible:
			out.append([row.get_meta("message"), hint.text])
	return out


## Sends the message box's text to the session.
func send() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty() or session_id.is_empty() or _read_only():
		return
	var sent_to := session_id
	var id := sidecar.send_command("message.send", {"session": session_id, "text": text}, func(reply: Dictionary) -> void:
		if reply.get("type") == "error":
			_watching.erase(sent_to)
			# Another session's chat opened meanwhile: neither the error nor
			# the text belongs there. Returning, it says the message hasn't
			# reached the session and gives the text back.
			if _box_session != sent_to:
				_not_picked_up[sent_to] = text
				_given_back.erase(sent_to)
				return
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
	_not_picked_up.erase(session_id)
	_given_back.erase(session_id)
	_watch_pickup(session_id, text)
	_refresh_status()


# Watches a sent message until it shows up (S06). A provider may never pick
# it up, e.g. a provider whose account can't be used may drop it unseen;
# then the status says so and the text comes back. Only while the
# orchestrator isn't busy: a busy one queues it for after its turn.
func _watch_pickup(session: String, text: String) -> void:
	var agent := store.orchestrator(session)
	var busy: bool = agent.get("state") == "working" \
			or (agent.get("state") == "waiting" and agent.get("reason") != "sign_in")
	if busy:
		_watching.erase(session)
		return
	_watch_count += 1
	var token := _watch_count
	_watching[session] = token
	get_tree().create_timer(pickup_timeout).timeout.connect(func() -> void:
		if _watching.get(session) != token:
			return
		_watching.erase(session)
		_not_picked_up[session] = text
		if session == session_id:
			_give_back(session)
			_refresh_status())


# Puts a message that wasn't picked up back in the box, unless something
# else was typed meanwhile; once only, so a box cleared stays clear. The
# warning stays until it's picked up or something is sent.
func _give_back(session: String) -> void:
	if _input.text.is_empty() and _not_picked_up.has(session) and not _given_back.has(session):
		_input.text = _not_picked_up[session]
		_given_back[session] = true


# Picked up after all, maybe after the warning: the warning goes, and so
# does the text given back, if the box still holds just that (sending it
# again would send it twice).
func _picked_up(session: String) -> void:
	_watching.erase(session)
	var text: String = _not_picked_up.get(session, "")
	var given := _given_back.erase(session)
	if not _not_picked_up.erase(session):
		return
	# The box is kept while the chat is closed: clear it then too.
	if given and _box_session == session and _input.text == text:
		_input.text = ""
	if session == session_id:
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
		_refresh_hints()
		if _messages.get_child_count() + _to_build.size() > MAX_SHOWN:
			if not _to_build.is_empty():
				_to_build.pop_back()
			else:
				var first := _messages.get_child(1)
				_rows.erase(first.get_meta("message"))
				_folds.erase(first.get_meta("message"))
				_hints.erase(first.get_meta("message"))
				first.free()
			# Not every message is shown now: nor are the calls before them.
			var top: ToolFold = _folds.get("")
			if top:
				_folds.erase("")
				top.ids = []
				top.refresh()
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
	_refresh_header()
	var all := store.messages(session_id)
	for m in all.slice(maxi(0, all.size() - MAX_SHOWN)):
		_to_build.push_front(m["message"])
	_tree = store.tool_tree(session_id)
	for id in s.get("tool_order", []):
		_placed[id] = true
	# The calls before the first message, when it's shown.
	var top := _new_fold(_tree["after"].get_or_add("", []) if all.size() <= MAX_SHOWN else [])
	_messages.add_child(top)
	if all.size() <= MAX_SHOWN:
		_folds[""] = top
	_build_run += 1
	_keep = Keep.END
	_build_some()
	_build_rest(_build_run)


## Builds queued messages, newest first, each above the ones built so far,
## for about [constant BUILD_BUDGET_USEC]; always at least one.
func _build_some() -> void:
	var start := Time.get_ticks_usec()
	while not _to_build.is_empty():
		var m: Dictionary = store.session(session_id)["messages"].get(_to_build.pop_front(), {})
		if not m.is_empty():
			_add_row(m, 1) # under the calls before the first message
		if Time.get_ticks_usec() - start > BUILD_BUDGET_USEC:
			break
	_refresh_hints()


## Builds the rest a few per frame. Rows appear above what's on screen, so
## the view keeps its place ([member _keep]) until they and their text
## have settled.
func _build_rest(run: int) -> void:
	while not _to_build.is_empty():
		await get_tree().process_frame
		if run != _build_run:
			return
		_build_some()
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
		if run != _build_run:
			return
	_keep = Keep.NONE


# The scroll range changed (rows added, or a height settled): back to the
# end, or to the same distance from it, before the frame is drawn.
func _keep_place() -> void:
	if _keep == Keep.NONE:
		return
	var bar := _scroll.get_v_scroll_bar()
	_keeping = true
	_scroll.scroll_vertical = int(bar.max_value if _keep == Keep.END else bar.max_value - _from_end)
	_keeping = false


# Scrolled while a chat is being laid out: keep to where it is now.
func _note_place() -> void:
	var bar := _scroll.get_v_scroll_bar()
	if _at_end():
		_keep = Keep.END
	else:
		_keep = Keep.FROM_END
		_from_end = bar.max_value - bar.value


func _clear() -> void:
	_rows.clear()
	_hints.clear()
	_folds.clear()
	_placed.clear()
	_tree = {}
	_to_build.clear()
	_build_run += 1
	_keep = Keep.NONE
	for child in _messages.get_children():
		child.free()


## Adds a message's row at the end, or at [param at] when given.
func _add_row(m: Dictionary, at := -1) -> void:
	var user: bool = m["role"] == "user"
	var plan: bool = m.get("kind") == "plan"
	var style := StyleBoxFlat.new()
	style.bg_color = USER_COLOUR if user else AGENT_COLOUR
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	if plan:
		style.border_color = PLAN_BORDER
		style.set_border_width_all(2)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_stretch_ratio = 3.0
	var view := MarkdownView.new()
	view.font_size = FONT_SIZE
	view.link_clicked.connect(ask_open_link)
	if plan:
		var stack := VBoxContainer.new()
		var caption := Label.new()
		caption.text = "Plan"
		caption.add_theme_font_size_override("font_size", 16)
		caption.add_theme_color_override("font_color", DIM)
		stack.add_child(caption)
		stack.add_child(view)
		bubble.add_child(stack)
	else:
		bubble.add_child(view)
	view.set_markdown(_display(m))
	var line := HBoxContainer.new()
	line.add_child(bubble)
	# Yours on the right, the agent's on the left; a plan takes the width.
	if not plan:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_stretch_ratio = 1.0
		line.add_child(spacer)
		if user:
			line.move_child(spacer, 0)
	# The message, then the tool calls that followed it.
	var row := VBoxContainer.new()
	row.set_meta("message", m["message"])
	row.set_meta("view", view)
	row.add_child(line)
	var fold := _new_fold(_tree["after"].get_or_add(m["message"], []))
	row.add_child(fold)
	_folds[m["message"]] = fold
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", DIM)
	hint.visible = false
	row.add_child(hint)
	_hints[m["message"]] = hint
	_messages.add_child(row)
	if at >= 0:
		_messages.move_child(row, at)
	_rows[m["message"]] = view


func _new_fold(ids: Array) -> ToolFold:
	var fold := ToolFold.new()
	fold.setup(store, session_id, _tree, ids)
	return fold


# A call started or finished: it goes in (or updates) the fold of the
# message its top-level call came after.
func _on_tool_changed(id: String, tool_call: String) -> void:
	if id != session_id or _rebuild_queued:
		return
	var tools: Dictionary = store.session(id).get("tools", {})
	var call: Dictionary = tools.get(tool_call, {})
	if call.is_empty():
		return
	if not _placed.has(tool_call):
		_placed[tool_call] = true
		SessionStore.place_tool(_tree, tools, call)
	var top := store.top_tool(id, tool_call)
	var after = top.get("after")
	var fold: ToolFold = _folds.get(after if after is String else "")
	if fold == null:
		return
	var at_end := _at_end()
	fold.refresh()
	if at_end:
		_scroll_to_end()


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
	if _not_picked_up.has(session_id):
		_status.text = "Your message hasn't reached the session. Check its terminal, then send it again."
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
				"plan":
					_status.text = "Waiting for you to approve the plan: answer it above or in the terminal."
				"sign_in":
					_status.text = "Waiting for you to sign in, in the terminal."
				_:
					_status.text = "Waiting for you in the terminal."
		"error":
			_status.text = STOP_TEXT.get(agent.get("reason"), "Stopped.")
		_:
			_status.text = ""


# The title, the usage, the mode when the session declares
# permission_modes and it is known, and the model and effort when it
# declares model_info and either is known.
func _refresh_header() -> void:
	var s := store.session(session_id)
	_title.text = _session_title(s)
	var mode = s.get("mode")
	_mode.visible = s.get("capabilities", {}).has("permission_modes") and mode is String
	_mode.text = "Mode: %s" % PermissionModes.name_of(mode) if _mode.visible else ""
	_model.text = model_words(s.get("model"), s.get("effort")) if s.get("capabilities", {}).has("model_info") else ""
	_model.visible = not _model.text.is_empty()
	_compose.visible = not _read_only()
	_read_only_hint.visible = _read_only()
	_read_only_hint.text = OUTSIDE_READ_ONLY_TEXT if s.get("origin") == "external" else READ_ONLY_TEXT
	_refresh_usage()


# A session the world only watches (S07, S08): no message box.
func _read_only() -> bool:
	return store.session(session_id).get("read_only", false) == true


# Context and totals, when the session declares usage and has counted.
func _refresh_usage() -> void:
	var s := store.session(session_id)
	var usage = s.get("usage") if s.get("capabilities", {}).has("usage") else null
	_usage.text = UsageText.header(usage)
	_usage.tooltip_text = UsageText.header_details(usage)
	_usage.visible = not _usage.text.is_empty()


# Each turn's output tokens at its end: under the last row before the next
# user message, or the last row for the turn going on. A turn whose user
# message isn't shown (older than the rows shown) has none; nor does one
# with no tokens yet.
func _refresh_hints() -> void:
	if session_id.is_empty():
		return
	var messages: Dictionary = store.session(session_id).get("messages", {})
	var tokens := -1 # the turn's, or -1 before the first shown user message
	var last := ""
	var ends := {} # message id → its turn's tokens
	for row in _messages.get_children():
		var id: String = row.get_meta("message", "")
		if id.is_empty():
			continue
		var m: Dictionary = messages.get(id, {})
		if m.get("role") == "user":
			if tokens > 0:
				ends[last] = tokens
			tokens = int(m.get("turn_tokens", 0))
		last = id
	if tokens > 0:
		ends[last] = tokens
	for id in _hints:
		var hint: Label = _hints[id]
		hint.visible = ends.has(id)
		if hint.visible:
			hint.text = UsageText.turn(ends[id])


## A model and effort level (protocol choices, or null) in the header's
## words: "Opus 5.5 · High effort", either alone, or "" with neither.
static func model_words(model: Variant, effort: Variant) -> String:
	var parts: Array[String] = []
	if model is Dictionary:
		parts.append(str(model.get("label", "")))
	if effort is Dictionary:
		parts.append("%s effort" % str(effort.get("label", "")))
	return " · ".join(parts)


static func _session_title(s: Dictionary) -> String:
	if s.get("title") is String and not s["title"].is_empty():
		return s["title"]
	var project: Dictionary = s.get("project", {})
	if project.has("name"):
		return project["name"]
	return str(project.get("path", "")).get_file()
