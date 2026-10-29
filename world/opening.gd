class_name Opening
extends CanvasLayer
## The game's opening (C17; user's decisions, 2026-10-28): a card with the
## developer's logo and name, "Made with" Godot's logo along the bottom,
## covering the world and the main menu (C14) as the game starts. It shows
## for at least [constant CARD_S], and stays, with a bar saying how far
## the start is, until the sidecar has synced and, if sessions came back,
## the first island has started rising (at most [constant ISLAND_WAIT_S]
## after the sync). Then it fades into the main menu. A key or click
## skips the card: straight to the menu if the game is ready, else to the
## bar. Lifted too when the sidecar fails (S01 says why), and after
## [constant TIMEOUT_S] whatever happens. Keys and clicks wait under it.
## A PLACEHOLDER, like all UI; the logos are the user's and Godot's.

const LOGO := preload("res://assets/opening/moofys_logo.png")
const GODOT_LOGO := preload("res://assets/opening/godot_logo.png")
const DEVELOPER := "moofys"
## The card's least time on screen, its fade in included.
const CARD_S := 2.5
const FADE_IN_S := 0.4
const FADE_OUT_S := 0.5
## How long it waits after the sync for the first island to start rising.
const ISLAND_WAIT_S := 5.0
## Past the client's longest start (every attempt and the waits between
## them), plus the sync: never stuck.
const TIMEOUT_S := SidecarClient.START_TIMEOUT_S + 10.0
## The logo's share of the window's height, in whole steps of its pixels.
const LOGO_SHARE := 0.32
const BACKGROUND := Color(0.95, 0.92, 0.85)
const INK := Color(0.12, 0.12, 0.17)

## Emitted once it has faded out.
signal lifted

var _sidecar: SidecarClient
var _store: SessionStore
var _covering := false
var _lifting := false
var _skipped := false
var _elapsed := 0.0
var _synced := false
var _synced_at := 0.0 # its time since shown when the sidecar synced
var _islands_coming := false
var _island_rising := false
var _root := Control.new()
var _logo := TextureRect.new()
var _status := VBoxContainer.new()
var _stage := Label.new()
var _bar := ProgressBar.new()
var _target := 0.0
var _fade: Tween


func _init() -> void:
	layer = 9 # over the menus and the HUD, under the quit dialog (10)
	_build()
	visible = false


## Covers the world until the game is ready, [param sidecar] and
## [param store] saying how the start goes and [param islands] when the
## first island rises. A sidecar already failed or stopped covers
## nothing.
func setup(sidecar: SidecarClient, store: SessionStore, islands: SessionIslands) -> void:
	_sidecar = sidecar
	_store = store
	if sidecar.status in [SidecarClient.Status.FAILED, SidecarClient.Status.STOPPED]:
		lifted.emit.call_deferred()
		return
	_covering = true
	visible = true
	_root.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(_root, "modulate:a", 1.0, FADE_IN_S)
	if sidecar.status == SidecarClient.Status.READY:
		_on_synced([])
	else:
		sidecar.synced.connect(_on_synced, CONNECT_ONE_SHOT)
	islands.island_rising.connect(func(_id: String) -> void: _island_rising = true)


func is_covering() -> bool:
	return _covering


## Whether the bar and its stage show.
func bar_shown() -> bool:
	return _status.visible


## The stage the bar names, for tests.
func stage_text() -> String:
	return _stage.text


## How far the bar is (0 to 1), for tests.
func bar_value() -> float:
	return _bar.value


## The card skipped, as a key or click does.
func skip() -> void:
	_skipped = true


## Gone at once: dev tools that show the world straight away.
func lift_now() -> void:
	if not _covering:
		return
	_covering = false
	visible = false
	lifted.emit()


func _on_synced(_providers: Array) -> void:
	_synced = true
	_synced_at = _elapsed
	# Sessions back from before (S07, S08) bring their islands up behind.
	_islands_coming = not _store.sessions.is_empty()


func _is_ready() -> bool:
	if _sidecar.status in [SidecarClient.Status.FAILED, SidecarClient.Status.STOPPED] or _elapsed >= TIMEOUT_S:
		return true
	if not _synced:
		return false
	return not _islands_coming or _island_rising or _elapsed - _synced_at >= ISLAND_WAIT_S


func _process(delta: float) -> void:
	if not _covering or _lifting:
		return
	_elapsed += delta
	var card_done := _skipped or _elapsed >= CARD_S
	if _is_ready():
		if card_done:
			_lift()
		return
	if card_done:
		_status.visible = true
	_show_stage()
	_bar.value = lerpf(_bar.value, _target, 1.0 - exp(-4.0 * delta))


func _show_stage() -> void:
	if _synced:
		_stage.text = tr("Bringing up your islands…")
		_target = 0.85
	elif _sidecar.status in [SidecarClient.Status.CONNECTING, SidecarClient.Status.SYNCING]:
		_stage.text = tr("Finding your sessions…")
		_target = 0.55
	elif _sidecar.attempt() > 0:
		_stage.text = Languages.fill(tr("Starting the sidecar (try {try} of {tries})…"), {"try": Languages.number(str(_sidecar.attempt() + 1)), "tries": Languages.number(str(_sidecar.handshake_timeouts_s.size()))})
		_target = 0.25
	else:
		_stage.text = tr("Starting the sidecar…")
		_target = 0.25


func _lift() -> void:
	_lifting = true
	_bar.value = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _fade:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_root, "modulate:a", 0.0, FADE_OUT_S)
	_fade.finished.connect(func() -> void:
		_lifting = false
		lift_now())


# A key, click or button skips the card; none reaches what's under it.
func _input(event: InputEvent) -> void:
	if not _covering or _lifting:
		return
	if event.is_pressed() and not event.is_echo() and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		skip()
	if not event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


# The logo in whole steps of its pixels, so they stay square.
func _fit() -> void:
	var height := get_viewport().get_visible_rect().size.y
	var step := maxi(2, floori(height * LOGO_SHARE / LOGO.get_height()))
	_logo.custom_minimum_size = Vector2(LOGO.get_width(), LOGO.get_height()) * step


func _build() -> void:
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var card := VBoxContainer.new()
	card.name = "Card"
	card.add_theme_constant_override("separation", 14)
	center.add_child(card)
	_logo.name = "Logo"
	_logo.texture = LOGO
	_logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(_logo)
	var name_label := Label.new()
	name_label.name = "Developer"
	name_label.text = DEVELOPER
	Languages.content(name_label) # a name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", INK)
	card.add_child(name_label)
	# The bar, once the card's time is up and the game isn't ready.
	_status.name = "Status"
	_status.add_theme_constant_override("separation", 6)
	_status.custom_minimum_size.x = 360.0
	_status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_status.visible = false
	card.add_child(_status)
	_bar.name = "Bar"
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.custom_minimum_size.y = 8.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(INK, 0.15)
	track.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = INK
	fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	_status.add_child(_bar)
	_stage.name = "Stage"
	Languages.translated(_stage)
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_font_size_override("font_size", 16)
	_stage.add_theme_color_override("font_color", Color(INK, 0.7))
	_status.add_child(_stage)
	# "Made with" Godot's logo, along the bottom.
	var made := HBoxContainer.new()
	made.name = "MadeWith"
	made.alignment = BoxContainer.ALIGNMENT_CENTER
	made.add_theme_constant_override("separation", 10)
	made.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	made.grow_horizontal = Control.GROW_DIRECTION_BOTH
	made.grow_vertical = Control.GROW_DIRECTION_BEGIN
	made.offset_bottom = -28.0
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(made)
	var with := Label.new()
	with.text = "Made with"
	with.add_theme_font_size_override("font_size", 16)
	with.add_theme_color_override("font_color", Color(INK, 0.7))
	with.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	made.add_child(with)
	var godot := TextureRect.new()
	godot.name = "GodotLogo"
	godot.texture = GODOT_LOGO
	godot.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	godot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	godot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	godot.custom_minimum_size = Vector2(GODOT_LOGO.get_width(), GODOT_LOGO.get_height()) * (56.0 / GODOT_LOGO.get_height())
	made.add_child(godot)
