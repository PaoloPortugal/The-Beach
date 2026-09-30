extends Node3D
## The world scene (M1): one island with its orchestrator, the ocean, the
## player and walking up to chat.

@onready var _island: Island = $Island
@onready var _player: Player = $Player
@onready var _orchestrator: Orchestrator = $Orchestrator


func _ready() -> void:
	# Under the Compatibility renderer, sun shadows wash the island out to
	# white (Godot 4.7.2, seen on AMD; NOTES → Watch items), so they're off
	# there.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.shadow_enabled = false
	# The island is generated in its own _ready, which runs before this one.
	# The orchestrator stands in the middle, facing +z; the player starts
	# 6 m in front of it (still on the flat middle), facing it.
	var ground := _island.height_at(0.0, 0.0)
	_orchestrator.position = Vector3(0.0, ground, 0.0)
	_player.spawn_point = Vector3(0.0, ground + 0.1, 6.0)
	_player.respawn()
