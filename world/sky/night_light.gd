class_name NightLight
extends Node3D
## A warm light that comes on at night (W09), so islands read from afar
## and their middles are bright to chat by: torches along an island's
## beach and a lamp on the orchestrator's desk. Placeholders until there's
## art. DayNight sets their darkness (the group call); by day they're out.

const GROUP := "night_lights"
const WARM := Color(1.0, 0.72, 0.42)
const FLAME := Color(1.0, 0.62, 0.25)
## Lights fade out past this distance from the camera (the flames still
## show), so far islands cost nothing.
const FADE_FROM := 60.0
const FADE_OVER := 30.0

## The light's energy at full night and its reach.
var energy := 1.6
var reach := 9.0

var _light := OmniLight3D.new()
var _flame: MeshInstance3D
var _flame_material := StandardMaterial3D.new()


## A torch: a pole with a flame on top, 1.8 m tall.
static func torch() -> NightLight:
	var n := NightLight.new()
	n.name = "Torch"
	var pole := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.05
	cylinder.bottom_radius = 0.07
	cylinder.height = 1.6
	cylinder.radial_segments = 5
	cylinder.rings = 1
	pole.mesh = cylinder
	pole.position.y = 0.8
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.29, 0.18)
	pole.material_override = wood
	n.add_child(pole)
	n._add_flame(Vector3(0.0, 1.72, 0.0), 0.16)
	return n


## A desk lamp: a short stand with a glowing shade.
static func lamp() -> NightLight:
	var n := NightLight.new()
	n.name = "Lamp"
	n.energy = 1.2
	n.reach = 5.0
	var stand := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.3, 0.04)
	stand.mesh = box
	stand.position.y = 0.15
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.25, 0.25, 0.27)
	stand.material_override = metal
	n.add_child(stand)
	n._add_flame(Vector3(0.0, 0.34, 0.0), 0.09)
	return n


func _add_flame(at: Vector3, size: float) -> void:
	_flame = MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = size
	shape.height = size * 2.4
	shape.radial_segments = 5
	shape.rings = 2
	_flame.mesh = shape
	_flame.position = at
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.albedo_color = FLAME
	_flame.material_override = _flame_material
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)
	_light.position = at + Vector3(0.0, 0.1, 0.0)


func _ready() -> void:
	add_to_group(GROUP)
	_light.light_color = WARM
	_light.omni_range = reach
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = FADE_FROM
	_light.distance_fade_length = FADE_OVER
	add_child(_light)
	set_darkness(DayNight.current_darkness)


## 0 by day (out), 1 at night (fully lit).
func set_darkness(darkness: float) -> void:
	var on := smoothstep(0.3, 0.8, darkness)
	_light.light_energy = energy * on
	_light.visible = on > 0.0
	if _flame:
		_flame.visible = on > 0.0
		_flame.scale = Vector3.ONE * lerpf(0.4, 1.0, on)


## Whether it's lit now.
func is_lit() -> bool:
	return _light.visible
