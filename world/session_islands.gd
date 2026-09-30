class_name SessionIslands
extends Node3D
## One island per live session, each with its orchestrator bound to the
## session. A stand-in for W04 (rise / sink) and W05 (archipelagos): an
## island appears once its session is up and goes when it ends, and
## islands sit on rings around the spawn platform, reusing free spots.

signal island_added(session_id: String, island: Island, orchestrator: Orchestrator)
## Emitted just before the island is taken away and freed.
signal island_removed(session_id: String, island: Island)

const ORCHESTRATOR := preload("res://agents/orchestrator/orchestrator.tscn")
## Distance from the platform to the first ring of islands, and between
## rings, metres. An island's mesh reaches about 67 m from its centre.
const RING_SPACING := 180.0
const PER_RING := 6

var store: SessionStore

var _islands := {} # session id → Island
var _slots := {} # slot number → session id


## Call once, before anything else that listens for new sessions (see
## SessionPost.setup).
func setup(p_store: SessionStore) -> void:
	store = p_store
	store.session_added.connect(_on_added)
	store.session_removed.connect(_on_removed)


func island(session_id: String) -> Island:
	return _islands.get(session_id)


func orchestrator(session_id: String) -> Orchestrator:
	var i := island(session_id)
	return i.get_node("Orchestrator") if i else null


## Where the player lands on a session's island: 6 m in front of the
## orchestrator, on the flat middle.
func arrival_point(session_id: String) -> Vector3:
	var i := island(session_id)
	return i.global_position + Vector3(0.0, i.height_at(0.0, 6.0) + 0.1, 6.0)


## The session whose island is under [param point], or "".
func session_at(point: Vector3) -> String:
	for id in _islands:
		var i: Island = _islands[id]
		var d := Vector2(point.x - i.global_position.x, point.z - i.global_position.z)
		if d.length() < i.generator.radius * 2.0:
			return id
	return ""


static func slot_position(slot: int) -> Vector3:
	var ring := slot / PER_RING
	# Each ring is turned half a step so islands don't line up behind each other.
	var angle := (slot % PER_RING + ring * 0.5) * TAU / PER_RING
	var r := RING_SPACING * (ring + 1)
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)


func _on_added(id: String, _created: bool) -> void:
	var slot := 0
	while _slots.has(slot):
		slot += 1
	var i := Island.new()
	i.name = "Island%d" % slot
	i.position = slot_position(slot)
	add_child(i) # generates the island
	var o: Orchestrator = ORCHESTRATOR.instantiate()
	o.name = "Orchestrator"
	o.session_id = id
	o.position = Vector3(0.0, i.height_at(0.0, 0.0), 0.0)
	i.add_child(o)
	i.set_meta("slot", slot)
	_islands[id] = i
	_slots[slot] = id
	island_added.emit(id, i, o)


func _on_removed(id: String, _reason: String) -> void:
	var i: Island = _islands.get(id)
	if i == null:
		return
	# Still listed while the signal runs, so session_at() can find it.
	island_removed.emit(id, i)
	_islands.erase(id)
	_slots.erase(i.get_meta("slot"))
	i.queue_free()
