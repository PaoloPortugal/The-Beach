extends CanvasLayer
## Dev tool for live checks, not a feature: shows the steps of the current
## test (checklist.txt next to this file) in the top-left corner, over
## everything, and reloads them when the file changes. The world adds it
## only when the game starts with `-- --checklist`. F1 hides it down to a
## small tab and shows it again.

const FILE := "res://tests/live/checklist.txt"

var _modified := 0
var _text := ""
var _hidden := false

@onready var _label: Label = $Panel/Text


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_reload)
	add_child(timer)
	timer.start()
	_reload()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F1:
		get_viewport().set_input_as_handled()
		_hidden = not _hidden
		_show()


func _show() -> void:
	_label.text = "F1: checklist" if _hidden else _text + "\n\n(F1 to hide)"
	_label.custom_minimum_size.x = 0.0 if _hidden else 456.0
	$Panel.reset_size() # shrink to fit the shorter text


func _reload() -> void:
	var modified := FileAccess.get_modified_time(FILE)
	if modified == _modified:
		return
	_modified = modified
	_text = FileAccess.get_file_as_string(FILE).strip_edges()
	_show()
