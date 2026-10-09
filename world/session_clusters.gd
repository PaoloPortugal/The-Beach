class_name SessionClusters
extends RefCounted
## Clusters (W05; user's decisions, 2026-10-02): islands of the same git
## repository, worktrees included, sit together. A session joins its
## repository's cluster on its own (by project folder outside git); the
## first one of a repository makes a new cluster, named after it, and
## later ones join that cluster (not one a session of it was moved to). When
## starting or resuming, the sessions menu can pick another running
## cluster or a new one instead. A cluster lasts while it has sessions, or
## islands of ended ones still above water (W04, [method hold]): with the
## last one gone, it and its spot are freed.
##
## Layout (W06, the user's wedges; unbounded since 2026-10-09): the first
## 8 clusters each own a wedge from the spawn platform and fill its island
## spots nearest the platform first, so they grow outward, without limit,
## and never into a neighbour. A 9th and later cluster is far: its first
## island on far rings, the rest round it, fanning away from the platform,
## bridged to each other but not to the platform ([method is_far]).

## Cluster membership or names changed.
signal changed

## Choices for [method choose]: by repository, or a new cluster. Any other
## value is a cluster id.
const AUTOMATIC := ""
const NEW := "new"

## Near clusters' wedges, each [code]TAU / WEDGES[/code] wide; a
## cluster in spot (slot) [code]WEDGES[/code] or later is far.
const WEDGES := 8
## Distance between neighbouring islands, metres. An island's land
## reaches at most about 44 m from its centre (its sea floor, 68 m).
const ISLAND_SPACING := 100.0
## How far an island's centre stays inside its wedge's edges, metres: its
## land and a bridge along the edge (a corridor) clear of it.
const EDGE_MARGIN := 50.0
## Far clusters' first islands: on rings from this far out,
## [constant FAR_SPACING] apart, and about that far apart on a ring.
const FAR_RADIUS := 2000.0
const FAR_SPACING := 1200.0

## Cluster id → {"name": String, "slot": int, "sessions": {session id or
## hold → island index}, "key": the repository (or folder outside git) it
## was made for automatically, "" for one made by hand}.
var _clusters := {}
## Session id or hold → cluster id.
var _of := {}
## Session id → the choice made when it was started, until it comes up.
var _choices := {}
## Holds: island spots of ended sessions, see [method hold].
var _holds := {}
var _next_id := 1
var _next_hold := 1


## Records where a session being started should go (a [constant AUTOMATIC],
## [constant NEW] or a cluster id), before it comes up.
func choose(session_id: String, choice: String) -> void:
	_choices[session_id] = choice


## Puts a session that came up in its cluster; returns the cluster id.
## [param session] is the protocol's session object.
func add(session_id: String, session: Dictionary) -> String:
	if _of.has(session_id):
		return _of[session_id]
	var project: Dictionary = session.get("project", {})
	var choice: String = _choices.get(session_id, AUTOMATIC)
	_choices.erase(session_id)
	var id := ""
	if choice == NEW:
		id = _new_cluster(SessionsMenu.project_name(project), "")
	elif _clusters.has(choice):
		id = choice
	else:
		id = _cluster_for(_key(project))
		if id.is_empty():
			var repo: String = project.get("repo", "")
			id = _new_cluster(repo.get_file() if not repo.is_empty() else SessionsMenu.project_name(project), _key(project))
	var members: Dictionary = _clusters[id]["sessions"]
	var index := 0
	while index in members.values():
		index += 1
	members[session_id] = index
	_of[session_id] = id
	changed.emit()
	return id


## Takes a session (or a [method hold]) out; its cluster goes with its last
## one.
func remove(session_id: String) -> void:
	_choices.erase(session_id)
	if not _of.has(session_id):
		return
	var id: String = _of[session_id]
	_of.erase(session_id)
	_holds.erase(session_id)
	_clusters[id]["sessions"].erase(session_id)
	if _clusters[id]["sessions"].is_empty():
		_clusters.erase(id)
	changed.emit()


## Takes an ended session out but keeps its island's spot, while its island
## is still above water (W04). Returns the hold, to [method remove] once
## the island is gone. A cluster left with only holds isn't in
## [method ids], but keeps its spot, and its repository's next session
## still joins it.
func hold(session_id: String) -> String:
	_choices.erase(session_id)
	if not _of.has(session_id):
		return ""
	var id: String = _of[session_id]
	var members: Dictionary = _clusters[id]["sessions"]
	var key := "hold:%d" % _next_hold
	_next_hold += 1
	members[key] = members[session_id]
	members.erase(session_id)
	_of.erase(session_id)
	_of[key] = id
	_holds[key] = true
	changed.emit()
	return key


## The ids of the clusters with sessions, in the order of their spots.
func ids() -> Array[String]:
	var out: Array[String] = []
	for id in _clusters:
		if not sessions(id).is_empty():
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return _clusters[a]["slot"] < _clusters[b]["slot"])
	return out


func cluster_of(session_id: String) -> String:
	return _of.get(session_id, "")


func cluster_name(cluster_id: String) -> String:
	return _clusters.get(cluster_id, {}).get("name", "")


## A cluster's sessions, in the order of their islands.
func sessions(cluster_id: String) -> Array[String]:
	var members: Dictionary = _clusters.get(cluster_id, {}).get("sessions", {})
	var out: Array[String] = []
	out.assign(members.keys().filter(func(k: String) -> bool: return not _holds.has(k)))
	out.sort_custom(func(a: String, b: String) -> bool: return members[a] < members[b])
	return out


## Where a session's (or a hold's) island goes.
func island_position(session_id: String) -> Vector3:
	var id: String = _of[session_id]
	return spot(_clusters[id]["slot"], _clusters[id]["sessions"][session_id])


## Whether a cluster is far (a 9th or later): its islands are bridged to
## each other but not to the platform.
func is_far(cluster_id: String) -> bool:
	return _clusters.has(cluster_id) and _clusters[cluster_id]["slot"] >= WEDGES


## Island [param index] of the cluster in spot [param slot]: in its wedge
## for a near one, round its first island for a far one.
static func spot(slot: int, index: int) -> Vector3:
	var p: Vector2
	var origin := Vector3.ZERO
	var dir: Vector2
	if slot >= WEDGES:
		origin = far_spot(slot - WEDGES)
		dir = Vector2(origin.x, origin.z).normalized()
		p = _far_spots(index + 1)[index]
	else:
		dir = Vector2.from_angle(slot * TAU / WEDGES)
		p = _wedge_spots(index + 1)[index]
	# p is (outward, across): along the wedge's middle, or away from the
	# platform through the first island.
	return origin + Vector3(p.x * dir.x - p.y * dir.y, 0.0, p.x * dir.y + p.y * dir.x)


## The first island of the cluster in spot [param slot].
static func cluster_position(slot: int) -> Vector3:
	return spot(slot, 0)


## Far cluster [param k]'s first island: on rings far beyond the wedges'
## first islands.
static func far_spot(k: int) -> Vector3:
	var ring := 0
	var first := 0
	while true:
		var count := int(TAU * (FAR_RADIUS + ring * FAR_SPACING) / FAR_SPACING)
		if k < first + count:
			var r := FAR_RADIUS + ring * FAR_SPACING
			var angle := float(k - first) * TAU / count
			return Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		first += count
		ring += 1
	return Vector3.ZERO


# The first [param count] island spots of a wedge, as (along its middle,
# across it), worked out once: scanning outward in rows 2 m apart, then
# from the middle sideways, each spot is the first point at least
# ISLAND_SPACING from the earlier ones and EDGE_MARGIN inside the edges.
static var _spots := PackedVector2Array()
static var _scan_at := EDGE_MARGIN / sin(PI / WEDGES)


static func _wedge_spots(count: int) -> PackedVector2Array:
	var half := PI / WEDGES
	while _spots.size() < count:
		var accepted := false
		var k := 0
		while k * 2.0 <= _scan_at * tan(half) and not accepted:
			for across in ([0.0] if k == 0 else [k * 2.0, -k * 2.0]):
				var p := Vector2(_scan_at, across)
				if p.length() * sin(half - absf(p.angle())) < EDGE_MARGIN:
					continue
				var clear := true
				for q in _spots:
					if p.distance_to(q) < ISLAND_SPACING:
						clear = false
						break
				if clear:
					_spots.append(p)
					accepted = true
					break
			k += 1
		if not accepted:
			_scan_at += 2.0
	return _spots


# The first [param count] island spots of a far cluster, from its first
# island, as (away from the platform, across): a triangular grid
# ISLAND_SPACING apart, on the side away from the platform, nearest
# first (then the furthest out, then one side before the other). Worked out
# once, out to a radius grown as needed.
static var _grid := PackedVector2Array()
static var _grid_radius := 0.0


static func _far_spots(count: int) -> PackedVector2Array:
	while _grid.size() < count:
		_grid_radius += ISLAND_SPACING * 4.0
		var row := ISLAND_SPACING * sqrt(3.0) / 2.0
		var points := []
		for j in int(_grid_radius / row) + 1:
			var shift := 0.5 * (j % 2)
			var reach := int(_grid_radius / ISLAND_SPACING) + 1
			for i in range(-reach, reach + 1):
				var p := Vector2(j * row, (i + shift) * ISLAND_SPACING)
				if p.length() <= _grid_radius + 0.01:
					points.append(p)
		points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			if absf(a.length() - b.length()) > 0.01:
				return a.length() < b.length()
			if absf(a.x - b.x) > 0.01:
				return a.x > b.x
			return a.y > b.y)
		_grid = PackedVector2Array(points)
	return _grid


static func _key(project: Dictionary) -> String:
	var repo: String = project.get("repo", "")
	return repo if not repo.is_empty() else str(project.get("path", ""))


## The cluster made automatically for this repository, or "". Sessions
## of it put elsewhere by hand don't count.
func _cluster_for(key: String) -> String:
	for id in _clusters:
		if _clusters[id]["key"] == key:
			return id
	return ""


func _new_cluster(base: String, key: String) -> String:
	var names := {}
	for c in _clusters.values():
		names[c["name"]] = true
	if base.is_empty():
		base = "Cluster"
	var cluster_name := base
	var n := 2
	while names.has(cluster_name):
		cluster_name = "%s %d" % [base, n]
		n += 1
	var slots := {}
	for c in _clusters.values():
		slots[c["slot"]] = true
	var slot := 0
	while slots.has(slot):
		slot += 1
	var id := str(_next_id)
	_next_id += 1
	_clusters[id] = {"name": cluster_name, "slot": slot, "sessions": {}, "key": key}
	return id
