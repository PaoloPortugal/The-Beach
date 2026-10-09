class_name Underwater
extends Node
## The view under the water (W08): while the camera is below the surface,
## the fog turns blue and close, so the sea floor fades into deep water
## instead of the sky's haze. Above it, the world's own fog comes back.

const FOG_COLOUR := Color(0.06, 0.32, 0.46)
const FOG_BEGIN := 0.0
const FOG_END := 70.0

## Whether the camera is under the water now.
var active := false
## How much light reaches the water (W09's DayNight): 1 by day, less by
## night; the blue fog under water darkens with it.
var light := 1.0:
	set(value):
		light = value
		if active:
			_environment.fog_light_color = FOG_COLOUR * light

var _environment: Environment
var _above := {}


func setup(environment: Environment) -> void:
	_environment = environment
	for key in ["fog_light_color", "fog_depth_begin", "fog_depth_end", "fog_sky_affect"]:
		_above[key] = _environment.get(key)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _environment == null:
		return
	# The waves reach about ±0.35 m; the eyes float above them (Player).
	set_active(camera.global_position.y < Player.WATER_Y)


## Sets the world's own fog [param key] to [param value]: now if above
## the water, or for when the camera comes back up (W09's sky colours).
func set_above(key: String, value: Variant) -> void:
	_above[key] = value
	if not active:
		_environment.set(key, value)


func set_active(under: bool) -> void:
	if under == active:
		return
	active = under
	if under:
		_environment.fog_light_color = FOG_COLOUR * light
		_environment.fog_depth_begin = FOG_BEGIN
		_environment.fog_depth_end = FOG_END
		_environment.fog_sky_affect = 1.0
	else:
		for key in _above:
			_environment.set(key, _above[key])
