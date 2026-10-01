class_name Island
extends StaticBody3D
## A generated beach island (W01) with its collision. See IslandGenerator.

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


func height_at(x: float, z: float) -> float:
	return generator.height_at(x, z)
