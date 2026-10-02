class_name AgentStateMarker
extends Node3D
## The small marker floating over an agent (A03, minimal): working is a
## slowly spinning yellow diamond, waiting on the user a bouncing orange
## "!", error a red "×"; idle and done show nothing. Placeholders built
## from primitives. It turns to face the camera around the vertical axis.
## While waiting, a beacon rises from it too (A05).

const WORKING := Color(1.0, 0.82, 0.2)
const WAITING := Color(1.0, 0.5, 0.1)
const ERROR := Color(0.9, 0.15, 0.12)

var _shapes := {} # "working" / "waiting" / "error" → Node3D
var _kind := ""
var _time := 0.0
var _beacon := AttentionBeacon.new()


func _ready() -> void:
	var diamond := _part(WORKING, Vector3(0.18, 0.18, 0.18), Vector3.ZERO)
	diamond.rotation = Vector3(deg_to_rad(45.0), 0.0, deg_to_rad(35.26))
	_shapes["working"] = _group([diamond])
	_shapes["waiting"] = _group([
		_part(WAITING, Vector3(0.08, 0.24, 0.08), Vector3(0.0, 0.06, 0.0)),
		_part(WAITING, Vector3(0.08, 0.08, 0.08), Vector3(0.0, -0.14, 0.0)),
	])
	var a := _part(ERROR, Vector3(0.32, 0.08, 0.08), Vector3.ZERO)
	a.rotation.z = deg_to_rad(45.0)
	var b := _part(ERROR, Vector3(0.32, 0.08, 0.08), Vector3.ZERO)
	b.rotation.z = deg_to_rad(-45.0)
	_shapes["error"] = _group([a, b])
	_beacon.name = "Beacon"
	add_child(_beacon)
	show_state("idle")


## Shows the marker for a protocol state (working, waiting, idle, done,
## error).
func show_state(state: String) -> void:
	_kind = state if _shapes.has(state) else ""
	for k in _shapes:
		_shapes[k].visible = k == _kind
	set_process(_kind != "")
	_beacon.set_on(_kind == "waiting")


## What the marker shows: "working", "waiting", "error", or "" for nothing.
func shown() -> String:
	return _kind


## Whether its attention beacon is on (A05).
func beacon_on() -> bool:
	return _beacon.is_on()


func _process(delta: float) -> void:
	_time += delta
	var camera := get_viewport().get_camera_3d()
	if camera:
		var to := camera.global_position - global_position
		global_rotation = Vector3(0.0, atan2(to.x, to.z), 0.0)
	var shape: Node3D = _shapes[_kind]
	match _kind:
		"working":
			shape.rotation.y = _time * 1.5
		"waiting":
			shape.position.y = absf(sin(_time * 5.0)) * 0.12


func _group(parts: Array) -> Node3D:
	var g := Node3D.new()
	for p in parts:
		g.add_child(p)
	add_child(g)
	return g


func _part(colour: Color, size: Vector3, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = at
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m
