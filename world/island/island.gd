class_name Island
extends StaticBody3D
## A generated island (W01) with its collision, of a [Biome] (W10) with
## its props ([IslandProps]) and, on a mountain, its [Zipline]. See
## IslandGenerator. Torches along its edge light up at night (W09).

## How many torches, evenly round the island.
const TORCHES := 4
## Props keep this far from a torch, metres.
const TORCH_CLEAR := 1.5
## Props keep this far from a zipline's cable, across the ground, metres.
const ZIPLINE_CLEAR := 2.0

## 0 picks a new random island every run; any other value pins one. Holds
## the one used once it's in the tree (W12 saves it).
@export var island_seed := 0
## The kind of island ([enum Biome.Kind]); set before it enters the tree.
@export var biome: int = Biome.Kind.BEACH

var generator: IslandGenerator
## Its trees, rocks and the like.
var props := IslandProps.new()
## Which valley's mouth its zipline stands at (W10; see [method
## IslandGenerator.zipline_valley]).
var zipline_valley := 0
## Set before it enters the tree (SessionIslands does): its zipline waits
## for the first [method set_landings], so it starts clear of its bridges
## and clears no props under a valley it then leaves.
var zipline_waits := false
## Set before it enters the tree (SessionIslands does, C14): its ground
## is made on a worker thread, so a new island doesn't stall the game for
## the 50-90 ms it takes, and what's then added on the main thread goes
## in a step a frame (W01). Until [signal built] it has its [member
## generator] ([method height_at] works) but not all of its ground,
## collision, props or torches.
var build_in_background := false

## Its ground is in ([member build_in_background]).
signal built

var _landings: Array[Vector3] = []
var _landed := false # set_landings has been called
var _task := -1 # its WorkerThreadPool task while it's being made
var _made := {} # what the task made: written there, read once it's done
var _steps: Array[Callable] = [] # what's left to add, a step a frame
var _built := false
var _shape: ConcavePolygonShape3D # its collision, between two steps
static var _ground_material: StandardMaterial3D


func _ready() -> void:
	set_process(false)
	if island_seed == 0:
		island_seed = randi_range(1, 2147483647) # kept: W12 saves it
	print("Island seed: %d (%s)" % [island_seed, Biome.NAMES[biome]])
	generator = IslandGenerator.new(island_seed, biome)
	if not build_in_background:
		for step in _finish_steps(_make(island_seed, biome, {})):
			step.call()
		_built = true
		return
	# The task has a generator of its own and writes only to _made, so the
	# island can be freed while it runs.
	var made := _made
	var s := island_seed
	var b := biome
	_task = WorkerThreadPool.add_task(func() -> void: Island._make(s, b, made), false, "Island %d" % s)
	set_process(true)


func _process(_delta: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_steps = _finish_steps(_made)
	_steps.pop_front().call()
	if _steps.is_empty():
		_built = true
		set_process(false)
		built.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


## Whether its ground is in (always, unless [member build_in_background]).
func is_built() -> bool:
	return _built


# The slow part, on any thread: [param into] gets the ground and the
# props' spots.
static func _make(s: int, b: int, into: Dictionary) -> Dictionary:
	var g := IslandGenerator.new(s, b)
	into.merge(g.make())
	into["spots"] = g.prop_spots()
	return into


# What's added on the main thread once the ground is made, in steps of a
# few ms each (measured: 2.5-8 ms; 18-30 ms all at once).
func _finish_steps(made: Dictionary) -> Array[Callable]:
	return [_add_ground.bind(made), _make_collision.bind(made), _add_collision, _add_props.bind(made), _add_torches, _add_rest]


func _add_ground(made: Dictionary) -> void:
	generator.take(made)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made["arrays"])
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = ground_material()
	add_child(mesh_instance)


func _make_collision(made: Dictionary) -> void:
	_shape = ConcavePolygonShape3D.new()
	_shape.set_faces(made["faces"])


func _add_collision() -> void:
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	_shape = null
	add_child(collision)


# The torches' spots are cleared first, so the props are built once.
func _add_props(made: Dictionary) -> void:
	var spots: Array[Dictionary] = made["spots"]
	for at in _torch_spots():
		spots = IslandProps.without_near(spots, at, at, TORCH_CLEAR)
	props.name = "Props"
	add_child(props)
	props.setup(spots)


func _add_rest() -> void:
	if not zipline_waits:
		_add_zipline()
	# The read-only mark stood on height_at till now; landings that came
	# first place the zipline now.
	if _landed:
		_built = true # set_landings places the zipline only on a built one
		set_landings(_landings)
	else:
		var flag := get_node_or_null("ReadOnlyFlag") as ReadOnlyFlag
		if flag:
			flag.place(self)


## The ground's material, one for every island: vertex colours, matte.
static func ground_material() -> StandardMaterial3D:
	if _ground_material == null:
		_ground_material = StandardMaterial3D.new()
		_ground_material.vertex_color_use_as_albedo = true
		_ground_material.vertex_color_is_srgb = true  # the palette is written in sRGB
		_ground_material.roughness = 1.0
	return _ground_material


func height_at(x: float, z: float) -> float:
	return generator.height_at(x, z)


## How high the island is where bridges meet it (W10).
func edge_height() -> float:
	return generator.edge_height()


## The highest point of its ground, metres above its origin.
func top() -> float:
	return generator.top


## The zipline up from its beach, or null (W10: mountains have one).
func zipline() -> Zipline:
	return get_node_or_null("Zipline") as Zipline


## Where its bridges land now, local (W06): its zipline moves to another
## valley's mouth if one runs through its cable (W10), once nobody is
## riding it. The props cleared under the old cable stay cleared (user's,
## 2026-10-12).
func set_landings(landings: Array[Vector3]) -> void:
	_landings = landings
	_landed = true
	# The read-only mark (S08) keeps clear of them.
	var flag := get_node_or_null("ReadOnlyFlag") as ReadOnlyFlag
	if flag:
		flag.place(self)
	# Not built yet: its ground comes in with them.
	if not generator.profile.get("zipline", false) or not is_built():
		return
	if zipline_waits:
		zipline_waits = false
		zipline_valley = generator.zipline_valley(landings, 0)
		_add_zipline()
		return
	_place_zipline()


## Where its bridges land now, local (W06).
func landings() -> Array[Vector3]:
	return _landings


## Shows or hides the read-only mark (S08).
func set_read_only(on: bool) -> void:
	var flag := get_node_or_null("ReadOnlyFlag") as ReadOnlyFlag
	if on and flag == null:
		flag = ReadOnlyFlag.new()
		add_child(flag)
		flag.place(self)
	elif not on and flag:
		remove_child(flag)
		flag.queue_free()


## Whether it has the read-only mark (S08).
func read_only() -> bool:
	return has_node("ReadOnlyFlag")


## The night lights on it (W09).
func torches() -> Array[NightLight]:
	var out: Array[NightLight] = []
	for c in get_children():
		if c is NightLight:
			out.append(c)
	return out


# Torches at the island's edge height (half a metre on a beach), inward
# from the shore along a diagonal, so they mark the island's edge at night.
# They stand on the built ground, which on a cliff can be metres off
# height_at (W10).
func _add_torches() -> void:
	var spots := _torch_spots()
	for k in spots.size():
		var torch := NightLight.torch()
		torch.name = "Torch%d" % k
		torch.position = spots[k]
		add_child(torch)


func _torch_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var at := maxf(0.5, edge_height())
	for k in TORCHES:
		var dir := Vector2.from_angle(TAU * (k + 0.5) / TORCHES)
		var r := generator.shore_radius(dir.x, dir.y)
		while r > 0.0 and generator.surface_height(dir.x * r, dir.y * r) < at:
			r -= 0.5
		out.append(Vector3(dir.x * r, generator.surface_height(dir.x * r, dir.y * r), dir.y * r))
	return out


func _add_zipline() -> void:
	var ends := generator.zipline_ends(zipline_valley)
	if ends.is_empty():
		return
	var z := Zipline.new(ends[0], ends[1])
	add_child(z)
	z.ride_ended.connect(_place_zipline, CONNECT_DEFERRED)
	props.clear_near(ends[0], ends[1], ZIPLINE_CLEAR)


func _place_zipline() -> void:
	var z := zipline()
	if z == null or z.is_riding():
		return
	var v := generator.zipline_valley(_landings, zipline_valley)
	if v == zipline_valley:
		return
	zipline_valley = v
	remove_child(z)
	z.queue_free()
	_add_zipline()
