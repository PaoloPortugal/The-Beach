extends SceneTree
## Headless test for the M1 world: the island generator (W01) and jump
## assist (W03), then the world scene with
## real physics: the player lands on the spawn platform, walks, jumps, and
## swims in the sea over the seabed (W08), back by the sessions menu's
## "Platform" or the big map; the sessions menu; islands for
## sessions (applied to the store by hand) rising and sinking (W04), each
## orchestrator's bubble, and
## walking up to chat in the chat panel (A01, C01, C02), both rendering
## Markdown (C03); subagents'
## placement, coming and going, and state markers (A02, A03, A04); the
## attention cue (A05); the day and night and the weather (W09); the
## debug commands (C09).
##
##   godot --headless --path . --script res://tests/world/world_test.gd
##   ... -- --sidecar-dev-fake    also starts a session from the menu and
##                                chats with the fake provider, which
##                                spawns subagents

const ErrorWatch := preload("res://tests/error_watch.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_run()


func _run() -> void:
	_island()
	await _biomes()
	_jump_assist()
	_placement()
	await _scene()
	if not _failed and _errors.ok():
		print("PASS world_test")
		quit(0)


func _island() -> void:
	var a := IslandGenerator.new(42)
	var b := IslandGenerator.new(42)
	var c := IslandGenerator.new(7)
	var same := true
	var differs := false
	for p in [Vector2(10, 3), Vector2(-15, 12), Vector2(4, -22), Vector2(25, 25)]:
		same = same and is_equal_approx(a.height_at(p.x, p.y), b.height_at(p.x, p.y))
		differs = differs or not is_equal_approx(a.height_at(p.x, p.y), c.height_at(p.x, p.y))
	_check(same, "same seed, same island")
	_check(differs, "different seed, different island")

	for seed in [1, 7, 42, 1234, 99999]:
		var g := IslandGenerator.new(seed)
		var flat := true
		for r in [0.0, 3.0, 6.0]:
			for k in 8:
				var ang := k * TAU / 8.0
				flat = flat and is_equal_approx(g.height_at(cos(ang) * r, sin(ang) * r), g.plateau_height)
		_check(flat, "seed %d: the middle is flat and above water" % seed)
		# Every direction reaches the sea: a shallow shelf, then a drop-off
		# below the deepest sea floor (W08).
		var shore := true
		for k in 16:
			var ang := k * TAU / 16.0
			var r := g.shore_radius(cos(ang), sin(ang))
			var on_shelf := r * (g.shelf_start + g.shelf_end) / 2.0
			var past := r * (g.skirt_end + 0.05)
			shore = shore and is_equal_approx(g.height_at(cos(ang) * on_shelf, sin(ang) * on_shelf), g.sea_floor)
			shore = shore and is_equal_approx(g.height_at(cos(ang) * past, sin(ang) * past), g.skirt_floor)
		_check(shore, "seed %d: surrounded by sea" % seed)
		_check(g.skirt_floor < Seabed.DEEPEST, "seed %d: the drop-off reaches below the sea floor" % seed)

	var built := a.build()
	var faces: PackedVector3Array = built["faces"]
	_check(faces.size() > 0 and faces.size() % 3 == 0, "mesh has triangles")
	var up := true
	for i in range(0, faces.size(), 3):
		up = up and (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).y > 0.0
	_check(up, "every triangle faces up (clockwise from above)")
	# Under the water its faces take the sea floor's colours, so its shelf
	# and drop-off match the floor where they meet (W08).
	var arrays: Array = (built["mesh"] as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var under := 0
	var matched := 0
	for i in range(0, verts.size(), 3):
		var h := (verts[i].y + verts[i + 1].y + verts[i + 2].y) / 3.0
		if h < -0.5:
			under += 1
			# The mesh keeps 8 bits a channel.
			if _close(colours[i], Seabed.colour(h), 1.0 / 255.0):
				matched += 1
	_check(under > 0 and matched == under, "under the water the island has the sea floor's colours (%d of %d)" % [matched, under])


# W10: every biome's shape, its props, and that you can walk up it.
func _biomes() -> void:
	var beach := IslandGenerator.new(42)
	var also := IslandGenerator.new(42, Biome.Kind.BEACH)
	_check(beach.biome == Biome.Kind.BEACH and is_equal_approx(beach.height_at(12, 5), also.height_at(12, 5)), "biomes: the beach is the default, W01's shape")
	# The beach's props (user's, 2026-10-09): palms and plants inland, sand
	# castles, starfish and shells by the water.
	var tropical := {}
	var by_water := true
	for seed in [1, 7, 42, 1234, 99999]:
		for s in IslandGenerator.new(seed).prop_spots():
			var kind: int = s["prop"]
			tropical[kind] = tropical.get(kind, 0) + 1
			var h: float = s["position"].y + 0.02
			if kind in [IslandProps.Prop.SAND_CASTLE, IslandProps.Prop.STARFISH, IslandProps.Prop.SHELL]:
				by_water = by_water and h > 0.05 and h < 0.6
	var all_kinds := [IslandProps.Prop.PALM, IslandProps.Prop.TROPICAL_PLANT, IslandProps.Prop.SAND_CASTLE, IslandProps.Prop.STARFISH, IslandProps.Prop.SHELL].all(func(k: int) -> bool: return tropical.get(k, 0) > 0)
	_check(all_kinds and tropical.size() == 5 and by_water, "biomes: the beach has palms, plants, sand castles, starfish and shells, the small ones by the water (%s)" % str(tropical))
	var rolled := {}
	for k in 200:
		rolled[Biome.resolve(Biome.RANDOM)] = true
	_check(rolled.size() == Biome.Kind.size() and Biome.resolve(Biome.Kind.SNOWY) == Biome.Kind.SNOWY, "biomes: Random rolls every kind, a chosen one stays")
	for kind: int in [Biome.Kind.FOREST, Biome.Kind.MOUNTAIN, Biome.Kind.SNOWY, Biome.Kind.DESERT]:
		var name: String = Biome.NAMES[kind]
		var flat := true
		var sea := true
		var shoulder := true
		var props := true
		var some_props := 0
		var walk := true
		for seed in [1, 7, 42, 1234, 99999]:
			var g := IslandGenerator.new(seed, kind)
			for r in [0.0, 3.0, 6.0]:
				for k in 8:
					var ang := k * TAU / 8.0
					flat = flat and is_equal_approx(g.height_at(cos(ang) * r, sin(ang) * r), g.plateau_height)
			var landings: Array[Vector2] = []
			for k in 16:
				var ang := k * TAU / 16.0
				var dir := Vector2(cos(ang), sin(ang))
				var r := g.shore_radius(dir.x, dir.y)
				var on_shelf := r * (g.shelf_start + g.shelf_end) / 2.0
				sea = sea and is_equal_approx(g.height_at(dir.x * on_shelf, dir.y * on_shelf), g.sea_floor)
				# A bridge lands where the ground first reaches the edge
				# height, on a shoulder about that high.
				var at := r * 1.2
				while at > 0.0 and g.height_at(dir.x * at, dir.y * at) < g.edge_height():
					at -= 0.25
				var inward := g.height_at(dir.x * (at - 1.0), dir.y * (at - 1.0))
				shoulder = shoulder and at > g.plateau_radius and absf(inward - g.edge_height()) < 0.4
				landings.append(dir * at)
			for s in g.prop_spots():
				some_props += 1
				var p: Vector3 = s["position"]
				props = props and Vector2(p.x, p.z).length() >= g.plateau_radius + IslandGenerator.PROP_CLEAR and p.y > IslandGenerator.BEACH_TOP
			# A mountain's beach is under a cliff: its zipline's top stands
			# for it (user's, 2026-10-09).
			var ends := g.zipline_ends()
			if kind == Biome.Kind.MOUNTAIN:
				landings.append(Vector2(ends[1].x, ends[1].z))
			walk = walk and _walkable(g, landings, kind != Biome.Kind.MOUNTAIN)
		_check(flat, "biomes: %s: the middle is flat" % name)
		_check(sea, "biomes: %s: surrounded by sea" % name)
		_check(shoulder, "biomes: %s: bridges land on a shoulder at its edge height (%.1f m)" % [name, Biome.profile(kind)["edge"]])
		_check(props and some_props > 5, "biomes: %s: props, off the beach and the middle (%d)" % [name, some_props])
		_check(walk, "biomes: %s: you can walk up to the middle from %s every landing" % [name, "the zipline's top and" if kind == Biome.Kind.MOUNTAIN else "the beach and"])
	# The mountain (user's, 2026-10-09): spires at least three times as
	# high as the first ones (15 m), some taller, a high meadow, and a
	# zipline whose rider clears the cliff.
	var tops: Array[float] = []
	var meadow := true
	var cable := true
	var only_mountain := true
	for seed in [1, 7, 42, 1234, 99999]:
		var g := IslandGenerator.new(seed, Biome.Kind.MOUNTAIN)
		g.build()
		tops.append(g.top)
		meadow = meadow and g.plateau_height >= 18.0 and g.edge_height() >= 15.0
		var ends := g.zipline_ends()
		var a := ends[0] + Vector3(0, Zipline.POST_HEIGHT, 0)
		var b := ends[1] + Vector3(0, Zipline.POST_HEIGHT, 0)
		cable = cable and ends[0].y < 1.0 and absf(ends[1].y - g.edge_height()) < 0.5
		for i in 51:
			var p := a.lerp(b, i / 50.0)
			cable = cable and p.y - Zipline.HANG + 1.6 - g.height_at(p.x, p.z) > 0.5
		only_mountain = only_mountain and IslandGenerator.new(seed, Biome.Kind.FOREST).zipline_ends().is_empty()
	_check(tops.min() > 50.0 and tops.max() > 60.0, "biomes: mountains reach %.0f-%.0f m, some taller" % [tops.min(), tops.max()])
	_check(meadow, "biomes: a mountain's middle is a meadow high up, its edge nearly as high")
	_check(cable and only_mountain, "biomes: a mountain's zipline runs from its beach to its shoulder, your head clear of the cliff; only mountains have one")

	# Props: their meshes face outward, they clear where asked, and the
	# solid ones have collision.
	for kind: int in IslandProps.Prop.values():
		var arrays := IslandProps.mesh(kind).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var out := 0
		for i in range(0, verts.size(), 3):
			var mid := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
			if normals[i].dot(Vector3(mid.x, 0.0, mid.z)) >= -0.01 or normals[i].y > 0.3:
				out += 1
		# A leaning palm's trunk and flat leaves face every way, so for
		# those the mesh's signed volume says it's wound outward: an
		# inside-out part would take away from it.
		if kind in [IslandProps.Prop.PALM, IslandProps.Prop.TROPICAL_PLANT, IslandProps.Prop.STARFISH]:
			var volume := 0.0
			for i in range(0, verts.size(), 3):
				volume += verts[i].dot(verts[i + 2].cross(verts[i + 1])) / 6.0
			_check(volume > 0.0, "props: %s is wound outward (%.3f m³)" % [IslandProps.Prop.keys()[kind], volume])
			continue
		# (A cactus's arms point sideways, so some faces turn in.)
		_check(verts.size() > 0 and out * 10 >= verts.size() / 3 * 8, "props: %s faces outward (%d of %d)" % [IslandProps.Prop.keys()[kind], out, verts.size() / 3])
	var props := IslandProps.new()
	root.add_child(props)
	var spots: Array[Dictionary] = []
	spots.append({"prop": IslandProps.Prop.TREE, "position": Vector3(10, 1, 0), "yaw": 0.0, "scale": 1.0})
	spots.append({"prop": IslandProps.Prop.BUSH, "position": Vector3(-10, 1, 0), "yaw": 0.0, "scale": 1.0})
	spots.append({"prop": IslandProps.Prop.ROCK, "position": Vector3(0, 1, 10), "yaw": 0.0, "scale": 1.0})
	props.setup(spots)
	var shapes := props.find_children("*", "CollisionShape3D", false, false).size()
	_check(shapes == 2 and props.is_near(Vector2(10.5, 0), 1.0) and not props.is_near(Vector2(5, 5), 1.0), "props: trees and rocks are solid, bushes aren't")
	props.clear_near(Vector3(0, 0, 4), Vector3(0, 0, 14), 2.0)
	_check(props.spots.size() == 2 and not props.is_near(Vector2(0, 10), 1.0), "props: cleared along a bridge's way in")
	props.free()

	# W10: a steep bridge gets level steps; its collision stays a ramp.
	var bridge := Bridge.new(Vector3(0, 0.5, 0), Vector3(0, 6.0, -12.0))
	root.add_child(bridge)
	await process_frame # it builds in _ready
	var level := 0
	for seg in bridge.get_children():
		if not seg.has_node("Near"):
			continue
		var a: Array = ((seg.get_node("Near") as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in range(0, v.size(), 3):
			if n[i].y > 0.999 and v[i].y > 1.5:
				level += 1
	var ramp := true
	for s in [2.0, 6.0, 10.0]:
		ramp = ramp and absf(bridge.deck_y(s) - lerpf(0.5, 6.0, s / 12.0)) < 0.01
	_check(level > 20 and ramp, "bridges: a steep one has level steps (%d tops), on a smooth ramp" % level)
	bridge.free()


# Whether, on a 1 m grid, the middle can be reached from every landing
# and, if [param beach], from the beach, without a step steeper than 40°.
func _walkable(g: IslandGenerator, landings: Array[Vector2], beach := true) -> bool:
	var reach := int(g.radius * 1.5)
	var size := reach * 2 + 1
	var h := PackedFloat32Array()
	h.resize(size * size)
	for i in size:
		for j in size:
			h[i * size + j] = g.height_at(i - reach, j - reach)
	var seen := PackedByteArray()
	seen.resize(size * size)
	var todo: Array[int] = [reach * size + reach]
	seen[todo[0]] = 1
	var limit := tan(deg_to_rad(40.0))
	while not todo.is_empty():
		var at: int = todo.pop_back()
		var i := at / size
		var j := at % size
		for step in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var ni: int = i + step[0]
			var nj: int = j + step[1]
			if ni < 0 or nj < 0 or ni >= size or nj >= size:
				continue
			var next := ni * size + nj
			if seen[next] == 0 and h[next] > 0.0 and absf(h[next] - h[at]) <= limit:
				seen[next] = 1
				todo.append(next)
	var ok := true
	for p in landings:
		ok = ok and seen[(int(round(p.x)) + reach) * size + int(round(p.y)) + reach] == 1
	# The beach: a point just inland of the shore in 16 directions.
	for k in (16 if beach else 0):
		var dir := Vector2.from_angle(k * TAU / 16.0)
		var r := g.shore_radius(dir.x, dir.y) - 1.5
		ok = ok and seen[(int(round(dir.x * r)) + reach) * size + int(round(dir.y * r)) + reach] == 1
	return ok


func _jump_assist() -> void:
	var dt := 1.0 / 60.0
	var j := JumpAssist.new()
	_check(j.step(dt, true, true), "a press on the floor jumps")
	_check(not j.step(dt, true, false), "one press, one jump")

	j = JumpAssist.new()
	j.step(dt, false, true)  # pressed in the air...
	for i in 4:
		j.step(dt, false, false)
	_check(j.step(dt, true, false), "...and it jumps on landing (buffer)")

	j = JumpAssist.new()
	j.step(dt, false, true)
	for i in 20:
		j.step(dt, false, false)
	_check(not j.step(dt, true, false), "a press long before landing is dropped")

	j = JumpAssist.new()
	j.step(dt, true, false)
	for i in 4:
		j.step(dt, false, false)  # walked off an edge
	_check(j.step(dt, false, true), "a press just after leaving the floor jumps (coyote)")
	_check(not j.step(dt, false, true), "no second jump in the air")

	j = JumpAssist.new()
	j.step(dt, true, false)
	for i in 20:
		j.step(dt, false, false)
	_check(not j.step(dt, false, true), "no coyote jump long after leaving the floor")


func _placement() -> void:
	_check(AgentPlacement.slots_in_ring(0) == 20 and AgentPlacement.ring_of(20) == Vector2i(1, 0), "placement: 20 on the first ring, then the next")
	var points: Array[Vector2] = []
	for slot in 80:
		points.append(AgentPlacement.slot_position(slot))
	var closest := INF
	for i in points.size():
		for j in i:
			closest = minf(closest, points[i].distance_to(points[j]))
	_check(closest > 2.0, "placement: slots at least 2 m apart (closest %.2f m)" % closest)
	_check(points.all(func(p: Vector2) -> bool: return p.length() > 9.0), "placement: all outside the chat zone")
	_check(AgentPlacement.slot_position(7) == AgentPlacement.slot_position(7), "placement: a slot is always in the same place")
	var far := AgentPlacement.slot_position(5000)
	_check(far.length() > 100.0 and is_finite(far.x), "placement: no maximum")


func _scene() -> void:
	var world: Node3D = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	await process_frame  # _ready runs once the tree is going
	var player: Player = world.get_node("Player")
	var spawn := player.spawn_point
	_check(spawn.is_equal_approx(Vector3(0, 1.1, 3)), "spawns on the platform")

	await _frames(30)
	_check(player.is_on_floor() and absf(player.global_position.y - 1.0) < 0.2, "lands on the platform")

	var before := player.global_position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	var walked := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	_check(walked > 1.5, "walks (%.2f m in 0.5 s)" % walked)

	await _frames(30)
	var start_y := player.global_position.y
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	await _frames(15)
	_check(player.global_position.y > start_y + 0.8, "jumps")

	await _crouch_slide(player)
	await _sky(world, player)
	await _commands(world, player)
	await _swimming(world, player)
	await _menu(world, player)
	await _sessions(world, player)
	await _agents(world)
	await _biome_island(world, player)
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		await _live(world, player)

	world.queue_free()
	await _frames(1)


# W11: crouching and sliding, on test ground high above the world so the
# slopes are known: a flat floor with a low bar over it, and a slope.
func _crouch_slide(player: Player) -> void:
	var arena := Node3D.new()
	arena.position = Vector3(0, 500, 0)
	root.add_child(arena)
	_test_box(arena, Vector3(0, -0.5, -50), Vector3(20, 1, 120), 0.0) # the floor
	_test_box(arena, Vector3(0, 1.45, 4), Vector3(20, 0.5, 2), 0.0) # a bar 1.2 m up
	var slope := deg_to_rad(20.0)
	# Down towards -z (W) from (40, 0, 0): slide down it, or turned round, up.
	_test_box(arena, Vector3(40, -30 * sin(slope) - 0.5 * cos(slope), -30 * cos(slope) + 0.5 * sin(slope)), Vector3(20, 1, 60), -slope)
	var flat := arena.position + Vector3(0, 0.05, 7)
	var body := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	var head: Node3D = player.get_node("Head")
	var speed := func() -> float: return Vector2(player.velocity.x, player.velocity.z).length()

	player.rotation.y = 0.0 # facing -z
	player.global_position = flat
	player.velocity = Vector3.ZERO
	await _frames(10)
	Input.action_press("crouch")
	await _frames(20)
	_check(player.crouching and not player.sliding and is_equal_approx(body.height, 1.1) and is_equal_approx(head.position.y, 0.95), "W11: Ctrl crouches, 1.1 m with the eyes at 0.95 m (eyes %.2f)" % head.position.y)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(30)
	_check(not player.sliding and absf(speed.call() - player.crouch_speed) < 0.05, "crouch-walks at 2.5 m/s, sprinting or not (%.2f)" % speed.call())
	await _frames(60) # past the start of the bar, under it
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("crouch")
	await _frames(10)
	_check(player.crouching and player.global_position.z < arena.position.z + 5.0, "under something low it stays crouched (z %.2f)" % (player.global_position.z - arena.position.z))
	Input.action_press("move_forward")
	await _until(func() -> bool: return not player.crouching, 3.0)
	Input.action_release("move_forward")
	_check(not player.crouching and is_equal_approx(body.height, 1.8) and player.global_position.z < arena.position.z + 3.0, "and stands up once out from under it")
	await _frames(20)
	_check(is_equal_approx(head.position.y, 1.6), "the eyes back at 1.6 m")

	# A slide on the flat: the burst fades to crouching speed in about 1 s.
	var slide := func(from: Vector3, frames: int) -> void:
		player.global_position = from
		player.velocity = Vector3.ZERO
		await _frames(40) # landed
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await _frames(25)
		Input.action_press("crouch")
		await _frames(1)
		Input.action_release("sprint")
		await _frames(frames)
	await slide.call(arena.position + Vector3(0, 0.05, -10), 0)
	var start_z := player.global_position.z
	_check(player.sliding and speed.call() > 10.5, "W11: crouching at a sprint slides, with a burst (%.2f m/s)" % speed.call())
	var t := 0
	while player.sliding and t < 180:
		await _frames(1)
		t += 1
	var slid := start_z - player.global_position.z
	_check(t > 45 and t < 90 and slid > 5.0, "fading to crouching speed in about 1 s on the flat (%.2f s, %.1f m)" % [t / 60.0, slid])
	_check(player.crouching and speed.call() <= player.crouch_speed + 0.05, "then crouch-walks")
	Input.action_release("move_forward")
	Input.action_release("crouch")

	# Downhill it keeps its speed; uphill it stops sooner.
	await slide.call(arena.position + Vector3(40, 0.05, -3), 30)
	_check(player.sliding and speed.call() > 10.5, "downhill a slide keeps its speed (%.2f m/s after 0.5 s)" % speed.call())
	Input.action_release("move_forward")
	Input.action_release("crouch")
	player.rotation.y = PI # facing +z, up the slope
	var low := arena.position + Vector3(40, 0.1 - 40 * sin(slope), -40 * cos(slope))
	await slide.call(low, 0)
	t = 0
	while player.sliding and t < 180:
		await _frames(1)
		t += 1
	_check(t > 0 and t < 40, "uphill it stops sooner (%.2f s)" % (t / 60.0))
	Input.action_release("move_forward")
	Input.action_release("crouch")

	# A slide jump keeps the slide's speed; landing still crouched slides on
	# without a new burst.
	player.rotation.y = 0.0
	await slide.call(arena.position + Vector3(0, 0.05, -10), 20)
	var before := speed.call() as float
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	await _frames(30)
	_check(not player.is_on_floor() and not player.sliding and speed.call() > before - 0.3, "W11: a slide jump keeps the slide's speed (%.2f, was %.2f)" % [speed.call(), before])
	await _until(func() -> bool: return player.is_on_floor(), 3.0)
	await _frames(2)
	_check(player.sliding and speed.call() < before + 0.2 and speed.call() < player.slide_speed - 1.0, "landing crouched slides on, with no new burst (%.2f m/s)" % speed.call())
	Input.action_release("move_forward")
	Input.action_release("crouch")
	await _frames(40)
	_check(not player.crouching and not player.sliding, "letting go of Ctrl stands up")

	player.respawn()
	arena.queue_free()
	await _frames(30)


func _test_box(parent: Node3D, at: Vector3, size: Vector3, tilt: float) -> void:
	var box := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	box.add_child(shape)
	box.position = at
	box.rotation.x = tilt
	parent.add_child(box)


# W09: the day and night cycle, the weather and what they bring.
func _sky(world: Node3D, player: Player) -> void:
	var day: DayNight = world.day_night
	var weather: Weather = world.weather
	var sun: DirectionalLight3D = world.get_node("Sun")
	var env: Environment = (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(DayNight.CYCLE == 28.0 * 60.0 and day.cycle == DayNight.CYCLE, "W09: a 28-minute day")
	_check(day.hour() > 8.5 and day.hour() < 10.5 and day.sun_height() > 0.3 and day.darkness == 0.0, "it starts mid-morning, the sun well up (%.1f h)" % day.hour())
	_check(sun.visible and sun.light_energy > 0.5 and (-sun.global_basis.z).y < -0.3, "the sun shines down from the sky")
	var night_samples := 0
	for i in 1000:
		if DayNight.sun_direction((i + 0.5) / 1000.0).y < 0.0:
			night_samples += 1
	_check(night_samples == 500, "half of it is night (%d of 1000)" % night_samples)
	_check(DayNight.sun_direction(0.0).x > 0.99 and DayNight.sun_direction(0.25).z > 0.4 and DayNight.sun_direction(0.5).x < -0.99, "the sun rises in the east, crosses the south and sets in the west")
	var round_trip := true
	for h in [0.0, 5.5, 6.0, 12.0, 17.25, 23.9]:
		day.set_hour(h)
		round_trip = round_trip and absf(day.hour() - h) < 0.001
	_check(round_trip, "set_hour and hour agree")
	day.set_hour(10.0)
	var t := day.time
	day._process(day.cycle / 4.0)
	_check(absf(day.hour() - 16.0) < 0.01, "a quarter of the cycle is six hours (%.2f)" % day.hour())
	day.cycle = 60.0 # --day-minutes 1
	day._process(15.0)
	_check(absf(day.time - fposmod(t + 0.5, 1.0)) < 0.001, "--day-minutes shortens the day")
	day.cycle = DayNight.CYCLE
	# Performance: each change to the sky redraws its reflection map, so a
	# change too small to see isn't sent.
	day.set_hour(10.0)
	var sky: ShaderMaterial = env.sky.sky_material
	var sent: Vector3 = sky.get_shader_parameter("sun_direction")
	day._process(0.5)
	_check(sky.get_shader_parameter("sun_direction") == sent, "the sky isn't redrawn for a change too small to see")
	day._process(5.0)
	_check(sky.get_shader_parameter("sun_direction") != sent, "but is once it shows")

	day.set_hour(0.0)
	var moon := -DayNight.sun_direction(day.time)
	_check(day.darkness == 1.0 and day.sun_height() < -0.5 and DayNight.current_darkness == 1.0, "at midnight it's night, the sun far below")
	_check(sun.visible and (-sun.global_basis.z).dot(-moon) > 0.99 and sun.light_energy > 0.05 and sun.light_energy < DayNight.SUN_ENERGY / 2.0, "the moon, opposite the sun, lights the night, dimmer")
	_check(env.ambient_light_energy >= 0.3, "and the night stays readable (ambient %.2f)" % env.ambient_light_energy)

	# Night lights: an island's torches and the desk lamp.
	var island := Island.new()
	island.island_seed = 7
	island.position = Vector3(0, -500, 0) # out of the way
	world.add_child(island)
	var orchestrator: Orchestrator = load("res://agents/orchestrator/orchestrator.tscn").instantiate()
	island.add_child(orchestrator)
	var lamp: NightLight = orchestrator.get_node("Lamp")
	var torches := island.torches()
	var on_beach := torches.all(func(n: NightLight) -> bool: return absf(n.position.y - 0.5) < 0.5 and Vector2(n.position.x, n.position.z).length() > 5.0)
	_check(torches.size() == Island.TORCHES and on_beach, "an island has %d torches along its beach" % Island.TORCHES)
	var lights: Array[OmniLight3D] = []
	for n: NightLight in torches + [lamp]:
		lights.append_array(n.find_children("*", "OmniLight3D", true, false))
	_check(lights.size() == torches.size() + 1 and lights.all(func(l: OmniLight3D) -> bool: return not l.shadow_enabled and l.distance_fade_enabled and l.distance_fade_begin + l.distance_fade_length <= 100.0), "night lights cast no shadows and fade out within 100 m")
	_check(torches.all(func(n: NightLight) -> bool: return n.is_lit()) and lamp.is_lit(), "made at night, the torches and the desk lamp are lit")
	day.set_hour(12.0)
	await _settle()
	_check(torches.all(func(n: NightLight) -> bool: return not n.is_lit()) and not lamp.is_lit(), "and out by day")
	day.set_hour(22.0)
	await _settle()
	_check(torches.all(func(n: NightLight) -> bool: return n.is_lit()) and lamp.is_lit(), "lit again at night")
	island.queue_free()

	# The weather, stepped by hand.
	_check(Weather.kind_named("storm") == Weather.Kind.STORM and Weather.kind_named("fog") == -1, "weather kinds by name (--weather)")
	var picks := {}
	for i in 10000:
		var k := Weather.pick_next((i + 0.5) / 10000.0)
		picks[k] = picks.get(k, 0) + 1
	var weighted := true
	for k in Weather.WEIGHTS:
		weighted = weighted and absf(picks.get(k, 0) / 10000.0 - Weather.WEIGHTS[k]) < 0.002
	_check(weighted and Weather.WEIGHTS[Weather.Kind.CLEAR] > 0.4, "the next kind follows the weights, clear the most often")
	var w := Weather.new()
	w.rng.seed = 3
	w.set_kind(Weather.Kind.CLEAR, true)
	w.changes = false
	w.set_kind(Weather.Kind.STORM, false)
	w.step(30.0)
	_check(w.cover > 0.1 and w.cover < 0.65 and w.rain > 0.0 and w.rain <= 0.51, "a change eases in over about a minute (cover %.2f after 30 s)" % w.cover)
	var bounded := true
	var strikes: Array[float] = []
	var clock := [0.0]
	w.lightning.connect(func(_direction: Vector2) -> void: strikes.append(clock[0]))
	var peak := 0.0
	while clock[0] < 600.0:
		w.step(0.05)
		clock[0] += 0.05
		peak = maxf(peak, w.flash)
		for v in [w.cover, w.rain, w.wind, w.storm]:
			bounded = bounded and v >= 0.0 and v <= 1.0
	_check(bounded and w.cover == 1.0 and w.storm == 1.0, "levels stay between 0 and 1 and reach the storm's")
	var gaps_ok := strikes.size() > 20
	for i in range(1, strikes.size()):
		var gap := strikes[i] - strikes[i - 1]
		gaps_ok = gaps_ok and gap >= Weather.MIN_GAP - 0.06 and gap <= Weather.MAX_GAP + 0.06
	_check(gaps_ok, "a storm brings lightning, 10-20 s apart (%d strikes in 10 min)" % strikes.size())
	_check(peak > 0.3 and peak <= Weather.FLASH_PEAK, "a soft flash, never a white-out (peak %.2f)" % peak)
	_check(w.kind == Weather.Kind.STORM, "with changes off (--weather) the kind stays")
	w.lightning_enabled = false
	var before := strikes.size()
	for i in 1200:
		w.step(0.05)
	_check(strikes.size() == before and w.flash == 0.0, "lightning off: none")
	w.lightning_enabled = true
	w.set_kind(Weather.Kind.CLEAR, true)
	for i in 1200:
		w.step(0.05)
	_check(strikes.size() == before, "and none without a storm")
	w.free()

	# In the world: clouds, rain and the bolt.
	var clouds: Clouds = world.clouds
	var rain: Rain = world.rain
	var camera: Camera3D = player.get_node("Head/Camera3D")
	weather.changes = false
	weather.set_kind(Weather.Kind.CLEAR, true)
	await _settle()
	var clear_clouds := clouds.shown_count()
	weather.set_kind(Weather.Kind.STORM, true)
	await _settle()
	_check(clear_clouds <= ceili(Weather.TARGETS[Weather.Kind.CLEAR][0] * Clouds.COUNT) and clouds.shown_count() == Clouds.COUNT, "clouds follow the cover (%d clear, %d in a storm)" % [clear_clouds, clouds.shown_count()])
	_check(rain.emitting and rain.amount_ratio == 1.0, "a storm rains")
	weather.lightning_enabled = false # the bolt by hand
	var bolt: LightningBolt = world.lightning_bolt
	bolt.strike(Vector2(1, 0))
	var at := bolt.get_aabb().get_center()
	var away := Vector2(at.x, at.z).distance_to(Vector2(camera.global_position.x, camera.global_position.z))
	_check(bolt.visible and away > LightningBolt.MIN_DISTANCE - 10.0, "a bolt strikes far away (%.0f m)" % away)
	await _until(func() -> bool: return not bolt.visible, 2.0)
	_check(not bolt.visible, "and is gone in a moment")
	player.global_position = Vector3(20, -6, 0)
	player.velocity = Vector3.ZERO
	await _until(func() -> bool: return world.underwater.active and not rain.emitting, 2.0)
	_check(world.underwater.active and not rain.emitting, "no rain under the water")
	var no_shadows := clouds.get_children().all(func(c: GeometryInstance3D) -> bool: return c.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check(no_shadows and rain.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and bolt.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "clouds, rain and the bolt cast no shadows")
	weather.lightning_enabled = true
	weather.set_kind(Weather.Kind.CLEAR, true)
	day.set_hour(10.0)
	player.global_position = player.spawn_point
	player.velocity = Vector3.ZERO
	await _frames(30)


# C09: the debug commands and their console.
func _commands(world: Node3D, player: Player) -> void:
	var day: DayNight = world.day_night
	var weather: Weather = world.weather
	var was_time := day.time
	var was_kind := weather.kind
	var was_changes := weather.changes
	_check(DebugCommands.parse_time("7m") == 420.0 and DebugCommands.parse_time("30s") == 30.0 and DebugCommands.parse_time("10m22s") == 622.0 and DebugCommands.parse_time("noon") == 840.0, "C09: times as 7m, 30s, 10m22s or a name")
	_check(DebugCommands.parse_time("x") < 0.0 and DebugCommands.parse_time("") < 0.0 and DebugCommands.parse_time("7") < 0.0, "C09: anything else isn't a time")
	var c := DebugCommands.new(day, weather)
	var hours := {"0s": 0.0, "7m": 6.0, "noon": 12.0, "21m": 18.0, "midnight": 0.0}
	var ok := true
	for t in hours:
		c.run("/time set " + t)
		ok = ok and is_equal_approx(fposmod(day.hour() + 0.001, 24.0), hours[t] + 0.001)
	_check(ok, "C09: /time set counts from midnight: 7m sunrise, 14m noon, 21m sunset")
	c.run("/time set noon")
	var reply := c.run("/time add 7m")
	_check(is_equal_approx(day.hour(), 18.0) and reply.contains("21m 00s"), "C09: /time add moves on (%s)" % reply)
	_check(c.run("/time query").begins_with("It's 21m 00s") and c.run("/time set day").contains("10m 22s"), "C09: /time query, and day is the launch's mid-morning")
	_check(c.run("/time set later").begins_with("Not a time"), "C09: a bad time is refused")
	reply = c.run("/time speed 2")
	var fast := day.cycle
	var refused := c.run("/time speed 0").begins_with("Not a speed") and c.run("/time speed 2m").begins_with("Not a speed")
	c.run("/time speed 1")
	_check(fast == DayNight.CYCLE / 2.0 and reply == "Speed 2: a day now takes 14m." and refused and day.cycle == DayNight.CYCLE, "C09: /time speed 2 makes a day 14m, 1 puts it back (%s)" % reply)
	var changing := weather.changes
	weather.changes = true
	reply = c.run("/weather storm")
	_check(weather.kind == Weather.Kind.STORM and weather.storm == 1.0 and weather.changes and reply == "Weather set to storm.", "C09: /weather sets it now, and it still changes by itself")
	_check(c.run("/weather query") == "The weather is storm." and c.run("/weather fog").begins_with("Unknown weather") and c.run("/weather auto").begins_with("Unknown weather"), "C09: /weather query, and an unknown kind is refused")
	weather.changes = changing
	c.run("/weather clear")
	c.run("/lightning")
	await _frames(3)
	_check(weather.flash > 0.0 and world.lightning_bolt.visible, "C09: /lightning strikes, even in clear weather")
	_check(c.run("/fly").begins_with("Unknown command") and c.run("/help").begins_with("Commands:"), "C09: unknown commands, and /help")

	var console: DebugConsole = world.debug_console
	_check(console != null, "C09: the console is there in a debug build")
	_press("debug_console")
	await _until(func() -> bool: return console.is_open() and not player.controls_enabled, 2.0)
	_check(console.is_open() and not player.controls_enabled, "C09: T opens the console and stops the player")
	_press("ui_cancel")
	await _until(func() -> bool: return not console.is_open() and player.controls_enabled, 2.0)
	_check(not console.is_open() and player.controls_enabled, "C09: Esc closes it")
	console.open()
	console.submit("/time set noon")
	_check(not console.is_open() and player.controls_enabled and console.reply_text().begins_with("Time set to 14m 00s"), "C09: Enter runs the line, closes and shows the reply")
	day.time = was_time
	day.apply()
	weather.set_kind(was_kind, true)
	weather.changes = was_changes
	await _until(func() -> bool: return not world.lightning_bolt.visible, 2.0)


# W08: swimming, the seabed, the view under the water, and the ways back to
# the platform.
func _swimming(world: Node3D, player: Player) -> void:
	var head: Node3D = player.get_node("Head")
	var env: Environment = (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var seabed: Seabed = world.get_node("Seabed")
	_check(seabed.chunk_count() > 0, "the seabed is built around you")
	_check(Seabed.height_at(0, 0) == Seabed.PLATFORM_FLOOR and Seabed.height_at(5000, 300) <= Seabed.SHALLOWEST and Seabed.height_at(5000, 300) >= Seabed.DEEPEST, "shallow by the platform, deeper out at sea")
	# Out at sea it stays between SHALLOWEST and DEEPEST (sunk islands and
	# bridge posts count on it) but uses that range: banks, deeps, mounds.
	var lo := 0.0
	var hi := -100.0
	var bumps := 0.0
	var samples := 0
	for i in 120:
		for j in 120:
			var x := 300.0 + i * 23.7
			var z := -1400.0 + j * 21.3
			var h := Seabed.height_at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			bumps += absf(h - Seabed.height_at(x + Seabed.CELL, z))
			samples += 1
	_check(lo >= Seabed.DEEPEST and hi <= Seabed.SHALLOWEST, "the sea floor stays between %.0f and %.0f m (%.2f..%.2f)" % [Seabed.SHALLOWEST, Seabed.DEEPEST, hi, lo])
	_check(hi > Seabed.SHALLOWEST - 1.0 and lo < Seabed.DEEPEST + 1.0 and bumps / samples > 0.3, "with banks, deeps and mounds (%.2f..%.2f, %.2f m a cell)" % [hi, lo, bumps / samples])
	_check(Seabed.colour(-4.0).is_equal_approx(Seabed.SAND) and Seabed.colour(-40.0).is_equal_approx(Seabed.DEEP) and _close(Seabed.colour(-14.0), Seabed.colour(-14.01), 0.001) and _close(Seabed.colour(-19.0), Seabed.colour(-19.01), 0.001), "its colour darkens smoothly with depth")

	player.global_position = Vector3(20, -3, 0)
	player.velocity = Vector3.ZERO
	await _frames(30)
	_check(player.swimming and player.global_position.y > -3.3, "in deep water it swims, not sinks (y %.2f)" % player.global_position.y)
	_check(world.underwater.active and env.fog_depth_end == Underwater.FOG_END, "under the water the fog is blue and close")

	Input.action_press("jump")
	await _frames(120)
	var top := player.global_position.y
	await _frames(30)
	Input.action_release("jump")
	_check(absf(top + player.float_depth) < 0.15 and player.global_position.y < -player.float_depth + 0.05, "Space rises to the surface and floats there, no higher (y %.2f)" % player.global_position.y)
	await _frames(5)
	_check(not world.underwater.active and env.fog_depth_end == 390.0, "with the head above the water, the world's own fog")

	var before := player.global_position.y
	Input.action_press("swim_down")
	Input.action_press("crouch") # the same key, Ctrl
	await _frames(30)
	var crouched := player.crouching
	Input.action_release("swim_down")
	Input.action_release("crouch")
	_check(player.global_position.y < before - 0.8 and not crouched, "Ctrl sinks, and doesn't crouch in the water (W11)")

	head.rotation.x = -0.9
	before = player.global_position.y
	var from := Vector2(player.global_position.x, player.global_position.z)
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	_check(player.global_position.y < before - 0.8 and from.distance_to(Vector2(player.global_position.x, player.global_position.z)) > 0.5, "W swims where you look: down and along")
	head.rotation.x = 0.0

	Input.action_press("swim_down")
	await _frames(150)
	Input.action_release("swim_down")
	var p := player.global_position
	var floor_y := Seabed.height_at(p.x, p.z)
	_check(p.y > floor_y - 0.3 and p.y < floor_y + 0.6, "the seabed stops you (y %.2f, floor %.2f)" % [p.y, floor_y])

	# Sprinting up leaps out of the water (a dolphin jump), not high enough
	# to land on the platform's deck, and back in to swim.
	player.global_position = Vector3(200, -10, 0)
	player.velocity = Vector3.ZERO
	await _frames(2)
	Input.action_press("sprint")
	Input.action_press("jump")
	var peak := -100.0
	var left := false
	for i in 360:
		await _frames(1)
		peak = maxf(peak, player.global_position.y)
		if not player.swimming and not left:
			left = true
			Input.action_release("jump")
			Input.action_release("sprint")
		elif left and player.swimming:
			break
	Input.action_release("jump")
	Input.action_release("sprint")
	_check(left and peak > -player.float_depth + 1.0, "sprinting up leaps out of the water (feet to %.2f)" % peak)
	_check(peak < world.get_script().get_script_constant_map()["PLATFORM_TOP"], "but not as high as the platform's deck (%.2f)" % peak)
	_check(player.swimming and player.global_position.y < -player.swim_depth, "and falls back in to swim (y %.2f)" % player.global_position.y)

	# Out of the water only up a beach.
	var island := Island.new()
	island.island_seed = 42
	island.position = Vector3(0, 0, -300)
	world.add_child(island)
	var shore := island.generator.shore_radius(0.0, 1.0)
	player.rotation.y = 0.0 # facing -z, the island
	player.global_position = island.position + Vector3(0, -1.5, shore * 1.3)
	player.velocity = Vector3.ZERO
	await _frames(10)
	_check(player.swimming, "swimming over an island's shelf")
	Input.action_press("move_forward")
	await _until(func() -> bool: return not player.swimming and player.global_position.y > 0.3, 10.0)
	Input.action_release("move_forward")
	_check(not player.swimming and player.global_position.y > 0.3, "swims to the beach and walks out")
	island.queue_free()

	# Back to the platform from the water: the sessions menu, then the map.
	player.global_position = Vector3(30, -2, 0)
	await _frames(5)
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	menu.open()
	await _frames(2)
	_check(menu.entries()[1] == "⌂ Platform", "the sessions menu offers the platform")
	menu.choose("⌂ Platform")
	await _frames(2)
	_check(not menu.is_open() and not player.swimming and player.global_position.distance_to(player.spawn_point) < 0.2, "which takes you there")
	player.global_position = Vector3(30, -2, 0)
	await _frames(5)
	world.world_map.open()
	await _frames(2)
	world.world_map.click(world.world_map.to_map(Vector3(3, 0, -4)))
	await _frames(2)
	_check(not world.world_map.is_open() and player.global_position.distance_to(player.spawn_point) < 0.2, "and so does clicking the platform on the big map")
	await _frames(30)


func _menu(world: Node3D, player: Player) -> void:
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	await _frames(5)
	_check(menu.hint_visible() and not menu.is_open(), "no sessions yet: \"Press Tab for sessions\"")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.is_open() and not player.controls_enabled and not menu.hint_visible(), "Tab opens the sessions menu and pauses the player")
	_check(menu.page() == SessionsMenu.Page.MAIN and menu.entries().slice(0, 2) == ["+ Add session…", "⌂ Platform"] and not menu.pickers_visible(), "its first page: Add session and the platform, no cluster or biome")
	_check(menu.listings_asked == 0 and not menu.entries().has("Resume"), "S04: and no stored sessions, so the sidecar isn't asked for them")
	menu.choose("+ Add session")
	_check(menu.page() == SessionsMenu.Page.ADD and menu.entries() == ["+ New session…", "▸ Resume a session…"] and menu.pickers_visible(), "Add session: New or Resume, with the cluster and biome")
	var kinds: Array[String] = ["Random"]
	for k: int in Biome.NAMES:
		kinds.append(Biome.NAMES[k])
	_check(menu.biome_choices() == kinds and menu.biome_choice() == Biome.RANDOM, "W10: the biome selector offers Random and each biome, Random first")
	menu.choose_biome("Mountain")
	_check(menu.biome_choice() == Biome.Kind.MOUNTAIN, "W10: and picks one")
	menu.choose("+ New session")
	await _frames(2)
	_check(menu.picker().visible, "New session opens the folder picker, in the game window")
	menu.picker().get_cancel_button().pressed.emit()
	await _frames(2)
	_check(menu.is_open() and menu.page() == SessionsMenu.Page.ADD and not menu.picker().visible and not player.controls_enabled, "cancelling it goes back to the menu")
	menu.choose("▸ Resume a session")
	_check(menu.page() == SessionsMenu.Page.RESUME and menu.listings_asked == 1 and menu.pickers_visible() and menu.biome_choice() == Biome.Kind.MOUNTAIN, "S04: Resume asks for the stored sessions, the choices kept")
	_press("ui_cancel")
	await _until(func() -> bool: return menu.page() == SessionsMenu.Page.ADD, 2.0)
	_check(menu.is_open() and menu.page() == SessionsMenu.Page.ADD, "Esc goes back a page: Resume to Add session")
	_press("ui_cancel")
	await _until(func() -> bool: return menu.page() == SessionsMenu.Page.MAIN, 2.0)
	_check(menu.is_open() and menu.page() == SessionsMenu.Page.MAIN and not menu.pickers_visible(), "then to the first page")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled and menu.hint_visible(), "where Esc closes the menu")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.page() == SessionsMenu.Page.MAIN and menu.biome_choice() == Biome.RANDOM, "it opens on its first page, the biome back to Random each time")
	menu.choose("+ Add session")
	menu.choose("▸ Resume a session")
	_press("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled, "Tab closes it from any page")
	# Choosing a folder ends in the launcher's create().
	var sidecar: SidecarClient = root.get_node("Sidecar")
	await _until(func() -> bool: return sidecar.status == SidecarClient.Status.READY, 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "the sidecar is up")

	# The system's picker (none headless, so a stand-in that keeps its
	# callback): the menu waits with a note and Cancel.
	var answer := [Callable()]
	var pickers_shown := [0]
	menu.native_picker = true
	menu.show_native = func(_dir: String, callback: Callable) -> Error:
		answer[0] = callback
		return OK
	menu.native_picker_shown.connect(func(_dir: String) -> void: pickers_shown[0] += 1)
	var new_session := func() -> void:
		_press("sessions_menu")
		await _until(func() -> bool: return menu.is_open(), 2.0)
		menu.choose("+ Add session")
		menu.choose("+ New session")
		await _frames(2)
	await new_session.call()
	_check(pickers_shown[0] == 1 and menu.waiting_for_picker() and menu.is_open() and not menu.picker().visible, "system picker: the menu waits for it, with a note")
	answer[0].call(false, PackedStringArray(), 0)
	await _until(func() -> bool: return not menu.waiting_for_picker(), 2.0)
	_check(menu.is_open() and menu.page() == SessionsMenu.Page.ADD and not menu.waiting_for_picker() and not player.controls_enabled, "system picker: cancelling it goes back to the menu")
	menu.choose("+ New session")
	await _frames(2)
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.waiting_for_picker(), 2.0)
	_check(menu.is_open() and menu.page() == SessionsMenu.Page.ADD and not menu.waiting_for_picker() and menu.pickers_visible() and not player.controls_enabled, "system picker lost behind the game: Esc stops waiting, back on Add a session")
	answer[0].call(true, PackedStringArray([OS.get_user_data_dir()]), 0)
	await _settle()
	_check(not menu.launcher.busy() and menu.notice_text() == "" and menu.is_open() and menu.page() == SessionsMenu.Page.ADD, "and its late answer is ignored")
	menu.choose("+ New session")
	await _frames(2)
	menu.get_node("Panel/Layout/Waiting/Cancel").pressed.emit()
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and not menu.waiting_for_picker() and player.controls_enabled, "and its Cancel closes the menu and gives the controls back")
	answer[0].call(true, PackedStringArray([OS.get_user_data_dir()]), 0)
	await _settle()
	_check(not menu.launcher.busy() and menu.notice_text() == "" and not menu.is_open(), "and that late answer is ignored too")
	await new_session.call()
	answer[0].call(true, PackedStringArray([OS.get_user_data_dir().path_join("no-such-folder")]), 0)
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled, "system picker: choosing a folder closes the menu and gives the controls back")
	await _until(func() -> bool: return menu.notice_text().begins_with("Couldn't"), 5.0)
	_check(menu.notice_text().contains("does not exist") and not menu.launcher.busy(), "a missing folder is refused, and the notice says so")
	menu.native_picker = false

	# A session that's slow to start (its terminal may have closed unseen):
	# the menu can stop waiting for it.
	var started := [0]
	menu.launcher.session_started.connect(func(_id: String) -> void: started[0] += 1)
	menu.launcher.pending = "slow"
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.entries().has("✕ Stop waiting for the session starting"), "a start under way: the menu offers to stop waiting")
	menu.choose("✕ Stop waiting")
	await _frames(2)
	_check(not menu.launcher.busy() and menu.notice_text().begins_with("Stopped waiting") and not menu.entries().has("✕ Stop waiting for the session starting"), "stopping frees the launcher for another start")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(started[0] == 0, "and nobody waits for it any more")


# W10: an island of a chosen biome rises from deep enough, is bridged at
# its edge height with its way in clear of props, and sinks again.
func _biome_island(world: Node3D, player: Player) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	player.global_position = player.spawn_point
	islands.choose_biome("m1", Biome.Kind.MOUNTAIN)
	store.apply({"type": "session.created", "session": _snapshot("m1")})
	var m := islands.island("m1")
	_check(m.biome == Biome.Kind.MOUNTAIN and m.edge_height() > 4.0, "W10: the chosen biome is the island's")
	_check(m.position.y + m.top() < Seabed.DEEPEST, "W10: a high island rises from all under the sea floor (top %.1f m)" % (m.position.y + m.top()))
	await _until(func() -> bool: return not islands.is_rising("m1"), 6.0)
	var region := SessionIslands.region(m)
	var ends: Array[Vector3] = []
	var clear := true
	for b in islands.bridges.all_bridges():
		for e: Vector3 in [b.from, b.to]:
			if Vector2(e.x - m.global_position.x, e.z - m.global_position.z).length() < m.generator.radius * 1.5:
				ends.append(e)
				clear = clear and not m.props.is_near(Vector2(e.x - m.global_position.x, e.z - m.global_position.z), SessionIslands.LANDING_CLEAR - 0.1)
	_check(islands.bridges.links().any(func(l: Array) -> bool: return region in l) and not ends.is_empty(), "W10: it's bridged")
	_check(ends.all(func(e: Vector3) -> bool: return absf(e.y - m.edge_height()) < 0.3) and clear, "W10: its bridges land at its edge height, clear of props")
	# Its zipline: E by the bottom post rides you up, E at the top down.
	var zip := m.zipline()
	_check(zip != null and islands.island("m1") == m, "W10: a mountain has a zipline")
	if zip:
		player.global_position = zip.to_global(zip.low) + Vector3(0.5, 0.1, 0)
		player.velocity = Vector3.ZERO
		await physics_frame
		await physics_frame
		_press("interact")
		await _until(func() -> bool: return zip.is_riding(), 1.0)
		var started := zip.is_riding() and player.riding
		await _until(func() -> bool: return not zip.is_riding(), 8.0)
		var up := not player.riding and player.global_position.y > m.global_position.y + m.edge_height() - 0.5
		_check(started and up, "W10: E by its bottom post rides you up to the shoulder (%.1f m)" % (player.global_position.y - m.global_position.y))
		await physics_frame
		await physics_frame
		player.global_position = zip.to_global(zip.high) + Vector3(0, 0.1, 0)
		await physics_frame
		await physics_frame
		_press("interact")
		await _until(func() -> bool: return zip.is_riding(), 1.0)
		await _until(func() -> bool: return not zip.is_riding(), 8.0)
		_check(not player.riding and player.global_position.y < m.global_position.y + 2.0, "W10: and E at the top takes you down")
		player.global_position = player.spawn_point
	store.apply({"type": "session.ended", "session": "m1", "seq": 2, "reason": "exited"})
	var gone := m.get_instance_id()
	await _until(func() -> bool: return not is_instance_id_valid(gone), 8.0)
	_check(not is_instance_id_valid(gone), "W10: and sinks when its session ends")


func _snapshot(id: String) -> Dictionary:
	return {
		"session": id, "seq": 1, "provider": "fake", "native_id": null, "origin": "app",
		"project": {"path": "/p", "name": "demo"}, "title": null, "started_at": "2026-09-30T10:00:00Z",
		"capabilities": {}, "extensions": [], "permissions": [], "notices": [],
		"agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
	}


# Sessions applied to the store by hand, so no provider is needed.
func _sessions(world: Node3D, player: Player) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var chat: ChatController = world.get_node("ChatController")
	var at := player.global_position
	store.apply({"type": "session.snapshot", "session": _snapshot("h1")})
	store.apply({"type": "session.snapshot", "session": _snapshot("h2")})
	await _frames(2)
	var island := islands.island("h1")
	var orchestrator := islands.orchestrator("h1")
	_check(island != null and islands.island("h2") != null, "an island per session")
	_check(island.global_position.distance_to(islands.island("h2").global_position) > 90.0, "islands apart from each other")
	_check(Vector2(island.global_position.x, island.global_position.z).length() > 100.0, "and away from the platform")
	var clusters := islands.clusters
	var c1 := clusters.cluster_of("h1")
	_check(c1 != "" and clusters.cluster_of("h2") == c1 and clusters.cluster_name(c1) == "demo", "clusters: same folder, same cluster, named after it")
	_check(island.global_position.is_equal_approx(SessionClusters.cluster_position(0)), "clusters: the first island is in its cluster's middle")
	_check(orchestrator.session_id == "h1", "its orchestrator belongs to the session")
	_check(orchestrator.position.is_equal_approx(Vector3(0, island.height_at(0, 0), 0)), "and stands in the middle of it")
	_check(player.global_position.distance_to(at) < 0.1, "a session already running doesn't move the player")
	_check(island.position.y == 0.0 and not islands.is_rising("h1"), "and its island is just there, not rising")
	_check(islands.unvisited().is_empty() and not island.has_node("NewBeacon"), "nor marked as new")
	var bridges := islands.bridges
	var r1 := SessionIslands.region(island)
	var r2 := SessionIslands.region(islands.island("h2"))
	_check(bridges.bridge("platform", r1) != null and bridges.bridge(r1, r2) != null and bridges.links().size() == 2, "W06: bridges from the platform to the first island, and on to the next")
	var minimap: Minimap = world.minimap
	await _settle() # the minimap updates in _process
	_check(minimap.shown_cluster() == c1 and minimap.map_rect().position == Vector2(Minimap.GAP, Minimap.GAP), "the minimap shows the nearest cluster, top left")
	var drawn := minimap.to_map(island.global_position)
	_check(Rect2(Vector2.ZERO, minimap.map_rect().size).has_point(drawn) and Rect2(Vector2.ZERO, minimap.map_rect().size).has_point(minimap.to_map(player.global_position)), "with its islands and you on it")
	await _big_map(world, player, islands)
	await _settle()
	_check(minimap.shown_cluster() == c1, "the minimap is back once the big map closes")
	await _quit(world, player)

	var bubble := chat.bubble("h1")
	_check(bubble != null and not bubble.visible, "no bubble before the orchestrator says anything")
	store.apply({"type": "message.started", "session": "h1", "seq": 2, "message": "u1", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": "h1", "seq": 3, "message": "u1", "text": "Hi there"})
	_check(not bubble.visible, "your own messages don't show in the bubble")
	store.apply({"type": "message.started", "session": "h1", "seq": 4, "message": "a1", "agent": "main", "role": "assistant"})
	store.apply({"type": "message.delta", "session": "h1", "seq": 5, "message": "a1", "text": "Looking at it.\n"})
	_check(bubble.visible and bubble.shown_text() == "Looking at it.", "the bubble streams the reply")
	store.apply({"type": "message.delta", "session": "h1", "seq": 6, "message": "a1", "text": "two\nthree\nfour\nfive\n"})
	_check(bubble.shown_text() == "…two\nthree\nfour\nfive", "and keeps its newest lines")
	bubble.show_text("**Bold** and `code`")
	_check(bubble.shown_text() == "Bold and code", "the bubble renders Markdown")
	bubble.show_text("```py\nx = 1\n\ny = 2\n```")
	_check(bubble.shown_text() == "x = 1\ny = 2", "code shows in the bubble, without blank lines")
	bubble.show_text("word ".repeat(80))
	_check(bubble.shown_text().begins_with("…word") and bubble.shown_text().count("\n") == 3, "a long paragraph wraps and keeps 4 lines")
	_check(bubble.get_node("Viewport/Panel/Box/Clip/Text").size.x <= MessageBubble.MAX_WIDTH, "no wider than its limit")
	bubble.show_text("[url=https://x]click[/url]")
	_check(bubble.shown_text() == "[url=https://x]click[/url]", "the bubble shows markup as written")
	bubble.show_text("  \n")
	_check(not bubble.visible, "blank text hides it")
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 7, "agent": "main", "state": "working", "reason": null})

	world.teleport("h1")
	await _frames(20)
	_check(player.global_position.distance_to(orchestrator.global_position) < 7.0 and player.is_on_floor(), "teleport: in front of the orchestrator, on its island")
	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _until(func() -> bool: return chat.prompt_visible(), 2.0)
	_check(chat.prompt_visible(), "walking close shows \"Press E to chat\"")
	# The sidecar doesn't have h1, so fetching its history fails.
	await _until(func() -> bool: return not chat._history.has("h1"), 5.0)
	_check(not chat._history.has("h1"), "a failed history fetch is forgotten")
	chat.open(orchestrator)
	# Checked at once: the retry fails again within a frame or two.
	_check(chat._history.get("h1") == "asking", "opening the chat asks for the history again")
	chat.close()
	world.world_map.open()
	_press("interact")
	await _settle()
	_check(not chat.is_open(), "E doesn't open the chat while the big map is open")
	world.world_map.close()
	_press("interact")
	await _until(func() -> bool: return chat.is_open(), 2.0)
	var panel := chat.panel()
	_check(chat.is_open() and panel.visible and not player.controls_enabled, "E opens the chat panel and pauses the player")
	await _settle()
	_check(world.minimap.shown_cluster() == "", "the minimap hides while chatting")
	_press("minimap")
	await _settle()
	_check(not world.world_map.is_open() and chat.is_open(), "M doesn't open the big map while chatting")
	# The newest message is built at once, the older ones over a few frames.
	await _until(func() -> bool: return not panel.is_loading(), 5.0)
	_check(panel.shown_messages() == ["Hi there", "Looking at it.\ntwo\nthree\nfour\nfive"], "the panel shows the chat so far")
	_check(panel.status_text() == "Working…", "and what the orchestrator is doing")
	store.apply({"type": "message.completed", "session": "h1", "seq": 8, "message": "a1", "text": "Done. [url=https://x]click[/url]"})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 9, "agent": "main", "state": "idle", "reason": null})
	_check(panel.shown_messages()[1] == "Done. [url=https://x]click[/url]" and panel.status_text() == "", "it updates in place; text is shown as written, not as markup")
	store.apply({"type": "message.started", "session": "h1", "seq": 81, "message": "a2", "agent": "main", "role": "assistant"})
	store.apply({"type": "message.completed", "session": "h1", "seq": 82, "message": "a2", "text": "# Fixed\n\n**Done**, see [docs](https://example.com):\n\n```gd\nvar x := 1\n```"})
	_check(panel.shown_messages()[2] == "Fixed\n \nDone, see docs:\nvar x := 1", "Markdown is rendered in the panel")
	var view: MarkdownView = panel._rows["a2"]
	_check(view.get_child_count() == 2 and view.get_child(1).has_meta("code"), "a code block gets its own panel")
	(view.get_child(0) as RichTextLabel).meta_clicked.emit("0")
	_check(panel.link_asked() == "https://example.com", "a link asks before opening, showing its address")
	# A real key: the dialog has the focus, so a key goes to it.
	for pressed in [true, false]:
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = pressed
		Input.parse_input_event(esc)
	await _until(func() -> bool: return panel.link_asked().is_empty(), 2.0)
	await _settle()
	_check(chat.is_open() and panel.link_asked() == "", "Esc closes the question, not the chat")
	await _tool_log(store, panel)
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 10, "agent": "main", "state": "waiting", "reason": "permission"})
	_check(panel.status_text().contains("above or in the terminal"), "a permission wait points to the card and the terminal")
	store.apply({"type": "session.notice", "session": "h1", "seq": 11, "notice": {"code": "transcripts_off", "message": "x"}})
	_check(panel.get_node("Layout/Notices").visible, "notices show")
	await _card(store, panel)
	await _usage(world, store, panel)

	# Sending to a session the sidecar doesn't have: refused, text kept.
	panel.set_draft("hello")
	panel.send()
	_check(panel.draft() == "", "sending clears the box")
	await _until(func() -> bool: return panel.status_text().begins_with("Couldn't send"), 5.0)
	_check(panel.status_text().begins_with("Couldn't send") and panel.draft() == "hello", "a refused message says so and comes back")
	# One box serves every chat (S06 review): kept while closed, emptied
	# on opening another session's.
	panel.close()
	panel.open("h1")
	_check(panel.draft() == "hello", "the box keeps its text while the chat is closed")
	panel.close()
	panel.open("h2")
	_check(panel.draft() == "", "opening another session's chat empties the box")
	panel.set_draft("for h2")
	panel.close()
	panel.open("h1")
	_check(panel.draft() == "", "and going back doesn't bring h2's text")
	panel.set_draft("hello")
	panel.send()
	panel.close()
	panel.open("h2")
	await _until(func() -> bool: return panel._not_picked_up.has("h1"), 5.0)
	_check(panel._not_picked_up.has("h1") and panel.draft() == "" and not panel.status_text().begins_with("Couldn't send"), "a refusal for h1 doesn't land in h2's chat")
	panel.close()
	panel.open("h1")
	_check(panel.draft() == "hello" and panel.status_text().begins_with("Your message hasn't reached"), "returning, it says the message hasn't arrived and gives it back")
	panel._not_picked_up.clear()
	panel._given_back.clear()
	panel.set_draft("")
	# A message that wasn't picked up (set by hand: this sidecar refuses
	# h1) comes back on returning, unless the box was cleared there.
	panel._not_picked_up["h1"] = "lost"
	panel.close()
	panel.open("h1")
	_check(panel.draft() == "lost" and panel.status_text().begins_with("Your message hasn't reached"), "a message not picked up comes back on opening its chat")
	panel.close()
	panel.open("h2")
	_check(panel.draft() == "" and panel.status_text() == "", "not in another session's")
	panel.close()
	panel.open("h1")
	_check(panel.draft() == "lost", "and comes back again on returning, unsent")
	panel.set_draft("")
	panel.close()
	panel.open("h2")
	panel.close()
	panel.open("h1")
	_check(panel.draft() == "", "cleared, it stays clear")
	# A late pickup for h1 leaves h2's box alone, even holding the same text.
	panel.close()
	panel.open("h2")
	panel.set_draft("lost")
	var state: Dictionary = store.orchestrator("h1").duplicate()
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 9001, "agent": "main", "state": "working", "reason": null})
	_check(panel.draft() == "lost" and not panel._not_picked_up.has("h1"), "a late pickup for h1 doesn't touch h2's box")
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 9002, "agent": "main", "state": state["state"], "reason": state.get("reason")})
	panel._not_picked_up.clear()
	panel._given_back.clear()
	panel.close()
	panel.open("h1")

	var walk_at := player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(walk_at) < 0.05, "no walking while chatting")
	_press("ui_cancel")
	await _until(func() -> bool: return not chat.is_open(), 2.0)
	_check(not chat.is_open() and chat.prompt_visible() and player.controls_enabled, "Esc closes the chat")

	# The session ends while you're on its island, with the chat open.
	_press("interact")
	await _until(func() -> bool: return chat.is_open(), 2.0)
	# /resume in the terminal: the latest switch notice, and the resumed chat.
	store.apply({"type": "session.notice", "session": "h1", "seq": 20, "notice": {"code": "conversation_cleared", "message": "x"}})
	store.apply({"type": "session.notice", "session": "h1", "seq": 21, "notice": {"code": "conversation_resumed", "message": "x"}})
	var shown: String = panel.get_node("Layout/Notices").text
	_check(shown.contains("/resume") and not shown.contains("/clear") and shown.contains("transcripts"), "of the conversation switches, only the latest notice shows")
	store.apply({"type": "session.updated", "session": "h1", "seq": 22, "native_id": "n2"})
	store.replace_history("h1", [{"message": "r1", "agent": "main", "role": "user", "text": "earlier", "at": "2026-09-29T08:00:00Z"}])
	await _frames(1)
	_check(panel.shown_messages() == ["earlier"], "a replaced chat is laid out again")
	# A long chat: the newest messages at once, the older ones a few per frame.
	var long_chat: Array = []
	var expected: Array[String] = []
	for k in 150:
		long_chat.append({"message": "l%d" % k, "agent": "main", "role": "assistant", "text": "**%d**\n\n```\ncode %d\n```" % [k, k], "at": "2026-09-29T08:00:00Z"})
		expected.append("%d\ncode %d" % [k, k])
	# The live message that isn't in this history stays at the end.
	expected.append("earlier")
	store.replace_history("h1", long_chat)
	_check(panel.is_loading() and panel.shown_messages() == expected.slice(expected.size() - panel.shown_messages().size()), "a long chat shows its newest messages first")
	await _until(func() -> bool: return not panel.is_loading(), 20.0)
	_check(panel.shown_messages() == expected, "then all of it, in order")
	# /clear: the sidecar's history is empty, so the window clears at once.
	store.apply({"type": "session.updated", "session": "h1", "seq": 23, "native_id": "n3"})
	store.apply({"type": "session.notice", "session": "h1", "seq": 24, "notice": {"code": "conversation_cleared", "message": "x"}})
	store.replace_history("h1", [])
	await _frames(1)
	shown = panel.get_node("Layout/Notices").text
	_check(panel.shown_messages().is_empty() and shown.contains("(/clear)") and not shown.contains("(/resume)"), "after /clear the chat is empty, with its notice")
	await _sign_in(world, panel)
	await _attention(world)
	var on_island := player.global_position
	store.apply({"type": "session.ended", "session": "h1", "seq": 30, "reason": "exited"})
	# Waits hold weak references: a lambda can't capture a freed object.
	var orchestrator_ref: WeakRef = weakref(orchestrator)
	var island_ref: WeakRef = weakref(island)
	await _until(func() -> bool: return orchestrator_ref.get_ref() == null and not chat.is_open(), 2.0)
	_check(islands.island("h1") == null and not is_instance_valid(orchestrator) and not chat.is_open() and player.controls_enabled, "an ended session's orchestrator goes, and its chat closes")
	_check(chat.bubble("h1") == null and not chat.prompt_visible(), "nothing of it is left to talk to")
	await _frames(10)
	_check(island in islands.left_islands() and island.position.y == 0.0 and player.global_position.distance_to(on_island) < 0.5, "W04: its island stays while you're on it")
	# W06: on its bridge to the platform, far from the island, counts too.
	var to_platform := bridges.bridge("platform", r1)
	player.global_position = to_platform.from.lerp(to_platform.to, 0.5) + Vector3(0, 0.6, 0)
	await _frames(20)
	_check(to_platform.carries(player.global_position) and not islands._is_over(island, player.global_position), "W06: on its bridge, away from the island")
	_check(island in islands.left_islands() and island.position.y == 0.0 and is_instance_valid(to_platform) and bridges.has(r1), "the empty island and its bridges stay")
	player.global_position = on_island
	await _frames(10)
	# A session started meanwhile: its island rises, and you're taken there
	# once it's up. A beach: a mountain starts about 100 m down (W10), so
	# facing it from the platform, its aim point is on the 64x64 headless
	# window's on-screen edge.
	islands.choose_biome("h3", Biome.Kind.BEACH)
	store.apply({"type": "session.created", "session": _snapshot("h3")})
	var h3 := islands.island("h3")
	_check(islands.is_rising("h3") and h3.position.y < -1.0, "a new session's island rises out of the sea")
	_check(not h3.global_position.is_equal_approx(SessionClusters.cluster_position(0)), "not in the spot of the island you're on")
	var beacon: AttentionBeacon = h3.get_node("NewBeacon")
	_check(Array(islands.unvisited()) == ["h3"] and beacon.is_on(), "a beacon stands over it until you've been there")
	var pointers: NewIslandPointers = world.pointers
	var to_h3 := h3.global_position - player.global_position
	player.rotation.y = atan2(-to_h3.x, -to_h3.z) # facing it
	# The arrows follow the camera in _process: wait for process frames, not
	# physics ones. Right after an island is built, a main-loop iteration
	# catches up several physics steps before any _process runs.
	await _settle()
	_check(pointers.shown().is_empty(), "facing it: no arrow, the beacon shows it (shown %s, player %s, h3 %s)" % [pointers.shown(), player.global_position, h3.global_position])
	player.rotation.y += PI
	await _settle()
	var arrow := pointers.arrow("h3")
	var label: Label = arrow.get_node("Label") if arrow else null
	_check(Array(pointers.shown()) == ["h3"] and label.text.begins_with("demo · ") and label.text.ends_with(" m"), "behind you: an arrow at the edge, with its project and distance")
	var screen := root.get_visible_rect()
	_check(screen.has_point(arrow.position) and not screen.grow(-pointers.margin() - 1.0).has_point(arrow.position), "on the screen's edge")
	world.teleport("h3")
	await _frames(5)
	_check(player.global_position.distance_to(on_island) < 0.5, "going there waits for it to rise")
	await _until(func() -> bool: return not islands.is_rising("h3"), 6.0)
	await _frames(20)
	_check(h3.position.y == 0.0 and player.global_position.distance_to(islands.orchestrator("h3").global_position) < 7.0 and player.is_on_floor(), "then takes you there")
	_check(is_instance_valid(island) and island.position.y < 0.0, "you've left the empty island: it sinks")
	await _settle()
	_check(islands.unvisited().is_empty() and not beacon.is_on() and pointers.shown().is_empty(), "being there clears the beacon and the arrow")
	await _until(func() -> bool: return island_ref.get_ref() == null, 6.0)
	_check(island_ref.get_ref() == null, "and goes")
	store.apply({"type": "session.snapshot", "session": _snapshot("h5")})
	_check(islands.island("h5").global_position.is_equal_approx(SessionClusters.cluster_position(0)), "its spot is free again")
	# A session that ends as its island rises: back down at once (you're not
	# on it).
	store.apply({"type": "session.created", "session": _snapshot("h6")})
	await _frames(5)
	var h6 := islands.island("h6")
	store.apply({"type": "session.ended", "session": "h6", "seq": 2, "reason": "exited"})
	_check(not islands.is_rising("h6") and h6 in islands.left_islands() and islands.unvisited().is_empty(), "a session ending while its island rises")
	var h6_ref: WeakRef = weakref(h6)
	await _until(func() -> bool: return h6_ref.get_ref() == null, 6.0)
	_check(not is_instance_valid(h6), "sinks it from there")
	player.respawn()
	for id in ["h2", "h3", "h5"]:
		store.apply({"type": "session.ended", "session": id, "seq": 2, "reason": "exited"})
	await _frames(2)


# C04: the tool calls after a message, folded into one line. h1's chat is
# u1, a1, a2 so far.
func _tool_log(store: SessionStore, panel: ChatPanel) -> void:
	_check(not panel.tool_fold("a2").visible and not panel.tool_fold("").visible, "no tool calls, no fold")
	store.apply({"type": "tool.started", "session": "h1", "seq": 83, "tool_call": "t1", "agent": "main", "tool": "Bash", "summary": "Run: [b]rm[/b] x", "input": {"command": "rm [i]x[/i]"}})
	var fold := panel.tool_fold("a2")
	_check(fold.visible and fold.header_text() == "▸ 1 tool call (1 running)", "a call folds into one line after its message")
	store.apply({"type": "tool.finished", "session": "h1", "seq": 84, "tool_call": "t1", "status": "error", "summary": "Exit [color=red]code[/color] 1"})
	_check(fold.header_text() == "▸ 1 tool call (1 failed)", "and follows it as it ends")
	store.apply({"type": "tool.started", "session": "h1", "seq": 85, "tool_call": "t2", "agent": "main", "tool": "Agent", "summary": "Agent: look"})
	store.apply({"type": "tool.started", "session": "h1", "seq": 86, "tool_call": "t3", "agent": "s1", "tool": "Read", "summary": "Read a.gd", "within": "t2"})
	store.apply({"type": "tool.finished", "session": "h1", "seq": 87, "tool_call": "t3", "status": "denied"})
	_check(fold.header_text() == "▸ 2 tool calls (1 running, 1 failed)", "a subagent's call isn't counted at the top")
	fold.set_open(true)
	_check(fold.shown_calls() == ["failed Run: [b]rm[/b] x / Exit [color=red]code[/color] 1", "running Agent: look"], "opened: each call, how it went, its result; text as written")
	var inner := fold.inner("t2")
	_check(inner.visible and inner.header_text() == "▸ 1 tool call (1 denied)" and not fold.inner("t1").visible, "a subagent's calls fold inside its Agent call")
	inner.set_open(true)
	store.apply({"type": "tool.started", "session": "h1", "seq": 88, "tool_call": "t4", "agent": "s1", "tool": "Read", "summary": "Read b.gd", "within": "t2"})
	_check(inner.shown_calls() == ["denied Read a.gd", "running Read b.gd"], "and grow there live")
	fold.show_details("t1", true)
	_check(fold.details_text("t1").contains("Tool: Bash") and fold.details_text("t1").contains("\"command\": \"rm [i]x[/i]\""), "Details shows the input, as written")
	# Untrusted text never reaches a BBCode node (Security rules).
	_check(fold.find_children("*", "RichTextLabel", true, false).is_empty(), "the log's summary, result and details are plain Labels")
	fold.show_details("t1", false)
	_check(fold.details_text("t1") == "", "and hides it again")
	_check(panel.shown_messages().size() == 3, "the log doesn't count as messages")
	# Calls from the history land after their own message, laid out again.
	store.load_history("h1", [], [{"tool_call": "t0", "agent": "main", "tool": "Read", "summary": "Read NOTES.md", "status": "ok", "after": "u1"}])
	# Laid out again on the next frame, the oldest message (u1) last.
	await _until(func() -> bool: return not panel._rebuild_queued and not panel.is_loading() and panel.tool_fold("u1") != null, 5.0)
	_check(panel.tool_fold("u1").visible and panel.tool_fold("u1").header_text() == "▸ 1 tool call", "history's calls go after their message")
	_check(panel.tool_fold("a2").header_text() == "▸ 2 tool calls (1 running, 1 failed)", "and the live ones stay where they were")
	for t in ["t2", "t4"]:
		store.apply({"type": "tool.finished", "session": "h1", "seq": 89, "tool_call": t, "status": "ok"})


# S06, with h1's chat open: the account can't be used. The provider's notice
# shows as sent, the status points to the terminal, the orchestrator shows
# the "!" and A05's cue; a sign-in or a call going through clears it. Other
# failures say what stopped the turn. Leaves h1 as it found it.
func _sign_in(world: Node3D, panel: ChatPanel) -> void:
	var store: SessionStore = world.store
	var attention: Attention = world.attention
	var marker: AgentStateMarker = world.get_node("SessionIslands").orchestrator("h1").get_node("StateMarker")
	var was: Dictionary = store.agent("h1", "main").duplicate()
	var state := func(seq: int, to: String, reason: Variant = null) -> void:
		store.apply({"type": "agent.state_changed", "session": "h1", "seq": seq, "agent": "main", "state": to, "reason": reason})
	var notices := func() -> String: return panel.get_node("Layout/Notices").text
	state.call(40, "idle")
	await _frames(2)
	var others := attention.waiting_sessions()
	var message := "Claude Code needs you to sign in again: run /login in its terminal."
	store.apply({"type": "session.notice", "session": "h1", "seq": 41, "notice": {"code": "sign_in_needed", "message": message}})
	state.call(42, "waiting", "sign_in")
	await _frames(2)
	_check(notices.call().contains(message), "sign-in: the provider's notice shows as it sent it")
	_check(panel.status_text() == "Waiting for you to sign in, in the terminal.", "sign-in: the status points to the terminal")
	_check(marker.shown() == "waiting" and marker.beacon_on() and attention.waiting_sessions() == others + 1, "sign-in: the orchestrator shows the \"!\" and the attention cue")
	store.apply({"type": "session.notice_cleared", "session": "h1", "seq": 43, "code": "sign_in_needed"})
	state.call(44, "idle")
	await _frames(2)
	_check(not notices.call().contains(message) and notices.call().contains("(/clear)"), "sign-in: cleared, only that notice goes")
	_check(panel.status_text() == "" and not marker.beacon_on() and attention.waiting_sessions() == others, "sign-in: no wait, no cue")
	store.apply({"type": "session.notice_cleared", "session": "h1", "seq": 45, "code": "sign_in_needed"})
	_check(notices.call().contains("(/clear)"), "sign-in: clearing a notice that isn't there changes nothing")
	state.call(46, "error", "rate_limit")
	_check(panel.status_text().begins_with("Stopped: a usage or rate limit"), "a failed turn says what stopped it")
	state.call(47, "error", "overloaded")
	_check(panel.status_text().contains("overloaded"), "and another reason its own")
	state.call(48, "error", "unknown")
	_check(panel.status_text() == "Stopped.", "an unknown reason says only Stopped.")
	state.call(49, was["state"], was.get("reason"))
	await _frames(2)


# A05: h1's orchestrator waits on a permission; h2's comes and goes.
func _attention(world: Node3D) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var attention: Attention = world.attention
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	# Never the developer's own settings file, nor another run's.
	attention.settings_path = "user://world_test_settings_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(attention.settings_path))
	var focused := [true]
	var asked := [0]
	var chimes := [0]
	attention.is_focused = func() -> bool: return focused[0]
	attention.request_attention = func() -> void: asked[0] += 1
	attention.play_chime = func() -> void: chimes[0] += 1
	attention.sound_on = true
	var h1: AgentStateMarker = islands.orchestrator("h1").get_node("StateMarker")
	var h2: AgentStateMarker = islands.orchestrator("h2").get_node("StateMarker")
	var state := func(seq: int, to: String, reason: Variant = null) -> void:
		store.apply({"type": "agent.state_changed", "session": "h2", "seq": seq, "agent": "main", "state": to, "reason": reason})
	_check(attention.count_text() == "1 session waiting" and h1.beacon_on() and not h2.beacon_on(), "attention: a waiting agent has a beacon, and the corner counts it")
	state.call(3, "waiting", "permission")
	await _frames(2)
	_check(attention.count_text() == "2 sessions waiting" and h2.beacon_on(), "attention: counted by session")
	_check(asked[0] == 0 and chimes[0] == 0, "attention: in the game, no flash and no chime")
	var beacon: AttentionBeacon = h2.get_node("Beacon")
	_check(beacon.visible, "attention: the beacon shows")
	state.call(4, "working")
	await _frames(2)
	_check(attention.count_text() == "1 session waiting" and not h2.beacon_on(), "attention: it goes when the agent stops waiting")
	await _until(func() -> bool: return not beacon.visible, 3.0)
	_check(not beacon.visible, "attention: the beacon fades out")
	focused[0] = false
	state.call(5, "waiting", "question")
	_check(asked[0] == 1 and chimes[0] == 1, "attention: in another window, a new wait flashes the window and chimes")
	state.call(6, "waiting", "permission")
	_check(asked[0] == 1 and chimes[0] == 1, "attention: once per wait")
	var arriving := _snapshot("h5")
	arriving["agents"][0]["state"] = "waiting"
	arriving["agents"][0]["reason"] = "permission"
	store.apply({"type": "session.snapshot", "session": arriving})
	_check(attention.count_text() == "3 sessions waiting" and asked[0] == 2, "attention: a session that arrives waiting counts, and flashes")
	store.apply({"type": "session.ended", "session": "h5", "seq": 2, "reason": "exited"})
	_check(attention.count_text() == "2 sessions waiting", "attention: an ended session isn't counted")
	asked[0] = 1
	chimes[0] = 1
	menu.open()
	_check(menu.sound_toggle().visible and menu.sound_toggle().button_pressed, "attention: the sessions menu has the sound toggle, on")
	menu.sound_toggle().button_pressed = false
	menu.close()
	_check(not attention.sound_on, "attention: the toggle turns the chime off")
	state.call(7, "working")
	state.call(8, "waiting", "permission")
	_check(asked[0] == 2 and chimes[0] == 1, "attention: with the sound off, only the flash")
	var chime: AudioStream = load(Attention.CHIME) if ResourceLoader.exists(Attention.CHIME) else null
	_check(chime != null and chime.get_length() > 0.0, "attention: the chime's file is there and loads")
	var again := Attention.new()
	again.settings_path = attention.settings_path
	again.setup(SessionStore.new())
	_check(not again.sound_on, "attention: the sound setting is kept between runs")
	again.free()
	attention.sound_on = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(attention.settings_path))
	focused[0] = true
	state.call(9, "idle")
	await _frames(1)


# S05: closing the window with sessions h1 and h2 running asks first.
# W06's big map, with two sessions' islands (h1, h2) in the world: M opens
# it, it zooms and moves, a drag isn't a click, clicking h2's island takes
# you there, M and Esc close it.
func _big_map(world: Node3D, player: Player, islands: SessionIslands) -> void:
	var big: WorldMap = world.world_map
	_press("minimap")
	await _until(func() -> bool: return big.is_open(), 2.0)
	await _settle()
	_check(big.is_open() and not player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "M opens the big map, stops you and frees the mouse")
	_check(world.minimap.shown_cluster() == "", "the minimap hides while it's open")
	_check(big.to_map(player.global_position).is_equal_approx(big.map_rect().size / 2.0) and big.map_rect().size.x > 0.0, "it opens centred on you")
	var fit: Rect2 = world.minimap.fit_area()
	_check(is_equal_approx(big.zoom, clampf(minf(big.map_rect().size.x / fit.size.x, big.map_rect().size.y / fit.size.y), big.min_zoom(), WorldMap.MAX_ZOOM)), "at the minimap's scale")
	var at := Vector2(3, 4)
	var held := big.to_world(at)
	var zoom := big.zoom
	big.zoom_by(1.0, at)
	_check(is_equal_approx(big.zoom, zoom * WorldMap.ZOOM_STEP) and big.to_world(at).is_equal_approx(held), "the wheel zooms, keeping the point under the pointer still")
	big.zoom_by(100.0, at)
	_check(big.zoom == WorldMap.MAX_ZOOM, "up to its closest zoom")
	# Zooming out about the islands' middle.
	var middle := (islands.island("h1").global_position + islands.island("h2").global_position) / 2.0
	big.centre = Vector2(middle.x, middle.z)
	big.zoom_by(-100.0, big.map_rect().size / 2.0)
	var view := Rect2(Vector2.ZERO, big.map_rect().size)
	_check(big.zoom <= WorldMap.MIN_ZOOM and view.has_point(big.to_map(islands.island("h1").global_position)) and view.has_point(big.to_map(islands.island("h2").global_position)), "and out until every island fits")
	var centre := big.centre
	Input.action_press("move_right")
	await _settle()
	await _settle()
	Input.action_release("move_right")
	_check(big.centre.x > centre.x and is_equal_approx(big.centre.y, centre.y), "D moves the view east")
	# A drag: press, move past the click slop, let go.
	centre = big.centre
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(5, 5)))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(15, 5)
	motion.relative = Vector2(10, 0)
	big._on_map_input(motion)
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(15, 5)))
	_check(big.is_open() and is_equal_approx(big.centre.x, centre.x - 10.0 / big.zoom), "dragging moves the map, and isn't a click")
	var target := islands.island("h2")
	big.centre = Vector2(target.global_position.x, target.global_position.z)
	var spot := big.to_map(target.global_position)
	_check(big.session_at(spot) == "h2" and big.session_at(spot + Vector2(1000, 1000)) == "", "it knows which session's island is under the pointer")
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, true, spot))
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, false, spot + Vector2(2, 0)))
	await _frames(20)
	# (Headless, the mouse can't be captured: Input.mouse_mode stays visible.)
	_check(not big.is_open() and player.controls_enabled, "clicking an island closes the map, giving the controls back")
	_check(player.global_position.distance_to(islands.orchestrator("h2").global_position) < 7.0, "and takes you there")
	big.open()
	_press("ui_cancel")
	await _settle()
	_check(not big.is_open() and player.controls_enabled, "Esc closes it")
	big.open()
	_press("minimap")
	await _settle()
	_check(not big.is_open() and player.controls_enabled, "and so does M")


func _mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	return event


func _quit(world: Node3D, player: Player) -> void:
	var guard: QuitGuard = world.quit_guard
	var quits := [0]
	guard.quit = func() -> void: quits[0] += 1
	var mouse := Input.mouse_mode
	guard.request_quit()
	await _settle()
	var text := guard.shown_text()
	_check(guard.is_asking() and quits[0] == 0, "quit: with sessions running, it asks first")
	_check(text.begins_with("2 sessions are still running") and text.count("demo") == 2 and text.contains("/exit"), "quit: listing them, and how to end them")
	_check(not player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "quit: the mouse is free to answer")
	world.store.apply({"type": "agent.state_changed", "session": "h1", "seq": 50, "agent": "main", "state": "working", "reason": null})
	_check(guard.shown_text().contains("working"), "quit: the list follows what they're doing")
	world.store.apply({"type": "agent.state_changed", "session": "h1", "seq": 51, "agent": "main", "state": "idle", "reason": null})
	guard.dialog().get_cancel_button().pressed.emit()
	await _frames(1)
	_check(not guard.is_asking() and quits[0] == 0 and player.controls_enabled and Input.mouse_mode == mouse, "quit: back to the game, as it was")
	guard.request_quit()
	guard.dialog().get_ok_button().pressed.emit()
	_check(quits[0] == 1, "quit: Quit quits")
	var empty := QuitGuard.new()
	empty.store = SessionStore.new()
	empty.quit = func() -> void: quits[0] += 10
	empty.request_quit()
	_check(quits[0] == 11, "quit: with no session running, it just quits")
	empty.free()
	await _quit_many(player)


# S05: with more sessions than the window can list, the list scrolls and
# the buttons stay on screen. In a window too short for even the header
# and the hint, the buttons still do. (The test window is 64x64, too
# narrow for the buttons, so the window is resized here.)
func _quit_many(player: Player) -> void:
	var store := SessionStore.new()
	for i in 64:
		var snap := _snapshot("m%d" % i)
		snap["title"] = "Session number %d with a fairly long title" % i
		store.apply({"type": "session.snapshot", "session": snap})
	var guard := QuitGuard.new()
	guard.quit = func() -> void: pass
	get_root().add_child(guard)
	guard.setup(store, player)
	var window := get_root()
	var before := window.size
	for size: Vector2i in [Vector2i(1152, 648), Vector2i(640, 360), Vector2i(320, 180)]:
		window.size = size
		guard.request_quit()
		await _settle()
		var room := Rect2(Vector2.ZERO, window.get_visible_rect().size)
		var d := guard.dialog()
		var on_screen := [d.get_ok_button(), d.get_cancel_button()].all(func(b: Button) -> bool:
			return b.is_visible_in_tree() and room.encloses(Rect2(Vector2(d.position) + b.get_global_rect().position, b.size)))
		_check(on_screen, "quit: with 64 sessions, Quit and Back to the game are on screen (%dx%d)" % [size.x, size.y])
		if size.y >= 360:
			var bar := guard.list_scroll().get_v_scroll_bar()
			_check(bar.page > 0 and bar.max_value > bar.page and guard.shown_text().contains("/exit"), "quit: the list scrolls, and the hint still shows (%dx%d)" % [size.x, size.y])
		d.get_cancel_button().pressed.emit()
		await _settle()
	window.size = before
	guard.free()


# C05: the card for permission prompts and questions, on session h1 (which
# the sidecar doesn't have, so its answers are refused).
func _card(store: SessionStore, panel: ChatPanel) -> void:
	var card := panel.pending_card()
	_check(not card.visible, "card: hidden with nothing pending")
	store.apply({"type": "permission.requested", "session": "h1", "seq": 12, "permission": {
		"permission": "p1", "agent": "main", "tool": "Bash", "summary": "Run: [b]rm[/b] x", "input": {"command": "rm x"}}})
	var sub := _agent("s1", "main", "working")
	sub["name"] = "Explore"
	store.apply({"type": "agent.spawned", "session": "h1", "seq": 13, "agent": sub})
	store.apply({"type": "question.asked", "session": "h1", "seq": 14, "question": {"question": "q1", "agent": "s1", "items": [
		{"text": "Which fruit?", "header": "Fruit", "multi_select": false, "options": [{"label": "Apple", "description": "Crisp"}, {"label": "Banana"}]},
		{"text": "What goes with it?", "multi_select": true, "options": [{"label": "Honey"}, {"label": "Nuts"}]},
	]}})
	_check(card.visible and card.header_text() == "The orchestrator asks to use Bash:" and card.count_text() == "1 of 2 waiting", "card: the oldest request first, with how many wait")
	var buttons := card.find_children("*", "Button", true, false)
	_check(buttons.map(func(b: Button) -> String: return b.text) == ["Details", "Yes", "No", "Send"], "card: Yes and No, one per line, without options")
	var yes: Button = buttons[1]
	_check(yes.focus_mode == Control.FOCUS_NONE, "card: no key can press Yes")
	_check(card.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Run: [b]rm[/b] x"), "card: the summary is shown as written")
	_check(not _note(card).editable and _button(card, "Send").disabled, "card: the note and Send are locked until No")
	_click(card, "No")
	_check(card.denying() and _note(card).editable and not _button(card, "Send").disabled and card.error_text() == "", "card: No unlocks the note and Send, and answers nothing")
	card.set_note("not that one")
	_click(card, "Yes")
	await _until(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer") and card.current()["kind"] == "permission", "card: a refused answer says so and stays")
	_check(not card.denying() and not _note(card).editable and _note(card).text == "not that one", "card: Yes locks the note again, keeping it")
	_click(card, "No")
	_check(_note(card).text == "not that one", "card: No again, the note is still there")
	_click(card, "Send")
	await _until(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer"), "card: Send denies")
	store.apply({"type": "permission.resolved", "session": "h1", "seq": 15, "permission": "p1", "decision": "allow", "by": "external"})
	_check(card.header_text() == "Subagent Explore asks:" and card.count_text() == "" and card.error_text() == "", "card: answered in the terminal, the next one shows, naming its agent")
	_check(card.step() == 0, "card: questions start at the first item")
	card.next()
	_check(card.step() == 0, "card: no Next before an answer")
	_click(card, "Banana")
	_check(card.step() == 1, "card: a single choice moves straight on")
	card.choose("Honey")
	card.choose("Nuts")
	card.choose("Honey")
	_check(card.step() == 1, "card: checkboxes don't move on")
	_click(card, "Back")
	card.set_other("Mango")
	card.next()
	_check(card.step() == 1, "card: Back, your own words, then Next")
	panel.close()
	panel.open("h1")
	_check(panel.pending_card().step() == 1, "card: progress survives closing the chat")
	card.send_answers()
	await _until(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer"), "card: Send on the last item")
	store.apply({"type": "question.resolved", "session": "h1", "seq": 16, "question": "q1", "by": "external"})
	_check(not card.visible, "card: hidden again when nothing waits")
	_modes_and_plans(store, panel)


# C08: context and totals in the chat's header, each turn's tokens at its
# end, and the plan's limits in the corner.
func _usage(world: Node3D, store: SessionStore, panel: ChatPanel) -> void:
	var corner: UsageLimits = world.usage_limits
	_check(panel.usage_text() == "" and panel.turn_hints().is_empty() and corner.text() == "", "usage: nothing shown without it")
	var snap := store.session("h1").duplicate(true)
	snap["seq"] = 40
	snap["capabilities"]["usage"] = {}
	snap["usage"] = null
	store.apply({"type": "session.snapshot", "session": snap})
	_check(panel.usage_text() == "", "usage: none before the first count")
	var usage := {
		"tokens": {"input": 40, "output": 1234, "cache_read": 52000, "cache_write": 9000},
		"context": {"tokens": 61040, "percent": 31, "window": 200000},
		"turn": {"message": "uu1", "output_tokens": 1234}, "limits": [],
	}
	var say := func(id: String, role: String, seq: int) -> void:
		store.apply({"type": "message.started", "session": "h1", "seq": seq, "message": id, "agent": "main", "role": role})
		store.apply({"type": "message.completed", "session": "h1", "seq": seq + 1, "message": id, "text": id})
	say.call("uu1", "user", 41)
	say.call("ua1", "assistant", 43)
	store.apply({"type": "usage.updated", "session": "h1", "seq": 45, "usage": usage.duplicate(true)})
	_check(panel.usage_text() == "Context 31% · ↑ 61k in · ↓ 1.2k out", "usage: context and totals in the header")
	_check(panel.get_node("Layout/Header/Usage").tooltip_text.contains("Cache reads: 52,000"), "usage: the exact figures on hover")
	_check(panel.turn_hints() == [["ua1", "↓ 1.2k tokens"]], "usage: the turn's tokens at its end")
	say.call("uu2", "user", 46)
	usage["turn"] = {"message": "uu2", "output_tokens": 0}
	store.apply({"type": "usage.updated", "session": "h1", "seq": 48, "usage": usage.duplicate(true)})
	_check(panel.turn_hints() == [["ua1", "↓ 1.2k tokens"]], "usage: a new turn has none until it counts")
	usage["turn"]["output_tokens"] = 480
	store.apply({"type": "usage.updated", "session": "h1", "seq": 49, "usage": usage.duplicate(true)})
	_check(panel.turn_hints() == [["ua1", "↓ 1.2k tokens"], ["uu2", "↓ 480 tokens"]], "usage: it goes up while working")
	say.call("ua2", "assistant", 50)
	usage["turn"]["output_tokens"] = 2600
	usage["context"] = {"tokens": 64000, "percent": null, "window": null}
	store.apply({"type": "usage.updated", "session": "h1", "seq": 52, "usage": usage.duplicate(true)})
	_check(panel.turn_hints() == [["ua1", "↓ 1.2k tokens"], ["ua2", "↓ 2.6k tokens"]], "usage: and stays at the turn's end")
	_check(panel.usage_text().begins_with("Context 64k · "), "usage: without a %, the context in tokens")
	panel.close()
	panel.open("h1")
	await _until(func() -> bool: return not panel.is_loading(), 3.0)
	_check(panel.turn_hints() == [["ua1", "↓ 1.2k tokens"], ["ua2", "↓ 2.6k tokens"]] and panel.usage_text() != "", "usage: laid out again on opening")

	# The plan's limits: once, the latest across sessions, hidden once over.
	var now := SessionStore.unix_time("2026-10-08T12:00:00Z")
	corner.now = func() -> float: return now
	var five := {"id": "five_hour", "label": "5-hour", "used_percent": 74, "resets_at": "2026-10-08T13:00:00.000Z"}
	var week := {"id": "seven_day", "label": "Weekly", "used_percent": 94, "resets_at": "2026-10-10T09:00:00.000Z"}
	usage["limits"] = [five]
	store.apply({"type": "usage.updated", "session": "h1", "seq": 53, "usage": usage.duplicate(true)})
	_check(corner.text().begins_with("5-hour 74% · resets "), "usage: the 5-hour limit in the corner")
	var other := store.session("h2").duplicate(true)
	other["seq"] = 40
	other["usage"] = {"tokens": usage["tokens"], "context": null, "turn": {"message": null, "output_tokens": 0},
		"limits": [five.merged({"used_percent": 76}, true), week]}
	store.apply({"type": "session.snapshot", "session": other})
	_check(corner.text().begins_with("5-hour 76%") and corner.text().contains("   Weekly 94% · resets "), "usage: the latest figures across sessions, both limits")
	# Each provider's limits are its own account's: a line each, named.
	var offered := corner.providers
	corner.providers = func() -> Array: return [{"provider": "fake", "name": "Fake"}, {"provider": "codex", "name": "Codex"}]
	other["seq"] = 41
	other["provider"] = "codex" # never changes for real: refreshed by hand
	store.apply({"type": "session.snapshot", "session": other.duplicate(true)})
	corner.refresh()
	var lines := corner.text().split("\n")
	_check(lines.size() == 2 and lines[0].begins_with("Fake: 5-hour 74% · resets ") and not lines[0].contains("Weekly")
		and lines[1].begins_with("Codex: 5-hour 76% · resets ") and lines[1].contains("   Weekly 94% · resets "), "usage: a line per provider, named: %s" % [lines])
	await process_frame
	await process_frame
	var label: Label = corner.get_node("Limits")
	var bottom := label.get_viewport_rect().size.y - 12.0
	_check(label.size.y >= label.get_combined_minimum_size().y and label.size.y > 28.0 and is_equal_approx(label.get_rect().end.y, bottom),
		"usage: more lines grow upwards from the corner: %s in %s" % [label.get_rect(), label.get_viewport_rect()])
	corner.providers = func() -> Array: return [{"provider": "fake", "name": "Fake"}]
	corner.refresh()
	_check(corner.text().split("\n")[1].begins_with("codex: 5-hour 76%"), "usage: a provider the sidecar doesn't list by its id")
	other["seq"] = 42
	other["provider"] = "fake"
	store.apply({"type": "session.snapshot", "session": other.duplicate(true)})
	corner.refresh()
	_check(corner.text().begins_with("5-hour 76%") and not corner.text().contains("\n"), "usage: one provider: one line, unnamed")
	corner.providers = offered
	var later := SessionStore.unix_time("2026-10-08T13:00:01Z")
	corner.now = func() -> float: return later
	corner.refresh()
	_check(corner.text().begins_with("Weekly 94%"), "usage: a limit past its reset is hidden")
	var after := SessionStore.unix_time("2026-10-11T00:00:00Z")
	corner.now = func() -> float: return after
	corner.refresh()
	_check(corner.text() == "", "usage: none once every window is over")
	# The provider's own words, in its order, as plain text (untrusted).
	corner.now = func() -> float: return now
	other["seq"] = 43
	other["usage"]["limits"] = [week.merged({"label": "[b]Weekly[/b]"}, true), five.merged({"id": "daily", "label": "Today"}, true)]
	store.apply({"type": "session.snapshot", "session": other.duplicate(true)})
	_check(corner.text().begins_with("[b]Weekly[/b] 94% · resets ") and corner.text().contains("   Today 74% · resets ") and not corner.text().contains("5-hour 76"),
		"usage: the provider's labels and order, shown as they are: %s" % corner.text())
	corner.now = func() -> float: return Time.get_unix_time_from_system()


# Records the commands sent and refuses each, so a card can be clicked again.
class _Recorder extends SidecarClient:
	var sent := []

	func send_command(type: String, fields: Dictionary = {}, on_reply := Callable()) -> String:
		sent.append([type, fields])
		if on_reply.is_valid():
			on_reply.call({"type": "error", "message": "recorded"})
		return "r%d" % sent.size()


# C06 and C07: the mode in the header, a plan in the chat and on the card;
# C05: a permission's other ways to allow (its options).
func _modes_and_plans(store: SessionStore, panel: ChatPanel) -> void:
	var card := panel.pending_card()
	_check(panel.mode_text() == "", "modes: no mode shown without permission_modes")
	var snap := store.session("h1").duplicate(true)
	snap["seq"] = 17
	snap["capabilities"] = {"permission_modes": {}, "plans": {}}
	snap["mode"] = null
	store.apply({"type": "session.snapshot", "session": snap})
	_check(panel.mode_text() == "", "modes: none shown while it isn't known")
	store.apply({"type": "session.updated", "session": "h1", "seq": 18, "mode": "default"})
	_check(panel.mode_text() == "Mode: Manual", "modes: the header shows the mode in our words")
	store.apply({"type": "session.updated", "session": "h1", "seq": 19, "mode": "acceptEdits"})
	_check(panel.mode_text() == "Mode: Accept edits", "modes: and follows it")
	store.apply({"type": "session.updated", "session": "h1", "seq": 20, "mode": "someNewMode"})
	_check(panel.mode_text() == "Mode: someNewMode", "modes: an unknown mode shows as its id")
	store.apply({"type": "session.updated", "session": "h1", "seq": 21, "mode": "plan"})

	var recorder := _Recorder.new()
	var real := card.sidecar
	card.sidecar = recorder
	store.apply({"type": "message.started", "session": "h1", "seq": 22, "message": "plan1", "agent": "main", "role": "assistant", "kind": "plan"})
	store.apply({"type": "message.completed", "session": "h1", "seq": 23, "message": "plan1", "text": "# The plan\n\n1. Do [b]this[/b]"})
	var plan_shown: String = panel.shown_messages().back()
	_check(plan_shown.begins_with("The plan\n") and plan_shown.contains("Do [b]this[/b]"),"plans: the plan is a message, rendered as Markdown")
	var line: HBoxContainer = panel._messages.get_children().back().get_child(0)
	_check(line.get_child_count() == 1 and line.get_child(0).find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Plan"), "plans: full width, marked as a plan")
	store.apply({"type": "plan.asked", "session": "h1", "seq": 24, "plan": {"plan": "x1", "agent": "main", "text": "# The plan", "modes": ["auto", "default"]}})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 25, "agent": "main", "state": "waiting", "reason": "plan"})
	_check(panel.status_text().contains("approve the plan") and panel.status_text().contains("terminal"), "plans: the status points to the card and the terminal")
	_check(card.visible and card.header_text() == "The orchestrator has a plan for you to approve:", "plans: the card asks")
	var texts: Array = card.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	_check(texts == ["Yes, and use auto mode", "Yes, manually approve edits", "No, keep planning", "Send"], "plans: its choices in the provider's order")
	_check(card.find_children("*", "Button", true, false).all(func(b: Button) -> bool: return b.focus_mode == Control.FOCUS_NONE), "plans: no key can press them")
	_click(card, "Yes, and use auto mode")
	_check(recorder.sent.back() == ["plan.answer", {"session": "h1", "plan": "x1", "approve": true, "mode": "auto"}], "plans: approving sends the mode")
	_check(not _note(card).editable and _button(card, "Send").disabled, "plans: the note is locked until \"No, keep planning\"")
	_click(card, "No, keep planning")
	_check(card.denying() and _note(card).editable and not _button(card, "Send").disabled, "plans: \"No, keep planning\" unlocks it")
	_click(card, "Send")
	_check(recorder.sent.back() == ["plan.answer", {"session": "h1", "plan": "x1", "approve": false}], "plans: Send without a note")
	card.set_note("  smaller steps ")
	_click(card, "Send")
	_check(recorder.sent.back() == ["plan.answer", {"session": "h1", "plan": "x1", "approve": false, "note": "smaller steps"}], "plans: Send with the note")
	card.approve_plan("acceptEdits")
	_check(recorder.sent.size() == 3, "plans: a mode the plan doesn't offer isn't sent")
	store.apply({"type": "plan.resolved", "session": "h1", "seq": 26, "plan": "x1", "decision": "rejected", "by": "app"})
	store.apply({"type": "plan.asked", "session": "h1", "seq": 27, "plan": {"plan": "x2", "agent": "main", "text": "# Again", "modes": ["acceptEdits", "default"]}})
	texts = card.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	_check(texts[0] == "Yes, auto-accept edits" and card.error_text() == "" and not card.denying(), "plans: without auto, the terminal's other words; a fresh card")
	store.apply({"type": "plan.resolved", "session": "h1", "seq": 28, "plan": "x2", "decision": "approved", "by": "external"})
	_check(not card.visible, "plans: answered in the terminal, the card goes")
	_check(panel.shown_messages().back().begins_with("The plan"), "plans: the plan stays in the chat")

	var dont_ask := "Yes, and don't ask again for: npm test [b]*[/b]"
	store.apply({"type": "permission.requested", "session": "h1", "seq": 29, "permission": {
		"permission": "p5", "agent": "main", "tool": "Bash", "summary": "Run: npm test", "options": [
			{"option": "suggested", "label": dont_ask}, {"option": "auto", "label": "Yes, and switch to auto mode"}]}})
	var choices := card.find_children("*", "Button", true, false)
	_check(choices.map(func(b: Button) -> String: return b.text) == ["Yes", dont_ask, "Yes, and switch to auto mode", "No", "Send"], "options: one per line between Yes and No, in the provider's order and words, as written")
	_check(choices.all(func(b: Button) -> bool: return b.focus_mode == Control.FOCUS_NONE), "options: by click only")
	var option_line: Button = choices[1]
	_check(option_line.autowrap_mode != TextServer.AUTOWRAP_OFF and option_line.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "options: a long label wraps across the card")
	_click(card, "Yes, and switch to auto mode")
	_check(recorder.sent.back() == ["permission.respond", {"session": "h1", "permission": "p5", "decision": "allow", "option": "auto"}], "options: one sends its id")
	_click(card, dont_ask)
	_check(recorder.sent.back() == ["permission.respond", {"session": "h1", "permission": "p5", "decision": "allow", "option": "suggested"}], "options: each its own")
	_click(card, "No")
	card.set_note("never sent")
	_click(card, "Yes")
	_check(recorder.sent.back() == ["permission.respond", {"session": "h1", "permission": "p5", "decision": "allow"}], "options: plain Yes sends none, and never the note")
	card.respond("allow", "default")
	_check(recorder.sent.size() == 6, "options: one the prompt doesn't offer isn't sent")
	store.apply({"type": "permission.resolved", "session": "h1", "seq": 30, "permission": "p5", "decision": "allow", "by": "app"})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 31, "agent": "main", "state": "waiting", "reason": "permission"})
	card.sidecar = real
	recorder.free()


func _button(card: PendingCard, text: String) -> BaseButton:
	for b: BaseButton in card.find_children("*", "BaseButton", true, false):
		if b.text == text:
			return b
	return null


func _note(card: PendingCard) -> LineEdit:
	return card.find_children("*", "LineEdit", true, false)[0]


# Clicks a card's button by its text, through its signal like a real click
# (the card lays itself out again from inside it).
func _click(card: PendingCard, text: String) -> void:
	for b: BaseButton in card.find_children("*", "BaseButton", true, false):
		if b.text == text:
			if b.toggle_mode:
				b.button_pressed = not b.button_pressed
			b.pressed.emit()
			return
	_check(false, "card: no button \"%s\"" % text)


func _agent(id: String, parent: String, state: String) -> Dictionary:
	return {"agent": id, "role": "subagent", "parent": parent, "name": "Explore", "task": "t", "state": state, "reason": null}


# Subagents applied to the store by hand.
func _agents(world: Node3D) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var snap := _snapshot("h4")
	snap["agents"][0]["state"] = "working"
	snap["agents"].append(_agent("old", "main", "done"))
	snap["agents"].append(_agent("s0", "main", "working"))
	store.apply({"type": "session.snapshot", "session": snap})
	await _frames(2)
	_check(store.activity("h4") == "working", "activity: working")
	var agents := islands.agents("h4")
	var island := islands.island("h4")
	var orchestrator := islands.orchestrator("h4")
	agents.error_linger = 0.5
	_check(orchestrator.get_node("StateMarker").shown() == "working", "agents: the orchestrator's marker shows it working")
	_check(agents.subagent("old") == null and agents.subagent("s0") != null, "agents: a finished one isn't shown, a working one is")
	_check(agents.subagent("s0").shown_state() == "working", "agents: with its marker")

	store.apply({"type": "agent.spawned", "session": "h4", "seq": 2, "agent": _agent("s1", "main", "working")})
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 3, "agent": _agent("s2", "s1", "working")})
	await _frames(20)
	var nodes: Array = ["s0", "s1", "s2"].map(func(a: String) -> Subagent: return agents.subagent(a))
	_check(nodes.all(func(n: Subagent) -> bool: return n != null) and agents.subagent_count() == 3, "agents: a spawned one appears")
	var slots := {}
	var placed := true
	for n: Subagent in nodes:
		slots[n.slot] = true
		var p := n.position
		var inward := Vector3(-p.x, 0, -p.z).normalized()
		var forward := n.global_basis.z
		placed = placed and Vector2(p.x, p.z).length() > 9.0 and absf(p.y - island.height_at(p.x, p.z)) < 0.6
		placed = placed and forward.dot(inward) > 0.9 and n.worker_position().distance_to(n.global_position) < 0.01
	_check(slots.size() == 3, "agents: each at its own slot")
	_check(placed, "agents: around the orchestrator, on the sand, facing it")

	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 4, "agent": "s1", "state": "waiting", "reason": "permission"})
	_check(agents.subagent("s1").shown_state() == "waiting", "agents: waiting on you shows the \"!\"")

	# Done: walks its report to its parent (s1, still at its PC), then goes.
	var s1 := agents.subagent("s1")
	var s2 := agents.subagent("s2")
	var s2_slot := s2.slot
	var start := s2.worker_position().distance_to(s1.worker_position())
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 5, "agent": "s2", "state": "done", "reason": null})
	_check(s2.is_leaving() and s2.get_node("Worker/Paper").visible and s2.shown_state() == "", "agents: a done one gets up with its paper")
	await _frames(15)
	_check(s2.worker_position().distance_to(s1.worker_position()) < start - 0.5, "agents: and walks to whoever called it")
	await _until(func() -> bool: return agents.subagent("s2") == null, 3.0)
	_check(agents.subagent("s2") == null and agents.subagent_count() == 2, "agents: and is gone once there (not only after giving up)")
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 6, "agent": _agent("s3", "main", "working")})
	_check(agents.subagent("s3").slot == s2_slot, "agents: a freed slot is reused")

	# Resumed while walking back: back at its PC.
	var s3 := agents.subagent("s3")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 7, "agent": "s3", "state": "done", "reason": null})
	await _frames(10)
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 8, "agent": "s3", "state": "working", "reason": null})
	await _frames(30)
	_check(agents.subagent("s3") == s3 and not s3.is_leaving() and s3.worker_position().distance_to(s3.global_position) < 0.01, "agents: resumed on the way back, it returns to its PC")

	# Error: stays in red for a while, then goes; resumed later, it comes back to its slot.
	var s1_slot := s1.slot
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 9, "agent": "s1", "state": "error", "reason": "interrupted"})
	_check(s1.shown_state() == "error", "agents: an error shows the \"×\"")
	await _frames(10)
	_check(agents.subagent("s1") == s1, "agents: and it stays a while")
	await _until(func() -> bool: return agents.subagent("s1") == null, 5.0)
	_check(agents.subagent("s1") == null, "agents: then goes")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 10, "agent": "s1", "state": "working", "reason": null})
	_check(agents.subagent("s1") != null and agents.subagent("s1").slot == s1_slot, "agents: resumed later, it comes back to its slot")

	# Walks to the orchestrator, 10+ m away, in about 4 s: every one of
	# them gets there (a walk that never quite arrives gives up only
	# after 20 s).
	for a in ["s0", "s1", "s3"]:
		store.apply({"type": "agent.state_changed", "session": "h4", "seq": 11, "agent": a, "state": "done", "reason": null})
	await _until(func() -> bool: return agents.subagent_count() == 0, 8.0)
	_check(agents.subagent_count() == 0, "agents: all walk to the orchestrator and go (%d left)" % agents.subagent_count())

	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 12, "agent": "main", "state": "idle", "reason": null})
	_check(store.activity("h4") == "idle", "activity: idle once everyone is done")
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 20, "agent": _agent("s9", "main", "working")})
	_check(store.activity("h4") == "working", "activity: an idle orchestrator waiting on a subagent counts as working")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 21, "agent": "s9", "state": "waiting", "reason": "permission"})
	_check(store.activity("h4") == "waiting" and SessionsMenu.state_text(store.activity("h4")) == "waiting for you", "activity: a subagent waiting on you")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 22, "agent": "s9", "state": "done", "reason": null})
	await _until(func() -> bool: return agents.subagent_count() == 0, 8.0)
	_check(orchestrator.get_node("StateMarker").shown() == "", "agents: an idle orchestrator shows no marker")
	store.apply({"type": "session.ended", "session": "h4", "seq": 13, "reason": "exited"})
	await _frames(2)


# With the fake provider: start a session from the menu and chat with it,
# then resume a stored one.
func _live(world: Node3D, player: Player) -> void:
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	var islands: SessionIslands = world.get_node("SessionIslands")
	var chat: ChatController = world.get_node("ChatController")
	var sidecar: SidecarClient = root.get_node("Sidecar")
	# The real way in: Tab, Add session, New session, the picker's own
	# "select" button.
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	menu.choose("+ Add session")
	menu.choose("+ New session")
	await _frames(2)
	menu.picker().current_dir = OS.get_user_data_dir()
	await _frames(2)
	menu.picker().get_ok_button().pressed.emit()
	await _frames(2)
	_check(not menu.is_open() and not menu.picker().visible, "live: choosing a folder closes the picker and the menu")
	_check(player.controls_enabled, "live: and gives the controls back (headless has no mouse to check)")
	await _until(func() -> bool: return not world.store.sessions.is_empty(), 5.0)
	var id: String = world.store.sessions.keys()[0]
	await _frames(20)
	var orchestrator := islands.orchestrator(id)
	_check(orchestrator != null and menu.notice_text() == "", "live: the session is up, with its island")
	_check(islands.is_rising(id), "live: rising")
	await _until(func() -> bool: return player.global_position.distance_to(orchestrator.global_position) < 7.0, 6.0)
	_check(player.global_position.distance_to(orchestrator.global_position) < 7.0, "live: and once it's up, it takes you there")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.entries()[4].begins_with("New session   ·"), "live: a new session is listed as \"New session\"")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)

	await _until(func() -> bool: return chat.history_loaded(id), 5.0)
	_check(chat.history_loaded(id), "live: its history is loaded")
	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _until(func() -> bool: return chat.prompt_visible(), 2.0)
	_press("interact")
	await _until(func() -> bool: return chat.is_open(), 2.0)
	var panel := chat.panel()
	panel.set_draft("hello\nworld")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages().size() == 2 and panel.shown_messages()[1].contains("fake provider"), 8.0)
	_check(panel.shown_messages()[0] == "hello\nworld", "live: your message in the panel")
	_check(panel.shown_messages().size() == 2 and panel.shown_messages()[1].contains("> world"), "live: the reply streamed into the panel")
	_check(chat.bubble(id).shown_text().ends_with("(This is the fake provider.)"), "live: and into the bubble")
	# S06: a message the session never picks up says so and comes back; the
	# next one that arrives clears it.
	await _until(func() -> bool: return world.store.orchestrator(id).get("state") == "idle", 5.0)
	panel.pickup_timeout = 0.5
	panel.set_draft("lost")
	panel.send()
	_check(panel.draft() == "" and panel.status_text() == "", "live: a message sent, nothing said yet")
	await _until(func() -> bool: return panel.status_text().begins_with("Your message hasn't reached"), 5.0)
	_check(panel.status_text().begins_with("Your message hasn't reached") and panel.draft() == "lost", "live: one never picked up says so, its text back in the box")
	panel.set_draft("hello again")
	panel.send()
	# Your own message arrives before the turn starts: wait for the reply's
	# end, then past the pickup timeout, so a warning would be back by now.
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("> hello again") and panel.shown_messages()[-1].contains("(This is the fake provider.)") and world.store.orchestrator(id).get("state") == "idle", 8.0)
	await create_timer(panel.pickup_timeout + 0.2).timeout
	await _settle()
	_check(panel.status_text() == "" and panel.shown_messages()[-1].contains("hello again"), "live: the next one arrives, and the warning goes")
	# Busy (here, waiting on a permission), the provider queues a message for
	# after its turn: not watched.
	panel.set_draft("permission")
	panel.send()
	await _until(func() -> bool: return not world.store.session(id)["permissions"].is_empty(), 8.0)
	panel.set_draft("lost")
	panel.send()
	await _frames(90)
	_check(panel.status_text().begins_with("Waiting for a permission") and panel.draft() == "", "live: a message sent while busy isn't watched")
	var asked: String = world.store.session(id)["permissions"][0]["permission"]
	sidecar.send_command("permission.respond", {"session": id, "permission": asked, "decision": "deny"}, func(_r: Dictionary) -> void: pass)
	await _until(func() -> bool: return world.store.orchestrator(id).get("state") == "idle", 8.0)
	await _sign_in_pickup(world, chat, id)
	panel.pickup_timeout = 15.0
	_check(world.store.sessions[id].get("title") == "hello", "live: the first message's first line names the session")
	panel.set_draft("rename Tidy the notes")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Renamed"), 8.0)
	_check(world.store.sessions[id].get("title") == "Tidy the notes", "live: renaming it renames it")

	# Subagents: the fake provider spawns them, they work and walk back.
	var agents := islands.agents(id)
	panel.set_draft("agents 3")
	panel.send()
	await _until(func() -> bool: return agents.subagent_count() == 3, 8.0)
	_check(agents.subagent_count() == 3, "live: three subagents appear")
	await _until(func() -> bool: return agents.subagent_count() == 0, 18.0)
	_check(agents.subagent_count() == 0, "live: and all walk back and go when done")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("reported back"), 8.0)
	_check(panel.shown_messages()[-1].contains("reported back"), "live: the orchestrator sums up")
	var order: Array = world.store.session(id)["message_order"]
	var split := panel.tool_fold(order[-2])
	split.set_open(true)
	_check(split.shown_calls().size() == 3 and split.shown_calls().all(func(c: String) -> bool: return c.begins_with("ok Agent:")), "live: an Agent call per subagent in the log")
	var inside := split.inner(world.store.tool_tree(id)["after"][order[-2]][0])
	_check(inside.header_text() == "▸ 3 tool calls", "live: each holding its subagent's calls")

	# C04: a turn with tools, one failing.
	panel.set_draft("tools")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("One test failed"), 8.0)
	order = world.store.session(id)["message_order"]
	_check(panel.tool_fold(order[-2]).header_text() == "▸ 3 tool calls (1 failed)", "live: the tools turn's calls fold after its first message")

	# C05: answering a permission prompt and a question on the card.
	var card := panel.pending_card()
	panel.set_draft("permission")
	panel.send()
	await _until(func() -> bool: return card.visible, 8.0)
	_check(card.visible and card.header_text() == "The orchestrator asks to use Bash:", "live: a permission prompt on the card")
	card.respond("allow")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Installed"), 8.0)
	_check(not card.visible and panel.shown_messages()[-1].contains("Installed"), "live: allowed from the card")
	panel.set_draft("question")
	panel.send()
	await _until(func() -> bool: return card.visible, 8.0)
	card.choose("Banana")
	card.choose("Honey")
	card.choose("Nuts")
	card.send_answers()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("picked"), 8.0)
	_check(not card.visible and panel.shown_messages()[-1].contains("Banana; Honey, Nuts"), "live: a two-item question answered from the card")

	# C06 and C07: the mode in the header, a switch on a prompt (one of its
	# options, C05), a plan.
	_check(panel.mode_text() == "Mode: Auto", "live: the session's mode in the header")
	panel.set_draft("mode")
	panel.send()
	await _until(func() -> bool: return panel.mode_text() == "Mode: Manual", 8.0)
	_check(panel.mode_text() == "Mode: Manual", "live: a mode switch shows")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Now in"), 8.0)
	panel.set_draft("permission")
	panel.send()
	await _until(func() -> bool: return card.visible, 8.0)
	_check(_button(card, "Yes, and don't ask again for: npm install") != null, "live: the prompt's options on the card")
	_click(card, "Yes, and switch to auto mode")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Installed"), 8.0)
	_check(panel.mode_text() == "Mode: Auto" and not card.visible, "live: allowed and switched to auto from the card")
	panel.set_draft("plan")
	panel.send()
	# The plan and the orchestrator's wait are two events.
	await _until(func() -> bool: return card.visible and panel.status_text().contains("approve the plan"), 8.0)
	_check(panel.mode_text() == "Mode: Plan" and card.header_text().contains("plan"), "live: a plan on the card, in plan mode")
	_check(panel.status_text().contains("approve the plan"), "live: the status says so")
	var plan_rows: Array = world.store.messages(id).filter(func(m: Dictionary) -> bool: return m.get("kind") == "plan")
	_check(plan_rows.size() == 1 and panel.shown_messages().any(func(t: String) -> bool: return t.begins_with("Add a dark theme")), "live: the plan is in the chat")
	_click(card, "No, keep planning")
	card.set_note("a high-contrast option")
	_click(card, "Send")
	await _until(func() -> bool: return world.store.messages(id).filter(func(m: Dictionary) -> bool: return m.get("kind") == "plan").size() == 2 and card.visible, 10.0)
	_check(card.visible and panel.shown_messages().any(func(t: String) -> bool: return t.contains("a high-contrast option")), "live: sent back with a note, a revised plan comes")
	_click(card, "Yes, manually approve edits")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("approved"), 8.0)
	_check(not card.visible and panel.mode_text() == "Mode: Manual", "live: approved from the card, in the chosen mode")

	# C08: a heavy turn fills the context and the 5-hour limit; its tokens
	# show at its end.
	var percent := func(text: String, after: String) -> int:
		var at := text.find(after)
		return text.substr(at + after.length()).to_int() if at >= 0 else -1
	_check(panel.usage_text().begins_with("Context ") and world.usage_limits.text().begins_with("5-hour "), "live: usage in the header, limits in the corner")
	panel.set_draft("usage")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages()[-1].begins_with("Done. The context") and world.store.agent(id, "main")["state"] == "idle", 10.0)
	_check(percent.call(panel.usage_text(), "Context ") >= 80, "live: the context fills: %s" % panel.usage_text())
	_check(percent.call(world.usage_limits.text(), "5-hour ") >= 85 and world.usage_limits.text().contains("Weekly "), "live: the 5-hour limit climbs: %s" % world.usage_limits.text())
	var last_hint: Array = panel.turn_hints().back()
	_check(last_hint[0] == world.store.messages(id).back()["message"] and (last_hint[1].begins_with("↓ 10k") or last_hint[1].begins_with("↓ 11k")), "live: the turn's tokens at its end: %s" % [last_hint])
	_press("ui_cancel")
	await _until(func() -> bool: return not chat.is_open(), 2.0)

	# The open menu follows a rename.
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.entries()[4].begins_with("Tidy the notes   ·"), "live: the menu shows its name")
	sidecar.send_command("message.send", {"session": id, "text": "rename Notes"})
	await _until(func() -> bool: return menu.entries()[4].begins_with("Notes   ·"), 5.0)
	_check(menu.entries()[4].begins_with("Notes   ·"), "live: and follows a rename while open")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)

	var ended := islands.island(id)
	sidecar.send_command("session.end", {"session": id})
	await _until(func() -> bool: return islands.island(id) == null, 5.0)
	await _frames(2)
	_check(islands.island(id) == null and not is_instance_valid(orchestrator) and is_instance_valid(ended) and ended.position.y == 0.0, "live: ending it takes its orchestrator; the island stays while you're on it")
	player.respawn()
	var ended_ref: WeakRef = weakref(ended)
	await _until(func() -> bool: return ended_ref.get_ref() == null, 6.0)
	_check(not is_instance_valid(ended), "live: and sinks once you've left")

	# S04: resume a stored session from the menu.
	var is_listed := func(title: String) -> bool:
		return menu.entries().any(func(e: String) -> bool: return e.begins_with(title))
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	var lists_before := menu.listings_asked
	menu.choose("+ Add session")
	_check(menu.listings_asked == lists_before, "live: the menu and Add session don't ask for the stored sessions")
	menu.choose("▸ Resume a session")
	await _until(func() -> bool: return is_listed.call("Add a save system"), 5.0)
	var listed := menu.entries()
	_check(menu.listings_asked == lists_before + 1 and listed.size() == 3 and listed[0].begins_with("Fix the player") and listed[1].begins_with("Add a save system") and listed[1].contains("my-game") and listed[1].ends_with("1 d ago"), "live: Resume lists them newest first, with project and age")
	menu.search("SAVE")
	_check(menu.entries() == [listed[1]], "live: the search filters them")
	menu.choose("Add a save system")
	_check(not menu.is_open() and menu.notice_text() == "Starting…", "live: choosing one resumes it")
	await _until(func() -> bool: return not world.store.sessions.is_empty(), 5.0)
	var resumed: String = world.store.sessions.keys()[0]
	await _until(func() -> bool: return chat.history_loaded(resumed), 5.0)
	await _until(func() -> bool: return islands.orchestrator(resumed) != null and player.global_position.distance_to(islands.orchestrator(resumed).global_position) < 7.0, 6.0)
	_check(islands.orchestrator(resumed) != null and player.global_position.distance_to(islands.orchestrator(resumed).global_position) < 7.0, "live: its island comes back and you're taken there")
	_check(chat.bubble(resumed).shown_text() == "Resumed Add a save system.", "live: with its chat so far")
	chat.open(islands.orchestrator(resumed))
	await _until(func() -> bool: return chat.is_open() and panel.turn_hints().size() == 1 and panel.usage_text() != "", 5.0)
	_check(panel.turn_hints() == [["r2", "↓ 1.8k tokens"]] and panel.usage_text().begins_with("Context 31% · "), "live: and its usage so far: %s %s" % [panel.turn_hints(), panel.usage_text()])
	_press("ui_cancel")
	await _until(func() -> bool: return not chat.is_open(), 2.0)
	_press("sessions_menu")
	await _until(func() -> bool: return menu.entries().size() == 5, 5.0)
	var now := menu.entries()
	_check(now[2] == "Running" and now[3].begins_with("▸ ") and now[4].begins_with("Add a save system"), "live: now under Running, in its cluster")
	menu.choose("+ Add session")
	menu.choose("▸ Resume a session")
	await _until(func() -> bool: return is_listed.call("Fix the player"), 5.0)
	_check(is_listed.call("Fix the player") and not is_listed.call("Add a save system"), "live: and not under Resume")
	_press("ui_cancel")
	_press("ui_cancel")
	await _until(func() -> bool: return menu.page() == SessionsMenu.Page.MAIN, 2.0)
	player.respawn()
	menu.choose("Add a save system")
	await _frames(5)
	_check(not menu.is_open() and player.global_position.distance_to(islands.orchestrator(resumed).global_position) < 7.0, "live: a running one takes you to its island")
	sidecar.send_command("session.end", {"session": resumed})
	await _until(func() -> bool: return islands.island(resumed) == null, 5.0)


# S06, live with the fake and h1's chat open, pickup_timeout short: waiting
# on sign_in isn't busy, so a message is watched there too; a draft typed
# meanwhile stays; the text comes back on reopening, once; a late pickup
# (a user message, or the orchestrator working, applied by hand: the fake
# never picks up a lost one) takes the warning and the text given back.
func _sign_in_pickup(world: Node3D, chat: ChatController, id: String) -> void:
	var store: SessionStore = world.store
	var panel := chat.panel()
	var orchestrator := (world.get_node("SessionIslands") as SessionIslands).orchestrator(id)
	var warned := func() -> bool: return panel.status_text().begins_with("Your message hasn't reached")
	var reopen := func() -> void:
		_press("ui_cancel")
		await _until(func() -> bool: return not chat.is_open(), 2.0)
		chat.open(orchestrator)
		await _until(func() -> bool: return chat.is_open(), 2.0)
	panel.set_draft("signin")
	panel.send()
	await _until(func() -> bool: return store.orchestrator(id).get("reason") == "sign_in", 8.0)
	_check(panel.status_text() == "Waiting for you to sign in, in the terminal.", "live: signin, the orchestrator waits on sign_in")
	panel.set_draft("lost")
	panel.send()
	await _until(warned, 5.0)
	_check(warned.call() and panel.draft() == "lost", "live: waiting on sign_in, one never picked up says so, its text back")

	panel.set_draft("lost")
	panel.send()
	_check(panel.status_text() == "Waiting for you to sign in, in the terminal.", "live: sending again takes the warning")
	panel.set_draft("a draft")
	await _until(warned, 5.0)
	_check(warned.call() and panel.draft() == "a draft", "live: a draft typed before the warning isn't replaced")
	panel.set_draft("")
	await reopen.call()
	_check(warned.call() and panel.draft() == "lost", "live: reopening with the box empty gives the text back")
	panel.set_draft("")
	await reopen.call()
	_check(warned.call() and panel.draft() == "", "live: once only: cleared, it stays clear; the warning stays")

	panel.set_draft("lost")
	panel.send()
	await _until(warned, 5.0)
	_check(panel.draft() == "lost", "live: given back again for the next one lost")
	store.apply({"type": "message.started", "session": id, "seq": 9001, "message": "late1", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": id, "seq": 9002, "message": "late1", "text": "lost"})
	_check(panel.status_text() == "Waiting for you to sign in, in the terminal." and panel.draft() == "", "live: picked up late by a user message: the warning and the text given back go")
	panel.set_draft("lost")
	panel.send()
	await _until(warned, 5.0)
	panel.set_draft("lost, edited")
	store.apply({"type": "message.started", "session": id, "seq": 9003, "message": "late2", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": id, "seq": 9004, "message": "late2", "text": "lost"})
	_check(not warned.call() and panel.draft() == "lost, edited", "live: picked up late, an edited box is left alone")
	panel.set_draft("lost")
	panel.send()
	await _until(warned, 5.0)
	_check(panel.draft() == "lost", "live: and given back once more")
	store.apply({"type": "agent.state_changed", "session": id, "seq": 9005, "agent": "main", "state": "working", "reason": null})
	_check(panel.status_text() == "Working…" and panel.draft() == "", "live: picked up late by the orchestrator working: the warning and the text go")
	store.apply({"type": "agent.state_changed", "session": id, "seq": 9006, "agent": "main", "state": "waiting", "reason": "sign_in"})
	# The box is kept with the chat closed: a pickup then clears it too.
	panel.set_draft("lost")
	panel.send()
	await _until(warned, 5.0)
	_press("ui_cancel")
	await _until(func() -> bool: return not chat.is_open(), 2.0)
	_check(panel.draft() == "lost", "live: closing the chat keeps the box")
	store.apply({"type": "message.started", "session": id, "seq": 9007, "message": "late3", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": id, "seq": 9008, "message": "late3", "text": "lost"})
	chat.open(orchestrator)
	await _until(func() -> bool: return chat.is_open(), 2.0)
	_check(not warned.call() and panel.draft() == "", "live: picked up late with the chat closed: reopened, no warning and no text to send twice")

	# The next call going through clears the sign-in wait.
	panel.set_draft("signed in again")
	panel.send()
	await _until(func() -> bool: return store.orchestrator(id).get("state") == "idle" and store.session(id)["notices"].is_empty(), 8.0)
	await _frames(40)
	_check(panel.status_text() == "" and panel.draft() == "" and panel.shown_messages()[-1].contains("signed in again"), "live: the next one goes through and the wait clears")


func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


# Whether two colours are within [param by] in every channel.
func _close(a: Color, b: Color, by: float) -> bool:
	return absf(a.r - b.r) < by and absf(a.g - b.g) < by and absf(a.b - b.b) < by


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


# For checks that something did NOT happen: a whole main-loop iteration, so
# input events and deferred calls have been handled. Physics frames don't
# promise that: a slow iteration runs several physics steps in a row.
func _settle() -> void:
	for i in 2:
		await process_frame


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
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
