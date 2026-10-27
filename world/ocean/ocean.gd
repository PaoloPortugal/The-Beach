class_name Ocean
extends MeshInstance3D
## Keeps the ocean plane under the camera so its edge never shows. It moves
## in whole grid cells, and the waves are computed in world space, so the
## water doesn't visibly shift when it moves. The weather (W09) speeds up
## the waves with the wind and puts rain rings on them. [method height_at]
## gives the water's height anywhere, for what floats (D01's bobber).

const CELL := 800.0 / 200.0  # plane size / subdivisions + 1
## The waves' speed (phase per second) and height, calm. Full wind makes
## them WINDY_SPEED times faster and WINDY_HEIGHT times higher: only a
## little higher, since the eyes float about 0.45 m above still water
## (W08's Player) and higher waves would cover them.
const WAVE_SPEED := 0.8
const WAVE_HEIGHT := 0.35
const WINDY_SPEED := 2.2
const WINDY_HEIGHT := 1.15
## As ocean.gdshader's wave_length.
const WAVE_LENGTH := 14.0

## Set by the world; without it the sea stays calm.
var weather: Weather
var _phase := 0.0
var _height := WAVE_HEIGHT
var _material: ShaderMaterial


func _ready() -> void:
	_material = (mesh as PlaneMesh).material as ShaderMaterial


func _process(delta: float) -> void:
	var wind := weather.wind if weather else 0.0
	_phase += delta * WAVE_SPEED * lerpf(1.0, WINDY_SPEED, wind)
	_material.set_shader_parameter("wave_phase", _phase)
	_height = WAVE_HEIGHT * lerpf(1.0, WINDY_HEIGHT, wind)
	_material.set_shader_parameter("wave_height", _height)
	_material.set_shader_parameter("rain", weather.rain if weather else 0.0)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := camera.global_position
	global_position = Vector3(snappedf(p.x, CELL), 0.0, snappedf(p.z, CELL))


## The water's height at (x, z) now, as ocean.gdshader moves it (its
## grid's flat faces aside: within a few cm).
func height_at(x: float, z: float) -> float:
	var k := TAU / WAVE_LENGTH
	var p := Vector2(x, z)
	var w := sin(p.dot(Vector2(0.8, 0.6)) * k + _phase) \
			+ 0.6 * sin(p.dot(Vector2(-0.5, 0.9)) * k * 1.7 + _phase * 1.3) \
			+ 0.3 * sin(p.dot(Vector2(0.2, -1.0)) * k * 2.9 + _phase * 1.9)
	return global_position.y + w / 1.9 * _height
