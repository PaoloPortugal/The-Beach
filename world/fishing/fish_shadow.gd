class_name FishShadow
extends MeshInstance3D
## A fish seen from above (D01): a dark shape just under the surface, the
## placeholder until there are fish models. Shadows wander in the clear
## shallows, where you can aim a cast at one, and a fish coming to the
## bobber anywhere shows as one. [Fishing] moves it with [method swim_to];
## [method swim_off] sends it away, gone once out of sight.

## How far under the water it swims, metres.
const DEPTH := 0.45
const COLOUR := Color(0.05, 0.11, 0.13)
## How far it wanders from where it came, metres, and how fast, m/s.
const WANDER := 2.0
const WANDER_SPEED := 0.5
## Seconds to grow in or shrink out of sight.
const GROW := 0.6
## How fast it turns toward where it swims, radians/s.
const TURN := 5.0

static var _mesh: ArrayMesh

## On the line: [Fishing] moves it; it doesn't wander.
var hooked := false
## Where it came from: it wanders round here.
var home := Vector3.ZERO

var _goal := Vector3.ZERO
var _speed := WANDER_SPEED
var _rest := 0.0 # seconds still before wandering on
var _size := 0.0 # grows to 1, shrinks to 0 when leaving
var _leaving := false
var _length := 0.5


func _init(length := 0.5) -> void:
	_length = length
	mesh = _shape()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scale = Vector3.ONE * 0.001


func _ready() -> void:
	home = Vector3(position.x, -DEPTH, position.z)
	position = home
	_goal = home


## Swims to [param point] (on the water's plane) at [param speed] m/s.
func swim_to(point: Vector3, speed: float) -> void:
	_goal = Vector3(point.x, -DEPTH, point.z)
	_speed = speed


## Whether it has got where it was swimming.
func arrived() -> bool:
	return Vector2(position.x - _goal.x, position.z - _goal.z).length() < 0.05


## Darts [param far] metres away from [param from] at [param speed], then
## is gone.
func swim_off(from: Vector3, far := 5.0, speed := 4.0) -> void:
	var away := Vector2(position.x - from.x, position.z - from.z)
	if away.length() < 0.01:
		away = Vector2.from_angle(randf() * TAU)
	away = away.normalized() * far
	swim_to(position + Vector3(away.x, 0.0, away.y), speed)
	_leaving = true
	hooked = true # no more wandering


## A quick dart of [param by] metres toward where it faces and back (a
## nibble).
func lunge(by: float) -> void:
	position += -global_basis.z.normalized() * by


func leaving() -> bool:
	return _leaving


func _process(delta: float) -> void:
	if _leaving and arrived():
		_size = maxf(_size - delta / GROW, 0.0)
		if _size <= 0.0:
			queue_free()
			return
	else:
		_size = minf(_size + delta / GROW, 1.0)
	scale = Vector3.ONE * maxf(_size * _length, 0.001)
	if not hooked and arrived():
		_rest -= delta
		if _rest <= 0.0:
			var at := Vector2.from_angle(randf() * TAU) * randf() * WANDER
			swim_to(home + Vector3(at.x, 0.0, at.y), WANDER_SPEED)
			_rest = randf_range(0.5, 3.0)
	var to := Vector2(_goal.x - position.x, _goal.z - position.z)
	var step := minf(to.length(), _speed * delta)
	if to.length() > 0.001:
		var dir := to.normalized()
		position += Vector3(dir.x, 0.0, dir.y) * step
		var facing := atan2(-dir.x, -dir.y)
		rotation.y = rotate_toward(rotation.y, facing, TURN * delta)
	position.y = -DEPTH


# A fish from above, 1 m long and facing -z: a flat body and a tail.
static func _shape() -> ArrayMesh:
	if _mesh:
		return _mesh
	var v := PackedVector3Array()
	var body := 12
	for i in body:
		var a := TAU * i / body
		var b := TAU * (i + 1) / body
		v.append(Vector3(0.0, 0.0, -0.1))
		v.append(Vector3(sin(b) * 0.14, 0.0, -0.1 + cos(b) * 0.4))
		v.append(Vector3(sin(a) * 0.14, 0.0, -0.1 + cos(a) * 0.4))
	v.append_array([Vector3(0.0, 0.0, 0.25), Vector3(-0.13, 0.0, 0.5), Vector3(0.13, 0.0, 0.5)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = COLOUR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.surface_set_material(0, m)
	return _mesh
