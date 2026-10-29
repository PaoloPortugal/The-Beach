extends SceneTree
## Writes the translation template, locale/messages.pot, from the code
## (C16; tests/locale/pot.gd says what it takes). Run it after changing
## the game's text; locale_test.gd fails while the file is out of date.
##
##   godot --headless --path . --script res://tests/locale/write_pot.gd

const ErrorWatch := preload("res://tests/error_watch.gd")
const Pot := preload("res://tests/locale/pot.gd")

# Like the suites: an error quits, and the Sidecar autoload's sidecar
# stays off the user's sessions.
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	var found := Pot.extract_project()
	for e: String in found["errors"]:
		printerr(e)
	if not found["errors"].is_empty():
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Pot.POT_PATH.get_base_dir()))
	var f := FileAccess.open(Pot.POT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("Can't write %s: %s" % [Pot.POT_PATH, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(Pot.render_pot(found["entries"]))
	f.close()
	print("Wrote %s: %d entries" % [Pot.POT_PATH, found["entries"].size()])
	quit(0 if _errors.ok() else 1)
