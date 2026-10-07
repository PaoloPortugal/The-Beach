class_name Minimap
extends CanvasLayer
## W06: a small map of the cluster you're in or nearest to (its islands,
## bridges, the platform when in view, and you), north-up, in the top
## left. M shows or hides it; it's hidden while [member hidden_when] says
## so (the chat or the sessions menu is open). Placeholder UI, like all UI.

## Its size in pixels (less on a tiny window), and its gap to the edges.
const SIZE := 200.0
const GAP := 16.0
## Metres of sea kept around what it shows.
const PADDING := 30.0
const SEA := Color(0.08, 0.2, 0.3, 0.75)
const LAND := Color(0.94, 0.85, 0.63)
const EMPTY_LAND := Color(0.6, 0.56, 0.47)
const BRIDGE := Color(0.55, 0.4, 0.26)
const YOU := Color(1, 1, 1)

var islands: SessionIslands
var player: Node3D
## Returns true while the map should be hidden.
var hidden_when := func() -> bool: return false
## Whether it's switched on (M).
var on := true
## Its gap to the top (more under the live checklist).
var top := GAP

var _map := Control.new()
# The cluster shown and the world rectangle (x, z) it fits, for tests.
var _shown := ""
var _area := Rect2()
# The islands drawn: the cluster's bridged ones, or the far one you're at.
var _drawn: Array[Island] = []


func _init() -> void:
	layer = 1
	_map.name = "Map"
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.draw.connect(_draw_map)
	add_child(_map)


func setup(p_islands: SessionIslands, p_player: Node3D) -> void:
	islands = p_islands
	player = p_player


## The cluster it shows now, or "" (for tests).
func shown_cluster() -> String:
	return _shown if _map.visible else ""


## Where a world point is on the map, in the map's pixels (for tests).
func to_map(point: Vector3) -> Vector2:
	var scale := _map.size.x / _area.size.x
	return (Vector2(point.x, point.z) - _area.position) * scale


func map_rect() -> Rect2:
	return _map.get_rect()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("minimap") and not hidden_when.call():
		on = not on
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_shown = islands.nearest_cluster(player.global_position) if islands and player else ""
	_map.visible = on and not hidden_when.call() and not _shown.is_empty()
	if not _map.visible:
		return
	var screen := get_viewport().get_visible_rect().size
	var side := minf(SIZE, minf(screen.x, screen.y) / 3.0)
	_map.position = Vector2(GAP, top)
	_map.size = Vector2(side, side)
	# Fit the cluster's islands and you, square.
	_drawn = _islands_shown()
	var area := Rect2(Vector2(player.global_position.x, player.global_position.z), Vector2.ZERO)
	for i in _drawn:
		var reach := i.generator.radius * 1.45
		area = area.merge(Rect2(Vector2(i.global_position.x, i.global_position.z) - Vector2(reach, reach), Vector2(reach, reach) * 2.0))
	area = area.grow(PADDING)
	var longest := maxf(area.size.x, area.size.y)
	_area = Rect2(area.get_center() - Vector2(longest, longest) / 2.0, Vector2(longest, longest))
	_map.queue_redraw()


# The cluster's islands joined by bridges, or, near one in a far spot
# (no bridges, W06), just that one.
func _islands_shown() -> Array[Island]:
	var all := islands.cluster_islands(_shown)
	var nearest: Island = null
	for i in all:
		if nearest == null or i.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
			nearest = i
	if nearest == null or islands.is_far(nearest):
		var just: Array[Island] = []
		if nearest:
			just.append(nearest)
		return just
	var out: Array[Island] = []
	out.assign(all.filter(func(i: Island) -> bool: return not islands.is_far(i)))
	return out


func _draw_map() -> void:
	_map.draw_rect(Rect2(Vector2.ZERO, _map.size), SEA)
	# The spawn platform, at the world's centre.
	var platform := PackedVector2Array()
	for corner in [Vector3(-6, 0, -6), Vector3(6, 0, -6), Vector3(6, 0, 6), Vector3(-6, 0, 6)]:
		platform.append(to_map(corner))
	_map.draw_colored_polygon(platform, BRIDGE)
	for i in _drawn:
		var outline := PackedVector2Array()
		for k in 24:
			var a := k * TAU / 24.0
			var r := i.generator.shore_radius(cos(a), sin(a))
			outline.append(to_map(i.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)))
		_map.draw_colored_polygon(outline, EMPTY_LAND if i in islands.left_islands() else LAND)
	for b in islands.bridges.bridges_in(_shown):
		if is_instance_valid(b):
			_map.draw_line(to_map(b.from), to_map(b.to), BRIDGE, 3.0)
	# You: an arrow pointing where you face (-z is ahead).
	var at := to_map(player.global_position)
	var ahead := -player.global_transform.basis.z
	var dir := Vector2(ahead.x, ahead.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var side := dir.orthogonal()
	_map.draw_colored_polygon(PackedVector2Array([at + dir * 8.0, at - dir * 5.0 + side * 5.0, at - dir * 2.0, at - dir * 5.0 - side * 5.0]), YOU)
	_map.draw_rect(Rect2(Vector2.ZERO, _map.size), Color(1, 1, 1, 0.5), false, 1.0)
