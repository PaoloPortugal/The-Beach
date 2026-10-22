extends Node3D
## Dev tool (W06, user's request): the world with 64 made-up sessions in
## 20 clusters, to see how the layout and bridges look. The sidecar is
## stopped as soon as the demo starts, so none of your real sessions show.
## A 16-island cluster shows a near wedge growing outward; the 12 past the
## 8th are far clusters (W05), bridged within but not to the platform.
##
##   godot --path . res://tests/world/layout_demo.tscn
##
## With [code]-- --crowd[/code], the crowd instead (W05: 311 sessions,
## [constant CROWD]), to see big clusters or measure performance with them.
##
## B switches to a view from above (fog off, so no draw distance; mouse
## wheel zooms); the sessions ring (hold Tab) goes to any island; M opens the big
## map.

## Islands per cluster: 64 in 20 clusters, the first 8 near (d01-d41),
## the rest far (d42-d64).
const SIZES := [16, 6, 5, 4, 3, 3, 2, 2, 6, 4, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1]

## The crowd (W05, user's request, 2026-10-09): near clusters of about 40
## and far ones of about 20, some more, some fewer, some very few. 311
## sessions in 13 clusters. The bridges test runs [constant CROWD_TRIMMED]
## on CI, and this one with [code]-- --crowd[/code].
const CROWD := [52, 45, 40, 38, 33, 25, 8, 3, 26, 20, 14, 5, 2]
## A smaller crowd for CI: two big neighbouring wedges, two big
## neighbouring far clusters and some very small ones. 178 sessions.
const CROWD_TRIMMED := [45, 40, 25, 8, 3, 2, 1, 1, 26, 20, 5, 2]

## The sizes used: [constant SIZES], [constant CROWD] when the demo is run
## with [code]-- --crowd[/code], or what a test sets before it enters the
## tree.
var sizes: Array = SIZES

var world: Node3D
var _above := Camera3D.new()
var _fog := true


func _ready() -> void:
	# By path: a --script test can't name the autoload.
	get_node("/root/Sidecar").stop()
	# Run as the main scene, not by a test.
	if "--crowd" in OS.get_cmdline_user_args() and get_tree().current_scene == self:
		sizes = CROWD
	if get_tree().current_scene == self:
		# Run as the main scene: its fake sessions never in the user's
		# remembered islands (W12; a test already has its own file).
		IslandMemory.file = "user://layout-demo-islands.json"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(IslandMemory.file))
	world = load("res://world/world.tscn").instantiate()
	if get_tree().current_scene != self:
		# Run by a test: the defaults, never the developer's settings file (C10, A05).
		var settings_file := "user://layout_demo_test_settings_%d.cfg" % OS.get_process_id()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_file))
		world.settings.path = settings_file
		world.attention.settings_path = settings_file
	add_child(world)
	var store: SessionStore = world.store
	var n := 0
	for c in sizes.size():
		var repo := "/demo/repo-%02d" % (c + 1)
		for k in sizes[c]:
			n += 1
			store.apply({"type": "session.snapshot", "session": session("d%02d" % n, repo, "task %d" % (k + 1))})
	_above.projection = Camera3D.PROJECTION_ORTHOGONAL
	_above.size = 1600.0
	_above.far = 2000.0
	_above.rotation_degrees = Vector3(-90, 0, 0)
	add_child(_above)


## A session as a snapshot gives it, in [param repo].
static func session(id: String, repo: String, title: String) -> Dictionary:
	return {
		"session": id, "seq": 1, "provider": "fake", "native_id": null, "origin": "app",
		"project": {"path": repo, "name": repo.get_file(), "repo": repo}, "title": title,
		"started_at": "2026-10-07T10:00:00Z", "capabilities": {}, "extensions": [], "permissions": [],
		"notices": [], "agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
	}


func _process(_delta: float) -> void:
	var player: Node3D = world.get_node("Player")
	_above.global_position = Vector3(player.global_position.x, 900.0, player.global_position.z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		_above.current = not _above.current
		if not _above.current:
			(world.get_node("Player/Head/Camera3D") as Camera3D).current = true
		_set_fog(not _above.current)
	elif event is InputEventMouseButton and event.pressed and _above.current:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_above.size = maxf(100.0, _above.size * 0.85)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_above.size = minf(6000.0, _above.size / 0.85)


func _set_fog(on: bool) -> void:
	for env: WorldEnvironment in world.find_children("*", "WorldEnvironment", true, false):
		env.environment.fog_enabled = on
	# Without the fog, everything is drawn however far.
	world.fit_draw_distance()
