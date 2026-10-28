class_name SidecarLost
extends CanvasLayer
## When the sidecar can't be started (S01; user's decisions, 2026-10-28):
## without it there's no game. The first start failing quits the game,
## with a message box saying why; a restart in play failing covers the
## world with a notice whose one button quits (through [QuitGuard], so
## sessions still running are listed first). A PLACEHOLDER, like all UI.

const FIRST_TEXT := "The game can't run without its sidecar, which couldn't start:\n%s\n\nTry starting the game again. If it keeps happening, reinstalling the game may fix it; the game's log says more."
const IN_PLAY_TEXT := "The sidecar stopped and couldn't be started again:\n%s\n\nThe world can't follow your sessions without it. Quit, and start the game again: your sessions keep running in their terminals and come back then."
## The notice's width, unless the window is narrower.
const WIDTH := 520.0

## Ends the game after a failed first start; tests replace it.
var quit: Callable = func() -> void: get_tree().quit(1)
## Shows a message box (blocking) before that; tests replace it.
var alert: Callable = func(text: String) -> void: OS.alert(text, str(ProjectSettings.get_setting("application/config/name")))

var _sidecar: SidecarClient
var _guard: QuitGuard
var _player: Player
var _text := Label.new()
var _quit_button := Button.new()


func _init() -> void:
	layer = 25 # above everything but the quit dialog it opens, which it hides for
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = WIDTH
	box.add_child(_text)
	_quit_button.text = "Quit"
	_quit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_quit_button.pressed.connect(_quit_pressed)
	box.add_child(_quit_button)
	visible = false


func setup(sidecar: SidecarClient, guard: QuitGuard, player: Player) -> void:
	_sidecar = sidecar
	_guard = guard
	_player = player
	sidecar.failed.connect(_on_failed)
	# Back to the game from the quit dialog: the notice again.
	guard.dialog().canceled.connect(func() -> void:
		if is_notifying():
			_show())
	# It may have failed before the world was there (no program to start).
	if sidecar.status == SidecarClient.Status.FAILED:
		_on_failed.call_deferred(sidecar.failure)


func is_notifying() -> bool:
	return not _text.text.is_empty()


## The notice's text, for tests.
func shown_text() -> String:
	return _text.text


func quit_button() -> Button:
	return _quit_button


func _on_failed(reason: String) -> void:
	if not _sidecar.has_synced:
		alert.call(FIRST_TEXT % reason)
		quit.call()
		return
	_text.text = IN_PLAY_TEXT % reason
	_show()


func _show() -> void:
	visible = true
	_player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_quit_button.grab_focus.call_deferred()


func _quit_pressed() -> void:
	visible = false
	_guard.request_quit()


# Keys wait under it, but Enter and Space still press Quit.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and not event.is_action("ui_accept"):
		get_viewport().set_input_as_handled()
