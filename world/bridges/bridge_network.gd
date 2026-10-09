class_name BridgeNetwork
extends Node3D
## Connects regions with bridges (W06): a general system, not
## beach-specific, so other biomes (W10) plug in. Each group of regions
## (a cluster's islands) is one tree, just enough bridges to connect it;
## hubs (the spawn platform) belong to every group's tree but a hubless
## one's (a far cluster). A region that
## comes is bridged to its group's nearest one. When one goes, its bridges
## go with it and the cut pieces are patched: every other bridge stays,
## and the shortest new ones join the pieces (user's, 2026-10-07).
##
## A region is a key with a centre, a reach (how far its land goes, for
## keeping bridges clear of it) and an edge: a Callable taking the point a
## bridge heads for and giving where the bridge meets the region (the
## deck's top there).

## Region key → {"group": String, "centre": Vector3, "reach": float,
## "edge": Callable, "hub": bool}.
var _regions := {}
## Bridges in the order they were made: {"a", "b", "group", "bridge"}.
var _links: Array[Dictionary] = []
## Groups whose trees leave the hubs out → true.
var _hubless := {}


## Adds a hub: in every group's tree (but hubless ones), never bridged by
## itself.
func add_hub(key: String, centre: Vector3, reach: float, edge: Callable) -> void:
	_regions[key] = {"group": "", "centre": centre, "reach": reach, "edge": edge, "hub": true}


## Adds a region to [param group]'s tree, bridged to the nearest one there.
## Without [param with_hubs], the group's tree leaves the hubs out (its
## first region has no bridge).
func add(key: String, group: String, centre: Vector3, reach: float, edge: Callable, with_hubs := true) -> void:
	if _regions.has(key):
		return
	if not with_hubs:
		_hubless[group] = true
	_regions[key] = {"group": group, "centre": centre, "reach": reach, "edge": edge, "hub": false}
	var best := _best_link([key], _members(group).filter(func(k: String) -> bool: return k != key))
	if not best.is_empty():
		_link(best[0], best[1], group)


## Takes a region out with its bridges, and joins what that cut apart.
func remove(key: String) -> void:
	if not _regions.has(key):
		return
	var group: String = _regions[key]["group"]
	for l in _links.duplicate():
		if l["a"] == key or l["b"] == key:
			_unlink(l)
	_regions.erase(key)
	if group == "":
		return
	if not _regions.values().any(func(r: Dictionary) -> bool: return r["group"] == group):
		_hubless.erase(group)
	var pieces := _pieces(group)
	while pieces.size() > 1:
		var best := []
		var shortest := INF
		for i in pieces.size():
			for j in i:
				var link := _best_link(pieces[i], pieces[j])
				if not link.is_empty() and link[2] < shortest:
					best = link
					shortest = link[2]
		if best.is_empty():
			break
		_link(best[0], best[1], group)
		pieces = _pieces(group)


func has(key: String) -> bool:
	return _regions.has(key)


## Every bridge, as [region key, region key].
func links() -> Array:
	return _links.map(func(l: Dictionary) -> Array: return [l["a"], l["b"]])


## The bridges of [param group] (hub ones included), as [Bridge]s.
func bridges_in(group: String) -> Array[Bridge]:
	var out: Array[Bridge] = []
	for l in _links:
		if l["group"] == group:
			out.append(l["bridge"])
	return out


## Every bridge, as [Bridge]s.
func all_bridges() -> Array[Bridge]:
	var out: Array[Bridge] = []
	for l in _links:
		out.append(l["bridge"])
	return out


## The bridge between two regions, or null.
func bridge(a: String, b: String) -> Bridge:
	for l in _links:
		if (l["a"] == a and l["b"] == b) or (l["a"] == b and l["b"] == a):
			return l["bridge"]
	return null


## Whether [param point] is on one of [param key]'s bridges.
func on_bridge_of(key: String, point: Vector3) -> bool:
	for l in _links:
		if (l["a"] == key or l["b"] == key) and (l["bridge"] as Bridge).carries(point):
			return true
	return false


## Whether the straight line between two regions' centres keeps clear of
## every other region's land.
func is_clear(a: String, b: String) -> bool:
	var p: Vector3 = _regions[a]["centre"]
	var q: Vector3 = _regions[b]["centre"]
	for k in _regions:
		if k == a or k == b:
			continue
		var r: Dictionary = _regions[k]
		var c: Vector3 = r["centre"]
		var closest := Geometry2D.get_closest_point_to_segment(Vector2(c.x, c.z), Vector2(p.x, p.z), Vector2(q.x, q.z))
		if closest.distance_to(Vector2(c.x, c.z)) < r["reach"] + Bridge.WIDTH / 2.0 + 1.0:
			return false
	return true


# The group's regions and, unless it's hubless, the hubs.
func _members(group: String) -> Array:
	var hubs := not _hubless.has(group)
	return _regions.keys().filter(func(k: String) -> bool: return (hubs and _regions[k]["hub"]) or _regions[k]["group"] == group)


# The shortest clear link between two sets of regions, else the shortest:
# [a, b, length], or [] if a set is empty.
func _best_link(these: Array, those: Array) -> Array:
	var best := []
	var best_clear := false
	for a: String in these:
		for b: String in those:
			var d: float = (_regions[a]["centre"] as Vector3).distance_to(_regions[b]["centre"])
			var clear := is_clear(a, b)
			if best.is_empty() or (clear and not best_clear) or (clear == best_clear and d < best[2]):
				best = [a, b, d]
				best_clear = clear
	return best


# The group's regions and (unless it's hubless) the hubs, in pieces connected by its bridges.
func _pieces(group: String) -> Array:
	var members := _members(group)
	var root := {}
	for k in members:
		root[k] = k
	var find := func(k: String) -> String:
		while root[k] != k:
			k = root[k]
		return k
	for l in _links:
		if l["group"] == group:
			root[find.call(l["a"])] = find.call(l["b"])
	var by_root := {}
	for k in members:
		by_root.get_or_add(find.call(k), []).append(k)
	return by_root.values()


func _link(a: String, b: String, group: String) -> void:
	var ra: Dictionary = _regions[a]
	var rb: Dictionary = _regions[b]
	var from: Vector3 = ra["edge"].call(rb["centre"])
	var to: Vector3 = rb["edge"].call(ra["centre"])
	var bridge := Bridge.new(from, to)
	bridge.name = "Bridge"
	add_child(bridge, true)
	_links.append({"a": a, "b": b, "group": group, "bridge": bridge})


func _unlink(l: Dictionary) -> void:
	_links.erase(l)
	(l["bridge"] as Bridge).queue_free()
