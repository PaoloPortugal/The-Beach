class_name SessionIslands
extends Node3D
## One island per live session, each with its orchestrator bound to the
## session and its subagents (IslandAgents). Islands are placed by
## cluster (W05, [SessionClusters]). A new session's island rises out of
## the sea (W04); one already running when the world connects is simply
## there. Until the player has been on a new session's island, a beacon
## stands over it (and [NewIslandPointers] points to it). When a session
## ends its orchestrator and agents go at once; the empty island stays
## while the player is on it (or on one of its bridges), then sinks and is
## freed. Bridges (W06, [BridgeNetwork]) join a cluster's islands and the
## spawn platform once an island is up, and go when it starts sinking.

signal island_added(session_id: String, island: Island, orchestrator: Orchestrator)
## A new session's island is up (at once for one already running).
signal island_risen(session_id: String)

const ORCHESTRATOR := preload("res://agents/orchestrator/orchestrator.tscn")
## Where an island starts rising from and sinks to: low enough that the
## opaque sea hides all of it (its dunes reach about 3.2 m).
const SUNK_Y := -8.0
## The new-island beacon's colour: not A05's orange, which means waiting.
const NEW_COLOUR := Color(0.35, 1.0, 0.55)
## How high the beach is where a bridge meets it, metres above the water.
const BRIDGE_END_HEIGHT := 0.5

var store: SessionStore
## Which cluster each session is in, and where its island goes.
var clusters := SessionClusters.new()
## The bridges between islands, and to the platform (a hub added by the
## world).
var bridges := BridgeNetwork.new()
## Whoever has to leave an ended session's island before it sinks.
var player: Node3D
## Seconds to rise and to sink.
var rise_time := 3.0
var sink_time := 4.0

var _islands := {} # session id → Island
var _rising := {} # session id → its Tween
var _left := {} # Island of an ended session → its cluster hold
var _sinking := {} # Island → true, of those in _left
var _unvisited := {} # session id → its new-island AttentionBeacon
var _cluster := {} # Island → its cluster id, while it's in the world
var _far := {} # Island → true, for one in a far spot (no bridges)


func _ready() -> void:
	bridges.name = "Bridges"
	add_child(bridges)


## Call once, before anything else that listens for new sessions (see
## SessionsMenu.setup).
func setup(p_store: SessionStore) -> void:
	store = p_store
	store.session_added.connect(_on_added)
	store.session_removed.connect(_on_removed)


func island(session_id: String) -> Island:
	return _islands.get(session_id)


func orchestrator(session_id: String) -> Orchestrator:
	var i := island(session_id)
	return i.get_node("Orchestrator") if i else null


## The agents on a session's island (subagents, state markers), or null.
func agents(session_id: String) -> IslandAgents:
	var i := island(session_id)
	return i.get_node("Agents") if i else null


## Whether a session's island is still rising.
func is_rising(session_id: String) -> bool:
	return _rising.has(session_id)


## New sessions whose islands the player hasn't been on yet.
func unvisited() -> Array[String]:
	var out: Array[String] = []
	out.assign(_unvisited.keys())
	return out


## The islands of a cluster in the world: live, empty or sinking.
func cluster_islands(cluster_id: String) -> Array[Island]:
	var out: Array[Island] = []
	for i: Island in _cluster:
		if _cluster[i] == cluster_id and is_instance_valid(i):
			out.append(i)
	return out


## Every island in the world: live, empty or sinking (W06's big map).
func all_islands() -> Array[Island]:
	var out: Array[Island] = []
	for i: Island in _cluster:
		if is_instance_valid(i):
			out.append(i)
	return out


## The cluster an island in the world belongs to, or "".
func cluster_of(i: Island) -> String:
	return _cluster.get(i, "")


## The live sessions with an island.
func session_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_islands.keys())
	return out


## The cluster of the island nearest [param point], or "".
func nearest_cluster(point: Vector3) -> String:
	var found := ""
	var best := INF
	for i: Island in _cluster:
		if is_instance_valid(i) and _distance(i, point) < best:
			found = _cluster[i]
			best = _distance(i, point)
	return found


## Whether an island is in a far spot, with no bridges (W06: past 16
## clusters, or an inner cluster's 11th island).
func is_far(i: Island) -> bool:
	return _far.has(i)


## The key of an island's region in [member bridges].
static func region(i: Island) -> String:
	return "island:%d" % i.get_instance_id()


## Ended sessions' islands still in the world: waiting for the player to
## leave, or sinking.
func left_islands() -> Array[Island]:
	var out: Array[Island] = []
	out.assign(_left.keys())
	return out


## Where the player lands on a session's island: 6 m in front of the
## orchestrator, on the flat middle.
func arrival_point(session_id: String) -> Vector3:
	var i := island(session_id)
	return i.global_position + Vector3(0.0, i.height_at(0.0, 6.0) + 0.1, 6.0)


## The session whose island is under [param point] (the nearest, as a
## cluster's islands are close together), or "".
func session_at(point: Vector3) -> String:
	var found := ""
	var best := INF
	for id in _islands:
		var i: Island = _islands[id]
		var d := _distance(i, point)
		if _is_over(i, point) and d < best:
			found = id
			best = d
	return found


func _process(_delta: float) -> void:
	for id: String in _unvisited.keys():
		if player and _is_over(_islands[id], player.global_position):
			_unvisited[id].set_on(false)
			_unvisited.erase(id)
	for i: Island in _left:
		if not _sinking.has(i) and not (player and (_is_over(i, player.global_position) or bridges.on_bridge_of(region(i), player.global_position))):
			_sink(i)


func _on_added(id: String, created: bool) -> void:
	clusters.add(id, store.session(id))
	var i := Island.new()
	i.name = "Island"
	i.position = clusters.island_position(id)
	if created:
		i.position.y = SUNK_Y
	add_child(i, true) # generates the island
	var o: Orchestrator = ORCHESTRATOR.instantiate()
	o.name = "Orchestrator"
	o.session_id = id
	o.position = Vector3(0.0, i.height_at(0.0, 0.0), 0.0)
	i.add_child(o)
	var agents := IslandAgents.new()
	agents.name = "Agents"
	i.add_child(agents)
	agents.setup(store, id, i, o)
	_islands[id] = i
	_cluster[i] = clusters.cluster_of(id)
	if not clusters.is_bridged(id):
		_far[i] = true
	island_added.emit(id, i, o)
	if not created:
		_bridge(id)
		island_risen.emit(id)
		return
	# Rises with the island, from its middle.
	var beacon := AttentionBeacon.new()
	beacon.name = "NewBeacon"
	beacon.colour = NEW_COLOUR
	beacon.position = o.position
	i.add_child(beacon)
	beacon.set_on(true)
	_unvisited[id] = beacon
	# Bound to the island, so it stops if the island goes.
	var tween := i.create_tween()
	tween.tween_property(i, "position:y", 0.0, rise_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		_rising.erase(id)
		_bridge(id)
		island_risen.emit(id))
	_rising[id] = tween


func _on_removed(id: String, _reason: String) -> void:
	var i: Island = _islands.get(id)
	if i == null:
		return
	_islands.erase(id)
	if _rising.has(id):
		_rising[id].kill()
		_rising.erase(id)
	if _unvisited.has(id):
		_unvisited[id].set_on(false)
		_unvisited.erase(id)
	i.get_node("Orchestrator").queue_free()
	i.get_node("Agents").queue_free()
	_left[i] = clusters.hold(id)


func _sink(i: Island) -> void:
	_sinking[i] = true
	bridges.remove(region(i))
	var tween := i.create_tween()
	tween.tween_property(i, "position:y", SUNK_Y, sink_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		clusters.remove(_left[i])
		_left.erase(i)
		_sinking.erase(i)
		_cluster.erase(i)
		_far.erase(i)
		i.queue_free())


# A risen island joins its cluster's bridges, unless it's in a far spot.
func _bridge(id: String) -> void:
	if not clusters.is_bridged(id):
		return
	var i: Island = _islands[id]
	var reach := i.generator.radius * 1.45
	bridges.add(region(i), clusters.cluster_of(id), i.global_position, reach, func(toward: Vector3) -> Vector3:
		return _shore_point(i, toward))


# Where a bridge heading for [param toward] meets the island's beach: the
# outermost point that high, on the line from its middle.
static func _shore_point(i: Island, toward: Vector3) -> Vector3:
	var c := i.global_position
	var dir := Vector2(toward.x - c.x, toward.z - c.z).normalized()
	var r := i.generator.shore_radius(dir.x, dir.y) * 1.2
	while r > 0.0 and i.height_at(dir.x * r, dir.y * r) < BRIDGE_END_HEIGHT:
		r -= 0.25
	return c + Vector3(dir.x * r, i.height_at(dir.x * r, dir.y * r), dir.y * r)


# Whether [param point] is on or around the island: its land and shallows.
func _is_over(i: Island, point: Vector3) -> bool:
	return _distance(i, point) < i.generator.radius * 2.0


func _distance(i: Island, point: Vector3) -> float:
	return Vector2(point.x - i.global_position.x, point.z - i.global_position.z).length()
