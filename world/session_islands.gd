class_name SessionIslands
extends Node3D
## One island per live session, each with its orchestrator bound to the
## session and its subagents (IslandAgents). Islands are placed by
## cluster (W05, [SessionClusters]). A new session's island rises out of
## the sea (W04); one already running when the world connects is simply
## there. Until the player has been on a new session's island, a beacon
## stands over it (and [NewIslandPointers] points to it). When a session
## ends its orchestrator and agents go at once; the empty island stays
## while the player is on it, then sinks and is freed.

signal island_added(session_id: String, island: Island, orchestrator: Orchestrator)
## A new session's island is up (at once for one already running).
signal island_risen(session_id: String)

const ORCHESTRATOR := preload("res://agents/orchestrator/orchestrator.tscn")
## Where an island starts rising from and sinks to: low enough that the
## opaque sea hides all of it (its dunes reach about 3.2 m).
const SUNK_Y := -8.0
## The new-island beacon's colour: not A05's orange, which means waiting.
const NEW_COLOUR := Color(0.35, 1.0, 0.55)

var store: SessionStore
## Which cluster each session is in, and where its island goes.
var clusters := SessionClusters.new()
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
		if not _sinking.has(i) and not (player and _is_over(i, player.global_position)):
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
	island_added.emit(id, i, o)
	if not created:
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
	var tween := i.create_tween()
	tween.tween_property(i, "position:y", SUNK_Y, sink_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.finished.connect(func() -> void:
		clusters.remove(_left[i])
		_left.erase(i)
		_sinking.erase(i)
		i.queue_free())


# Whether [param point] is on or around the island: its land and shallows.
func _is_over(i: Island, point: Vector3) -> bool:
	return _distance(i, point) < i.generator.radius * 2.0


func _distance(i: Island, point: Vector3) -> float:
	return Vector2(point.x - i.global_position.x, point.z - i.global_position.z).length()
