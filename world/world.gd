extends Node3D
## The world scene: the player starts on a platform in the open sea. Tab
## opens the sessions menu, to start, resume or go to a session. Each live
## session gets an island with its orchestrator, rising out of the sea for
## a new one; one you started takes you there once it's up. Plus the ocean and the chat. Closing the window while sessions
## run asks first (S05). Sessions waiting on you draw attention (A05).
## Bridges join each cluster's islands and the platform, and a minimap
## shows the cluster you're in (W06).

## Godot's copy of the live sessions, fed by the sidecar.
var store := SessionStore.new()
## Asks before quitting while sessions run.
var quit_guard := QuitGuard.new()
## Says when sessions wait on you (A05; the beacons are on the agents).
var attention := Attention.new()
## Points to new sessions' islands while they're off-screen (W04).
var pointers := NewIslandPointers.new()
## The map of the cluster you're in or nearest to (W06).
var minimap := Minimap.new()

## The spawn platform's deck: half its width and its top (world.tscn).
const PLATFORM_HALF := 6.0
const PLATFORM_TOP := 1.0

# The session whose island is rising, to take the player to once it's up.
var _teleport_when_risen := ""

@onready var _player: Player = $Player
@onready var _islands: SessionIslands = $SessionIslands
@onready var _menu: SessionsMenu = $SessionsMenu
@onready var _chat: ChatController = $ChatController


func _ready() -> void:
	# Under the Compatibility renderer, sun shadows wash the island out to
	# white (Godot 4.7.2, seen on AMD; NOTES → Watch items), so they're off
	# there.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.shadow_enabled = false
	# The platform's deck is at y = 1. Falling in the sea brings you back
	# here.
	_player.spawn_point = Vector3(0.0, 1.1, 3.0)
	_player.respawn()
	_menu.player = _player

	# Order matters: the islands hear of a new session first, so its island
	# exists by the time the menu's launcher says it started.
	_islands.setup(store)
	# The platform is in every cluster's bridge tree (W06).
	_islands.bridges.add_hub("platform", Vector3.ZERO, PLATFORM_HALF * sqrt(2.0), platform_edge)
	_chat.setup(store, Sidecar)
	_menu.setup(store, Sidecar, _islands.clusters)
	add_child(quit_guard)
	quit_guard.setup(store, _player)
	add_child(attention)
	attention.setup(store)
	add_child(pointers)
	pointers.setup(_islands, store)
	add_child(minimap)
	minimap.setup(_islands, _player)
	minimap.hidden_when = func() -> bool: return _chat.is_open() or _menu.is_open()
	_menu.attention = attention
	_islands.player = _player
	_islands.island_added.connect(func(_id: String, _island: Island, orchestrator: Orchestrator) -> void:
		_chat.watch(orchestrator))
	_islands.island_risen.connect(func(id: String) -> void:
		if id == _teleport_when_risen:
			teleport(id))
	_menu.launcher.session_started.connect(teleport)
	_menu.go_to.connect(teleport)
	store.attach(Sidecar)
	# Dev tool: the current live check's steps, top left (NOTES → Running it).
	if "--checklist" in OS.get_cmdline_user_args():
		add_child(load("res://tests/live/checklist.tscn").instantiate())
		minimap.top = 56.0 # under it


## Puts the player on a session's island, facing its orchestrator, once
## the island has risen (W04). From the sessions menu; travel proper is
## W06 (bridges) and W07.
func teleport(session_id: String) -> void:
	_teleport_when_risen = ""
	if _islands.island(session_id) == null:
		return
	if _islands.is_rising(session_id):
		_teleport_when_risen = session_id
		return
	_player.global_position = _islands.arrival_point(session_id)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0 # the orchestrator is straight ahead (-z)


## Where a bridge heading for [param toward] leaves the platform: its
## deck's edge, with the bridge's overrun (Bridge.OVERRUN) ending there.
static func platform_edge(toward: Vector3) -> Vector3:
	var dir := Vector2(toward.x, toward.z).normalized()
	var out := PLATFORM_HALF / maxf(absf(dir.x), absf(dir.y)) + Bridge.OVERRUN
	return Vector3(dir.x * out, PLATFORM_TOP, dir.y * out)
