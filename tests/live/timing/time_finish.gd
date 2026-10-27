extends SceneTree
# Times an island's main-thread work after its ground is made
# (Island._finish_steps and what follows), with the real renderer, then frame times as islands
# arrive through the background path.

func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 90, 160)
	cam.far = 1000.0
	root.add_child(cam)
	cam.look_at(Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	_run.call_deferred()


func _ms(t: int) -> float:
	return (Time.get_ticks_usec() - t) / 1000.0


func _made(s: int, b: int) -> Dictionary:
	return Island._make(s, b, {})


func _run() -> void:
	await process_frame
	print("--- steps, ms (two seeds per biome; first of each biome may build prop meshes) ---")
	for b in Biome.NAMES.size():
		for k in 2:
			var s := 1000 + b * 10 + k
			var made := _made(s, b)
			var i := Island.new()
			i.island_seed = s
			i.biome = b
			i.zipline_waits = true
			i.build_in_background = true
			i.position = Vector3(-300 + b * 120, -200, 0)
			# Let its task finish, then do _finish's steps by hand.
			root.add_child(i)
			WorkerThreadPool.wait_for_task_completion(i._task)
			i._task = -1
			i.set_process(false)
			var t := Time.get_ticks_usec()
			i.generator.take(made)
			var t_take := _ms(t)
			t = Time.get_ticks_usec()
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, made["arrays"])
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mi.material_override = mat
			i.add_child(mi)
			var t_mesh := _ms(t)
			t = Time.get_ticks_usec()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(made["faces"])
			var t_faces := _ms(t)
			t = Time.get_ticks_usec()
			var col := CollisionShape3D.new()
			col.shape = shape
			i.add_child(col)
			var t_col := _ms(t)
			t = Time.get_ticks_usec()
			i.props.name = "Props"
			i.add_child(i.props)
			i.props.setup(made["spots"])
			var t_props := _ms(t)
			t = Time.get_ticks_usec()
			i._add_torches()
			var t_torch := _ms(t)
			t = Time.get_ticks_usec()
			var landings: Array[Vector3] = []
			for a in [0.3, 2.5]:
				var r := i.generator.shore_radius(cos(a), sin(a))
				landings.append(Vector3(cos(a) * r, 0, sin(a) * r))
			i.set_landings(landings)
			var t_land := _ms(t)
			print("%-8s seed %d: take %.1f  mesh %.1f  faces %.1f  collision %.1f  props %.1f (%d spots)  torches %.1f  landings+zipline %.1f  = %.1f" % [
				Biome.NAMES[b], s, t_take, t_mesh, t_faces, t_col, t_props, made["spots"].size(), t_torch, t_land,
				t_take + t_mesh + t_faces + t_col + t_props + t_torch + t_land])
			i.queue_free()
	await process_frame
	await process_frame

	print("--- frames as islands arrive (background path), ms ---")
	var last := Time.get_ticks_usec()
	var frames: Array[float] = []
	var marks := {} # frame index -> label
	var n := 0
	for f in 600:
		if f % 100 == 50 and n < 5:
			var i := Island.new()
			i.biome = n
			i.build_in_background = true
			i.zipline_waits = true
			i.position = Vector3(-120 + n * 60, 0, -40)
			var at := frames.size()
			i.built.connect(func() -> void: marks[frames.size()] = "built %s" % Biome.NAMES[i.biome])
			root.add_child(i)
			marks[at] = "added"
			n += 1
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	var sorted := frames.duplicate()
	sorted.sort()
	print("median %.1f ms, 95th %.1f ms, max %.1f ms" % [sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], sorted[-1]])
	for at: int in marks:
		var row := PackedStringArray()
		for j in range(at, mini(at + 4, frames.size())):
			row.append("%.1f" % frames[j])
		print("%-16s frames from it: %s" % [marks[at], ", ".join(row)])
	var worst := PackedStringArray()
	for j in frames.size():
		if frames[j] > sorted[frames.size() / 2] * 3.0:
			worst.append("#%d %.1f" % [j, frames[j]])
	print("spikes (>3x median): %s" % ", ".join(worst))
	quit()
