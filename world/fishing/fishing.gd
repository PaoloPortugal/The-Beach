class_name Fishing
extends Node3D
## Fishing (D01; the user's design, 2026-10-27, round 2 after the live
## check), with the rod in hand (C15's slot 2). Hold left click (`use`)
## to charge the cast, a small meter filling; let go and the bobber, a
## real ball on the line, is thrown where you look, harder the fuller the
## charge. It floats on the water, and rolls and rests on land, where
## nothing ever comes. Hold the click while it's out to reel it in
## slowly; let go to stop. A fish comes to a bobber resting in the
## water: its shadow swims up, nibbles once or a few times, and bites,
## the bobber plunging with a splash. A click then hooks it (a click on
## a nibble scares it off) and the fight starts ([FishFight]): hold the
## click to reel it in between its runs and let go on a run, the reel's
## drag giving line, and push the mouse, which moves the rod (the view
## turning with it), against its pull, where the arrow by the crosshair
## points; it's landed at the rod's tip. The fight is read from the
## world: the rod bends with the strain, the line goes straight and
## trembles near its limit, the shadow swims where the fish is, splashing
## on a run. Too much strain snaps the line; too long slack, the hook
## slips.
##
## What comes depends only on the world ([FishSpecies]): the water under
## the bobber, the nearest island's biome, the hour and the weather.
## Shadows wander in the clear shallows, and a cast near one brings that
## one at once. You can walk while the line is out: it pays out up to
## [member max_line], then drags the bobber, scaring off the fish on the
## line. Leaving (the chat or a menu, another tool, swimming) reels in
## at once: it costs only the fish on the line. Catches go in the
## [CatchLog]. Made by `world.gd`, at the world's origin, so its
## children's positions are the world's.

## A fish was caught; [param first] the species' first.
signal caught(id: String, size_cm: int, first: bool)

## OUT: the bobber is out but not resting in the water (flying is
## CASTING): on land, rolling, being reeled or dragged. Nothing comes.
## FIGHT: a fish on the hook. LANDING: won, it's pulled out of the
## water, then caught.
enum State { IDLE, CHARGING, CASTING, OUT, WAITING, APPROACH, NIBBLE, BITE, FIGHT, LANDING }

## Seconds to fill the meter; the throw's speed, m/s, from a tap to a
## full meter (about 4 m and 22 m over flat water at eye level), and how
## far above where you look it goes, degrees.
const CHARGE_TIME := 1.0
const MIN_THROW := 5.2
const MAX_THROW := 18.0
const LIFT := 15.0
## The bobber: its radius, metres, and mass, kg. It collides only with
## the "ground" layer (project.godot: islands, the sea floor, bridges,
## the platform), never props, agents or the player.
const BOBBER_RADIUS := 0.07
const BOBBER_MASS := 0.05
const GROUND_LAYER := 3
## The line is drawn in this many pieces; each point between its ends is
## held this far above the ground under it (metres).
const LINE_POINTS := 12
const LINE_LIFT := 0.03
## Water shallower than this under the bobber counts as land: nothing
## comes there.
const MIN_DEPTH := 0.3
## Line left slack when the bobber settles in the water, metres; how fast
## holding the click reels in, m/s; how near the rod's tip it's back.
const SLACK := 0.6
const REEL_SPEED := 4.0
const BACK := 1.5
## Reeling, a taut bobber coming less than SNAG_MOVE metres nearer (seen
## from above) in SNAG_TIME seconds is snagged: on land it hops up at HOP m/s, in the
## water the line lifts it out.
const SNAG_TIME := 0.5
const SNAG_MOVE := 0.05
const HOP := 2.5
## Further than this past the line's longest from the rod's tip (a jump
## across the world), it reels in, metres.
const LOST := 10.0
## Under this speed, m/s, a bobber in the water rests there.
const REST_SPEED := 0.6
## A shadow this near where the bobber settles comes at once, metres.
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
const BITE_DIP := 0.45
const DIP_BACK := 0.6
## The splash ring on the bite: how long it spreads, seconds, and how
## wide it gets, metres.
const SPLASH_TIME := 0.6
const SPLASH_SIZE := 0.8
## The rod (a placeholder): its length, where its grip is in the
## camera's view at GRIP_FOV degrees (moved and scaled with the field of
## view, so it stays in the same place on screen), and its tilt forward
## from upright, degrees, at rest, fully charged and reeling.
const ROD_LENGTH := 1.2
const GRIP := Vector3(0.28, -0.32, -0.45)
const GRIP_FOV := 80.0
const ROD_TILT := -55.0
const ROD_CHARGED := -15.0
const ROD_REELING := -40.0
## The rod is drawn in ROD_JOINTS pieces, bending forward at each joint
## after the first, the tip's most, by up to ROD_BEND degrees at the
## line's limit; in a fight its tip swings ROD_SWING degrees to a side at
## most.
const ROD_JOINTS := 4
const ROD_BEND := 18.0
const ROD_SWING := 30.0
## In a fight: how far the rod's tip moves for the view's turn the mouse
## would have made (radians; the tip goes from -1 to 1); how far the view
## turns with the rod's tip at either end, degrees; how far under the
## water the bobber is pulled, metres; past how far off the middle of
## the view (less the rod's turn), degrees, the view drifts after the
## fish, and how fast, degrees/s; the strain from which the line
## trembles and the view shakes, and the most it shakes, metres.
const ROD_MOUSE := 2.0
const VIEW_SWING := 25.0
## The fight won, the fish is pulled out of the water over LAND_TIME
## seconds, the bobber rising to HANG metres under the rod's tip, the
## fish hanging under it; then it's caught.
const LAND_TIME := 0.8
const HANG := 0.6
## On a run: how far the fish rises toward the surface, metres, and its
## spray, a ring every SPRAY_EVERY seconds where it swims, each spreading
## to SPRAY_SIZE metres over SPRAY_TIME seconds (SPRAYS at once at most).
const RUN_RISE := 0.35
const SPRAY_EVERY := 0.15
const SPRAY_TIME := 0.5
const SPRAY_SIZE := 1.2
const SPRAYS := 5
const FIGHT_DIP := 0.2
const DRIFT_FROM := 20.0
const DRIFT_SPEED := 40.0
const TREMBLE := 0.8
const SHAKE := 0.012
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
var bite_window := 1.5
## The longest the line pays out, metres, as you walk; past it the
## bobber is dragged. A throw goes no further than this less [constant
## SLACK]. A variable so the tests can shorten it.
var max_line := 30.0

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
## Where the bobber rests in the water, on the water's plane.
var target := Vector3.ZERO
## How much line is out, metres: the bobber is pulled back when further
## from the rod's tip.
var line_length := 0.0
## Whether the click is held to reel in.
var reeling := false
## The fight, while a fish is on the hook; else null.
var fight: FishFight

var _timer := 0.0
var _nibbles_left := 0
var _dip := 0.0
var _fish: FishShadow # the fish on the line: aimed at, coming, nibbling or biting
var _species := {}
var _size_cm := 0 # the hooked fish's
var _where := {} # the bobber's water and biome
var _release := false # cast on the next physics frame
var _snag_timer := 0.0
var _snag_reach := INF # how far across, from the tip, the snag check started
var _lifting := false # snagged in the water while reeling: the line lifts it
var _shadow_timer := 0.0
var _shadows: Array[FishShadow] = [] # wandering, the fish on the line among them
var _splash_age := INF
var _view_rod := 0.0 # the rod's tip the view was last turned with, in a fight
var _land_from := Vector3.ZERO # where the bobber was when the fight was won
var _land_age := 0.0
var _sprays: Array[MeshInstance3D] = [] # a run's rings, oldest first
var _spray_ages: Array[float] = []
var _spray_timer := 0.0
var _clock := 0.0
var _rod := Node3D.new()
var _joints: Array[Node3D] = [] # the rod's pieces, the first at the grip
var _tip := Node3D.new()
var _bobber := RigidBody3D.new()
var _splash := MeshInstance3D.new()
var _splash_material := StandardMaterial3D.new()
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


## Reels in at once: the bobber comes back and the fish on the line, if
## any, swims off.
func reel_in() -> void:
	_lose_fish(false)
	_end()


## Whether a fish is on the hook (or being pulled out).
func fighting() -> bool:
	return state == State.FIGHT or state == State.LANDING


## Whether the bobber is out (flying, on land, in the water).
func bobber_out() -> bool:
	return state != State.IDLE and state != State.CHARGING


func _unhandled_input(event: InputEvent) -> void:
	if not usable():
		return
	if event is InputEventMouseMotion and state == State.FIGHT:
		fight.push(event.screen_relative.x * player.mouse_sensitivity * ROD_MOUSE)
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
				_to_out()
				reeling = true
			State.WAITING:
				_lose_fish(false)
				_to_out()
				reeling = true
			_:
				reeling = true
		get_viewport().set_input_as_handled()
	elif event.is_action_released("use"):
		if state == State.CHARGING:
			_release = true
		reeling = false
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
	if bobber_out() and not _left():
		_move_bobber(delta)


func _process(delta: float) -> void:
	if player == null:
		return
	_place_rod(delta)
	_splash_age += delta
	_clock += delta
	if state == State.IDLE or _left():
		if state == State.LANDING:
			_catch() # already won
		elif state != State.IDLE:
			reel_in()
		_place_splash()
		_place_sprays(delta)
		return
	match state:
		State.CHARGING:
			charge = minf(charge + delta / CHARGE_TIME, 1.0)
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
					_splash_age = 0.0
					if is_instance_valid(_fish):
						_fish.lunge(HOLD)
		State.BITE:
			_dip = BITE_DIP
			_timer -= delta
			if _timer <= 0.0:
				_lose_fish(true)
				hud.say("It got away")
				_back_to_waiting()
		State.FIGHT:
			_fight_step(delta)
		State.LANDING:
			_land_step(delta)
	if state != State.BITE and state != State.FIGHT:
		_dip = move_toward(_dip, 0.0, DIP_BACK * delta)
	if _floating():
		_bobber.global_position = Vector3(target.x, ocean.height_at(target.x, target.z) - _dip, target.z)
	if bobber_out():
		_draw_line()
	_place_splash()
	_place_sprays(delta)


# Leaving the rod (D01): the chat or a menu, another tool, swimming or
# riding. Walking isn't: the line pays out.
func _left() -> bool:
	return not usable() or player.swimming or player.riding


func _on_held(_tool: String) -> void:
	if state != State.IDLE:
		reel_in()


# Resting in the water, where fish come: it floats on the waves, placed
# there each frame, not moved by the physics.
func _floating() -> bool:
	return state in [State.WAITING, State.APPROACH, State.NIBBLE, State.BITE, State.FIGHT]


# Thrown along where you look, a little above it, harder the fuller the
# charge, from the rod's tip.
func _cast() -> void:
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var forward := -camera.global_basis.z
	var throw := forward.rotated(camera.global_basis.x.normalized(), deg_to_rad(LIFT)).normalized()
	_bobber.freeze = false
	_bobber.global_position = _tip.global_position
	_bobber.global_rotation = Vector3.ZERO
	_bobber.linear_velocity = throw * lerpf(MIN_THROW, MAX_THROW, charge)
	_bobber.angular_velocity = Vector3.ZERO
	_bobber.visible = true
	_line.visible = true
	line_length = 0.0
	_dip = 0.0
	state = State.CASTING


# The bobber's physics while it's out: the line pays out as it flies or
# as you walk, holding the click reels it in, the line pulls it when
# taut, and the water holds it up. A flying bobber stops in the water or
# on land; one that comes to rest in the water is where fish come.
func _move_bobber(delta: float) -> void:
	var tip := _tip.global_position
	var at := _bobber.global_position
	var dist := tip.distance_to(at)
	if dist > max_line + LOST:
		reel_in()
		return
	if state == State.FIGHT or state == State.LANDING:
		return # the fight moves it
	if _floating():
		if dist > max_line:
			# Dragged: the fish on the line takes fright.
			_lose_fish(true)
			_to_out()
		else:
			line_length = maxf(line_length, dist)
		return
	# The line pulls level, so it drags the bobber over the water or the
	# ground; only one snagged in the water (the platform's side, a steep
	# shore) is lifted out toward the rod.
	var flat := Vector3(tip.x - at.x, 0.0, tip.z - at.z)
	if reeling:
		if state == State.CASTING:
			state = State.OUT
		# No shorter than the drop from the tip, where a level pull ends.
		line_length = maxf(minf(line_length, dist) - REEL_SPEED * delta, maxf(tip.y - at.y, 0.0))
		if flat.length() < BACK:
			_end()
			return
	else:
		_lifting = false
		if dist > line_length:
			# A throw pays out no further than the line's longest, less the
			# slack it settles with, so it's held there and drops, never
			# landing past it (dragged at once).
			line_length = minf(dist, max_line - SLACK if state == State.CASTING else max_line)
	var v := _bobber.linear_velocity
	var water := ocean.height_at(at.x, at.z)
	var under := clampf((water + BOBBER_RADIUS - at.y) / (2.0 * BOBBER_RADIUS), 0.0, 1.0)
	var to_tip := (tip - at) / maxf(dist, 0.001) if _lifting else flat / maxf(flat.length(), 0.001)
	if dist > line_length:
		var away := v.dot(to_tip)
		if away < 0.0:
			v -= to_tip * away
		v += to_tip * (dist - line_length) * 8.0
		_unsnag(flat.length(), to_tip, under > 0.0, delta)
	else:
		_snag_timer = 0.0
		_snag_reach = INF
	if under > 0.0:
		v.y += under * 2.2 * 9.8 * delta
		v -= v * minf(under * 4.0 * delta, 1.0)
	_bobber.linear_velocity = v
	var deep := under > 0.0 and depth_at(at) >= MIN_DEPTH
	if state == State.CASTING:
		if deep:
			_settle_in_water()
		elif _bobber.get_contact_count() > 0:
			state = State.OUT
	elif deep and not reeling and dist <= max_line and v.length() < REST_SPEED:
		_settle_in_water()


# Reeling a taut bobber that has stopped (an edge, a step): on land it
# hops up and over; in the water the line lifts it out from then on.
func _unsnag(reach: float, to_tip: Vector3, wet: bool, delta: float) -> void:
	if not reeling or _lifting:
		_snag_timer = 0.0
		_snag_reach = INF
		return
	if reach < _snag_reach - SNAG_MOVE:
		_snag_reach = reach
		_snag_timer = 0.0
		return
	_snag_timer += delta
	if _snag_timer >= SNAG_TIME:
		_snag_timer = 0.0
		_snag_reach = reach
		if wet:
			_lifting = true
		else:
			_bobber.linear_velocity = to_tip + Vector3.UP * HOP


# The bobber rests in the water: a shadow near it comes soon, else wait.
func _settle_in_water() -> void:
	var tip := _tip.global_position
	var at := _bobber.global_position
	# Held at the throw's longest, the line's pull lets it stretch a
	# little past: back to it.
	if tip.distance_to(at) > max_line - SLACK:
		at = tip + (at - tip).normalized() * (max_line - SLACK)
	target = Vector3(at.x, Player.WATER_Y, at.z)
	_where = {"water": FishSpecies.water_at(depth_at(at)), "biome": biome_at(at)}
	_bobber.freeze = true
	_bobber.global_rotation = Vector3.ZERO
	line_length = minf(tip.distance_to(at) + SLACK, max_line)
	_dip = 0.0
	state = State.WAITING
	_fish = null
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


# Out of the water's rest, back to the physics: reeled or dragged.
func _to_out() -> void:
	state = State.OUT
	_bobber.freeze = false
	_bobber.linear_velocity = Vector3.ZERO
	_snag_reach = INF
	_snag_timer = 0.0


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


# Hooked: the fight starts, the click held reeling it in, the view held
# so the mouse moves the rod, and you kept where you stand.
func _hook() -> void:
	_size_cm = FishSpecies.size_for(_species, rng.randf())
	var tip := _tip.global_position
	var flat := Vector2(target.x - tip.x, target.z - tip.z).length()
	fight = FishFight.new(_species, _size_cm, Vector2(target.x, target.z), minf(flat + SLACK, max_line), rng)
	fight.max_line = max_line
	fight.back = BACK
	fight.swimmable = func(at: Vector2) -> bool: return depth_at(Vector3(at.x, 0.0, at.y)) >= MIN_DEPTH
	state = State.FIGHT
	reeling = true
	player.look_held = true
	player.move_held = true
	_view_rod = 0.0


# The fight's next frame, shown in the world: the fish (its shadow and
# the bobber pulled under) where it swims, a splash as it starts a run,
# the line's length, the view turning with the rod, drifting after the
# fish and shaking near the line's limit. Then landed, snapped or
# slipped.
func _fight_step(delta: float) -> void:
	var tip := _tip.global_position
	fight.step(delta, Vector2(tip.x, tip.z), reeling)
	target = Vector3(fight.fish.x, Player.WATER_Y, fight.fish.y)
	_dip = FIGHT_DIP
	line_length = tip.distance_to(_bobber.global_position) + fight.slack(Vector2(tip.x, tip.z))
	if is_instance_valid(_fish):
		_fish.swim_to(target, FishFight.SPEED * 4.0)
		_fish.raised = RUN_RISE if fight.running else 0.0
	if fight.ran:
		fight.ran = false
		_splash_age = 0.0
	# A run throws up spray where the fish swims.
	if fight.running:
		_spray_timer -= delta
		if _spray_timer <= 0.0:
			_spray_timer = SPRAY_EVERY
			_spray(target)
	else:
		_spray_timer = 0.0
	# The view turns with the rod's tip, so the fish dragging it pulls
	# the view its way and pushing back brings it back; past that, it
	# drifts after the fish.
	var swing := deg_to_rad(VIEW_SWING)
	player.rotate_y(-(fight.rod - _view_rod) * swing)
	_view_rod = fight.rod
	var look := -player.global_basis.z * Vector3(1, 0, 1)
	var off := look.signed_angle_to((target - player.global_position) * Vector3(1, 0, 1), Vector3.UP) - fight.rod * swing
	var from := deg_to_rad(DRIFT_FROM)
	if absf(off) > from:
		player.rotate_y(signf(off) * minf(absf(off) - from, deg_to_rad(DRIFT_SPEED) * delta))
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var shake := SHAKE * clampf((fight.strain - TREMBLE) / (1.0 - TREMBLE), 0.0, 1.0)
	camera.h_offset = rng.randf_range(-shake, shake)
	camera.v_offset = rng.randf_range(-shake, shake)
	match fight.outcome:
		"landed":
			state = State.LANDING
			_land_from = _bobber.global_position
			_land_age = 0.0
		"snapped":
			hud.say("The line snapped")
			_lose_fish(true)
			_end()
		"slipped":
			hud.say("It slipped off the hook")
			_lose_fish(true)
			_to_out()


# Won: the fish pulled up out of the water to hang from the rod's tip,
# then caught.
func _land_step(delta: float) -> void:
	_land_age += delta
	var t := clampf(_land_age / LAND_TIME, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var tip := _tip.global_position
	var at := _land_from.lerp(tip + Vector3.DOWN * HANG, eased)
	_bobber.global_position = at
	line_length = tip.distance_to(at)
	target = Vector3(at.x, Player.WATER_Y, at.z)
	if is_instance_valid(_fish):
		_fish.swim_to(target, 20.0)
		_fish.raised = at.y - 0.1 + FishShadow.DEPTH - Player.WATER_Y
		_fish.hang = eased
	var camera := player.get_node("Head/Camera3D") as Camera3D
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	if t >= 1.0:
		_catch()


func _catch() -> void:
	var biome: int = _where["biome"]
	var first := catches.record(_species["id"], _size_cm, Biome.NAMES[biome] if biome >= 0 else "", _where["water"])
	hud.show_catch(_species["name"], _size_cm, first)
	caught.emit(_species["id"], _size_cm, first)
	if is_instance_valid(_fish):
		_fish.queue_free()
	_fish = null
	_end()


# The fight over: the view is yours again.
func _stop_fight() -> void:
	if fight == null:
		return
	fight = null
	player.look_held = false
	player.move_held = false
	var camera := player.get_node("Head/Camera3D") as Camera3D
	camera.h_offset = 0.0
	camera.v_offset = 0.0


# The fish on the line, if any, swims off: darting away when [param
# scared], else wandering back off.
func _lose_fish(scared: bool) -> void:
	_stop_fight()
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
	_stop_fight()
	state = State.IDLE
	charge = 0.0
	_release = false
	reeling = false
	_lifting = false
	line_length = 0.0
	_bobber.freeze = true
	_bobber.visible = false
	_line.visible = false


# The rod in your hand, bottom right whatever the field of view, tilting
# back as you charge and up as you reel.
func _place_rod(delta: float) -> void:
	_rod.visible = hotbar.held_tool() == "rod"
	var camera := _rod.get_parent() as Camera3D
	var s := tan(deg_to_rad(camera.fov) / 2.0) / tan(deg_to_rad(GRIP_FOV) / 2.0)
	_rod.position = Vector3(GRIP.x * s, GRIP.y * s, GRIP.z)
	_rod.scale = Vector3.ONE * s
	var tilt := ROD_TILT
	if state == State.CHARGING:
		tilt = lerpf(ROD_TILT, ROD_CHARGED, charge)
	elif state == State.BITE:
		tilt = ROD_TILT + 10.0
	elif reeling:
		tilt = ROD_REELING
	_rod.rotation_degrees.x = move_toward(_rod.rotation_degrees.x, tilt, 400.0 * delta)
	# In a fight it bends with the strain, the tip most, and swings to
	# where it's pushed.
	var strain := fight.strain if fight else 0.0
	for i in range(1, _joints.size()):
		_joints[i].rotation_degrees.x = -ROD_BEND * strain * i / (_joints.size() - 1.0)
	_rod.rotation_degrees.z = move_toward(_rod.rotation_degrees.z, -fight.rod * ROD_SWING if fight else 0.0, 300.0 * delta)


# The line: from the rod's tip to the bobber, straight when taut, sagging
# with the slack, never into the ground (it lies on it instead).
func _draw_line() -> void:
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _line_material)
	for p in line_points():
		_line_mesh.surface_add_vertex(p)
	_line_mesh.surface_end()


## The line's points as drawn, from the rod's tip to the bobber.
func line_points() -> PackedVector3Array:
	var from := _tip.global_position
	var at := _bobber.global_position
	var dist := from.distance_to(at)
	var slack := line_length - dist
	var sag := 0.0
	if state != State.CASTING and slack > 0.05:
		sag = minf(dist * 0.06 + slack * 0.5, 1.5)
	var space := get_world_3d().direct_space_state
	var out := PackedVector3Array()
	for i in LINE_POINTS + 1:
		var t := float(i) / LINE_POINTS
		var straight := from.lerp(at, t)
		var p := straight + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		if fight and fight.strain > TREMBLE:
			p.y += (fight.strain - TREMBLE) / (1.0 - TREMBLE) * 0.04 * sin(_clock * 60.0 + i * 2.0) * sin(PI * t)
		if i > 0 and i < LINE_POINTS:
			p.y = maxf(p.y, _ground_y(space, straight, p) + LINE_LIFT)
		out.append(p)
	return out


# The top of the ground layer (as the bobber meets it: not props) between
# where a point of the line would be taut, [param straight], and sagging,
# [param p]; -INF if none. So a deck above the line doesn't lift it.
func _ground_y(space: PhysicsDirectSpaceState3D, straight: Vector3, p: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(straight + Vector3.UP * 0.1, p + Vector3.DOWN * LINE_LIFT, 1 << (GROUND_LAYER - 1))
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else -INF


# The bite's splash: a ring spreading on the water round the bobber,
# fading out.
func _place_splash() -> void:
	var t := _splash_age / SPLASH_TIME
	_splash.visible = t < 1.0 and bobber_out()
	if not _splash.visible:
		return
	var r := lerpf(0.1, SPLASH_SIZE, t)
	_splash.scale = Vector3(r, 0.2, r)
	_splash.global_position = Vector3(target.x, ocean.height_at(target.x, target.z) + 0.02, target.z)
	_splash_material.albedo_color.a = 0.8 * (1.0 - t)


# A run's spray: the oldest ring starts again at [param at].
func _spray(at: Vector3) -> void:
	var ring: MeshInstance3D = _sprays.pop_front()
	_spray_ages.pop_front()
	ring.set_meta("at", Vector2(at.x, at.z))
	_sprays.append(ring)
	_spray_ages.append(0.0)


# The run's rings spreading on the water, fading out.
func _place_sprays(delta: float) -> void:
	for i in _sprays.size():
		_spray_ages[i] += delta
		var ring := _sprays[i]
		var t := _spray_ages[i] / SPRAY_TIME
		ring.visible = t < 1.0 and bobber_out()
		if not ring.visible:
			continue
		var at: Vector2 = ring.get_meta("at")
		var r := lerpf(0.15, SPRAY_SIZE, t)
		ring.scale = Vector3(r, 0.3, r)
		ring.global_position = Vector3(at.x, ocean.height_at(at.x, at.y) + 0.02, at.y)
		((ring.mesh as TorusMesh).material as StandardMaterial3D).albedo_color.a = 0.75 * (1.0 - t)


## Whether a run's spray shows now.
func spraying() -> bool:
	return _sprays.any(func(r: MeshInstance3D) -> bool: return r.visible)


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


# A placeholder rod held in the view, bottom right: a tapering stick in
# a few pieces, each a joint it bends at.
func _make_rod() -> void:
	_rod.name = "Rod"
	_rod.position = GRIP
	_rod.rotation_degrees.x = ROD_TILT
	_rod.visible = false
	var m := StandardMaterial3D.new()
	m.albedo_color = ROD_COLOUR
	m.roughness = 0.8
	var piece := ROD_LENGTH / ROD_JOINTS
	var parent: Node3D = _rod
	for i in ROD_JOINTS:
		var joint := Node3D.new()
		joint.position.y = 0.0 if i == 0 else piece
		parent.add_child(joint)
		_joints.append(joint)
		var stick := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.bottom_radius = lerpf(0.016, 0.007, float(i) / ROD_JOINTS)
		cylinder.top_radius = lerpf(0.016, 0.007, float(i + 1) / ROD_JOINTS)
		cylinder.height = piece
		cylinder.radial_segments = 6
		cylinder.rings = 1
		cylinder.material = m
		stick.mesh = cylinder
		stick.position.y = piece / 2.0
		stick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		joint.add_child(stick)
		parent = joint
	_tip.name = "Tip"
	_tip.position.y = piece
	parent.add_child(_tip)
	player.get_node("Head/Camera3D").add_child(_rod)


# A placeholder bobber, red below and white above: a small ball that
# rolls, on the ground layer only. Then the line and the splash ring.
func _make_bobber() -> void:
	_bobber.name = "Bobber"
	_bobber.visible = false
	_bobber.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_bobber.freeze = true
	_bobber.mass = BOBBER_MASS
	_bobber.collision_layer = 0
	_bobber.collision_mask = 0
	_bobber.set_collision_mask_value(GROUND_LAYER, true)
	_bobber.continuous_cd = true
	_bobber.contact_monitor = true
	_bobber.max_contacts_reported = 2
	_bobber.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_bobber.linear_damp = 0.05
	_bobber.angular_damp = 1.5
	var surface := PhysicsMaterial.new()
	surface.friction = 0.6
	surface.bounce = 0.3
	_bobber.physics_material_override = surface
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = BOBBER_RADIUS
	collision.shape = shape
	_bobber.add_child(collision)
	for part in [[Color(0.85, 0.12, 0.1), BOBBER_RADIUS, 0.0], [Color(0.95, 0.95, 0.92), 0.05, 0.04]]:
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
	_splash.name = "Splash"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.85
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 3
	_splash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_splash_material.albedo_color = Color(1, 1, 1, 0.8)
	ring.material = _splash_material
	_splash.mesh = ring
	_splash.visible = false
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)
	# A run's spray: rings like the splash, each with its own fade.
	for i in SPRAYS:
		var spray := MeshInstance3D.new()
		spray.name = "Spray%d" % i
		var torus := TorusMesh.new()
		torus.inner_radius = 0.8
		torus.outer_radius = 1.0
		torus.rings = 24
		torus.ring_segments = 3
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1, 0)
		torus.material = m
		spray.mesh = torus
		spray.visible = false
		spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spray.set_meta("at", Vector2.ZERO)
		add_child(spray)
		_sprays.append(spray)
		_spray_ages.append(INF)
