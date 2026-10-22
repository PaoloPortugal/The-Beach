class_name ReadOnlyFlag
extends Node3D
## The read-only mark (S08): a grey pennant on a pole near the edge of an
## island whose session the world only watches ([code]read_only[/code]:
## started outside the game, or taken back read-only after a restart, S07).
## It stands between two torches, on the side furthest from the island's
## bridges, and the pennant sways a little. A PLACEHOLDER built from
## primitives (the user's choice of look, 2026-10-22), until real art.

const POLE := Color(0.62, 0.62, 0.6)
const PENNANT := Color(0.8, 0.82, 0.85)
const HEIGHT := 3.0
## How far inward from the edge it stands, metres.
const INSET := 1.2
## Props are cleared this far around it.
const CLEAR := 1.2

var _pennant := MeshInstance3D.new()
var _time := 0.0


func _init() -> void:
	name = "ReadOnlyFlag"
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.04
	cylinder.bottom_radius = 0.06
	cylinder.height = HEIGHT
	cylinder.radial_segments = 5
	cylinder.rings = 1
	pole.mesh = cylinder
	pole.position.y = HEIGHT * 0.5
	pole.material_override = _material(POLE)
	add_child(pole)
	# A flat triangle off the pole's top, pointing away along +x.
	var prism := PrismMesh.new()
	prism.size = Vector3(0.6, 1.0, 0.03)
	prism.left_to_right = 0.0
	_pennant.name = "Pennant"
	_pennant.mesh = prism
	_pennant.rotation.z = -PI * 0.5
	_pennant.position = Vector3(0.5, HEIGHT - 0.35, 0.0)
	_pennant.material_override = _material(PENNANT)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.add_child(_pennant)
	add_child(hinge)


func _process(delta: float) -> void:
	_time += delta
	($Hinge as Node3D).rotation.y = sin(_time * 1.3) * 0.25


## Stands it on [param island], away from its bridges' landings.
func place(island: Island) -> void:
	var landings := island.landings()
	var best := Vector3.ZERO
	var best_gap := -1.0
	# Between the torches (which stand on the diagonals).
	for k in 4:
		var at := _spot(island, Vector2.from_angle(TAU * k / 4.0))
		var gap := INF
		for l in landings:
			gap = minf(gap, Vector2(at.x, at.z).distance_to(Vector2(l.x, l.z)))
		if gap > best_gap:
			best_gap = gap
			best = at
	position = best
	island.props.clear_near(best, best, CLEAR)


# Inward from the shore along dir, like the torches, then a little more.
static func _spot(island: Island, dir: Vector2) -> Vector3:
	var g := island.generator
	var edge := maxf(0.5, island.edge_height())
	var r := g.shore_radius(dir.x, dir.y)
	while r > 0.0 and g.surface_height(dir.x * r, dir.y * r) < edge:
		r -= 0.5
	r = maxf(0.0, r - INSET)
	return Vector3(dir.x * r, g.surface_height(dir.x * r, dir.y * r), dir.y * r)


static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 1.0
	return m
