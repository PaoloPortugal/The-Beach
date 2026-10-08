class_name Seabed
extends Node3D
## The sea floor everywhere (W08): a low-poly height field in square
## chunks, built around the camera out to the fog and dropped behind it.
## Shallow around the spawn platform, banks and deeper water elsewhere,
## with trenches. Islands bring their own shelf and drop-off down past it
## (W01), so they can rise out of it and sink back in (W04). The water
## level is y = 0.

## Chunk size and grid spacing, metres.
const CHUNK := 64.0
const CELL := 4.0
## The floor's depth: banks at SHALLOWEST, open water down to DEEPEST
## (trenches included). Islands' drop-offs reach below DEEPEST.
const SHALLOWEST := -14.0
const DEEPEST := -30.0
## Mounds and hollows on top of the banks and deeps, up to this high or deep.
const MOUNDS := 2.0
## How hard the base noise is pushed toward the banks and the deeps, so
## the floor uses its whole range rather than sitting in the middle.
const SPREAD := 1.7
## Around the spawn platform the floor rises to PLATFORM_FLOOR, flat out to
## PLATFORM_FLAT metres and back to the open floor by PLATFORM_BLEND.
const PLATFORM_FLOOR := -6.0
const PLATFORM_FLAT := 40.0
const PLATFORM_BLEND := 90.0
## Chunks are kept out to this distance from the camera (past the fog, 390
## m) and dropped past it plus a margin, so they don't flicker at the line.
const KEEP := 420.0
const DROP_MARGIN := 64.0
## At most this many chunks are built a frame, nearest first.
const BUILDS_PER_FRAME := 6

const SAND := Color(0.70, 0.68, 0.54)
const MID := Color(0.56, 0.58, 0.50)
const DEEP := Color(0.42, 0.47, 0.46)
## Where colour() is all SAND (above), all MID, and all DEEP (below).
const SAND_TO := -10.0
const MID_AT := -19.0
const DEEP_FROM := -28.0

static var _base := _warped(_noise(7101, 0.004, 3))
static var _trench := _noise(7102, 0.003, 1)
static var _mounds := _noise(7103, 0.025, 2)

## Chunk coordinates -> MeshInstance3D.
var _chunks := {}
var _material: StandardMaterial3D


static func _noise(p_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.seed = p_seed
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


# Bends the noise's space so its banks wind and stretch rather than being
# round blobs.
static func _warped(n: FastNoiseLite) -> FastNoiseLite:
	n.domain_warp_enabled = true
	n.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	n.domain_warp_frequency = 0.003
	n.domain_warp_amplitude = 90.0
	n.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_NONE
	return n


## The floor's height at a world point. The same every run.
static func height_at(x: float, z: float) -> float:
	var t := smoothstep(0.0, 1.0, clampf(_base.get_noise_2d(x, z) * SPREAD + 0.5, 0.0, 1.0))
	var open := lerpf(SHALLOWEST - MOUNDS, DEEPEST + MOUNDS, t)
	open += _mounds.get_noise_2d(x, z) * MOUNDS * 2.0
	# Trenches along the noise's zero lines.
	var ridge := 1.0 - absf(_trench.get_noise_2d(x, z))
	open -= smoothstep(0.88, 1.0, ridge) * 8.0
	open = clampf(open, DEEPEST, SHALLOWEST)
	var near := 1.0 - smoothstep(PLATFORM_FLAT, PLATFORM_BLEND, Vector2(x, z).length())
	return lerpf(open, PLATFORM_FLOOR, near)


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 1.0


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	update_around(camera.global_position, BUILDS_PER_FRAME)


## Builds up to [param budget] missing chunks around [param at], nearest
## first, and drops far ones. A budget of 0 or less builds them all.
func update_around(at: Vector3, budget: int) -> void:
	var centre := Vector2(at.x, at.z)
	for key in _chunks.keys():
		if _chunk_centre(key).distance_to(centre) > KEEP + DROP_MARGIN + CHUNK:
			_chunks[key].queue_free()
			_chunks.erase(key)
	var reach := int(ceil(KEEP / CHUNK))
	var cx := int(floor(at.x / CHUNK))
	var cz := int(floor(at.z / CHUNK))
	var missing: Array[Vector2i] = []
	for i in range(cx - reach, cx + reach + 1):
		for j in range(cz - reach, cz + reach + 1):
			var key := Vector2i(i, j)
			if not _chunks.has(key) and _chunk_centre(key).distance_to(centre) <= KEEP + CHUNK:
				missing.append(key)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_centre(a).distance_squared_to(centre) < _chunk_centre(b).distance_squared_to(centre))
	if budget > 0 and missing.size() > budget:
		missing.resize(budget)
	for key in missing:
		_chunks[key] = _build_chunk(key)


## How many chunks are built.
func chunk_count() -> int:
	return _chunks.size()


func _chunk_centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK


# A chunk: its mesh and a matching collision body.
func _build_chunk(key: Vector2i) -> Node3D:
	var n := int(CHUNK / CELL)
	var gi0 := key.x * n
	var gj0 := key.y * n
	var grid: Array[PackedVector3Array] = []
	for i in n + 1:
		var row := PackedVector3Array()
		for j in n + 1:
			row.append(_vertex(gi0 + i, gj0 + j))
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in n:
		for j in n:
			var a := grid[i][j]
			var b := grid[i + 1][j]
			var c := grid[i + 1][j + 1]
			var d := grid[i][j + 1]
			# Alternate the diagonal, like the islands (W01).
			if (gi0 + i + gj0 + j) % 2 == 0:
				_triangle(st, faces, a, b, c)
				_triangle(st, faces, a, c, d)
			else:
				_triangle(st, faces, a, b, d)
				_triangle(st, faces, b, c, d)
	var body := StaticBody3D.new()
	body.name = "Chunk_%d_%d" % [key.x, key.y]
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body


# A grid vertex in world space, jittered by its own grid index so
# neighbouring chunks agree on their shared edge.
static func _vertex(gi: int, gj: int) -> Vector3:
	var x := gi * CELL
	var z := gj * CELL
	var h := hash(Vector2i(gi, gj))
	x += ((h & 1023) / 1023.0 - 0.5) * 0.6 * CELL
	z += (((h >> 10) & 1023) / 1023.0 - 0.5) * 0.6 * CELL
	return Vector3(x, height_at(x, z), z)


static func _triangle(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces wind clockwise; the floor always faces up.
	var normal := (c - a).cross(b - a)
	if normal.y < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	st.set_normal(normal.normalized())
	st.set_color(colour((a.y + b.y + c.y) / 3.0))
	for v in [a, b, c]:
		st.add_vertex(v)
		faces.append(v)


## The floor's colour at a height: sand in the shallows, darkening
## smoothly through MID to DEEP. Islands' shelves use it too (W01), so the
## two match where they meet.
static func colour(h: float) -> Color:
	if h > MID_AT:
		return SAND.lerp(MID, inverse_lerp(SAND_TO, MID_AT, minf(h, SAND_TO)))
	return MID.lerp(DEEP, inverse_lerp(MID_AT, DEEP_FROM, maxf(h, DEEP_FROM)))
