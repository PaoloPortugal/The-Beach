extends Node3D
## The world scene: one island, the ocean and the player (M1).

@onready var _island: Island = $Island
@onready var _player: Player = $Player


func _ready() -> void:
	# Under the Compatibility renderer, sun shadows wash the island out to
	# white (Godot 4.7.2, seen on AMD; NOTES → Watch items), so they're off
	# there.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.shadow_enabled = false
	# The island is generated in its own _ready, which runs before this one.
	_player.spawn_point = Vector3(0.0, _island.height_at(0.0, 0.0) + 0.1, 0.0)
	_player.respawn()
