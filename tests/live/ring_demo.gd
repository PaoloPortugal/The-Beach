extends Node3D
## Dev tool for the sessions ring's live check (W07): the world with the
## fake provider and 12 sessions started for you, in four projects (four
## clusters), every biome, and the states the ring shows: working (blue),
## idle (grey), waiting for you (orange, pulsing). F2 starts one more in
## the biggest project, which takes the ring past 12 segments, so that
## cluster folds; F3 shows a session still starting (a stand-in: nothing
## really starts) and hides it again. Needs the fake provider:
##
##   godot --path . res://tests/live/ring_demo.tscn -- --sidecar-dev-fake --checklist
##
## The projects are empty folders under the game's user data folder
## (ring_demo/), outside git, so each is its own cluster.

## The sessions started: project, title, biome, then what to send it once
## it has its title ("" for nothing: it stays idle).
const SESSIONS := [
	["alpha", "Fix the login bug", Biome.Kind.BEACH, ""],
	["alpha", "Add dark mode", Biome.Kind.FOREST, "permission"],
	["alpha", "Write the release notes", Biome.Kind.MOUNTAIN, ""],
	["alpha", "Refactor the settings store", Biome.Kind.SNOWY, ""],
	["alpha", "Speed up the search", Biome.Kind.DESERT, ""],
	["beta", "Translate the menus", Biome.Kind.FOREST, "agents 4"],
	["beta", "Review the pull request", Biome.Kind.BEACH, ""],
	["beta", "A rather long session title to see how the middle copes with it", Biome.Kind.SNOWY, ""],
	["gamma", "Profile the renderer", Biome.Kind.MOUNTAIN, "question"],
	["gamma", "Update the dependencies", Biome.Kind.DESERT, ""],
	["delta", "Sketch the onboarding", Biome.Kind.BEACH, ""],
	["delta", "Clean up the logs", Biome.Kind.FOREST, ""],
]
## How long "Translate the menus" stays idle before it's sent agents
## again, seconds, so one session is working most of the time.
const REST := 2.0

var world: Node3D
var _sidecar: SidecarClient
var _started: Array[String] = []
var _working := ""
var _more := 0
var _work_timer := 0.0


func _ready() -> void:
	world = load("res://world/world.tscn").instantiate()
	add_child(world)
	# By path: the autoload's name isn't known to the parser here.
	_sidecar = get_node("/root/Sidecar")
	if not "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		push_warning("ring_demo: run it with -- --sidecar-dev-fake, or it starts real claude sessions")
		return
	while _sidecar.status != SidecarClient.Status.READY:
		await get_tree().process_frame
	var then := {}
	for spec: Array in SESSIONS:
		var id: String = await _start(spec[0], spec[2])
		if id.is_empty():
			continue
		_send(id, spec[1]) # its first message names it
		if not spec[3].is_empty():
			then[id] = spec[3]
	# The rest once the naming turns are over: one ending would set its
	# session idle again.
	await get_tree().create_timer(3.0).timeout
	for id: String in then:
		_send(id, then[id])
		if then[id] == "agents 4":
			_working = id


func _process(delta: float) -> void:
	if _working.is_empty():
		return
	if world.store.activity(_working) != "idle":
		_work_timer = 0.0
		return
	_work_timer += delta
	if _work_timer >= REST:
		_work_timer = 0.0
		_send(_working, "agents 4")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var launcher: SessionLauncher = (world.get_node("SessionsMenu") as SessionsMenu).launcher
	if key.physical_keycode == KEY_F2:
		_more += 1
		var id: String = await _start("alpha", Biome.RANDOM)
		if not id.is_empty():
			_send(id, "Extra task %d" % _more)
	elif key.physical_keycode == KEY_F3:
		# A stand-in: the ring and the create panel only look at pending.
		launcher.pending = "" if launcher.busy() else "ring-demo-starting"
		launcher.status_changed.emit("Starting…" if launcher.busy() else "")


# Starts a session in the project folder [param project] on an island of
# [param biome], like the launcher does but without taking you there;
# returns its id once it's in the store, or "".
func _start(project: String, biome: int) -> String:
	var path := ProjectSettings.globalize_path("user://ring_demo/" + project)
	DirAccess.make_dir_recursive_absolute(path)
	var provider: String = _sidecar.providers[0]["provider"]
	var reply: Array = [{}]
	_sidecar.send_command("session.create", {"provider": provider, "project": {"path": path}}, func(r: Dictionary) -> void:
		reply[0] = r
		var id: String = r.get("result", {}).get("session", "")
		if not id.is_empty():
			(world.get_node("SessionIslands") as SessionIslands).choose_biome(id, biome))
	while reply[0].is_empty():
		await get_tree().process_frame
	var id: String = reply[0].get("result", {}).get("session", "")
	if id.is_empty():
		push_warning("ring_demo: couldn't start a session: %s" % reply[0].get("message", ""))
		return ""
	var store: SessionStore = world.store
	while not store.sessions.has(id):
		await get_tree().process_frame
	_started.append(id)
	return id


func _send(id: String, text: String) -> void:
	_sidecar.send_command("message.send", {"session": id, "text": text})
