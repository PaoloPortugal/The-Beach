class_name AttentionBeacon
extends Node3D
## The attention cue's beacon (A05): a tall light pillar, orange by
## default, rising from an agent that waits on you, pulsing slowly, seen from other islands. It
## ignores the fog and gets wider with distance, so it stays a few pixels
## wide across the ocean. It fades in and out. A placeholder: an unshaded,
## see-through cylinder, no art. W04 uses it too, in another colour, over
## a new session's island.

const COLOUR := Color(1.0, 0.5, 0.1)
## Metres, from just above the agent's marker.
const HEIGHT := 150.0
const BASE := 0.6
## Width close up, and how much wider per metre away from the camera.
const WIDTH := 0.5
const WIDTH_PER_METRE := 0.01
## Seconds to fade fully in or out.
const FADE := 0.6

## Set before it enters the tree.
var colour := COLOUR

var _on := false
var _level := 0.0 # 0 hidden … 1 fully shown
var _time := 0.0
var _pillar: MeshInstance3D
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.disable_fog = true
	# Drawn before other see-through things, so the message bubble stays on
	# top of it.
	_material.render_priority = -1
	_material.albedo_color = Color(colour, 0.0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = WIDTH / 2.0
	mesh.bottom_radius = WIDTH / 2.0
	mesh.height = HEIGHT
	mesh.radial_segments = 12
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	mesh.material = _material
	_pillar = MeshInstance3D.new()
	_pillar.mesh = mesh
	_pillar.position.y = BASE + HEIGHT / 2.0
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pillar)
	visible = false
	set_process(false)


## Shows (fading in) or hides (fading out) the beacon.
func set_on(on: bool) -> void:
	_on = on
	if on:
		visible = true
		set_process(true)


## Whether it's on (it may still be fading out when not).
func is_on() -> bool:
	return _on


func _process(delta: float) -> void:
	_time += delta
	_level = move_toward(_level, 1.0 if _on else 0.0, delta / FADE)
	if _level == 0.0 and not _on:
		visible = false
		set_process(false)
		return
	# Mostly opaque: thinner orange over the blue sky reads as pink.
	_material.albedo_color.a = _level * (0.8 + 0.15 * sin(_time * 2.5))
	var camera := get_viewport().get_camera_3d()
	if camera:
		var to := camera.global_position - global_position
		var away := Vector2(to.x, to.z).length()
		var s := maxf(1.0, away * WIDTH_PER_METRE / WIDTH)
		_pillar.scale = Vector3(s, 1.0, s)
