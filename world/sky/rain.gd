class_name Rain
extends GPUParticles3D
## Rain (W09): falling streaks in a box over the camera, as many as the
## weather's rain level says, slanting with the wind. None under the
## water. The rings it makes on the water are the ocean's (W02).

const MAX_DROPS := 2400
## The box the drops start in, around and above the camera, metres.
const SPREAD := 26.0
const HEIGHT := 16.0
const SPEED := 24.0
const COLOUR := Color(0.78, 0.84, 0.92, 0.35)

var weather: Weather
## The wind's direction (Clouds owns it).
var wind_direction := Vector2.RIGHT

var _material := StandardMaterial3D.new()


func _ready() -> void:
	amount = MAX_DROPS
	amount_ratio = 0.0
	lifetime = (HEIGHT + 4.0) / SPEED
	visibility_aabb = AABB(Vector3(-SPREAD - 10.0, -HEIGHT - 10.0, -SPREAD - 10.0), Vector3(SPREAD + 10.0, HEIGHT + 10.0, SPREAD + 10.0) * 2.0)
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(SPREAD, 0.5, SPREAD)
	process.direction = Vector3.DOWN
	process.spread = 0.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = SPEED
	process.initial_velocity_max = SPEED * 1.1
	process_material = process
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.7)
	var material := _material
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = COLOUR
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	streak.material = material
	draw_pass_1 = streak
	emitting = false


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or weather == null:
		return
	var level := weather.rain
	var dry := camera.global_position.y < Player.WATER_Y
	emitting = level > 0.01 and not dry
	amount_ratio = clampf(level, 0.0, 1.0)
	# Unlit, so it dims with the night itself (DayNight).
	var light := lerpf(1.0, 0.3, DayNight.current_darkness)
	_material.albedo_color = Color(COLOUR.r * light, COLOUR.g * light, COLOUR.b * light, COLOUR.a)
	# Start upwind, so the slanting drops fall around the camera.
	var slant := wind_direction * weather.wind * 0.35
	(process_material as ParticleProcessMaterial).direction = Vector3(slant.x, -1.0, slant.y).normalized()
	global_position = camera.global_position + Vector3(-slant.x * HEIGHT, HEIGHT, -slant.y * HEIGHT)
