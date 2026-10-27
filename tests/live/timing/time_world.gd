extends SceneTree
# Frame times in the real world scene (main menu up) as sessions' islands
# arrive. Run with -- --sidecar-dev-fake. Never the user's files.

const SNAP := {
	"seq": 1, "provider": "fake", "native_id": null, "origin": "app",
	"project": {"path": "/p", "name": "demo"}, "title": null, "started_at": "2026-09-30T10:00:00Z",
	"capabilities": {}, "extensions": [], "permissions": [], "notices": [],
	"agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
}


func _initialize() -> void:
	IslandMemory.file = "user://timing-islands.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IslandMemory.file))
	var world: Node3D = load("res://world/world.tscn").instantiate()
	var settings_file := "user://timing_settings.cfg"
	world.settings.path = settings_file
	world.attention.settings_path = settings_file
	world.set_outside_sessions = func(_on: bool) -> void: pass
	root.add_child(world)
	_run.call_deferred(world)


func _run(world: Node3D) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true) # TIMING
	for i in 120:
		await process_frame
	var islands: SessionIslands = world.get_node("SessionIslands")
	var ph := {} # TIMING
	process_frame.connect(func() -> void: ph["process"] = Time.get_ticks_usec()) # TIMING
	RenderingServer.frame_pre_draw.connect(func() -> void: ph["pre_draw"] = Time.get_ticks_usec()) # TIMING
	RenderingServer.frame_post_draw.connect(func() -> void: ph["post_draw"] = Time.get_ticks_usec()) # TIMING
	physics_frame.connect(func() -> void: ph["physics"] = Time.get_ticks_usec()) # TIMING
	var frames: Array[float] = []
	var marks := {}
	islands.island_added.connect(func(_id: String, i: Island, _o: Orchestrator) -> void:
		i.built.connect(func() -> void: marks[frames.size()] = "built %s" % Biome.NAMES[i.biome]))
	var last := Time.get_ticks_usec()
	var biome_order := [Biome.Kind.BEACH, Biome.Kind.FOREST, Biome.Kind.MOUNTAIN, Biome.Kind.SNOWY, Biome.Kind.DESERT, Biome.Kind.BEACH]
	var n := 0
	for f in 900:
		if f % 140 == 20 and n < biome_order.size():
			var snap := SNAP.duplicate(true)
			snap["session"] = "t%d" % n
			snap["started_at"] = "2026-09-30T10:0%d:00Z" % n
			islands.default_biome = biome_order[n]
			marks[frames.size()] = "snapshot t%d" % n
			var t0 := Time.get_ticks_usec() # TIMING
			world.store.apply({"type": "session.snapshot", "session": snap})
			print("TIMING apply %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0)) # TIMING
			n += 1
		await process_frame
		var now := Time.get_ticks_usec()
		if now - last > 15000 and ph.size() == 4: # TIMING
			print("TIMING   phases from frame start: physics %.1f, process %.1f, pre_draw %.1f, post_draw %.1f, now %.1f" % [(ph["physics"] - last) / 1000.0, (ph["process"] - last) / 1000.0, (ph["pre_draw"] - last) / 1000.0, (ph["post_draw"] - last) / 1000.0, (now - last) / 1000.0]) # TIMING
		frames.append((now - last) / 1000.0)
		if frames[-1] > 15.0: # TIMING
			print("TIMING FRAME #%d %.1f ms, islands at %s, bridges %d" % [frames.size() - 1, frames[-1], islands.all_islands().map(func(i: Island) -> int: return int(i.position.y)), islands.bridges.links().size()]) # TIMING
			print("TIMING   render cpu %.1f gpu %.1f setup %.1f, process %.1f physics %.1f" % [RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()), RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), RenderingServer.get_frame_setup_time_cpu(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]) # TIMING
		last = now
	var sorted := frames.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	print("median %.1f ms, 95th %.1f ms, max %.1f ms" % [median, sorted[int(sorted.size() * 0.95)], sorted[-1]])
	var keys := marks.keys()
	keys.sort()
	for at: int in keys:
		var row := PackedStringArray()
		var from := at - 6 if String(marks[at]).begins_with("built") else at
		for j in range(maxi(from, 0), mini(at + 3, frames.size())):
			row.append("%.1f" % frames[j])
		print("%-16s frames from it: %s" % [marks[at], ", ".join(row)])
	var worst := PackedStringArray()
	for j in frames.size():
		if frames[j] > median * 2.5:
			worst.append("#%d %.1f" % [j, frames[j]])
	print("spikes (>2.5x median): %s" % ", ".join(worst))
	quit()
