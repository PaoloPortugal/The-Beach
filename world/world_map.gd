class_name WorldMap
extends CanvasLayer
## W06: the big map (user's, 2026-10-07). M opens it over the whole
## window, north-up, centred on you at the minimap's scale; drag it or use
## WASD and the arrow keys to look around, the wheel zooms. It shows every
## island (far ones too), bridge, the platform, you, each cluster's name
## and, zoomed in, each session's title and state. Clicking a session's
## island takes you there, and so does clicking the platform (W08). The world doesn't pause; you just don't move,
## and the mouse is free. M or Esc closes it. Placeholder UI, like all UI.

## The player clicked a live session's island.
signal go_to(session_id: String)
## The player clicked the spawn platform (W08).
signal go_to_platform

## Its gap to the window's edges, pixels.
const MARGIN := 24.0
## Pixels a metre: the closest zoom, the furthest one at least (it goes
## further if that's what fits every island), one notch of the wheel, and
## where the session titles show.
const MAX_ZOOM := 4.0
const MIN_ZOOM := 0.5
const ZOOM_STEP := 1.25
const LABEL_ZOOM := 1.0
## Its zoom with no islands to fit.
const START_ZOOM := 1.0
## Keys pan this share of the map's width a second.
const PAN_SPEED := 0.5
## A press let go within this many pixels is a click, not a drag.
const CLICK_SLOP := 6.0
## How close to a tiny island's middle a click still hits it, pixels.
const MIN_HIT := 8.0
## Half the spawn platform's width, metres (world.gd).
const PLATFORM_HALF := 6.0
const SEA := Color(0.06, 0.16, 0.24, 0.96)
const HOVER := Color(1, 1, 1, 0.9)
const NAME_COLOUR := Color(1, 1, 1)
const TITLE_COLOUR := Color(0.92, 0.94, 0.97)
const OUTLINE := Color(0, 0, 0, 0.8)
## A session's state ([method SessionStore.activity]) as a dot's colour.
const STATE_COLOURS := {
	"waiting": Color(1.0, 0.75, 0.25),
	"working": Color(0.45, 0.8, 1.0),
	"error": Color(1.0, 0.4, 0.35),
	"idle": Color(0.65, 0.68, 0.72),
}

var islands: SessionIslands
var player: Player
var store: SessionStore
## Its starting scale is the minimap's.
var minimap: Minimap
## The world point (x, z) at the map's middle, and its pixels a metre.
var centre := Vector2.ZERO
var zoom := START_ZOOM

var _map := Control.new()
var _open := false
# The left button's press, while held, for dragging and clicking.
var _pressed := false
var _press_at := Vector2.ZERO
var _dragged := false
# The live session whose island the pointer is over, or "".
var _hover := ""
# The labels drawn this frame, so a later one doesn't overlap them.
var _labels: Array[Rect2] = []


func _init() -> void:
	layer = 3 # over the minimap, the menu and the chat; under quitting's
	_map.name = "Map"
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.visible = false
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_on_map_input)
	add_child(_map)


func setup(p_islands: SessionIslands, p_player: Player, p_store: SessionStore, p_minimap: Minimap) -> void:
	islands = p_islands
	player = p_player
	store = p_store
	minimap = p_minimap


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_map.visible = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_place()
	centre = Vector2(player.global_position.x, player.global_position.z)
	var fit := minimap.fit_area() if minimap else Rect2()
	zoom = START_ZOOM if fit.size == Vector2.ZERO else minf(_map.size.x / fit.size.x, _map.size.y / fit.size.y)
	zoom = clampf(zoom, min_zoom(), MAX_ZOOM)
	_pressed = false
	_hover = ""
	_map.queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	_map.visible = false
	_pressed = false
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Where a world point is on the map, in the map's pixels.
func to_map(point: Vector3) -> Vector2:
	return _map.size / 2.0 + (Vector2(point.x, point.z) - centre) * zoom


## The world point (x, z) under a point on the map.
func to_world(at: Vector2) -> Vector2:
	return centre + (at - _map.size / 2.0) / zoom


func map_rect() -> Rect2:
	return _map.get_rect()


## The furthest it zooms out: until every island fits, and at least to
## [constant MIN_ZOOM].
func min_zoom() -> float:
	var all := Rect2(Vector2(player.global_position.x, player.global_position.z), Vector2.ZERO)
	for i in islands.all_islands():
		all = all.merge(Minimap.reach_rect(i))
	all = all.grow(Minimap.PADDING)
	return minf(MIN_ZOOM, minf(_map.size.x / all.size.x, _map.size.y / all.size.y))


## Zooms in (steps > 0) or out by wheel notches, keeping the world point
## under [param at] (map pixels) where it is.
func zoom_by(steps: float, at: Vector2) -> void:
	var held := to_world(at)
	zoom = clampf(zoom * pow(ZOOM_STEP, steps), min_zoom(), MAX_ZOOM)
	centre = held - (at - _map.size / 2.0) / zoom
	_map.queue_redraw()


## Moves the view by [param pixels] on the map, as a drag does.
func drag_by(pixels: Vector2) -> void:
	centre -= pixels / zoom
	_map.queue_redraw()


## The live session whose island is at [param at] (map pixels), or "".
func session_at(at: Vector2) -> String:
	var found := ""
	var best := INF
	for id in islands.session_ids():
		var i := islands.island(id)
		var d := to_map(i.global_position).distance_to(at)
		if d <= maxf(i.generator.radius * zoom, MIN_HIT) and d < best:
			found = id
			best = d
	return found


## Whether the spawn platform is at [param at] (map pixels).
func platform_at(at: Vector2) -> bool:
	var half := maxf(PLATFORM_HALF * zoom, MIN_HIT)
	var d := (at - to_map(Vector3.ZERO)).abs()
	return d.x <= half and d.y <= half


## A click on the map at [param at] (map pixels): on a live session's
## island or the platform it closes the map and asks to go there.
func click(at: Vector2) -> void:
	if platform_at(at):
		close()
		go_to_platform.emit()
		return
	var id := session_at(at)
	if id.is_empty():
		return
	close()
	go_to.emit(id)


# _input, not _unhandled_input, so Esc closes the map before the player
# sees it (the player's Esc frees the mouse).
func _input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("minimap") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
	elif not _open and event.is_action_pressed("minimap") and player.controls_enabled:
		get_viewport().set_input_as_handled()
		open()


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP when event.pressed:
				zoom_by(event.factor if event.factor > 0.0 else 1.0, event.position)
			MOUSE_BUTTON_WHEEL_DOWN when event.pressed:
				zoom_by(-(event.factor if event.factor > 0.0 else 1.0), event.position)
			MOUSE_BUTTON_LEFT when event.pressed:
				_pressed = true
				_dragged = false
				_press_at = event.position
			MOUSE_BUTTON_LEFT:
				var was_click := _pressed and not _dragged
				_pressed = false
				if was_click:
					click(event.position)
		_map.accept_event()
	elif event is InputEventMouseMotion:
		if _pressed:
			_dragged = _dragged or event.position.distance_to(_press_at) > CLICK_SLOP
			if _dragged:
				drag_by(event.relative)
		_hover = "" if _pressed else session_at(event.position)
		_map.accept_event()


func _process(delta: float) -> void:
	if not _open:
		return
	_place()
	var keys := Input.get_vector("move_left", "move_right", "move_forward", "move_back") + Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if keys != Vector2.ZERO:
		centre += keys.limit_length(1.0) * _map.size.x * PAN_SPEED * delta / zoom
	if not _hover.is_empty() and islands.island(_hover) == null:
		_hover = ""
	_map.mouse_default_cursor_shape = Control.CURSOR_DRAG if _dragged and _pressed else Control.CURSOR_POINTING_HAND if not _hover.is_empty() else Control.CURSOR_ARROW
	_map.queue_redraw()


# Fills the window, [constant MARGIN] in from its edges.
func _place() -> void:
	var rect := get_viewport().get_visible_rect().grow(-MARGIN)
	_map.position = rect.position
	_map.size = rect.size.max(Vector2.ONE)


func _draw_map() -> void:
	var view := Rect2(Vector2.ZERO, _map.size)
	_map.draw_rect(view, SEA)
	Minimap.draw_platform(_map, to_map)
	var left := islands.left_islands()
	var shown: Array[Island] = []
	for i in islands.all_islands():
		var r := Minimap.reach_rect(i)
		if view.intersects(Rect2(to_map(Vector3(r.position.x, 0, r.position.y)), r.size * zoom).grow(MIN_HIT)):
			shown.append(i)
	for i in shown:
		var colour := Minimap.EMPTY_LAND if i in left else Minimap.land_colour(i)
		Minimap.draw_island(_map, i, to_map, colour)
		# Far out, an island is a dot at least.
		_map.draw_circle(to_map(i.global_position), 2.5, colour)
	for b in islands.bridges.all_bridges():
		if is_instance_valid(b):
			_map.draw_line(to_map(b.from), to_map(b.to), Minimap.BRIDGE, maxf(2.4 * zoom, 1.5))
	if not _hover.is_empty() and islands.island(_hover):
		var line := Minimap.shoreline(islands.island(_hover), to_map)
		line.append(line[0])
		_map.draw_polyline(line, HOVER, 2.0)
	_labels.clear()
	_draw_cluster_names()
	if zoom >= LABEL_ZOOM:
		_draw_titles(shown)
	Minimap.draw_you(_map, player, to_map)
	_map.draw_rect(view, Color(1, 1, 1, 0.5), false, 1.0)


# Under each live session's island: a dot in its state's colour, then
# "title · state". Cluster names come first, then titles, where they fit.
func _draw_titles(shown: Array[Island]) -> void:
	var font := ThemeDB.fallback_font
	for id in islands.session_ids():
		var i := islands.island(id)
		if i not in shown:
			continue
		var s := store.session(id)
		var activity := store.activity(id)
		var text := "%s · %s" % [SessionsMenu.display_title(s.get("title")), SessionsMenu.state_text(activity)]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var at := to_map(i.global_position) + Vector2(-width / 2.0 + 6.0, i.generator.radius * zoom + 16.0)
		if not _room(Rect2(at + Vector2(-16.0, -14.0), Vector2(width + 16.0, 18.0))):
			continue
		_map.draw_circle(at + Vector2(-10.0, -5.0), 5.0, STATE_COLOURS.get(activity, STATE_COLOURS["idle"]))
		_map.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, OUTLINE)
		_map.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, TITLE_COLOUR)


# Each cluster's name, over the middle of its islands in its wedge (or
# its far ones, with none there), above the top one.
func _draw_cluster_names() -> void:
	var font := ThemeDB.fallback_font
	var of := {} # cluster id → its islands
	var far := {} # cluster id → its islands in far spots
	for i in islands.all_islands():
		(far if islands.is_far(i) else of).get_or_add(islands.cluster_of(i), []).append(i)
	for cluster: String in far:
		if not of.has(cluster):
			of[cluster] = far[cluster]
	for cluster: String in of:
		if cluster.is_empty():
			continue
		var middle := Vector2.ZERO
		var top := INF
		for i: Island in of[cluster]:
			var at := to_map(i.global_position)
			middle += at
			top = minf(top, at.y - i.generator.radius * zoom)
		middle /= of[cluster].size()
		var text := islands.clusters.cluster_name(cluster)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		var at := Vector2(middle.x - width / 2.0, top - 8.0)
		if not _room(Rect2(at + Vector2(0.0, -18.0), Vector2(width, 22.0))):
			continue
		_map.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, OUTLINE)
		_map.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, NAME_COLOUR)


# Whether a label fits without overlapping one drawn before it this
# frame; if so, it's taken. Labels that don't fit are skipped.
func _room(rect: Rect2) -> bool:
	for taken in _labels:
		if taken.intersects(rect):
			return false
	_labels.append(rect)
	return true
