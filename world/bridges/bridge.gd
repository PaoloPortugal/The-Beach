class_name Bridge
extends StaticBody3D
## A wooden bridge between two points (W06), generated in code like the
## islands: low-poly planks on posts, with rails on both sides. Any length
## and slope: the deck runs from [member from] to [member to] (the deck's
## top at each end), rising at most [constant RAMP] to stay
## [constant CLEARANCE] above the water in between; ends higher than that
## are joined in a straight line (W10's different heights). A placeholder
## that art can replace.
##
## It's drawn in segments (see [constant SEGMENT]), each with its up-close
## look and a simple far version shown past [constant NEAR_DISTANCE]
## (NOTES → Architecture → Performance). That split stays when art
## replaces the generated look: only what each version is made of changes.

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
## Steeper than this (rise per metre), the planks are level steps (W10).
const STEPS_FROM := 0.2
## Posts (both sides) at most this far apart; their rails' top. The rails
## stop this far from each end, so you can step on from the side.
const POST_SPACING := 4.0
const RAIL_HEIGHT := 1.0
const RAIL_INSET := 1.0
## The rails' collision is taller than they are, so you can't jump over.
const WALL_HEIGHT := 2.2
## How far the posts reach into the sea floor (W08's [Seabed]).
const POST_SINK := 0.5
## How far the deck runs on past each end, into the ground.
const OVERRUN := 1.5
## Segments are at most this long, metres, so a long bridge's near part
## isn't judged by its middle's distance.
const SEGMENT := 24.0
## A segment whose middle is further than this from the camera, metres,
## shows its far version. The margin keeps it from flickering at the line:
## it swaps at NEAR_DISTANCE + NEAR_MARGIN going away and at
## NEAR_DISTANCE - NEAR_MARGIN coming back.
const NEAR_DISTANCE := 70.0
const NEAR_MARGIN := 4.0
## The far version's pieces are at most this long, metres.
const FAR_STEP := 4.0

var from: Vector3
var to: Vector3
## Set before it enters the tree ([BridgeNetwork] passes it on): its
## meshes and collision are made on a worker thread (W01: about 0.5 ms a
## metre), and go in once made; [method carries] works before.
var build_in_background := false

## Its meshes and collision are in ([member build_in_background]).
signal built

var _task := -1 # its WorkerThreadPool task while it's being made
var _made := {} # what the task made: written there, read once it's done
var _maker: Bridge # the bridge the task works on
var _built := false


func _init(p_from := Vector3.ZERO, p_to := Vector3.FORWARD) -> void:
	from = p_from
	to = p_to


func _ready() -> void:
	set_process(false)
	# Also on the "ground" layer (project.godot), for D01's bobber.
	set_collision_layer_value(3, true)
	var flat := Vector2(to.x - from.x, to.z - from.z)
	position = from
	# Local -z runs along the bridge, +x across it.
	rotation.y = atan2(-flat.x, -flat.y)
	if not build_in_background:
		_add(_make(self, {}))
		return
	# The task works on a bridge of its own, out of the tree (made here: a
	# body is made with it), and writes only to _made, so this one can be
	# freed while it runs.
	_maker = Bridge.new(from, to)
	_maker.rotation.y = rotation.y
	var made := _made
	var maker := _maker
	_task = WorkerThreadPool.add_task(func() -> void: Bridge._make(maker, made), false, "Bridge")
	set_process(true)


func _process(_delta: float) -> void:
	if not WorkerThreadPool.is_task_completed(_task):
		return
	_end_task()
	set_process(false)
	_add(_made)
	built.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		_end_task()


func _end_task() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_maker.free()
	_maker = null


## Whether its meshes and collision are in (always, unless [member
## build_in_background]).
func is_built() -> bool:
	return _built


# The slow part, on any thread for a bridge out of the tree: [param into]
# gets [param b]'s near and far surfaces, a segment each, and its
# collision's faces.
static func _make(b: Bridge, into: Dictionary) -> Dictionary:
	var bounds := b.segment_bounds()
	var far: Array[Array] = []
	for k in bounds.size() - 1:
		far.append(b._far_mesh(b.length(), bounds[k], bounds[k + 1]))
	into["near"] = b._near_meshes(b.length(), bounds)
	into["far"] = far
	into["faces"] = b._collision_faces(b.length())
	return into


func _add(made: Dictionary) -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	for k in made["near"].size():
		var segment := Node3D.new()
		segment.name = "Segment%d" % k
		add_child(segment)
		var up_close := MeshInstance3D.new()
		up_close.name = "Near"
		up_close.mesh = _mesh_of(made["near"][k])
		up_close.material_override = material
		up_close.visibility_range_end = NEAR_DISTANCE
		up_close.visibility_range_end_margin = NEAR_MARGIN
		segment.add_child(up_close)
		var far := MeshInstance3D.new()
		far.name = "Far"
		far.mesh = _mesh_of(made["far"][k])
		far.material_override = material
		far.visibility_range_begin = NEAR_DISTANCE
		far.visibility_range_begin_margin = NEAR_MARGIN
		segment.add_child(far)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true # the rail walls work from both sides
	shape.set_faces(made["faces"])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	_built = true


static func _mesh_of(arrays: Array) -> ArrayMesh:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Where the segments start and end, metres along from [member from]: the
## deck's whole run (overrun included) cut evenly, none longer than
## [constant SEGMENT].
func segment_bounds() -> PackedFloat32Array:
	var total := length() + 2.0 * OVERRUN
	var count := maxi(1, ceili(total / SEGMENT))
	var out := PackedFloat32Array()
	for k in count + 1:
		out.append(-OVERRUN + total * k / count)
	return out


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


# The up-close look, one surface's arrays per segment: planks across the deck, each
# tilted to the slope under it, and posts with two rails on both sides. A
# piece goes in the segment where it starts.
func _near_meshes(length: float, bounds: PackedFloat32Array) -> Array[Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([from, to])
	var tools: Array[SurfaceTool] = []
	for k in bounds.size() - 1:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var segment_at := func(s: float) -> SurfaceTool:
		for k in range(bounds.size() - 2, 0, -1):
			if s >= bounds[k]:
				return tools[k]
		return tools[0]
	var y := _deck_y_local(length)
	var half := WIDTH / 2.0

	var s := -OVERRUN
	while s < length + OVERRUN:
		var s1 := minf(s + PLANK, length + OVERRUN)
		var y0: float = y.call(s) + rng.randf_range(-0.015, 0.015)
		var y1: float = y.call(s1) + rng.randf_range(-0.015, 0.015)
		var shade := WOOD.lightened(rng.randf_range(-0.08, 0.12))
		var w := half + rng.randf_range(-0.06, 0.06)
		var thick := THICKNESS
		# Steep: a level step at the slope's middle, deep enough to meet
		# the next (W10). The collision stays a smooth ramp.
		if absf(y1 - y0) > STEPS_FROM * (s1 - s):
			var mid: float = y.call((s + s1) / 2.0)
			thick += absf(y1 - y0) + PLANK_GAP
			y0 = mid
			y1 = mid
		_slab(segment_at.call(s), Vector3(-w, y0, -s), Vector3(w, y0, -s), Vector3(w, y1, -s1), Vector3(-w, y1, -s1), thick, shade)
		s = s1 + PLANK_GAP

	var posts := _posts(length)
	var dark := WOOD.darkened(0.25)
	for side in [-1.0, 1.0]:
		var x: float = side * (half + 0.08)
		for i in posts.size():
			var at := posts[i]
			var st: SurfaceTool = segment_at.call(at)
			var top: float = y.call(at) + RAIL_HEIGHT
			var bottom := _post_bottom(x, at)
			_box(st, Vector3(x, (bottom + top) / 2.0, -at), Vector3(0.18, top - bottom, 0.18), dark)
			if i == posts.size() - 1:
				continue
			var nxt := posts[i + 1]
			for h in [RAIL_HEIGHT, RAIL_HEIGHT * 0.5]:
				var ya: float = y.call(at) + h
				var yb: float = y.call(nxt) + h
				_slab(st, Vector3(x - 0.06, ya, -at), Vector3(x + 0.06, ya, -at), Vector3(x + 0.06, yb, -nxt), Vector3(x - 0.06, yb, -nxt), 0.1, WOOD.lightened(0.05))
	var out: Array[Array] = []
	for st in tools:
		out.append(st.commit_to_arrays())
	return out


# The far version of the segment from [param s0] to [param s1]: the deck
# as one slab (its top and sides), a top rail on each side and plain posts
# down into the sea floor, in the near pieces' colours (a surface's arrays).
func _far_mesh(length: float, s0: float, s1: float) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := _deck_y_local(length)
	var half := WIDTH / 2.0
	var down := Vector3(0.0, -THICKNESS, 0.0)
	var steps := maxi(1, ceili((s1 - s0) / FAR_STEP))
	for i in steps:
		var a := lerpf(s0, s1, float(i) / steps)
		var b := lerpf(s0, s1, float(i + 1) / steps)
		var ya: float = y.call(a)
		var yb: float = y.call(b)
		var l0 := Vector3(-half, ya, -a)
		var r0 := Vector3(half, ya, -a)
		var r1 := Vector3(half, yb, -b)
		var l1 := Vector3(-half, yb, -b)
		var inside := (l0 + r1) / 2.0 + down / 2.0
		_quad(st, inside, l0, r0, r1, l1, WOOD.lightened(0.02))
		_quad(st, inside, r0, r1, r1 + down, r0 + down, WOOD.darkened(0.15))
		_quad(st, inside, l0, l1, l1 + down, l0 + down, WOOD.darkened(0.15))
	var posts := _posts(length)
	if posts.is_empty():
		return st.commit_to_arrays()
	var dark := WOOD.darkened(0.25)
	var rail := WOOD.lightened(0.05)
	for side in [-1.0, 1.0]:
		var x: float = side * (half + 0.08)
		for at in posts:
			# Each post in one segment: the one it starts in.
			if at >= s0 and at < s1:
				_post(st, Vector3(x, y.call(at) + RAIL_HEIGHT, -at), _post_bottom(x, at), dark)
		# The top rail, where this segment has one.
		var ra := maxf(s0, posts[0])
		var rb := minf(s1, posts[-1])
		if rb - ra < 0.01:
			continue
		var rail_steps := maxi(1, ceili((rb - ra) / FAR_STEP))
		var lo := Vector3(0.0, -0.1, 0.0)
		for i in rail_steps:
			var a := lerpf(ra, rb, float(i) / rail_steps)
			var b := lerpf(ra, rb, float(i + 1) / rail_steps)
			var ya: float = y.call(a) + RAIL_HEIGHT
			var yb: float = y.call(b) + RAIL_HEIGHT
			var inside := Vector3(x, (ya + yb) / 2.0 - 0.05, -(a + b) / 2.0)
			var p0 := Vector3(x - 0.06, ya, -a)
			var q0 := Vector3(x + 0.06, ya, -a)
			var q1 := Vector3(x + 0.06, yb, -b)
			var p1 := Vector3(x - 0.06, yb, -b)
			_quad(st, inside, p0, q0, q1, p1, rail)
			_quad(st, inside, q0, q1, q1 + lo, q0 + lo, rail.darkened(0.15))
			_quad(st, inside, p0, p1, p1 + lo, p0 + lo, rail.darkened(0.15))
	return st.commit_to_arrays()


# The deck's collision as one strip sampled every metre, and on both sides
# a wall 2.2 m high you can't get past.
func _collision_faces(length: float) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var y := _deck_y_local(length)
	var half := WIDTH / 2.0
	var steps := maxi(1, ceili((length + 2.0 * OVERRUN) / 1.0))
	for i in steps:
		var a := -OVERRUN + (length + 2.0 * OVERRUN) * i / steps
		var b := -OVERRUN + (length + 2.0 * OVERRUN) * (i + 1) / steps
		var ya: float = y.call(a)
		var yb: float = y.call(b)
		_quad_faces(faces, Vector3(-half, ya, -a), Vector3(half, ya, -a), Vector3(half, yb, -b), Vector3(-half, yb, -b))
	var posts := _posts(length)
	for side in [-1.0, 1.0]:
		var x: float = side * (half + 0.08)
		for i in posts.size() - 1:
			var at := posts[i]
			var nxt := posts[i + 1]
			# Sampled like the deck, so a ramp's wall follows it.
			var m := maxi(1, ceili(nxt - at))
			for j in m:
				var a := at + (nxt - at) * j / m
				var b := at + (nxt - at) * (j + 1) / m
				var ya: float = y.call(a)
				var yb: float = y.call(b)
				_quad_faces(faces, Vector3(x, ya, -a), Vector3(x, ya + WALL_HEIGHT, -a), Vector3(x, yb + WALL_HEIGHT, -b), Vector3(x, yb, -b))
	return faces


# The deck's top in local heights (the node sits at [member from]), by
# the distance along.
func _deck_y_local(length: float) -> Callable:
	return func(s: float) -> float: return deck_height(from.y, to.y, length, s) - from.y


# Where the posts stand, metres along: at most POST_SPACING apart between
# the rails' ends, which stop RAIL_INSET from each end. None on a bridge
# too short for rails.
func _posts(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if length <= 2.0 * RAIL_INSET:
		return out
	var span := length - 2.0 * RAIL_INSET
	var n := maxi(1, ceili(span / POST_SPACING))
	for i in n + 1:
		out.append(RAIL_INSET + span * i / n)
	return out


# Where the post at ([param x], -[param at]) ends, in the bridge's own
# coordinates: a little way into the sea floor under it.
func _post_bottom(x: float, at: float) -> float:
	var world := from + Vector3(x, 0.0, -at).rotated(Vector3.UP, rotation.y)
	return Seabed.height_at(world.x, world.z) - POST_SINK - from.y


# A far post: its four sides, from [param bottom] up to [param top].
func _post(st: SurfaceTool, top: Vector3, bottom: float, colour: Color) -> void:
	var h := 0.09
	var inside := Vector3(top.x, (top.y + bottom) / 2.0, top.z)
	var corners := [Vector3(-h, 0, h), Vector3(h, 0, h), Vector3(h, 0, -h), Vector3(-h, 0, -h)]
	for k in 4:
		var c0: Vector3 = top + corners[k]
		var c1: Vector3 = top + corners[(k + 1) % 4]
		_quad(st, inside, c0, c1, Vector3(c1.x, bottom, c1.z), Vector3(c0.x, bottom, c0.z), colour)


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
