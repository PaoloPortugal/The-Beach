extends CanvasLayer
## Dev tool for live checks, not a feature: shows the steps of the current
## test (checklist.txt next to this file) in the top-left corner, over
## everything, and reloads them when the file changes. The world adds it
## only when the game starts with `-- --checklist`.

const FILE := "res://tests/live/checklist.txt"

var _modified := 0

@onready var _label: Label = $Panel/Text


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.timeout.connect(_reload)
	add_child(timer)
	timer.start()
	_reload()


func _reload() -> void:
	var modified := FileAccess.get_modified_time(FILE)
	if modified == _modified:
		return
	_modified = modified
	_label.text = FileAccess.get_file_as_string(FILE).strip_edges()
