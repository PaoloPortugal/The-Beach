class_name Fishing
extends Node3D
## Fishing (D01; the user's design, 2026-10-27), with the rod in hand
## (C15's slot 2). Hold left click (`use`) to charge the cast, a small
## meter filling; let go and the bobber flies where you look, as far as
## the charge says. Then a fish comes, its shadow swimming up to the
## bobber, nibbles once or a few times, and bites: the bobber goes under
## for a moment. A click then catches it; a click on a nibble scares it
## off; a click while nothing is there reels in. No catch bar for now.
##
## What comes depends only on the world ([FishSpecies]): the water under
## the bobber, the nearest island's biome, the hour and the weather.
## Shadows wander in the clear shallows, and a cast near one brings that
## one at once. Leaving (walking off, the chat or a menu, another tool,
## swimming) reels in: it costs only the fish on the line. Catches go in
## the [CatchLog]. Made by `world.gd`, at the world's origin, so its
## children's positions are the world's.

## A fish was caught; [param first] the species' first.
signal caught(id: String, size_cm: int, first: bool)

enum State { IDLE, CHARGING, CASTING, WAITING, APPROACH, NIBBLE, BITE }

## Seconds to fill the meter; the cast's reach, metres from the player,
## from a tap to a full meter.
const CHARGE_TIME := 1.0
const MIN_CAST := 4.0
const MAX_CAST := 22.0
## The bobber's flight, seconds, and how high its arc rises, metres.
const FLIGHT_TIME := 0.6
const ARC := 2.5
## Water shallower than this where the bobber would land counts as land.
const MIN_DEPTH := 0.3
## Walking further than this from where you cast reels in, metres.
const LEAVE_DISTANCE := 2.5
## A shadow this near where the bobber lands comes at once, metres.
const AIM_RADIUS := 4.0
## Shadows in the shallows round the player: at most SHADOWS, between
## SHADOW_NEAR and SHADOW_RANGE metres away, in water SHADOW_DEPTH deep
## (min, max), one tried every SHADOW_EVERY seconds; gone past
## SHADOW_DROP.
const SHADOWS := 5
const SHADOW_NEAR := 6.0
const SHADOW_RANGE := 30.0
const SHADOW_DROP := 40.0
const SHADOW_DEPTH := Vector2(1.5, FishSpecies.DROP_OFF_FROM)
const SHADOW_EVERY := 0.5
## Where a fish not yet seen starts toward the bobber, metres from it,
## and how close it stops.
const APPROACH_FROM := 3.5
const HOLD := 0.35
## How far a nibble's dart goes, metres.
const LUNGE := 0.15
## How far under the water the bobber dips on a nibble and on the bite,
## metres, and how fast a nibble's dip comes back up, m/s.
const NIBBLE_DIP := 0.08
const BITE_DIP := 0.3
const DIP_BACK := 0.6
## The rod (a placeholder): its length, where its grip is in the
## camera's view, and its tilt forward from upright, degrees, at rest
## and fully charged.
const ROD_LENGTH := 1.2
const GRIP := Vector3(0.28, -0.32, -0.45)
const ROD_TILT := -55.0
const ROD_CHARGED := -15.0
const ROD_COLOUR := Color(0.45, 0.30, 0.18)
const LINE_COLOUR := Color(0.92, 0.92, 0.88)

## Timings, seconds; the tests shorten them. The wait before a fish
## comes (min, max), and when a shadow was aimed at; its swim to the
## bobber; how many nibbles (min, max) and the gaps between them (min,
## max); the bite's window.
var wait := Vector2(4.0, 12.0)
var aimed_wait := Vector2(0.5, 1.5)
var approach_time := 2.0
var nibbles := Vector2i(1, 3)
var nibble_gap := Vector2(0.7, 1.5)
var bite_window := 0.9

var player: Player
var hotbar: Hotbar
var islands: SessionIslands
var day_night: DayNight
var weather: Weather
var ocean: Ocean
var catches := CatchLog.new()
var hud := FishingHud.new()
var rng := RandomNumberGenerator.new()

var state := State.IDLE
## How full the meter is, 0 to 1, while charging.
var charge := 0.0
## Where the bobber flies to or floats, on the water's plane.
var target := Vector3.ZERO

var _cast_from := Vector3.ZERO # where the player stood
var _flight := 0.0
var _flight_from := Vector3.ZERO
var _timer := 0.0
var _nibbles_left := 0
var _dip := 0.0
var _fish: FishShadow # the fish on the line: aimed at, coming, nibbling or biting
var _species := {}
var _where := {} # the bobber's water and biome
var _release := false # cast on the next physics frame (the ray needs it)
var _shadow_timer := 0.0
var _shadows: Array[FishShadow] = [] # wandering, the fish on the line among them
var _rod := Node3D.new()
var _tip := Node3D.new()
var _bobber := Node3D.new()
var _line := MeshInstance3D.new()
var _line_mesh := ImmediateMesh.new()
var _line_material := StandardMaterial3D.new()


func setup(p_player: Player, p_hotbar: Hotbar, p_islands: SessionIslands, p_day_night: DayNight, p_weather: Weather, p_ocean: Ocean) -> void:
	player = p_player
	hotbar = p_hotbar
	islands = p_islands
	day_night = p_day_night
	weather = p_weather
	ocean = p_ocean
	rng.randomize()
	catches.load_file()
	hotbar.held_changed.connect(_on_held)
	_make_rod()
	_make_bobber()
	hud.name = "FishingHud"
	hud.fishing = self
	add_child(hud)


func _exit_tree() -> void:
	catches.flush()


## Whether the rod is in hand and you have the controls.
func usable() -> bool:
	return player != null and player.controls_enabled and hotbar.held_tool() == "rod"


## How deep the water is at [param point]'s x and z, metres: negative
## over land (an island, a deck, the platform).
func depth_at(point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 60.0, point.z), Vector3(point.x, -60.0, point.z))
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -Seabed.height_at(point.x, point.z)
	return Player.WATER_Y - (hit["position"] as Vector3).y


## The kind of island nearest [param point] ([enum Biome.Kind]), or -1
## away from islands.
func biome_at(point: Vector3) -> int:
	var i := islands.island(islands.session_at(point))
	return i.generator.biome if i else -1


## Reels in: the bobber comes back and the fish on the line, if any,
## swims off.
func reel_in() -> void:
	_lose_fish(false)
	_end()


func _unhandled_input(event: InputEvent) -> void:
	if not usable():
		return
	if event.is_action_pressed("use"):
		match state:
			State.IDLE:
				if not player.swimming and not player.riding:
					state = State.CHARGING
					charge = 0.0
			State.CHARGING:
				pass
			State.BITE:
				_hook()
			State.APPROACH, State.NIBBLE:
				_lose_fish(true)
				hud.say("Too soon: it swam off")
				_end()
			_:
				reel_in()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("use") and state == State.CHARGING:
		_release = true
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if _release:
		_release = false
		if state == State.CHARGING:
			_cast()
	_shadow_timer -= delta
	if _shadow_timer <= 0.0:
		_shadow_timer = SHADOW_EVERY
		_tend_shadows()


func _process(delta: float) -> void:
	if player == null:
		return
	_rod.visible = hotbar.held_tool() == "rod"
	var tilt := ROD_TILT
	if state == State.CHARGING:
		tilt = lerpf(ROD_TILT, ROD_CHARGED, charge)
	elif state == State.BITE:
		tilt = ROD_TILT + 10.0
	_rod.rotation_degrees.x = move_toward(_rod.rotation_degrees.x, tilt, 400.0 * delta)
	if state == State.IDLE:
		return
	if _left():
		reel_in()
		return
	match state:
		State.CHARGING:
			charge = minf(charge + delta / CHARGE_TIME, 1.0)
		State.CASTING:
			_flight = minf(_flight + delta / FLIGHT_TIME, 1.0)
			if _flight >= 1.0:
				_land()
		State.WAITING:
			_timer -= delta
			if _timer <= 0.0:
				_fish_comes()
		State.APPROACH:
			if not is_instance_valid(_fish):
				_back_to_waiting()
			elif _fish.arrived():
				state = State.NIBBLE
				_timer = rng.randf_range(nibble_gap.x, nibble_gap.y)
		State.NIBBLE:
			_timer -= delta
			if _timer <= 0.0:
				if _nibbles_left > 0:
					_nibbles_left -= 1
					_dip = NIBBLE_DIP
					if is_instance_valid(_fish):
						_fish.lunge(LUNGE)
					_timer = rng.randf_range(nibble_gap.x, nibble_gap.y)
				else:
					state = State.BITE
					_timer = bite_window
					if is_instance_valid(_fish):
						_fish.lunge(HOLD)
		State.BITE:
			_dip = BITE_DIP
			_timer -= delta
			if _timer <= 0.0:
				_lose_fish(true)
				hud.say("It got away")
				_back_to_waiting()
	if state != State.BITE:
		_dip = move_toward(_dip, 0.0, DIP_BACK * delta)
	_place_bobber()


# Leaving the spot or the rod (D01): walking off, the chat or a menu,
# another tool, swimming or riding.
func _left() -> bool:
	if not usable() or player.swimming or player.riding:
		return true
	if state == State.CHARGING:
		return false
	var moved := Vector2(player.global_position.x - _cast_from.x, player.global_position.z - _cast_from.z)
	return moved.length() > LEAVE_DISTANCE


func _on_held(_tool: String) -> void:
	if state != State.IDLE:
		reel_in()


# Where you look, as far as the charge says: onto water only.
func _cast() -> void:
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var forward := -camera.global_basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() < 0.05: # looking straight down
		flat = -player.global_basis.z
	flat = flat.normalized()
	var at := player.global_position + flat * lerpf(MIN_CAST, MAX_CAST, charge)
	var depth := depth_at(at)
	if depth < MIN_DEPTH:
		state = State.IDLE
		hud.say("Can't cast onto land")
		return
	target = Vector3(at.x, Player.WATER_Y, at.z)
	_where = {"water": FishSpecies.water_at(depth), "biome": biome_at(at)}
	_cast_from = player.global_position
	_flight_from = _tip.global_position
	_flight = 0.0
	_dip = 0.0
	state = State.CASTING
	_bobber.visible = true
	_line.visible = true


# The bobber is on the water: a shadow near it comes soon, else wait.
func _land() -> void:
	state = State.WAITING
	var best := AIM_RADIUS
	for s in _shadows:
		if is_instance_valid(s) and not s.hooked:
			var d := Vector2(s.position.x - target.x, s.position.z - target.z).length()
			if d < best:
				best = d
				_fish = s
	if is_instance_valid(_fish):
		_fish.hooked = true
		_timer = rng.randf_range(aimed_wait.x, aimed_wait.y)
	else:
		_timer = rng.randf_range(wait.x, wait.y)


# What lives here now comes: the aimed shadow, or a new one. Nothing
# comes where nothing lives.
func _fish_comes() -> void:
	var conditions := _where.duplicate()
	conditions["hour"] = day_night.hour()
	conditions["weather"] = Weather.NAMES[weather.kind]
	_species = FishSpecies.pick(conditions, rng.randf())
	if _species.is_empty():
		_lose_fish(false)
		_timer = rng.randf_range(wait.x, wait.y)
		return
	if not is_instance_valid(_fish):
		var from := Vector2.from_angle(rng.randf() * TAU) * APPROACH_FROM
		_fish = _add_shadow(target + Vector3(from.x, 0.0, from.y))
		_fish.hooked = true
	var to := Vector2(target.x - _fish.position.x, target.z - _fish.position.z)
	var stop := target - Vector3(to.x, 0.0, to.y).normalized() * HOLD
	_fish.swim_to(stop, maxf(to.length() - HOLD, 0.1) / approach_time)
	_nibbles_left = rng.randi_range(nibbles.x, nibbles.y)
	state = State.APPROACH


func _hook() -> void:
	var size := FishSpecies.size_for(_species, rng.randf())
	var biome: int = _where["biome"]
	var first := catches.record(_species["id"], size, Biome.NAMES[biome] if biome >= 0 else "", _where["water"])
	hud.show_catch(_species["name"], size, first)
	caught.emit(_species["id"], size, first)
	if is_instance_valid(_fish):
		_fish.queue_free()
	_fish = null
	_end()


# The fish on the line, if any, swims off: darting away when [param
# scared], else wandering back off.
func _lose_fish(scared: bool) -> void:
	if is_instance_valid(_fish):
		if scared:
			_fish.swim_off(target)
		else:
			_fish.swim_off(target, 3.0, 1.0)
	_fish = null


func _back_to_waiting() -> void:
	_fish = null
	state = State.WAITING
	_timer = rng.randf_range(wait.x, wait.y)


func _end() -> void:
	state = State.IDLE
	charge = 0.0
	_release = false
	_bobber.visible = false
	_line.visible = false


func _place_bobber() -> void:
	if state == State.CHARGING:
		return
	var at := target
	if state == State.CASTING:
		at = _flight_from.lerp(target, _flight) + Vector3.UP * ARC * 4.0 * _flight * (1.0 - _flight)
	else:
		at.y = ocean.height_at(at.x, at.z) - _dip
	_bobber.global_position = at
	# The line: from the rod's tip, sagging toward the water.
	var from := _tip.global_position
	var sag := 0.0 if state == State.CASTING else minf(from.distance_to(at) * 0.08, 1.2)
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_material)
	for i in 13:
		var t := i / 12.0
		_line_mesh.surface_add_vertex(from.lerp(at, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	_line_mesh.surface_end()


# Keeps a few shadows wandering in the shallows round the player.
func _tend_shadows() -> void:
	_shadows.assign(_shadows.filter(func(s: Variant) -> bool: return is_instance_valid(s) and not s.leaving()))
	var here := player.global_position
	for s in _shadows:
		if s != _fish and Vector2(s.position.x - here.x, s.position.z - here.z).length() > SHADOW_DROP:
			s.swim_off(s.position, 0.0, 1.0)
	if _shadows.size() >= SHADOWS:
		return
	var at := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(SHADOW_NEAR, SHADOW_RANGE)
	var p := Vector3(here.x + at.x, 0.0, here.z + at.y)
	var depth := depth_at(p)
	if depth >= SHADOW_DEPTH.x and depth < SHADOW_DEPTH.y:
		_add_shadow(p)


func _add_shadow(at: Vector3) -> FishShadow:
	var s := FishShadow.new(rng.randf_range(0.35, 0.6))
	s.position = at
	add_child(s)
	_shadows.append(s)
	return s


# A placeholder rod held in the view, bottom right: a tapering stick.
func _make_rod() -> void:
	_rod.name = "Rod"
	_rod.position = GRIP
	_rod.rotation_degrees.x = ROD_TILT
	_rod.visible = false
	var stick := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.007
	cylinder.bottom_radius = 0.016
	cylinder.height = ROD_LENGTH
	cylinder.radial_segments = 6
	cylinder.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = ROD_COLOUR
	m.roughness = 0.8
	cylinder.material = m
	stick.mesh = cylinder
	stick.position.y = ROD_LENGTH / 2.0
	stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rod.add_child(stick)
	_tip.name = "Tip"
	_tip.position.y = ROD_LENGTH
	_rod.add_child(_tip)
	player.get_node("Head/Camera3D").add_child(_rod)


# A placeholder bobber, red below and white above, and the line.
func _make_bobber() -> void:
	_bobber.name = "Bobber"
	_bobber.visible = false
	for part in [[Color(0.85, 0.12, 0.1), 0.07, 0.0], [Color(0.95, 0.95, 0.92), 0.05, 0.04]]:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = part[1]
		sphere.height = part[1] * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		var m := StandardMaterial3D.new()
		m.albedo_color = part[0]
		sphere.material = m
		ball.mesh = sphere
		ball.position.y = part[2]
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bobber.add_child(ball)
	add_child(_bobber)
	_line.name = "Line"
	_line.mesh = _line_mesh
	_line.visible = false
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.albedo_color = LINE_COLOUR
	add_child(_line)
