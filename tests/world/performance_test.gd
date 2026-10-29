extends SceneTree
## Headless test for the performance rules (NOTES → Architecture →
## Performance): the island's coarse seabed (W01) has no cracks and far
## fewer triangles; a bridge (W06) is drawn in segments, each swapping to
## its far version past the near distance; a message bubble (C02) only
## redraws when its text changes and hides far away; islands, agents and
## bridges past the fog aren't drawn, following the fog (the layout demo's
## view from above turns it off), subagents that come later included.
## Headless Godot draws nothing, so what's checked is how each is set up;
## the drawing itself was measured in a window (NOTES → Performance).
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/world/performance_test.gd

const ErrorWatch := preload("res://tests/error_watch.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_run()


func _run() -> void:
	_seabed()
	await process_frame # the tree is going
	_bridge()
	await _bubble()
	await _draw_distance()
	if not _failed and _errors.ok():
		print("PASS performance_test")
		quit(0)


func _seabed() -> void:
	for seed in [1, 7, 42, 1234]:
		var g := IslandGenerator.new(seed)
		var faces: PackedVector3Array = g.build()["faces"]
		var tris := faces.size() / 3
		# The grid's half-width, as build() works it out, and its cells.
		var cells := int(ceil(2.0 * g.radius * 1.45 * g.skirt_end / g.cell / IslandGenerator.COARSE)) * IslandGenerator.COARSE
		var extent := cells * g.cell / 2.0
		# The 2 m grid everywhere would be 2 triangles a cell.
		var fine := cells * cells * 2
		_check(tris < fine / 2, "seed %d: the drop-off is coarse (%d triangles, %d all fine)" % [seed, tris, fine])
		var buckets := _buckets(faces)
		# No gaps or overlaps: every point is under exactly one triangle.
		var bad := 0
		var x := -extent + 0.37
		while x < extent:
			var z := -extent + 0.61
			while z < extent:
				if _covering(faces, buckets, Vector2(x, z)).size() != 1:
					bad += 1
				z += 1.7
			x += 1.3
		_check(bad == 0, "seed %d: every point of the grid is under one triangle (%d not)" % [seed, bad])
		# No cracks: every corner lying on a coarse triangle's edge (a fine
		# cell beside a coarse block) is at that triangle's height there.
		var on_edges := 0
		var cracks := 0
		for v in faces:
			for t in _covering(faces, buckets, Vector2(v.x, v.z), 1e-4):
				if _longest(faces, t) > 5.0:
					on_edges += 1
					if absf(_height_on(faces, t, Vector2(v.x, v.z)) - v.y) > 1e-3:
						cracks += 1
		_check(on_edges > 0 and cracks == 0, "seed %d: no cracks between coarse and fine (%d of %d)" % [seed, cracks, on_edges])
		# The land keeps its 2 m detail.
		var coarse_on_land := 0
		for t in tris:
			var top := maxf(faces[t * 3].y, maxf(faces[t * 3 + 1].y, faces[t * 3 + 2].y))
			if top >= g.coarse_below and _longest(faces, t) > 5.0:
				coarse_on_land += 1
		_check(coarse_on_land == 0, "seed %d: only the drop-off is coarse" % seed)


func _bridge() -> void:
	var bridge := Bridge.new(Vector3(0, 0.5, 0), Vector3(0, 0.5, -100.0))
	root.add_child(bridge)
	var bounds := bridge.segment_bounds()
	var short := true
	for k in bounds.size() - 1:
		short = short and bounds[k + 1] - bounds[k] <= Bridge.SEGMENT + 0.001
	_check(bounds.size() - 1 == 5 and short and is_equal_approx(bounds[0], -Bridge.OVERRUN) and is_equal_approx(bounds[-1], 100.0 + Bridge.OVERRUN), "bridge: a 100 m bridge in 5 segments of at most %d m" % Bridge.SEGMENT)
	var near_tris := 0
	var far_tris := 0
	var swaps := true
	for k in bounds.size() - 1:
		var near: MeshInstance3D = bridge.get_node("Segment%d/Near" % k)
		var far: MeshInstance3D = bridge.get_node("Segment%d/Far" % k)
		swaps = swaps and near.visibility_range_end == Bridge.NEAR_DISTANCE and far.visibility_range_begin == Bridge.NEAR_DISTANCE \
			and near.visibility_range_end_margin == far.visibility_range_begin_margin and near.visibility_range_begin == 0.0
		near_tris += near.mesh.surface_get_array_len(0) / 3
		far_tris += far.mesh.surface_get_array_len(0) / 3
		# The far version stands where the near one does.
		var n := near.mesh.get_aabb()
		var f := far.mesh.get_aabb()
		swaps = swaps and absf(n.get_center().z - f.get_center().z) < 2.0 and absf(n.size.x - f.size.x) < 0.3
	_check(swaps, "each segment shows its near version up to %d m and its far one past it, in the same place" % Bridge.NEAR_DISTANCE)
	_check(far_tris * 3 < near_tris, "the far version is much simpler (%d triangles, near %d)" % [far_tris, near_tris])
	bridge.free()


func _bubble() -> void:
	var bubble: MessageBubble = load("res://chat/message_bubble.tscn").instantiate()
	var anchor := Node3D.new()
	root.add_child(anchor)
	anchor.add_child(bubble)
	var viewport: SubViewport = bubble.get_node("Viewport")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "bubble: hidden, its viewport doesn't draw")
	bubble.show_text("Hello **there**.")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "a new text draws it once")
	await process_frame
	await process_frame
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	bubble.show_text("Hello **there**.")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the same text again doesn't redraw it")
	_check(viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS and bubble.shown_text() == "Hello there.", "and not every frame after (%s)" % bubble.shown_text())
	bubble.show_text("")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not bubble.visible, "no text: hidden, not drawing")
	_check(bubble.visibility_range_end > 0.0 and bubble.visibility_range_end <= 70.0, "it isn't drawn past %d m" % bubble.visibility_range_end)
	anchor.free()


func _draw_distance() -> void:
	var demo: Node3D = load("res://tests/world/layout_demo.tscn").instantiate()
	root.add_child(demo)
	await _settle()
	var world: Node3D = demo.world
	var islands: SessionIslands = world.get_node("SessionIslands")
	# Made off the main thread, then risen (C14).
	var deadline := Time.get_ticks_msec() + 30000
	while not islands.all_up() and Time.get_ticks_msec() < deadline:
		await process_frame
	var fog: float = (world.get_node("WorldEnvironment") as WorldEnvironment).environment.fog_depth_end
	_check(fog > 0.0 and islands.draw_distance == fog, "draw distance: the fog's end (%d m)" % fog)
	_check(_limited(islands, fog), "islands, orchestrators, markers and far bridges end at the fog plus their size")
	# Its ground comes after the orchestrator (made off the main thread, C14).
	var island_mesh: MeshInstance3D = islands.island("d01").get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D)[0]
	_check(island_mesh.visibility_range_end > fog + 90.0, "an island counts its seabed's reach (%.0f m)" % island_mesh.visibility_range_end)
	var kept := _own_ranges(islands)
	_check(kept, "bridges' near versions and bubbles keep their own; beacons have none")
	# A subagent spawned later gets it too.
	world.store.apply({"type": "agent.spawned", "session": "d01", "seq": 2, "agent": {"agent": "s1", "role": "subagent", "parent": "main", "name": "Explore", "task": "t", "state": "working", "reason": null}})
	await _settle()
	var sub: Subagent = islands.agents("d01").subagent("s1")
	var sub_meshes := sub.find_children("*", "GeometryInstance3D", true, false)
	_check(not sub_meshes.is_empty() and sub_meshes.all(func(g: GeometryInstance3D) -> bool: return g.has_meta(DrawDistance.UNLIMITED) or g.visibility_range_end > fog), "a subagent spawned later is limited too")
	# The demo's view from above turns the fog off: no limit.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	demo._unhandled_input(key)
	await _settle()
	_check(islands.draw_distance == 0.0 and _limited(islands, 0.0), "fog off (the demo's view from above): everything drawn however far")
	_check(_own_ranges(islands), "and the near versions and bubbles keep theirs")
	demo._unhandled_input(key)
	await _settle()
	_check(islands.draw_distance == fog and _limited(islands, fog), "fog back on: limited again")
	demo.queue_free()
	await _settle()


# Whether every geometry under the islands that has no range of its own
# ends at [param distance] plus its size (0: no limit).
func _limited(islands: SessionIslands, distance: float) -> bool:
	var count := 0
	for g: GeometryInstance3D in islands.find_children("*", "GeometryInstance3D", true, false):
		if g.has_meta(DrawDistance.UNLIMITED) or g is MessageBubble or g.name == "Near":
			continue
		count += 1
		var want := distance + DrawDistance.radius(g) if distance > 0.0 else 0.0
		if not is_equal_approx(g.visibility_range_end, want):
			printerr("  not limited: ", g.get_path(), " ", g.visibility_range_end, " want ", want)
			return false
	return count > 64 * 3


func _own_ranges(islands: SessionIslands) -> bool:
	var near := 0
	var bubbles := 0
	var beacons := 0
	for g: GeometryInstance3D in islands.find_children("*", "GeometryInstance3D", true, false):
		if g.name == "Near":
			near += 1
			if g.visibility_range_end != Bridge.NEAR_DISTANCE:
				return false
		elif g is MessageBubble:
			bubbles += 1
			if g.visibility_range_end <= 0.0 or g.visibility_range_end > 70.0:
				return false
		elif g.has_meta(DrawDistance.UNLIMITED):
			beacons += 1
			if g.visibility_range_end != 0.0:
				return false
	return near > 0 and bubbles == 64 and beacons >= 64


# Triangle indices by 4 m square, for finding what's under a point.
func _buckets(faces: PackedVector3Array) -> Dictionary:
	var out := {}
	for t in faces.size() / 3:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for k in 3:
			var p := Vector2(faces[t * 3 + k].x, faces[t * 3 + k].z)
			lo = lo.min(p)
			hi = hi.max(p)
		for bx in range(floori(lo.x / 4.0), floori(hi.x / 4.0) + 1):
			for bz in range(floori(lo.y / 4.0), floori(hi.y / 4.0) + 1):
				var key := Vector2i(bx, bz)
				if not out.has(key):
					out[key] = []
				out[key].append(t)
	return out


# The triangles whose top view contains [param p], allowing [param slack]
# outside their edges (barycentric).
func _covering(faces: PackedVector3Array, buckets: Dictionary, p: Vector2, slack := 0.0) -> Array:
	var out := []
	for t in buckets.get(Vector2i(floori(p.x / 4.0), floori(p.y / 4.0)), []):
		var w := _barycentric(faces, t, p)
		if w.x >= -slack and w.y >= -slack and w.z >= -slack:
			out.append(t)
	return out


# A triangle's longest side, seen from above: about 2-3 m for a fine cell,
# 8-11 m for a coarse block.
func _longest(faces: PackedVector3Array, t: int) -> float:
	var a := Vector2(faces[t * 3].x, faces[t * 3].z)
	var b := Vector2(faces[t * 3 + 1].x, faces[t * 3 + 1].z)
	var c := Vector2(faces[t * 3 + 2].x, faces[t * 3 + 2].z)
	return maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))


func _height_on(faces: PackedVector3Array, t: int, p: Vector2) -> float:
	var w := _barycentric(faces, t, p)
	return w.x * faces[t * 3].y + w.y * faces[t * 3 + 1].y + w.z * faces[t * 3 + 2].y


func _barycentric(faces: PackedVector3Array, t: int, p: Vector2) -> Vector3:
	var a := Vector2(faces[t * 3].x, faces[t * 3].z)
	var b := Vector2(faces[t * 3 + 1].x, faces[t * 3 + 1].z)
	var c := Vector2(faces[t * 3 + 2].x, faces[t * 3 + 2].z)
	var d := (b - a).cross(c - a)
	var u := (b - p).cross(c - p) / d
	var v := (c - p).cross(a - p) / d
	return Vector3(u, v, 1.0 - u - v)


# A whole main-loop iteration or two, deferred calls included.
func _settle() -> void:
	for i in 3:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
