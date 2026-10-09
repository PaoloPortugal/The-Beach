class_name IslandAgents
extends Node3D
## The agents of one session on its island (A02, A03, A04): keeps the
## orchestrator's state marker current, and puts a subagent at a free slot
## around the orchestrator (AgentPlacement) while it works or waits. A
## done subagent walks its report back to its parent and goes; an errored
## one shows it for [member error_linger] seconds and goes. A resumed one
## comes back, to its old slot if that is still free. Subagents that
## already finished before the island appeared aren't shown.
##
## Sits at the island's origin, where the orchestrator stands.

const SUBAGENT := preload("res://agents/subagent/subagent.tscn")
## A slot this close to a prop (W10) is skipped, metres, and one on ground
## sloping more than SLOT_SLOPE between it and its PC.
const PROP_CLEAR := 1.8
const SLOT_SLOPE := 0.3

## How long an errored subagent stays at its PC, seconds.
var error_linger := 10.0

var store: SessionStore
var session_id := ""
var island: Island
var orchestrator: Orchestrator

var _subagents := {} # agent id → Subagent
var _slots := {} # slot → agent id
var _last_slot := {} # agent id → the slot it had, for a resumed one

func setup(p_store: SessionStore, p_session: String, p_island: Island, p_orchestrator: Orchestrator) -> void:
	store = p_store
	session_id = p_session
	island = p_island
	orchestrator = p_orchestrator
	store.agent_added.connect(_on_agent)
	store.agent_changed.connect(_on_agent)
	for a in store.session(session_id).get("agents", []):
		_on_agent(session_id, a["agent"])


## The subagent in the world for [param agent_id], or null.
func subagent(agent_id: String) -> Subagent:
	return _subagents.get(agent_id)


func subagent_count() -> int:
	return _subagents.size()


func _on_agent(session: String, agent_id: String) -> void:
	if session != session_id:
		return
	var a := store.agent(session_id, agent_id)
	if a.is_empty():
		return
	var state: String = a["state"]
	if a["role"] == "orchestrator":
		orchestrator.show_state(state)
		return
	var node: Subagent = _subagents.get(agent_id)
	match state:
		"working", "waiting":
			if node == null:
				node = _spawn(agent_id)
			elif node.is_leaving():
				node.appear()
			node.show_state(state)
		"done":
			if node and not node.is_leaving():
				node.show_state(state)
				var parent: String = a["parent"] if a["parent"] != null else ""
				node.report_to(func() -> Vector3: return _position_of(parent))
		"error":
			if node and not node.is_leaving():
				node.show_state(state)
				node.leave_after(error_linger)


func _spawn(agent_id: String) -> Subagent:
	var slot := _free_slot(_last_slot.get(agent_id, -1))
	var p := AgentPlacement.slot_position(slot)
	var node: Subagent = SUBAGENT.instantiate()
	node.name = "Subagent_%d" % slot
	node.session_id = session_id
	node.agent_id = agent_id
	node.slot = slot
	node.ground = island.height_at
	# Facing the orchestrator, standing on the sand; where the ground under
	# it and its PC differ, it sinks in a little rather than float.
	var inward := -p.normalized()
	var pc := p + inward * 0.45
	node.position = Vector3(p.x, minf(island.height_at(p.x, p.y), island.height_at(pc.x, pc.y)), p.y)
	node.rotation.y = atan2(inward.x, inward.y)
	node.gone.connect(_on_gone)
	add_child(node)
	node.appear()
	_subagents[agent_id] = node
	_slots[slot] = agent_id
	_last_slot[agent_id] = slot
	return node


## [param wanted] if it is free, else the first free slot on land. Slots
## in the sea, on a prop (W10's trees and rocks) or on a steep hill (W10)
## are skipped until the rings are past any shore.
func _free_slot(wanted: int) -> int:
	if wanted >= 0 and not _slots.has(wanted):
		return wanted
	var slot := 0
	while true:
		if not _slots.has(slot):
			var p := AgentPlacement.slot_position(slot)
			var past := p.length() > island.generator.radius * 1.5
			if past or _fits(p):
				return slot
		slot += 1
	return slot


# Whether a slot at [param p] is on land, clear of props and level enough.
func _fits(p: Vector2) -> bool:
	var pc := p - p.normalized() * 0.45
	var h := island.height_at(p.x, p.y)
	return h > 0.3 and absf(h - island.height_at(pc.x, pc.y)) < SLOT_SLOPE and not island.props.is_near(p, PROP_CLEAR)


## Where a subagent walks its report to: its parent subagent if that one
## is still at its PC, else the orchestrator.
func _position_of(parent: String) -> Vector3:
	var node: Subagent = _subagents.get(parent)
	if node and not node.is_leaving():
		return node.worker_position()
	return orchestrator.global_position


func _on_gone(node: Subagent) -> void:
	if _subagents.get(node.agent_id) == node:
		_subagents.erase(node.agent_id)
	_slots.erase(node.slot)
