class_name Seabed
extends Node3D
## The sea floor everywhere (W08): a low-poly height field in square
## chunks, made on a worker thread around the camera out to the fog and
## dropped behind it.
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
## Mounds and hollows on top of the banks and deeps: mostly within this
## high or deep, a few up to about 1.6 times it (the depth is clamped after).
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
## Chunks are made on a worker thread, this many to a task, nearest
## first, one task at a time; at most ADDS_PER_FRAME made ones go in a
## frame.
const BATCH := 6
const ADDS_PER_FRAME := 2

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

## Chunk coordinates -> its StaticBody3D.
var _chunks := {}
var _material: StandardMaterial3D
var _task := -1 # the WorkerThreadPool task making a batch, or -1
var _made: Array[Dictionary] = [] # what it made: written there, read once it's done
var _to_add: Array[Dictionary] = [] # made chunks waiting to go in
var _pending := {} # chunk coordinates -> true, being made or waiting to go in


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


# Making a chunk takes about 4 ms (it stalled the start, 6 a frame, and
# a teleport out to sea): a worker makes them (_make_chunk, static,
# writing only to its own array, so the seabed can go meanwhile) and
# the main thread only adds them.
func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var centre := Vector2(camera.global_position.x, camera.global_position.z)
	for key in _chunks.keys():
		if _chunk_centre(key).distance_to(centre) > KEEP + DROP_MARGIN + CHUNK:
			_chunks[key].queue_free()
			_chunks.erase(key)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_to_add.append_array(_made)
	for k in mini(ADDS_PER_FRAME, _to_add.size()):
		var made: Dictionary = _to_add.pop_front()
		_pending.erase(made["key"])
		# Not if the camera's gone far meanwhile (a teleport).
		if _chunk_centre(made["key"]).distance_to(centre) <= KEEP + DROP_MARGIN + CHUNK:
			_chunks[made["key"]] = _add_chunk(made)
	if _task < 0:
		var missing := _missing(centre)
		if missing.size() > BATCH:
			missing.resize(BATCH)
		if not missing.is_empty():
			for key in missing:
				_pending[key] = true
			var made: Array[Dictionary] = []
			_made = made
			_task = WorkerThreadPool.add_task(func() -> void:
				for key in missing:
					made.append(Seabed._make_chunk(key)), false, "Seabed")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


## How many chunks are in.
func chunk_count() -> int:
	return _chunks.size()


# The chunks within reach of [param centre] that aren't in or on their
# way, nearest first.
func _missing(centre: Vector2) -> Array[Vector2i]:
	var reach := int(ceil(KEEP / CHUNK))
	var cx := int(floor(centre.x / CHUNK))
	var cz := int(floor(centre.y / CHUNK))
	var missing: Array[Vector2i] = []
	for i in range(cx - reach, cx + reach + 1):
		for j in range(cz - reach, cz + reach + 1):
			var key := Vector2i(i, j)
			if not _chunks.has(key) and not _pending.has(key) and _chunk_centre(key).distance_to(centre) <= KEEP + CHUNK:
				missing.append(key)
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_centre(a).distance_squared_to(centre) < _chunk_centre(b).distance_squared_to(centre))
	return missing


static func _chunk_centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK


# A chunk's mesh arrays and collision faces (on a worker thread).
static func _make_chunk(key: Vector2i) -> Dictionary:
	var n := int(CHUNK / CELL)
	var gi0 := key.x * n
	var gj0 := key.y * n
	var grid: Array[PackedVector3Array] = []
	for i in n + 1:
		var row := PackedVector3Array()
		for j in n + 1:
			row.append(_vertex(gi0 + i, gj0 + j))
		grid.append(row)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	for i in n:
		for j in n:
			var a := grid[i][j]
			var b := grid[i + 1][j]
			var c := grid[i + 1][j + 1]
			var d := grid[i][j + 1]
			# Alternate the diagonal, like the islands (W01).
			if (gi0 + i + gj0 + j) % 2 == 0:
				_triangle(vertices, normals, colours, a, b, c)
				_triangle(vertices, normals, colours, a, c, d)
			else:
				_triangle(vertices, normals, colours, a, b, d)
				_triangle(vertices, normals, colours, b, c, d)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	return {"key": key, "arrays": arrays}


# A made chunk in: its mesh and a matching collision body.
func _add_chunk(made: Dictionary) -> Node3D:
	var key: Vector2i = made["key"]
	var arrays: Array = made["arrays"]
	var body := StaticBody3D.new()
	body.name = "Chunk_%d_%d" % [key.x, key.y]
	body.set_collision_layer_value(3, true) # also "ground" (project.godot), for D01's bobber
	var mesh := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.mesh = array_mesh
	mesh.material_override = _material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	# The collision's faces are the mesh's triangles.
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
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


static func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces wind clockwise; the floor always faces up.
	var normal := (c - a).cross(b - a)
	if normal.y < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	var tint := colour((a.y + b.y + c.y) / 3.0)
	for v in [a, b, c]:
		vertices.append(v)
		normals.append(normal.normalized())
		colours.append(tint)


## The floor's colour at a height: sand in the shallows, darkening
## smoothly through MID to DEEP. Islands' shelves use it too (W01), so the
## two match where they meet.
static func colour(h: float) -> Color:
	if h > MID_AT:
		return SAND.lerp(MID, inverse_lerp(SAND_TO, MID_AT, minf(h, SAND_TO)))
	return MID.lerp(DEEP, inverse_lerp(MID_AT, DEEP_FROM, maxf(h, DEEP_FROM)))
