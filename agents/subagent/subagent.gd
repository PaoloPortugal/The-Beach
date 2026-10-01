class_name Subagent
extends Node3D
## A subagent (A02): a smaller placeholder orchestrator at a little PC,
## until the agents' look is decided (open question 7). Faces +z, with its
## PC in front of it. It pops in at its PC; when done it gets up and walks
## in a straight line to whoever called it with a paper over its head, and
## shrinks away there. Nothing of it collides but the PC, and the walk
## ignores the terrain's shape apart from standing on it.

## Emitted once it has shrunk away, just before it is freed.
signal gone(subagent: Subagent)

const POP_TIME := 0.3
const WALK_SPEED := 3.0
## Stops this far from where it is walking to.
const ARRIVE_DISTANCE := 1.4
## A walk that takes longer than this ends where it is.
const MAX_WALK_TIME := 20.0

var session_id := ""
var agent_id := ""
## Where it sits: its slot around the orchestrator (A04).
var slot := -1
## Ground height at a point in the parent's space: (x, z) → y. The
## parent must be a Node3D.
var ground := func(_x: float, _z: float) -> float: return 0.0

var _walk_to := Callable() # → global position it is walking to
var _walk_time := 0.0
var _leaving := false
var _tween: Tween
var _timer: SceneTreeTimer

@onready var _worker: Node3D = $Worker
@onready var _pc: Node3D = $Pc
@onready var _paper: Node3D = $Worker/Paper
@onready var _marker: AgentStateMarker = $Worker/StateMarker


func _ready() -> void:
	set_physics_process(false)


## Pops in at its PC (again, if it was leaving).
func appear() -> void:
	_stop()
	_leaving = false
	_worker.transform = Transform3D.IDENTITY
	_paper.visible = false
	_pc.visible = true
	_pc.process_mode = Node.PROCESS_MODE_INHERIT
	_worker.scale = Vector3.ONE * 0.01
	_pc.scale = Vector3.ONE * 0.01
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_worker, "scale", Vector3.ONE, POP_TIME)
	_tween.tween_property(_pc, "scale", Vector3.ONE, POP_TIME)


func show_state(state: String) -> void:
	_marker.show_state(state)


## True once it has started leaving (walking back, or about to shrink).
func is_leaving() -> bool:
	return _leaving


## Where its body is now (it moves while walking back).
func worker_position() -> Vector3:
	return _worker.global_position


## Its marker's state (see [method AgentStateMarker.shown]).
func shown_state() -> String:
	return _marker.shown()


## Done: gets up and walks to [param target] (a Callable returning a
## global position, followed as it moves) with its report, then shrinks
## away. Its PC goes at once.
func report_to(target: Callable) -> void:
	_stop()
	_leaving = true
	_paper.visible = true
	_tween = create_tween()
	_tween.tween_property(_pc, "scale", Vector3.ONE * 0.01, POP_TIME)
	_tween.tween_callback(func() -> void: _pc.visible = false)
	_pc.process_mode = Node.PROCESS_MODE_DISABLED # its collision goes too
	_walk_to = target
	_walk_time = 0.0
	set_physics_process(true)


## Stays where it is for [param seconds], then shrinks away with its PC
## (an error: its marker shows why meanwhile).
func leave_after(seconds: float) -> void:
	_stop()
	_leaving = true
	_timer = get_tree().create_timer(seconds)
	_timer.timeout.connect(_vanish)


func _physics_process(delta: float) -> void:
	_walk_time += delta
	var target: Vector3 = _walk_to.call()
	var from := _worker.global_position
	var to := Vector2(target.x - from.x, target.z - from.z)
	# The last step lands on ARRIVE_DISTANCE only to float precision, maybe
	# a hair short, so arriving allows a centimetre.
	if to.length() <= ARRIVE_DISTANCE + 0.01 or _walk_time > MAX_WALK_TIME:
		set_physics_process(false)
		_vanish()
		return
	var step := to.normalized() * minf(WALK_SPEED * delta, to.length() - ARRIVE_DISTANCE)
	var parent: Node3D = get_parent()
	var at := parent.to_local(from + Vector3(step.x, 0.0, step.y))
	at.y = ground.call(at.x, at.z)
	_worker.global_position = parent.to_global(at)
	_worker.global_rotation = Vector3(0.0, atan2(to.x, to.y), 0.0)


func _vanish() -> void:
	_stop()
	_leaving = true
	_tween = create_tween().set_parallel()
	_tween.tween_property(_worker, "scale", Vector3.ONE * 0.01, POP_TIME)
	if _pc.visible:
		_tween.tween_property(_pc, "scale", Vector3.ONE * 0.01, POP_TIME)
	_tween.chain().tween_callback(func() -> void:
		gone.emit(self)
		queue_free())


func _stop() -> void:
	set_physics_process(false)
	if _tween:
		_tween.kill()
		_tween = null
	if _timer and _timer.timeout.is_connected(_vanish):
		_timer.timeout.disconnect(_vanish)
		_timer = null
