class_name PauseMenu
extends CanvasLayer
## The pause menu (C13): Esc opens it when nothing else is open (the chat,
## the menus, the map and the debug console take Esc first), dims the
## screen and frees the mouse; Esc again, or Resume, closes it. Settings
## opens the settings menu (C10), whose Esc comes back here; Main menu goes
## back to the main menu (C14), sessions still running; Quit game
## asks first while sessions run, as closing the window does (S05).
## Nothing pauses: the sessions, the sky and the islands carry on (user's
## decision, 2026-10-22). A PLACEHOLDER, like all UI for now.

const BUTTONS := ["Resume", "Settings", "Main menu", "Quit game"] # TRANSLATE

## Main menu was pressed; the world opens the main menu (C14).
signal main_menu_chosen

var player: Player
var settings_menu: SettingsMenu
var quit_guard: QuitGuard

var _open := false
## Over the world, under this panel and the settings menu's (the world
## adds this before the settings menu, so on the same layer it's drawn
## first).
var _dim := ColorRect.new()
var _panel := PanelContainer.new()
var _buttons := {} # text → its Button


func _init() -> void:
	layer = 2
	_build()
	_dim.visible = false
	_panel.visible = false


func setup(with_player: Player, with_settings_menu: SettingsMenu, with_quit_guard: QuitGuard) -> void:
	player = with_player
	settings_menu = with_settings_menu
	quit_guard = with_quit_guard
	settings_menu.back = _back_from_settings


## Whether it's showing, its settings page included.
func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_dim.visible = true
	_panel.visible = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Closes it, and the settings opened from it, and gives the player the
## controls back.
func close() -> void:
	if not _open:
		return
	_open = false
	_dim.visible = false
	_panel.visible = false
	if settings_menu.is_open():
		settings_menu.close()
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The button reading [param text] (one of [constant BUTTONS]), for tests.
func button(text: String) -> Button:
	return _buttons[text]


func open_settings() -> void:
	_panel.visible = false
	settings_menu.open()


## Closes this and asks the world for the main menu (C14).
func to_main_menu() -> void:
	close()
	main_menu_chosen.emit()


func quit() -> void:
	quit_guard.request_quit()


# Esc from the settings menu: back to this one, the controls still off;
# settings opened some other way (tests) give them back.
func _back_from_settings() -> void:
	if _open:
		_panel.visible = true
	else:
		player.controls_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# _input, so Esc closes it before anything else sees it; while its settings
# page shows, the settings menu takes Esc. It opens in _unhandled_input:
# the chat, the sessions menu, the map and the debug console take their
# Esc in _input first.
func _input(event: InputEvent) -> void:
	if _open and _panel.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not _open and player and player.controls_enabled and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		open()


func _build() -> void:
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.94)
	style.set_corner_radius_all(16)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_panel.add_child(layout)
	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	for text: String in BUTTONS:
		var b := Button.new()
		b.name = text.replace(" ", "")
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 40.0
		layout.add_child(b)
		_buttons[text] = b
	_buttons["Resume"].pressed.connect(close)
	_buttons["Settings"].pressed.connect(open_settings)
	_buttons["Main menu"].pressed.connect(to_main_menu)
	_buttons["Quit game"].pressed.connect(quit)
	var hint := Label.new()
	hint.text = "Esc to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.6)
	layout.add_child(hint)
