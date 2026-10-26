class_name MenuCamera
extends Camera3D
## The main menu's backdrop (C14): circles the islands slowly, high up,
## looking down at their middle. [method descend] eases it down to the
## player's own camera (Play), [method ascend] back up from it (the pause
## menu's Main menu). The circle follows the islands as they come and go.

## Seconds for one turn round the islands.
const TURN_TIME := 240.0
## Seconds to ease down to the player, or up from them.
const EASE_TIME := 2.5
## The circle's radius: past the farthest island by this much, and never
## less than [constant MIN_RADIUS]; the fog (390 m, world.tscn) and the
## islands' draw distance keep it under [constant MAX_RADIUS].
const MARGIN := 40.0
const MIN_RADIUS := 60.0
const MAX_RADIUS := 220.0
## How high it flies, for its radius: a gentle look down.
const HEIGHT_PER_RADIUS := 0.45
const MIN_HEIGHT := 25.0
## How fast the circle's middle and radius follow a change, per second.
const FOLLOW := 0.5

## Emitted when [method descend] has reached the player's camera, now current.
signal arrived

enum Mode { IDLE, ORBIT, DESCEND, ASCEND }

## Where the islands are; none is only the platform's spot (tests).
var islands: SessionIslands
## The player's camera, which [method descend] hands back to.
var player_camera: Camera3D

var _mode := Mode.IDLE
var _angle := 0.0
var _middle := Vector3.ZERO
var _radius := MIN_RADIUS
var _t := 0.0 # 0 to 1 through an ease
var _from := Transform3D.IDENTITY # where an ease started
var _from_fov := 70.0
var _orbit_fov := 60.0


func _init() -> void:
	fov = _orbit_fov
	far = 1000.0


## Starts circling, from where the circle is: the game's start.
func start_orbit() -> void:
	_fit(1.0)
	_mode = Mode.ORBIT
	global_transform = orbit_transform()
	fov = _orbit_fov
	make_current()


## Eases from the player's camera up into the circle.
func ascend() -> void:
	_fit(1.0)
	_from = player_camera.global_transform
	_from_fov = player_camera.fov
	_t = 0.0
	_mode = Mode.ASCEND
	global_transform = _from
	fov = _from_fov
	make_current()


## Eases from where it is down to the player's camera, then makes that one
## current and emits [signal arrived].
func descend() -> void:
	_from = global_transform
	_from_fov = fov
	_t = 0.0
	_mode = Mode.DESCEND


## Stops at once and hands back to the player's camera (no ease).
func stop() -> void:
	_mode = Mode.IDLE
	player_camera.make_current()


func mode() -> Mode:
	return _mode


## Where on the circle it is now.
func orbit_transform() -> Transform3D:
	var height := maxf(MIN_HEIGHT, _radius * HEIGHT_PER_RADIUS)
	var at := _middle + Vector3(cos(_angle) * _radius, height, sin(_angle) * _radius)
	return Transform3D(Basis.IDENTITY, at).looking_at(_middle, Vector3.UP)


## The circle's middle and radius it is heading for: the islands' middle,
## the platform's included, and past the farthest one.
func target_circle() -> Array:
	var points: Array[Vector3] = [Vector3.ZERO]
	if islands:
		for i: Island in islands.all_islands():
			points.append(Vector3(i.global_position.x, 0.0, i.global_position.z))
	var middle := Vector3.ZERO
	for p in points:
		middle += p
	middle /= points.size()
	var far_point := 0.0
	for p in points:
		far_point = maxf(far_point, p.distance_to(middle))
	return [middle, clampf(far_point + MARGIN, MIN_RADIUS, MAX_RADIUS)]


func _process(delta: float) -> void:
	if _mode == Mode.IDLE:
		return
	_angle = fmod(_angle + TAU * delta / TURN_TIME, TAU)
	_fit(1.0 - exp(-FOLLOW * delta))
	match _mode:
		Mode.ORBIT:
			global_transform = orbit_transform()
		Mode.ASCEND:
			_t = minf(1.0, _t + delta / EASE_TIME)
			_blend(_from, _from_fov, orbit_transform(), _orbit_fov)
			if _t >= 1.0:
				_mode = Mode.ORBIT
		Mode.DESCEND:
			_t = minf(1.0, _t + delta / EASE_TIME)
			_blend(_from, _from_fov, player_camera.global_transform, player_camera.fov)
			if _t >= 1.0:
				_mode = Mode.IDLE
				player_camera.make_current()
				arrived.emit()


func _blend(a: Transform3D, a_fov: float, b: Transform3D, b_fov: float) -> void:
	var w := smoothstep(0.0, 1.0, _t)
	global_transform = a.interpolate_with(b, w)
	fov = lerpf(a_fov, b_fov, w)


# Moves the circle [param weight] of the way to where it should be.
func _fit(weight: float) -> void:
	var goal := target_circle()
	_middle = _middle.lerp(goal[0], weight)
	_radius = lerpf(_radius, goal[1], weight)
