extends SceneTree
## Headless test for the M1 world: the island generator (W01), jump
## assist (W03) and the bubble's text cut (C02), then the world scene with
## real physics: the player lands on the spawn platform, walks, jumps and is
## put back when it falls in the sea; the session post; islands for
## sessions (applied to the store by hand), each orchestrator's bubble, and
## walking up to chat in the chat panel (A01, C01, C02).
##
##   godot --headless --path . --script res://tests/world/world_test.gd
##   ... -- --sidecar-dev-fake    also starts a session from the post and
##                                chats with the fake provider

var _failed := false


func _initialize() -> void:
	_run()


func _run() -> void:
	_island()
	_jump_assist()
	_bubble_text()
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


func _bubble_text() -> void:
	_check(MessageBubble.tail_lines("", 40, 4) == "", "no text, no bubble")
	_check(MessageBubble.tail_lines("Hello there.", 40, 4) == "Hello there.", "short text as is")
	_check(MessageBubble.tail_lines("aaa bbb ccc", 7, 4) == "aaa bbb\nccc", "wraps at word boundaries")
	_check(MessageBubble.tail_lines("one\n\n\ntwo\n", 40, 4) == "one\ntwo", "blank lines dropped")
	_check(MessageBubble.tail_lines("l1\nl2\nl3\nl4\nl5\nl6", 40, 4) == "…l3\nl4\nl5\nl6", "keeps the last lines, marked cut")
	_check(MessageBubble.tail_lines("abcdefghij", 4, 4) == "abcd\nefgh\nij", "a long word is split")


func _scene() -> void:
	var world: Node3D = load("res://world/world.tscn").instantiate()
	root.add_child(world)
	await process_frame  # _ready runs once the tree is going
	var player: Player = world.get_node("Player")
	var spawn := player.spawn_point
	_check(spawn.is_equal_approx(Vector3(0, 1.1, 3)), "spawns on the platform")

	await _frames(30)
	_check(player.is_on_floor() and absf(player.global_position.y - 1.0) < 0.2, "lands on the platform")

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

	player.global_position = Vector3(20, -3, 0)
	await _frames(2)
	_check(player.global_position.distance_to(spawn) < 0.2, "falling in the sea puts it back on the platform")

	await _post(world, player)
	await _sessions(world, player)
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		await _live(world, player)

	world.queue_free()
	await _frames(1)


func _post(world: Node3D, player: Player) -> void:
	var post: SessionPost = world.get_node("SpawnPlatform/SessionPost")
	await _frames(5)
	_check(not post.prompt_visible(), "no session prompt at the spawn")
	player.global_position = Vector3(0, 1.1, -1.2)
	await _frames(5)
	_check(post.prompt_visible(), "near the post: \"Press E to start a session\"")
	_press("interact")
	await _frames(2)
	_check(post.picker().visible and not player.controls_enabled and not post.prompt_visible(), "E opens the folder picker, in the game window, and pauses the player")
	post.picker().get_cancel_button().pressed.emit()
	await _frames(2)
	_check(not post.picker().visible and player.controls_enabled and post.prompt_visible(), "cancelling it gives the controls back")
	# Choosing a folder ends in create().
	var sidecar: SidecarClient = root.get_node("Sidecar")
	await _until(func() -> bool: return sidecar.status == SidecarClient.Status.READY, 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "the sidecar is up")
	post.create(OS.get_user_data_dir().path_join("no-such-folder"))
	await _until(func() -> bool: return post.status_text().begins_with("Couldn't"), 5.0)
	_check(post.status_text().contains("does not exist") and post.pending == "", "a missing folder is refused, and the sign says so")
	player.respawn()
	await _frames(5)
	_check(not post.prompt_visible(), "walking away hides it")


func _snapshot(id: String) -> Dictionary:
	return {
		"session": id, "seq": 1, "provider": "fake", "native_id": null, "origin": "app",
		"project": {"path": "/p", "name": "demo"}, "title": null, "started_at": "2026-09-30T10:00:00Z",
		"capabilities": {}, "extensions": [], "permissions": [], "notices": [],
		"agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
	}


# Sessions applied to the store by hand, so no provider is needed.
func _sessions(world: Node3D, player: Player) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var chat: ChatController = world.get_node("ChatController")
	var at := player.global_position
	store.apply({"type": "session.snapshot", "session": _snapshot("h1")})
	store.apply({"type": "session.snapshot", "session": _snapshot("h2")})
	await _frames(2)
	var island := islands.island("h1")
	var orchestrator := islands.orchestrator("h1")
	_check(island != null and islands.island("h2") != null, "an island per session")
	_check(island.global_position.distance_to(islands.island("h2").global_position) > 150.0, "islands apart from each other")
	_check(Vector2(island.global_position.x, island.global_position.z).length() > 150.0, "and away from the platform")
	_check(orchestrator.session_id == "h1", "its orchestrator belongs to the session")
	_check(orchestrator.position.is_equal_approx(Vector3(0, island.height_at(0, 0), 0)), "and stands in the middle of it")
	_check(player.global_position.distance_to(at) < 0.1, "a session already running doesn't move the player")

	var bubble := chat.bubble("h1")
	_check(bubble != null and not bubble.visible, "no bubble before the orchestrator says anything")
	store.apply({"type": "message.started", "session": "h1", "seq": 2, "message": "u1", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": "h1", "seq": 3, "message": "u1", "text": "Hi there"})
	_check(not bubble.visible, "your own messages don't show in the bubble")
	store.apply({"type": "message.started", "session": "h1", "seq": 4, "message": "a1", "agent": "main", "role": "assistant"})
	store.apply({"type": "message.delta", "session": "h1", "seq": 5, "message": "a1", "text": "Looking at it.\n"})
	_check(bubble.visible and bubble.shown_text() == "Looking at it.", "the bubble streams the reply")
	store.apply({"type": "message.delta", "session": "h1", "seq": 6, "message": "a1", "text": "two\nthree\nfour\nfive\n"})
	_check(bubble.shown_text() == "…two\nthree\nfour\nfive", "and keeps its newest lines")
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 7, "agent": "main", "state": "working", "reason": null})

	world.teleport("h1")
	await _frames(20)
	_check(player.global_position.distance_to(orchestrator.global_position) < 7.0 and player.is_on_floor(), "teleport: in front of the orchestrator, on its island")
	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _frames(5)
	_check(chat.prompt_visible(), "walking close shows \"Press E to chat\"")
	_press("interact")
	await _frames(2)
	var panel := chat.panel()
	_check(chat.is_open() and panel.visible and not player.controls_enabled, "E opens the chat panel and pauses the player")
	_check(panel.shown_messages() == ["Hi there", "Looking at it.\ntwo\nthree\nfour\nfive"], "the panel shows the chat so far")
	_check(panel.status_text() == "Working…", "and what the orchestrator is doing")
	store.apply({"type": "message.completed", "session": "h1", "seq": 8, "message": "a1", "text": "Done. [url=https://x]click[/url]"})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 9, "agent": "main", "state": "idle", "reason": null})
	_check(panel.shown_messages()[1] == "Done. [url=https://x]click[/url]" and panel.status_text() == "", "it updates in place; text is shown as written, not as markup")
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 10, "agent": "main", "state": "waiting", "reason": "permission"})
	_check(panel.status_text().contains("terminal"), "a permission wait points to the terminal")
	store.apply({"type": "session.notice", "session": "h1", "seq": 11, "notice": {"code": "transcripts_off", "message": "x"}})
	_check(panel.get_node("Layout/Notices").visible, "notices show")

	# Sending to a session the sidecar doesn't have: refused, text kept.
	panel.set_draft("hello")
	panel.send()
	_check(panel.draft() == "", "sending clears the box")
	await _until(func() -> bool: return panel.status_text().begins_with("Couldn't send"), 5.0)
	_check(panel.status_text().begins_with("Couldn't send") and panel.draft() == "hello", "a refused message says so and comes back")

	var walk_at := player.global_position
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(walk_at) < 0.05, "no walking while chatting")
	_press("ui_cancel")
	await _frames(2)
	_check(not chat.is_open() and chat.prompt_visible() and player.controls_enabled, "Esc closes the chat")

	# The session ends while you're on its island, with the chat open.
	_press("interact")
	await _frames(2)
	store.apply({"type": "session.ended", "session": "h1", "seq": 12, "reason": "exited"})
	await _frames(2)
	_check(islands.island("h1") == null and not chat.is_open() and player.controls_enabled, "an ended session's island goes, and its chat closes")
	_check(player.global_position.distance_to(player.spawn_point) < 0.5, "whoever stood on it is back on the platform")
	_check(chat.bubble("h1") == null and not chat.prompt_visible(), "nothing of it is left")
	store.apply({"type": "session.snapshot", "session": _snapshot("h3")})
	_check(islands.island("h3").global_position.is_equal_approx(SessionIslands.slot_position(0)), "a new island takes the free spot")
	store.apply({"type": "session.ended", "session": "h2", "seq": 2, "reason": "exited"})
	store.apply({"type": "session.ended", "session": "h3", "seq": 2, "reason": "exited"})
	await _frames(2)


# With the fake provider: start a session from the post and chat with it.
func _live(world: Node3D, player: Player) -> void:
	var post: SessionPost = world.get_node("SpawnPlatform/SessionPost")
	var islands: SessionIslands = world.get_node("SessionIslands")
	var chat: ChatController = world.get_node("ChatController")
	var sidecar: SidecarClient = root.get_node("Sidecar")
	post.create(OS.get_user_data_dir())
	await _until(func() -> bool: return not world.store.sessions.is_empty(), 5.0)
	var id: String = world.store.sessions.keys()[0]
	await _frames(20)
	var orchestrator := islands.orchestrator(id)
	_check(orchestrator != null and post.status_text() == "", "live: the session is up, with its island")
	_check(player.global_position.distance_to(orchestrator.global_position) < 7.0, "live: and it takes you there")

	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _frames(5)
	_press("interact")
	await _frames(2)
	var panel := chat.panel()
	panel.set_draft("hello\nworld")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages().size() == 2 and panel.shown_messages()[1].contains("fake provider"), 8.0)
	_check(panel.shown_messages()[0] == "hello\nworld", "live: your message in the panel")
	_check(panel.shown_messages().size() == 2 and panel.shown_messages()[1].contains("> world"), "live: the reply streamed into the panel")
	_check(chat.bubble(id).shown_text().ends_with("(This is the fake provider.)"), "live: and into the bubble")
	_press("ui_cancel")
	await _frames(2)

	sidecar.send_command("session.end", {"session": id})
	await _until(func() -> bool: return islands.island(id) == null, 5.0)
	await _frames(2)
	_check(islands.island(id) == null and player.global_position.distance_to(player.spawn_point) < 0.5, "live: ending it sinks the island and brings you back")


func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
