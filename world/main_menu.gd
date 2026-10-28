class_name MainMenu
extends CanvasLayer
## The main menu (C14): the game opens on it, over the live world, while
## the [MenuCamera] circles the islands; the sidecar starts and islands
## come behind it. Play is never held back: the camera eases down to the
## player and the controls come back when it gets there. Settings opens
## the settings menu (C10) as the pause menu does; Credits shows
## assets/CREDITS.md, with Godot's own notices behind a toggle; Quit asks first while
## sessions run (S05). The pause menu's Main menu (C13) brings it back,
## the camera easing up; sessions keep running. A PLACEHOLDER, like all
## UI for now.

## The game's name on the menu: the working name (NOTES.md → Conventions
## → Renaming the project).
const TITLE := "The Beach"
const BUTTONS := ["Play", "Settings", "Credits", "Quit"] # TRANSLATE
const CREDITS_FILE := "res://assets/CREDITS.md"

## Emitted once the camera is back with the player and the controls too.
signal played
## Emitted when it opens, and on Play (or [method close_now]) before the
## camera heads for the player, who may be moved then.
signal opened
signal leaving

var player: Player
var settings_menu: SettingsMenu
var quit_guard: QuitGuard
var camera: MenuCamera
## The HUD it hides while it shows (the minimap hides itself).
var hud: Array[CanvasLayer] = []
## Opens a link from the credits; tests replace it.
var open_link: Callable = func(url: String) -> void: OS.shell_open(url)

var _open := false
var _back_before := Callable()
var _dim := ColorRect.new()
var _panel := PanelContainer.new()
var _credits := PanelContainer.new()
var _credits_body: VBoxContainer
var _licences: VBoxContainer # Godot's notices, behind their toggle
## Said instead of the credits when their file can't be read.
var _credits_error: RichTextLabel
var _buttons := {} # text → its Button


func _init() -> void:
	layer = 2
	_build()
	_dim.visible = false
	_panel.visible = false
	_credits.visible = false


func setup(with_player: Player, with_settings_menu: SettingsMenu, with_quit_guard: QuitGuard, with_camera: MenuCamera) -> void:
	player = with_player
	settings_menu = with_settings_menu
	quit_guard = with_quit_guard
	camera = with_camera
	camera.player_camera = player.get_node("Head/Camera3D")
	camera.arrived.connect(_on_arrived)


## Whether it shows, its settings and credits pages and the ease down to
## the player included.
func is_open() -> bool:
	return _open


## The game's start: straight onto the circle.
func open_at_start() -> void:
	_show()
	camera.start_orbit()


## From the game (the pause menu's Main menu): the camera eases up.
func open() -> void:
	if _open:
		return
	_show()
	camera.ascend()


## Play: the camera eases down to the player, who gets the controls back
## when it's there ([signal played]).
func play() -> void:
	if not _open or not _panel.visible:
		return
	_dim.visible = false
	_panel.visible = false
	leaving.emit()
	camera.descend()


## Gone at once, the camera back with the player: dev tools that show
## the world straight away (the layout and ring demos).
func close_now() -> void:
	if not _open:
		return
	_dim.visible = false
	_panel.visible = false
	_credits.visible = false
	leaving.emit()
	camera.stop()
	_on_arrived()


func open_settings() -> void:
	_panel.visible = false
	_back_before = settings_menu.back
	settings_menu.back = _back_from_settings
	settings_menu.open()


func open_credits() -> void:
	if _credits_body.get_child_count() == 0:
		_fill_credits()
	_panel.visible = false
	_credits.visible = true


func close_credits() -> void:
	_credits.visible = false
	_panel.visible = true


func credits_open() -> bool:
	return _credits.visible


func quit() -> void:
	quit_guard.request_quit()


## The button reading [param text] (one of [constant BUTTONS]), for tests.
func button(text: String) -> Button:
	return _buttons[text]


## Shows or hides Godot's licences under the credits (their toggle).
func toggle_godot_licences() -> void:
	if _licences.get_child_count() == 0:
		_licences.add_child(_plain(Engine.get_license_text()))
		_licences.add_child(_plain(_godot_components()))
	_licences.visible = not _licences.visible
	_buttons["Godot licences"].text = "Hide Godot licences" if _licences.visible else "Show Godot licences" # TRANSLATE


func godot_licences_shown() -> bool:
	return _licences != null and _licences.visible


## The credits' text as shown, for tests (empty until first opened).
func credits_text() -> String:
	var parts: PackedStringArray = []
	_shown_text(_credits_body, parts)
	return "\n".join(parts)


func _shown_text(node: Node, parts: PackedStringArray) -> void:
	for c in node.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		if c is MarkdownView:
			parts.append((c as MarkdownView).shown_text())
		elif c is Label:
			parts.append((c as Label).text)
		elif c is Button:
			parts.append((c as Button).text)
		elif c is RichTextLabel:
			parts.append((c as RichTextLabel).get_parsed_text())
		elif c is VBoxContainer:
			_shown_text(c, parts)


func _show() -> void:
	_open = true
	_dim.visible = true
	_panel.visible = true
	_credits.visible = false
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for h in hud:
		h.visible = false
	opened.emit()


func _on_arrived() -> void:
	_open = false
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for h in hud:
		h.visible = true
	played.emit()


# Esc in the settings: back here, and the settings back to the pause menu's.
func _back_from_settings() -> void:
	settings_menu.back = _back_before
	_panel.visible = true


# The credits' one formatted line, in the new language.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _credits_error:
		_credits_error.text = Languages.fill(tr("The credits file couldn't be read ({file})."), {"file": CREDITS_FILE})


# Esc leaves the credits; on the menu itself it does nothing (Play or Quit).
# The settings menu takes its own Esc first.
func _input(event: InputEvent) -> void:
	if _open and _credits.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_credits()


func _fill_credits() -> void:
	var text := FileAccess.get_file_as_string(CREDITS_FILE)
	if text.is_empty():
		_credits_error = Languages.translated(_plain("")) as RichTextLabel
		_credits_body.add_child(_credits_error)
		_notification(NOTIFICATION_TRANSLATION_CHANGED)
	else:
		var view := MarkdownView.new()
		view.font_size = 16
		view.link_clicked.connect(func(url: String) -> void: open_link.call(url))
		_credits_body.add_child(view)
		view.set_markdown(text)
	var godot := Label.new()
	godot.text = "Made with Godot Engine"
	godot.add_theme_font_size_override("font_size", 22)
	_credits_body.add_child(godot)
	# Godot's licence and its parts' (long; built when first shown).
	var toggle := Button.new()
	toggle.name = "GodotLicences"
	toggle.text = "Show Godot licences"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.pressed.connect(toggle_godot_licences)
	_credits_body.add_child(toggle)
	_buttons["Godot licences"] = toggle
	_licences = VBoxContainer.new()
	_licences.name = "Licences"
	Languages.content(_licences) # Godot's legal text, as written
	_licences.add_theme_constant_override("separation", 14)
	_licences.visible = false
	_credits_body.add_child(_licences)


# The parts of Godot made by others, each with its copyright and licence,
# then the licences' texts (Engine.get_copyright_info, get_license_info).
func _godot_components() -> String:
	var lines: PackedStringArray = ["Godot Engine includes these third-party parts:", ""]
	for component: Dictionary in Engine.get_copyright_info():
		lines.append(component.name)
		for part: Dictionary in component.parts:
			for holder: String in part.copyright:
				lines.append("    © " + holder)
			lines.append("    License: " + part.license)
		lines.append("")
	var licenses := Engine.get_license_info()
	for name: String in licenses:
		lines.append("— " + name + " —")
		lines.append(licenses[name])
		lines.append("")
	return "\n".join(lines)


# Long plain text, never read as BBCode.
func _plain(text: String) -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = false
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.add_theme_font_size_override("normal_font_size", 14)
	rtl.text = text
	return rtl


func _build() -> void:
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", _style())
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_panel.add_child(layout)
	var title := Label.new()
	title.name = "Title"
	title.text = TITLE
	Languages.content(title) # the game's name
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)
	for text: String in BUTTONS:
		var b := Button.new()
		b.name = text
		b.text = text
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 40.0
		layout.add_child(b)
		_buttons[text] = b
	_buttons["Play"].pressed.connect(play)
	_buttons["Settings"].pressed.connect(open_settings)
	_buttons["Credits"].pressed.connect(open_credits)
	_buttons["Quit"].pressed.connect(quit)

	_credits.name = "Credits"
	_credits.add_theme_stylebox_override("panel", _style())
	_credits.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Most of the screen, the world dimmed round it.
	_credits.anchor_left = 0.15
	_credits.anchor_right = 0.85
	_credits.anchor_top = 0.08
	_credits.anchor_bottom = 0.92
	add_child(_credits)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_credits.add_child(column)
	var heading := Label.new()
	heading.text = "Credits"
	heading.add_theme_font_size_override("font_size", 26)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_credits_body = VBoxContainer.new()
	_credits_body.name = "Body"
	_credits_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_credits_body.add_theme_constant_override("separation", 14)
	scroll.add_child(_credits_body)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(160, 40)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(close_credits)
	column.add_child(back)
	_buttons["Back"] = back


# The pause menu's panel (C13).
static func _style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.11, 0.94)
	style.set_corner_radius_all(16)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style
