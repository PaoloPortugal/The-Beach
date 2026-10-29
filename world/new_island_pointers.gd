class_name NewIslandPointers
extends CanvasLayer
## W04: while a new session's island is off-screen, an arrow at the
## screen's edge points to it, with its project's name and distance, until
## the player has been on it (SessionIslands.unvisited). On screen, its
## beacon shows where it is. Placeholder UI, like all UI.

## Pixels from the screen's edge (less on a tiny window, see [method margin]).
const MARGIN := 56.0
## Where on the island it points: high enough that an island still under
## water counts as on screen when its beacon is.
const AIM_HEIGHT := 20.0

var islands: SessionIslands
var store: SessionStore

var _arrows := {} # session id → Node2D


func setup(p_islands: SessionIslands, p_store: SessionStore) -> void:
	islands = p_islands
	store = p_store


## The sessions whose arrows show now (for tests).
func shown() -> Array[String]:
	var out: Array[String] = []
	for id: String in _arrows:
		if _arrows[id].visible:
			out.append(id)
	return out


## The margin used now: [constant MARGIN], at most a quarter of the
## window's smaller side.
func margin() -> float:
	var size := get_viewport().get_visible_rect().size
	return minf(MARGIN, minf(size.x, size.y) / 4.0)


## Where an arrow is and the way it points (for tests), or null.
func arrow(session_id: String) -> Node2D:
	return _arrows.get(session_id)


func _process(_delta: float) -> void:
	var ids: Array[String] = islands.unvisited() if islands else ([] as Array[String])
	for id: String in _arrows.keys():
		if not id in ids:
			_arrows[id].queue_free()
			_arrows.erase(id)
	var camera := get_viewport().get_camera_3d()
	for id in ids:
		if not _arrows.has(id):
			_arrows[id] = _make_arrow()
			add_child(_arrows[id])
		var a: Node2D = _arrows[id]
		var target := islands.island(id).global_position + Vector3(0.0, AIM_HEIGHT, 0.0)
		var place := _edge(camera, target)
		a.visible = place.size() == 2
		if not a.visible:
			continue
		a.position = place[0]
		a.get_node("Tip").rotation = place[1]
		var label: Label = a.get_node("Label")
		var s := store.session(id) if store else {}
		var metres := Vector2(target.x - camera.global_position.x, target.z - camera.global_position.z).length()
		label.text = "%s · %d m" % [SessionsMenu.project_name(s.get("project", {})), roundi(metres)]
		# The label sits on the screen's side of the arrow, kept on screen.
		var size := get_viewport().get_visible_rect().size
		var at: Vector2 = place[0] - Vector2.from_angle(place[1]) * 34.0 - label.size / 2.0
		at = at.clamp(Vector2(8, 8), (size - label.size - Vector2(8, 8)).max(Vector2(8, 8)))
		label.position = at - a.position


# [position, angle] on the inset edge toward [param target], or [] when
# it's on screen.
func _edge(camera: Camera3D, target: Vector3) -> Array:
	if camera == null:
		return []
	var rect := get_viewport().get_visible_rect()
	var behind := camera.is_position_behind(target)
	var p := camera.unproject_position(target)
	var m := margin()
	if not behind and rect.grow(-m).has_point(p):
		return []
	var centre := rect.size / 2.0
	var dir := p - centre
	if behind:
		dir = -dir
	if dir.length() < 0.001:
		dir = Vector2.DOWN
	var half := centre - Vector2(m, m)
	var t := INF
	if dir.x != 0.0:
		t = half.x / absf(dir.x)
	if dir.y != 0.0:
		t = minf(t, half.y / absf(dir.y))
	return [centre + dir * t, dir.angle()]


func _make_arrow() -> Node2D:
	var a := Node2D.new()
	var tip := Polygon2D.new()
	tip.name = "Tip"
	tip.polygon = PackedVector2Array([Vector2(18, 0), Vector2(-10, -13), Vector2(-4, 0), Vector2(-10, 13)])
	tip.color = SessionIslands.NEW_COLOUR
	a.add_child(tip)
	var label := Languages.content(Label.new()) as Label # the project's name (C16)
	label.name = "Label"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", SessionIslands.NEW_COLOUR)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	a.add_child(label)
	return a
