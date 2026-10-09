extends MeshInstance3D
## Keeps the ocean plane under the camera so its edge never shows. It moves
## in whole grid cells, and the waves are computed in world space, so the
## water doesn't visibly shift when it moves. The weather (W09) speeds up
## the waves with the wind and puts rain rings on them.

const CELL := 800.0 / 200.0  # plane size / subdivisions + 1
## The waves' speed (phase per second) and height, calm. Full wind makes
## them WINDY_SPEED times faster and WINDY_HEIGHT times higher: only a
## little higher, since the eyes float about 0.45 m above still water
## (W08's Player) and higher waves would cover them.
const WAVE_SPEED := 0.8
const WAVE_HEIGHT := 0.35
const WINDY_SPEED := 2.2
const WINDY_HEIGHT := 1.15

## Set by the world; without it the sea stays calm.
var weather: Weather
var _phase := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = (mesh as PlaneMesh).material as ShaderMaterial


func _process(delta: float) -> void:
	var wind := weather.wind if weather else 0.0
	_phase += delta * WAVE_SPEED * lerpf(1.0, WINDY_SPEED, wind)
	_material.set_shader_parameter("wave_phase", _phase)
	_material.set_shader_parameter("wave_height", WAVE_HEIGHT * lerpf(1.0, WINDY_HEIGHT, wind))
	_material.set_shader_parameter("rain", weather.rain if weather else 0.0)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := camera.global_position
	global_position = Vector3(snappedf(p.x, CELL), 0.0, snappedf(p.z, CELL))
