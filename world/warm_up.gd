class_name WarmUp
extends Node3D
## Pays an island's first-time costs as the world loads, behind the main
## menu (W01), so the first island to arrive costs what later ones do:
## its props' meshes ([method IslandProps.warm_up], on a worker thread),
## then one of each prop, the ground's material, an orchestrator and a
## torch, out of sight where islands are made, for a few frames (their
## shaders are made as they go in and first drawn). Then it goes.

## Frames it stays once all is in.
const FRAMES := 3

static var _kept: Array[Material] = [] # see _add

var _in := false
var _frames := 0


func _ready() -> void:
	if not _kept.is_empty(): # warmed up already (another world: the suites)
		queue_free()
		return
	position.y = SessionIslands.BUILDING_Y
	IslandProps.warm_up()


func _process(_delta: float) -> void:
	if not _in:
		if IslandProps.is_warm():
			_add()
			_in = true
		return
	_frames += 1
	if _frames >= FRAMES:
		queue_free()


func _add() -> void:
	for kind: int in IslandProps.Prop.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = IslandProps.mesh(kind)
		mm.instance_count = 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = IslandProps.material()
		add_child(mmi)
	# The same vertex format as the ground's: position, normal, colour.
	var ground := MeshInstance3D.new()
	ground.mesh = IslandProps.mesh(IslandProps.Prop.SHELL)
	ground.material_override = Island.ground_material()
	add_child(ground)
	var o: Orchestrator = SessionIslands.ORCHESTRATOR.instantiate()
	o.remove_from_group("orchestrators") # no chat watches it
	var t0 := Time.get_ticks_usec() # TIMING
	add_child(o)
	print("TIMING warm orch add %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)) # TIMING
	add_child(NightLight.torch())
	# A material's shader goes with the last material that uses it: these
	# keep each one made here.
	for g: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		if g.material_override:
			_kept.append(g.material_override)
		var mesh: Mesh = g.get("mesh")
		if mesh:
			for k in mesh.get_surface_count():
				if mesh.surface_get_material(k):
					_kept.append(mesh.surface_get_material(k))
