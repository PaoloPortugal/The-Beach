class_name ToolFold
extends VBoxContainer
## The tool-call log (C04) in the chat panel: the tool calls that came after
## one chat message, folded into one line ("▸ 5 tool calls"). A click opens
## it: each call's summary, how it went, its result line and, behind
## Details, its input. A subagent's calls fold inside the call that started
## it, the same way.
##
## Tool text is untrusted (NOTES.md → Security rules): it only ever goes in
## plain Labels, never BBCode.

const FONT_SIZE := 15
const STATUS_TEXT := {"running": "running", "ok": "ok", "error": "failed", "denied": "denied"}
const STATUS_COLOUR := {
	"running": Color(0.95, 0.8, 0.35),
	"ok": Color(0.5, 0.8, 0.55),
	"error": Color(0.95, 0.45, 0.4),
	"denied": Color(0.95, 0.6, 0.3),
}
const DIM := Color(0.62, 0.65, 0.72)
## Most characters of a call's input shown in its details.
const MAX_DETAILS := 4000

var store: SessionStore
var session_id := ""
## The session's [method SessionStore.tool_tree], shared with the panel.
var tree: Dictionary
## This fold's calls, oldest first: a list inside [member tree], so calls
## added there show on the next [method refresh].
var ids: Array = []

var _header: Button
var _list: VBoxContainer
var _entries := {} # call id → {"box", "status", "summary", "result", "details", "more", "inner"}


func setup(p_store: SessionStore, p_session_id: String, p_tree: Dictionary, p_ids: Array) -> void:
	store = p_store
	session_id = p_session_id
	tree = p_tree
	ids = p_ids
	_header = Button.new()
	_header.flat = true
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.focus_mode = Control.FOCUS_NONE
	_header.add_theme_font_size_override("font_size", FONT_SIZE)
	_header.add_theme_color_override("font_color", DIM)
	_header.pressed.connect(func() -> void: set_open(not is_open()))
	add_child(_header)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 20)
	add_child(indent)
	_list = VBoxContainer.new()
	_list.visible = false
	indent.add_child(_list)
	refresh()


func is_open() -> bool:
	return _list.visible


func set_open(open: bool) -> void:
	_list.visible = open
	refresh()


## The folded line, e.g. "▸ 3 tool calls (1 running)".
func header_text() -> String:
	return _header.text


## Each call shown (when open), oldest first, as
## "<status> <summary>[ / <result>]".
func shown_calls() -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		var e: Dictionary = _entries.get(id, {})
		if not e.is_empty() and e["box"].visible:
			var line := "%s %s" % [e["status"].text, e["summary"].text]
			if e["result"].visible:
				line += " / " + e["result"].text
			out.append(line)
	return out


## The fold inside a call (its subagent's calls), once this one is open.
func inner(tool_call: String) -> ToolFold:
	return _entries.get(tool_call, {}).get("inner")


## Shows or hides a call's input, once this fold is open.
func show_details(tool_call: String, on: bool) -> void:
	var e: Dictionary = _entries.get(tool_call, {})
	if not e.is_empty():
		e["more"].button_pressed = on


## A call's details text as shown, or "" when hidden.
func details_text(tool_call: String) -> String:
	var e: Dictionary = _entries.get(tool_call, {})
	return e["details"].text if not e.is_empty() and e["details"].visible else ""


## Updates the line and, when open, every call in it.
func refresh() -> void:
	var tools: Dictionary = store.session(session_id).get("tools", {})
	var count := 0
	var by_status := {}
	for id in ids:
		var call: Dictionary = tools.get(id, {})
		if not call.is_empty():
			count += 1
			by_status[call["status"]] = by_status.get(call["status"], 0) + 1
	visible = count > 0
	var text := "%s %d tool call%s" % ["▾" if is_open() else "▸", count, "" if count == 1 else "s"]
	var parts: PackedStringArray = []
	for status in ["running", "error", "denied"]:
		if by_status.has(status):
			parts.append("%d %s" % [by_status[status], STATUS_TEXT[status]])
	if not parts.is_empty():
		text += " (%s)" % ", ".join(parts)
	_header.text = text
	if not is_open():
		return
	for id in ids:
		var call: Dictionary = tools.get(id, {})
		if not _entries.has(id):
			_entries[id] = _make_entry(id)
		_update_entry(_entries[id], call)


func _make_entry(id: String) -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	box.add_child(line)
	var status := _label(Color.WHITE)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.custom_minimum_size.x = 70
	line.add_child(status)
	var summary := _label(Color(0.88, 0.9, 0.94))
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(summary)
	var more := Button.new()
	more.text = "Details"
	more.flat = true
	more.toggle_mode = true
	more.focus_mode = Control.FOCUS_NONE
	more.add_theme_font_size_override("font_size", FONT_SIZE - 2)
	line.add_child(more)
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 74)
	box.add_child(indent)
	var below := VBoxContainer.new()
	below.add_theme_constant_override("separation", 0)
	indent.add_child(below)
	var result := _label(DIM)
	below.add_child(result)
	var details := _label(DIM)
	details.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	details.visible = false
	below.add_child(details)
	more.toggled.connect(func(on: bool) -> void: details.visible = on)
	var inner_fold := ToolFold.new()
	below.add_child(inner_fold)
	inner_fold.setup(store, session_id, tree, tree["within"].get_or_add(id, []))
	_list.add_child(box)
	return {"box": box, "status": status, "summary": summary, "result": result, "details": details, "more": more, "inner": inner_fold}


func _update_entry(e: Dictionary, call: Dictionary) -> void:
	e["box"].visible = not call.is_empty()
	if call.is_empty():
		return
	var status: String = call["status"]
	e["status"].text = STATUS_TEXT.get(status, status)
	e["status"].add_theme_color_override("font_color", STATUS_COLOUR.get(status, DIM))
	e["summary"].text = call["summary"]
	var result: String = call.get("result", "")
	e["result"].text = result
	e["result"].visible = not result.is_empty()
	var details := "Tool: %s\nAgent: %s" % [call["tool"], call["agent"]]
	if call.has("input"):
		var input := JSON.stringify(call["input"], "  ")
		if input.length() > MAX_DETAILS:
			input = input.left(MAX_DETAILS) + "\n…"
		details += "\n" + input
	e["details"].text = details
	e["inner"].refresh()


func _label(colour: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", colour)
	return label
