class_name Zipline
extends Node3D
## The mountain's way up from its beach (W10, user's, 2026-10-09): a cable
## from a post on the beach to one on the shoulder above the cliff. E
## (interact) with the crosshair on either post ([Interactable], C11)
## rides it to the other: you hang under the
## cable and can look round, but not move, until you're off. Low-poly
## placeholder like the props. Made by [Island] where the biome has one,
## at [method IslandGenerator.zipline_ends].

## How high the cable is over the ground at each post, metres.
const POST_HEIGHT := 4.0
## How far below the cable your feet hang while riding.
const HANG := 2.2
## Riding speed along the cable, m/s, and how long it eases in and out.
const SPEED := 7.0
## How far from a post's middle (from the camera) you can get on, metres.
const REACH := 3.0
## Where you're let off at the top: this far further inward, metres.
const STEP_OFF := 1.5

const WOOD := Color(0.45, 0.32, 0.20)
const CABLE := Color(0.22, 0.22, 0.24)

## A ride has ended, the rider let off at the far post.
signal ride_ended

## The ground at the foot of each post, local to the island.
var low: Vector3
var high: Vector3

var _rider: Player
var _from: Vector3 # global, the cable at the start and the end
var _to: Vector3
var _ride_t := 0.0
## What the crosshair aims at by each post: the low one's, the high one's.
var ends: Array[Interactable] = []


func _init(p_low: Vector3, p_high: Vector3) -> void:
	low = p_low
	high = p_high
	name = "Zipline"


func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat, like the props
	for k in 2:
		var foot := low if k == 0 else high
		_part(st, foot + Vector3(0, (POST_HEIGHT + 0.3) / 2.0, 0), Vector3(0.0, 0.0, 0.0), 0.13, POST_HEIGHT + 0.3, WOOD)
	var a := cable_point(0)
	var b := cable_point(1)
	_part(st, (a + b) / 2.0, b - a, 0.045, a.distance_to(b), CABLE)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = st.commit()
	mi.material_override = IslandProps.material()
	add_child(mi)
	for k in 2:
		var end := Interactable.new("Zipline up" if k == 0 else "Zipline down", REACH, 0.6)
		end.name = "End%d" % k
		end.position = (low if k == 0 else high) + Vector3(0, 1.3, 0)
		end.used.connect(func(player: Player) -> void:
			if not player.riding:
				ride(player, k))
		add_child(end)
		ends.append(end)


## Where the cable is above post [param end] (0 low, 1 high), local.
func cable_point(end: int) -> Vector3:
	return (low if end == 0 else high) + Vector3(0, POST_HEIGHT, 0)


## Whether someone is riding it now.
func is_riding() -> bool:
	return _rider != null


## Starts [param player] riding from the post [param end] to the other.
func ride(player: Player, end: int) -> void:
	if _rider:
		return
	_rider = player
	_from = to_global(cable_point(end))
	_to = to_global(cable_point(1 - end))
	_ride_t = 0.0
	player.riding = true
	player.swimming = false
	player.velocity = Vector3.ZERO
	player.global_position = _from - Vector3(0, HANG, 0)


func _physics_process(delta: float) -> void:
	if _rider:
		_ride_t = minf(1.0, _ride_t + SPEED * delta / maxf(_from.distance_to(_to), 0.1))
		_rider.global_position = _from.lerp(_to, smoothstep(0.0, 1.0, _ride_t)) - Vector3(0, HANG, 0)
		if _ride_t >= 1.0:
			_let_off()


# At the far post: on the ground, a step inward at the top.
func _let_off() -> void:
	var at_top := _to.y > _from.y
	var foot := to_global(high if at_top else low)
	if at_top:
		var island := get_parent() as Island
		var inward := Vector3(-high.x, 0.0, -high.z).normalized() * STEP_OFF
		var spot := high + inward
		if island:
			spot.y = island.height_at(spot.x, spot.z)
		foot = to_global(spot)
	_rider.global_position = foot + Vector3(0, 0.05, 0)
	_rider.velocity = Vector3.ZERO
	_rider.riding = false
	_rider = null
	ride_ended.emit()


# Whoever rides gets let go if the island goes (its session ended).
func _exit_tree() -> void:
	if _rider:
		_rider.riding = false
		_rider = null


# An upright cylinder of [param length] at [param centre], turned to lie
# along [param along] if given.
func _part(st: SurfaceTool, centre: Vector3, along: Vector3, radius: float, length: float, colour: Color) -> void:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = length
	m.radial_segments = 6
	m.rings = 0
	var basis := Basis()
	if along.length() > 0.001:
		var y := along.normalized()
		var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
		basis = Basis(x, y, x.cross(y))
	var arrays := m.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	st.set_color(colour)
	for i in indices:
		st.add_vertex(centre + basis * verts[i])
