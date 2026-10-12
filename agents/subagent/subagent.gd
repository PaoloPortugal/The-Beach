class_name Subagent
extends Node3D
## A subagent (A02): a smaller placeholder orchestrator at a little PC,
## until the user's custom models come (open question 7). Faces +z, with its
## PC in front of it. It pops in at its PC; when done it stands up and
## throws its paper in an arc to whoever called it, which bobs as it
## lands, and then it shrinks away with its PC. Nothing of it collides but
## the PC.

## Emitted once it has shrunk away, just before it is freed.
signal gone(subagent: Subagent)

const POP_TIME := 0.3
## Standing up and the throw's wind-up before the paper leaves, seconds.
const STAND_TIME := 0.15
const WIND_UP := 0.2
## How long the paper flies, seconds, whatever the distance (user's,
## 2026-10-12: the report reaches the caller for real before the world
## hears of it, so it lands about 1 s later from any ring).
const FLIGHT_TIME := 0.6
## How high the arc rises over the straight line: this share of the
## distance, at least ARC_MIN metres.
const ARC_SHARE := 0.25
const ARC_MIN := 1.0
## How high a catcher bobs, metres, and for how long, seconds.
const BOB_HEIGHT := 0.12
const BOB_TIME := 0.25

var session_id := ""
var agent_id := ""
## Where it sits: its slot around the orchestrator (A04).
var slot := -1

var _catch_at := Callable() # → global position the paper flies to
var _on_caught := Callable()
var _flight := -1.0 # seconds into the paper's flight; < 0 when not flying
var _from := Vector3.ZERO
var _paper_rest: Transform3D
var _bob: Tween
var _leaving := false
var _tween: Tween
var _timer: SceneTreeTimer

@onready var _worker: Node3D = $Worker
@onready var _pc: Node3D = $Pc
@onready var _paper: Node3D = $Worker/Paper
@onready var _marker: AgentStateMarker = $Worker/StateMarker


func _ready() -> void:
	_paper_rest = _paper.transform
	set_process(false)


## Pops in at its PC (again, if it was leaving).
func appear() -> void:
	_stop()
	_leaving = false
	_worker.transform = Transform3D.IDENTITY
	_paper.visible = false
	_pc.visible = true
	_worker.scale = Vector3.ONE * 0.01
	_pc.scale = Vector3.ONE * 0.01
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_worker, "scale", Vector3.ONE, POP_TIME)
	_tween.tween_property(_pc, "scale", Vector3.ONE, POP_TIME)


func show_state(state: String) -> void:
	_marker.show_state(state)


## True once it has started leaving (throwing its report, or about to
## shrink).
func is_leaving() -> bool:
	return _leaving


## Where its body is now.
func worker_position() -> Vector3:
	return _worker.global_position


## Its marker's state (see [method AgentStateMarker.shown]).
func shown_state() -> String:
	return _marker.shown()


## Done: stands up and throws its report to [param catch_at] (a Callable
## returning a global position, followed while the paper flies), calls
## [param on_caught] as it lands, then shrinks away with its PC.
func report_to(catch_at: Callable, on_caught: Callable) -> void:
	_stop()
	_leaving = true
	_paper.visible = true
	_catch_at = catch_at
	_on_caught = on_caught
	var to := _worker.get_parent_node_3d().to_local(catch_at.call())
	var facing := atan2(to.x, to.z)
	_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_worker, "position:y", 0.08, STAND_TIME)
	_tween.parallel().tween_property(_worker, "rotation:y", facing, STAND_TIME)
	_tween.tween_property(_worker, "rotation:x", -0.35, WIND_UP * 0.6)
	_tween.tween_property(_worker, "rotation:x", 0.25, WIND_UP * 0.4)
	_tween.tween_callback(_throw)


## A short bob: a report it waited on has landed.
func bob() -> void:
	if _bob:
		_bob.kill()
	_bob = create_tween()
	_bob.tween_method(func(t: float) -> void: _worker.position.y = sin(t * PI) * BOB_HEIGHT, 0.0, 1.0, BOB_TIME)


## Where a report thrown to it lands: its head.
func catch_point() -> Vector3:
	return _worker.to_global(Vector3(0.0, 0.95, -0.12))


## Stays where it is for [param seconds], then shrinks away with its PC
## (an error: its marker shows why meanwhile).
func leave_after(seconds: float) -> void:
	_stop()
	_leaving = true
	_timer = get_tree().create_timer(seconds)
	_timer.timeout.connect(_vanish)


# Lets go of the paper: it flies on its own until it lands.
func _throw() -> void:
	_from = _paper.global_position
	_paper.top_level = true
	_paper.global_position = _from
	_flight = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_flight += delta
	var t := minf(_flight / FLIGHT_TIME, 1.0)
	var to: Vector3 = _catch_at.call()
	var arc := maxf(ARC_MIN, _from.distance_to(to) * ARC_SHARE)
	_paper.global_position = _from.lerp(to, t) + Vector3.UP * arc * 4.0 * t * (1.0 - t)
	_paper.rotate_y(delta * 9.0)
	if t >= 1.0:
		_land_paper()
		_on_caught.call()
		_vanish()


# The paper back on its head, hidden.
func _land_paper() -> void:
	set_process(false)
	_flight = -1.0
	_paper.visible = false
	_paper.top_level = false
	_paper.transform = _paper_rest


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
	if _flight >= 0.0:
		_land_paper()
	if _bob:
		_bob.kill()
		_bob = null
	if _tween:
		_tween.kill()
		_tween = null
	if _timer and _timer.timeout.is_connected(_vanish):
		_timer.timeout.disconnect(_vanish)
		_timer = null
