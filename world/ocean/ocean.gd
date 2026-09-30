extends MeshInstance3D
## Keeps the ocean plane under the camera so its edge never shows. It moves
## in whole grid cells, and the waves are computed in world space, so the
## water doesn't visibly shift when it moves.

const CELL := 800.0 / 200.0  # plane size / subdivisions + 1


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var p := camera.global_position
	global_position = Vector3(snappedf(p.x, CELL), 0.0, snappedf(p.z, CELL))
