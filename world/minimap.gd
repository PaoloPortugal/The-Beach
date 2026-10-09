class_name Minimap
extends CanvasLayer
## W06: a small map of the cluster you're in or nearest to (its islands,
## bridges, the platform when in view, and you), north-up, in the top
## left. Always on, except while [member hidden_when] says so (the chat,
## the sessions menu or the big map is open). Placeholder UI, like all UI.
## Its drawing helpers are shared with the big map ([WorldMap]).

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
## How far an island's region reaches, as a share of its generator's
## radius (as for its bridges: SessionIslands).
const REACH := 1.45

var islands: SessionIslands
var player: Node3D
## Returns true while the map should be hidden.
var hidden_when := func() -> bool: return false
## Its gap to the top (more under the live checklist).
var top := GAP

var _map := Control.new()
# The cluster shown and the world rectangle (x, z) it fits, for tests.
var _shown := ""
var _area := Rect2()
# The islands drawn: the cluster's.
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


## The square of the world (x, z) the minimap fits: the islands of the
## cluster nearest you (near or far) and you, with
## [constant PADDING] of sea around. Empty with no islands. The big map
## opens at this scale.
func fit_area() -> Rect2:
	_shown = islands.nearest_cluster(player.global_position) if islands and player else ""
	if _shown.is_empty():
		return Rect2()
	_drawn = islands.cluster_islands(_shown)
	var area := Rect2(Vector2(player.global_position.x, player.global_position.z), Vector2.ZERO)
	for i in _drawn:
		area = area.merge(reach_rect(i))
	area = area.grow(PADDING)
	var longest := maxf(area.size.x, area.size.y)
	return Rect2(area.get_center() - Vector2(longest, longest) / 2.0, Vector2(longest, longest))


func _process(_delta: float) -> void:
	_area = fit_area()
	_map.visible = not hidden_when.call() and not _shown.is_empty()
	if not _map.visible:
		return
	var screen := get_viewport().get_visible_rect().size
	var side := minf(SIZE, minf(screen.x, screen.y) / 3.0)
	_map.position = Vector2(GAP, top)
	_map.size = Vector2(side, side)
	_map.queue_redraw()


func _draw_map() -> void:
	_map.draw_rect(Rect2(Vector2.ZERO, _map.size), SEA)
	draw_platform(_map, to_map)
	var left := islands.left_islands()
	for i in _drawn:
		draw_island(_map, i, to_map, EMPTY_LAND if i in left else land_colour(i))
	for b in islands.bridges.bridges_in(_shown):
		if is_instance_valid(b):
			_map.draw_line(to_map(b.from), to_map(b.to), BRIDGE, 3.0)
	draw_you(_map, player, to_map)
	_map.draw_rect(Rect2(Vector2.ZERO, _map.size), Color(1, 1, 1, 0.5), false, 1.0)


## The square of the world (x, z) an island's region covers.
static func reach_rect(i: Island) -> Rect2:
	var reach := i.generator.radius * REACH
	return Rect2(Vector2(i.global_position.x, i.global_position.z) - Vector2(reach, reach), Vector2(reach, reach) * 2.0)


## Draws the spawn platform, at the world's centre, on [param canvas];
## [param to_map] turns a world point into the canvas's pixels.
static func draw_platform(canvas: CanvasItem, to_map: Callable) -> void:
	var platform := PackedVector2Array()
	for corner in [Vector3(-6, 0, -6), Vector3(6, 0, -6), Vector3(6, 0, 6), Vector3(-6, 0, 6)]:
		platform.append(to_map.call(corner))
	canvas.draw_colored_polygon(platform, BRIDGE)


## An island's shoreline on the canvas.
static func shoreline(i: Island, to_map: Callable) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for k in 24:
		var a := k * TAU / 24.0
		var r := i.generator.shore_radius(cos(a), sin(a))
		outline.append(to_map.call(i.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)))
	return outline


## An island's colour on the maps: a beach's sand, else its biome's
## ground (W10).
static func land_colour(i: Island) -> Color:
	return LAND if i.biome == Biome.Kind.BEACH else Biome.profile(i.biome)["ground"]


static func draw_island(canvas: CanvasItem, i: Island, to_map: Callable, colour: Color) -> void:
	canvas.draw_colored_polygon(shoreline(i, to_map), colour)


## You: an arrow pointing where you face (-z is ahead).
static func draw_you(canvas: CanvasItem, player: Node3D, to_map: Callable) -> void:
	var at: Vector2 = to_map.call(player.global_position)
	var ahead := -player.global_transform.basis.z
	var dir := Vector2(ahead.x, ahead.z).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP
	var side := dir.orthogonal()
	canvas.draw_colored_polygon(PackedVector2Array([at + dir * 8.0, at - dir * 5.0 + side * 5.0, at - dir * 2.0, at - dir * 5.0 - side * 5.0]), YOU)
