class_name DebugConsole
extends CanvasLayer
## Where the debug commands (C09) are typed: "/" opens a line at the bottom
## left with the "/" already in it, Enter runs it ([DebugCommands]) and
## closes, Esc closes. Up and Down go through what you ran before. The
## reply stays above it for a few seconds. Separate from the chat box, so
## a session's own slash commands never reach it. Only made in debug
## builds (world.gd). A PLACEHOLDER, like all UI.

## How long a reply shows, seconds.
const REPLY_TIME := 6.0

var commands: DebugCommands
var player: Player

var _box := VBoxContainer.new()
var _reply := Label.new()
var _line := LineEdit.new()
var _history: Array[String] = []
var _back := 0 # how far back in _history Up has gone
var _reply_left := 0.0


func _ready() -> void:
	layer = 20
	_box.anchor_top = 1.0
	_box.anchor_bottom = 1.0
	_box.offset_left = 16.0
	_box.offset_right = 616.0
	_box.offset_top = -120.0
	_box.offset_bottom = -16.0
	_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(_box)
	_reply.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reply.add_theme_color_override("font_outline_color", Color.BLACK)
	_reply.add_theme_constant_override("outline_size", 4)
	_reply.visible = false
	_box.add_child(_reply)
	_line.placeholder_text = "/help"
	_line.visible = false
	_line.text_submitted.connect(_submit)
	_box.add_child(_line)


func is_open() -> bool:
	return _line.visible


## Opens the line with [param text] in it.
func open(text := "/") -> void:
	_line.visible = true
	_line.text = text
	_line.caret_column = text.length()
	_line.grab_focus()
	_back = 0
	if player:
		player.controls_enabled = false


func close() -> void:
	if not is_open():
		return
	_line.visible = false
	_line.release_focus()
	if player:
		player.controls_enabled = true


## What the reply says now ("" when none shows).
func reply_text() -> String:
	return _reply.text if _reply.visible else ""


## Runs [param line] as if typed, and shows the reply.
func submit(line: String) -> void:
	_submit(line)


func _submit(line: String) -> void:
	close()
	if line.strip_edges().trim_prefix("/").is_empty():
		return
	_history.append(line)
	_show(commands.run(line) if commands else "No commands.")


func _show(text: String) -> void:
	_reply.text = text
	_reply.visible = true
	_reply_left = REPLY_TIME


func _process(delta: float) -> void:
	if _reply.visible:
		_reply_left -= delta
		if _reply_left <= 0.0:
			_reply.visible = false


# _input, not _unhandled_input, so the "/" that opens it isn't typed again,
# and Esc closes it before the player frees the mouse.
func _input(event: InputEvent) -> void:
	if is_open():
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close()
		elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			get_viewport().set_input_as_handled()
			_back = clampi(_back + (1 if event.is_action_pressed("ui_up") else -1), 0, _history.size())
			_line.text = _history[_history.size() - _back] if _back > 0 else "/"
			_line.caret_column = _line.text.length()
	elif event.is_action_pressed("debug_console") and player and player.controls_enabled:
		get_viewport().set_input_as_handled()
		open()
