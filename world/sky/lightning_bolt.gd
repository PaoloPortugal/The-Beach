class_name LightningBolt
extends MeshInstance3D
## A thunderstorm's lightning bolt (W09): a jagged ribbon from the clouds
## to the sea, far from the camera, showing for a moment at each strike
## (Weather.lightning). The flash on the sky and the light is DayNight's.

## How far away it strikes, metres, and from how high.
const MIN_DISTANCE := 180.0
const MAX_DISTANCE := 320.0
const TOP := 110.0
const SEGMENTS := 9
const WIDTH := 2.0
## How long it shows, seconds.
const SHOW_TIME := 0.3

var _rng := RandomNumberGenerator.new()
var _age := -1.0
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_rng.randomize()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(0.86, 0.9, 1.0, 0.0)
	_material.disable_fog = true
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ImmediateMesh.new()
	visible = false


## Strikes in [param direction] (horizontal) from the camera.
func strike(direction: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var base := Vector2(eye.x, eye.z) + direction.normalized() * _rng.randf_range(MIN_DISTANCE, MAX_DISTANCE)
	var points := PackedVector3Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var jitter := Vector2.ZERO if i == 0 else Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 7.0))
		points.append(Vector3(base.x + jitter.x, lerpf(TOP, 0.0, t), base.y + jitter.y))
	var im := mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var a := points[i]
		var b := points[i + 1]
		# Flat to the camera, thinning toward the sea.
		var side := (b - a).cross(eye - a).normalized() * WIDTH * (1.0 - 0.6 * i / SEGMENTS)
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			im.surface_add_vertex(v)
	im.surface_end()
	global_transform = Transform3D.IDENTITY
	_age = 0.0
	visible = true


func _process(delta: float) -> void:
	if _age < 0.0:
		return
	_age += delta
	_material.albedo_color.a = 0.85 * clampf(1.0 - _age / SHOW_TIME, 0.0, 1.0)
	if _age >= SHOW_TIME:
		_age = -1.0
		visible = false
