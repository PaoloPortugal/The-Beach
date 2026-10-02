class_name SessionIslands
extends Node3D
## One island per live session, each with its orchestrator bound to the
## session and its subagents (IslandAgents). Islands are placed by
## cluster (W05, [SessionClusters]). A stand-in for W04 (rise / sink): an
## island appears once its session is up and goes when it ends.

signal island_added(session_id: String, island: Island, orchestrator: Orchestrator)
## Emitted just before the island is taken away and freed.
signal island_removed(session_id: String, island: Island)

const ORCHESTRATOR := preload("res://agents/orchestrator/orchestrator.tscn")

var store: SessionStore
## Which cluster each session is in, and where its island goes.
var clusters := SessionClusters.new()

var _islands := {} # session id → Island


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
		var d := Vector2(point.x - i.global_position.x, point.z - i.global_position.z).length()
		if d < i.generator.radius * 2.0 and d < best:
			found = id
			best = d
	return found


func _on_added(id: String, _created: bool) -> void:
	clusters.add(id, store.session(id))
	var i := Island.new()
	i.name = "Island"
	i.position = clusters.island_position(id)
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


func _on_removed(id: String, _reason: String) -> void:
	var i: Island = _islands.get(id)
	if i == null:
		return
	# Still listed while the signal runs, so session_at() can find it.
	island_removed.emit(id, i)
	_islands.erase(id)
	clusters.remove(id)
	i.queue_free()
