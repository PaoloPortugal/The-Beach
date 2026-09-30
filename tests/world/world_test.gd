extends SceneTree
## Headless test for the M1 world: the island generator (W01), jump
## assist (W03), then the world scene itself with real physics: the player
## lands on the island, walks, jumps and is put back when it falls in the
## sea; then walking up to the orchestrator to chat (A01, C01).
##
##   godot --headless --path . --script res://tests/world/world_test.gd

var _failed := false


func _initialize() -> void:
	_run()


func _run() -> void:
	_island()
	_jump_assist()
	await _scene()
	if not _failed:
		print("PASS world_test")
		quit(0)


func _island() -> void:
	var a := IslandGenerator.new(42)
	var b := IslandGenerator.new(42)
	var c := IslandGenerator.new(7)
	var same := true
	var differs := false
	for p in [Vector2(10, 3), Vector2(-15, 12), Vector2(4, -22), Vector2(25, 25)]:
		same = same and is_equal_approx(a.height_at(p.x, p.y), b.height_at(p.x, p.y))
		differs = differs or not is_equal_approx(a.height_at(p.x, p.y), c.height_at(p.x, p.y))
	_check(same, "same seed, same island")
	_check(differs, "different seed, different island")

	for seed in [1, 7, 42, 1234, 99999]:
		var g := IslandGenerator.new(seed)
		var flat := true
		for r in [0.0, 3.0, 6.0]:
			for k in 8:
				var ang := k * TAU / 8.0
				flat = flat and is_equal_approx(g.height_at(cos(ang) * r, sin(ang) * r), g.plateau_height)
		_check(flat, "seed %d: the middle is flat and above water" % seed)
		# Every direction reaches the sea, and far out is the sea floor.
		var shore := true
		for k in 16:
			var ang := k * TAU / 16.0
			var far := g.shore_radius(cos(ang), sin(ang)) * 1.7
			shore = shore and is_equal_approx(g.height_at(cos(ang) * far, sin(ang) * far), g.sea_floor)
		_check(shore, "seed %d: surrounded by sea" % seed)

	var built := a.build()
	var faces: PackedVector3Array = built["faces"]
	_check(faces.size() > 0 and faces.size() % 3 == 0, "mesh has triangles")
	var up := true
	for i in range(0, faces.size(), 3):
		up = up and (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).y > 0.0
	_check(up, "every triangle faces up (clockwise from above)")


func _jump_assist() -> void:
	var dt := 1.0 / 60.0
	var j := JumpAssist.new()
	_check(j.step(dt, true, true), "a press on the floor jumps")
	_check(not j.step(dt, true, false), "one press, one jump")

	j = JumpAssist.new()
	j.step(dt, false, true)  # pressed in the air...
	for i in 4:
		j.step(dt, false, false)
	_check(j.step(dt, true, false), "...and it jumps on landing (buffer)")

	j = JumpAssist.new()
	j.step(dt, false, true)
	for i in 20:
		j.step(dt, false, false)
	_check(not j.step(dt, true, false), "a press long before landing is dropped")

	j = JumpAssist.new()
	j.step(dt, true, false)
	for i in 4:
		j.step(dt, false, false)  # walked off an edge
	_check(j.step(dt, false, true), "a press just after leaving the floor jumps (coyote)")
	_check(not j.step(dt, false, true), "no second jump in the air")

	j = JumpAssist.new()
	j.step(dt, true, false)
	for i in 20:
		j.step(dt, false, false)
	_check(not j.step(dt, false, true), "no coyote jump long after leaving the floor")


func _scene() -> void:
	var world: Node3D = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	await process_frame  # _ready runs once the tree is going
	var player: Player = world.get_node("Player")
	var island: Island = world.get_node("Island")
	var spawn := player.spawn_point
	_check(is_equal_approx(spawn.y, island.height_at(0, 0) + 0.1), "spawns on the flat middle of the island")

	await _frames(30)
	_check(player.is_on_floor() and absf(player.global_position.y - island.height_at(0, 0)) < 0.2, "lands on the island")

	var before := player.global_position
	Input.action_press("move_forward")
	await _frames(30)
	Input.action_release("move_forward")
	var walked := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	_check(walked > 1.5, "walks (%.2f m in 0.5 s)" % walked)

	await _frames(30)
	var start_y := player.global_position.y
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	await _frames(15)
	_check(player.global_position.y > start_y + 0.8, "jumps")

	player.global_position = Vector3(0, -3, 0)
	await _frames(2)
	_check(player.global_position.is_equal_approx(spawn) or player.global_position.distance_to(spawn) < 0.2, "falling in the sea puts it back at the spawn")

	await _chat(world, player)

	world.queue_free()
	await _frames(1)


func _chat(world: Node3D, player: Player) -> void:
	var orchestrator: Orchestrator = world.get_node("Orchestrator")
	var chat: ChatController = world.get_node("ChatController")
	var island: Island = world.get_node("Island")
	_check(orchestrator.position.is_equal_approx(Vector3(0, island.height_at(0, 0), 0)), "the orchestrator stands in the middle")
	await _frames(5)
	_check(not chat.prompt_visible(), "no chat prompt at the spawn (6 m away)")

	_press("interact")
	await _frames(2)
	_check(not chat.is_open(), "E does nothing far from the orchestrator")

	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _frames(5)
	_check(chat.prompt_visible(), "walking close shows \"Press E to chat\"")

	_press("interact")
	await _frames(2)
	_check(chat.is_open() and not chat.prompt_visible(), "E opens the chat and hides the prompt")
	# Headless Godot has no mouse (its mode always reads visible), so the
	# mouse capture is checked in the running game, not here.
	_check(not player.controls_enabled, "the chat pauses the player")
	var at := player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(at) < 0.05, "no walking while chatting")

	_press("ui_cancel")
	await _frames(2)
	_check(not chat.is_open() and chat.prompt_visible(), "Esc closes the chat; the prompt is back")
	_check(player.controls_enabled, "Esc gives the controls back")

	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 6.0)
	await _frames(5)
	_check(not chat.prompt_visible(), "walking away hides the prompt")


func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
