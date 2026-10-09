class_name IslandGenerator
extends RefCounted
## Builds a low-poly island from a seed and a [Biome] (W01, W10): a height
## field that rises from below the sea floor (W08's [Seabed]) up a
## drop-off, across a shallow shelf and the beach to a flat middle, where
## the orchestrator will stand. Perlin noise bends the shoreline and adds
## dunes or hills, so every seed gives a different island. Flat-shaded and
## coloured by height (and, off the beach biome, by steepness). The water
## level is y = 0.
##
## Other biomes than the beach (W10) climb from a narrow beach up a slope
## to a shoulder at their edge height, where bridges meet them, then over
## hills up to the middle. Where props stand comes from here too
## ([method prop_spots]).

const WET_SAND := Color(0.82, 0.72, 0.52)
const SAND := Color(0.94, 0.85, 0.63)
const GRASS := Color(0.48, 0.68, 0.34)
## The drop-off is coarser: a block of COARSE x COARSE cells whose vertices
## are all below [member coarse_below] is two triangles (8 m across with
## 2 m cells).
const COARSE := 4
## Off the beach biome (W10): the beach is BEACH_WIDTH metres wide, up to
## BEACH_TOP above the water; the slope above it climbs SLOPE (rise per
## metre, on average) to the edge height; the shoulder there is SHOULDER
## metres wide. On a small island the beach and the shoulder shrink first
## (to BAND_MIN), the slope only if that isn't enough.
const BEACH_WIDTH := 3.0
const BEACH_TOP := 0.6
const SLOPE := 0.5
const SHOULDER := 4.0
const BAND_MIN := 1.5
## Hills leave VALLEYS straight ways from the shoulder to the middle,
## VALLEY_WIDTH metres wide, so you can always walk up (W10).
const VALLEYS := 3
const VALLEY_WIDTH := 4.0
## Triangles steeper than this (their normal's y below it) are rock.
const STEEP := 0.8
## Props stay this far outside the flat middle, and off ground steeper
## than PROP_SLOPE (rise per metre).
const PROP_CLEAR := 2.5
const PROP_SLOPE := 0.7

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
## The shallow shelf around the beach: it reaches [member sea_floor] at
## [member shelf_start] shoreline radii and stays there to
## [member shelf_end], then the drop-off falls to [member skirt_floor],
## below the deepest sea floor ([constant Seabed.DEEPEST]), by
## [member skirt_end].
var sea_floor := -4.0
var shelf_start := 1.25
var shelf_end := 1.4
var skirt_end := 1.75
var skirt_floor := -36.0
## Depth below which the island is coarse (see [constant COARSE]): the
## drop-off, below the shelf.
var coarse_below := -5.0
## The kind of island ([enum Biome.Kind]) and its [constant Biome.PROFILES]
## entry.
var biome: int
var profile: Dictionary
## The highest point of the last [method build], metres.
var top := 0.0

var _shore_noise := FastNoiseLite.new()
var _dune_noise := FastNoiseLite.new()
var _seed: int
var _tint := RandomNumberGenerator.new()
var _valley_turn := 0.0 # the first valley's angle


func _init(p_seed: int, p_biome: int = Biome.Kind.BEACH) -> void:
	_seed = p_seed
	biome = p_biome
	profile = Biome.profile(biome)
	plateau_height = profile["plateau"]
	dune_height = profile["hills"]
	_tint.seed = p_seed + 2
	var turn := RandomNumberGenerator.new()
	turn.seed = p_seed + 4
	_valley_turn = turn.randf() * TAU
	_shore_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_shore_noise.seed = p_seed
	_shore_noise.frequency = 1.0
	_dune_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_dune_noise.seed = p_seed + 1
	_dune_noise.frequency = 0.07
	_dune_noise.fractal_octaves = 3
	if not profile["legacy"]:
		_dune_noise.frequency = 0.05


## Distance from the centre to the shoreline in the direction of (x, z).
## Sampled around a circle so the outline closes on itself.
func shore_radius(x: float, z: float) -> float:
	var a := atan2(z, x)
	return radius * (1.0 + 0.45 * _shore_noise.get_noise_2d(cos(a) * 1.5, sin(a) * 1.5))


## How high the island is where bridges meet it (W06, W10): the beach's
## half metre, or the shoulder at the top of the slope.
func edge_height() -> float:
	return profile["edge"]


func height_at(x: float, z: float) -> float:
	if not profile["legacy"]:
		return _biome_height(x, z)
	var shore := shore_radius(x, z)
	var t := Vector2(x, z).length() / shore  # 0 at the centre, 1 at the shoreline
	var flat := plateau_radius / shore
	var h: float
	if t < 1.0:
		h = plateau_height * (1.0 - smoothstep(flat, 1.0, t))
	else:
		h = sea_floor * smoothstep(1.0, shelf_start, t)
		h += (skirt_floor - sea_floor) * smoothstep(shelf_end, skirt_end, t)
	# Dunes: none on the flat middle, and gone before the beach so the
	# shoreline stays clean (no holes or stray islets).
	var dunes := smoothstep(flat, flat + 0.2, t) * (1.0 - smoothstep(0.65, 0.9, t))
	return h + _dune_noise.get_noise_2d(x, z) * dune_height * 2.0 * dunes


# Off the beach biome: the beach, the slope up to the shoulder, the
# shoulder, then up to the flat middle, with hills between them.
func _biome_height(x: float, z: float) -> float:
	var shore := shore_radius(x, z)
	var r := Vector2(x, z).length()
	var t := r / shore
	if t >= 1.0:
		var below := sea_floor * smoothstep(1.0, shelf_start, t)
		return below + (skirt_floor - sea_floor) * smoothstep(shelf_end, skirt_end, t)
	var edge: float = profile["edge"]
	var d := shore - r # metres inland from the shoreline
	var bands := _bands(shore)
	var b := bands[0]
	var c := bands[1]
	var w := bands[2]
	var beach_top := minf(BEACH_TOP, edge)
	var h: float
	if d < b:
		h = beach_top * smoothstep(0.0, b, d)
	elif d < b + c:
		h = lerpf(beach_top, edge, smoothstep(b, b + c, d))
	else:
		var rise_end := shore - plateau_radius
		h = lerpf(edge, plateau_height, smoothstep(b + c + w, rise_end, d)) if rise_end > b + c + w else plateau_height
	# Hills: none on the shoulder (bridges land there) or the flat middle.
	var hills := smoothstep(b + c + w, b + c + w + 3.0, d) * smoothstep(plateau_radius + 1.0, plateau_radius + 5.0, r)
	hills *= smoothstep(VALLEY_WIDTH / 2.0, VALLEY_WIDTH * 1.5, _valley_distance(x, z))
	if hills > 0.0:
		h += clampf(_dune_noise.get_noise_2d(x, z) * profile.get("hill_gain", 2.5), 0.0, 1.0) * dune_height * hills
	return h


# How far (x, z) is from the nearest valley's line, metres.
func _valley_distance(x: float, z: float) -> float:
	var step := TAU / VALLEYS
	var off := fposmod(atan2(z, x) - _valley_turn + step / 2.0, step) - step / 2.0
	return Vector2(x, z).length() * absf(sin(off))


# The beach's, the slope's and the shoulder's widths for a shoreline
# [param shore] metres out, fitted to a small island: 3 m are kept for
# the rise to the middle.
func _bands(shore: float) -> Array[float]:
	var edge: float = profile["edge"]
	var b := BEACH_WIDTH
	var c := maxf(0.0, edge - BEACH_TOP) / SLOPE
	var w := SHOULDER
	var room := shore - plateau_radius - 3.0
	if b + c + w > room:
		var k := clampf((room - c) / (b + w), BAND_MIN / BEACH_WIDTH, 1.0)
		b *= k
		w = maxf(BAND_MIN, w * k)
	if b + c + w > room:
		var k := clampf(room / (b + c + w), 0.3, 1.0)
		return [b * k, c * k, w * k]
	return [b, c, w]


## Where props stand (W10), from the seed: an Array of {"prop":
## [enum IslandProps.Prop], "position": Vector3 (local), "yaw": float,
## "scale": float}, on jittered grid cells sized by the biome's density;
## not on the beach, the flat middle or steep ground.
func prop_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kinds: Array = profile["props"]
	var density: float = profile["density"]
	if kinds.is_empty() or density <= 0.0:
		return out
	var total := 0.0
	for k in kinds:
		total += k[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 3
	var spacing := sqrt(100.0 / density)
	var n := int(ceil(radius * 1.45 / spacing))
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			# Every roll is made, kept or not, so a spot doesn't depend on
			# the ones before it.
			var x := (i + rng.randf_range(-0.4, 0.4)) * spacing
			var z := (j + rng.randf_range(-0.4, 0.4)) * spacing
			var roll := rng.randf() * total
			var yaw := rng.randf() * TAU
			var size := rng.randf_range(0.8, 1.25)
			if Vector2(x, z).length() < plateau_radius + PROP_CLEAR:
				continue
			var h := height_at(x, z)
			if h < BEACH_TOP + 0.3:
				continue
			var gx := absf(height_at(x + 1.0, z) - height_at(x - 1.0, z)) / 2.0
			var gz := absf(height_at(x, z + 1.0) - height_at(x, z - 1.0)) / 2.0
			if maxf(gx, gz) > PROP_SLOPE:
				continue
			var prop: int = kinds[0][0]
			for k in kinds:
				roll -= k[1]
				if roll <= 0.0:
					prop = k[0]
					break
			# Sunk a little, so a prop on a slope doesn't float.
			out.append({"prop": prop, "position": Vector3(x, h - 0.15, z), "yaw": yaw, "scale": size})
	return out


## Returns {"mesh": ArrayMesh, "faces": PackedVector3Array}; the faces are
## for a ConcavePolygonShape3D. The seabed is coarse (see [constant
## COARSE]); fine cells beside a coarse block have their vertices on the
## shared edge moved onto it, so there are no cracks.
func build() -> Dictionary:
	var extent := radius * 1.45 * skirt_end
	# A whole number of coarse blocks across.
	var n := int(ceil(2.0 * extent / cell / COARSE)) * COARSE
	extent = n * cell / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	top = -INF
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
			top = maxf(top, row[-1].y)
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
	st.set_color(_colour((a.y + b.y + c.y) / 3.0, normal.y))
	for v in [a, b, c]:
		st.add_vertex(v)
		faces.append(v)


func _colour(h: float, up: float) -> Color:
	if h < -0.5:
		return Seabed.colour(h) # the sea floor's own colours (W08)
	if profile["legacy"]:
		if h < 0.25:
			return WET_SAND
		if h > plateau_height + 0.4:
			return GRASS
		return SAND
	var colour: Color
	if h < 0.25:
		colour = profile["wet"]
	elif profile["peak_from"] > 0.0 and h > profile["peak_from"]:
		colour = profile["peak"]
	elif up < STEEP and h > BEACH_TOP:
		colour = profile["rock"]
	elif h < minf(BEACH_TOP, edge_height()) + 0.15:
		colour = profile["shore"]
	elif h > profile["high_from"]:
		colour = profile["high"]
	else:
		colour = profile["ground"]
	# A little variation per triangle, so big areas aren't one flat colour.
	var shade := _tint.randf_range(-0.05, 0.05)
	return colour.lightened(shade) if shade > 0.0 else colour.darkened(-shade)
