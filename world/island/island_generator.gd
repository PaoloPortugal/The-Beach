class_name IslandGenerator
extends RefCounted
## Builds a low-poly beach island from a seed (W01): a height field that
## rises from the sea floor to a flat middle, where the orchestrator will
## stand. Perlin noise bends the shoreline and adds dunes, so every seed
## gives a different island. Flat-shaded and coloured by height. The water
## level is y = 0.

const SEABED := Color(0.62, 0.64, 0.52)
const WET_SAND := Color(0.82, 0.72, 0.52)
const SAND := Color(0.94, 0.85, 0.63)
const GRASS := Color(0.48, 0.68, 0.34)
## The seabed, deep under the opaque water, is coarser: a block of
## COARSE x COARSE cells whose vertices are all below [member coarse_below]
## is two triangles (8 m across with 2 m cells).
const COARSE := 4

## Rough shoreline radius, metres. The noise moves it by up to a third.
var radius := 30.0
## Grid spacing, metres. Bigger is more low-poly.
var cell := 2.0
## Height of the flat middle above the water.
var plateau_height := 2.0
## Radius of the flat middle.
var plateau_radius := 7.0
## Height of the dunes between the middle and the beach.
var dune_height := 1.2
var sea_floor := -4.0
## Depth below which the seabed is coarse (see [constant COARSE]). The
## waves reach about ±0.35 m.
var coarse_below := -1.0

var _shore_noise := FastNoiseLite.new()
var _dune_noise := FastNoiseLite.new()
var _seed: int


func _init(p_seed: int) -> void:
	_seed = p_seed
	_shore_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_shore_noise.seed = p_seed
	_shore_noise.frequency = 1.0
	_dune_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_dune_noise.seed = p_seed + 1
	_dune_noise.frequency = 0.07
	_dune_noise.fractal_octaves = 3


## Distance from the centre to the shoreline in the direction of (x, z).
## Sampled around a circle so the outline closes on itself.
func shore_radius(x: float, z: float) -> float:
	var a := atan2(z, x)
	return radius * (1.0 + 0.45 * _shore_noise.get_noise_2d(cos(a) * 1.5, sin(a) * 1.5))


func height_at(x: float, z: float) -> float:
	var shore := shore_radius(x, z)
	var t := Vector2(x, z).length() / shore  # 0 at the centre, 1 at the shoreline
	var flat := plateau_radius / shore
	var h: float
	if t < 1.0:
		h = plateau_height * (1.0 - smoothstep(flat, 1.0, t))
	else:
		h = sea_floor * smoothstep(1.0, 1.6, t)
	# Dunes: none on the flat middle, and gone before the beach so the
	# shoreline stays clean (no holes or stray islets).
	var dunes := smoothstep(flat, flat + 0.2, t) * (1.0 - smoothstep(0.65, 0.9, t))
	return h + _dune_noise.get_noise_2d(x, z) * dune_height * 2.0 * dunes


## Returns {"mesh": ArrayMesh, "faces": PackedVector3Array}; the faces are
## for a ConcavePolygonShape3D. The seabed is coarse (see [constant
## COARSE]); fine cells beside a coarse block have their vertices on the
## shared edge moved onto it, so there are no cracks.
func build() -> Dictionary:
	var extent := radius * 1.4 * 1.6
	# A whole number of coarse blocks across.
	var n := int(ceil(2.0 * extent / cell / COARSE)) * COARSE
	extent = n * cell / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var grid: Array[PackedVector3Array] = []
	for i in n + 1:
		var row := PackedVector3Array()
		for j in n + 1:
			var x := -extent + i * cell
			var z := -extent + j * cell
			# Jitter inner vertices so the triangles aren't a regular grid.
			if i > 0 and i < n and j > 0 and j < n:
				x += rng.randf_range(-0.3, 0.3) * cell
				z += rng.randf_range(-0.3, 0.3) * cell
			row.append(Vector3(x, height_at(x, z), z))
		grid.append(row)

	var blocks := n / COARSE
	var coarse: Array[PackedByteArray] = []
	for bi in blocks:
		var row := PackedByteArray()
		row.resize(blocks)
		for bj in blocks:
			row[bj] = 1 if _deep(grid, bi * COARSE, bj * COARSE) else 0
		coarse.append(row)
	# Fine vertices on an edge shared with a coarse block go onto that edge.
	for bi in blocks:
		for bj in blocks:
			if not coarse[bi][bj]:
				continue
			var i0 := bi * COARSE
			var j0 := bj * COARSE
			for side in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var ni: int = bi + side[0]
				var nj: int = bj + side[1]
				if ni < 0 or nj < 0 or ni >= blocks or nj >= blocks or coarse[ni][nj]:
					continue
				# The edge's fixed coordinate and its two corners.
				for k in range(1, COARSE):
					var t := float(k) / COARSE
					if side[0] != 0:
						var ie: int = i0 + (COARSE if side[0] > 0 else 0)
						grid[ie][j0 + k] = grid[ie][j0].lerp(grid[ie][j0 + COARSE], t)
					else:
						var je: int = j0 + (COARSE if side[1] > 0 else 0)
						grid[i0 + k][je] = grid[i0][je].lerp(grid[i0 + COARSE][je], t)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for bi in blocks:
		for bj in blocks:
			if coarse[bi][bj]:
				_add_cell(st, faces, grid, bi * COARSE, bj * COARSE, COARSE, bi + bj)
				continue
			for i in range(bi * COARSE, (bi + 1) * COARSE):
				for j in range(bj * COARSE, (bj + 1) * COARSE):
					_add_cell(st, faces, grid, i, j, 1, i + j)
	return {"mesh": st.commit(), "faces": faces}


# Whether every vertex of the block at (i0, j0) is deep enough to be coarse.
func _deep(grid: Array[PackedVector3Array], i0: int, j0: int) -> bool:
	for i in range(i0, i0 + COARSE + 1):
		for j in range(j0, j0 + COARSE + 1):
			if grid[i][j].y >= coarse_below:
				return false
	return true


# Two triangles over the [param size] x [param size] cells from (i, j).
func _add_cell(st: SurfaceTool, faces: PackedVector3Array, grid: Array[PackedVector3Array], i: int, j: int, size: int, parity: int) -> void:
	var a := grid[i][j]
	var b := grid[i + size][j]
	var c := grid[i + size][j + size]
	var d := grid[i][j + size]
	# Alternate the diagonal for a less regular look.
	if parity % 2 == 0:
		_add_triangle(st, faces, a, b, c)
		_add_triangle(st, faces, a, c, d)
	else:
		_add_triangle(st, faces, a, b, d)
		_add_triangle(st, faces, b, c, d)


func _add_triangle(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot's front faces wind clockwise; the height field always faces up.
	var normal := (c - a).cross(b - a)
	if normal.y < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	st.set_normal(normal)
	st.set_color(_colour((a.y + b.y + c.y) / 3.0))
	for v in [a, b, c]:
		st.add_vertex(v)
		faces.append(v)


func _colour(h: float) -> Color:
	if h < -0.5:
		return SEABED
	if h < 0.25:
		return WET_SAND
	if h > plateau_height + 0.4:
		return GRASS
	return SAND
