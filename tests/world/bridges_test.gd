extends SceneTree
## Headless test for W06's bridges: a bridge's shape (clearance, ramps,
## any slope), walking across one and not getting past its rails (real
## physics), the bridge tree (each region to its nearest, patching a cut
## without moving other bridges, a hubless group), and the layout demo's
## 64 sessions: every near cluster joined to the platform, every far one
## joined within but not to it, no bridge over another island's land or
## across another bridge, and still so after islands sink; and a crowd of
## clusters of varied sizes, the same: 178 sessions, or with -- --crowd
## the full 311 (too slow to run on every push).
##
##   godot --headless --path . --script res://tests/world/bridges_test.gd
##   godot --headless --path . --script res://tests/world/bridges_test.gd -- --crowd

const ErrorWatch := preload("res://tests/error_watch.gd")
const LayoutDemo := preload("res://tests/world/layout_demo.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_run()


func _run() -> void:
	_profile()
	_tree()
	await _walk()
	await _demo()
	await _crowd()
	if not _failed and _errors.ok():
		print("PASS bridges_test")
		quit(0)


func _profile() -> void:
	var y := func(s: float) -> float: return Bridge.deck_height(0.5, 1.0, 60.0, s)
	_check(is_equal_approx(y.call(0.0), 0.5) and is_equal_approx(y.call(60.0), 1.0), "shape: the deck meets both ends")
	_check(is_equal_approx(y.call(30.0), Bridge.CLEARANCE), "and stays clear of the waves in between")
	var steepest := 0.0
	for s in 59:
		steepest = maxf(steepest, absf(y.call(s + 1.0) - y.call(s)))
	_check(steepest <= Bridge.RAMP + 0.001, "ramps no steeper than %.2f" % Bridge.RAMP)
	var high := func(s: float) -> float: return Bridge.deck_height(3.0, 9.0, 60.0, s)
	_check(is_equal_approx(high.call(30.0), 6.0), "ends higher up (W10): a straight slope")


# Regions in a row, 100 m apart, plus a hub: the bridges make a tree.
func _tree() -> void:
	var net := BridgeNetwork.new()
	root.add_child(net)
	var edge := func(centre: Vector3) -> Callable:
		return func(toward: Vector3) -> Vector3: return centre + (toward - centre).normalized() * 20.0
	net.add_hub("hub", Vector3.ZERO, 8.0, edge.call(Vector3.ZERO))
	for k in 4:
		var c := Vector3(130.0 + 100.0 * k, 0.0, 0.0)
		net.add("r%d" % k, "g", c, 40.0, edge.call(c))
	_check(_pairs(net) == ["hub-r0", "r0-r1", "r1-r2", "r2-r3"], "tree: each new region to its nearest, the first to the hub")
	var kept := net.bridge("r2", "r3")
	net.remove("r1")
	_check(_pairs(net) == ["hub-r0", "r0-r2", "r2-r3"], "a cut is patched with the shortest bridge, the rest stay")
	_check(net.bridge("r2", "r3") == kept, "the same bridge, not a new one")
	var side := Vector3(230.0, 0.0, 90.0)
	net.add("other", "h", side, 40.0, edge.call(side))
	_check(net.bridge("hub", "other") != null and net.bridge("r2", "other") == null, "another group has its own tree, from the hub")
	_check(not net.is_clear("hub", "r2"), "a line across another region's land isn't clear")
	net.remove("r0")
	_check(_pairs(net) == ["hub-other", "hub-r2", "r2-r3"], "losing the hub's bridge: the hub links again")
	# A hubless group (a far cluster): bridged within, never to the hub.
	for k in 3:
		var c := Vector3(-130.0 - 100.0 * k, 0.0, 0.0)
		net.add("f%d" % k, "far", c, 40.0, edge.call(c), false)
	_check(_pairs(net) == ["f0-f1", "f1-f2", "hub-other", "hub-r2", "r2-r3"], "a hubless group: its first region has no bridge, the next ones join it")
	net.remove("f1")
	_check(net.bridge("f0", "f2") != null and net.bridge("hub", "f0") == null and net.bridge("hub", "f2") == null, "a cut is patched within it, not through the hub")
	net.free()


func _walk() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	await process_frame # the tree is going
	for z in [0.0, -64.0]:
		var ground := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(20, 1, 20)
		shape.shape = box
		ground.add_child(shape)
		ground.position = Vector3(0, 0.0, z) # top at 0.5
		scene.add_child(ground)
	# From one ground's edge to the other's, its overrun on each.
	var bridge := Bridge.new(Vector3(0, 0.5, -10.0 + Bridge.OVERRUN), Vector3(0, 0.5, -54.0 - Bridge.OVERRUN))
	scene.add_child(bridge)
	var player: Player = load("res://world/player/player.tscn").instantiate()
	scene.add_child(player)
	player.spawn_point = Vector3(0, 1.0, 50.0)
	player.global_position = Vector3(0, 0.6, -5.0)
	await _frames(10)
	Input.action_press("move_forward")
	await _until(func() -> bool: return player.global_position.z < -58.0 or player.global_position.z > 40.0, 15.0)
	Input.action_release("move_forward")
	_check(player.global_position.z < -58.0 and player.global_position.z > -80.0, "walk: across the bridge to the other side")
	player.global_position = Vector3(0, 1.4, -32.0)
	await _frames(10)
	_check(player.is_on_floor() and absf(player.global_position.y - bridge.deck_y(22.0 + Bridge.OVERRUN)) < 0.3, "standing in the middle, on its deck (%.2f m, deck %.2f m, floor %s)" % [player.global_position.y, bridge.deck_y(22.0 + Bridge.OVERRUN), player.is_on_floor()])
	_check(bridge.carries(player.global_position), "the bridge knows you're on it")
	for action in ["move_left", "move_right"]:
		player.global_position = Vector3(0, 1.4, -32.0)
		await _frames(5)
		Input.action_press(action)
		Input.action_press("sprint")
		for k in 6:
			_press("jump")
			await _frames(15)
		Input.action_release(action)
		Input.action_release("sprint")
		await _frames(30)
		_check(absf(player.global_position.x) < Bridge.WIDTH / 2.0 and player.global_position.y > 0.5, "rails: no running or jumping off (%s)" % action)
	scene.free()


func _demo() -> void:
	var demo: Node3D = load("res://tests/world/layout_demo.tscn").instantiate()
	root.add_child(demo)
	await _frames(5)
	var world: Node3D = demo.world
	var islands: SessionIslands = world.get_node("SessionIslands")
	await _until(islands.all_up, 30.0) # made off the main thread, then risen (C14)
	var clusters := islands.clusters
	_check(world.store.sessions.size() == 64 and clusters.ids().size() == 20, "demo: 64 sessions in 20 clusters")
	_layout_ok(islands, "demo")
	var far := 0
	for id in world.store.sessions:
		far += 1 if clusters.is_far(clusters.cluster_of(id)) else 0
	_check(far == 23 and clusters.is_far(clusters.cluster_of("d42")) and not clusters.is_far(clusters.cluster_of("d41")), "demo: the 12 clusters past the 8th (23 islands) are far")
	_check(islands.island("d16").global_position.distance_to(islands.island("d01").global_position) > 500.0 and not islands.is_far(islands.island("d16")), "demo: the 16-island cluster still in its wedge, reaching %.0f m out" % islands.island("d16").global_position.length())
	# The minimap: the cluster you're at, near or far.
	var player: Player = world.get_node("Player")
	var minimap: Minimap = world.minimap
	player.global_position = islands.island("d02").global_position + Vector3(0, 3, 0)
	await _frames(5)
	await _settle()
	var size := minimap.map_rect().size
	var on_map := func(id: String) -> bool: return Rect2(Vector2.ZERO, size).has_point(minimap.to_map(islands.island(id).global_position))
	_check(minimap.shown_cluster() == clusters.cluster_of("d02") and on_map.call("d01") and on_map.call("d16"), "minimap: the cluster's islands in its wedge")
	player.global_position = islands.island("d43").global_position + Vector3(0, 3, 0)
	await _frames(5)
	await _settle()
	_check(minimap.shown_cluster() == clusters.cluster_of("d42") and on_map.call("d42") and on_map.call("d47") and not on_map.call("d01"), "near a far cluster, its islands")
	# The big map (W06): zoomed right out, the whole world fits.
	var big: WorldMap = world.world_map
	big.open()
	await _settle()
	var all := Rect2(Vector2.ZERO, Vector2.ZERO)
	for i in islands.all_islands():
		all = all.merge(Minimap.reach_rect(i))
	big.centre = all.get_center()
	big.zoom_by(-100.0, big.map_rect().size / 2.0)
	var view := Rect2(Vector2.ZERO, big.map_rect().size)
	_check(islands.all_islands().size() == 64 and islands.all_islands().all(func(i: Island) -> bool: return view.has_point(big.to_map(i.global_position))), "big map: zoomed out, all 64 islands fit, far ones too")
	big.centre = Vector2(islands.island("d64").global_position.x, islands.island("d64").global_position.z)
	_check(big.session_at(view.size / 2.0) == "d64", "big map: a far island can be picked")
	big.close()
	# Islands in the middle of trees sink: what's left is patched.
	player.global_position = Vector3(0, 1.1, 0)
	var before := islands.bridges.links().size()
	var keep: Array = islands.bridges.links()
	var gone := ["d01", "d02", "d15", "d14", "d43"]
	for id in gone:
		world.store.apply({"type": "session.ended", "session": id, "seq": 2, "reason": "exited"})
	await _until(func() -> bool: return islands.left_islands().all(func(i: Island) -> bool: return not islands.bridges.has(SessionIslands.region(i))), 3.0)
	var after: Array = islands.bridges.links()
	_check(after.size() == before - gone.size(), "demo: one bridge fewer per sunk island (a tree still)")
	var removed := keep.filter(func(l: Array) -> bool: return not l in after)
	var touching := removed.all(func(l: Array) -> bool: return islands.left_islands().any(func(i: Island) -> bool: return SessionIslands.region(i) in l))
	_check(touching, "only the sinking islands' bridges went")
	_layout_ok(islands, "after sinking")
	demo.queue_free()
	await _frames(2)


# The layout demo crowded (LayoutDemo.CROWD_TRIMMED, or CROWD with
# -- --crowd): clusters of varied sizes, near and far. Still well apart,
# bridged as it should be, and patched after islands sink, near and far.
func _crowd() -> void:
	var demo: Node3D = LayoutDemo.new()
	var full := "--crowd" in OS.get_cmdline_user_args()
	demo.sizes = LayoutDemo.CROWD if full else LayoutDemo.CROWD_TRIMMED
	var far_count: int = demo.sizes.size() - SessionClusters.WEDGES
	var started := Time.get_ticks_msec()
	root.add_child(demo)
	await _frames(5)
	var world: Node3D = demo.world
	var islands: SessionIslands = world.get_node("SessionIslands")
	await _until(islands.all_up, 120.0) # made off the main thread, then risen (C14)
	var clusters := islands.clusters
	var total: int = demo.sizes.reduce(func(a: int, b: int) -> int: return a + b, 0)
	var ids := clusters.ids()
	_check(world.store.sessions.size() == total and ids.size() == demo.sizes.size(), "crowd%s: %d sessions in %d clusters (%.0f s to build)" % [" (full)" if full else "", total, ids.size(), (Time.get_ticks_msec() - started) / 1000.0])
	_check(ids.slice(0, 8).all(func(id: String) -> bool: return not clusters.is_far(id)) and ids.slice(8).all(func(id: String) -> bool: return clusters.is_far(id)), "crowd: the %d past the 8th are far" % far_count)
	var all := islands.all_islands()
	var closest := INF
	var furthest := 0.0
	for a in all.size():
		furthest = maxf(furthest, all[a].global_position.length())
		for b in a:
			closest = minf(closest, all[a].global_position.distance_to(all[b].global_position))
	_check(closest >= SessionClusters.ISLAND_SPACING - 0.01, "crowd: no two islands closer than 100 m (closest %.1f m, furthest out %.0f m)" % [closest, furthest])
	# A near cluster's tree has a bridge per island (one to the platform),
	# a far one's one fewer.
	_check(islands.bridges.links().size() == total - far_count, "crowd: a tree per cluster (%d bridges)" % islands.bridges.links().size())
	_layout_ok(islands, "crowd")
	# Islands sink, in the middle and at the ends of trees, near and far.
	world.get_node("Player").global_position = Vector3(0, 1.1, 0)
	var before := islands.bridges.links().size()
	# [cluster, island], in both crowds: the biggest's first, 5th and
	# last, middles of others (in the trimmed crowd, a 3-island one), and
	# far ones' first and middles.
	var gone := []
	for at in [[0, 0], [0, 4], [0, -1], [3, 4], [4, 1], [8, 0], [8, 13], [9, 7], [11, 1]]:
		gone.append(clusters.sessions(ids[at[0]])[at[1]])
	for id in gone:
		world.store.apply({"type": "session.ended", "session": id, "seq": 2, "reason": "exited"})
	await _until(func() -> bool: return islands.left_islands().all(func(i: Island) -> bool: return not islands.bridges.has(SessionIslands.region(i))), 3.0)
	_check(islands.bridges.links().size() == before - gone.size(), "crowd: one bridge fewer per sunk island")
	_layout_ok(islands, "crowd after sinking")
	demo.queue_free()
	await _frames(2)


# Every near cluster joined to the platform, every far one joined within
# but not to it; no bridge over other land or across another bridge.
func _layout_ok(islands: SessionIslands, what: String) -> void:
	var net := islands.bridges
	var regions := {}
	for id in islands.clusters.ids():
		for i in islands.cluster_islands(id):
			if net.has(SessionIslands.region(i)):
				regions[SessionIslands.region(i)] = i
	# Joined: from the platform, every near island is reachable; from a far
	# cluster's island, its cluster's and nothing else.
	var near := regions.keys().filter(func(k: String) -> bool: return not islands.is_far(regions[k]))
	var reach := _reached(net, "platform")
	_check(near.all(func(k: String) -> bool: return reach.has(k)) and reach.size() == near.size() + 1, "%s: every near island is joined to the platform, and no far one" % what)
	var within := true
	for id in islands.clusters.ids():
		if not islands.clusters.is_far(id):
			continue
		var mine := islands.cluster_islands(id).filter(func(i: Island) -> bool: return net.has(SessionIslands.region(i))).map(func(i: Island) -> String: return SessionIslands.region(i))
		if mine.is_empty():
			continue
		var got := _reached(net, mine[0])
		within = within and got.size() == mine.size() and mine.all(func(k: String) -> bool: return got.has(k))
	_check(within, "%s: every far cluster's islands are joined to each other, and to nothing else" % what)
	var over_land := 0
	var bridges: Array[Bridge] = []
	for c in islands.clusters.ids():
		bridges.append_array(net.bridges_in(c))
	for b in bridges:
		var middle := (b.from + b.to) / 2.0
		var half := b.from.distance_to(b.to) / 2.0
		for i: Island in regions.values():
			var c := i.global_position
			if Vector2(c.x - middle.x, c.z - middle.z).length() > half + 80.0:
				continue # too far to reach it
			if Vector2(b.from.x - c.x, b.from.z - c.z).length() < 50.0 or Vector2(b.to.x - c.x, b.to.z - c.z).length() < 50.0:
				continue # one of its own ends
			for k in 41:
				var local := b.from.lerp(b.to, k / 40.0) - c
				if i.height_at(local.x, local.z) > 0.0:
					over_land += 1
	_check(over_land == 0, "%s: no bridge over another island's land (%d points)" % [what, over_land])
	var crossing := 0
	for x in bridges.size():
		for y in x:
			var a := bridges[x]
			var b := bridges[y]
			if a.from.distance_to(b.from) < 20.0 or a.from.distance_to(b.to) < 20.0 or a.to.distance_to(b.from) < 20.0 or a.to.distance_to(b.to) < 20.0:
				continue # sharing an island or the platform
			if Geometry2D.segment_intersects_segment(Vector2(a.from.x, a.from.z), Vector2(a.to.x, a.to.z), Vector2(b.from.x, b.from.z), Vector2(b.to.x, b.to.z)) != null:
				crossing += 1
	_check(crossing == 0, "%s: no bridge across another (%d)" % [what, crossing])


# The regions joined to [param from] by bridges, it included.
func _reached(net: BridgeNetwork, from: String) -> Dictionary:
	var reach := {from: true}
	var grew := true
	while grew:
		grew = false
		for l: Array in net.links():
			if reach.has(l[0]) != reach.has(l[1]):
				reach[l[0]] = true
				reach[l[1]] = true
				grew = true
	return reach


# The bridges as "a-b", sorted, each pair in order.
func _pairs(net: BridgeNetwork) -> Array:
	var out := net.links().map(func(l: Array) -> String: return "%s-%s" % ([l[0], l[1]] if l[0] < l[1] else [l[1], l[0]]))
	out.sort()
	return out


func _press(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


# A whole main-loop iteration or two: physics frames alone may not run
# _process (a slow iteration runs several physics steps in a row).
func _settle() -> void:
	for i in 2:
		await process_frame


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
