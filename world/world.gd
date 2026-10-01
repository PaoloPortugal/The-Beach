extends Node3D
## The world scene (M1): the player starts on a platform in the open sea,
## with a post for starting a session. Each live session gets an island
## with its orchestrator; one you started takes you there. Plus the ocean
## and the chat.

## Godot's copy of the live sessions, fed by the sidecar.
var store := SessionStore.new()

@onready var _player: Player = $Player
@onready var _islands: SessionIslands = $SessionIslands
@onready var _post: SessionPost = $SpawnPlatform/SessionPost
@onready var _chat: ChatController = $ChatController


func _ready() -> void:
	# Under the Compatibility renderer, sun shadows wash the island out to
	# white (Godot 4.7.2, seen on AMD; NOTES → Watch items), so they're off
	# there.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.shadow_enabled = false
	# The platform's deck is at y = 1; the player starts in front of the
	# post, facing it. Falling in the sea brings you back here.
	_player.spawn_point = Vector3(0.0, 1.1, 3.0)
	_player.respawn()
	_post.player = _player

	# Order matters: the islands hear of a new session first, so its island
	# exists by the time the post says it started.
	_islands.setup(store)
	_chat.setup(store, Sidecar)
	_post.setup(store, Sidecar)
	_islands.island_added.connect(func(_id: String, _island: Island, orchestrator: Orchestrator) -> void:
		_chat.watch(orchestrator))
	_islands.island_removed.connect(func(id: String, _island: Island) -> void:
		# Its island is going: whoever stands on it goes back to the platform.
		if _islands.session_at(_player.global_position) == id:
			_player.respawn())
	_post.session_started.connect(teleport)
	store.attach(Sidecar)
	# Dev tool: the current live check's steps, top left (NOTES → Running it).
	if "--checklist" in OS.get_cmdline_user_args():
		add_child(load("res://tests/live/checklist.tscn").instantiate())


## Puts the player on a session's island, facing its orchestrator.
## Temporary: travel between islands is W06 (bridges) and W07 (teleport menu).
func teleport(session_id: String) -> void:
	if _islands.island(session_id) == null:
		return
	_player.global_position = _islands.arrival_point(session_id)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0 # the orchestrator is straight ahead (-z)
