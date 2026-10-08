class_name Island
extends StaticBody3D
## A generated beach island (W01) with its collision. See IslandGenerator.
## Torches along its beach light up at night (W09).

## How many torches, evenly round the beach.
const TORCHES := 4

## 0 picks a new random island every run; any other value pins one.
@export var island_seed := 0

var generator: IslandGenerator


func _ready() -> void:
	var s := island_seed if island_seed != 0 else randi_range(1, 2147483647)
	print("Island seed: %d" % s)
	generator = IslandGenerator.new(s)
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
	_add_torches()


func height_at(x: float, z: float) -> float:
	return generator.height_at(x, z)


## The night lights on it (W09).
func torches() -> Array[NightLight]:
	var out: Array[NightLight] = []
	for c in get_children():
		if c is NightLight:
			out.append(c)
	return out


# Torches where the beach is half a metre above the water, inward from the
# shore along a diagonal, so they mark the island's edge at night.
func _add_torches() -> void:
	for k in TORCHES:
		var dir := Vector2.from_angle(TAU * (k + 0.5) / TORCHES)
		var r := generator.shore_radius(dir.x, dir.y)
		while r > 0.0 and generator.height_at(dir.x * r, dir.y * r) < 0.5:
			r -= 0.5
		var torch := NightLight.torch()
		torch.name = "Torch%d" % k
		torch.position = Vector3(dir.x * r, generator.height_at(dir.x * r, dir.y * r), dir.y * r)
		add_child(torch)
