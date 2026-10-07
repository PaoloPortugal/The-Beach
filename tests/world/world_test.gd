extends SceneTree
## Headless test for the M1 world: the island generator (W01) and jump
## assist (W03), then the world scene with
## real physics: the player lands on the spawn platform, walks, jumps and is
## put back when it falls in the sea; the sessions menu; islands for
## sessions (applied to the store by hand) rising and sinking (W04), each
## orchestrator's bubble, and
## walking up to chat in the chat panel (A01, C01, C02), both rendering
## Markdown (C03); subagents'
## placement, coming and going, and state markers (A02, A03, A04); the
## attention cue (A05).
##
##   godot --headless --path . --script res://tests/world/world_test.gd
##   ... -- --sidecar-dev-fake    also starts a session from the menu and
##                                chats with the fake provider, which
##                                spawns subagents

const ErrorWatch := preload("res://tests/error_watch.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_run()


func _run() -> void:
	_island()
	_jump_assist()
	_placement()
	await _scene()
	if not _failed and _errors.ok():
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


func _placement() -> void:
	_check(AgentPlacement.slots_in_ring(0) == 20 and AgentPlacement.ring_of(20) == Vector2i(1, 0), "placement: 20 on the first ring, then the next")
	var points: Array[Vector2] = []
	for slot in 80:
		points.append(AgentPlacement.slot_position(slot))
	var closest := INF
	for i in points.size():
		for j in i:
			closest = minf(closest, points[i].distance_to(points[j]))
	_check(closest > 2.0, "placement: slots at least 2 m apart (closest %.2f m)" % closest)
	_check(points.all(func(p: Vector2) -> bool: return p.length() > 9.0), "placement: all outside the chat zone")
	_check(AgentPlacement.slot_position(7) == AgentPlacement.slot_position(7), "placement: a slot is always in the same place")
	var far := AgentPlacement.slot_position(5000)
	_check(far.length() > 100.0 and is_finite(far.x), "placement: no maximum")


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

	await _menu(world, player)
	await _sessions(world, player)
	await _agents(world)
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		await _live(world, player)

	world.queue_free()
	await _frames(1)


func _menu(world: Node3D, player: Player) -> void:
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	await _frames(5)
	_check(menu.hint_visible() and not menu.is_open(), "no sessions yet: \"Press Tab for sessions\"")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.is_open() and not player.controls_enabled and not menu.hint_visible(), "Tab opens the sessions menu and pauses the player")
	_check(menu.entries()[0] == "+ New session…" and "Resume" in menu.entries(), "with New session and a list to resume")
	menu.choose("+ New session")
	await _frames(2)
	_check(menu.picker().visible, "New session opens the folder picker, in the game window")
	menu.picker().get_cancel_button().pressed.emit()
	await _frames(2)
	_check(menu.is_open() and not menu.picker().visible and not player.controls_enabled, "cancelling it goes back to the menu")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled and menu.hint_visible(), "Esc closes the menu")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_press("sessions_menu")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled, "and so does Tab")
	# Choosing a folder ends in the launcher's create().
	var sidecar: SidecarClient = root.get_node("Sidecar")
	await _until(func() -> bool: return sidecar.status == SidecarClient.Status.READY, 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "the sidecar is up")

	# The system's picker (none headless, so a stand-in that keeps its
	# callback): the menu waits with a note and Cancel.
	var answer := [Callable()]
	var pickers_shown := [0]
	menu.native_picker = true
	menu.show_native = func(_dir: String, callback: Callable) -> Error:
		answer[0] = callback
		return OK
	menu.native_picker_shown.connect(func(_dir: String) -> void: pickers_shown[0] += 1)
	var new_session := func() -> void:
		_press("sessions_menu")
		await _until(func() -> bool: return menu.is_open(), 2.0)
		menu.choose("+ New session")
		await _frames(2)
	await new_session.call()
	_check(pickers_shown[0] == 1 and menu.waiting_for_picker() and menu.is_open() and not menu.picker().visible, "system picker: the menu waits for it, with a note")
	answer[0].call(false, PackedStringArray(), 0)
	await _until(func() -> bool: return not menu.waiting_for_picker(), 2.0)
	_check(menu.is_open() and not menu.waiting_for_picker() and not player.controls_enabled, "system picker: cancelling it goes back to the menu")
	menu.choose("+ New session")
	await _frames(2)
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and not menu.waiting_for_picker() and player.controls_enabled, "system picker lost behind the game: Esc gives the controls back")
	answer[0].call(true, PackedStringArray([OS.get_user_data_dir()]), 0)
	await _settle()
	_check(not menu.launcher.busy() and menu.notice_text() == "" and not menu.is_open(), "and its late answer is ignored")
	await new_session.call()
	answer[0].call(true, PackedStringArray([OS.get_user_data_dir().path_join("no-such-folder")]), 0)
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(not menu.is_open() and player.controls_enabled, "system picker: choosing a folder closes the menu and gives the controls back")
	await _until(func() -> bool: return menu.notice_text().begins_with("Couldn't"), 5.0)
	_check(menu.notice_text().contains("does not exist") and not menu.launcher.busy(), "a missing folder is refused, and the notice says so")
	menu.native_picker = false

	# A session that's slow to start (its terminal may have closed unseen):
	# the menu can stop waiting for it.
	var started := [0]
	menu.launcher.session_started.connect(func(_id: String) -> void: started[0] += 1)
	menu.launcher.pending = "slow"
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.entries().has("✕ Stop waiting for the session starting"), "a start under way: the menu offers to stop waiting")
	menu.choose("✕ Stop waiting")
	await _frames(2)
	_check(not menu.launcher.busy() and menu.notice_text().begins_with("Stopped waiting") and not menu.entries().has("✕ Stop waiting for the session starting"), "stopping frees the launcher for another start")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)
	_check(started[0] == 0, "and nobody waits for it any more")


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
	_check(island.global_position.distance_to(islands.island("h2").global_position) > 90.0, "islands apart from each other")
	_check(Vector2(island.global_position.x, island.global_position.z).length() > 100.0, "and away from the platform")
	var clusters := islands.clusters
	var c1 := clusters.cluster_of("h1")
	_check(c1 != "" and clusters.cluster_of("h2") == c1 and clusters.cluster_name(c1) == "demo", "clusters: same folder, same cluster, named after it")
	_check(island.global_position.is_equal_approx(SessionClusters.cluster_position(0)), "clusters: the first island is in its cluster's middle")
	_check(orchestrator.session_id == "h1", "its orchestrator belongs to the session")
	_check(orchestrator.position.is_equal_approx(Vector3(0, island.height_at(0, 0), 0)), "and stands in the middle of it")
	_check(player.global_position.distance_to(at) < 0.1, "a session already running doesn't move the player")
	_check(island.position.y == 0.0 and not islands.is_rising("h1"), "and its island is just there, not rising")
	_check(islands.unvisited().is_empty() and not island.has_node("NewBeacon"), "nor marked as new")
	var bridges := islands.bridges
	var r1 := SessionIslands.region(island)
	var r2 := SessionIslands.region(islands.island("h2"))
	_check(bridges.bridge("platform", r1) != null and bridges.bridge(r1, r2) != null and bridges.links().size() == 2, "W06: bridges from the platform to the first island, and on to the next")
	var minimap: Minimap = world.minimap
	_check(minimap.shown_cluster() == c1 and minimap.map_rect().position == Vector2(Minimap.GAP, Minimap.GAP), "the minimap shows the nearest cluster, top left")
	var drawn := minimap.to_map(island.global_position)
	_check(Rect2(Vector2.ZERO, minimap.map_rect().size).has_point(drawn) and Rect2(Vector2.ZERO, minimap.map_rect().size).has_point(minimap.to_map(player.global_position)), "with its islands and you on it")
	await _big_map(world, player, islands)
	await _settle()
	_check(minimap.shown_cluster() == c1, "the minimap is back once the big map closes")
	await _quit(world, player)

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
	bubble.show_text("**Bold** and `code`")
	_check(bubble.shown_text() == "Bold and code", "the bubble renders Markdown")
	bubble.show_text("```py\nx = 1\n\ny = 2\n```")
	_check(bubble.shown_text() == "x = 1\ny = 2", "code shows in the bubble, without blank lines")
	bubble.show_text("word ".repeat(80))
	_check(bubble.shown_text().begins_with("…word") and bubble.shown_text().count("\n") == 3, "a long paragraph wraps and keeps 4 lines")
	_check(bubble.get_node("Viewport/Panel/Box/Clip/Text").size.x <= MessageBubble.MAX_WIDTH, "no wider than its limit")
	bubble.show_text("[url=https://x]click[/url]")
	_check(bubble.shown_text() == "[url=https://x]click[/url]", "the bubble shows markup as written")
	bubble.show_text("  \n")
	_check(not bubble.visible, "blank text hides it")
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 7, "agent": "main", "state": "working", "reason": null})

	world.teleport("h1")
	await _frames(20)
	_check(player.global_position.distance_to(orchestrator.global_position) < 7.0 and player.is_on_floor(), "teleport: in front of the orchestrator, on its island")
	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _until(func() -> bool: return chat.prompt_visible(), 2.0)
	_check(chat.prompt_visible(), "walking close shows \"Press E to chat\"")
	# The sidecar doesn't have h1, so fetching its history fails.
	await _until(func() -> bool: return not chat._history.has("h1"), 5.0)
	_check(not chat._history.has("h1"), "a failed history fetch is forgotten")
	chat.open(orchestrator)
	# Checked at once: the retry fails again within a frame or two.
	_check(chat._history.get("h1") == "asking", "opening the chat asks for the history again")
	chat.close()
	world.world_map.open()
	_press("interact")
	await _settle()
	_check(not chat.is_open(), "E doesn't open the chat while the big map is open")
	world.world_map.close()
	_press("interact")
	await _until(func() -> bool: return chat.is_open(), 2.0)
	var panel := chat.panel()
	_check(chat.is_open() and panel.visible and not player.controls_enabled, "E opens the chat panel and pauses the player")
	await _settle()
	_check(world.minimap.shown_cluster() == "", "the minimap hides while chatting")
	_press("minimap")
	await _settle()
	_check(not world.world_map.is_open() and chat.is_open(), "M doesn't open the big map while chatting")
	# The newest message is built at once, the older ones over a few frames.
	await _until(func() -> bool: return not panel.is_loading(), 5.0)
	_check(panel.shown_messages() == ["Hi there", "Looking at it.\ntwo\nthree\nfour\nfive"], "the panel shows the chat so far")
	_check(panel.status_text() == "Working…", "and what the orchestrator is doing")
	store.apply({"type": "message.completed", "session": "h1", "seq": 8, "message": "a1", "text": "Done. [url=https://x]click[/url]"})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 9, "agent": "main", "state": "idle", "reason": null})
	_check(panel.shown_messages()[1] == "Done. [url=https://x]click[/url]" and panel.status_text() == "", "it updates in place; text is shown as written, not as markup")
	store.apply({"type": "message.started", "session": "h1", "seq": 81, "message": "a2", "agent": "main", "role": "assistant"})
	store.apply({"type": "message.completed", "session": "h1", "seq": 82, "message": "a2", "text": "# Fixed\n\n**Done**, see [docs](https://example.com):\n\n```gd\nvar x := 1\n```"})
	_check(panel.shown_messages()[2] == "Fixed\n \nDone, see docs:\nvar x := 1", "Markdown is rendered in the panel")
	var view: MarkdownView = panel._rows["a2"]
	_check(view.get_child_count() == 2 and view.get_child(1).has_meta("code"), "a code block gets its own panel")
	(view.get_child(0) as RichTextLabel).meta_clicked.emit("0")
	_check(panel.link_asked() == "https://example.com", "a link asks before opening, showing its address")
	# A real key: the dialog has the focus, so a key goes to it.
	for pressed in [true, false]:
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.physical_keycode = KEY_ESCAPE
		esc.pressed = pressed
		Input.parse_input_event(esc)
	await _until(func() -> bool: return panel.link_asked().is_empty(), 2.0)
	await _settle()
	_check(chat.is_open() and panel.link_asked() == "", "Esc closes the question, not the chat")
	await _tool_log(store, panel)
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 10, "agent": "main", "state": "waiting", "reason": "permission"})
	_check(panel.status_text().contains("above or in the terminal"), "a permission wait points to the card and the terminal")
	store.apply({"type": "session.notice", "session": "h1", "seq": 11, "notice": {"code": "transcripts_off", "message": "x"}})
	_check(panel.get_node("Layout/Notices").visible, "notices show")
	await _card(store, panel)

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
	await _until(func() -> bool: return not chat.is_open(), 2.0)
	_check(not chat.is_open() and chat.prompt_visible() and player.controls_enabled, "Esc closes the chat")

	# The session ends while you're on its island, with the chat open.
	_press("interact")
	await _until(func() -> bool: return chat.is_open(), 2.0)
	# /resume in the terminal: the latest switch notice, and the resumed chat.
	store.apply({"type": "session.notice", "session": "h1", "seq": 20, "notice": {"code": "conversation_cleared", "message": "x"}})
	store.apply({"type": "session.notice", "session": "h1", "seq": 21, "notice": {"code": "conversation_resumed", "message": "x"}})
	var shown: String = panel.get_node("Layout/Notices").text
	_check(shown.contains("/resume") and not shown.contains("/clear") and shown.contains("transcripts"), "of the conversation switches, only the latest notice shows")
	store.apply({"type": "session.updated", "session": "h1", "seq": 22, "native_id": "n2"})
	store.replace_history("h1", [{"message": "r1", "agent": "main", "role": "user", "text": "earlier", "at": "2026-09-29T08:00:00Z"}])
	await _frames(1)
	_check(panel.shown_messages() == ["earlier"], "a replaced chat is laid out again")
	# A long chat: the newest messages at once, the older ones a few per frame.
	var long_chat: Array = []
	var expected: Array[String] = []
	for k in 150:
		long_chat.append({"message": "l%d" % k, "agent": "main", "role": "assistant", "text": "**%d**\n\n```\ncode %d\n```" % [k, k], "at": "2026-09-29T08:00:00Z"})
		expected.append("%d\ncode %d" % [k, k])
	# The live message that isn't in this history stays at the end.
	expected.append("earlier")
	store.replace_history("h1", long_chat)
	_check(panel.is_loading() and panel.shown_messages() == expected.slice(expected.size() - panel.shown_messages().size()), "a long chat shows its newest messages first")
	await _until(func() -> bool: return not panel.is_loading(), 20.0)
	_check(panel.shown_messages() == expected, "then all of it, in order")
	# /clear: the sidecar's history is empty, so the window clears at once.
	store.apply({"type": "session.updated", "session": "h1", "seq": 23, "native_id": "n3"})
	store.apply({"type": "session.notice", "session": "h1", "seq": 24, "notice": {"code": "conversation_cleared", "message": "x"}})
	store.replace_history("h1", [])
	await _frames(1)
	shown = panel.get_node("Layout/Notices").text
	_check(panel.shown_messages().is_empty() and shown.contains("(/clear)") and not shown.contains("(/resume)"), "after /clear the chat is empty, with its notice")
	await _attention(world)
	var on_island := player.global_position
	store.apply({"type": "session.ended", "session": "h1", "seq": 30, "reason": "exited"})
	# Waits hold weak references: a lambda can't capture a freed object.
	var orchestrator_ref: WeakRef = weakref(orchestrator)
	var island_ref: WeakRef = weakref(island)
	await _until(func() -> bool: return orchestrator_ref.get_ref() == null and not chat.is_open(), 2.0)
	_check(islands.island("h1") == null and not is_instance_valid(orchestrator) and not chat.is_open() and player.controls_enabled, "an ended session's orchestrator goes, and its chat closes")
	_check(chat.bubble("h1") == null and not chat.prompt_visible(), "nothing of it is left to talk to")
	await _frames(10)
	_check(island in islands.left_islands() and island.position.y == 0.0 and player.global_position.distance_to(on_island) < 0.5, "W04: its island stays while you're on it")
	# W06: on its bridge to the platform, far from the island, counts too.
	var to_platform := bridges.bridge("platform", r1)
	player.global_position = to_platform.from.lerp(to_platform.to, 0.5) + Vector3(0, 0.6, 0)
	await _frames(20)
	_check(to_platform.carries(player.global_position) and not islands._is_over(island, player.global_position), "W06: on its bridge, away from the island")
	_check(island in islands.left_islands() and island.position.y == 0.0 and is_instance_valid(to_platform) and bridges.has(r1), "the empty island and its bridges stay")
	player.global_position = on_island
	await _frames(10)
	# A session started meanwhile: its island rises, and you're taken there
	# once it's up.
	store.apply({"type": "session.created", "session": _snapshot("h3")})
	var h3 := islands.island("h3")
	_check(islands.is_rising("h3") and h3.position.y < -1.0, "a new session's island rises out of the sea")
	_check(not h3.global_position.is_equal_approx(SessionClusters.cluster_position(0)), "not in the spot of the island you're on")
	var beacon: AttentionBeacon = h3.get_node("NewBeacon")
	_check(Array(islands.unvisited()) == ["h3"] and beacon.is_on(), "a beacon stands over it until you've been there")
	var pointers: NewIslandPointers = world.pointers
	var to_h3 := h3.global_position - player.global_position
	player.rotation.y = atan2(-to_h3.x, -to_h3.z) # facing it
	await _frames(3)
	_check(pointers.shown().is_empty(), "facing it: no arrow, the beacon shows it")
	player.rotation.y += PI
	await _frames(3)
	await _settle() # the arrows are placed in _process
	var arrow := pointers.arrow("h3")
	var label: Label = arrow.get_node("Label") if arrow else null
	_check(Array(pointers.shown()) == ["h3"] and label.text.begins_with("demo · ") and label.text.ends_with(" m"), "behind you: an arrow at the edge, with its project and distance")
	var screen := root.get_visible_rect()
	_check(screen.has_point(arrow.position) and not screen.grow(-pointers.margin() - 1.0).has_point(arrow.position), "on the screen's edge")
	world.teleport("h3")
	await _frames(5)
	_check(player.global_position.distance_to(on_island) < 0.5, "going there waits for it to rise")
	await _until(func() -> bool: return not islands.is_rising("h3"), 6.0)
	await _frames(20)
	_check(h3.position.y == 0.0 and player.global_position.distance_to(islands.orchestrator("h3").global_position) < 7.0 and player.is_on_floor(), "then takes you there")
	_check(is_instance_valid(island) and island.position.y < 0.0, "you've left the empty island: it sinks")
	await _frames(3)
	_check(islands.unvisited().is_empty() and not beacon.is_on() and pointers.shown().is_empty(), "being there clears the beacon and the arrow")
	await _until(func() -> bool: return island_ref.get_ref() == null, 6.0)
	_check(island_ref.get_ref() == null, "and goes")
	store.apply({"type": "session.snapshot", "session": _snapshot("h5")})
	_check(islands.island("h5").global_position.is_equal_approx(SessionClusters.cluster_position(0)), "its spot is free again")
	# A session that ends as its island rises: back down at once (you're not
	# on it).
	store.apply({"type": "session.created", "session": _snapshot("h6")})
	await _frames(5)
	var h6 := islands.island("h6")
	store.apply({"type": "session.ended", "session": "h6", "seq": 2, "reason": "exited"})
	_check(not islands.is_rising("h6") and h6 in islands.left_islands() and islands.unvisited().is_empty(), "a session ending while its island rises")
	var h6_ref: WeakRef = weakref(h6)
	await _until(func() -> bool: return h6_ref.get_ref() == null, 6.0)
	_check(not is_instance_valid(h6), "sinks it from there")
	player.respawn()
	for id in ["h2", "h3", "h5"]:
		store.apply({"type": "session.ended", "session": id, "seq": 2, "reason": "exited"})
	await _frames(2)


# C04: the tool calls after a message, folded into one line. h1's chat is
# u1, a1, a2 so far.
func _tool_log(store: SessionStore, panel: ChatPanel) -> void:
	_check(not panel.tool_fold("a2").visible and not panel.tool_fold("").visible, "no tool calls, no fold")
	store.apply({"type": "tool.started", "session": "h1", "seq": 83, "tool_call": "t1", "agent": "main", "tool": "Bash", "summary": "Run: [b]rm[/b] x", "input": {"command": "rm [i]x[/i]"}})
	var fold := panel.tool_fold("a2")
	_check(fold.visible and fold.header_text() == "▸ 1 tool call (1 running)", "a call folds into one line after its message")
	store.apply({"type": "tool.finished", "session": "h1", "seq": 84, "tool_call": "t1", "status": "error", "summary": "Exit [color=red]code[/color] 1"})
	_check(fold.header_text() == "▸ 1 tool call (1 failed)", "and follows it as it ends")
	store.apply({"type": "tool.started", "session": "h1", "seq": 85, "tool_call": "t2", "agent": "main", "tool": "Agent", "summary": "Agent: look"})
	store.apply({"type": "tool.started", "session": "h1", "seq": 86, "tool_call": "t3", "agent": "s1", "tool": "Read", "summary": "Read a.gd", "within": "t2"})
	store.apply({"type": "tool.finished", "session": "h1", "seq": 87, "tool_call": "t3", "status": "denied"})
	_check(fold.header_text() == "▸ 2 tool calls (1 running, 1 failed)", "a subagent's call isn't counted at the top")
	fold.set_open(true)
	_check(fold.shown_calls() == ["failed Run: [b]rm[/b] x / Exit [color=red]code[/color] 1", "running Agent: look"], "opened: each call, how it went, its result; text as written")
	var inner := fold.inner("t2")
	_check(inner.visible and inner.header_text() == "▸ 1 tool call (1 denied)" and not fold.inner("t1").visible, "a subagent's calls fold inside its Agent call")
	inner.set_open(true)
	store.apply({"type": "tool.started", "session": "h1", "seq": 88, "tool_call": "t4", "agent": "s1", "tool": "Read", "summary": "Read b.gd", "within": "t2"})
	_check(inner.shown_calls() == ["denied Read a.gd", "running Read b.gd"], "and grow there live")
	fold.show_details("t1", true)
	_check(fold.details_text("t1").contains("Tool: Bash") and fold.details_text("t1").contains("\"command\": \"rm [i]x[/i]\""), "Details shows the input, as written")
	# Untrusted text never reaches a BBCode node (Security rules).
	_check(fold.find_children("*", "RichTextLabel", true, false).is_empty(), "the log's summary, result and details are plain Labels")
	fold.show_details("t1", false)
	_check(fold.details_text("t1") == "", "and hides it again")
	_check(panel.shown_messages().size() == 3, "the log doesn't count as messages")
	# Calls from the history land after their own message, laid out again.
	store.load_history("h1", [], [{"tool_call": "t0", "agent": "main", "tool": "Read", "summary": "Read NOTES.md", "status": "ok", "after": "u1"}])
	# Laid out again on the next frame, the oldest message (u1) last.
	await _until(func() -> bool: return not panel._rebuild_queued and not panel.is_loading() and panel.tool_fold("u1") != null, 5.0)
	_check(panel.tool_fold("u1").visible and panel.tool_fold("u1").header_text() == "▸ 1 tool call", "history's calls go after their message")
	_check(panel.tool_fold("a2").header_text() == "▸ 2 tool calls (1 running, 1 failed)", "and the live ones stay where they were")
	for t in ["t2", "t4"]:
		store.apply({"type": "tool.finished", "session": "h1", "seq": 89, "tool_call": t, "status": "ok"})


# A05: h1's orchestrator waits on a permission; h2's comes and goes.
func _attention(world: Node3D) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var attention: Attention = world.attention
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	# Never the developer's own settings file, nor another run's.
	attention.settings_path = "user://world_test_settings_%d.cfg" % OS.get_process_id()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(attention.settings_path))
	var focused := [true]
	var asked := [0]
	var chimes := [0]
	attention.is_focused = func() -> bool: return focused[0]
	attention.request_attention = func() -> void: asked[0] += 1
	attention.play_chime = func() -> void: chimes[0] += 1
	attention.sound_on = true
	var h1: AgentStateMarker = islands.orchestrator("h1").get_node("StateMarker")
	var h2: AgentStateMarker = islands.orchestrator("h2").get_node("StateMarker")
	var state := func(seq: int, to: String, reason: Variant = null) -> void:
		store.apply({"type": "agent.state_changed", "session": "h2", "seq": seq, "agent": "main", "state": to, "reason": reason})
	_check(attention.count_text() == "1 session waiting" and h1.beacon_on() and not h2.beacon_on(), "attention: a waiting agent has a beacon, and the corner counts it")
	state.call(3, "waiting", "permission")
	await _frames(2)
	_check(attention.count_text() == "2 sessions waiting" and h2.beacon_on(), "attention: counted by session")
	_check(asked[0] == 0 and chimes[0] == 0, "attention: in the game, no flash and no chime")
	var beacon: AttentionBeacon = h2.get_node("Beacon")
	_check(beacon.visible, "attention: the beacon shows")
	state.call(4, "working")
	await _frames(2)
	_check(attention.count_text() == "1 session waiting" and not h2.beacon_on(), "attention: it goes when the agent stops waiting")
	await _until(func() -> bool: return not beacon.visible, 3.0)
	_check(not beacon.visible, "attention: the beacon fades out")
	focused[0] = false
	state.call(5, "waiting", "question")
	_check(asked[0] == 1 and chimes[0] == 1, "attention: in another window, a new wait flashes the window and chimes")
	state.call(6, "waiting", "permission")
	_check(asked[0] == 1 and chimes[0] == 1, "attention: once per wait")
	var arriving := _snapshot("h5")
	arriving["agents"][0]["state"] = "waiting"
	arriving["agents"][0]["reason"] = "permission"
	store.apply({"type": "session.snapshot", "session": arriving})
	_check(attention.count_text() == "3 sessions waiting" and asked[0] == 2, "attention: a session that arrives waiting counts, and flashes")
	store.apply({"type": "session.ended", "session": "h5", "seq": 2, "reason": "exited"})
	_check(attention.count_text() == "2 sessions waiting", "attention: an ended session isn't counted")
	asked[0] = 1
	chimes[0] = 1
	menu.open()
	_check(menu.sound_toggle().visible and menu.sound_toggle().button_pressed, "attention: the sessions menu has the sound toggle, on")
	menu.sound_toggle().button_pressed = false
	menu.close()
	_check(not attention.sound_on, "attention: the toggle turns the chime off")
	state.call(7, "working")
	state.call(8, "waiting", "permission")
	_check(asked[0] == 2 and chimes[0] == 1, "attention: with the sound off, only the flash")
	var chime: AudioStream = load(Attention.CHIME) if ResourceLoader.exists(Attention.CHIME) else null
	_check(chime != null and chime.get_length() > 0.0, "attention: the chime's file is there and loads")
	var again := Attention.new()
	again.settings_path = attention.settings_path
	again.setup(SessionStore.new())
	_check(not again.sound_on, "attention: the sound setting is kept between runs")
	again.free()
	attention.sound_on = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(attention.settings_path))
	focused[0] = true
	state.call(9, "idle")
	await _frames(1)


# S05: closing the window with sessions h1 and h2 running asks first.
# W06's big map, with two sessions' islands (h1, h2) in the world: M opens
# it, it zooms and moves, a drag isn't a click, clicking h2's island takes
# you there, M and Esc close it.
func _big_map(world: Node3D, player: Player, islands: SessionIslands) -> void:
	var big: WorldMap = world.world_map
	_press("minimap")
	await _until(func() -> bool: return big.is_open(), 2.0)
	await _settle()
	_check(big.is_open() and not player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "M opens the big map, stops you and frees the mouse")
	_check(world.minimap.shown_cluster() == "", "the minimap hides while it's open")
	_check(big.to_map(player.global_position).is_equal_approx(big.map_rect().size / 2.0) and big.map_rect().size.x > 0.0, "it opens centred on you")
	var fit: Rect2 = world.minimap.fit_area()
	_check(is_equal_approx(big.zoom, clampf(minf(big.map_rect().size.x / fit.size.x, big.map_rect().size.y / fit.size.y), big.min_zoom(), WorldMap.MAX_ZOOM)), "at the minimap's scale")
	var at := Vector2(3, 4)
	var held := big.to_world(at)
	var zoom := big.zoom
	big.zoom_by(1.0, at)
	_check(is_equal_approx(big.zoom, zoom * WorldMap.ZOOM_STEP) and big.to_world(at).is_equal_approx(held), "the wheel zooms, keeping the point under the pointer still")
	big.zoom_by(100.0, at)
	_check(big.zoom == WorldMap.MAX_ZOOM, "up to its closest zoom")
	# Zooming out about the islands' middle.
	var middle := (islands.island("h1").global_position + islands.island("h2").global_position) / 2.0
	big.centre = Vector2(middle.x, middle.z)
	big.zoom_by(-100.0, big.map_rect().size / 2.0)
	var view := Rect2(Vector2.ZERO, big.map_rect().size)
	_check(big.zoom <= WorldMap.MIN_ZOOM and view.has_point(big.to_map(islands.island("h1").global_position)) and view.has_point(big.to_map(islands.island("h2").global_position)), "and out until every island fits")
	var centre := big.centre
	Input.action_press("move_right")
	await _settle()
	await _settle()
	Input.action_release("move_right")
	_check(big.centre.x > centre.x and is_equal_approx(big.centre.y, centre.y), "D moves the view east")
	# A drag: press, move past the click slop, let go.
	centre = big.centre
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(5, 5)))
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(15, 5)
	motion.relative = Vector2(10, 0)
	big._on_map_input(motion)
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(15, 5)))
	_check(big.is_open() and is_equal_approx(big.centre.x, centre.x - 10.0 / big.zoom), "dragging moves the map, and isn't a click")
	var target := islands.island("h2")
	big.centre = Vector2(target.global_position.x, target.global_position.z)
	var spot := big.to_map(target.global_position)
	_check(big.session_at(spot) == "h2" and big.session_at(spot + Vector2(1000, 1000)) == "", "it knows which session's island is under the pointer")
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, true, spot))
	big._on_map_input(_mouse_button(MOUSE_BUTTON_LEFT, false, spot + Vector2(2, 0)))
	await _frames(20)
	# (Headless, the mouse can't be captured: Input.mouse_mode stays visible.)
	_check(not big.is_open() and player.controls_enabled, "clicking an island closes the map, giving the controls back")
	_check(player.global_position.distance_to(islands.orchestrator("h2").global_position) < 7.0, "and takes you there")
	big.open()
	_press("ui_cancel")
	await _settle()
	_check(not big.is_open() and player.controls_enabled, "Esc closes it")
	big.open()
	_press("minimap")
	await _settle()
	_check(not big.is_open() and player.controls_enabled, "and so does M")


func _mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	return event


func _quit(world: Node3D, player: Player) -> void:
	var guard: QuitGuard = world.quit_guard
	var quits := [0]
	guard.quit = func() -> void: quits[0] += 1
	var mouse := Input.mouse_mode
	guard.request_quit()
	var text := guard.dialog().dialog_text
	_check(guard.is_asking() and quits[0] == 0, "quit: with sessions running, it asks first")
	_check(text.begins_with("2 sessions are still running") and text.count("demo") == 2 and text.contains("/exit"), "quit: listing them, and how to end them")
	_check(not player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "quit: the mouse is free to answer")
	world.store.apply({"type": "agent.state_changed", "session": "h1", "seq": 50, "agent": "main", "state": "working", "reason": null})
	_check(guard.dialog().dialog_text.contains("working"), "quit: the list follows what they're doing")
	world.store.apply({"type": "agent.state_changed", "session": "h1", "seq": 51, "agent": "main", "state": "idle", "reason": null})
	guard.dialog().get_cancel_button().pressed.emit()
	await _frames(1)
	_check(not guard.is_asking() and quits[0] == 0 and player.controls_enabled and Input.mouse_mode == mouse, "quit: back to the game, as it was")
	guard.request_quit()
	guard.dialog().get_ok_button().pressed.emit()
	_check(quits[0] == 1, "quit: Quit quits")
	var empty := QuitGuard.new()
	empty.store = SessionStore.new()
	empty.quit = func() -> void: quits[0] += 10
	empty.request_quit()
	_check(quits[0] == 11, "quit: with no session running, it just quits")
	empty.free()


# C05: the card for permission prompts and questions, on session h1 (which
# the sidecar doesn't have, so its answers are refused).
func _card(store: SessionStore, panel: ChatPanel) -> void:
	var card := panel.pending_card()
	_check(not card.visible, "card: hidden with nothing pending")
	store.apply({"type": "permission.requested", "session": "h1", "seq": 12, "permission": {
		"permission": "p1", "agent": "main", "tool": "Bash", "summary": "Run: [b]rm[/b] x", "input": {"command": "rm x"}}})
	var sub := _agent("s1", "main", "working")
	sub["name"] = "Explore"
	store.apply({"type": "agent.spawned", "session": "h1", "seq": 13, "agent": sub})
	store.apply({"type": "question.asked", "session": "h1", "seq": 14, "question": {"question": "q1", "agent": "s1", "items": [
		{"text": "Which fruit?", "header": "Fruit", "multi_select": false, "options": [{"label": "Apple", "description": "Crisp"}, {"label": "Banana"}]},
		{"text": "What goes with it?", "multi_select": true, "options": [{"label": "Honey"}, {"label": "Nuts"}]},
	]}})
	_check(card.visible and card.header_text() == "The orchestrator asks to use Bash:" and card.count_text() == "1 of 2 waiting", "card: the oldest request first, with how many wait")
	var buttons := card.find_children("*", "Button", true, false)
	_check(buttons.map(func(b: Button) -> String: return b.text) == ["Details", "Yes", "No", "Send"], "card: Yes and No, one per line, without options")
	var yes: Button = buttons[1]
	_check(yes.focus_mode == Control.FOCUS_NONE, "card: no key can press Yes")
	_check(card.find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Run: [b]rm[/b] x"), "card: the summary is shown as written")
	_check(not _note(card).editable and _button(card, "Send").disabled, "card: the note and Send are locked until No")
	_click(card, "No")
	_check(card.denying() and _note(card).editable and not _button(card, "Send").disabled and card.error_text() == "", "card: No unlocks the note and Send, and answers nothing")
	card.set_note("not that one")
	_click(card, "Yes")
	await _until(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer") and card.current()["kind"] == "permission", "card: a refused answer says so and stays")
	_check(not card.denying() and not _note(card).editable and _note(card).text == "not that one", "card: Yes locks the note again, keeping it")
	_click(card, "No")
	_check(_note(card).text == "not that one", "card: No again, the note is still there")
	_click(card, "Send")
	await _until(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer"), "card: Send denies")
	store.apply({"type": "permission.resolved", "session": "h1", "seq": 15, "permission": "p1", "decision": "allow", "by": "external"})
	_check(card.header_text() == "Subagent Explore asks:" and card.count_text() == "" and card.error_text() == "", "card: answered in the terminal, the next one shows, naming its agent")
	_check(card.step() == 0, "card: questions start at the first item")
	card.next()
	_check(card.step() == 0, "card: no Next before an answer")
	_click(card, "Banana")
	_check(card.step() == 1, "card: a single choice moves straight on")
	card.choose("Honey")
	card.choose("Nuts")
	card.choose("Honey")
	_check(card.step() == 1, "card: checkboxes don't move on")
	_click(card, "Back")
	card.set_other("Mango")
	card.next()
	_check(card.step() == 1, "card: Back, your own words, then Next")
	panel.close()
	panel.open("h1")
	_check(panel.pending_card().step() == 1, "card: progress survives closing the chat")
	card.send_answers()
	await _until(func() -> bool: return card.error_text().begins_with("Couldn't answer"), 5.0)
	_check(card.error_text().begins_with("Couldn't answer"), "card: Send on the last item")
	store.apply({"type": "question.resolved", "session": "h1", "seq": 16, "question": "q1", "by": "external"})
	_check(not card.visible, "card: hidden again when nothing waits")
	_modes_and_plans(store, panel)


# Records the commands sent and refuses each, so a card can be clicked again.
class _Recorder extends SidecarClient:
	var sent := []

	func send_command(type: String, fields: Dictionary = {}, on_reply := Callable()) -> String:
		sent.append([type, fields])
		if on_reply.is_valid():
			on_reply.call({"type": "error", "message": "recorded"})
		return "r%d" % sent.size()


# C06 and C07: the mode in the header, a plan in the chat and on the card;
# C05: a permission's other ways to allow (its options).
func _modes_and_plans(store: SessionStore, panel: ChatPanel) -> void:
	var card := panel.pending_card()
	_check(panel.mode_text() == "", "modes: no mode shown without permission_modes")
	var snap := store.session("h1").duplicate(true)
	snap["seq"] = 17
	snap["capabilities"] = {"permission_modes": {}, "plans": {}}
	snap["mode"] = null
	store.apply({"type": "session.snapshot", "session": snap})
	_check(panel.mode_text() == "", "modes: none shown while it isn't known")
	store.apply({"type": "session.updated", "session": "h1", "seq": 18, "mode": "default"})
	_check(panel.mode_text() == "Mode: Manual", "modes: the header shows the mode in our words")
	store.apply({"type": "session.updated", "session": "h1", "seq": 19, "mode": "acceptEdits"})
	_check(panel.mode_text() == "Mode: Accept edits", "modes: and follows it")
	store.apply({"type": "session.updated", "session": "h1", "seq": 20, "mode": "someNewMode"})
	_check(panel.mode_text() == "Mode: someNewMode", "modes: an unknown mode shows as its id")
	store.apply({"type": "session.updated", "session": "h1", "seq": 21, "mode": "plan"})

	var recorder := _Recorder.new()
	var real := card.sidecar
	card.sidecar = recorder
	store.apply({"type": "message.started", "session": "h1", "seq": 22, "message": "plan1", "agent": "main", "role": "assistant", "kind": "plan"})
	store.apply({"type": "message.completed", "session": "h1", "seq": 23, "message": "plan1", "text": "# The plan\n\n1. Do [b]this[/b]"})
	var plan_shown: String = panel.shown_messages().back()
	_check(plan_shown.begins_with("The plan\n") and plan_shown.contains("Do [b]this[/b]"),"plans: the plan is a message, rendered as Markdown")
	var line: HBoxContainer = panel._messages.get_children().back().get_child(0)
	_check(line.get_child_count() == 1 and line.get_child(0).find_children("*", "Label", true, false).any(func(l: Label) -> bool: return l.text == "Plan"), "plans: full width, marked as a plan")
	store.apply({"type": "plan.asked", "session": "h1", "seq": 24, "plan": {"plan": "x1", "agent": "main", "text": "# The plan", "modes": ["auto", "default"]}})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 25, "agent": "main", "state": "waiting", "reason": "plan"})
	_check(panel.status_text().contains("approve the plan") and panel.status_text().contains("terminal"), "plans: the status points to the card and the terminal")
	_check(card.visible and card.header_text() == "The orchestrator has a plan for you to approve:", "plans: the card asks")
	var texts: Array = card.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	_check(texts == ["Yes, and use auto mode", "Yes, manually approve edits", "No, keep planning", "Send"], "plans: its choices in the provider's order")
	_check(card.find_children("*", "Button", true, false).all(func(b: Button) -> bool: return b.focus_mode == Control.FOCUS_NONE), "plans: no key can press them")
	_click(card, "Yes, and use auto mode")
	_check(recorder.sent.back() == ["plan.answer", {"session": "h1", "plan": "x1", "approve": true, "mode": "auto"}], "plans: approving sends the mode")
	_check(not _note(card).editable and _button(card, "Send").disabled, "plans: the note is locked until \"No, keep planning\"")
	_click(card, "No, keep planning")
	_check(card.denying() and _note(card).editable and not _button(card, "Send").disabled, "plans: \"No, keep planning\" unlocks it")
	_click(card, "Send")
	_check(recorder.sent.back() == ["plan.answer", {"session": "h1", "plan": "x1", "approve": false}], "plans: Send without a note")
	card.set_note("  smaller steps ")
	_click(card, "Send")
	_check(recorder.sent.back() == ["plan.answer", {"session": "h1", "plan": "x1", "approve": false, "note": "smaller steps"}], "plans: Send with the note")
	card.approve_plan("acceptEdits")
	_check(recorder.sent.size() == 3, "plans: a mode the plan doesn't offer isn't sent")
	store.apply({"type": "plan.resolved", "session": "h1", "seq": 26, "plan": "x1", "decision": "rejected", "by": "app"})
	store.apply({"type": "plan.asked", "session": "h1", "seq": 27, "plan": {"plan": "x2", "agent": "main", "text": "# Again", "modes": ["acceptEdits", "default"]}})
	texts = card.find_children("*", "Button", true, false).map(func(b: Button) -> String: return b.text)
	_check(texts[0] == "Yes, auto-accept edits" and card.error_text() == "" and not card.denying(), "plans: without auto, the terminal's other words; a fresh card")
	store.apply({"type": "plan.resolved", "session": "h1", "seq": 28, "plan": "x2", "decision": "approved", "by": "external"})
	_check(not card.visible, "plans: answered in the terminal, the card goes")
	_check(panel.shown_messages().back().begins_with("The plan"), "plans: the plan stays in the chat")

	var dont_ask := "Yes, and don't ask again for: npm test [b]*[/b]"
	store.apply({"type": "permission.requested", "session": "h1", "seq": 29, "permission": {
		"permission": "p5", "agent": "main", "tool": "Bash", "summary": "Run: npm test", "options": [
			{"option": "suggested", "label": dont_ask}, {"option": "auto", "label": "Yes, and switch to auto mode"}]}})
	var choices := card.find_children("*", "Button", true, false)
	_check(choices.map(func(b: Button) -> String: return b.text) == ["Yes", dont_ask, "Yes, and switch to auto mode", "No", "Send"], "options: one per line between Yes and No, in the provider's order and words, as written")
	_check(choices.all(func(b: Button) -> bool: return b.focus_mode == Control.FOCUS_NONE), "options: by click only")
	var option_line: Button = choices[1]
	_check(option_line.autowrap_mode != TextServer.AUTOWRAP_OFF and option_line.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "options: a long label wraps across the card")
	_click(card, "Yes, and switch to auto mode")
	_check(recorder.sent.back() == ["permission.respond", {"session": "h1", "permission": "p5", "decision": "allow", "option": "auto"}], "options: one sends its id")
	_click(card, dont_ask)
	_check(recorder.sent.back() == ["permission.respond", {"session": "h1", "permission": "p5", "decision": "allow", "option": "suggested"}], "options: each its own")
	_click(card, "No")
	card.set_note("never sent")
	_click(card, "Yes")
	_check(recorder.sent.back() == ["permission.respond", {"session": "h1", "permission": "p5", "decision": "allow"}], "options: plain Yes sends none, and never the note")
	card.respond("allow", "default")
	_check(recorder.sent.size() == 6, "options: one the prompt doesn't offer isn't sent")
	store.apply({"type": "permission.resolved", "session": "h1", "seq": 30, "permission": "p5", "decision": "allow", "by": "app"})
	store.apply({"type": "agent.state_changed", "session": "h1", "seq": 31, "agent": "main", "state": "waiting", "reason": "permission"})
	card.sidecar = real
	recorder.free()


func _button(card: PendingCard, text: String) -> BaseButton:
	for b: BaseButton in card.find_children("*", "BaseButton", true, false):
		if b.text == text:
			return b
	return null


func _note(card: PendingCard) -> LineEdit:
	return card.find_children("*", "LineEdit", true, false)[0]


# Clicks a card's button by its text, through its signal like a real click
# (the card lays itself out again from inside it).
func _click(card: PendingCard, text: String) -> void:
	for b: BaseButton in card.find_children("*", "BaseButton", true, false):
		if b.text == text:
			if b.toggle_mode:
				b.button_pressed = not b.button_pressed
			b.pressed.emit()
			return
	_check(false, "card: no button \"%s\"" % text)


func _agent(id: String, parent: String, state: String) -> Dictionary:
	return {"agent": id, "role": "subagent", "parent": parent, "name": "Explore", "task": "t", "state": state, "reason": null}


# Subagents applied to the store by hand.
func _agents(world: Node3D) -> void:
	var store: SessionStore = world.store
	var islands: SessionIslands = world.get_node("SessionIslands")
	var snap := _snapshot("h4")
	snap["agents"][0]["state"] = "working"
	snap["agents"].append(_agent("old", "main", "done"))
	snap["agents"].append(_agent("s0", "main", "working"))
	store.apply({"type": "session.snapshot", "session": snap})
	await _frames(2)
	_check(store.activity("h4") == "working", "activity: working")
	var agents := islands.agents("h4")
	var island := islands.island("h4")
	var orchestrator := islands.orchestrator("h4")
	agents.error_linger = 0.5
	_check(orchestrator.get_node("StateMarker").shown() == "working", "agents: the orchestrator's marker shows it working")
	_check(agents.subagent("old") == null and agents.subagent("s0") != null, "agents: a finished one isn't shown, a working one is")
	_check(agents.subagent("s0").shown_state() == "working", "agents: with its marker")

	store.apply({"type": "agent.spawned", "session": "h4", "seq": 2, "agent": _agent("s1", "main", "working")})
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 3, "agent": _agent("s2", "s1", "working")})
	await _frames(20)
	var nodes: Array = ["s0", "s1", "s2"].map(func(a: String) -> Subagent: return agents.subagent(a))
	_check(nodes.all(func(n: Subagent) -> bool: return n != null) and agents.subagent_count() == 3, "agents: a spawned one appears")
	var slots := {}
	var placed := true
	for n: Subagent in nodes:
		slots[n.slot] = true
		var p := n.position
		var inward := Vector3(-p.x, 0, -p.z).normalized()
		var forward := n.global_basis.z
		placed = placed and Vector2(p.x, p.z).length() > 9.0 and absf(p.y - island.height_at(p.x, p.z)) < 0.6
		placed = placed and forward.dot(inward) > 0.9 and n.worker_position().distance_to(n.global_position) < 0.01
	_check(slots.size() == 3, "agents: each at its own slot")
	_check(placed, "agents: around the orchestrator, on the sand, facing it")

	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 4, "agent": "s1", "state": "waiting", "reason": "permission"})
	_check(agents.subagent("s1").shown_state() == "waiting", "agents: waiting on you shows the \"!\"")

	# Done: walks its report to its parent (s1, still at its PC), then goes.
	var s1 := agents.subagent("s1")
	var s2 := agents.subagent("s2")
	var s2_slot := s2.slot
	var start := s2.worker_position().distance_to(s1.worker_position())
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 5, "agent": "s2", "state": "done", "reason": null})
	_check(s2.is_leaving() and s2.get_node("Worker/Paper").visible and s2.shown_state() == "", "agents: a done one gets up with its paper")
	await _frames(15)
	_check(s2.worker_position().distance_to(s1.worker_position()) < start - 0.5, "agents: and walks to whoever called it")
	await _until(func() -> bool: return agents.subagent("s2") == null, 3.0)
	_check(agents.subagent("s2") == null and agents.subagent_count() == 2, "agents: and is gone once there (not only after giving up)")
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 6, "agent": _agent("s3", "main", "working")})
	_check(agents.subagent("s3").slot == s2_slot, "agents: a freed slot is reused")

	# Resumed while walking back: back at its PC.
	var s3 := agents.subagent("s3")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 7, "agent": "s3", "state": "done", "reason": null})
	await _frames(10)
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 8, "agent": "s3", "state": "working", "reason": null})
	await _frames(30)
	_check(agents.subagent("s3") == s3 and not s3.is_leaving() and s3.worker_position().distance_to(s3.global_position) < 0.01, "agents: resumed on the way back, it returns to its PC")

	# Error: stays in red for a while, then goes; resumed later, it comes back to its slot.
	var s1_slot := s1.slot
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 9, "agent": "s1", "state": "error", "reason": "interrupted"})
	_check(s1.shown_state() == "error", "agents: an error shows the \"×\"")
	await _frames(10)
	_check(agents.subagent("s1") == s1, "agents: and it stays a while")
	await _until(func() -> bool: return agents.subagent("s1") == null, 5.0)
	_check(agents.subagent("s1") == null, "agents: then goes")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 10, "agent": "s1", "state": "working", "reason": null})
	_check(agents.subagent("s1") != null and agents.subagent("s1").slot == s1_slot, "agents: resumed later, it comes back to its slot")

	# Walks to the orchestrator, 10+ m away, in about 4 s: every one of
	# them gets there (a walk that never quite arrives gives up only
	# after 20 s).
	for a in ["s0", "s1", "s3"]:
		store.apply({"type": "agent.state_changed", "session": "h4", "seq": 11, "agent": a, "state": "done", "reason": null})
	await _until(func() -> bool: return agents.subagent_count() == 0, 8.0)
	_check(agents.subagent_count() == 0, "agents: all walk to the orchestrator and go (%d left)" % agents.subagent_count())

	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 12, "agent": "main", "state": "idle", "reason": null})
	_check(store.activity("h4") == "idle", "activity: idle once everyone is done")
	store.apply({"type": "agent.spawned", "session": "h4", "seq": 20, "agent": _agent("s9", "main", "working")})
	_check(store.activity("h4") == "working", "activity: an idle orchestrator waiting on a subagent counts as working")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 21, "agent": "s9", "state": "waiting", "reason": "permission"})
	_check(store.activity("h4") == "waiting" and SessionsMenu.state_text(store.activity("h4")) == "waiting for you", "activity: a subagent waiting on you")
	store.apply({"type": "agent.state_changed", "session": "h4", "seq": 22, "agent": "s9", "state": "done", "reason": null})
	await _until(func() -> bool: return agents.subagent_count() == 0, 8.0)
	_check(orchestrator.get_node("StateMarker").shown() == "", "agents: an idle orchestrator shows no marker")
	store.apply({"type": "session.ended", "session": "h4", "seq": 13, "reason": "exited"})
	await _frames(2)


# With the fake provider: start a session from the menu and chat with it,
# then resume a stored one.
func _live(world: Node3D, player: Player) -> void:
	var menu: SessionsMenu = world.get_node("SessionsMenu")
	var islands: SessionIslands = world.get_node("SessionIslands")
	var chat: ChatController = world.get_node("ChatController")
	var sidecar: SidecarClient = root.get_node("Sidecar")
	# The real way in: Tab, New session, the picker's own "select" button.
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	menu.choose("+ New session")
	await _frames(2)
	menu.picker().current_dir = OS.get_user_data_dir()
	await _frames(2)
	menu.picker().get_ok_button().pressed.emit()
	await _frames(2)
	_check(not menu.is_open() and not menu.picker().visible, "live: choosing a folder closes the picker and the menu")
	_check(player.controls_enabled, "live: and gives the controls back (headless has no mouse to check)")
	await _until(func() -> bool: return not world.store.sessions.is_empty(), 5.0)
	var id: String = world.store.sessions.keys()[0]
	await _frames(20)
	var orchestrator := islands.orchestrator(id)
	_check(orchestrator != null and menu.notice_text() == "", "live: the session is up, with its island")
	_check(islands.is_rising(id), "live: rising")
	await _until(func() -> bool: return player.global_position.distance_to(orchestrator.global_position) < 7.0, 6.0)
	_check(player.global_position.distance_to(orchestrator.global_position) < 7.0, "live: and once it's up, it takes you there")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.entries()[3].begins_with("New session   ·"), "live: a new session is listed as \"New session\"")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)

	await _until(func() -> bool: return chat.history_loaded(id), 5.0)
	_check(chat.history_loaded(id), "live: its history is loaded")
	player.global_position = orchestrator.global_position + Vector3(0, 0.1, 2.0)
	await _until(func() -> bool: return chat.prompt_visible(), 2.0)
	_press("interact")
	await _until(func() -> bool: return chat.is_open(), 2.0)
	var panel := chat.panel()
	panel.set_draft("hello\nworld")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages().size() == 2 and panel.shown_messages()[1].contains("fake provider"), 8.0)
	_check(panel.shown_messages()[0] == "hello\nworld", "live: your message in the panel")
	_check(panel.shown_messages().size() == 2 and panel.shown_messages()[1].contains("> world"), "live: the reply streamed into the panel")
	_check(chat.bubble(id).shown_text().ends_with("(This is the fake provider.)"), "live: and into the bubble")
	_check(world.store.sessions[id].get("title") == "hello", "live: the first message's first line names the session")
	panel.set_draft("rename Tidy the notes")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Renamed"), 8.0)
	_check(world.store.sessions[id].get("title") == "Tidy the notes", "live: renaming it renames it")

	# Subagents: the fake provider spawns them, they work and walk back.
	var agents := islands.agents(id)
	panel.set_draft("agents 3")
	panel.send()
	await _until(func() -> bool: return agents.subagent_count() == 3, 8.0)
	_check(agents.subagent_count() == 3, "live: three subagents appear")
	await _until(func() -> bool: return agents.subagent_count() == 0, 18.0)
	_check(agents.subagent_count() == 0, "live: and all walk back and go when done")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("reported back"), 8.0)
	_check(panel.shown_messages()[-1].contains("reported back"), "live: the orchestrator sums up")
	var order: Array = world.store.session(id)["message_order"]
	var split := panel.tool_fold(order[-2])
	split.set_open(true)
	_check(split.shown_calls().size() == 3 and split.shown_calls().all(func(c: String) -> bool: return c.begins_with("ok Agent:")), "live: an Agent call per subagent in the log")
	var inside := split.inner(world.store.tool_tree(id)["after"][order[-2]][0])
	_check(inside.header_text() == "▸ 3 tool calls", "live: each holding its subagent's calls")

	# C04: a turn with tools, one failing.
	panel.set_draft("tools")
	panel.send()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("One test failed"), 8.0)
	order = world.store.session(id)["message_order"]
	_check(panel.tool_fold(order[-2]).header_text() == "▸ 3 tool calls (1 failed)", "live: the tools turn's calls fold after its first message")

	# C05: answering a permission prompt and a question on the card.
	var card := panel.pending_card()
	panel.set_draft("permission")
	panel.send()
	await _until(func() -> bool: return card.visible, 8.0)
	_check(card.visible and card.header_text() == "The orchestrator asks to use Bash:", "live: a permission prompt on the card")
	card.respond("allow")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Installed"), 8.0)
	_check(not card.visible and panel.shown_messages()[-1].contains("Installed"), "live: allowed from the card")
	panel.set_draft("question")
	panel.send()
	await _until(func() -> bool: return card.visible, 8.0)
	card.choose("Banana")
	card.choose("Honey")
	card.choose("Nuts")
	card.send_answers()
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("picked"), 8.0)
	_check(not card.visible and panel.shown_messages()[-1].contains("Banana; Honey, Nuts"), "live: a two-item question answered from the card")

	# C06 and C07: the mode in the header, a switch on a prompt (one of its
	# options, C05), a plan.
	_check(panel.mode_text() == "Mode: Auto", "live: the session's mode in the header")
	panel.set_draft("mode")
	panel.send()
	await _until(func() -> bool: return panel.mode_text() == "Mode: Manual", 8.0)
	_check(panel.mode_text() == "Mode: Manual", "live: a mode switch shows")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Now in"), 8.0)
	panel.set_draft("permission")
	panel.send()
	await _until(func() -> bool: return card.visible, 8.0)
	_check(_button(card, "Yes, and don't ask again for: npm install") != null, "live: the prompt's options on the card")
	_click(card, "Yes, and switch to auto mode")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("Installed"), 8.0)
	_check(panel.mode_text() == "Mode: Auto" and not card.visible, "live: allowed and switched to auto from the card")
	panel.set_draft("plan")
	panel.send()
	# The plan and the orchestrator's wait are two events.
	await _until(func() -> bool: return card.visible and panel.status_text().contains("approve the plan"), 8.0)
	_check(panel.mode_text() == "Mode: Plan" and card.header_text().contains("plan"), "live: a plan on the card, in plan mode")
	_check(panel.status_text().contains("approve the plan"), "live: the status says so")
	var plan_rows: Array = world.store.messages(id).filter(func(m: Dictionary) -> bool: return m.get("kind") == "plan")
	_check(plan_rows.size() == 1 and panel.shown_messages().any(func(t: String) -> bool: return t.begins_with("Add a dark theme")), "live: the plan is in the chat")
	_click(card, "No, keep planning")
	card.set_note("a high-contrast option")
	_click(card, "Send")
	await _until(func() -> bool: return world.store.messages(id).filter(func(m: Dictionary) -> bool: return m.get("kind") == "plan").size() == 2 and card.visible, 10.0)
	_check(card.visible and panel.shown_messages().any(func(t: String) -> bool: return t.contains("a high-contrast option")), "live: sent back with a note, a revised plan comes")
	_click(card, "Yes, manually approve edits")
	await _until(func() -> bool: return panel.shown_messages()[-1].contains("approved"), 8.0)
	_check(not card.visible and panel.mode_text() == "Mode: Manual", "live: approved from the card, in the chosen mode")
	_press("ui_cancel")
	await _until(func() -> bool: return not chat.is_open(), 2.0)

	# The open menu follows a rename.
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open(), 2.0)
	_check(menu.entries()[3].begins_with("Tidy the notes   ·"), "live: the menu shows its name")
	sidecar.send_command("message.send", {"session": id, "text": "rename Notes"})
	await _until(func() -> bool: return menu.entries()[3].begins_with("Notes   ·"), 5.0)
	_check(menu.entries()[3].begins_with("Notes   ·"), "live: and follows a rename while open")
	_press("ui_cancel")
	await _until(func() -> bool: return not menu.is_open(), 2.0)

	var ended := islands.island(id)
	sidecar.send_command("session.end", {"session": id})
	await _until(func() -> bool: return islands.island(id) == null, 5.0)
	await _frames(2)
	_check(islands.island(id) == null and not is_instance_valid(orchestrator) and is_instance_valid(ended) and ended.position.y == 0.0, "live: ending it takes its orchestrator; the island stays while you're on it")
	player.respawn()
	var ended_ref: WeakRef = weakref(ended)
	await _until(func() -> bool: return ended_ref.get_ref() == null, 6.0)
	_check(not is_instance_valid(ended), "live: and sinks once you've left")

	# S04: resume a stored session from the menu.
	_press("sessions_menu")
	await _until(func() -> bool: return menu.is_open() and menu.entries().any(func(e: String) -> bool: return e.begins_with("Add a save system")), 5.0)
	var listed := menu.entries()
	_check(listed.size() == 5 and listed[2].begins_with("Fix the player") and listed[3].begins_with("Add a save system") and listed[3].contains("my-game") and listed[3].ends_with("1 d ago"), "live: stored sessions listed newest first, with project and age")
	menu.search("SAVE")
	_check(menu.entries() == ["+ New session…", "Resume", listed[3]], "live: the search filters them")
	menu.choose("Add a save system")
	_check(not menu.is_open() and menu.notice_text() == "Starting…", "live: choosing one resumes it")
	await _until(func() -> bool: return not world.store.sessions.is_empty(), 5.0)
	var resumed: String = world.store.sessions.keys()[0]
	await _until(func() -> bool: return chat.history_loaded(resumed), 5.0)
	await _until(func() -> bool: return islands.orchestrator(resumed) != null and player.global_position.distance_to(islands.orchestrator(resumed).global_position) < 7.0, 6.0)
	_check(islands.orchestrator(resumed) != null and player.global_position.distance_to(islands.orchestrator(resumed).global_position) < 7.0, "live: its island comes back and you're taken there")
	_check(chat.bubble(resumed).shown_text() == "Resumed Add a save system.", "live: with its chat so far")
	_press("sessions_menu")
	await _until(func() -> bool: return menu.entries().size() == 7, 5.0)
	var now := menu.entries()
	_check(now[1] == "Running" and now[2].begins_with("▸ ") and now[3].begins_with("Add a save system") and not now.slice(4).any(func(e: String) -> bool: return e.begins_with("Add a save")), "live: now under Running, in its cluster, not Resume")
	player.respawn()
	menu.choose("Add a save system")
	await _frames(5)
	_check(not menu.is_open() and player.global_position.distance_to(islands.orchestrator(resumed).global_position) < 7.0, "live: a running one takes you to its island")
	sidecar.send_command("session.end", {"session": resumed})
	await _until(func() -> bool: return islands.island(resumed) == null, 5.0)


func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


# For checks that something did NOT happen: a whole main-loop iteration, so
# input events and deferred calls have been handled. Physics frames don't
# promise that: a slow iteration runs several physics steps in a row.
func _settle() -> void:
	for i in 2:
		await process_frame


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
