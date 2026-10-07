extends Node3D
## Dev tool (W06, user's request): the world with 64 made-up sessions in
## 20 clusters, to see how the layout and bridges look. The sidecar is
## stopped, so none of your real sessions show and nothing is started.
## Clusters past 16 and a 13-island cluster show the far spots.
##
##   godot --path . res://tests/world/layout_demo.tscn
##
## B switches to a view from above (fog off; mouse wheel zooms); Tab's
## Running list goes to any island; M shows or hides the minimap.

## Islands per cluster: 64 in 20 clusters.
const SIZES := [13, 7, 6, 5, 4, 4, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 2]

var world: Node3D
var _above := Camera3D.new()
var _fog := true


func _ready() -> void:
	# By path: a --script test can't name the autoload.
	get_node("/root/Sidecar").stop()
	world = load("res://world/world.tscn").instantiate()
	add_child(world)
	var store: SessionStore = world.store
	var n := 0
	for c in SIZES.size():
		var repo := "/demo/repo-%02d" % (c + 1)
		for k in SIZES[c]:
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
