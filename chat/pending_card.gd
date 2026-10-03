class_name PendingCard
extends PanelContainer
## Answering in the world (C05): the card in the chat panel, between the
## chat and the message box, for what the session waits on you for. One at
## a time, oldest first, with "1 of 3 waiting"; subagents' too, naming the
## agent.
## - A permission prompt: its summary, a Details toggle (the raw input as
##   plain text), then its choices one per line, like the terminal's list:
##   "Yes", its other ways to allow (its [code]options[/code], in the
##   provider's order and words: "Yes, and don't ask again for: …", "Yes,
##   and switch to auto mode", …), and "No". Yes and an option answer at
##   once. No unlocks a note (sent as your next message) and Send, which
##   denies; like Claude Code's own prompt, only a deny takes a note.
## - A plan to approve (the [code]plans[/code] capability, C07; the plan
##   itself is a message in the chat): one "Yes, …" button per mode it can
##   switch to, in the provider's order, and "No, keep planning", which
##   unlocks a note (what to change) and Send, like Deny.
## - A question set (the [code]questions[/code] capability): one item at a
##   time. A click on a single-choice option moves straight on; checkboxes
##   (multi-select) and the "Other…" field need Next; Back goes back. On the
##   last item a click only selects, and Send answers.
## The answer buttons and Send take no keyboard focus, so no key press
## (Enter in the chat, say) can ever answer for you. Everything shown is untrusted
## (NOTES.md → Security rules): plain labels and buttons only, no BBCode.

const DIM := Color(0.6, 0.64, 0.7)
const ERROR := Color(1.0, 0.55, 0.5)

var store: SessionStore
var sidecar: SidecarClient
## The session whose requests are shown, or "".
var session_id := ""

var _shown := "" # key ("permission:<id>" / "question:<id>" / "plan:<id>") of the request on the card
var _busy := "" # key of the request whose answer is on its way
var _error := "" # why the last answer was refused, for the request on the card
# Kept while the chat is closed, keyed by session and request id.
var _notes := {} # "<session>/<permission or plan>" → the note typed so far
var _denying := {} # "<session>/<permission or plan>" → true once Deny (or "No, keep planning") is pressed: the note unlocked
var _progress := {} # "<session>/<question>" → {step, chosen: Array per item, other: Array per item}

var _box: VBoxContainer
var _who: Label
var _count: Label
var _body: VBoxContainer
var _error_label: Label
var _options: Array[BaseButton] = []
var _next: Button
var _note: LineEdit # the permission's or plan's note field, while one is shown


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.09)
	style.border_color = Color(0.95, 0.65, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	visible = false
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	var header := HBoxContainer.new()
	_who = _label("", 18)
	_who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count = _label("", 16, DIM, false)
	header.add_child(_who)
	header.add_child(_count)
	_box.add_child(header)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	_box.add_child(_body)
	_error_label = _label("", 16, ERROR)
	_box.add_child(_error_label)


## Connects to the store. Call once.
func setup(p_store: SessionStore, p_sidecar: SidecarClient) -> void:
	store = p_store
	sidecar = p_sidecar
	for sig in [store.permissions_changed, store.questions_changed, store.plans_changed, store.agent_changed, store.agent_added]:
		sig.connect(func(id: String, _rest = null) -> void:
			if id == session_id:
				refresh())


## Shows a session's requests ("" hides the card).
func show_session(id: String) -> void:
	session_id = id
	_shown = ""
	_error = ""
	refresh(true)


## The request on the card ({kind, item}), or {}.
func current() -> Dictionary:
	if session_id.is_empty() or store == null:
		return {}
	var all := store.pending(session_id)
	return all[0] if not all.is_empty() else {}


func header_text() -> String:
	return _who.text


func count_text() -> String:
	return _count.text


func error_text() -> String:
	return _error


## Lays the card out again if the request on it changed (or [param force]).
func refresh(force := false) -> void:
	var all: Array[Dictionary] = []
	if not session_id.is_empty() and store != null:
		all = store.pending(session_id)
		_forget_answered(all)
	visible = not all.is_empty()
	_count.text = "1 of %d waiting" % all.size() if all.size() > 1 else ""
	if all.is_empty():
		_shown = ""
		return
	var key := _key(all[0])
	if key != _shown:
		_error = ""
	if force or key != _shown:
		_shown = key
		_render()
	else:
		_who.text = _who_text(all[0])


# --- Permissions ---------------------------------------------------------

## Answers the permission prompt on the card: "allow" (Yes), or "deny"
## with the note (Send). The note goes only with a deny. An allow can be
## one of the prompt's other ways to allow: [param option] is its id.
func respond(decision: String, option := "") -> void:
	var c := current()
	if c.get("kind") != "permission" or _busy == _shown:
		return
	var id: String = c["item"]["permission"]
	var fields := {"session": session_id, "permission": id, "decision": decision}
	if decision == "allow":
		if not option.is_empty():
			var offered: Array = c["item"].get("options", [])
			if not offered.any(func(o: Dictionary) -> bool: return o["option"] == option):
				return
			fields["option"] = option
		_denying.erase(_k(id))
	else:
		var note: String = _notes.get(_k(id), "").strip_edges()
		if not note.is_empty():
			fields["note"] = note
	_send("permission.respond", fields)


## No (or "No, keep planning") pressed, or pressed again: unlocks the
## note and Send, or locks them.
func set_denying(on: bool) -> void:
	var c := current()
	if c.get("kind") not in ["permission", "plan"]:
		return
	if on:
		_denying[_k(c["item"][c["kind"]])] = true
	else:
		_denying.erase(_k(c["item"][c["kind"]]))
	_render()
	if on and _note.is_inside_tree() and _note.editable:
		_note.grab_focus()


## Whether the note and Send are unlocked on the card.
func denying() -> bool:
	var c := current()
	return c.get("kind") in ["permission", "plan"] and _denying.has(_k(c["item"][c["kind"]]))


func set_note(text: String) -> void:
	var c := current()
	if c.get("kind") in ["permission", "plan"]:
		_notes[_k(c["item"][c["kind"]])] = text
		_render()


func _render_permission(p: Dictionary) -> void:
	_body.add_child(_label(p["summary"], 18))
	if p.has("input"):
		var details := ScrollContainer.new()
		details.custom_minimum_size = Vector2(0, 140)
		details.visible = false
		var raw := _label(JSON.stringify(p["input"], "  "), 15, DIM)
		raw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.add_child(raw)
		var toggle := Button.new()
		toggle.text = "Details"
		toggle.toggle_mode = true
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		toggle.toggled.connect(func(on: bool) -> void: details.visible = on)
		_body.add_child(toggle)
		_body.add_child(details)
	var id: String = p["permission"]
	var denying := _denying.has(_k(id))
	# One choice per line, as the terminal lists them.
	_body.add_child(_list_choice("Yes", respond.bind("allow")))
	for option: Dictionary in p.get("options", []):
		var label: String = option["label"]
		var option_id: String = option["option"]
		_body.add_child(_list_choice(label, respond.bind("allow", option_id)))
	var no := _list_choice("No", func() -> void: set_denying(not denying))
	no.toggle_mode = true
	no.set_pressed_no_signal(denying)
	_body.add_child(no)
	_note_row(id, denying,
		"Optional: what to do instead (sent as your next message)", "Press No to add a note",
		respond.bind("deny"))


# The note and Send under a permission or plan: kept but locked unless
# you're denying (No, or sending a plan back); only Send sends the note.
func _note_row(id: String, denying: bool, hint: String, locked_hint: String, send_action: Callable) -> void:
	var row := _row()
	var note := LineEdit.new()
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.placeholder_text = hint if denying else locked_hint
	note.text = _notes.get(_k(id), "")
	note.editable = denying and _busy != _shown
	note.add_theme_font_size_override("font_size", 16)
	note.text_changed.connect(func(t: String) -> void: _notes[_k(id)] = t)
	row.add_child(note)
	var send := _answer_button("Send", send_action)
	send.disabled = send.disabled or not denying
	row.add_child(send)
	_body.add_child(row)
	_note = note


# --- Plans ---------------------------------------------------------------

## Approves the plan on the card, switching the session to [param mode]
## (one of the plan's modes).
func approve_plan(mode: String) -> void:
	var c := current()
	if c.get("kind") != "plan" or _busy == _shown or not c["item"]["modes"].has(mode):
		return
	_denying.erase(_k(c["item"]["plan"]))
	_send("plan.answer", {"session": session_id, "plan": c["item"]["plan"], "approve": true, "mode": mode})


## Sends the plan on the card back to keep planning, with the note if one
## was typed (Send, after "No, keep planning").
func keep_planning() -> void:
	var c := current()
	if c.get("kind") != "plan" or _busy == _shown:
		return
	var id: String = c["item"]["plan"]
	var fields := {"session": session_id, "plan": id, "approve": false}
	var note: String = _notes.get(_k(id), "").strip_edges()
	if not note.is_empty():
		fields["note"] = note
	_send("plan.answer", fields)


func _render_plan(p: Dictionary) -> void:
	_body.add_child(_label("Would you like to proceed? The plan is above, in the chat.", 18))
	var id: String = p["plan"]
	var denying := _denying.has(_k(id))
	# One choice per line, in the provider's order, as the terminal lists them.
	for mode in p["modes"]:
		var b := _answer_button(PermissionModes.plan_choice(mode), approve_plan.bind(mode))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_body.add_child(b)
	var no := _answer_button("No, keep planning", func() -> void: set_denying(not denying))
	no.toggle_mode = true
	no.set_pressed_no_signal(denying)
	no.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(no)
	_note_row(id, denying,
		"Optional: what to change in the plan", "Press \"No, keep planning\" to say what to change",
		keep_planning)


# --- Questions -----------------------------------------------------------

## Which item of the question on the card is shown (0-based), or -1.
func step() -> int:
	var c := current()
	return _progress_of(c["item"])["step"] if c.get("kind") == "question" else -1


## Picks an option of the shown item: a click on a single-choice option
## (moves on unless it's the last item), or a checkbox (multi-select).
func choose(label: String) -> void:
	var c := current()
	if c.get("kind") != "question":
		return
	var q: Dictionary = c["item"]
	var p := _progress_of(q)
	var i: int = p["step"]
	var item: Dictionary = q["items"][i]
	if item["multi_select"]:
		var chosen: Array = p["chosen"][i]
		if chosen.has(label):
			chosen.erase(label)
		else:
			chosen.append(label)
		for b in _options:
			if b.text == label:
				b.set_pressed_no_signal(chosen.has(label))
		_update_nav()
		return
	p["chosen"][i] = [label]
	p["other"][i] = ""
	if i < q["items"].size() - 1:
		p["step"] = i + 1
	_render()


## Types an "Other…" answer for the shown item.
func set_other(text: String) -> void:
	var c := current()
	if c.get("kind") != "question":
		return
	var p := _progress_of(c["item"])
	var i: int = p["step"]
	p["other"][i] = text
	# A single choice is either an option or your own words.
	if not c["item"]["items"][i]["multi_select"] and not text.strip_edges().is_empty():
		p["chosen"][i] = []
		for b in _options:
			b.set_pressed_no_signal(false)
	_update_nav()


func next() -> void:
	var c := current()
	if c.get("kind") != "question":
		return
	var p := _progress_of(c["item"])
	if p["step"] < c["item"]["items"].size() - 1 and _answered(c["item"], p["step"]):
		p["step"] += 1
		_render()


func back() -> void:
	var c := current()
	if c.get("kind") != "question":
		return
	var p := _progress_of(c["item"])
	if p["step"] > 0:
		p["step"] -= 1
		_render()


## Sends the answers, once every item is answered.
func send_answers() -> void:
	var c := current()
	if c.get("kind") != "question" or _busy == _shown:
		return
	var q: Dictionary = c["item"]
	var answers := []
	for i in q["items"].size():
		if not _answered(q, i):
			return
		answers.append(_answer(q, i))
	_send("question.answer", {"session": session_id, "question": q["question"], "answers": answers})


func _render_question(q: Dictionary) -> void:
	var p := _progress_of(q)
	var i: int = p["step"]
	var items: Array = q["items"]
	var item: Dictionary = items[i]
	var top := _row()
	if items.size() > 1:
		top.add_child(_label("Question %d of %d" % [i + 1, items.size()], 16, DIM, false))
	if item.get("header", "") != "":
		top.add_child(_label(item["header"], 16, DIM, false))
	if top.get_child_count() > 0:
		_body.add_child(top)
	_body.add_child(_label(item["text"], 18))
	_options.clear()
	var chosen: Array = p["chosen"][i]
	for option in item["options"]:
		var label: String = option["label"]
		var button: BaseButton
		if item["multi_select"]:
			var box := CheckBox.new()
			box.text = label
			box.button_pressed = chosen.has(label)
			box.toggled.connect(func(_on: bool) -> void: choose(label))
			button = box
		else:
			var b := Button.new()
			b.text = label
			b.toggle_mode = true
			b.button_pressed = chosen == [label]
			b.custom_minimum_size = Vector2(160, 0)
			b.pressed.connect(choose.bind(label))
			button = b
		button.add_theme_font_size_override("font_size", 16)
		_options.append(button)
		var row := _row()
		row.add_child(button)
		if option.get("description", "") != "":
			var description := _label(option["description"], 15, DIM)
			description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(description)
		_body.add_child(row)
	var other := LineEdit.new()
	other.placeholder_text = "Other…"
	other.text = p["other"][i]
	other.add_theme_font_size_override("font_size", 16)
	other.text_changed.connect(set_other)
	_body.add_child(other)
	var nav := _row()
	if i > 0:
		var b := Button.new()
		b.text = "Back"
		b.pressed.connect(back)
		nav.add_child(b)
	nav.add_child(_spacer())
	if i < items.size() - 1:
		_next = Button.new()
		_next.text = "Next"
		_next.pressed.connect(next)
	else:
		_next = _answer_button("Send", send_answers)
	nav.add_child(_next)
	_body.add_child(nav)
	_update_nav()


func _progress_of(q: Dictionary) -> Dictionary:
	var id := _k(q["question"])
	if not _progress.has(id):
		var chosen := []
		var other := []
		for item in q["items"]:
			chosen.append([])
			other.append("")
		_progress[id] = {"step": 0, "chosen": chosen, "other": other}
	return _progress[id]


func _answered(q: Dictionary, i: int) -> bool:
	return not _answer(q, i).is_empty()


# One item's answer: the chosen labels (in the options' order) and/or your
# own words; for a single choice, one or the other.
func _answer(q: Dictionary, i: int) -> Array[String]:
	var p := _progress_of(q)
	var item: Dictionary = q["items"][i]
	var other: String = p["other"][i].strip_edges()
	var out: Array[String] = []
	if not item["multi_select"] and not other.is_empty():
		out.append(other)
		return out
	for option in item["options"]:
		if p["chosen"][i].has(option["label"]):
			out.append(option["label"])
	if not other.is_empty():
		out.append(other)
	return out


func _update_nav() -> void:
	var c := current()
	if _next != null and is_instance_valid(_next) and c.get("kind") == "question":
		_next.disabled = _busy == _shown or not _answered(c["item"], _progress_of(c["item"])["step"])


# --- Shared --------------------------------------------------------------

func _render() -> void:
	# Often called from one of these controls' own signals (an option, Back):
	# take them out now, free them once the signal is done.
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_options.clear()
	_next = null
	var c := current()
	_error_label.text = _error
	_error_label.visible = not _error.is_empty()
	if c.is_empty():
		return
	_who.text = _who_text(c)
	match c["kind"]:
		"permission":
			_render_permission(c["item"])
		"plan":
			_render_plan(c["item"])
		_:
			_render_question(c["item"])


func _send(type: String, fields: Dictionary) -> void:
	var key := _shown
	_busy = key
	_error = ""
	var sent := sidecar.send_command(type, fields, func(reply: Dictionary) -> void:
		if reply.get("type") != "error":
			return # it resolves when the session says so
		if _busy == key:
			_busy = ""
		if _shown == key:
			_error = "Couldn't answer: %s" % reply.get("message", "")
			_render())
	if sent.is_empty():
		_busy = ""
		_error = "Not connected to the sidecar."
	_render()


func _forget_answered(all: Array[Dictionary]) -> void:
	var live := {}
	for c in all:
		live[_k(c["item"][c["kind"]])] = true
	for table in [_notes, _denying, _progress]:
		for key in table.keys():
			if key.begins_with(session_id + "/") and not live.has(key):
				table.erase(key)
	if not _busy.is_empty() and not all.any(func(c: Dictionary) -> bool: return _key(c) == _busy):
		_busy = ""


func _who_text(c: Dictionary) -> String:
	var a := store.agent(session_id, c["item"]["agent"])
	var who := "The orchestrator"
	if a.get("role") == "subagent":
		who = "Subagent %s" % a["name"] if a.get("name", "") != "" else "A subagent"
	match c["kind"]:
		"permission":
			return "%s asks to use %s:" % [who, c["item"]["tool"]]
		"plan":
			return "%s has a plan for you to approve:" % who
	return "%s asks:" % who


# A button that answers the session: no keyboard focus, so only a click
# presses it, and disabled while an answer is on its way.
func _answer_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(96, 0)
	b.disabled = _busy == _shown
	b.pressed.connect(action)
	return b


# One line of a permission's list: as wide as the card, its text from the
# left and wrapped (an option's label can be long, e.g. a whole command).
func _list_choice(text: String, action: Callable) -> Button:
	var b := _answer_button(text, action)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _k(id: String) -> String:
	return "%s/%s" % [session_id, id]


static func _key(c: Dictionary) -> String:
	return "%s:%s" % [c["kind"], c["item"][c["kind"]]]


static func _label(text: String, size: int, colour := Color.WHITE, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if colour != Color.WHITE:
		l.add_theme_color_override("font_color", colour)
	return l


static func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row


static func _spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c
