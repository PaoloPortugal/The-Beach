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

## 0 picks a new random island every run; any other value pins one.
@export var island_seed := 0
## The kind of island ([enum Biome.Kind]); set before it enters the tree.
@export var biome: int = Biome.Kind.BEACH

var generator: IslandGenerator
## Its trees, rocks and the like.
var props := IslandProps.new()


func _ready() -> void:
	var s := island_seed if island_seed != 0 else randi_range(1, 2147483647)
	print("Island seed: %d (%s)" % [s, Biome.NAMES[biome]])
	generator = IslandGenerator.new(s, biome)
	var built := generator.build()

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true  # the palette is written in sRGB
	material.roughness = 1.0
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = built["mesh"]
	mesh_instance.material_override = material
	add_child(mesh_instance)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(built["faces"])
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	props.name = "Props"
	add_child(props)
	props.setup(generator.prop_spots())
	_add_torches()
	var ends := generator.zipline_ends()
	if not ends.is_empty():
		add_child(Zipline.new(ends[0], ends[1]))
		props.clear_near(ends[0], ends[1], ZIPLINE_CLEAR)


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


## The night lights on it (W09).
func torches() -> Array[NightLight]:
	var out: Array[NightLight] = []
	for c in get_children():
		if c is NightLight:
			out.append(c)
	return out


# Torches at the island's edge height (half a metre on a beach), inward
# from the shore along a diagonal, so they mark the island's edge at night.
func _add_torches() -> void:
	var at := maxf(0.5, edge_height())
	for k in TORCHES:
		var dir := Vector2.from_angle(TAU * (k + 0.5) / TORCHES)
		var r := generator.shore_radius(dir.x, dir.y)
		while r > 0.0 and generator.height_at(dir.x * r, dir.y * r) < at:
			r -= 0.5
		var torch := NightLight.torch()
		torch.name = "Torch%d" % k
		torch.position = Vector3(dir.x * r, generator.height_at(dir.x * r, dir.y * r), dir.y * r)
		add_child(torch)
		props.clear_near(torch.position, torch.position, TORCH_CLEAR)
