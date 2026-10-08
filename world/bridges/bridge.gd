class_name Bridge
extends StaticBody3D
## A wooden bridge between two points (W06), generated in code like the
## islands: low-poly planks on posts, with rails on both sides. Any length
## and slope: the deck runs from [member from] to [member to] (the deck's
## top at each end), rising at most [constant RAMP] to stay
## [constant CLEARANCE] above the water in between; ends higher than that
## are joined in a straight line (W10's different heights). A placeholder
## that art can replace.

const WOOD := Color(0.55, 0.4, 0.26)
## Deck width and the planks' size along the bridge, metres.
const WIDTH := 2.4
const PLANK := 0.45
const PLANK_GAP := 0.05
const THICKNESS := 0.1
## The deck's height above the water away from its ends, and how steeply
## it gets there (rise per metre).
const CLEARANCE := 1.2
const RAMP := 0.15
## Posts (both sides) at most this far apart; their rails' top. The rails
## stop this far from each end, so you can step on from the side.
const POST_SPACING := 4.0
const RAIL_HEIGHT := 1.0
const RAIL_INSET := 1.0
## The rails' collision is taller than they are, so you can't jump over.
const WALL_HEIGHT := 2.2
## How far the posts reach down (below the sea floor, W01).
const POST_BOTTOM := -5.0
## How far the deck runs on past each end, into the ground.
const OVERRUN := 1.5

var from: Vector3
var to: Vector3


func _init(p_from := Vector3.ZERO, p_to := Vector3.FORWARD) -> void:
	from = p_from
	to = p_to


func _ready() -> void:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	position = from
	# Local -z runs along the bridge, +x across it.
	rotation.y = atan2(-flat.x, -flat.y)
	var built := _build(flat.length())
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = built["mesh"]
	mesh.material_override = material
	add_child(mesh)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true # the rail walls work from both sides
	shape.set_faces(built["faces"])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)


## The horizontal length, metres.
func length() -> float:
	return Vector2(to.x - from.x, to.z - from.z).length()


## The deck's top (world y) at [param s] metres from [member from], along.
func deck_y(s: float) -> float:
	return deck_height(from.y, to.y, length(), s)


## The deck's top at [param s] along a bridge [param length] long whose
## ends are at heights [param a] and [param b].
static func deck_height(a: float, b: float, length: float, s: float) -> float:
	var t := clampf(s / length, 0.0, 1.0) if length > 0.0 else 0.0
	var straight := lerpf(a, b, t)
	var arch := minf(CLEARANCE, minf(a + RAMP * maxf(s, 0.0), b + RAMP * maxf(length - s, 0.0)))
	return maxf(straight, arch)


## Whether [param point] (world) is on the bridge's deck or just above it.
func carries(point: Vector3) -> bool:
	var local := to_local(point)
	var s := -local.z
	return absf(local.x) <= WIDTH / 2.0 + 0.3 and s >= -OVERRUN and s <= length() + OVERRUN \
		and point.y >= deck_y(s) - 0.5 and point.y <= deck_y(s) + 3.0


func _build(length: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([from, to])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	# Local heights: the node sits at [member from].
	var y := func(s: float) -> float: return deck_height(from.y, to.y, length, s) - from.y
	var half := WIDTH / 2.0

	# Planks across the deck, each tilted to the slope under it.
	var s := -OVERRUN
	while s < length + OVERRUN:
		var s1 := minf(s + PLANK, length + OVERRUN)
		var y0: float = y.call(s) + rng.randf_range(-0.015, 0.015)
		var y1: float = y.call(s1) + rng.randf_range(-0.015, 0.015)
		var shade := WOOD.lightened(rng.randf_range(-0.08, 0.12))
		var w := half + rng.randf_range(-0.06, 0.06)
		_slab(st, Vector3(-w, y0, -s), Vector3(w, y0, -s), Vector3(w, y1, -s1), Vector3(-w, y1, -s1), THICKNESS, shade)
		s = s1 + PLANK_GAP

	# The deck's collision: one strip, sampled every metre.
	var steps := maxi(1, ceili((length + 2.0 * OVERRUN) / 1.0))
	for i in steps:
		var a := -OVERRUN + (length + 2.0 * OVERRUN) * i / steps
		var b := -OVERRUN + (length + 2.0 * OVERRUN) * (i + 1) / steps
		var ya: float = y.call(a)
		var yb: float = y.call(b)
		_quad_faces(faces, Vector3(-half, ya, -a), Vector3(half, ya, -a), Vector3(half, yb, -b), Vector3(-half, yb, -b))

	# Posts, rails and the walls you can't get past.
	if length > 2.0 * RAIL_INSET:
		var span := length - 2.0 * RAIL_INSET
		var n := maxi(1, ceili(span / POST_SPACING))
		var dark := WOOD.darkened(0.25)
		for side in [-1.0, 1.0]:
			var x: float = side * (half + 0.08)
			for i in n + 1:
				var at := RAIL_INSET + span * i / n
				var top: float = y.call(at) + RAIL_HEIGHT
				var bottom := POST_BOTTOM - from.y
				_box(st, Vector3(x, (bottom + top) / 2.0, -at), Vector3(0.18, top - bottom, 0.18), dark)
				if i == n:
					continue
				var nxt := RAIL_INSET + span * (i + 1) / n
				for h in [RAIL_HEIGHT, RAIL_HEIGHT * 0.5]:
					var ya: float = y.call(at) + h
					var yb: float = y.call(nxt) + h
					_slab(st, Vector3(x - 0.06, ya, -at), Vector3(x + 0.06, ya, -at), Vector3(x + 0.06, yb, -nxt), Vector3(x - 0.06, yb, -nxt), 0.1, WOOD.lightened(0.05))
				# Sampled like the deck, so a ramp's wall follows it.
				var m := maxi(1, ceili(nxt - at))
				for j in m:
					var a := at + (nxt - at) * j / m
					var b := at + (nxt - at) * (j + 1) / m
					var ya: float = y.call(a)
					var yb: float = y.call(b)
					_quad_faces(faces, Vector3(x, ya, -a), Vector3(x, ya + WALL_HEIGHT, -a), Vector3(x, yb + WALL_HEIGHT, -b), Vector3(x, yb, -b))
	return {"mesh": st.commit(), "faces": faces}


# A flat slab whose top is the quad a b c d, [param thick] deep.
func _slab(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thick: float, colour: Color) -> void:
	var down := Vector3(0.0, -thick, 0.0)
	var centre := (a + b + c + d) / 4.0 + down / 2.0
	_quad(st, centre, a, b, c, d, colour)
	_quad(st, centre, a + down, b + down, c + down, d + down, colour.darkened(0.3))
	var side := colour.darkened(0.15)
	_quad(st, centre, a + down, b + down, b, a, side)
	_quad(st, centre, b + down, c + down, c, b, side)
	_quad(st, centre, c + down, d + down, d, c, side)
	_quad(st, centre, d + down, a + down, a, d, side)


# An upright box centred on [param centre].
func _box(st: SurfaceTool, centre: Vector3, size: Vector3, colour: Color) -> void:
	var h := size / 2.0
	var top := centre + Vector3(0.0, h.y, 0.0)
	_slab(st, top + Vector3(-h.x, 0, h.z), top + Vector3(h.x, 0, h.z), top + Vector3(h.x, 0, -h.z), top + Vector3(-h.x, 0, -h.z), size.y, colour)


# Two triangles facing away from [param inside] (flat-shaded, one colour).
func _quad(st: SurfaceTool, inside: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	var out := (a + b + c + d) / 4.0 - inside
	_triangle(st, out, a, b, c, colour)
	_triangle(st, out, a, c, d, colour)


func _triangle(st: SurfaceTool, out: Vector3, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	# Godot's front faces wind clockwise: (c - a) x (b - a) is the front.
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-10:
		return
	if normal.dot(out) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	st.set_normal(normal.normalized())
	st.set_color(colour)
	for v in [a, b, c]:
		st.add_vertex(v)


func _quad_faces(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		faces.append(v)
