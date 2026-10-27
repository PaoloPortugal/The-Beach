extends SceneTree
# Frame times in the real world scene (main menu up) as sessions' islands
# arrive (W01; NOTES → Running it → Frame timing). Run with
# -- --sidecar-dev-fake. Never the user's files.
#
# Add --start for a game's start instead: frames from the very first,
# and six sessions taken back together by one sync (S07, W12), the way a
# restart brings them, 30 frames in.

const SNAP := {
	"seq": 1, "provider": "fake", "native_id": null, "origin": "app",
	"project": {"path": "/p", "name": "demo"}, "title": null, "started_at": "2026-09-30T10:00:00Z",
	"capabilities": {}, "extensions": [], "permissions": [], "notices": [],
	"agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
}
const BIOMES := [Biome.Kind.BEACH, Biome.Kind.FOREST, Biome.Kind.MOUNTAIN, Biome.Kind.SNOWY, Biome.Kind.DESERT, Biome.Kind.BEACH]


func _initialize() -> void:
	if not "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		printerr("Run with -- --sidecar-dev-fake: never the user's own sessions.")
		quit(1)
		return
	IslandMemory.file = "user://timing-islands.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IslandMemory.file))
	var world: Node3D = load("res://world/world.tscn").instantiate()
	var settings_file := "user://timing_settings.cfg"
	world.settings.path = settings_file
	world.attention.settings_path = settings_file
	world.set_outside_sessions = func(_on: bool) -> void: pass
	root.add_child(world)
	_run.call_deferred(world, "--start" in OS.get_cmdline_user_args())


func _run(world: Node3D, start: bool) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not start:
		for i in 120:
			await process_frame
	var islands: SessionIslands = world.get_node("SessionIslands")
	var frames: Array[float] = []
	var marks := {}
	islands.island_added.connect(func(_id: String, i: Island, _o: Orchestrator) -> void:
		i.built.connect(func() -> void: marks[frames.size()] = "built %s" % Biome.NAMES[i.biome]))
	var last := Time.get_ticks_usec()
	var n := 0
	for f in 600 if start else 900:
		if start and f == 30:
			marks[frames.size()] = "sync of %d" % BIOMES.size()
			_sync(world.store, islands)
		elif not start and f % 140 == 20 and n < BIOMES.size():
			islands.default_biome = BIOMES[n]
			marks[frames.size()] = "snapshot t%d" % n
			world.store.apply({"type": "session.snapshot", "session": _snap(n)})
			n += 1
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	var sorted := frames.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	print("median %.1f ms, 95th %.1f ms, max %.1f ms" % [median, sorted[int(sorted.size() * 0.95)], sorted[-1]])
	if start:
		var first := PackedStringArray()
		for j in mini(90, frames.size()):
			first.append("%.0f" % frames[j])
		print("first 90 frames: %s" % ", ".join(first))
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


func _snap(n: int) -> Dictionary:
	var snap := SNAP.duplicate(true)
	snap["session"] = "t%d" % n
	snap["started_at"] = "2026-09-30T10:0%d:00Z" % n
	if n % 2 == 1: # two repositories: two clusters
		snap["project"] = {"path": "/q", "name": "other"}
	return snap


# Every session taken back at once, as a reconnect's sync brings them:
# their snapshots while syncing, then the sync's end.
func _sync(store: SessionStore, islands: SessionIslands) -> void:
	store.syncing = true
	for n in BIOMES.size():
		islands.choose_biome("t%d" % n, BIOMES[n])
		store.apply({"type": "session.snapshot", "session": _snap(n)})
	store._on_synced()
