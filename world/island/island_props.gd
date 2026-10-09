class_name IslandProps
extends StaticBody3D
## An island's trees, rocks and the like (W10), made in code: low-poly
## placeholders until there's art (user's, 2026-10-08). One MultiMesh per
## kind of prop, so a forest is a few draw calls; trunks, rocks and cacti
## are solid, bushes and shrubs aren't. Where they stand comes from
## [method IslandGenerator.prop_spots]; [method clear_near] takes them off
## a bridge's landing or a torch's spot.

enum Prop { TREE, PINE, SNOW_PINE, BUSH, ROCK, RED_ROCK, CACTUS, DRY_SHRUB, PALM, TROPICAL_PLANT, SAND_CASTLE, STARFISH, SHELL }

const TRUNK := Color(0.42, 0.29, 0.18)
const LEAVES := Color(0.30, 0.54, 0.24)
const LEAVES_LIGHT := Color(0.38, 0.62, 0.28)
const NEEDLES := Color(0.19, 0.40, 0.25)
const SNOW := Color(0.93, 0.95, 0.98)
const STONE := Color(0.55, 0.53, 0.50)
const RED_STONE := Color(0.70, 0.47, 0.33)
const CACTUS_GREEN := Color(0.33, 0.52, 0.30)
const DRY := Color(0.62, 0.56, 0.32)
const BUSH_GREEN := Color(0.30, 0.50, 0.24)
const PALM_TRUNK := Color(0.58, 0.45, 0.30)
const FROND := Color(0.28, 0.60, 0.22)
const COCONUT := Color(0.36, 0.25, 0.14)
const TROPICAL := Color(0.22, 0.58, 0.30)
const CASTLE_SAND := Color(0.86, 0.74, 0.50)
const STARFISH_ORANGE := Color(0.93, 0.45, 0.28)
const SHELL_PINK := Color(0.97, 0.86, 0.80)

## How solid each kind is: [radius, height] of an upright cylinder at a
## scale of 1, or absent for none.
const SOLID := {
	Prop.TREE: [0.25, 3.0],
	Prop.PINE: [0.3, 3.0],
	Prop.SNOW_PINE: [0.3, 3.0],
	Prop.ROCK: [0.85, 1.0],
	Prop.RED_ROCK: [0.85, 1.0],
	Prop.CACTUS: [0.3, 2.4],
	Prop.PALM: [0.22, 4.5],
}

static var _meshes := {} # Prop → ArrayMesh, made once
static var _material: StandardMaterial3D

## The props standing: entries as from [method IslandGenerator.prop_spots].
var spots: Array[Dictionary] = []


## Builds the props at [param p_spots] (local to the island).
func setup(p_spots: Array[Dictionary]) -> void:
	spots = p_spots
	_rebuild()


## Takes away the props within [param radius] metres (across the ground)
## of the segment from [param a] to [param b] (local).
func clear_near(a: Vector3, b: Vector3, radius: float) -> void:
	var kept: Array[Dictionary] = []
	var p := Vector2(a.x, a.z)
	var q := Vector2(b.x, b.z)
	for s in spots:
		var at := Vector2(s["position"].x, s["position"].z)
		if Geometry2D.get_closest_point_to_segment(at, p, q).distance_to(at) >= radius:
			kept.append(s)
	if kept.size() != spots.size():
		spots = kept
		_rebuild()


## Whether a prop stands within [param radius] metres of [param at]
## (local, across the ground).
func is_near(at: Vector2, radius: float) -> bool:
	for s in spots:
		if Vector2(s["position"].x, s["position"].z).distance_to(at) < radius:
			return true
	return false


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var by_kind := {}
	for s in spots:
		by_kind.get_or_add(s["prop"], []).append(s)
	for kind: int in by_kind:
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh(kind)
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, _transform(list[k]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s" % Prop.keys()[kind].capitalize().replace(" ", "")
		mmi.multimesh = mm
		mmi.material_override = material()
		add_child(mmi)
		if not SOLID.has(kind):
			continue
		for s: Dictionary in list:
			var size: float = s["scale"]
			var shape := CylinderShape3D.new()
			shape.radius = SOLID[kind][0] * size
			shape.height = SOLID[kind][1] * size
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = s["position"] + Vector3(0.0, shape.height / 2.0, 0.0)
			add_child(collision)


static func _transform(s: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, s["yaw"]).scaled(Vector3.ONE * float(s["scale"]))
	return Transform3D(basis, s["position"])


## The shared material: vertex colours, like the islands.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 1.0
	return _material


## The mesh of a kind of prop, made once.
static func mesh(kind: int) -> ArrayMesh:
	if not _meshes.has(kind):
		_meshes[kind] = _make(kind)
	return _meshes[kind]


static func _make(kind: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = kind + 1
	match kind:
		Prop.TREE:
			_add(st, _cylinder(0.14, 0.2, 2.2, 6), Vector3(0, 1.1, 0), Vector3.ONE, TRUNK, rng, 0.0)
			_add(st, _sphere(1.5, 2.6, 7, 4), Vector3(0, 3.1, 0), Vector3.ONE, LEAVES, rng, 0.18)
			_add(st, _sphere(1.0, 1.7, 6, 3), Vector3(0.6, 3.8, 0.3), Vector3.ONE, LEAVES_LIGHT, rng, 0.12)
		Prop.PINE, Prop.SNOW_PINE:
			var top := SNOW if kind == Prop.SNOW_PINE else NEEDLES.lightened(0.08)
			_add(st, _cylinder(0.12, 0.18, 1.4, 5), Vector3(0, 0.7, 0), Vector3.ONE, TRUNK, rng, 0.0)
			_add(st, _cylinder(0.0, 1.5, 2.0, 7), Vector3(0, 2.0, 0), Vector3.ONE, NEEDLES, rng, 0.0)
			_add(st, _cylinder(0.0, 1.15, 1.7, 7), Vector3(0, 3.0, 0), Vector3.ONE, NEEDLES.lightened(0.04), rng, 0.0)
			_add(st, _cylinder(0.0, 0.75, 1.4, 6), Vector3(0, 3.9, 0), Vector3.ONE, top, rng, 0.0)
		Prop.BUSH:
			_add(st, _sphere(0.8, 1.1, 6, 3), Vector3(0, 0.4, 0), Vector3.ONE, BUSH_GREEN, rng, 0.12)
		Prop.ROCK, Prop.RED_ROCK:
			var stone := STONE if kind == Prop.ROCK else RED_STONE
			_add(st, _sphere(1.0, 1.4, 6, 3), Vector3(0, 0.3, 0), Vector3(1.2, 0.8, 1.0), stone, rng, 0.2)
		Prop.CACTUS:
			_add(st, _cylinder(0.22, 0.26, 2.4, 6), Vector3(0, 1.2, 0), Vector3.ONE, CACTUS_GREEN, rng, 0.0)
			_add(st, _cylinder(0.12, 0.12, 0.5, 5), Vector3(0.35, 1.1, 0), Vector3.ONE, CACTUS_GREEN, rng, 0.0, PI / 2.0)
			_add(st, _cylinder(0.14, 0.15, 0.9, 5), Vector3(0.6, 1.5, 0), Vector3.ONE, CACTUS_GREEN.lightened(0.05), rng, 0.0)
			_add(st, _cylinder(0.12, 0.12, 0.4, 5), Vector3(-0.3, 1.5, 0), Vector3.ONE, CACTUS_GREEN, rng, 0.0, PI / 2.0)
			_add(st, _cylinder(0.13, 0.14, 0.7, 5), Vector3(-0.5, 1.8, 0), Vector3.ONE, CACTUS_GREEN.lightened(0.05), rng, 0.0)
		Prop.DRY_SHRUB:
			_add(st, _sphere(0.55, 0.7, 6, 3), Vector3(0, 0.25, 0), Vector3.ONE, DRY, rng, 0.12)
		Prop.PALM:
			# A trunk of five pieces leaning more as it climbs, fronds
			# drooping from its top, coconuts under them.
			var at := Vector3.ZERO
			for k in 5:
				var lean := 0.05 + 0.07 * k
				var up := Vector3(sin(lean), cos(lean), 0.0)
				_add(st, _cylinder(0.17 - 0.015 * (k + 1), 0.17 - 0.015 * k, 1.0, 6), at + up * 0.5, Vector3.ONE, PALM_TRUNK.lightened(0.04 * (k % 2)), rng, 0.0, -lean)
				at += up * 0.95
			for k in 7:
				var yaw := TAU * k / 7.0 + 0.3
				var droop := 0.35 + 0.15 * (k % 2)
				var out := Basis(Vector3.UP, yaw) * Vector3(cos(droop), -sin(droop), 0.0)
				_add(st, _box(Vector3(1.9, 0.05, 0.42)), at + out * 0.95, Vector3.ONE, FROND.lightened(0.05 * (k % 2)), rng, 0.0, -droop, yaw)
			for k in 3:
				var where := Basis(Vector3.UP, TAU * k / 3.0) * Vector3(0.18, -0.2, 0.0)
				_add(st, _sphere(0.12, 0.24, 5, 3), at + where, Vector3.ONE, COCONUT, rng, 0.0)
		Prop.TROPICAL_PLANT:
			# Broad leaves fanning up and out from the ground.
			for k in 6:
				var yaw := TAU * k / 6.0
				var tilt := 0.7 + 0.2 * (k % 2)
				var out := Basis(Vector3.UP, yaw) * Vector3(cos(tilt), sin(tilt), 0.0)
				_add(st, _box(Vector3(1.0, 0.04, 0.32)), out * 0.5, Vector3.ONE, TROPICAL.lightened(0.06 * (k % 2)), rng, 0.0, tilt, yaw)
		Prop.SAND_CASTLE:
			# A walled square with a tower at each corner and a keep.
			_add(st, _box(Vector3(0.9, 0.3, 0.9)), Vector3(0, 0.15, 0), Vector3.ONE, CASTLE_SAND, rng, 0.0)
			for k in 4:
				var corner := Basis(Vector3.UP, TAU * k / 4.0 + PI / 4.0) * Vector3(0.64, 0.0, 0.0)
				_add(st, _cylinder(0.13, 0.15, 0.5, 6), corner + Vector3(0, 0.25, 0), Vector3.ONE, CASTLE_SAND.lightened(0.04), rng, 0.0)
				_add(st, _cylinder(0.0, 0.15, 0.2, 6), corner + Vector3(0, 0.6, 0), Vector3.ONE, CASTLE_SAND.darkened(0.04), rng, 0.0)
			_add(st, _cylinder(0.2, 0.24, 0.45, 6), Vector3(0, 0.52, 0), Vector3.ONE, CASTLE_SAND.lightened(0.02), rng, 0.0)
			_add(st, _cylinder(0.0, 0.24, 0.3, 6), Vector3(0, 0.9, 0), Vector3.ONE, CASTLE_SAND.darkened(0.04), rng, 0.0)
		Prop.STARFISH:
			for k in 5:
				var yaw := TAU * k / 5.0
				_add(st, _box(Vector3(0.22, 0.04, 0.08)), Basis(Vector3.UP, yaw) * Vector3(0.11, 0.02, 0.0), Vector3.ONE, STARFISH_ORANGE, rng, 0.0, 0.0, yaw)
		Prop.SHELL:
			_add(st, _sphere(0.1, 0.1, 6, 3), Vector3(0, 0.02, 0), Vector3(1.0, 0.8, 0.8), SHELL_PINK, rng, 0.0)
	return st.commit()


static func _cylinder(top: float, bottom: float, height: float, sides: int) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 0
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _sphere(radius: float, height: float, sides: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = rings
	return m


# Adds [param primitive]'s triangles, scaled by [param size], turned
# [param roll] about z, then [param yaw] about y, and moved to [param at], in one colour with flat
# normals. [param jitter] moves its vertices up to that much, the same for
# vertices in the same place, so it stays closed.
static func _add(st: SurfaceTool, primitive: PrimitiveMesh, at: Vector3, size: Vector3, colour: Color, rng: RandomNumberGenerator, jitter: float, roll := 0.0, yaw := 0.0) -> void:
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var xform := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll).scaled(size), at)
	var moved := {}
	var place := func(v: Vector3) -> Vector3:
		var key := v.snapped(Vector3.ONE * 0.001)
		if not moved.has(key):
			var offset := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * jitter
			moved[key] = xform * (v + offset)
		return moved[key]
	for k in range(0, indices.size(), 3):
		var a: Vector3 = place.call(verts[indices[k]])
		var b: Vector3 = place.call(verts[indices[k + 1]])
		var c: Vector3 = place.call(verts[indices[k + 2]])
		# Godot's front faces wind clockwise: (c - a) x (b - a) is the front.
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 1e-10:
			continue
		st.set_normal(normal.normalized())
		st.set_color(colour)
		for v in [a, b, c]:
			st.add_vertex(v)
