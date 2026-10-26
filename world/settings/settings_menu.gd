class_name SettingsMenu
extends CanvasLayer
## The settings menu (C10): the pause menu's Settings opens it (C13) and
## it frees the mouse; Esc goes back to the pause menu ([member back]).
## Tabs for Graphics, Controls, Sound, Game and Providers; every
## change applies at once and is saved ([Settings]). A PLACEHOLDER, like
## all UI for now.
##
## Game's "Show sessions started outside the game" (S08) is greyed out and
## shown off, the saved choice kept, while a provider says it can't list
## them (its [code]outside_sessions_off[/code] notice, in red beside it).
##
## Providers has a row per provider that runs a program of the user's
## (S02, [code]program_path[/code]): what it found (path and version, or
## why not, in red), Browse… to set it by hand and Reset to find it as
## usual again. The sidecar checks a path first; one it refuses is said in
## red and nothing changes.

const TABS := ["Graphics", "Controls", "Sound", "Game", "Providers"]
## What each choice reads as in the menu.
const NAMES := {
	"windowed": "Windowed", "borderless": "Borderless fullscreen", "fullscreen": "Fullscreen",
	"off": "Off", "low": "Low", "high": "High",
	0: "Off", 30: "30", 60: "60", 120: "120", 144: "144", 240: "240",
	"2x": "2×", "4x": "4×", "8x": "8×", "fxaa": "FXAA", "smaa": "SMAA",
}

var settings: Settings
var player: Player
## A05's chime is its own setting ([Attention.sound_on]).
var attention: Attention
## Under the Compatibility renderer the sun casts no shadows (world.gd),
## so the shadow setting is greyed out.
var shadows_available := true
## Screen-space anti-aliasing isn't in the Compatibility renderer either
## (Godot's docs), so its setting is greyed out there too.
var screen_space_aa_available := true
## Called when Esc leaves the menu, instead of giving the controls back:
## the pause menu's way back (C13). Unset, Esc just closes it.
var back := Callable()
## For the providers' notices (S08); null in tests that build the menu alone.
var sidecar: SidecarClient:
	set(s):
		if sidecar and sidecar.providers_changed.is_connected(_refresh):
			sidecar.providers_changed.disconnect(_refresh)
		sidecar = s
		if sidecar:
			sidecar.providers_changed.connect(_refresh)
		_refresh()

var _open := false
var _panel := PanelContainer.new()
var _tabs := TabContainer.new()
var _controls := {} # setting key → its Control
var _values := {} # a slider's key → the Label showing its value
var _sound := CheckButton.new()
## Why sessions started outside the game can't be shown, when a provider says so (S08).
var _outside_off := Label.new()
## Each program_path provider's row (S02): provider id → {status, error,
## browse, reset, label, box, busy}.
var _programs := {}
var _providers: GridContainer
## Said while no provider has anything to set.
var _no_providers := Label.new()
var _file_dialog: FileDialog


func _init() -> void:
	layer = 2
	_build()
	_panel.visible = false


func setup(with_settings: Settings, with_player: Player, with_attention: Attention) -> void:
	settings = with_settings
	player = with_player
	attention = with_attention
	settings.changed.connect(_refresh)
	_refresh()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_panel.visible = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The control that sets [param key] (a [Settings] key), for tests.
func control(key: String) -> Control:
	return _controls[key]


## Why outside sessions can't be shown (S08), for tests: empty while they can.
func outside_off_text() -> String:
	return _outside_off.text if _outside_off.visible else ""


## The chime's toggle (A05), for tests.
func sound_toggle() -> CheckButton:
	return _sound


## Shows the tab called [param tab_name].
func show_tab(tab_name: String) -> void:
	_tabs.current_tab = TABS.find(tab_name)


func current_tab() -> String:
	return TABS[_tabs.current_tab]


# _input, so Esc leaves it before anything else (the pause menu) sees it.
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if back.is_valid():
			_open = false
			_panel.visible = false
			back.call()
		else:
			close()


func _build() -> void:
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
	_panel.custom_minimum_size = Vector2(600, 0)
	add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_panel.add_child(layout)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 26)
	layout.add_child(title)
	# As tall as the tallest tab, so the panel doesn't jump between tabs.
	_tabs.use_hidden_tabs_for_min_size = true
	layout.add_child(_tabs)
	for tab_name: String in TABS:
		var grid := GridContainer.new()
		grid.name = tab_name
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 10)
		_tabs.add_child(grid)

	var graphics := _tabs.get_child(0)
	_choice(graphics, "Window", "graphics/window_mode")
	_toggle(graphics, "Vsync", "graphics/vsync")
	_choice(graphics, "FPS cap", "graphics/fps_cap")
	_slider(graphics, "Render scale", "graphics/render_scale", func(v: float) -> String: return "%d %%" % roundi(v * 100.0))
	_choice(graphics, "Shadows", "graphics/shadows")
	_choice(graphics, "Anti-aliasing (MSAA)", "graphics/msaa")
	_choice(graphics, "Screen-space anti-aliasing", "graphics/screen_space_aa")
	_toggle(graphics, "Lightning in storms", "graphics/lightning")
	var controls := _tabs.get_child(1)
	_slider(controls, "Mouse sensitivity", "controls/mouse_sensitivity", func(v: float) -> String: return "%.2fx" % v)
	_slider(controls, "Field of view", "controls/fov", func(v: float) -> String: return "%d°" % roundi(v))
	var sound := _tabs.get_child(2)
	_row(sound, "Sound when waiting\n(while you're in another window)", _sound)
	_sound.toggled.connect(func(on: bool) -> void:
		if attention:
			attention.sound_on = on)
	var game := _tabs.get_child(3)
	_toggle(game, "Take me to a new session's island", "game/go_to_new_island")
	_toggle(game, "Crosshair", "game/crosshair")
	_toggle(game, "Show sessions started outside the game", "game/outside_sessions")
	_outside_off.name = "OutsideOff"
	_outside_off.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
	_outside_off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outside_off.custom_minimum_size.x = 300.0
	_outside_off.visible = false
	game.add_child(_outside_off)
	game.add_child(Control.new())
	_providers = _tabs.get_child(4)
	_no_providers.text = "Nothing to set for the AI tools in use."
	_no_providers.modulate = Color(1, 1, 1, 0.6)
	_providers.add_child(_no_providers)

	var bottom := HBoxContainer.new()
	layout.add_child(bottom)
	var reset := Button.new()
	reset.name = "Reset"
	reset.text = "Reset to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(reset_all)
	bottom.add_child(reset)
	var hint := Label.new()
	hint.text = "Esc to go back"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.modulate = Color(1, 1, 1, 0.6)
	bottom.add_child(hint)


## Every setting back to its default, the chime included.
func reset_all() -> void:
	if attention:
		attention.sound_on = true
	settings.reset()


func _row(grid: Node, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	control.focus_mode = Control.FOCUS_NONE
	control.custom_minimum_size.x = 240.0
	grid.add_child(control)


func _choice(grid: Node, text: String, key: String) -> void:
	var button := OptionButton.new()
	for choice: Variant in Settings.CHOICES[key]:
		button.add_item(NAMES[choice])
	button.item_selected.connect(func(i: int) -> void: settings.set_value(key, Settings.CHOICES[key][i]))
	_controls[key] = button
	_row(grid, text, button)


func _toggle(grid: Node, text: String, key: String) -> void:
	var button := CheckButton.new()
	button.toggled.connect(func(on: bool) -> void: settings.set_value(key, on))
	_controls[key] = button
	_row(grid, text, button)


func _slider(grid: Node, text: String, key: String, shown: Callable) -> void:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	var r: Array = Settings.RANGES[key]
	slider.min_value = r[0]
	slider.max_value = r[1]
	slider.step = r[2]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	var value := Label.new()
	value.custom_minimum_size.x = 64.0
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(slider)
	box.add_child(value)
	slider.value_changed.connect(func(v: float) -> void:
		value.text = shown.call(v)
		settings.set_value(key, v))
	_controls[key] = slider
	_values[key] = [value, shown]
	_row(grid, text, box)


# Shows the saved values, without setting them again.
func _refresh() -> void:
	if settings == null:
		return
	for key: String in _controls:
		var c: Control = _controls[key]
		var v: Variant = settings.value(key)
		if c is OptionButton:
			(c as OptionButton).select(Settings.CHOICES[key].find(v))
		elif c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(v)
		elif c is HSlider:
			(c as HSlider).set_value_no_signal(v)
			var shown: Array = _values[key]
			shown[0].text = shown[1].call(v)
	_grey_out("graphics/shadows", shadows_available)
	_grey_out("graphics/screen_space_aa", screen_space_aa_available)
	if attention:
		_sound.set_pressed_no_signal(attention.sound_on)
	# A provider that can't list them: off and greyed out, whatever is saved.
	var off: Dictionary = sidecar.provider_notice("outside_sessions_off") if sidecar else {}
	var outside: CheckButton = _controls["game/outside_sessions"]
	outside.disabled = not off.is_empty()
	if not off.is_empty():
		outside.set_pressed_no_signal(false)
	_outside_off.text = off.get("message", "")
	_outside_off.visible = not off.is_empty()
	_refresh_programs()


## Sets [param provider]'s program by hand, or clears it ([param path]
## empty), as Browse… and Reset do (S02). The row says "Checking…" until
## the sidecar answers.
func choose_program(provider: String, path: String) -> void:
	var row: Dictionary = _programs.get(provider, {})
	if row.is_empty() or sidecar == null:
		return
	row["busy"] = true
	row["error"].text = ""
	_refresh_programs()
	sidecar.set_program_path(provider, path, func(reply: Dictionary) -> void:
		row["busy"] = false
		if reply.get("type") != "ok":
			row["error"].text = "Not changed: %s" % reply.get("message", "")
		_refresh_programs())


## A provider's row as shown, for tests: what was found, and why a choice
## was refused ("" if none). Empty if it has no row.
func program_text(provider: String) -> String:
	return _programs[provider]["status"].text if _programs.has(provider) else ""


func program_error(provider: String) -> String:
	return _programs[provider]["error"].text if _programs.has(provider) else ""


# A row per provider that declares program_path, kept up with what it
# found; rows of providers gone are removed.
func _refresh_programs() -> void:
	var listed: Array = sidecar.providers.filter(func(p: Dictionary) -> bool: return p.get("capabilities", {}).has("program_path")) if sidecar else []
	var ids := listed.map(func(p: Dictionary) -> String: return p.get("provider", ""))
	for id: String in _programs.keys():
		if id not in ids:
			_programs[id]["label"].queue_free()
			_programs[id]["box"].queue_free()
			_programs.erase(id)
	for p: Dictionary in listed:
		var id: String = p.get("provider", "")
		if not _programs.has(id):
			_programs[id] = _program_row(id, str(p.get("name", id)))
		var row: Dictionary = _programs[id]
		var program: Dictionary = p.get("program", {})
		var status: Label = row["status"]
		var missing := program.has("path") and program["path"] == null
		if row["busy"]:
			status.text = "Checking…"
		elif program.is_empty():
			status.text = "Not looked for yet: it's found when a session starts."
		elif missing:
			status.text = str(program.get("message", ""))
		else:
			status.text = "%s\nversion %s%s" % [program.get("path", ""), program.get("version", ""), "  ·  set by hand" if program.get("set_by_hand") else ""]
		status.modulate = Color(0.95, 0.35, 0.3) if missing and not row["busy"] else Color.WHITE
		row["browse"].disabled = row["busy"]
		row["reset"].disabled = row["busy"] or not sidecar.program_paths.has(id)
	_no_providers.visible = _programs.is_empty()


# One row: the provider's name; what it found, Browse… and Reset, and why a
# choice was refused.
func _program_row(id: String, provider_name: String) -> Dictionary:
	var label := Label.new()
	label.text = provider_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var box := VBoxContainer.new()
	box.name = "Program_%s" % id
	box.custom_minimum_size.x = 300.0
	# The path and messages are shown as plain text. Wrapping labels get a
	# width of their own: while Providers is a hidden tab they have none, would
	# wrap at every character, and the panel (as tall as its tallest tab)
	# would grow past the screen.
	var status := Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	status.custom_minimum_size.x = 300.0
	box.add_child(status)
	var buttons := HBoxContainer.new()
	var browse := Button.new()
	browse.text = "Browse…"
	browse.focus_mode = Control.FOCUS_NONE
	browse.pressed.connect(_browse.bind(id))
	buttons.add_child(browse)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Find it as usual"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void: choose_program(id, ""))
	buttons.add_child(reset)
	box.add_child(buttons)
	var error := Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.custom_minimum_size.x = 300.0
	error.add_theme_color_override("font_color", Color(0.95, 0.35, 0.3))
	box.add_child(error)
	_providers.add_child(label)
	_providers.add_child(box)
	return {"status": status, "error": error, "browse": browse, "reset": reset, "label": label, "box": box, "busy": false}


# The system's file picker, starting where the current one is.
func _browse(id: String) -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		add_child(_file_dialog)
	for c: Dictionary in _file_dialog.file_selected.get_connections():
		_file_dialog.file_selected.disconnect(c["callable"])
	_file_dialog.file_selected.connect(func(path: String) -> void: choose_program(id, path), CONNECT_ONE_SHOT)
	var program: Variant = sidecar.provider_program(id).get("path") if sidecar else null
	if program is String:
		_file_dialog.current_dir = (program as String).get_base_dir()
	_file_dialog.filters = PackedStringArray(["*.exe ; Programs"]) if OS.get_name() == "Windows" else PackedStringArray()
	_file_dialog.title = "Choose %s" % _programs[id]["label"].text
	_file_dialog.popup_centered_ratio(0.6)


# A setting the Compatibility renderer can't do: greyed out, shown Off.
func _grey_out(key: String, available: bool) -> void:
	var button: OptionButton = _controls[key]
	button.disabled = not available
	if not available:
		button.select(0) # off, whatever is saved
	button.tooltip_text = "" if available else "Off under the Compatibility renderer"
