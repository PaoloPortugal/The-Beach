extends Logger
## Fails a headless suite on any error Godot logs: a GDScript runtime error
## ("SCRIPT ERROR"), push_error, or an engine error. Warnings don't count.
## A runtime error only aborts the function it happens in (an awaiting
## caller carries on), so without this a suite could print PASS with checks
## skipped. On the first error it quits with 1 at once; the suite's PASS
## line checks `ok()` too, for an error in a suite's last, synchronous steps.
##
##   const ErrorWatch := preload("res://tests/error_watch.gd")
##   var _errors := ErrorWatch.new(self)
##   ...
##   if not _failed and _errors.ok():
##       print("PASS ...")
##       quit(0)
##
## Every suite installs it, so it also keeps the suite's sidecar (the
## Sidecar autoload starts one) off the user's own sessions folder: a
## test's sidecar must never take the user's running sessions back (S07).
## It runs before the autoload starts the sidecar, which inherits this.
## It also gives the suites their own remembered islands' file (W12).

## Read by the sidecar (sidecar/src/launch/app-data.ts).
const TEST_SESSIONS_ENV := "SIDECAR_TEST_SESSIONS_DIR"

var _tree: SceneTree
var _mutex := Mutex.new()
var _count := 0


func _init(tree: SceneTree) -> void:
	_tree = tree
	OS.add_logger(self)
	# Per user (the temp folder is shared on Linux, where another account
	# could plant run folders in it first).
	var sessions := OS.get_user_data_dir().path_join("test-sessions")
	DirAccess.make_dir_recursive_absolute(sessions)
	OS.set_environment(TEST_SESSIONS_ENV, sessions)
	# Nor the user's remembered islands (W12): each suite starts with none.
	IslandMemory.file = "user://test-islands.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IslandMemory.file))


## False if an error was logged.
func ok() -> bool:
	_mutex.lock()
	var count := _count
	_mutex.unlock()
	return count == 0


func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	_count += 1
	var first := _count == 1
	_mutex.unlock()
	if first:
		_report.call_deferred()
	# Logged from any thread: the exit code is set right away on the main
	# one, so an error while the suite shuts down still fails it.
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		_tree.quit(1)
	else:
		_tree.quit.call_deferred(1)


## Not printed from inside the logger: printing logs again.
func _report() -> void:
	printerr("FAIL an error was logged (above); the checks after it may not have run")
