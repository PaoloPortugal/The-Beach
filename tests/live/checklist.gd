extends CanvasLayer
## Dev tool for live checks, not a feature: shows the steps of the current
## test (checklist.txt next to this file) in the top-left corner, over
## everything, and reloads them when the file changes. The world adds it
## only when the game starts with `-- --checklist`. F1 hides it down to a
## small tab and shows it again. A list taller than the window shows what
## fits; the mouse wheel (over the list, or while walking) or Page Up and
## Page Down scroll it.

const FILE := "res://tests/live/checklist.txt"

var _modified := 0
var _text := ""
var _hidden := false
var _scroll := 0

@onready var _label: Label = $Panel/Text
@onready var _tab: PanelContainer = _make_tab()


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_reload)
	add_child(timer)
	timer.start()
	_reload()
	# Lines are counted at the label's width, known only after layout.
	_show.call_deferred()
	get_viewport().size_changed.connect(_show)


# The small "F1: checklist" tab shown while the list is hidden.
func _make_tab() -> PanelContainer:
	var tab := PanelContainer.new()
	tab.position = Vector2(8, 8)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_theme_stylebox_override("panel", $Panel.get_theme_stylebox("panel"))
	var label := Label.new()
	label.text = "F1: checklist"
	label.add_theme_font_size_override("font_size", 14)
	tab.add_child(label)
	tab.visible = false
	add_child(tab)
	return tab


func _input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel and wheel.pressed and not _hidden and _label.get_line_count() > _label.max_lines_visible \
			and (wheel.button_index == MOUSE_BUTTON_WHEEL_UP or wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		# Over the list, or while walking (mouse captured, nothing else
		# scrolls); else the wheel is left to the chat.
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if captured or $Panel.get_global_rect().has_point(wheel.position):
			get_viewport().set_input_as_handled()
			_scroll += 2 if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN else -2
			_show()
		return
	var key := event as InputEventKey
	if not key or not key.pressed or _hidden and key.keycode != KEY_F1:
		return
	if key.keycode == KEY_F1 and not key.echo:
		get_viewport().set_input_as_handled()
		_hidden = not _hidden
		_show()
	elif key.keycode == KEY_PAGEDOWN or key.keycode == KEY_PAGEUP:
		get_viewport().set_input_as_handled()
		var step := maxi(_label.max_lines_visible - 2, 1)
		_scroll += step if key.keycode == KEY_PAGEDOWN else -step
		_show()


func _show() -> void:
	# Two panels, swapped: resizing one panel to fit didn't grow it back
	# (the wrapped text isn't measured yet when it's resized).
	_label.text = _text + "\n\n(F1 to hide)"
	# Only the lines that fit the window, from the scrolled-to one.
	# The window less the panel's offsets and margins; a line is its height
	# plus the spacing between lines.
	var room := get_viewport().get_visible_rect().size.y - 16.0 - 20.0
	var spacing := float(_label.get_theme_constant("line_spacing"))
	var fits := maxi(int((room + spacing) / (_label.get_line_height() + spacing)), 3)
	if _label.get_line_count() > fits:
		_label.text = "(mouse wheel or PgUp/PgDn to scroll)\n" + _label.text
	_label.max_lines_visible = fits
	_scroll = clampi(_scroll, 0, maxi(_label.get_line_count() - fits, 0))
	_label.lines_skipped = _scroll
	$Panel.visible = not _hidden
	_tab.visible = _hidden
	$Panel.reset_size()


func _reload() -> void:
	var modified := FileAccess.get_modified_time(FILE)
	if modified == _modified:
		return
	_modified = modified
	_text = FileAccess.get_file_as_string(FILE).strip_edges()
	_show()
