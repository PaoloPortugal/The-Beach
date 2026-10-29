extends SceneTree
## Headless test for the M1 world: the island generator (W01) and jump
## assist (W03), then the world scene with
## real physics: the player lands on the spawn platform, walks, jumps, and
## swims in the sea over the seabed (W08), back by the sessions ring's
## "Platform" or the big map; the sessions ring and its create panel
## (W07, S03); islands for
## sessions (applied to the store by hand) rising and sinking (W04), each
## orchestrator's bubble, and
## walking up to chat in the chat panel (A01, C01, C02), both rendering
## Markdown (C03); subagents'
## placement, coming and going, and state markers (A02, A03, A04); the
## attention cue (A05); the day and night and the weather (W09); the
## debug commands (C09); fishing and its catches (D01); the opening at
## the start (C17); the menus in a made-up language (C16).
##
##   godot --headless --fixed-fps 60 --path . --script res://tests/world/world_test.gd
##   ... -- --sidecar-dev-fake    also starts a session from the menu and
##                                chats with the fake provider, which
##                                spawns subagents

const ErrorWatch := preload("res://tests/error_watch.gd")
const LocaleTest := preload("res://tests/locale/locale_test.gd")
const Pot := preload("res://tests/locale/pot.gd")

var _failed := false
## What the world asked the sidecar for sessions started outside the game (S08).
var _outside_sent: Array[bool] = []
var _errors := ErrorWatch.new(self)
## The world's fishing, for _cast (D01).
var _rod_user: Fishing
## A long timer whose time left reads the game's clock, for _game_ms.
var _clock: SceneTreeTimer
## Where _pace started: game and wall clock, in ms.
var _paced_from: Array[int] = [0, 0]


func _initialize() -> void:
	_run()


func _run() -> void:
	_island()
	_lap("_island")
	await _biomes()
	_lap("_biomes")
	_jump_assist()
	_lap("_jump_assist")
	_placement()
	_lap("_placement")
	_fish_species()
	_lap("_fish_species")
	_fish_fight()
	_lap("_fish_fight")
	_catch_log()
	_lap("_catch_log")
	await _scene()
	_lap("_scene")
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
	# A bridge landing on the zipline's cable moves it to another valley's
	# mouth (W10; found by the user, 2026-10-09); one landing elsewhere
	# doesn't, nor does one beside another valley.
	var moves := true
	for seed in range(1, 13):
		var g := IslandGenerator.new(seed * 7919, Biome.Kind.MOUNTAIN)
		var top := g.zipline_ends(0)[1]
		var side := Vector3(-top.z, 0.0, top.x).normalized() * (IslandGenerator.BRIDGE_CLEAR - 1.0)
		var away := Basis(Vector3.UP, TAU / IslandGenerator.VALLEYS / 2.0) * top
		var v := g.zipline_valley([top + side], 0)
		moves = moves and v != 0 and g.zipline_room([top + side], v) >= IslandGenerator.BRIDGE_CLEAR
		moves = moves and g.zipline_valley([away], 0) == 0 and g.zipline_valley([], 0) == 0
		moves = moves and g.zipline_valley([top], 1) == 1
	_check(moves, "biomes: a bridge landing within %.0f m of a mountain's zipline moves it to a clear valley; others don't" % IslandGenerator.BRIDGE_CLEAR)
	# What stands on a mountain stands on its built ground, a jittered 2 m
	# grid that on the cliff is up to 2 m off height_at (W10; found by the
	# user, 2026-10-09): every torch and zipline post, on many seeds.
	var worst := 0.0
	var stood := 0
	for seed in range(1, 13):
		var island := Island.new()
		island.island_seed = seed * 7919
		island.biome = Biome.Kind.MOUNTAIN
		island.position = Vector3(0, -800, 0) # out of the way
		root.add_child(island)
		await process_frame # it builds in _ready
		var faces := PackedVector3Array()
		for c in island.get_children():
			if c is CollisionShape3D:
				faces = (c.shape as ConcavePolygonShape3D).get_faces()
		var feet: Array[Vector3] = [island.zipline().low, island.zipline().high]
		for t in island.torches():
			feet.append(t.position)
		for f in feet:
			worst = maxf(worst, absf(f.y - _mesh_height(faces, f.x, f.z)))
			stood += 1
		island.free()
	_check(stood == 12 * (2 + Island.TORCHES) and worst < 0.03, "biomes: a mountain's torches and zipline posts stand on its ground (%d, at most %.3f m off)" % [stood, worst])

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
	_check(points.all(func(p: Vector2) -> bool: return p.length() > 9.0), "placement: all outside its talking reach")
	_check(AgentPlacement.slot_position(7) == AgentPlacement.slot_position(7), "placement: a slot is always in the same place")
	var far := AgentPlacement.slot_position(5000)
	_check(far.length() > 100.0 and is_finite(far.x), "placement: no maximum")


func _scene() -> void:
	var world: Node3D = load("res://world/world.tscn").instantiate()
	# Never the developer's own settings file, nor another run's (C10, A05).
	var settings_file := "user://world_test_settings_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))
	# In English whatever the system's language (C16).
	var pinned := ConfigFile.new()
	pinned.set_value("game", "language", "en")
	pinned.save(settings_file)
	world.settings.path = settings_file
	world.attention.settings_path = settings_file
	# Never the user's own running sessions (S08): the setting is recorded, not sent.
	world.set_outside_sessions = func(on: bool) -> void: _outside_sent.append(on)
	root.add_child(world)
	await process_frame  # _ready runs once the tree is going
	_lap("world_load")
	var player: Player = world.get_node("Player")
	var spawn := player.spawn_point
	_check(spawn.is_equal_approx(Vector3(0, 1.1, 3)), "spawns on the platform")
	await _opening(world, player)
	_lap("_opening")
	await _menu_start(world, player)
	_lap("_menu_start")
	await _loading_cover(world, player)
	_lap("_loading_cover")
	await _sidecar_lost(world, player)
	_lap("_sidecar_lost")

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
	_lap("_crouch_slide")
	await _sky(world, player)
	_lap("_sky")
	await _commands(world, player)
	_lap("_commands")
	await _swimming(world, player)
	_lap("_swimming")
	await _menu(world, player)
	_lap("_menu")
	await _sessions(world, player)
	_lap("_sessions")
	await _agents(world)
	_lap("_agents")
	await _pause(world, player)
	_lap("_pause")
	await _main_menu(world, player)
	_lap("_main_menu")
	await _settings(world, player)
	_lap("_settings")
	await _languages(world, player)
	_lap("_languages")
	await _biome_island(world, player)
	_lap("_biome_island")
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		_pace(true)
		await _live(world, player)
		_pace(false)
		_lap("_live")

	world.queue_free()
	await _frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))


# C13: the pause menu: Esc opens and closes it, Esc in other menus closes
# only those, Settings and back, and Quit game through the quit guard.
func _pause(world: Node3D, player: Player) -> void:
	var pause: PauseMenu = world.pause_menu
	var menu: SettingsMenu = world.settings_menu
	var sessions: SessionsMenu = world.get_node("SessionsMenu")
	var dim: ColorRect = pause.get_node("Dim")
	_press("ui_cancel")
	await _settle()
	# The mouse itself can't be captured headless: the live check's.
	_check(pause.is_open() and dim.visible and not player.controls_enabled and not menu.is_open(), "C13: Esc opens the pause menu, dimmed, and stops the player")
	_check(pause.button("Resume").is_visible_in_tree() and pause.button("Settings").is_visible_in_tree() and pause.button("Main menu").is_visible_in_tree() and pause.button("Quit game").is_visible_in_tree(), "C13: Resume, Settings, Main menu (C14) and Quit game")
	_press("ui_cancel")
	await _settle()
	_check(not pause.is_open() and not dim.visible and player.controls_enabled, "C13: Esc again closes it")
	pause.open()
	pause.button("Resume").pressed.emit()
	_check(not pause.is_open() and player.controls_enabled, "C13: and so does Resume")
	_hold("sessions_menu")
	await _settle()
	_check(sessions.ring_open(), "C13: (the sessions ring open)")
	_press("ui_cancel")
	await _settle()
	_check(not sessions.is_open() and not pause.is_open(), "C13: Esc in the sessions ring closes only that")
	_release("sessions_menu")
	await _open_create(sessions)
	_press("ui_cancel")
	await _settle()
	_check(not sessions.is_open() and not pause.is_open(), "C13: and in the create panel")

	# Settings, and Esc back.
	_press("ui_cancel")
	await _settle()
	pause.button("Settings").pressed.emit()
	await _settle()
	_check(menu.is_open() and pause.is_open() and dim.visible and not pause.button("Settings").is_visible_in_tree() and not player.controls_enabled, "C13: Settings opens the settings menu in its place, still dimmed")
	_press("ui_cancel")
	await _settle()
	_check(not menu.is_open() and pause.is_open() and pause.button("Settings").is_visible_in_tree() and not player.controls_enabled, "C13: Esc in the settings goes back to the pause menu")
	_press("ui_cancel")
	await _settle()
	_check(not pause.is_open() and player.controls_enabled, "C13: and Esc again back to the game")
	# The settings opened without it (as other tests do) give the controls back.
	menu.open()
	_press("ui_cancel")
	await _settle()
	_check(not menu.is_open() and not pause.is_open() and player.controls_enabled, "C13: settings opened on their own close to the game")

	# Quit game asks first while sessions run, as closing the window does.
	var guard: QuitGuard = world.quit_guard
	var quits := [0]
	var quit_before := guard.quit
	guard.quit = func() -> void: quits[0] += 1
	pause.open()
	pause.button("Quit game").pressed.emit()
	_check(quits[0] == 1, "C13: Quit game with no session running quits")
	world.store.apply({"type": "session.snapshot", "session": _snapshot("p1")})
	await _frames(1)
	pause.button("Quit game").pressed.emit()
	await _settle()
	_check(guard.is_asking() and quits[0] == 1, "C13: with a session running, the quit guard asks first (S05)")
	guard.dialog().get_cancel_button().pressed.emit()
	await _frames(1)
	_check(not guard.is_asking() and pause.is_open() and not player.controls_enabled, "C13: Back to the game leaves the pause menu open")
	pause.button("Quit game").pressed.emit()
	guard.dialog().get_ok_button().pressed.emit()
	_check(quits[0] == 2, "C13: and its Quit quits")
	guard.quit = quit_before
	world.store.apply({"type": "session.ended", "session": "p1", "seq": 2, "reason": "exited"})
	pause.close()
	await _settle()


# C14: back to the main menu from the pause menu, the camera easing up;
# its Settings, Credits and Quit; the camera's circle round the islands.
func _main_menu(world: Node3D, player: Player) -> void:
	var menu: MainMenu = world.main_menu
	var camera: MenuCamera = world.menu_camera
	var pause: PauseMenu = world.pause_menu
	var settings: SettingsMenu = world.settings_menu
	var own: Camera3D = player.get_node("Head/Camera3D")
	var where := player.global_position
	pause.open()
	pause.button("Main menu").pressed.emit()
	await _frames(1)
	_check(menu.is_open() and not pause.is_open() and not player.controls_enabled and camera.mode() == MenuCamera.Mode.ASCEND and get_root().get_camera_3d() == camera, "C14: the pause menu's Main menu opens it, the camera easing up")
	_check(camera.global_position.distance_to(own.global_position) < 2.0, "C14: from the player's own view")
	await _until(func() -> bool: return camera.mode() == MenuCamera.Mode.ORBIT, MenuCamera.EASE_TIME + 2.0)
	_check(camera.mode() == MenuCamera.Mode.ORBIT, "C14: then circles")

	# Settings, and Esc back to the main menu; the pause menu's way back kept.
	menu.button("Settings").pressed.emit()
	await _settle()
	_check(settings.is_open() and not menu.get_node("Panel").visible and menu.get_node("Dim").visible and not player.controls_enabled, "C14: Settings opens the settings menu in its place")
	_press("ui_cancel")
	await _settle()
	_check(not settings.is_open() and menu.is_open() and menu.get_node("Panel").visible and not pause.is_open() and not player.controls_enabled, "C14: Esc in the settings goes back to the main menu")
	_check(settings.back.is_valid() and settings.back.get_object() == pause, "C14: the settings' Esc goes to the pause menu again afterwards")

	# Credits: the file as it is, then Godot's notices; Back and Esc.
	menu.button("Credits").pressed.emit()
	await _settle()
	var shown := menu.credits_text()
	_check(menu.credits_open() and not menu.get_node("Panel").visible, "C14: Credits opens in the menu's place")
	_check(shown.contains("Asset credits") and shown.contains("Kenney Interface Sounds") and shown.contains("Shaders and code-generated visuals"), "C14: it shows assets/CREDITS.md")
	_check(shown.contains("Made with Godot Engine") and shown.contains("Show Godot licences") and not shown.contains("FreeType") and not menu.godot_licences_shown(), "C14: then Made with Godot Engine, its licences behind a toggle")
	menu.button("Godot licences").pressed.emit()
	await _settle()
	shown = menu.credits_text()
	_check(menu.godot_licences_shown() and shown.contains(Engine.get_license_text().substr(0, 60)) and shown.contains("FreeType") and shown.contains("Hide Godot licences"), "C14: the toggle shows Godot's licence and its third-party parts")
	menu.button("Godot licences").pressed.emit()
	_check(not menu.godot_licences_shown() and not menu.credits_text().contains("FreeType"), "C14: and hides them again")
	var opened: Array[String] = []
	menu.open_link = func(url: String) -> void: opened.append(url)
	var view: MarkdownView = menu.find_child("Body", true, false).get_child(0)
	view.link_clicked.emit("https://kenney.nl/assets/interface-sounds")
	_check(opened == ["https://kenney.nl/assets/interface-sounds"], "C14: a link in the credits opens")
	_press("ui_cancel")
	await _settle()
	_check(not menu.credits_open() and menu.get_node("Panel").visible and menu.is_open(), "C14: Esc goes back from the credits")
	menu.open_credits()
	menu.button("Back").pressed.emit()
	_check(not menu.credits_open() and menu.get_node("Panel").visible, "C14: and so does Back")

	# Quit asks first while sessions run (S05).
	var guard: QuitGuard = world.quit_guard
	var quits := [0]
	var quit_before := guard.quit
	guard.quit = func() -> void: quits[0] += 1
	menu.button("Quit").pressed.emit()
	_check(quits[0] == 1, "C14: Quit with no session running quits")
	world.store.apply({"type": "session.snapshot", "session": _snapshot("m1")})
	await _frames(1)
	menu.button("Quit").pressed.emit()
	await _settle()
	_check(guard.is_asking() and quits[0] == 1, "C14: with a session running, the quit guard asks first")
	guard.dialog().get_cancel_button().pressed.emit()
	await _frames(1)
	_check(not guard.is_asking() and menu.is_open() and not player.controls_enabled, "C14: Back to the game leaves the main menu up")
	guard.quit = quit_before

	# The circle: round the islands' middle, past the farthest.
	var circle := camera.target_circle()
	var islands: Array[Island] = world.get_node("SessionIslands").all_islands()
	_check(not islands.is_empty() and islands.all(func(i: Island) -> bool: return circle[1] == MenuCamera.MAX_RADIUS or Vector2(i.global_position.x - circle[0].x, i.global_position.z - circle[0].z).length() <= circle[1]), "C14: the circle takes in every island (or is as wide as it goes)")
	_check(circle[1] >= MenuCamera.MIN_RADIUS and circle[1] <= MenuCamera.MAX_RADIUS, "C14: within its limits (%.0f m)" % circle[1])

	# Play: back where the player was, sessions untouched.
	menu.button("Play").pressed.emit()
	await _until(func() -> bool: return not menu.is_open(), MenuCamera.EASE_TIME + 2.0)
	_check(player.controls_enabled and get_root().get_camera_3d() == own and player.global_position.distance_to(where) < 1.0 and world.store.sessions.has("m1"), "C14: Play again, the player where they were and the session still there")
	world.store.apply({"type": "session.ended", "session": "m1", "seq": 2, "reason": "exited"})
	await _settle()

	# Standing on an island whose session ends behind the menu: it sinks
	# there and then, and Play puts the player on the platform (user's).
	var session_islands: SessionIslands = world.get_node("SessionIslands")
	world.store.apply({"type": "session.snapshot", "session": _snapshot("m2")})
	await _islands_up(session_islands)
	world.teleport("m2")
	await _frames(2)
	var m2 := session_islands.island("m2")
	_check(session_islands.session_at(player.global_position) == "m2", "C14: (the player on m2's island)")
	pause.open()
	pause.button("Main menu").pressed.emit()
	await _frames(1)
	world.store.apply({"type": "session.ended", "session": "m2", "seq": 2, "reason": "exited"})
	await _settle()
	_check(is_instance_valid(m2) and m2.position.y < 0.0 and m2 in session_islands.left_islands(), "C14: an ended session's island sinks while the main menu's up, the player on it or not")
	var m2_ref: WeakRef = weakref(m2)
	await _until(func() -> bool: return m2_ref.get_ref() == null, session_islands.sink_time + 2.0)
	menu.button("Play").pressed.emit()
	await _until(func() -> bool: return not menu.is_open(), MenuCamera.EASE_TIME + 2.0)
	_check(not is_instance_valid(m2) and player.global_position.distance_to(player.spawn_point) < 1.0 and player.controls_enabled, "C14: and Play puts the player on the platform")
	pause.open()
	pause.button("Main menu").pressed.emit()
	await _frames(1)
	player.global_position += Vector3(1.0, 0.0, 0.0)
	where = player.global_position
	menu.button("Play").pressed.emit()
	await _until(func() -> bool: return not menu.is_open(), MenuCamera.EASE_TIME + 2.0)
	_check(player.global_position.distance_to(where) < 1.0, "C14: only that once")


# C10: the settings menu, each setting applied, saved and reset.
func _settings(world: Node3D, player: Player) -> void:
	var menu: SettingsMenu = world.settings_menu
	var settings: Settings = world.settings
	var sessions: SessionsMenu = world.get_node("SessionsMenu")
	_check(not settings.path.ends_with("/settings.cfg"), "C10: the test's own settings file")
	_check(settings.value("controls/fov") == 80.0 and settings.value("graphics/shadows") == "high", "C10: no file, the defaults")
	var smaa := Viewport.SCREEN_SPACE_AA_SMAA if menu.screen_space_aa_available else Viewport.SCREEN_SPACE_AA_DISABLED
	_check(world.get_viewport().msaa_3d == Viewport.MSAA_DISABLED and world.get_viewport().screen_space_aa == smaa, "C10: SMAA by default (none under Compatibility), no MSAA")
	menu.open()
	var tabs := []
	for t: String in SettingsMenu.TABS:
		menu.show_tab(t)
		tabs.append(menu.current_tab())
	_check(tabs == ["Graphics", "Controls", "Sound", "Game", "Providers"], "C10: tabs for Graphics, Controls, Sound, Game and Providers")
	var sun: DirectionalLight3D = world.get_node("Sun")
	var camera: Camera3D = player.get_node("Head/Camera3D")
	var shadows: OptionButton = menu.control("graphics/shadows")
	shadows.item_selected.emit(1)
	_check(settings.value("graphics/shadows") == "low" and sun.shadow_enabled == menu.shadows_available and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "C10: low shadows, 2 splits")
	shadows.item_selected.emit(0)
	_check(not sun.shadow_enabled and shadows.selected == 0, "C10: shadows off")
	(menu.control("graphics/msaa") as OptionButton).item_selected.emit(1)
	_check(world.get_viewport().msaa_3d == Viewport.MSAA_2X, "C10: MSAA 2x")
	(menu.control("graphics/screen_space_aa") as OptionButton).item_selected.emit(1)
	var fxaa := Viewport.SCREEN_SPACE_AA_FXAA if menu.screen_space_aa_available else Viewport.SCREEN_SPACE_AA_DISABLED
	_check(world.get_viewport().screen_space_aa == fxaa, "C10: FXAA (none under Compatibility)")
	(menu.control("graphics/fps_cap") as OptionButton).item_selected.emit(2)
	_check(Engine.max_fps == 60, "C10: the FPS cap")
	(menu.control("graphics/render_scale") as HSlider).value = 0.7
	_check(is_equal_approx(world.get_viewport().scaling_3d_scale, 0.7), "C10: the render scale")
	(menu.control("graphics/lightning") as CheckButton).button_pressed = false
	_check(not world.weather.lightning_enabled, "C10: lightning off")
	(menu.control("graphics/vsync") as CheckButton).button_pressed = false
	(menu.control("graphics/window_mode") as OptionButton).item_selected.emit(1)
	(menu.control("controls/mouse_sensitivity") as HSlider).value = 2.0
	_check(is_equal_approx(player.mouse_sensitivity, Player.BASE_SENSITIVITY * 2.0), "C10: mouse sensitivity")
	(menu.control("controls/fov") as HSlider).value = 100.0
	_check(camera.fov == 100.0, "C10: field of view")
	world.attention.sound_on = true
	menu.sound_toggle().button_pressed = false
	_check(not world.attention.sound_on, "C10: the waiting chime's toggle, moved from the sessions menu")
	(menu.control("game/go_to_new_island") as CheckButton).button_pressed = false
	(menu.control("game/crosshair") as CheckButton).button_pressed = false
	_check(not world.crosshair.ring_on, "C10/C11: the crosshair's toggle hides its ring")
	# S08: sessions started outside the game, on by default, sent at start and on each change.
	var outside: CheckButton = menu.control("game/outside_sessions")
	menu.show_tab("Game")
	_check(outside.is_visible_in_tree() and outside.button_pressed and not outside.disabled and _outside_sent.size() > 0 and _outside_sent.all(func(on: bool) -> bool: return on), "S08: Game has the outside sessions toggle, on, and the world said so at start")
	var islands_of: SessionIslands = world.get_node("SessionIslands")
	islands_of.memory.put(["gone-key", "gone-alias"], {"biome": Biome.Kind.BEACH, "seed": 1, "cluster": "", "name": "", "repo_key": "", "slot": 0, "index": 0})
	islands_of._gone_outside.append(["gone-key", "gone-alias"])
	outside.button_pressed = false
	_check(_outside_sent.back() == false and settings.value("game/outside_sessions") == false, "S08: off: the sidecar is told, and it's saved")
	_check(not islands_of.memory.has("gone-key") and not islands_of.memory.has("gone-alias"), "S08: off: the islands of outside sessions kept after they went are forgotten")
	# A provider that can't list them: greyed out and off, its notice beside it, the saved choice kept.
	var stand_in := SidecarClient.new()
	stand_in.providers = [{"provider": "fake", "name": "Fake", "capabilities": {"outside_sessions": {}}}]
	menu.sidecar = stand_in
	outside.button_pressed = true
	_check(menu.outside_off_text() == "" and not outside.disabled, "S08: no notice, the toggle works")
	stand_in.providers[0]["notices"] = [{"code": "outside_sessions_off", "message": "Can't list them: agent view is off."}]
	stand_in.providers_changed.emit()
	_check(outside.disabled and not outside.button_pressed and menu.outside_off_text() == "Can't list them: agent view is off.", "S08: the provider's notice: greyed out, shown off, the notice in red beside it")
	_check(settings.value("game/outside_sessions") == true, "S08: and the saved choice is kept")
	# S02: a row per provider that runs a program of the user's, kept up with what it found.
	menu.show_tab("Providers")
	_check(menu.program_text("fake") == "" and menu._programs.is_empty() and menu._no_providers.is_visible_in_tree(), "S02: no row for a provider without program_path, Providers says there's nothing to set")
	stand_in.providers.append({"provider": "tool", "name": "Tool", "capabilities": {"program_path": {"program": "tool"}}})
	stand_in.providers_changed.emit()
	var tool_row: Dictionary = menu._programs.get("tool", {})
	_check(not tool_row.is_empty() and tool_row["label"].text == "Tool" and tool_row["box"].is_visible_in_tree() and not menu._no_providers.visible, "S02: a row for it in Providers, by its name, instead of the line")
	_check(menu.program_text("tool") == "Looking for it…", "S02: not found yet: looking (the sidecar looks at start)")
	_check(tool_row["reset"].disabled and not tool_row["browse"].disabled and not tool_row["look"].disabled and tool_row["look"].text == "Look again", "S02: Reset greyed out unless set by hand, Browse… and Look again there")
	stand_in.providers[1]["program"] = {"path": "/opt/tool/bin/tool", "version": "2.1.300", "set_by_hand": false}
	stand_in.providers_changed.emit()
	_check(menu.program_text("tool") == "/opt/tool/bin/tool\nversion 2.1.300" and tool_row["status"].modulate == Color.WHITE, "S02: found: its path and version")
	stand_in.program_paths = {"tool": "/opt/tool/bin/tool"}
	stand_in.providers[1]["program"] = {"path": "/opt/tool/bin/tool", "version": "2.1.300", "set_by_hand": true}
	stand_in.providers_changed.emit()
	_check(menu.program_text("tool").ends_with("  ·  set by hand") and not tool_row["reset"].disabled, "S02: set by hand: said so, and Reset works")
	stand_in.providers[1]["program"] = {"path": null, "set_by_hand": true, "message": "The Claude Code set in Settings doesn't work: There's no program at that path. Choose it again, or reset it."}
	stand_in.providers_changed.emit()
	_check(menu.program_text("tool").begins_with("The Claude Code set in Settings doesn't work") and tool_row["status"].modulate != Color.WHITE, "S02: not found: why, in red")
	menu.choose_program("tool", "/somewhere/else")
	_check(menu.program_error("tool") == "Not changed: The sidecar isn't running." and stand_in.program_paths == {"tool": "/opt/tool/bin/tool"} and not tool_row["browse"].disabled, "S02: no sidecar: not changed, said why, the setting kept")
	menu.look_again("tool")
	_check(menu.program_error("tool") == "Couldn't look: The sidecar isn't running." and menu.program_text("tool").begins_with("The Claude Code set in Settings doesn't work") and not tool_row["look"].disabled, "S02: Look again with no sidecar: said why, the row as it was")
	# The panel is as tall as its tallest tab, hidden ones too: the row's
	# wrapping text, a message and a refusal shown, mustn't make it taller
	# than a small screen on any tab.
	var heights := []
	for t: String in SettingsMenu.TABS:
		menu.show_tab(t)
		await _frames(2)
		heights.append(menu._panel.size.y)
	_check(heights.all(func(h: float) -> bool: return h < 600.0), "S02: the settings panel fits a small screen on every tab (heights %s)" % [heights])
	menu.show_tab("Game")
	menu.sidecar = root.get_node("Sidecar")
	stand_in.free()
	_check(not outside.disabled, "S08: (back to the real sidecar)")
	await _frames(1)
	_check(not is_instance_valid(tool_row["box"]), "S02: a provider gone, its row gone")
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		_check(menu._programs.is_empty(), "S02: the fake provider has no program row")
	else:
		# The real sidecar checks a path it's given before anything else.
		_check(menu._programs.has("claude"), "S02: the real sidecar's Claude Code has a row")
		menu.choose_program("claude", "claude.exe")
		_check(menu.program_text("claude") == "Checking…", "S02: Checking… until the sidecar answers")
		await _until_wall(func() -> bool: return menu.program_error("claude") != "", 10.0)
		_check(menu.program_error("claude") == "Not changed: That isn't a full path." and menu.program_text("claude") != "Checking…" and not root.get_node("Sidecar").program_paths.has("claude"), "S02: a path that isn't a full one refused by the sidecar, nothing kept")
	menu.close()

	var saved := Settings.new()
	saved.path = settings.path
	saved.load_file()
	var expect := {"graphics/shadows": "off", "graphics/msaa": "2x", "graphics/screen_space_aa": "fxaa", "graphics/fps_cap": 60, "graphics/render_scale": 0.7, "graphics/lightning": false, "graphics/vsync": false, "graphics/window_mode": "borderless", "controls/mouse_sensitivity": 2.0, "controls/fov": 100.0, "game/go_to_new_island": false, "game/crosshair": false, "game/outside_sessions": true}
	var lost := expect.keys().filter(func(k: String) -> bool:
		return not (is_equal_approx(saved.value(k), expect[k]) if expect[k] is float else saved.value(k) == expect[k]))
	_check(lost.is_empty(), "C10: every setting is kept between runs (not: %s)" % [lost])
	var cfg := ConfigFile.new()
	cfg.load(settings.path)
	_check(cfg.get_value("attention", "sound", true) == false, "C10: in the same file as the chime's")

	# Being taken to a session you started, off and on.
	var store: SessionStore = world.store
	store.apply({"type": "session.snapshot", "session": _snapshot("s10")})
	await _islands_up(world.get_node("SessionIslands"))
	var at := player.global_position
	sessions.launcher.session_started.emit("s10")
	await _frames(2)
	_check(player.global_position.distance_to(at) < 1.0, "C10: with it off, starting a session leaves you where you are")
	settings.set_value("game/go_to_new_island", true)
	sessions.launcher.session_started.emit("s10")
	await _frames(2)
	_check(player.global_position.distance_to(at) > 20.0, "C10: on, it takes you there")
	player.respawn()
	store.apply({"type": "session.ended", "session": "s10", "seq": 2, "reason": "exited"})

	# A broken file: what can't be read is the default.
	var bad := ConfigFile.new()
	bad.set_value("graphics", "shadows", "ultra")
	bad.set_value("graphics", "fps_cap", 75)
	bad.set_value("graphics", "msaa", 4)
	bad.set_value("graphics", "screen_space_aa", "taa")
	bad.set_value("controls", "fov", "wide")
	bad.set_value("controls", "mouse_sensitivity", 50)
	saved.path = settings.path + ".bad"
	bad.save(saved.path)
	saved.load_file()
	_check(saved.value("graphics/shadows") == "high" and saved.value("graphics/fps_cap") == 0 and saved.value("graphics/msaa") == "off" and saved.value("graphics/screen_space_aa") == "smaa" and saved.value("controls/fov") == 80.0 and saved.value("controls/mouse_sensitivity") == 3.0, "C10: values it can't take are the defaults, out of range ones clamped")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.path))

	menu.open()
	menu.reset_all()
	_check(settings.value("controls/fov") == 80.0 and camera.fov == 80.0 and Engine.max_fps == 0 and world.get_viewport().msaa_3d == Viewport.MSAA_DISABLED and world.get_viewport().screen_space_aa == smaa and world.weather.lightning_enabled and sun.shadow_enabled == menu.shadows_available and world.attention.sound_on and world.crosshair.ring_on, "C10: Reset to defaults puts every setting back, the chime and the crosshair too")
	_check((menu.control("controls/fov") as HSlider).value == 80.0 and menu.sound_toggle().button_pressed, "C10: and the menu shows them")
	menu.close()


# C16: the Language row, then every menu in a made-up language where
# every string is ⟦English⟧: shown text without the brackets is text the
# template misses, or not translated, unless it's content (a session
# titled "Settings" still says so) or has no letters.
func _languages(world: Node3D, player: Player) -> void:
	var settings: Settings = world.settings
	var menu: SettingsMenu = world.settings_menu
	var main: MainMenu = world.main_menu
	var pause: PauseMenu = world.pause_menu
	var sessions: SessionsMenu = world.get_node("SessionsMenu")
	var guard: QuitGuard = world.quit_guard
	_check(settings.value("game/language") == Languages.AUTOMATIC and TranslationServer.get_locale() == "en", "C16: the Language setting is Automatic, and the game in English")
	settings.set_value("game/language", "en") # pinned again after the reset
	var row: OptionButton = menu.control("game/language")
	menu.open()
	menu.show_tab("Game")
	await _settle()
	var items := []
	for i in row.item_count:
		items.append(row.get_item_text(i))
	_check(row.is_visible_in_tree() and items == ["Automatic", "English"] and row.selected == 1, "C16: Game's first row, Language: Automatic, then English (%s)" % [items])
	menu.close()

	var pseudo := LocaleTest.pseudo_translation()
	TranslationServer.add_translation(pseudo)
	settings.set_value("game/language", Pot.PSEUDO_LOCALE)
	await _settle()
	_check(TranslationServer.get_locale() == Pot.PSEUDO_LOCALE, "C16: a language chosen applies at once")
	var bad := []
	main.open()
	await _settle()
	bad.append_array(_untranslated(main, "main menu"))
	main.open_credits()
	await _settle()
	bad.append_array(_untranslated(main, "credits"))
	main.close_credits()
	main.close_now()
	await _settle()
	pause.open()
	await _settle()
	bad.append_array(_untranslated(pause, "pause"))
	# The walk itself: text the template lacks is found, content isn't.
	var stray := Label.new()
	stray.text = "Not in the template"
	var title := Languages.content(Label.new()) as Label
	title.text = "A session's title"
	pause.add_child(stray)
	pause.add_child(title)
	var found := _untranslated(pause, "pause")
	_check(found.size() == 1 and found[0].contains("Not in the template"), "C16: (the check finds untranslated text, and leaves content: %s)" % [found])
	stray.free()
	title.free()
	pause.close()
	menu.open()
	for t: String in SettingsMenu.TABS:
		menu.show_tab(t)
		await _settle()
		bad.append_array(_untranslated(menu, "settings: " + t))
	_check(row.get_item_text(0) == "⟦Automatic⟧" and row.get_item_text(row.selected).begins_with("⟦"), "C16: the Language row in the language too, and it under its own name")
	menu.close()
	await _open_create(sessions)
	bad.append_array(_untranslated(sessions, "sessions: add"))
	sessions._show(SessionsMenu.Page.RESUME)
	await _settle()
	bad.append_array(_untranslated(sessions, "sessions: resume"))
	sessions.close()
	await _settle()
	var quits := [0]
	var quit_before := guard.quit
	guard.quit = func() -> void: quits[0] += 1
	var titled := _snapshot("l1")
	titled["title"] = "Settings"
	world.store.apply({"type": "session.snapshot", "session": titled})
	await _frames(1)
	guard.request_quit()
	await _settle()
	bad.append_array(_untranslated(guard, "quit"))
	var listed: String = guard._list.text
	_check(guard.is_asking() and listed.contains("Settings   ·") and not listed.contains("⟦Settings⟧"), "C16: a session titled \"Settings\" still says \"Settings\" (%s)" % listed)
	guard.dialog().get_cancel_button().pressed.emit()
	guard.quit = quit_before
	world.store.apply({"type": "session.ended", "session": "l1", "seq": 2, "reason": "exited"})
	_check(bad.is_empty(), "C16: every menu's text is translated, content aside (not: %s)" % [bad])
	await _chat_content(world)
	await _huds(world, player)

	settings.set_value("game/language", "en")
	TranslationServer.remove_translation(pseudo)
	await _settle()
	_check(TranslationServer.get_locale() == "en" and pause.button("Resume").text == "Resume", "C16: back in English")
	_check(quits[0] == 0 and player.controls_enabled, "C16: (nothing quit, the player free)")


# C16 (security review): in the made-up language, a chat whose content is
# word for word the menus' ("Settings", "Resume", "Back") shows it as
# written, so a prompt's options read as in the terminal; the card's own
# "Details" is translated. Then (step 4) the chat's chrome: the status
# line, a notice of ours, the mode, "{effort} effort", the usage line and
# its details, the turn hint, the card's who line, count and buttons, the
# tool fold's line and statuses all bracketed, with content holding
# placeholders ("{tool}", "{n}") as written; back in English, said again.
func _chat_content(world: Node3D) -> void:
	var store: SessionStore = world.store
	var panel: ChatPanel = (world.get_node("ChatController") as ChatController).panel()
	var snap := _snapshot("l2")
	snap["title"] = "Settings"
	snap["capabilities"] = {"model_info": {}, "permission_modes": {}, "usage": {}}
	snap["model"] = {"id": "m", "label": "Resume"}
	snap["effort"] = {"id": "e", "label": "Back {n}"}
	snap["mode"] = "auto"
	snap["agents"][0]["state"] = "waiting"
	snap["agents"][0]["reason"] = "permission"
	snap["agents"].append(_agent("s1", "main", "working"))
	snap["agents"][1]["name"] = "Settings"
	store.apply({"type": "session.snapshot", "session": snap})
	store.apply({"type": "session.notice", "session": "l2", "seq": 2, "notice": {"code": "not_ours", "message": "Settings"}})
	store.apply({"type": "message.started", "session": "l2", "seq": 3, "message": "u1", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": "l2", "seq": 4, "message": "u1", "text": "Settings"})
	store.apply({"type": "tool.started", "session": "l2", "seq": 5, "tool_call": "t1", "agent": "main", "tool": "Back", "summary": "Settings"})
	store.apply({"type": "tool.finished", "session": "l2", "seq": 6, "tool_call": "t1", "status": "ok", "summary": "Resume"})
	store.apply({"type": "tool.started", "session": "l2", "seq": 7, "tool_call": "t2", "agent": "main", "tool": "{tool}", "summary": "{n}"})
	store.apply({"type": "tool.finished", "session": "l2", "seq": 8, "tool_call": "t2", "status": "error", "summary": "{n}"})
	store.apply({"type": "session.notice", "session": "l2", "seq": 9, "notice": {"code": "transcripts_off", "message": "x"}})
	store.apply({"type": "usage.updated", "session": "l2", "seq": 10, "usage": {
		"tokens": {"input": 40, "output": 1234, "cache_read": 52000, "cache_write": 9000},
		"context": {"tokens": 61040, "percent": 31, "window": 200000},
		"turn": {"message": "u1", "output_tokens": 1234}, "limits": []}})
	store.apply({"type": "permission.requested", "session": "l2", "seq": 11, "permission": {
		"permission": "p1", "agent": "main", "tool": "Back {tool}", "summary": "Settings", "input": {"x": 1},
		"options": [{"option": "o1", "label": "Resume"}]}})
	store.apply({"type": "question.asked", "session": "l2", "seq": 12, "question": {"question": "q1", "agent": "s1", "items": [
		{"text": "Settings", "header": "Back", "multi_select": false, "options": [{"label": "Resume", "description": "Settings"}, {"label": "Back"}]},
	]}})
	panel.open("l2")
	await _until(func() -> bool: return not panel.is_loading(), 5.0)
	panel.tool_fold("u1").set_open(true)
	await _settle()
	var card := panel.pending_card()
	var shown := func(where: Node) -> Array:
		var out := []
		for n: Node in where.find_children("*", "", true, false):
			if (n is Label or n is Button or n is RichTextLabel) and (n as CanvasItem).is_visible_in_tree():
				out.append(n.atr(n.text))
		return out
	var permission: Array = shown.call(panel)
	var wrong := permission.filter(func(t: String) -> bool: return t.contains("⟦Settings⟧") or t.contains("⟦Resume⟧") or t.contains("⟦Back⟧"))
	_check(wrong.is_empty() and card.header_text().contains("Back") and "Resume" in permission and "⟦Details⟧" in permission and panel._title.text == "Settings" and panel.model_text().begins_with("Resume · "), "C16: a chat's title, model, notice, message, tool row and permission (summary, options) as written, the card's Details translated (bracketed: %s)" % [wrong])
	# The chrome (step 4).
	var bad := _untranslated(panel, "chat")
	_check(bad.is_empty(), "C16: the chat's chrome is translated, content aside (not: %s)" % [bad])
	_check(panel.status_text() == "⟦Waiting for a permission: answer it above or in the terminal.⟧", "C16: the status line (%s)" % panel.status_text())
	_check(panel.notices_text() == "Settings\n⟦This session isn't saving transcripts, so parts of it may not show here.⟧", "C16: a notice of ours translated, the sidecar's as written (%s)" % panel.notices_text())
	_check(panel.mode_text() == "⟦Mode: ⟦Auto⟧⟧" and panel.model_text() == "Resume · ⟦Back {n} effort⟧", "C16: the mode, and the effort around the provider's label (%s, %s)" % [panel.mode_text(), panel.model_text()])
	var details: String = panel.get_node("Layout/Header/Usage").tooltip_text
	_check(panel.usage_text() == "⟦Context 31%⟧ · ⟦↑ 61k in⟧ · ⟦↓ 1.2k out⟧" and details.begins_with("⟦Context: 61,040 tokens of 200,000⟧\n⟦Input: 40⟧") and panel.turn_hints() == [["u1", "⟦↓ 1.2k tokens⟧"]], "C16: the usage line, its details and the turn hint (%s; %s; %s)" % [panel.usage_text(), details, panel.turn_hints()])
	_check(card.header_text() == "⟦The orchestrator asks to use Back {tool}:⟧" and card.count_text() == "⟦1 of 2 waiting⟧" and ["⟦Yes⟧", "⟦No⟧", "⟦Send⟧"].all(func(t: String) -> bool: return t in permission) and _note(card).atr(_note(card).placeholder_text) == "⟦Press No to add a note⟧", "C16: the card's who line (the tool as written), count, buttons and note (%s, %s)" % [card.header_text(), card.count_text()])
	var fold := panel.tool_fold("u1")
	_check(fold.header_text() == "▾ ⟦2 tool calls⟧ (⟦1 failed⟧)" and fold.shown_calls() == ["⟦ok⟧ Settings / Resume", "⟦failed⟧ {n} / {n}"], "C16: the tool fold's line and statuses, the summaries as written (%s; %s)" % [fold.header_text(), fold.shown_calls()])
	fold.show_details("t2", true)
	_check(fold.details_text("t2").begins_with("⟦Tool: {tool}\nAgent: main⟧"), "C16: a call's details, the tool's name as written (%s)" % fold.details_text("t2"))
	fold.show_details("t2", false)
	store.apply({"type": "permission.resolved", "session": "l2", "seq": 13, "permission": "p1", "decision": "deny", "by": "external"})
	await _settle()
	var question: Array = shown.call(card)
	wrong = question.filter(func(t: String) -> bool: return t.contains("⟦Settings⟧") or t.contains("⟦Resume⟧") or t.contains("⟦Back⟧"))
	_check(wrong.is_empty() and card.header_text().contains("Settings") and ["Settings", "Back", "Resume"].all(func(t: String) -> bool: return t in question), "C16: a question's header, text, options and descriptions as written, and the subagent's name (bracketed: %s)" % [wrong])
	_check(card.header_text() == "⟦Subagent Settings asks:⟧" and card.count_text() == "" and "⟦Send⟧" in question, "C16: a subagent's question, its name as written (%s)" % card.header_text())
	# Content holding placeholders, where our words wrap it (security
	# review): the sidecar's reasons, a mode id, a subagent's name.
	panel._send_error = "Couldn't send: {reason}"
	panel._send_reason = "Settings {reason}"
	panel._refresh_status()
	_check(panel.status_text() == "⟦Couldn't send: Settings {reason}⟧", "C16: a send refused, the sidecar's reason as written (%s)" % panel.status_text())
	panel._send_error = ""
	panel._refresh_status()
	card._error = "Couldn't answer: {reason}"
	card._error_reason = "Settings {reason}"
	card._render()
	_check(card.error_text() == "⟦Couldn't answer: Settings {reason}⟧", "C16: an answer refused, the sidecar's reason as written (%s)" % card.error_text())
	card._error = ""
	card._render()
	store.apply({"type": "session.updated", "session": "l2", "seq": 15, "mode": "{mode}"})
	_check(panel.mode_text() == "⟦Mode: {mode}⟧" and PermissionModes.plan_choice("{mode}") == "⟦Yes, and switch to {mode} mode⟧" and PermissionModes.plan_choice("plan") == "⟦Yes, and switch to ⟦Plan⟧ mode⟧", "C16: an unknown mode id as written, in the header and a plan's choice (%s)" % panel.mode_text())
	store.apply({"type": "session.updated", "session": "l2", "seq": 16, "mode": "auto"})
	var named := _agent("s2", "main", "working")
	named["name"] = "{tool}"
	store.apply({"type": "agent.spawned", "session": "l2", "seq": 17, "agent": named})
	var asking: String = card._who_text({"kind": "permission", "item": {"agent": "s2", "tool": "Back {tool}"}})
	_check(asking == "⟦Subagent {tool} asks to use Back {tool}:⟧", "C16: a subagent named \"{tool}\" asking for a tool, both as written (%s)" % asking)
	# Back in English, the chrome is said again at once.
	TranslationServer.set_locale("en")
	await _settle()
	_check(panel.mode_text() == "Mode: Auto" and panel.usage_text() == "Context 31% · ↑ 61k in · ↓ 1.2k out" and panel.turn_hints() == [["u1", "↓ 1.2k tokens"]] and card.header_text() == "Subagent Settings asks:" and fold.header_text() == "▾ 2 tool calls (1 failed)" and panel.status_text().begins_with("Waiting for a permission"), "C16: the chat's chrome follows the language (%s; %s; %s)" % [panel.mode_text(), card.header_text(), fold.header_text()])
	TranslationServer.set_locale(Pot.PSEUDO_LOCALE)
	await _settle()
	panel.close()
	store.apply({"type": "session.ended", "session": "l2", "seq": 30, "reason": "exited"})
	await _settle()


# C16: in the made-up language, the drawn HUDs and the corners: the
# crosshair's hint, the hotbar, the sessions ring, the big map, A05's
# count, C08's limits and W04's arrow, with a session whose title,
# project and limit names are the menus' words ("Settings", "Back",
# "Resume") or hold placeholders ("{n}", "{when}"), shown as written. Back in English, the corners follow.
func _huds(world: Node3D, player: Player) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	var attention: Attention = world.attention
	var corner: UsageLimits = world.usage_limits
	var focused := attention.is_focused
	attention.is_focused = func() -> bool: return true # no flash or chime
	var now := SessionStore.unix_time("2026-10-08T12:00:00Z")
	var now_before := corner.now
	corner.now = func() -> float: return now
	var snap := _snapshot("l3")
	snap["title"] = "Settings"
	snap["project"] = {"path": "/p", "name": "Back {n}"} # placeholders in content stay
	snap["capabilities"] = {"usage": {}}
	snap["agents"][0]["state"] = "waiting"
	var limit := func(label: String, hours: float) -> Dictionary:
		return {"id": label, "label": label, "used_percent": 50, "resets_at": Time.get_datetime_string_from_unix_time(int(now + hours * 3600.0)) + "Z"}
	snap["usage"] = {"tokens": {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}, "context": null,
		"turn": {"message": null, "output_tokens": 0}, "limits": [limit.call("Resume", 0.02), limit.call("Back", 72.0), limit.call("Settings", 480.0), limit.call("{when} {percent}", 1.0)]}
	store.apply({"type": "session.created", "session": snap}) # new: W04 points to it
	await _islands_up(islands)
	var as_written := func(texts: Array) -> bool:
		return texts.all(func(t: String) -> bool: return not (t.contains("⟦Settings⟧") or t.contains("⟦Back⟧") or t.contains("⟦Resume⟧")))
	var bracketed := func(words: Array) -> Array:
		return words.map(func(w: String) -> String: return "⟦%s⟧" % w)

	_check(attention.count_text() == "⟦1 session waiting⟧", "C16: A05's count (%s)" % attention.count_text())
	var limits := corner.text()
	var clock := limits.contains("⟦AM⟧") or limits.contains("⟦PM⟧")
	var weekday: bool = bracketed.call(UsageText.WEEKDAYS).any(func(w: String) -> bool: return limits.contains(w))
	var month: bool = bracketed.call(UsageText.MONTHS).any(func(m: String) -> bool: return limits.contains(m))
	_check(limits.begins_with("⟦Resume 50% · resets ⟦") and limits.contains("Back 50%") and limits.contains("Settings 50%") and limits.contains("{when} {percent} 50%") and clock and weekday and month and as_written.call([limits]), "C16: C08's limits, their times, days and months, the limits' names as written (%s)" % limits)

	var talk := Interactable.new("Talk", 3.0, 0.5)
	root.get_camera_3d().add_child(talk)
	talk.position = Vector3(0, 0, -1.0)
	await _frames(3)
	await _settle()
	_check(world.crosshair.hint_text().ends_with("  ⟦Talk⟧") and Array(world.crosshair.drawn) == [world.crosshair.hint_text()], "C16: the crosshair's hint (%s)" % [world.crosshair.drawn])
	talk.free()
	world.hotbar.select(world.hotbar.held_slot())
	await _settle()
	_check(Array(world.hotbar.drawn) == bracketed.call(["Hands", "Rod"]), "C16: the hotbar's names (%s)" % [world.hotbar.drawn])
	# Step 5: D01's text, the species under "fish".
	var fish_hud: FishingHud = world.fishing.hud
	fish_hud.say("It got away")
	fish_hud.show_catch(FishSpecies.SPECIES[1]["name"], 34, true)
	await _settle()
	_check(Array(fish_hud.drawn) == ["⟦It got away⟧", "⟦Caught: ⟦Drop-off fish⟧!⟧", "⟦34 cm⟧", "⟦New⟧"], "C16: fishing's line and catch card, the species translated (%s)" % [fish_hud.drawn])
	fish_hud.say("")
	fish_hud.show_catch("Settings {n}", 12, false) # not a species: shown as written
	await _settle()
	_check(fish_hud.card_text() == "⟦Caught: Settings {n}!⟧ ⟦12 cm⟧", "C16: a name the template lacks as written (%s)" % fish_hud.card_text())
	fish_hud._card_age = INF

	var to := islands.island("l3").global_position - player.global_position
	player.rotation.y = atan2(-to.x, -to.z) + PI # facing away
	await _settle()
	var arrow := world.pointers.arrow("l3") as Node2D
	var label: String = arrow.get_node("Label").text if arrow and arrow.visible else ""
	_check(label.begins_with("⟦Back {n} · ") and label.ends_with(" m⟧"), "C16: W04's arrow, its project as written (%s)" % label)

	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	var ring := menu.ring
	await _settle()
	var drawn := Array(ring.drawn)
	_check(menu.ring_open() and "⟦Release Tab to go  ·  click + for a new session  ·  Esc to cancel⟧" in drawn and ("⟦New session (click)⟧" in drawn or "⟦New session⟧" in drawn), "C16: the ring's own words (%s)" % [drawn])
	menu.point_at(ring.position_of("session", "l3"))
	await _settle()
	_check(ring.centre_text() == PackedStringArray(["Settings", "Back {n}", "⟦waiting for you⟧"]) and "Settings" in Array(ring.drawn), "C16: pointing at a session: its title and project as written, its state translated (%s)" % [ring.centre_text()])
	menu.point_at(ring.position_of("platform", ""))
	await _settle()
	_check(ring.centre_text() == PackedStringArray(["⟦Platform⟧", "⟦the spawn platform⟧"]), "C16: and at the platform (%s)" % [ring.centre_text()])
	menu.point_at(ring.centre())
	_release("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)

	var big: WorldMap = world.world_map
	big.open()
	big.zoom = WorldMap.MAX_ZOOM
	var at := islands.island("l3").global_position
	big.centre = Vector2(at.x, at.z)
	await _settle()
	drawn = Array(big.drawn)
	_check("⟦Settings · ⟦waiting for you⟧⟧" in drawn and as_written.call(drawn), "C16: the big map: the title as written, the state translated (%s)" % [drawn])
	big.close()
	player.controls_enabled = true

	world.settings.set_value("game/language", "en")
	await _settle()
	_check(attention.count_text() == "1 session waiting" and corner.text().begins_with("Resume 50% · resets "), "C16: the corners follow the language back (%s; %s)" % [attention.count_text(), corner.text()])
	store.apply({"type": "session.ended", "session": "l3", "seq": 2, "reason": "exited"})
	attention.is_focused = focused
	corner.now = now_before
	await _settle()


# The text [param node] and the nodes under it show, as in
# [method _languages], that is neither bracketed nor content: "where: text".
func _untranslated(node: Node, where: String) -> Array:
	var out := []
	if (node is CanvasItem and not node.is_visible_in_tree()) or (node is Window and not node.visible):
		return out
	if not Languages.is_content(node):
		var shown := []
		if node is Label or node is Button or node is RichTextLabel:
			shown.append(node.text)
		if (node is LineEdit or node is TextEdit) and node.text.is_empty():
			shown.append(node.placeholder_text)
		if node is TabBar:
			for i in node.tab_count:
				shown.append(node.get_tab_title(i))
		if node is Window:
			shown.append(node.title)
		if node is Control and not node.tooltip_text.is_empty():
			shown.append(node.tooltip_text)
		for text: String in shown:
			var seen := node.atr(text)
			if Pot._has_letter(seen) and not seen.contains(Pot.OPEN):
				out.append("%s: %s \"%s\"" % [where, node.name, seen])
	for child in node.get_children(true):
		out.append_array(_untranslated(child, where))
	return out


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
	# Performance: each change to the sky redraws its reflection map, a
	# small one; the sun and the colours move every frame, smoothly.
	day.set_hour(17.8)
	var sky: ShaderMaterial = env.sky.sky_material
	var sent: Vector3 = sky.get_shader_parameter("sun_direction")
	var top: Color = sky.get_shader_parameter("top_colour")
	day._process(0.1)
	_check(sky.get_shader_parameter("sun_direction") != sent and sky.get_shader_parameter("top_colour") != top, "the sun, moon and sky colours move every frame, smoothly")
	_check(env.sky.radiance_size == Sky.RADIANCE_SIZE_64, "on a 64 px reflection map")
	sent = sky.get_shader_parameter("sun_direction")
	sky.set_shader_parameter("sun_direction", Vector3.UP)
	day.apply()
	_check(sky.get_shader_parameter("sun_direction") == Vector3.UP, "with the clock stopped, nothing is sent again")
	sky.set_shader_parameter("sun_direction", sent)

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
	var refused := c.run("/time speed -1").begins_with("Not a speed") and c.run("/time speed 2m").begins_with("Not a speed")
	var stopped := c.run("/time speed 0")
	var at := day.time
	day._process(60.0)
	_check(stopped.begins_with("Speed 0: time stands still") and day.time == at and c.run("/time query").ends_with("time stands still (speed 0)."), "C09: /time speed 0 stops the clock (%s)" % stopped)
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
	# Its chunks are made on a worker thread and go in a couple a frame:
	# after a jump far out to sea, the floor fills in round you.
	var was := player.global_position
	player.global_position = Vector3(3000, 5, -2000)
	player.velocity = Vector3.ZERO
	var camera := player.get_viewport().get_camera_3d()
	var most := 0
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var before := seabed.chunk_count()
		await process_frame
		most = maxi(most, seabed.chunk_count() - before)
		player.global_position = Vector3(3000, 5, -2000)
		player.velocity = Vector3.ZERO
		if seabed._missing(Vector2(camera.global_position.x, camera.global_position.z)).is_empty() and seabed._pending.is_empty():
			break
	var under := seabed.get_node_or_null("Chunk_%d_%d" % [floori(3000 / Seabed.CHUNK), floori(-2000 / Seabed.CHUNK)])
	_check(seabed._missing(Vector2(camera.global_position.x, camera.global_position.z)).is_empty() and under != null, "far out, the floor fills in round you (%d chunks)" % seabed.chunk_count())
	_check(most <= Seabed.ADDS_PER_FRAME, "at most %d chunks go in a frame (%d)" % [Seabed.ADDS_PER_FRAME, most])
	var fits := under != null
	if under:
		for v: Vector3 in ((under.get_child(0) as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			fits = fits and is_equal_approx(v.y, Seabed.height_at(v.x, v.z))
	await physics_frame
	var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3001, 0, -1999), Vector3(3001, -60, -1999)))
	_check(fits and not hit.is_empty() and absf(hit["position"].y - Seabed.height_at(3001, -1999)) < 2.0, "a chunk made on the worker has the floor's shape and collision")
	player.global_position = was
	player.velocity = Vector3.ZERO
	await _until_wall(func() -> bool: return seabed._missing(Vector2(camera.global_position.x, camera.global_position.z)).is_empty() and seabed._pending.is_empty(), 15.0)
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
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	_check(menu.ring.segments()[0]["kind"] == "platform", "the sessions ring offers the platform")
	menu.point_at(menu.ring.position_of("platform", ""))
	_release("sessions_menu")
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
	_check(menu.hint_visible() and not menu.is_open(), "no sessions yet: \"Hold Tab for sessions\"")
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	_check(menu.ring_open() and not menu.panel_open() and not player.controls_enabled and not menu.hint_visible(), "W07: holding Tab shows the sessions ring and stops the player")
	var segments := menu.ring.segments()
	_check(segments.size() == 1 and segments[0]["kind"] == "platform" and is_zero_approx(segments[0]["angle"]), "W07: no sessions: only ⌂ Platform, at the top")
	_check(menu.ring.pointed().get("kind") == "centre" and menu.ring.centre_text()[0] == "New session", "W07: it opens pointing at the + in the middle")
	_release("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled and menu.listings_asked == 0, "W07: letting go of Tab in the middle only closes it: a quick tap opens nothing")
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled, "W07: Esc closes the ring")
	_release("sessions_menu")
	await _frames(2)
	_check(not menu.is_open() and player.controls_enabled, "W07: and letting go of Tab afterwards does nothing")
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	var went := [0]
	var count_went := func() -> void: went[0] += 1
	menu.go_to_platform.connect(count_went)
	menu.point_at(menu.ring.position_of("platform", ""))
	menu.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames(2)
	_check(not menu.is_open() and player.controls_enabled and went[0] == 0, "W07: the window losing focus (Tab let go elsewhere) closes the ring without acting")
	menu.go_to_platform.disconnect(count_went)
	# The ring's own pointer, held to the ring (user's, 2026-10-12).
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	var ring := menu.ring
	# (Headless, the mouse mode stays visible whatever is asked: the live
	# check sees it captured.)
	_check(ring.pointer() == ring.centre(), "W07: the ring's own pointer starts in the middle")
	var r := ring.radii()
	var rim := r.x + (r.x - r.y) * 0.12
	var push := InputEventMouseMotion.new()
	push.relative = Vector2(0, -2000)
	Input.parse_input_event(push)
	await _frames(1)
	var out := ring.pointer().distance_to(ring.centre())
	_check(ring.pointed().get("kind") == "platform" and out > rim and out <= rim + SessionRing.STRETCH + 0.01, "W07: pushed far past the rim, the pointer gives only a little: %.1f px past" % (out - rim))
	await _until(func() -> bool: return absf(ring.pointer().distance_to(ring.centre()) - rim) < 0.01, 2.0)
	_check(absf(ring.pointer().distance_to(ring.centre()) - rim) < 0.01 and ring.pointed().get("kind") == "platform", "W07: and springs back onto the rim, still pointing")
	menu.point_at(ring.centre())
	_click_at(Vector2(3, 3))
	await _until(func() -> bool: return menu.panel_open(), 2.0)
	_check(menu.panel_open(), "W07: a click acts on the ring's pointer, wherever the system's mouse is")
	_release("sessions_menu")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_release("sessions_menu")
	await _frames(2)
	await _open_create(menu)
	_check(menu.panel_open() and not menu.ring_open() and not player.controls_enabled and menu.page() == SessionsMenu.Page.ADD and menu.entries() == ["+ New session…", "▸ Resume a session…"] and menu.pickers_visible(), "W07: a click on the + opens the create panel: New or Resume, with the cluster and biome")
	_check(menu.listings_asked == 0, "S04: and the sidecar isn't asked for the stored sessions yet")
	# S02: no provider can start a session (its program wasn't found): both
	# greyed out, why in red under them, until it's found again.
	var sc: SidecarClient = menu.sidecar
	var had_program: Variant = sc.providers[0].get("program")
	sc.providers[0]["program"] = {"path": null, "set_by_hand": false, "message": "Claude Code wasn't found."}
	sc.providers_changed.emit()
	await _frames(1)
	_check(menu.entry_disabled("+ New session") and menu.entry_disabled("▸ Resume a session") and menu.entries() == ["+ New session…", "▸ Resume a session…", "Claude Code wasn't found. Or choose it yourself in Settings → Providers."], "S02: no program found: New and Resume greyed out, why and where to choose it (%s)" % [menu.entries()])
	sc.providers[0]["program"] = {"path": null, "set_by_hand": true, "message": "The Claude Code set in Settings doesn't work: There's no program at that path. Choose it again, or reset it."}
	sc.providers_changed.emit()
	await _frames(1)
	_check(menu.entries().back() == "The Claude Code set in Settings doesn't work: There's no program at that path. Choose it again, or reset it. (Settings → Providers)", "S02: one set by hand that doesn't work: said so")
	if had_program == null:
		sc.providers[0].erase("program")
	else:
		sc.providers[0]["program"] = had_program
	sc.providers_changed.emit()
	await _frames(1)
	_check(not menu.entry_disabled("+ New session") and not menu.entry_disabled("▸ Resume a session") and menu.entries() == ["+ New session…", "▸ Resume a session…"], "S02: found again (or still looking): both back")
	_check(not menu.waiting_for_picker() and not menu.launcher.busy() and menu.notice_text() == "", "W07: the click on + only opens the panel: no picker, no start, no notice")
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
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled and menu.hint_visible(), "where Esc closes it")
	await _open_create(menu)
	_check(menu.page() == SessionsMenu.Page.ADD and menu.biome_choice() == Biome.RANDOM, "it opens on Add session, the biome back to Random each time")
	menu.choose("▸ Resume a session")
	_press("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled, "Tab closes it from any page")
	# Choosing a folder ends in the launcher's create().
	var sidecar: SidecarClient = root.get_node("Sidecar")
	await _until_wall(func() -> bool: return sidecar.status == SidecarClient.Status.READY, 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "the sidecar is up")

	# C12: the model, effort and mode selectors, from the provider's lists
	# (the fake offers Claude's), Default first and back to it each time.
	await _open_create(menu)
	_check(menu.launch_choices("model") == ["Default", "Opus", "Sonnet", "Haiku", "Fable"] and menu.launch_choices("effort") == ["Default", "Low", "Medium", "High", "Extra high", "Max"] and menu.launch_choices("mode") == ["Default", "Manual", "Accept edits", "Plan", "Auto"], "C12: model, effort and mode offer Default, then the provider's list")
	_check(menu.launch_visible("model") and menu.launch_visible("effort") and menu.launch_visible("mode") and menu.launch_choice().is_empty(), "C12: all three show, at Default: nothing picked")
	menu.choose_launch("model", "Haiku")
	menu.choose_launch("mode", "Plan")
	_check(menu.launch_choice() == {"model": "haiku", "mode": "plan"}, "C12: a pick is the provider's id; Default is left out")
	menu.choose("▸ Resume a session")
	_check(menu.launch_visible("model") and menu.launch_choice() == {"model": "haiku", "mode": "plan"}, "C12: the Resume page shows them too, the picks kept")
	_press("ui_cancel")
	await _until(func() -> bool: return menu.page() == SessionsMenu.Page.ADD, 2.0)
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	await _open_create(menu)
	_check(menu.launch_choice().is_empty() and menu.launch_choices("model")[0] == "Default", "C12: reopened, all back to Default")
	# What reaches the sidecar: the picks with a new session or a resume; none at Default.
	var recorder := _LaterRecorder.new()
	recorder.providers = sidecar.providers
	menu.launcher.sidecar = recorder
	menu.choose_launch("effort", "Max")
	menu.choose_launch("mode", "Auto")
	var folder_answer := [Callable()]
	menu.native_picker = true
	menu.show_native = func(_dir: String, callback: Callable) -> Error:
		folder_answer[0] = callback
		return OK
	menu.choose("+ New session")
	await _frames(2)
	folder_answer[0].call(true, PackedStringArray([OS.get_user_data_dir()]), 0)
	await _until(func() -> bool: return recorder.sent.size() == 1, 2.0)
	_check(recorder.sent.size() == 1 and recorder.sent[0][0] == "session.create" and recorder.sent[0][1].get("launch") == {"effort": "max", "mode": "auto"}, "C12: a new session is asked for with the picks")
	menu.native_picker = false
	await _frames(2)
	menu.launcher.create(OS.get_user_data_dir())
	await _frames(2)
	menu.launcher.resume("fake", "n1")
	await _frames(2)
	_check(recorder.sent.size() == 3 and not recorder.sent[1][1].has("launch") and not recorder.sent[2][1].has("launch"), "C12: with nothing picked, no launch is sent")
	menu.launcher.sidecar = sidecar
	recorder.free()
	menu.launcher._say("") # the recorder's refusals
	await _settle()

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
		await _open_create(menu)
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
	await _until_wall(func() -> bool: return menu.notice_text().begins_with("Couldn't"), 5.0)
	_check(menu.notice_text().contains("does not exist") and not menu.launcher.busy(), "a missing folder is refused, and the notice says so")
	menu.native_picker = false

	# A session that's slow to start (its terminal may have closed unseen):
	# a faded segment in the ring, and the create panel can stop waiting.
	var started := [0]
	menu.launcher.session_started.connect(func(_id: String) -> void: started[0] += 1)
	menu.launcher.pending = "slow"
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	segments = menu.ring.segments()
	_check(segments.size() == 2 and segments[1]["kind"] == "starting", "W07: a start under way is a segment in the ring")
	menu.point_at(menu.ring.position_of("starting", "slow"))
	_check(menu.ring.pointed().get("kind") == "platform", "W07: which can't be pointed at")
	menu.point_at(menu.ring.centre())
	_click_at(menu.ring.centre())
	await _until(func() -> bool: return menu.panel_open(), 2.0)
	_release("sessions_menu")
	_check(menu.entries().has("✕ Stop waiting for the session starting"), "a start under way: the create panel offers to stop waiting")
	menu.choose("✕ Stop waiting")
	await _frames(2)
	_check(not menu.launcher.busy() and menu.notice_text().begins_with("Stopped waiting") and not menu.entries().has("✕ Stop waiting for the session starting"), "stopping frees the launcher for another start")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(started[0] == 0, "and nobody waits for it any more")


# W07: the ring with h1 and h2 running in one cluster: where they sit,
# pointing, a cluster folding and fanning out, and letting go of Tab on a
# session or the platform.
func _ring(world: Node3D, player: Player) -> void:
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	var ring := menu.ring
	var islands: SessionIslands = world.get_node("SessionIslands")
	var c1 := islands.clusters.cluster_of("h1")
	var shown := func() -> Array:
		return ring.segments().map(func(s: Dictionary) -> Array: return [s["kind"], s["id"]])
	player.controls_enabled = true # _quit's Quit left the game quitting
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	_check(menu.ring_open(), "W07: (the ring open, with h1 and h2 running)")
	_check(shown.call() == [["platform", ""], ["session", "h1"], ["session", "h2"]], "W07: the ring: ⌂ Platform at the top, then the cluster's sessions: %s" % [shown.call()])
	var segments := ring.segments()
	_check(segments[1]["angle"] > 0.0 and segments[2]["angle"] > segments[1]["angle"] and segments[1]["cluster"] == c1 and segments[2]["cluster"] == c1, "W07: clockwise, together as their cluster's arc")
	menu.point_at(ring.position_of("session", "h2"))
	_check(ring.pointed().get("id") == "h2" and ring.centre_text() == PackedStringArray(["New session", "demo", "idle"]), "W07: pointing at one shows its title, project and state in the middle: %s" % [ring.centre_text()])
	var out := (ring.position_of("session", "h2") - ring.centre()).normalized()
	menu.point_at(ring.centre() + out * ring.radii().x * 1.5)
	_check(ring.pointed().get("id") == "h2", "W07: pointing goes by direction: beyond the ring still points at it")
	menu.point_at(ring.position_of("session", "h1"))
	menu.launcher.pending = "late"
	await _frames(2)
	_check(ring.segments().size() == 4 and ring.pointed().get("id") == "h1", "W07: a segment arriving mid-hold doesn't change what a still pointer selects")
	menu.launcher.pending = ""
	await _frames(2)
	ring.max_segments = 1
	await _frames(2)
	_check(shown.call() == [["platform", ""], ["fold", c1]], "W07: past the most segments, a busy cluster folds into one: %s" % [shown.call()])
	menu.point_at(ring.position_of("fold", c1))
	_check(ring.fanned() == "" and ring.centre_text()[1] == "2 sessions", "W07: not fanned out at once; the middle counts its sessions (%s)" % [ring.centre_text()])
	await _until(func() -> bool: return ring.fanned() == c1, 2.0)
	_check(ring.fanned() == c1 and shown.call().count(["session", "h1"]) == 1 and shown.call().count(["session", "h2"]) == 1, "W07: pointing at it a moment fans its sessions out")
	menu.point_at(ring.position_of("session", "h1"))
	_check(ring.pointed().get("id") == "h1" and ring.fanned() == c1 and ring.pointer().distance_to(ring.position_of("session", "h1")) < 0.01, "W07: and one of them can be pointed at, the pointer free out to the fan")
	menu.point_at(ring.position_of("platform", ""))
	_check(ring.fanned() == "" and ring.pointed().get("kind") == "platform", "W07: pointing elsewhere folds it back")
	ring.max_segments = SessionRing.MAX_SEGMENTS
	await _frames(2)
	menu.point_at(ring.position_of("session", "h2"))
	_release("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	await _frames(20)
	_check(not menu.is_open() and player.controls_enabled and player.global_position.distance_to(islands.orchestrator("h2").global_position) < 7.0, "W07: letting go of Tab on a session takes you to its island")
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	menu.point_at(ring.position_of("platform", ""))
	_release("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	await _frames(2)
	_check(player.global_position.distance_to(player.spawn_point) < 0.2, "W07: and on ⌂ Platform, to the spawn platform")


# Holds Tab and clicks the ring's +: the create panel (W07).
func _open_create(menu: SessionsMenu) -> void:
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	_click_at(menu.ring.centre())
	await _until(func() -> bool: return menu.panel_open(), 2.0)
	_release("sessions_menu")
	await _frames(1)


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
	_check(m.zipline() == null, "W10: its zipline waits for its bridges")
	await _until_wall(func() -> bool: return not islands.is_rising("m1"), 6.0)
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
	var landings: Array[Vector3] = []
	for e in ends:
		landings.append(e - m.global_position)
	_check(m.generator.zipline_room(landings, m.zipline_valley) >= IslandGenerator.BRIDGE_CLEAR, "W10: its zipline's cable keeps clear of its bridges")
	# Its zipline: E by the bottom post rides you up, E at the top down.
	var zip := m.zipline()
	_check(zip != null and islands.island("m1") == m, "W10: a mountain has a zipline")
	if zip:
		player.global_position = zip.to_global(zip.low) + Vector3(0.5, 0.1, 0)
		player.velocity = Vector3.ZERO
		await physics_frame
		_face(player, zip.ends[0].global_position)
		await physics_frame
		await physics_frame
		_check(world.crosshair.hint_text() == "E  Zipline up", "C11: looking at its bottom post: \"%s\"" % world.crosshair.hint_text())
		_press("interact")
		await _until(func() -> bool: return zip.is_riding(), 1.0)
		var started := zip.is_riding() and player.riding
		# A bridge landing on its cable mid-ride moves it, once you're off.
		var valley := m.zipline_valley
		var blocked := landings.duplicate()
		blocked.append(zip.high)
		m.set_landings(blocked)
		var stayed := m.zipline() == zip and m.zipline_valley == valley
		await _until(func() -> bool: return not player.riding, 8.0)
		var up := not player.riding and player.global_position.y > m.global_position.y + m.edge_height() - 0.5
		_check(started and up, "W10: E by its bottom post rides you up to the shoulder (%.1f m)" % (player.global_position.y - m.global_position.y))
		await physics_frame
		await physics_frame
		var moved := m.zipline() != null and not is_instance_valid(zip) and m.zipline_valley != valley
		_check(stayed and moved and m.generator.zipline_room(blocked, m.zipline_valley) >= IslandGenerator.BRIDGE_CLEAR, "W10: a bridge landing on its cable moves it to another valley, not mid-ride")
		zip = m.zipline()
		player.global_position = zip.to_global(zip.high) + Vector3(0, 0.1, 0)
		await physics_frame
		_face(player, zip.ends[1].global_position)
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


# C14: the game opens on the main menu over the world, the camera
# circling; Play eases it down to the player, at once even while the
# sidecar starts.
func _menu_start(world: Node3D, player: Player) -> void:
	var menu: MainMenu = world.main_menu
	var camera: MenuCamera = world.menu_camera
	var own: Camera3D = player.get_node("Head/Camera3D")
	_check(menu.is_open() and menu.get_node("Panel").visible and menu.get_node("Dim").visible and not player.controls_enabled, "C14: the game opens on the main menu, the world dimmed, the player still")
	_check((menu.find_child("Title", true, false) as Label).text == MainMenu.TITLE and MainMenu.BUTTONS.all(func(b: String) -> bool: return menu.button(b).is_visible_in_tree()), "C14: the title, Play, Settings, Credits and Quit")
	_check(get_root().get_camera_3d() == camera and camera.mode() == MenuCamera.Mode.ORBIT, "C14: the menu's camera circles")
	_check(not world.usage_limits.visible and not world.pointers.visible and world.minimap.hidden_when.call() and not world.crosshair.shown(), "C14: no HUD under it")
	var at := camera.global_position
	await _frames(10)
	_check(camera.global_position.distance_to(at) > 0.01 and camera.global_position.y >= MenuCamera.MIN_HEIGHT - 0.1, "C14: it moves round, high up")
	_press("sessions_menu")
	await _frames(2)
	_check(not world.get_node("SessionsMenu").is_open(), "C14: keys wait under it")
	_press("ui_cancel")
	await _frames(2)
	_check(menu.is_open() and not world.pause_menu.is_open(), "C14: Esc on it does nothing")
	var played := [false]
	menu.played.connect(func() -> void: played[0] = true, CONNECT_ONE_SHOT)
	menu.button("Play").pressed.emit()
	_check(not menu.get_node("Panel").visible and camera.mode() == MenuCamera.Mode.DESCEND and not player.controls_enabled, "C14: Play hides the menu and the camera eases down, never held back")
	await _until(func() -> bool: return played[0], MenuCamera.EASE_TIME + 2.0)
	_check(played[0] and not menu.is_open() and player.controls_enabled and get_root().get_camera_3d() == own, "C14: once there, the player's own camera and the controls")
	_check(world.usage_limits.visible and world.pointers.visible, "C14: and the HUD back")


# C17: the opening covers the main menu at start, keys waiting under it,
# for at least its card's time, then fades into the menu. Then on
# stand-in clients: its bar's stages, the wait for the first island and
# its cap, a failure, and a sidecar already failed.
func _opening(world: Node3D, player: Player) -> void:
	var opening: Opening = world.opening
	var shown_at := _game_ms()
	_check(opening.is_covering() and opening.visible and world.main_menu.is_open() and not player.controls_enabled, "C17: the game opens on the opening, over the main menu")
	_check(not opening.bar_shown() and (opening.find_child("Developer", true, false) as Label).text == Opening.DEVELOPER and (opening.find_child("GodotLogo", true, false) as TextureRect).texture == Opening.GODOT_LOGO, "C17: the logo, the developer's name and Godot's logo, no bar at first")
	var logo: TextureRect = opening.find_child("Logo", true, false)
	_check(int(logo.custom_minimum_size.x) % Opening.LOGO.get_width() == 0 and logo.custom_minimum_size.x >= 2 * Opening.LOGO.get_width(), "C17: the logo in whole steps of its pixels (%s)" % logo.custom_minimum_size)
	_press("sessions_menu")
	await _frames(2)
	_check(not world.get_node("SessionsMenu").is_open() and opening.is_covering(), "C17: keys wait under it (an action isn't a skip)")
	# Closing the window still asks: the quit dialog over it, Esc reaching
	# the dialog rather than the opening (security review, 2026-10-28).
	var guard: QuitGuard = world.quit_guard
	var guard_quit: Callable = guard.quit
	var quits := [0]
	guard.quit = func() -> void: quits[0] += 1
	world.store.sessions["q1"] = _snapshot("q1")
	guard.request_quit()
	await process_frame
	_check(guard.is_asking() and opening.is_covering() and quits[0] == 0, "C17: closing the window while it covers asks, the quit dialog over it")
	for pressed in [true, false]:
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = pressed
		Input.parse_input_event(esc)
	await _frames(2)
	_check(not guard.is_asking() and quits[0] == 0, "C17: Esc reaches the dialog: back to the game")
	world.store.sessions.erase("q1")
	guard.quit = guard_quit
	var lifted := [false]
	opening.lifted.connect(func() -> void: lifted[0] = true, CONNECT_ONE_SHOT)
	await _until_wall(func() -> bool: return lifted[0], 30.0)
	var took := (_game_ms() - shown_at) / 1000.0
	_check(lifted[0] and not opening.is_covering() and not opening.visible and took >= Opening.CARD_S - 0.1, "C17: synced, no sessions back: it fades into the menu after its card's time (%.1f s)" % took)
	_check(world.main_menu.is_open() and world.main_menu.get_node("Panel").visible, "C17: the main menu under it")

	var store := SessionStore.new()
	var islands: SessionIslands = world.get_node("SessionIslands")
	# Still starting: a skip shows the bar at once, naming the stage.
	var client := SidecarClient.new()
	client.status = SidecarClient.Status.STARTING
	var other := Opening.new()
	root.add_child(other)
	other.setup(client, store, islands)
	other.skip()
	await process_frame
	await process_frame
	_check(other.is_covering() and other.bar_shown() and other.stage_text() == "Starting the sidecar…", "C17: skipped while starting: the bar, \"%s\"" % other.stage_text())
	client._attempt = 1
	await process_frame
	_check(other.stage_text() == "Starting the sidecar (try 2 of 3)…", "C17: a retry says which try (%s)" % other.stage_text())
	var before := other.bar_value()
	client.status = SidecarClient.Status.SYNCING
	await _frames(10)
	_check(other.stage_text() == "Finding your sessions…" and other.bar_value() > before, "C17: connected: finding the sessions, the bar further on")
	# Synced with sessions back: it waits for the first island to rise.
	store.sessions["o1"] = _snapshot("o1")
	client.status = SidecarClient.Status.READY
	client.synced.emit([])
	await _frames(5)
	_check(other.is_covering() and other.stage_text() == "Bringing up your islands…", "C17: synced with sessions back: it waits for their islands")
	var other_lifted := [false]
	other.lifted.connect(func() -> void: other_lifted[0] = true, CONNECT_ONE_SHOT)
	islands.island_rising.emit("o1")
	await _until(func() -> bool: return other_lifted[0], Opening.FADE_OUT_S + 1.0)
	_check(other_lifted[0] and not other.is_covering(), "C17: the first island rising lifts it")
	other.free()
	# An island that never rises: lifted once the wait is over.
	var capped := Opening.new()
	var synced_client := SidecarClient.new()
	synced_client.status = SidecarClient.Status.SYNCING
	root.add_child(capped)
	capped.setup(synced_client, store, islands)
	capped.skip()
	synced_client.status = SidecarClient.Status.READY
	synced_client.synced.emit([])
	await _frames(5)
	_check(capped.is_covering(), "C17: no island yet: still covering")
	capped._synced_at -= Opening.ISLAND_WAIT_S
	await _until(func() -> bool: return not capped.is_covering(), Opening.FADE_OUT_S + 1.0)
	_check(not capped.is_covering(), "C17: lifted %d s after the sync without an island" % Opening.ISLAND_WAIT_S)
	capped.free()
	store.sessions.clear()
	# A failure lifts it (S01 says why); one already failed covers nothing.
	var failing := Opening.new()
	client.status = SidecarClient.Status.STARTING
	root.add_child(failing)
	failing.setup(client, store, islands)
	failing.skip()
	client.status = SidecarClient.Status.FAILED
	await _until(func() -> bool: return not failing.is_covering(), Opening.FADE_OUT_S + 1.0)
	_check(not failing.is_covering(), "C17: a failed sidecar lifts it")
	failing.free()
	# A start stuck past every bound: lifted all the same.
	var stuck := Opening.new()
	client.status = SidecarClient.Status.STARTING
	root.add_child(stuck)
	stuck.setup(client, store, islands)
	stuck.skip()
	await _frames(2)
	_check(stuck.is_covering() and stuck.bar_shown(), "C17: a start that takes long: the bar")
	stuck._elapsed = Opening.TIMEOUT_S
	await _until(func() -> bool: return not stuck.is_covering(), Opening.FADE_OUT_S + 1.0)
	_check(not stuck.is_covering(), "C17: past %d s it lifts whatever happens" % Opening.TIMEOUT_S)
	stuck.free()
	client.status = SidecarClient.Status.FAILED
	var none := Opening.new()
	root.add_child(none)
	none.setup(client, store, islands)
	_check(not none.is_covering() and not none.visible, "C17: a sidecar already failed: no opening")
	none.free()
	client.free()
	synced_client.free()


# S01: the sidecar can't be started (user's decisions, 2026-10-28). The
# first start failing quits, saying why; a restart in play failing says
# to quit, its button going through the quit guard. On stand-in clients.
func _sidecar_lost(world: Node3D, player: Player) -> void:
	_check(world.sidecar_lost.get_parent() == world and not world.sidecar_lost.is_notifying(), "S01: the notice is in the world, not showing")
	var guard: QuitGuard = world.quit_guard
	# The first start fails: a message box, then the game quits.
	var first := SidecarClient.new()
	first.status = SidecarClient.Status.STARTING
	var lost := SidecarLost.new()
	var said := []
	var quits := [0]
	lost.alert = func(text: String) -> void: said.append(text)
	lost.quit = func() -> void: quits[0] += 1
	root.add_child(lost)
	lost.setup(first, guard, player)
	first.failed.emit("The sidecar didn't start in time.")
	_check(quits[0] == 1 and said.size() == 1 and said[0].contains("can't run without its sidecar") and said[0].contains("didn't start in time") and not lost.visible, "S01: the first start fails: says why, then quits")
	lost.free()
	first.free()
	# Failed before the world was there (no program to start): the same.
	var early := SidecarClient.new()
	early.status = SidecarClient.Status.FAILED
	early.failure = "The sidecar is missing from the game folder."
	lost = SidecarLost.new()
	said.clear()
	quits[0] = 0
	lost.alert = func(text: String) -> void: said.append(text)
	lost.quit = func() -> void: quits[0] += 1
	root.add_child(lost)
	lost.setup(early, guard, player)
	await _frames(1)
	_check(quits[0] == 1 and said.size() == 1 and said[0].contains("missing from the game folder"), "S01: failed before the world was up: says why, then quits")
	lost.free()
	early.free()
	# A restart in play fails: the notice, the controls held, keys wait.
	var in_play := SidecarClient.new()
	in_play.status = SidecarClient.Status.STARTING
	in_play.has_synced = true
	lost = SidecarLost.new()
	quits[0] = 0
	lost.quit = func() -> void: quits[0] += 1
	root.add_child(lost)
	lost.setup(in_play, guard, player)
	var controls_before := player.controls_enabled
	var mouse_before := Input.mouse_mode
	in_play.failed.emit("The sidecar stopped.")
	_check(lost.visible and lost.shown_text().contains("couldn't be started again") and lost.shown_text().contains("The sidecar stopped.") and quits[0] == 0 and not player.controls_enabled, "S01: a restart in play fails: the notice says to quit, the game stays, controls held")
	_press("sessions_menu")
	await _frames(2)
	_check(not world.get_node("SessionsMenu").is_open(), "S01: keys wait under it")
	# Quit goes through the guard: with sessions running it asks; back to
	# the game, the notice again.
	var guard_quits := [0]
	var guard_quit_before: Callable = guard.quit
	guard.quit = func() -> void: guard_quits[0] += 1
	world.store.sessions["lost1"] = _snapshot("lost1")
	lost.quit_button().pressed.emit()
	_check(guard.is_asking() and not lost.visible and guard_quits[0] == 0, "S01: Quit: the quit guard lists the sessions still running first")
	# Back to the game, as the dialog's button does.
	guard.dialog().hide()
	guard.dialog().canceled.emit()
	_check(lost.visible and not player.controls_enabled, "S01: back to the game from it: the notice again")
	world.store.sessions.erase("lost1")
	lost.quit_button().pressed.emit()
	_check(guard_quits[0] == 1 and quits[0] == 0, "S01: with none running, Quit quits")
	guard.quit = guard_quit_before
	lost.free()
	in_play.free()
	player.controls_enabled = controls_before
	Input.mouse_mode = mouse_before


# S07's cover isn't in the world any more (C14 shows the menu instead);
# kept, and still tested, in case it's wanted again (user's, 2026-10-26).
func _loading_cover(world: Node3D, player: Player) -> void:
	for status in [SidecarClient.Status.READY, SidecarClient.Status.FAILED, SidecarClient.Status.STOPPED]:
		var other := LoadingCover.new()
		var stand_in := SidecarClient.new()
		stand_in.status = status
		root.add_child(other)
		other.setup(stand_in, player)
		_check(not other.is_covering() and not other.visible and player.controls_enabled, "S07: no cover when the sidecar is %s" % SidecarClient.Status.keys()[status])
		other.free()
		stand_in.free()
	# One still starting: the failure lifts it too.
	var starting := SidecarClient.new()
	starting.status = SidecarClient.Status.CONNECTING
	var waits := LoadingCover.new()
	root.add_child(waits)
	waits.setup(starting, player)
	_check(waits.is_covering() and waits.visible and not player.controls_enabled, "S07: covered while it connects")
	_press("sessions_menu")
	await _frames(2)
	_check(not world.get_node("SessionsMenu").is_open(), "S07: keys wait under it")
	starting.failed.emit("test")
	_check(not waits.is_covering() and player.controls_enabled, "S07: a failed sidecar lifts it")
	waits.free()
	starting.free()


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
	var island := islands.island("h1")
	_check(island != null and not island.is_built() and island.position.y == SessionIslands.BUILDING_Y and islands.is_rising("h1"), "C14: its ground is made on a worker thread, the island out of sight meanwhile")
	await _until_wall(func() -> bool: return island.is_built(), 5.0)
	_check(island.is_built() and island.position.y < -1.0 and islands.is_rising("h1"), "C14: then a session already running's island rises too")
	# h2 only now: islands made at once finish in any order, and the first
	# up gets the bridge to the platform (checked below).
	store.apply({"type": "session.snapshot", "session": _snapshot("h2")})
	var early := Island.new()
	early.build_in_background = true
	early.position.y = -500.0 # out of the way
	world.add_child(early)
	var early_props := early.props
	early.free()
	_check(not is_instance_valid(early_props), "W01: an island freed before its props went in frees them too")
	await _islands_up(islands)
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
	_check(island.position.y == 0.0 and not islands.is_rising("h1"), "and its island is up")
	_restart_chat(world)
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
	_lap("_big_map")
	await _settle()
	_check(minimap.shown_cluster() == c1, "the minimap is back once the big map closes")
	await _quit(world, player)
	_lap("_quit")
	await _ring(world, player)
	_lap("_ring")

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
	await _crosshair(world, player, orchestrator)
	_lap("_crosshair")
	await _hotbar(world, player)
	_lap("_hotbar")
	await _fishing(world, player, island)
	_lap("_fishing")
	# The sidecar doesn't have h1, so fetching its history fails.
	await _until_wall(func() -> bool: return not chat._history.has("h1"), 5.0)
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
	_lap("_tool_log")
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 10, "agent": "main", "state": "waiting", "reason": "permission"})
	_check(panel.status_text().contains("above or in the terminal"), "a permission wait points to the card and the terminal")
	store.apply({"type": "session.notice", "session": "h1", "seq": 11, "notice": {"code": "transcripts_off", "message": "x"}})
	_check(panel.get_node("Layout/Notices").visible, "notices show")
	await _card(store, panel)
	_lap("_card")
	await _usage(world, store, panel)
	_lap("_usage")

	# Sending to a session the sidecar doesn't have: refused, text kept.
	panel.set_draft("hello")
	panel.send()
	_check(panel.draft() == "", "sending clears the box")
	await _until_wall(func() -> bool: return panel.status_text().begins_with("Couldn't send"), 5.0)
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
	await _frames(2)
	_check(not chat.is_open() and world.crosshair.target() == orchestrator.talk and player.controls_enabled, "Esc closes the chat")

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
	# C02: the view stays at the end every frame while older rows go in
	# above, not a frame late (the chat jittered).
	var bar: VScrollBar = panel.get_node("Layout/Scroll").get_v_scroll_bar()
	var off_end := [0]
	for f in 3000:
		if not panel.is_loading():
			break
		await _frames(1)
		if absf(bar.value - (bar.max_value - bar.page)) > 1.0:
			off_end[0] += 1
	_check(panel.shown_messages() == expected, "then all of it, in order")
	_check(off_end[0] == 0 and bar.max_value > bar.page * 3.0, "C02: the view at the end in every frame while it's built (%d frames off)" % off_end[0])
	# Scrolled up while it's built: the same distance from the end every frame.
	store.replace_history("h1", long_chat.duplicate())
	await _frames(2)
	bar.value = bar.max_value - bar.page - 300.0
	var from_end := bar.max_value - bar.value
	var moved := [0]
	for f in 3000:
		if not panel.is_loading():
			break
		await _frames(1)
		if absf(bar.max_value - bar.value - from_end) > 1.0:
			moved[0] += 1
	await _frames(ChatPanel.SETTLE_FRAMES + 1)
	_check(moved[0] == 0 and absf(bar.max_value - bar.value - from_end) <= 1.0 and panel.shown_messages() == expected, "C02: scrolled up, it keeps its distance from the end every frame (%d frames off)" % moved[0])
	# /clear: the sidecar's history is empty, so the window clears at once.
	store.apply({"type": "session.updated", "session": "h1", "seq": 23, "native_id": "n3"})
	store.apply({"type": "session.notice", "session": "h1", "seq": 24, "notice": {"code": "conversation_cleared", "message": "x"}})
	store.replace_history("h1", [])
	await _frames(1)
	shown = panel.get_node("Layout/Notices").text
	_check(panel.shown_messages().is_empty() and shown.contains("(/clear)") and not shown.contains("(/resume)"), "after /clear the chat is empty, with its notice")
	await _sign_in(world, panel)
	_lap("_sign_in")
	await _read_only_marks(world, panel)
	_lap("_read_only_marks")
	await _attention(world)
	_lap("_attention")
	var on_island := player.global_position
	store.apply({"type": "session.ended", "session": "h1", "seq": 30, "reason": "exited"})
	# Waits hold weak references: a lambda can't capture a freed object.
	var orchestrator_ref: WeakRef = weakref(orchestrator)
	var island_ref: WeakRef = weakref(island)
	await _until(func() -> bool: return orchestrator_ref.get_ref() == null and not chat.is_open(), 2.0)
	_check(islands.island("h1") == null and not is_instance_valid(orchestrator) and not chat.is_open() and player.controls_enabled, "an ended session's orchestrator goes, and its chat closes")
	_check(chat.bubble("h1") == null and world.crosshair.target() == null, "nothing of it is left to talk to")
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
	# Built (its main-thread part takes a few frames, W01): from then on it
	# rises from where you'd see it.
	await _until_wall(h3.is_built, 5.0)
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
	var h5_at := islands.island("h5").global_position
	_check(Vector2(h5_at.x, h5_at.z).is_equal_approx(Vector2(SessionClusters.cluster_position(0).x, SessionClusters.cluster_position(0).z)), "its spot is free again")
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
	# S07: a session taken back whose hooks can't reach the game says so in
	# our words, whatever the provider's message.
	store.apply({"type": "session.notice", "session": "h1", "seq": 45, "notice": {"code": "reattached_read_only", "message": "provider text"}})
	await _frames(1)
	_check(notices.call().contains("This session started before the game restarted, so it's read-only here.") and not notices.call().contains("provider text"), "S07: the read-only notice, in our words")
	store.apply({"type": "session.notice_cleared", "session": "h1", "seq": 46, "code": "reattached_read_only"})
	# S07: a read-only session's chat has no message box, a line instead; others keep theirs.
	_check(panel._compose.visible and not panel._read_only_hint.visible, "S07: a session the world drives has its message box")
	var watched := _snapshot("h9")
	watched["read_only"] = true
	store.apply({"type": "session.snapshot", "session": watched})
	panel.open("h9")
	await _frames(1)
	_check(not panel._compose.visible and panel._read_only_hint.visible and panel._read_only_hint.text == "Read-only: use its terminal.", "S07: a read-only session's chat: no message box, the hint instead")
	panel.set_draft("hi")
	panel.send()
	_check(panel.draft() == "hi" and not panel._watching.has("h9"), "S07: nothing is sent to a read-only session")
	panel.set_draft("")
	panel.open("h1")
	await _frames(1)
	_check(panel._compose.visible and not panel._read_only_hint.visible, "S07: back on a session the world drives, its box is back")
	store.apply({"type": "session.ended", "session": "h9", "seq": 2, "reason": "exited"})
	state.call(46, "error", "rate_limit")
	_check(panel.status_text().begins_with("Stopped: a usage or rate limit"), "a failed turn says what stopped it")
	state.call(47, "error", "overloaded")
	_check(panel.status_text().contains("overloaded"), "and another reason its own")
	state.call(48, "error", "unknown")
	_check(panel.status_text() == "Stopped.", "an unknown reason says only Stopped.")
	state.call(49, was["state"], was.get("reason"))
	await _frames(2)


# S08: an island the world only watches has the grey flag, whatever made it
# read-only (S07's or started outside the game); the chat line says where to
# chat with an outside one, and its notice is in our words.
func _read_only_marks(world: Node3D, panel: ChatPanel) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	_check(not islands.island("h1").read_only(), "S08: an island the world drives has no read-only mark")
	var outside := _snapshot("o1")
	outside["read_only"] = true
	outside["origin"] = "external"
	outside["notices"] = [{"code": "outside_read_only", "message": "provider text"}]
	var ours := _snapshot("o2")
	ours["read_only"] = true
	store.apply({"type": "session.snapshot", "session": outside})
	store.apply({"type": "session.created", "session": ours})
	await _frames(2)
	for id: String in ["o1", "o2"]:
		var i := islands.island(id)
		_check(i.read_only() and i.has_node("ReadOnlyFlag"), "S08: the read-only mark on %s's island" % id)
	# Where it stands only once the ground is in: mid-build, surface_height
	# already reads the new ground but the flag is re-placed only in the
	# last step, out of sight (S08 dev log, 2026-10-27).
	await _until_wall(func() -> bool: return islands.island("o1").is_built() and islands.island("o2").is_built(), 10.0)
	for id: String in ["o1", "o2"]:
		var i := islands.island(id)
		var flag := i.get_node_or_null("ReadOnlyFlag") as Node3D
		if flag:
			var r := Vector2(flag.position.x, flag.position.z).length()
			_check(r > 3.0 and absf(flag.position.y - i.generator.surface_height(flag.position.x, flag.position.z)) < 0.01, "S08: %s's flag stands on its island, near the edge (r %.1f)" % [id, r])
	# Once its bridges land, it keeps clear of them.
	await _until(func() -> bool: return not islands.is_rising("o2"), 10.0)
	await _frames(2)
	for id: String in ["o1", "o2"]:
		var i := islands.island(id)
		var flag := i.get_node("ReadOnlyFlag") as Node3D
		var at := Vector2(flag.position.x, flag.position.z)
		_check(not i.landings().is_empty() and i.landings().all(func(l: Vector3) -> bool: return Vector2(l.x, l.z).distance_to(at) > 3.0), "S08: %s's flag keeps clear of its bridges" % id)
	# The maps mark them too, and only them. The minimap is shown for this
	# even with the chat open.
	var minimap: Minimap = world.minimap
	var hidden_when := minimap.hidden_when
	minimap.hidden_when = func() -> bool: return false
	await _frames(2)
	var shown := islands.cluster_islands(minimap.shown_cluster())
	_check(islands.island("o1") in shown and islands.island("o2") in shown and islands.island("h1") in shown, "S08: the minimap shows the read-only islands' cluster")
	_check(shown.all(func(i: Island) -> bool: return (i in minimap.marked()) == i.read_only()), "S08: the minimap marks the read-only islands, and only them")
	minimap.hidden_when = hidden_when
	var big: WorldMap = world.world_map
	var controls := (world.get_node("Player") as Player).controls_enabled
	big.open()
	big.zoom = big.min_zoom()
	big.centre = Vector2(islands.island("o1").global_position.x, islands.island("o1").global_position.z)
	await _frames(2)
	_check(islands.island("o1") in big.marked() and islands.island("o2") in big.marked() and islands.island("h1") not in big.marked(), "S08: so does the big map")
	big.zoom = WorldMap.MAX_ZOOM
	await _frames(2)
	_check(islands.island("o1") in big.marked(), "S08: zoomed in too")
	big.close()
	(world.get_node("Player") as Player).controls_enabled = controls
	panel.open("o1")
	await _frames(1)
	var notices: String = panel.get_node("Layout/Notices").text
	_check(notices.contains("This session was started outside the game, so it's read-only here. Use its own window to chat with it.") and not notices.contains("provider text"), "S08: the outside notice, in our words (the user's)")
	_check(not panel._compose.visible and panel._read_only_hint.text == "Read-only: use its own window.", "S08: an outside session's chat points to its own window")
	panel.open("o2")
	await _frames(1)
	_check(panel._read_only_hint.text == "Read-only: use its terminal.", "S08: S07's read-only line stays its own")
	# A resync that changes it moves the mark.
	var driven := _snapshot("o2")
	driven["seq"] = 5
	store.apply({"type": "session.snapshot", "session": driven})
	await _frames(1)
	_check(not islands.island("o2").read_only(), "S08: no longer read-only, no mark")
	driven["seq"] = 6
	driven["read_only"] = true
	store.apply({"type": "session.snapshot", "session": driven})
	await _frames(1)
	_check(islands.island("o2").read_only(), "S08: read-only again, the mark again")
	panel.open("h1")
	store.apply({"type": "session.ended", "session": "o1", "seq": 2, "reason": "user"})
	store.apply({"type": "session.ended", "session": "o2", "seq": 7, "reason": "exited"})
	await _frames(1)
	_check(islands.island("o1") == null and islands.island("o2") == null, "S08: turned off (reason user) or gone, the session goes like any other")
	# One started outside the game mid-game rises like any, but isn't
	# marked as new: no beacon, no arrow (the user's, 2026-10-26).
	var risen := _snapshot("o3")
	risen["read_only"] = true
	risen["origin"] = "external"
	store.apply({"type": "session.created", "session": risen})
	await _frames(2)
	_check(islands.is_rising("o3") and not islands.island("o3").has_node("NewBeacon") and not "o3" in islands.unvisited() and not "o3" in world.pointers.shown(), "S08: an outside session's island rises with no new-island beacon or arrow")
	store.apply({"type": "session.ended", "session": "o3", "seq": 2, "reason": "exited"})
	await _frames(1)


# A05: h1's orchestrator waits on a permission; h2's comes and goes.
func _attention(world: Node3D) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var attention: Attention = world.attention
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	# The test's own settings file (_scene), emptied.
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
	var settings_menu: SettingsMenu = world.settings_menu
	settings_menu.open()
	settings_menu.show_tab("Sound")
	_check(settings_menu.sound_toggle().is_visible_in_tree() and settings_menu.sound_toggle().button_pressed, "attention: the settings' Sound tab has the toggle, on (C10)")
	settings_menu.sound_toggle().button_pressed = false
	settings_menu.close()
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
	focused[0] = true
	state.call(9, "idle")
	await _frames(1)
	# In a fishing fight (D01) a new wait pulses the corner once.
	attention.busy = func() -> bool: return true
	var pulsed := attention.pulses
	state.call(10, "waiting", "permission")
	await _frames(2)
	_check(attention.pulses == pulsed + 1 and asked[0] == 2 and chimes[0] == 1, "attention: a new wait in a fishing fight pulses the corner once, nothing else (D01)")
	state.call(11, "waiting", "question")
	await _frames(2)
	_check(attention.pulses == pulsed + 1, "attention: once per wait in a fight too")
	attention.busy = world.fishing.fighting
	state.call(12, "idle")
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
	_check(text.contains("come back when you start the game again") and text.ends_with("On a computer shared with other accounts, end them with /exit before quitting: while the game is closed, another account could reach them."), "quit (S07): they come back, and the line for a shared computer")
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
	# S08: a session started outside the game never had our hooks; quitting
	# changes nothing for it, so it isn't counted or listed.
	var outside := _snapshot("x1")
	outside["origin"] = "external"
	outside["read_only"] = true
	outside["title"] = "outside one"
	empty.store.apply({"type": "session.snapshot", "session": outside})
	empty.request_quit()
	_check(quits[0] == 21, "quit (S08): with only outside sessions running, it just quits")
	var ours := _snapshot("x2")
	ours["read_only"] = true
	empty.store.apply({"type": "session.snapshot", "session": ours})
	get_root().add_child(empty)
	empty.setup(empty.store, player)
	empty.request_quit()
	await _settle()
	_check(quits[0] == 21 and empty.shown_text().begins_with("1 session is still running") and not empty.shown_text().contains("outside one"), "quit (S08): S07's read-only one counted, the outside one left out")
	empty.dialog().get_cancel_button().pressed.emit()
	await _frames(1)
	empty.free()
	await _quit_many(player)
	_lap("_quit_many")


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
	await _until_wall(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer") and card.current()["kind"] == "permission", "card: a refused answer says so and stays")
	_check(not card.denying() and not _note(card).editable and _note(card).text == "not that one", "card: Yes locks the note again, keeping it")
	_click(card, "No")
	_check(_note(card).text == "not that one", "card: No again, the note is still there")
	_click(card, "Send")
	await _until_wall(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
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
	await _until_wall(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
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


# Answers session.get_history with the messages given per session.
class _Histories extends SidecarClient:
	var histories := {}
	var asked := []

	func send_command(type: String, fields: Dictionary = {}, on_reply := Callable()) -> String:
		if type != "session.get_history":
			return ""
		asked.append(fields["session"])
		on_reply.call({"type": "ok", "result": {"messages": histories.get(fields["session"], []), "tools": []}})
		return "h%d" % asked.size()


# S01 restart: the sessions keep their ids, so their islands and chats stay;
# once the restart has synced, each loaded chat is fetched again (what was
# said while the sidecar was down), once; an empty history (transcripts
# off) keeps ours. Stand-ins: the dev fake takes nothing back.
func _restart_chat(world: Node3D) -> void:
	var store: SessionStore = world.store
	var chat: ChatController = world.get_node("ChatController")
	var real := chat.sidecar
	var answers := _Histories.new()
	chat.sidecar = answers
	var was := chat._history.duplicate()
	chat._history["h1"] = "loaded"
	chat._history["h2"] = "loaded"
	store.apply({"type": "message.started", "session": "h1", "seq": 900, "message": "live1", "agent": "main", "role": "user"})
	store.apply({"type": "message.started", "session": "h2", "seq": 900, "message": "live2", "agent": "main", "role": "user"})
	answers.histories["h1"] = [{"message": "t1", "agent": "main", "role": "user", "text": "from the transcript", "at": "2026-09-30T10:00:00Z"}]
	chat._on_synced()
	_check(answers.asked.is_empty(), "S01 restart: a sync without a restart fetches nothing")
	root.get_node("Sidecar").restarting.emit("a test")
	chat._on_synced()
	answers.asked.sort()
	_check(answers.asked == ["h1", "h2"], "S01 restart: each loaded chat fetched again once it synced")
	_check(store.messages("h1").map(func(m: Dictionary) -> String: return m["message"]) == ["t1"], "S01 restart: the new sidecar's chat replaces ours")
	_check(store.messages("h2").map(func(m: Dictionary) -> String: return m["message"]) == ["live2"], "S01 restart: an empty history keeps ours")
	chat._on_synced()
	_check(answers.asked.size() == 2, "S01 restart: once")
	chat.sidecar = real
	chat._history = was
	answers.free()
	for id in ["h1", "h2"]:
		store.begin_chat_replace(id)
		store.replace_history(id, [])


# Records like [_Recorder], refusing on the next frame as the sidecar would,
# so the launcher isn't left busy.
class _LaterRecorder extends _Recorder:
	func send_command(type: String, fields: Dictionary = {}, on_reply := Callable()) -> String:
		sent.append([type, fields])
		if on_reply.is_valid():
			on_reply.call_deferred({"type": "error", "message": "recorded"})
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
	# C12: the model and effort beside the mode, with model_info.
	_check(panel.model_text() == "", "C12: no model shown without model_info")
	snap = store.session("h1").duplicate(true)
	snap["seq"] = 32
	snap["capabilities"] = {"permission_modes": {}, "plans": {}, "model_info": {}}
	snap["model"] = null
	snap["effort"] = null
	store.apply({"type": "session.snapshot", "session": snap})
	_check(panel.model_text() == "", "C12: nothing shown while neither is known")
	store.apply({"type": "session.updated", "session": "h1", "seq": 33, "effort": {"id": "high", "label": "High"}})
	_check(panel.model_text() == "High effort", "C12: the effort alone")
	store.apply({"type": "session.updated", "session": "h1", "seq": 34, "model": {"id": "claude-opus-5-5", "label": "Opus 5.5"}})
	_check(panel.model_text() == "Opus 5.5 · High effort" and panel.mode_text().begins_with("Mode: "), "C12: model and effort in the header, beside the mode")
	store.apply({"type": "session.updated", "session": "h1", "seq": 35, "effort": null})
	_check(panel.model_text() == "Opus 5.5", "C12: a model with no effort level")
	store.apply({"type": "session.updated", "session": "h1", "seq": 36, "model": {"id": "x", "label": "[b]x[/b]"}})
	_check(panel.model_text() == "[b]x[/b]", "C12: a provider's label is plain text")


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
	await _islands_up(islands)
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

	# Done: throws its report to its parent (s1, still at its PC), which
	# bobs, then goes.
	var s1 := agents.subagent("s1")
	var s2 := agents.subagent("s2")
	var s2_slot := s2.slot
	var paper := s2.get_node("Worker/Paper") as Node3D
	var thrown_at := _game_ms()
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 5, "agent": "s2", "state": "done", "reason": null})
	_check(s2.is_leaving() and paper.visible and s2.shown_state() == "", "agents: a done one stands up with its paper")
	await _until(func() -> bool: return paper.top_level, 1.0)
	_check(paper.top_level and s2.worker_position().distance_to(s2.global_position) < 0.3, "agents: and throws it from its PC (after %d ms)" % (_game_ms() - thrown_at))
	var across := func() -> float: return Vector2(paper.global_position.x - s1.catch_point().x, paper.global_position.z - s1.catch_point().z).length()
	var far: float = across.call()
	await _frames(12)
	_check(across.call() < far * 0.85 and paper.global_position.y > s2.worker_position().y + 1.0, "agents: the paper flies in an arc to whoever called it")
	var s1_worker := s1.get_node("Worker") as Node3D
	await _until(func() -> bool: return s1_worker.position.y > 0.02, 1.5)
	_check(s1_worker.position.y > 0.02 and not paper.visible, "agents: it bobs as the paper lands")
	await _until(func() -> bool: return agents.subagent("s2") == null, 2.0)
	var took := _game_ms() - thrown_at
	_check(agents.subagent("s2") == null and agents.subagent_count() == 2 and took < 1800, "agents: and the thrower is gone with its PC in about 1.3 s (%d ms)" % took)
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 6, "agent": _agent("s3", "main", "working")})
	_check(agents.subagent("s3").slot == s2_slot, "agents: a freed slot is reused")

	# Resumed mid-throw: back at its PC, the paper put away.
	var s3 := agents.subagent("s3")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 7, "agent": "s3", "state": "done", "reason": null})
	var s3_paper := s3.get_node("Worker/Paper") as Node3D
	await _until(func() -> bool: return s3_paper.top_level, 1.0)
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 8, "agent": "s3", "state": "working", "reason": null})
	await _frames(30)
	_check(agents.subagent("s3") == s3 and not s3.is_leaving() and s3.worker_position().distance_to(s3.global_position) < 0.01 and not s3_paper.visible and not s3_paper.top_level, "agents: resumed mid-throw, it is back at its PC, the paper put away")

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

	# Thrown to the orchestrator, 10+ m away, in the same short time:
	# it bobs, and every one of them goes.
	var body := orchestrator.get_node("Body") as Node3D
	var body_y := body.position.y
	thrown_at = _game_ms()
	for a in ["s0", "s1", "s3"]:
		store.apply({"type": "agent.state_changed", "session": "h4", "seq": 11, "agent": a, "state": "done", "reason": null})
	await _until(func() -> bool: return body.position.y > body_y + 0.02, 2.0)
	_check(body.position.y > body_y + 0.02, "agents: the orchestrator bobs as a paper lands")
	await _until(func() -> bool: return agents.subagent_count() == 0, 3.0)
	took = _game_ms() - thrown_at
	_check(agents.subagent_count() == 0 and took < 1800, "agents: all throw to the orchestrator and go, in %d ms (%d left)" % [took, agents.subagent_count()])
	await _frames(20)
	_check(is_equal_approx(body.position.y, body_y), "agents: and it settles back")

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
	await _open_create(menu)
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
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	menu.point_at(menu.ring.position_of("session", id))
	_check(menu.ring.pointed().get("id") == id and menu.ring.centre_text()[0] == "New session", "live: a new session is in the ring as \"New session\"")
	_press("ui_cancel")
	_release("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)

	await _until(func() -> bool: return chat.history_loaded(id), 5.0)
	_check(chat.history_loaded(id), "live: its history is loaded")
	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await physics_frame
	_face(player, orchestrator.talk.global_position)
	await _until(func() -> bool: return world.crosshair.target() == orchestrator.talk, 2.0)
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
	_lap("_sign_in_pickup")
	panel.pickup_timeout = 15.0
	_check(world.store.sessions[id].get("title") == "hello", "live: the first message's first line names the session")
	panel.set_draft("rename Tidy the notes")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Renamed"), 8.0)
	_check(world.store.sessions[id].get("title") == "Tidy the notes", "live: renaming it renames it")

	# Subagents: the fake provider spawns them, they work and throw their reports back.
	var agents := islands.agents(id)
	panel.set_draft("agents 3")
	panel.send()
	await _until(func() -> bool: return agents.subagent_count() == 3, 8.0)
	_check(agents.subagent_count() == 3, "live: three subagents appear")
	await _until(func() -> bool: return agents.subagent_count() == 0, 18.0)
	_check(agents.subagent_count() == 0, "live: and all throw their reports and go when done")
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
	_check(panel.model_text() == "Opus 5.5 · High effort", "live: and its model and effort (C12; the fake's defaults)")
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

	# The open ring follows a rename.
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	menu.point_at(menu.ring.position_of("session", id))
	_check(menu.ring.centre_text()[0] == "Tidy the notes", "live: the ring shows its name")
	sidecar.send_command("message.send", {"session": id, "text": "rename Notes"})
	await _until(func() -> bool: return menu.ring.centre_text()[0] == "Notes", 5.0)
	_check(menu.ring.centre_text()[0] == "Notes", "live: and follows a rename while open")
	_press("ui_cancel")
	_release("sessions_menu")
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
	var lists_before := menu.listings_asked
	await _open_create(menu)
	_check(menu.listings_asked == lists_before, "live: the ring and Add session don't ask for the stored sessions")
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
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	menu.point_at(menu.ring.position_of("session", resumed))
	_check(menu.ring.pointed().get("id") == resumed and menu.ring.centre_text()[0] == "Add a save system", "live: now in the ring")
	_press("ui_cancel")
	_release("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	await _open_create(menu)
	menu.choose("▸ Resume a session")
	await _until(func() -> bool: return is_listed.call("Fix the player"), 5.0)
	_check(is_listed.call("Fix the player") and not is_listed.call("Add a save system"), "live: and not under Resume")
	_press("ui_cancel")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	player.respawn()
	_hold("sessions_menu")
	await _until(func() -> bool: return menu.ring_open(), 2.0)
	menu.point_at(menu.ring.position_of("session", resumed))
	_release("sessions_menu")
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


# C11: the crosshair by an orchestrator: nothing while looking away, too
# far or behind something; looking at it, it grows and says "E  Talk";
# E acts only on what it is on; hidden while the controls are off.
func _crosshair(world: Node3D, player: Player, orchestrator: Orchestrator) -> void:
	var crosshair: Crosshair = world.crosshair
	var chat: ChatController = world.get_node("ChatController")
	var talk := orchestrator.talk
	await physics_frame
	_face(player, talk.global_position + (talk.global_position - player.global_position) * Vector3(-1, 0, -1))
	await _frames(15)
	_check(crosshair.shown() and crosshair.target() == null and crosshair.hint_text() == "" and is_zero_approx(crosshair.grown()), "C11: close but looking away: the crosshair stays small, no hint")
	_press("interact")
	await _frames(2)
	_check(not chat.is_open(), "C11: and E does nothing")
	_face(player, talk.global_position)
	await _until(func() -> bool: return crosshair.grown() >= 1.0, 2.0)
	_check(crosshair.target() == talk and crosshair.hint_text() == "E  Talk" and crosshair.grown() >= 1.0, "C11: looking at the orchestrator, it grows, \"%s\"" % crosshair.hint_text())
	# A wall in between.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(3, 3, 0.2)
	wall.add_child(shape)
	world.add_child(wall)
	var camera := player.get_node("Head/Camera3D") as Node3D
	wall.global_position = camera.global_position.lerp(talk.global_position, 0.4)
	wall.look_at(talk.global_position, Vector3.UP)
	await _frames(3)
	_check(crosshair.target() == null, "C11: not through a wall")
	wall.queue_free()
	await _frames(3)
	_check(crosshair.target() == talk, "C11: and again once it's gone")
	# Too far: back off along the view.
	var near := player.global_position
	var away := (player.global_position - talk.global_position) * Vector3(1, 0, 1)
	player.global_position += away.normalized() * (talk.reach + 1.0)
	await physics_frame
	_face(player, talk.global_position)
	await _frames(3)
	_check(crosshair.target() == null, "C11: not from further than its reach (%.1f m)" % talk.reach)
	player.global_position = near
	await physics_frame
	_face(player, talk.global_position)
	await _frames(3)
	crosshair.ring_on = false
	await _frames(2)
	_check(crosshair.target() == talk and crosshair.hint_text() == "E  Talk", "C11: the setting hides the ring, not the aiming or the hint")
	crosshair.ring_on = true
	player.controls_enabled = false
	await _frames(2)
	_check(not crosshair.shown() and crosshair.hint_text() == "" and crosshair.target() == null, "C11: hidden without the controls (chat, menus, the ring, the map)")
	player.controls_enabled = true
	await _frames(2)


# C15: the hotbar, by the number keys and the wheel, its fade, and nothing
# without the controls.
func _hotbar(world: Node3D, player: Player) -> void:
	var hotbar: Hotbar = world.hotbar
	var changes := []
	hotbar.held_changed.connect(func(tool: String) -> void: changes.append(tool))
	_check(hotbar.held_tool() == "hands" and is_zero_approx(hotbar.shown()), "C15: empty hands at the start, the hotbar hidden")
	_key(KEY_2)
	await _settle()
	_check(hotbar.held_tool() == "rod" and changes == ["rod"] and is_equal_approx(hotbar.shown(), 1.0), "C15: 2 takes the rod and shows the hotbar")
	_key(KEY_9)
	await _settle()
	_check(hotbar.held_tool() == "rod" and changes.size() == 1, "C15: a number past the last tool does nothing")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _settle()
	_check(hotbar.held_tool() == "hands", "C15: the wheel down from the last slot goes round to the first")
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	await _settle()
	_check(hotbar.held_tool() == "rod" and changes == ["rod", "hands", "rod"], "C15: the wheel up goes round the other way")
	await _until(func() -> bool: return is_zero_approx(hotbar.shown()), Hotbar.SHOW_TIME + Hotbar.FADE_TIME + 1.0)
	_check(is_zero_approx(hotbar.shown()), "C15: it fades out when left alone")
	player.controls_enabled = false
	_key(KEY_1)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await _settle()
	_check(hotbar.held_tool() == "rod" and is_zero_approx(hotbar.shown()), "C15: nothing without the controls (chat, menus, the ring, the map)")
	player.controls_enabled = true
	_key(KEY_1)
	await _settle()
	_check(hotbar.held_tool() == "hands", "C15: 1 puts it away")


# D01: what bites where and when, by the species table's conditions.
func _fish_species() -> void:
	var here := {"water": "shallows", "biome": Biome.Kind.BEACH, "hour": 10.0, "weather": "clear"}
	_check(FishSpecies.pick(here, 0.5)["id"] == "shallows_fish", "D01: the shallows' placeholder bites in the shallows")
	here["water"] = "drop_off"
	_check(FishSpecies.pick(here, 0.5)["id"] == "drop_off_fish", "D01: the drop-off's at the drop-off")
	here["water"] = "open_sea"
	here["biome"] = -1
	_check(FishSpecies.pick(here, 0.99)["id"] == "open_sea_fish", "D01: the open sea's out at sea, away from islands")
	_check(FishSpecies.water_at(1.0) == "shallows" and FishSpecies.water_at(6.0) == "drop_off" and FishSpecies.water_at(20.0) == "open_sea", "D01: the water's kind by its depth")
	var table := [
		{"id": "night", "name": "N", "water": ["shallows"], "biomes": [], "hours": [20.0, 4.0], "weather": [], "size": [10, 20], "weight": 1.0},
		{"id": "forest_rain", "name": "F", "water": ["shallows"], "biomes": [Biome.Kind.FOREST], "hours": [], "weather": ["rain", "storm"], "size": [10, 20], "weight": 3.0},
		{"id": "any", "name": "A", "water": ["shallows", "drop_off"], "biomes": [], "hours": [], "weather": [], "size": [10, 20], "weight": 1.0},
	]
	var ids := func(c: Dictionary) -> Array: return FishSpecies.matching(c, table).map(func(sp: Dictionary) -> String: return sp["id"])
	_check(ids.call({"water": "shallows", "biome": Biome.Kind.BEACH, "hour": 12.0, "weather": "clear"}) == ["any"], "D01: by day on a beach in the sun, only what lives anywhere")
	_check(ids.call({"water": "shallows", "biome": Biome.Kind.BEACH, "hour": 23.0, "weather": "clear"}) == ["night", "any"] and ids.call({"water": "shallows", "biome": -1, "hour": 2.0, "weather": "clear"}) == ["night", "any"], "D01: a night fish at night, past midnight too")
	_check(ids.call({"water": "shallows", "biome": Biome.Kind.FOREST, "hour": 12.0, "weather": "rain"}) == ["forest_rain", "any"], "D01: a forest fish by a forest island in the rain")
	_check(ids.call({"water": "shallows", "biome": Biome.Kind.FOREST, "hour": 12.0, "weather": "windy"}) == ["any"] and ids.call({"water": "shallows", "biome": -1, "hour": 12.0, "weather": "rain"}) == ["any"], "D01: not in other weather, nor away from its biome")
	_check(ids.call({"water": "open_sea", "biome": -1, "hour": 12.0, "weather": "clear"}) == [] and FishSpecies.pick({"water": "open_sea", "biome": -1, "hour": 12.0, "weather": "clear"}, 0.5, table).is_empty(), "D01: nothing where nothing lives")
	var rain := {"water": "shallows", "biome": Biome.Kind.FOREST, "hour": 12.0, "weather": "rain"}
	_check(FishSpecies.pick(rain, 0.7, table)["id"] == "forest_rain" and FishSpecies.pick(rain, 0.8, table)["id"] == "any", "D01: picked by weight among those that match")
	var sp: Dictionary = FishSpecies.SPECIES[0]
	_check(FishSpecies.size_for(sp, 0.0) == sp["size"][0] and FishSpecies.size_for(sp, 1.0) == sp["size"][1] and FishSpecies.size_for(sp, 0.5) < (sp["size"][0] + sp["size"][1]) / 2.0, "D01: sizes within the species' range, big ones rarer")
	var unique := {}
	for s: Dictionary in FishSpecies.SPECIES:
		unique[s["id"]] = true
	_check(unique.size() == FishSpecies.SPECIES.size(), "D01: every species' id is its own")


# D01: the fight on its own, stepped at 60 frames a second: how the
# strain, the rod and the line answer, the ways a fish is lost, and
# whole fights by four ways of playing, with fixed seeds.
func _fish_fight() -> void:
	var dt := 1.0 / 60.0
	# A fresh fish [param dist] metres out, the line taut unless [param slack].
	var fresh := func(species: Dictionary, size: int, dist: float, s := 1, slack := 0.0) -> FishFight:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		return FishFight.new(species, size, Vector2(0, -dist), dist + slack, rng)
	var sea: Dictionary = FishSpecies.named("open_sea_fish")
	var every := true
	for s: Dictionary in FishSpecies.SPECIES:
		every = every and s.get("pull", 0.0) > 0.0 and s.get("stamina", 0.0) > 0.0 and s.get("temper", 0.0) > 0.0
	_check(every and FishSpecies.named("shallows_fish")["pull"] < FishSpecies.named("drop_off_fish")["pull"] and FishSpecies.named("drop_off_fish")["stamina"] < sea["stamina"], "D01: every species fights by its pull, stamina and temper, the open sea's hardest")
	var small: FishFight = fresh.call(sea, 40, 20.0)
	var big: FishFight = fresh.call(sea, 120, 20.0)
	_check(big.power() > small.power() * 1.4, "D01: a bigger fish pulls harder (%.2f, %.2f)" % [small.power(), big.power()])
	# The fish held on one way (no turns, no runs unless [param run]),
	# reeled or not, the rod held where it's put.
	var held := func(f: FishFight, heading: float, reeling: bool, rod: float, seconds: float, run := false) -> FishFight:
		f.heading = heading
		f._turn_in = INF
		f._run_in = INF
		f.running = run
		for i in roundi(seconds * 60.0):
			f.rod = rod
			f.step(dt, Vector2.ZERO, reeling)
		return f
	var on_run: FishFight = fresh.call(sea, 80, 20.0)
	var rest_power := on_run.power()
	on_run.running = true
	_check(on_run.power() > rest_power * 3.0, "D01: on a run it pulls far harder than between runs (%.2f, %.2f)" % [on_run.power(), rest_power])
	var reeled: FishFight = held.call(fresh.call(sea, 80, 20.0), 0.0, true, 0.0, 1.2, true)
	var given: FishFight = held.call(fresh.call(sea, 80, 20.0), 0.0, false, 0.0, 2.0, true)
	_check(reeled.outcome == "snapped" and given.outcome == "" and given.strain <= 0.1 + FishFight.DRAG_STRAIN * FishFight.DRAG_MOST + 0.01 and given.slack(Vector2.ZERO) < 0.05 and given.line > 22.0 and given.energy < 1.0 - 2.0 / sea["stamina"] * 1.25, "D01: reeling into a run snaps the line; let go, the reel's drag gives line, taut, under the limit, and the run tires it (%s, %.2f, %.1f m out, energy %.2f)" % [reeled.outcome, given.strain, given.line, given.energy])
	var with: FishFight = held.call(fresh.call(sea, 80, 20.0), 1.2, true, 1.0, 0.3)
	var against: FishFight = held.call(fresh.call(sea, 80, 20.0), 1.2, true, -1.0, 0.3)
	_check(with.against() < -0.9 and with.strain > against.strain + 0.3, "D01: the rod held against the fish's side takes its pull; on its side, strains the line (%.2f, %.2f)" % [against.strain, with.strain])
	# Kept on its way: held against, it would turn and come in slack.
	var tired: FishFight = fresh.call(sea, 80, 20.0)
	var tired_with: FishFight = fresh.call(sea, 80, 20.0)
	for f: FishFight in [tired, tired_with]:
		f._turn_in = INF
		f._run_in = INF
		for i in 120:
			f.heading = 1.2
			f.rod = -1.0 if f == tired else 1.0
			f.step(dt, Vector2.ZERO, false)
	_check(tired.energy < tired_with.energy - 0.03, "D01: leaning against it tires it faster (%.2f, %.2f)" % [tired.energy, tired_with.energy])
	var small_fish: Dictionary = FishSpecies.named("shallows_fish")
	var gained: FishFight = held.call(fresh.call(small_fish, 20, 20.0), 1.2, true, -1.0, 1.0)
	var lost: FishFight = held.call(fresh.call(small_fish, 20, 20.0), 1.2, true, 1.0, 1.0)
	_check(gained.line < lost.line - 0.5, "D01: with the rod on the fish's side the reel hardly gains (%.1f m out against it, %.1f with it)" % [gained.line, lost.line])
	var turned: FishFight = fresh.call(sea, 80, 20.0)
	turned.heading = 0.8
	turned._run_in = 5.0
	turned.running = true
	for i in 90:
		turned.rod = -1.0
		turned.step(dt, Vector2.ZERO, false)
	var unturned: FishFight = held.call(fresh.call(sea, 80, 20.0), 0.8, false, 0.0, 0.5, true)
	_check(not turned.running and absf(turned.heading) > PI / 2.0 and absf(unturned.heading - 0.8) < 0.001, "D01: the rod held against a run turns its head round toward you and ends it (heading %.2f)" % turned.heading)
	var pulled: FishFight = fresh.call(sea, 80, 20.0)
	pulled.heading = 1.0
	pulled.running = true
	pulled.rod = 0.0
	var arrow_was := pulled.hint()
	pulled.rod = -1.0
	_check(arrow_was < -0.8 and absf(pulled.hint()) < 0.05, "D01: the arrow points away from the fish's side, gone with the rod held there (%.2f, %.2f)" % [arrow_was, pulled.hint()])
	var dragged: FishFight = fresh.call(sea, 80, 20.0)
	dragged.heading = 1.0
	dragged._turn_in = INF
	dragged.step(dt, Vector2.ZERO, false)
	var drift := dragged.rod
	dragged.push(-0.5)
	_check(drift > 0.0 and is_equal_approx(dragged.rod, drift - 0.5), "D01: a fish swimming right drags the rod's tip right; the mouse pushes it back")
	var snapped: FishFight = held.call(fresh.call(sea, 120, 20.0), 0.0, true, 0.0, 0.5, true)
	_check(snapped.outcome == "", "D01: not at once at the limit (%.2f)" % snapped.strain)
	held.call(snapped, 0.0, true, 0.0, FishFight.SNAP_TIME + 0.3, true)
	_check(snapped.outcome == "snapped", "D01: held at its limit a moment, the line snaps (%s)" % snapped.outcome)
	var ran_out: FishFight = held.call(fresh.call(sea, 80, 20.0), 0.0, false, 0.0, 10.0)
	ran_out.max_line = ran_out.line - 0.5 if ran_out.outcome == "" else ran_out.max_line
	held.call(ran_out, 0.0, false, 0.0, 0.2)
	_check(ran_out.outcome == "snapped", "D01: a fish that runs out all the line snaps it")
	var slipped: FishFight = held.call(fresh.call(sea, 80, 20.0), PI, false, 0.0, FishFight.SLIP_TIME - 0.5)
	_check(slipped.outcome == "" and slipped.slack(Vector2.ZERO) > FishFight.SLIP_SLACK, "D01: a fish coming at you leaves the line slack")
	held.call(slipped, PI, false, 0.0, 1.5)
	_check(slipped.outcome == "slipped", "D01: slack a while, the hook slips (%s)" % slipped.outcome)
	var shore: FishFight = fresh.call(sea, 80, 20.0)
	shore.swimmable = func(at: Vector2) -> bool: return at.y > -20.01
	shore.heading = 0.0
	shore._turn_in = INF
	shore.step(dt, Vector2.ZERO, false)
	_check(is_equal_approx(shore.fish.y, -20.0) and shore._turn_in < INF, "D01: a fish never swims onto land: it turns")
	var landed: FishFight = fresh.call(sea, 40, 3.0)
	held.call(landed, PI, true, 0.0, 2.0)
	_check(landed.outcome == "landed", "D01: reeled to the rod's tip, it's landed")

	# Whole fights, 12 each: "good" pushes where the arrow points and
	# lets go on a run or near the limit, "still" does too but leaves the
	# rod be, "hold" only reels, "idle" never does.
	var play := func(species: Dictionary, dist: float, way: String) -> Dictionary:
		var out := {"landed": 0, "times": []}
		for s in 12:
			var size: int = species["size"][0] + (species["size"][1] - species["size"][0]) * (s % 4) / 3
			var f: FishFight = fresh.call(species, size, dist, s, Fishing.SLACK)
			var reeling := true
			var t := 0.0
			while f.outcome == "" and t < 90.0:
				if way == "good" or way == "still":
					reeling = not f.running and (f.strain < 0.7 or (reeling and f.strain <= 0.85))
					if way == "good":
						f.push(signf(f.hint()) * 3.0 * dt)
				else:
					reeling = way == "hold"
				f.step(dt, Vector2.ZERO, reeling)
				t += dt
			out[f.outcome] = out.get(f.outcome, 0) + 1
			if f.outcome == "landed":
				out["times"].append(t)
		out["times"].sort()
		out["median"] = out["times"][out["times"].size() / 2] if out["times"].size() > 0 else -1.0
		return out
	var lengths := {"shallows_fish": [6.0, 7.0, 16.0], "drop_off_fish": [12.0, 15.0, 32.0], "open_sea_fish": [18.0, 28.0, 55.0]}
	for id: String in lengths:
		var r: Dictionary = play.call(FishSpecies.named(id), lengths[id][0], "good")
		_check(r["landed"] >= 10 and r["median"] >= lengths[id][1] and r["median"] <= lengths[id][2], "D01: played well, a %s %d m out is landed in about %.0f-%.0f s (%d of 12, median %.1f s)" % [id, lengths[id][0], lengths[id][1], lengths[id][2], r["landed"], r["median"]])
		if id != "shallows_fish":
			var left_be: Dictionary = play.call(FishSpecies.named(id), lengths[id][0], "still")
			_check(left_be["landed"] <= r["landed"] - 3 or left_be["median"] > r["median"] * 1.3, "D01: leaving the rod be, a %s takes far longer or gets away (%d of 12, median %.1f s; played well %d, %.1f s)" % [id, left_be["landed"], left_be["median"], r["landed"], r["median"]])
	var hold: Dictionary = play.call(sea, 18.0, "hold")
	_check(hold.get("snapped", 0) >= 9, "D01: only holding the click snaps most open sea fish (%d of 12)" % hold.get("snapped", 0))
	for id in ["drop_off_fish", "open_sea_fish"]:
		var idle: Dictionary = play.call(FishSpecies.named(id), 12.0, "idle")
		_check(idle["landed"] == 0 and idle.get("snapped", 0) + idle.get("slipped", 0) >= 9, "D01: never reeling, no %s is landed, most lost (%s)" % [id, idle])


# D01: the catches kept for the collection (D03): saved, read back, and a
# damaged file kept aside rather than written over.
func _catch_log() -> void:
	var was := CatchLog.file
	CatchLog.file = "user://test-catch-log.json"
	for f in [CatchLog.file, CatchLog.file + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var catches := CatchLog.new()
	catches.load_file()
	_check(catches.caught().is_empty(), "D01: no catches at first")
	var first := catches.record("a", 30, "Beach", "shallows")
	var again := catches.record("a", 25, "Forest", "drop_off")
	catches.record("a", 41, "", "open_sea")
	catches.flush()
	var e := catches.entry("a")
	_check(first and not again and e["count"] == 3 and e["biggest_cm"] == 41, "D01: a species' count and its biggest")
	_check(e["first"]["biome"] == "Beach" and e["first"]["water"] == "shallows" and e["first"]["at"] is String and e["first"]["at"].length() >= 16, "D01: and its first catch, when and where")
	var back := CatchLog.new()
	back.load_file()
	_check(back.caught().size() == 1 and back.caught()[0] == "a" and back.entry("a") == e, "D01: read back as saved")
	var f := FileAccess.open(CatchLog.file, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"species\": {\"a\": {\"count\": \"lots\"}}}")
	f.close()
	back.load_file()
	_check(back.caught().is_empty() and FileAccess.file_exists(CatchLog.file + ".bad"), "D01: a damaged file is kept as .bad and the log starts empty")
	for p in [CatchLog.file, CatchLog.file + ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	CatchLog.file = was


# D01: fishing with the rod, by real clicks: the water and the biome
# under the bobber, shadows in the shallows and aiming at one, a catch
# recorded and saved, scaring a fish off, missing a bite, reeling in,
# leaving, and no cast onto land, while swimming or without the rod.
func _fishing(world: Node3D, player: Player, island: Island) -> void:
	var fishing: Fishing = world.fishing
	_rod_user = fishing
	var hud := fishing.hud
	var was := player.global_position
	var turned := player.rotation.y
	var pitch := (player.get_node("Head") as Node3D).rotation.x
	var caught := []
	fishing.caught.connect(func(id: String, size: int, first: bool) -> void: caught.append([id, size, first]))
	_check(is_equal_approx(fishing.bite_window, 1.5), "D01: the bite's window is 1.5 s")
	fishing.wait = Vector2(0.2, 0.3)
	fishing.aimed_wait = Vector2(0.1, 0.1)
	fishing.approach_time = 0.3
	fishing.nibbles = Vector2i(1, 1)
	fishing.nibble_gap = Vector2(0.3, 0.3)
	fishing.bite_window = 2.0

	# Without the rod a click does nothing.
	_mouse_left(true)
	await _settle()
	_mouse_left(false)
	await _settle()
	_check(fishing.state == Fishing.State.IDLE and not fishing._rod.visible, "D01: no rod in hand: a click does nothing")
	_key(KEY_2)
	await _settle()
	_check(fishing._rod.visible, "D01: 2 takes the rod, seen in your hand")
	# Bottom right, in the same place on screen at any field of view.
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var fov := camera.fov
	var on_screen := []
	for f in [60.0, 110.0]:
		camera.fov = f
		await _settle()
		on_screen.append(camera.unproject_position(fishing._rod.global_position))
	camera.fov = fov
	var screen := camera.get_viewport().get_visible_rect().size
	_check(on_screen[0].distance_to(on_screen[1]) < 2.0 and on_screen[0].x > screen.x * 0.5 and on_screen[0].y > screen.y * 0.5, "D01: the rod bottom right at 60° and 110° (%s, %s)" % on_screen)
	# Only the ground stops the bobber: not the props, agents or you.
	_check(fishing._bobber.collision_mask == 1 << (Fishing.GROUND_LAYER - 1) and fishing._bobber.collision_layer == 0 and island.get_collision_layer_value(Fishing.GROUND_LAYER) and island.get_collision_layer_value(1) and not island.props.get_collision_layer_value(Fishing.GROUND_LAYER), "D01: the bobber collides with the ground layer only, the props aren't on it")

	# On the shore of h1's island, facing away from its bridges.
	var c := island.global_position
	var away := Vector3.ZERO
	var best := -INF
	var islands: SessionIslands = world.get_node("SessionIslands")
	for k in 16:
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 16.0)
		var room := INF
		for other in [Vector3.ZERO, islands.island("h2").global_position]:
			room = minf(room, d.angle_to((other - c) * Vector3(1, 0, 1)))
		if room > best:
			best = room
			away = d
	var shore := island.generator.shore_radius(away.x, away.z)
	_check(fishing.depth_at(c) < 0.0 and fishing.depth_at(c + away * shore * 1.1) > 0.3 and FishSpecies.water_at(fishing.depth_at(c + away * shore * 1.1)) == "shallows", "D01: land under an island, the shallows on its shelf")
	_check(fishing.biome_at(c + away * shore * 1.1) == island.generator.biome and fishing.biome_at(Vector3.ZERO) == -1, "D01: the biome of the island nearest, none at the platform")
	var stand := c + away * shore * 0.93
	player.global_position = Vector3(stand.x, c.y + island.generator.surface_height(away.x * shore * 0.93, away.z * shore * 0.93) + 0.2, stand.z)
	player.velocity = Vector3.ZERO
	await _frames(10)
	_face(player, player.global_position + away * 10.0 + Vector3.DOWN)
	await _until(func() -> bool: return fishing._shadows.size() >= 2, 15.0)
	var in_shallows := not fishing._shadows.is_empty()
	for s in fishing._shadows:
		var depth := fishing.depth_at(s.home) # where it came from: it wanders up to 2 m off
		in_shallows = in_shallows and depth >= Fishing.SHADOW_DEPTH.x and depth < Fishing.SHADOW_DEPTH.y and s.global_position.y < 0.0
	_check(in_shallows, "D01: fish shadows wander in the shallows round you, under the water (%d)" % fishing._shadows.size())
	# A shadow where the bobber settles comes at once, though the wait is
	# long: shadows all along the throw, as where it lands isn't known.
	fishing.wait = Vector2(60.0, 60.0)
	for k in 9:
		var along := player.global_position + away * (2.0 + 3.0 * k)
		fishing._add_shadow(Vector3(along.x, 0.0, along.z))
	await _cast(0.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.WAITING, 4.0)
	var aimed := fishing._fish
	var landed := fishing._bobber.global_position
	_check(fishing.state == Fishing.State.WAITING and is_instance_valid(aimed) and aimed.hooked and Vector2(aimed.position.x - fishing.target.x, aimed.position.z - fishing.target.z).length() < Fishing.AIM_RADIUS, "D01: a tap throws it into the shallows near a shadow, which is the one on the line (%s at %s, %.1f m out, %.2f m deep)" % [Fishing.State.keys()[fishing.state], landed, Vector2(landed.x - player.global_position.x, landed.z - player.global_position.z).length(), fishing.depth_at(landed)])
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	_check(fishing.state == Fishing.State.BITE and hud.bite_mark() and fishing._splash.visible, "D01: it comes, nibbles and bites: the \"!\" and the splash")
	fishing.wait = Vector2(0.2, 0.3)
	# The click on the bite hooks it, and held, reels: the fight. The
	# mouse moves the rod, and the view turns with it.
	_mouse_left(true)
	await _settle()
	_check(fishing.state == Fishing.State.FIGHT and fishing.reeling and player.look_held and world.attention.busy.call() and caught.is_empty() and not hud.bite_mark(), "D01: a click on the bite hooks it: the fight, reeling while held, the view held (%s)" % Fishing.State.keys()[fishing.state])
	var head_pitch := (player.get_node("Head") as Node3D).rotation.x
	var rod_was := fishing.fight.rod
	var yaw_was := player.rotation.y
	_mouse_move(-120.0)
	# The rod moves as the event arrives, the view in the fight's next
	# _process; process_frame comes before _process, so wait for the rod
	# and then two frames (a physics frame alone came between them).
	await _until(func() -> bool: return fishing.fight.rod < rod_was - 0.3, 1.0)
	await _settle()
	var turn := angle_difference(yaw_was, player.rotation.y)
	_check(fishing.fight.rod < rod_was - 0.3 and is_equal_approx((player.get_node("Head") as Node3D).rotation.x, head_pitch), "D01: in a fight the mouse moves the rod's tip (%.2f to %.2f), the view only turning with it" % [rod_was, fishing.fight.rod])
	_check(turn > (rod_was - fishing.fight.rod) * deg_to_rad(Fishing.VIEW_SWING) * 0.5, "D01: the view turns with the rod's tip: pushed left, it turns left (%.1f°)" % rad_to_deg(turn))
	var stood := player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check(player.move_held and Vector2(player.global_position.x - stood.x, player.global_position.z - stood.z).length() < 0.05, "D01: in a fight you stay where you stand: walking does nothing (%.2f m)" % Vector2(player.global_position.x - stood.x, player.global_position.z - stood.z).length())
	var fought: Dictionary = await _land(fishing)
	var shallows: Dictionary = fishing.catches.entry("shallows_fish")
	_check(caught.size() == 1 and caught[0][0] == "shallows_fish" and caught[0][2] and fishing.state == Fishing.State.IDLE and not fishing._bobber.visible and not player.look_held and not player.move_held and not world.attention.busy.call(), "D01: played against its pull, it's landed at the rod's tip, the bobber back and the view yours (%s, %.1f s)" % [fought["outcome"], fought["time"]])
	_check(fought["bent"] and fought["followed"] and fought["under"], "D01: in the fight the rod bends with the strain, the shadow swims where the fish is, the bobber pulled under (%s)" % fought)
	_check(fought["arrow"] and fought["arrow_right"], "D01: the arrow by the crosshair shows where to push the rod, away from the fish's side (%s)" % fought)
	_check(fought["pulled_out"], "D01: won, the fish is pulled up out of the water, hanging from the line, then caught (%s)" % fought)
	var sprayed: bool = fought["spray"]
	_check(not shallows.is_empty() and shallows["count"] == 1 and shallows["first"]["water"] == "shallows" and shallows["first"]["biome"] == Biome.NAMES[island.generator.biome], "D01: recorded with its biome and water (%s)" % [shallows.get("first")])

	# From the platform, away from h1: the drop-off.
	world.go_to_platform()
	await _frames(20)
	var out := (Vector3.ZERO - c) * Vector3(1, 0, 1)
	out = out.normalized()
	# Toward the platform's middle: a tap lands on the deck, rests there
	# and nothing comes; holding reels it in.
	_face(player, Vector3(0, 0.5, 0) - out * 2.0)
	await _cast(0.0)
	await _frames(60)
	var deck := fishing._bobber.global_position
	_check(fishing.state == Fishing.State.OUT and fishing._bobber.visible and absf(deck.x) < 6.0 and absf(deck.z) < 6.0 and deck.y > 0.9 and deck.y < 1.3, "D01: a cast onto the deck lands and rests on it (%s)" % deck)
	await _frames(30)
	_check(fishing.state == Fishing.State.OUT and not is_instance_valid(fishing._fish), "D01: nothing comes to a bobber on land")
	# Walking up to it, the line goes slack and lies on the deck, never
	# through it (the user's live check, 2026-10-27).
	var toward := ((deck - player.global_position) * Vector3(1, 0, 1)).normalized()
	player.global_position = Vector3(deck.x, player.global_position.y, deck.z) - toward * 1.5
	await _frames(10)
	var slack := fishing.line_length - fishing._tip.global_position.distance_to(fishing._bobber.global_position)
	var points := fishing.line_points()
	var through := 0
	for p in points.slice(1, points.size() - 1):
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 3.0, 1 << (Fishing.GROUND_LAYER - 1))
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (hit["position"] as Vector3).y > p.y + 0.001:
			through += 1
	_check(fishing.state == Fishing.State.OUT and slack > 1.0 and through == 0, "D01: walked up to it, the slack line lies on the deck, not through it (%.1f m slack, %d points under)" % [slack, through])
	_mouse_left(true)
	await _until(func() -> bool: return fishing.state == Fishing.State.IDLE, 5.0)
	_mouse_left(false)
	_check(fishing.state == Fishing.State.IDLE and not fishing._bobber.visible, "D01: holding the click reels it in off the deck")
	await _settle()
	_face(player, player.global_position + Vector3(0, 1.0, 0) + out * 30.0)
	await _cast(1.0)
	var flew := Vector2(fishing.target.x - player.global_position.x, fishing.target.z - player.global_position.z).length()
	_check(fishing.state == Fishing.State.WAITING and fishing._bobber.visible and flew > 17.0 and flew < 27.0 and fishing._where["water"] == "drop_off", "D01: a full charge throws it %.1f m where you look, into the drop-off" % flew)
	await _frames(2)
	_check(absf(fishing._bobber.global_position.y - fishing.ocean.height_at(fishing.target.x, fishing.target.z)) < 0.01, "D01: the bobber floats on the waves")
	# Hooked up to 27 m out, a run can take the last of 30 m of line: more
	# line for these two fights, so they're landed (the fight's own test
	# covers running out of line).
	fishing.max_line = 40.0
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	_mouse_left(true)
	await _settle()
	fought = await _land(fishing)
	sprayed = sprayed or fought["spray"]
	var drop: Dictionary = fishing.catches.entry("drop_off_fish")
	_check(caught.size() == 2 and caught[1][2] and drop["count"] == 1 and drop["first"]["biome"] == "" and hud.card_text() == "Caught: Drop-off fish! %d cm · New" % caught[1][1], "D01: the card: \"%s\"" % hud.card_text())
	await _cast(1.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	_mouse_left(true)
	await _settle()
	fought = await _land(fishing)
	sprayed = sprayed or fought["spray"]
	_check(sprayed, "D01: a run throws up spray where the fish swims")
	fishing.max_line = 30.0
	drop = fishing.catches.entry("drop_off_fish")
	_check(drop["count"] == 2 and drop["biggest_cm"] == maxi(caught[1][1], caught[2][1]) and not caught[2][2] and not hud.card_text().ends_with("New"), "D01: a second catch counts, keeps the biggest, not New")

	# Lost in a fight: held into a hard pull straight away, the line snaps; let go while it
	# swims at you, the hook slips; leaving lets it go.
	await _cast(1.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	_mouse_left(true)
	await _settle()
	# Held on its way (no turns: a shore in its path would turn it).
	fishing.fight.pull = 3.0
	fishing.fight.heading = 0.0
	fishing.fight._turn_in = INF
	fishing.fight._run_in = INF
	fishing.fight.swimmable = func(_at: Vector2) -> bool: return true
	var shook := {"seen": false}
	await _until(func() -> bool:
		shook["seen"] = shook["seen"] or (fishing.fighting() and absf(camera.h_offset) + absf(camera.v_offset) > 0.0)
		return fishing.state != Fishing.State.FIGHT, 5.0)
	_mouse_left(false)
	_check(fishing.state == Fishing.State.IDLE and hud.said() == "The line snapped" and not player.look_held and camera.h_offset == 0.0 and camera.v_offset == 0.0 and shook["seen"] and caught.size() == 3, "D01: reeled into a hard pull straight away, the view shakes, then the line snaps and the bobber's gone (%s, \"%s\")" % [Fishing.State.keys()[fishing.state], hud.said()])
	await _cast(1.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	_mouse_left(true)
	await _settle()
	_mouse_left(false)
	await _settle()
	fishing.fight.heading = PI
	fishing.fight._turn_in = INF
	fishing.fight._run_in = INF
	fishing.fight.swimmable = func(_at: Vector2) -> bool: return true
	await _until(func() -> bool: return fishing.state != Fishing.State.FIGHT, 5.0)
	# Free, the bobber floats and may already rest again.
	_check(fishing.state in [Fishing.State.OUT, Fishing.State.WAITING] and fishing._bobber.visible and hud.said() == "It slipped off the hook" and not player.look_held and caught.size() == 3, "D01: let go while it swims at you, the line goes slack and the hook slips, the bobber left out (%s)" % Fishing.State.keys()[fishing.state])
	fishing.reel_in()
	await _cast(1.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	_mouse_left(true)
	await _settle()
	_key(KEY_1)
	await _settle()
	_mouse_left(false)
	_check(fishing.state == Fishing.State.IDLE and not player.look_held and caught.size() == 3, "D01: switching tool mid-fight lets the fish go and gives the view back")
	_key(KEY_2)
	await _settle()

	# A click on a nibble scares it off; a missed bite leaves the bobber out.
	await _cast(1.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.NIBBLE, 5.0)
	_mouse_left(true)
	await _settle()
	_check(fishing.state == Fishing.State.OUT and fishing.reeling and hud.said() == "Too soon: it swam off" and caught.size() == 3, "D01: a click on a nibble scares it off, and reels")
	# Reeling drags it level through the water, never lifting it out.
	var level := func() -> float: return Vector2(fishing._bobber.global_position.x - player.global_position.x, fishing._bobber.global_position.z - player.global_position.z).length()
	var from: float = level.call()
	var above := -INF
	for k in 30:
		await _frames(1)
		var b := fishing._bobber.global_position
		above = maxf(above, b.y - fishing.ocean.height_at(b.x, b.z))
	_check(above < 0.15 and level.call() < from - 1.0, "D01: reeling drags it through the water, not up (%.2f m above it at most, %.1f m to %.1f m)" % [above, from, level.call()])
	# Let go: it stops, and rests in the water again, where the wait starts.
	_mouse_left(false)
	await _settle()
	var length := fishing.line_length
	await _frames(10)
	_check(not fishing.reeling and fishing.line_length >= length - 0.01, "D01: letting go stops reeling")
	await _until(func() -> bool: return fishing.state == Fishing.State.WAITING, 5.0)
	_check(fishing.state == Fishing.State.WAITING, "D01: reeled part way, it rests in the water and the wait starts there")
	fishing.bite_window = 0.1
	await _until(func() -> bool: return fishing.state == Fishing.State.BITE, 5.0)
	fishing.wait = Vector2(60.0, 60.0)
	await _until(func() -> bool: return fishing.state == Fishing.State.WAITING, 2.0)
	_check(fishing.state == Fishing.State.WAITING and hud.said() == "It got away" and caught.size() == 3, "D01: a missed bite: it gets away, the bobber stays out")
	_mouse_left(true)
	var lifted := {"seen": false} # snagged on the platform's side, then lifted out
	await _until(func() -> bool:
		lifted["seen"] = lifted["seen"] or fishing._lifting
		return fishing.state == Fishing.State.IDLE, 10.0)
	_mouse_left(false)
	_check(fishing.state == Fishing.State.IDLE and not fishing._bobber.visible and caught.size() == 3 and lifted["seen"] and not fishing._lifting, "D01: holding the click while waiting reels it all the way in, lifted out at the platform's side (%s, lifted %s)" % [Fishing.State.keys()[fishing.state], lifted["seen"]])
	await _settle()

	# Walking: the line pays out, up to its longest; past it the bobber
	# is dragged and the fish on the line takes fright.
	fishing.wait = Vector2(0.2, 0.3)
	fishing.nibble_gap = Vector2(30.0, 30.0)
	await _cast(0.5)
	var along_deck := out.cross(Vector3.UP)
	player.global_position += along_deck * 3.0
	await _frames(10)
	_check(fishing.state in [Fishing.State.WAITING, Fishing.State.APPROACH, Fishing.State.NIBBLE], "D01: a few steps don't reel in: the line pays out (%s)" % Fishing.State.keys()[fishing.state])
	await _until(func() -> bool: return fishing.state == Fishing.State.NIBBLE, 5.0)
	fishing.max_line = fishing._tip.global_position.distance_to(fishing._bobber.global_position) + 1.0
	player.global_position -= out * 4.0
	await _frames(10)
	_check(fishing.state == Fishing.State.OUT and not is_instance_valid(fishing._fish) and caught.size() == 3, "D01: past the line's longest it drags the bobber, and the fish swims off")
	fishing.max_line = 30.0
	fishing.nibble_gap = Vector2(0.3, 0.3)
	player.global_position = Vector3(0, player.global_position.y, 0) + out * 4.0
	await _settle()

	# Leaving reels in: another tool, the controls gone (the chat, a menu).
	await _cast(0.5)
	_key(KEY_1)
	await _settle()
	_check(fishing.state == Fishing.State.IDLE and not fishing._bobber.visible and not fishing._rod.visible, "D01: switching tool reels in")
	_key(KEY_2)
	await _cast(0.5)
	player.controls_enabled = false
	await _settle()
	_check(fishing.state == Fishing.State.IDLE, "D01: losing the controls (a chat, a menu) reels in")
	player.controls_enabled = true

	# A full charge aimed 30° up would fly past the line's longest: it's
	# held there and drops into the water, not dragged.
	fishing.wait = Vector2(60.0, 60.0)
	var eye := camera.global_position
	_face(player, eye + out * 10.0 + Vector3.UP * 10.0 * tan(deg_to_rad(30.0)))
	await _cast(1.0)
	await _until(fishing._floating, 5.0)
	var reach := fishing._tip.global_position.distance_to(fishing._bobber.global_position)
	await _frames(30)
	_check(fishing._floating() and reach <= fishing.max_line and reach > fishing.max_line - 3.0, "D01: a long throw stops at the line's longest and rests there (%.1f m, %s)" % [reach, Fishing.State.keys()[fishing.state]])
	fishing.reel_in()
	# Off a bridge's side, mid-span: over its rails (not ground) into the sea.
	var span: Bridge = islands.bridges.all_bridges()[0]
	for b in islands.bridges.all_bridges():
		if b.length() > span.length():
			span = b
	var middle := (span.from + span.to) / 2.0
	player.global_position = Vector3(middle.x, span.deck_y(span.length() / 2.0) + 0.1, middle.z)
	player.velocity = Vector3.ZERO
	await _frames(10)
	var side := (span.to - span.from).cross(Vector3.UP) * Vector3(1, 0, 1)
	_face(player, player.global_position + side.normalized() * 6.0)
	await _cast(0.0)
	await _until(fishing._floating, 4.0)
	var off := span.to_local(fishing._bobber.global_position)
	_check(fishing._floating() and absf(off.x) > Bridge.WIDTH / 2.0, "D01: a cast off a bridge's side clears its rails and lands in the water (%s, %.1f m across)" % [Fishing.State.keys()[fishing.state], off.x])
	fishing.reel_in()
	fishing.wait = Vector2(0.2, 0.3)

	# Not while swimming.
	player.global_position = out * 30.0 + Vector3(0, -3, 0)
	await _until(func() -> bool: return player.swimming, 3.0)
	_mouse_left(true)
	await _settle()
	_check(player.swimming and fishing.state == Fishing.State.IDLE, "D01: no casting while swimming")
	_mouse_left(false)

	fishing.catches.flush()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(CatchLog.file))
	_check(saved is Dictionary and saved["species"]["drop_off_fish"]["count"] == 2 and saved["species"]["shallows_fish"]["count"] == 1, "D01: the catches are saved in user://")
	_key(KEY_1)
	world.go_to_platform()
	player.global_position = was
	player.velocity = Vector3.ZERO
	player.rotation.y = turned
	(player.get_node("Head") as Node3D).rotation.x = pitch
	await _frames(5)


# Holds the left button, with the rod in [member _rod_user]'s hand, for a charge of [param charge] (0 a tap, 1 full)
# and lets go, then waits for the bobber to land (or not to be cast).
func _cast(charge: float) -> void:
	var fishing := _rod_user
	_mouse_left(true)
	await _settle()
	if charge > 0.0:
		await _until(func() -> bool: return fishing.charge >= charge, 3.0)
	_mouse_left(false)
	await _until(func() -> bool: return fishing.state != Fishing.State.CHARGING and fishing.state != Fishing.State.CASTING, 5.0)


# Plays the hooked fish, the click held from the hook: pushes the mouse
# where the arrow points, lets go of the click on a run or near the
# line's limit and takes it again after, until the fight ends. Says how
# it ended, how long it took, and what the world showed: the rod bent,
# the shadow following the fish, the bobber under, the arrow (and that
# it pointed away from the fish's side), a run's spray, and the fish
# pulled out of the water once won.
func _land(fishing: Fishing, timeout := 60.0) -> Dictionary:
	var out := {"outcome": "", "time": 0.0, "bent": false, "followed": true, "under": false, "arrow": false, "arrow_right": true, "spray": false, "pulled_out": false}
	var frames := [0, 0] # all, the bobber under
	var held := true
	var start := Time.get_ticks_msec()
	var game_start := _game_ms()
	var f := fishing.fight # kept: the fishing lets go of it when the fight ends
	while fishing.fighting() and Time.get_ticks_msec() - start < timeout * 1000.0:
		var b := fishing._bobber.global_position
		if fishing.state == Fishing.State.LANDING:
			# Won: pulled up out of the water, hanging from the line.
			if b.y > fishing.ocean.height_at(b.x, b.z) + 0.3 and is_instance_valid(fishing._fish) and fishing._fish.hang > 0.5 and fishing._fish.position.y > 0.0:
				out["pulled_out"] = true
			await _frames(1)
			continue
		if held and (f.running or f.strain > 0.85):
			_mouse_left(false)
			held = false
		elif not held and not f.running and f.strain < 0.7:
			_mouse_left(true)
			held = true
		var arrow := fishing.hud.arrow()
		if arrow != 0.0:
			out["arrow"] = true
			out["arrow_right"] = out["arrow_right"] and signf(arrow) == -signf(sin(f.heading))
		_mouse_move(signf(f.hint()) * 6.0)
		out["bent"] = out["bent"] or (f.strain > 0.3 and fishing._joints[-1].rotation_degrees.x < -1.0)
		# The waves may have moved on since it was placed (a slow frame).
		frames[0] += 1
		if b.y < fishing.ocean.height_at(b.x, b.z) - 0.1:
			frames[1] += 1
		out["spray"] = out["spray"] or fishing.spraying()
		if is_instance_valid(fishing._fish) and fishing._fish.arrived():
			out["followed"] = out["followed"] and Vector2(fishing._fish.position.x - b.x, fishing._fish.position.z - b.z).length() < 0.5
		await _frames(1)
	if held:
		_mouse_left(false)
	out["outcome"] = f.outcome
	out["under"] = frames[1] >= frames[0] * 0.9
	out["time"] = (_game_ms() - game_start) / 1000.0
	await _settle()
	return out


# The mouse moved [param dx] pixels across.
func _mouse_move(dx: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, 0.0)
	event.screen_relative = Vector2(dx, 0.0)
	Input.parse_input_event(event)


# The left mouse button, down or up.
func _mouse_left(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


# A press and release of the key at [param physical] (the US layout's place).
func _key(physical: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = physical
		event.pressed = pressed
		Input.parse_input_event(event)


# One notch of the mouse wheel.
func _wheel(button: MouseButton) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)


# Turns the player and its head so the camera looks at [param at].
func _face(player: Player, at: Vector3) -> void:
	var head := player.get_node("Head") as Node3D
	var d := at - (head.get_node("Camera3D") as Node3D).global_position
	player.rotation.y = atan2(-d.x, -d.z)
	head.rotation.x = atan2(d.y, Vector2(d.x, d.z).length())


# Holds an action down until _release (Tab for the ring).
func _hold(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _release(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)


# A left click at [param at], in the window.
func _click_at(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		Input.parse_input_event(event)


func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


# Whether two colours are within [param by] in every channel.
func _close(a: Color, b: Color, by: float) -> bool:
	return absf(a.r - b.r) < by and absf(a.g - b.g) < by and absf(a.b - b.b) < by


# Per-section timing: wall time and frames since the last lap.
var _lap_ms := Time.get_ticks_msec()
var _lap_phys := 0
var _lap_proc := 0


func _lap(name: String) -> void:
	var now := Time.get_ticks_msec()
	var phys := Engine.get_physics_frames()
	var proc := Engine.get_process_frames()
	print("  time %-18s %7.2f s  %5d physics  %5d process" % [name, (now - _lap_ms) / 1000.0, phys - _lap_phys, proc - _lap_proc])
	_lap_ms = now
	_lap_phys = phys
	_lap_proc = proc


# Milliseconds of game time (what the world's timers and animations run
# on), which is not the wall clock under --fixed-fps.
func _game_ms() -> int:
	if _clock == null:
		_clock = create_timer(1e6)
	return int((1e6 - _clock.time_left) * 1000.0)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


# For checks that something did NOT happen: a whole main-loop iteration, so
# input events and deferred calls have been handled. Physics frames don't
# promise that: a slow iteration runs several physics steps in a row.
func _settle() -> void:
	for i in 2:
		await process_frame


# Every island's ground made and the island up (C14: those taken back
# rise too). The ground is made on a worker thread: real time.
func _islands_up(islands: SessionIslands, timeout_s := 10.0) -> void:
	await _until_wall(islands.all_up, timeout_s)


# Waits for [param cond], at most [param timeout_s] of game time: under
# --fixed-fps the game runs faster than the clock, and a wall-clock bound
# would let a slower fallback pass for what a check waits on.
func _until(cond: Callable, timeout_s: float) -> void:
	var deadline := _game_ms() + int(timeout_s * 1000)
	while not cond.call() and _game_ms() < deadline:
		await process_frame


# Like _until, for work outside the game's clock: the real sidecar, a
# worker thread.
func _until_wall(cond: Callable, timeout_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame


# Under --fixed-fps, keeps the game's clock to the wall clock while [param
# on]: for the fake provider's turns, which race the game's timers (the
# chat's pickup timeout) as they do when you play.
func _pace(on: bool) -> void:
	if on:
		_paced_from = [_game_ms(), Time.get_ticks_msec()]
		process_frame.connect(_keep_pace)
	else:
		process_frame.disconnect(_keep_pace)


func _keep_pace() -> void:
	var ahead := (_game_ms() - _paced_from[0]) - (Time.get_ticks_msec() - _paced_from[1])
	if ahead > 0:
		OS.delay_msec(ahead)


# The height of the highest triangle of [param faces] over (x, z), found
# the slow way, or -INF if none is.
func _mesh_height(faces: PackedVector3Array, x: float, z: float) -> float:
	var best := -INF
	for t in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 1000.0, z), Vector3.DOWN, faces[t], faces[t + 1], faces[t + 2])
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
