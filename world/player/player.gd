class_name Player
extends CharacterBody3D
## First-person player (W03): walk, sprint and jump, with coyote time and
## jump buffering so parkour stays possible later. In deep water it swims
## (W08): toward where you look, Space up, Ctrl down, floating at the
## surface or leaping out of it when you come up fast; out of the water
## only by walking up a beach. Esc frees the mouse
## and a click captures it again.

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 5.5
@export var ground_accel := 50.0
@export var air_accel := 12.0
## Radians per pixel of mouse movement.
@export var mouse_sensitivity := 0.0025
@export var swim_speed := 3.5
@export var swim_sprint_speed := 6.0
## How quickly the water brings you to the speed you're swimming at, m/s².
@export var swim_accel := 8.0
## Feet deeper than this under the water start swimming; standing on
## ground with the feet above it again stops it.
@export var swim_depth := 1.3
## Where the feet float when you're at the surface: the eyes are just
## above the waves (they reach about 0.35 m).
@export var float_depth := 1.15
## How firmly the water holds you at the surface, per second.
@export var surface_pull := 4.0
## Reaching the surface faster than this, m/s upward, leaps out of the
## water with all your speed (a dolphin jump). Above swim_speed, so only
## sprinting up breaches; swimming up at your normal speed floats.
@export var breach_speed := 4.5

## The water level (W02).
const WATER_Y := 0.0
## Ground facing up at least this much (about 70° from flat) is a slope you
## can swim up and stand on from the water, not a wall.
const SLOPE_NORMAL := 0.35

var spawn_point := Vector3.ZERO
## Off while something else has the keyboard and mouse (the chat, C01):
## no walking, jumping or looking, and a click doesn't capture the mouse.
var controls_enabled := true
## In the water and swimming, not walking.
var swimming := false
## Carried by something else (W10's zipline), which moves the player:
## no walking, falling or swimming, but you can still look round.
var riding := false

var _jump := JumpAssist.new()
# Swimming touched sloping ground on its last move (W08).
var _grounded := false

@onready var _head: Node3D = $Head


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.screen_relative.x * mouse_sensitivity)
		_head.rotation.x = clampf(_head.rotation.x - event.screen_relative.y * mouse_sensitivity, -PI / 2 + 0.01, PI / 2 - 0.01)
	elif event.is_action_pressed("ui_cancel") and captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if riding:
		return
	var depth := WATER_Y - global_position.y
	if depth > swim_depth:
		swimming = true
	elif swimming and _grounded and depth < swim_depth - 0.1:
		swimming = false
		velocity.y = minf(velocity.y, 0.0) # no hop out of the water
	if swimming:
		_swim(delta, depth)
		return
	_grounded = false
	var on_floor := is_on_floor()
	if not on_floor:
		velocity += get_gravity() * delta
	var jump_pressed := controls_enabled and Input.is_action_just_pressed("jump")
	if _jump.step(delta, on_floor, jump_pressed):
		velocity.y = jump_velocity

	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var target := global_basis * Vector3(input.x, 0.0, input.y)
	target *= sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var accel := ground_accel if on_floor else air_accel
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(target.x, target.z), accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


# Swimming: toward where the camera looks, Space up and Ctrl down, held
# at the surface rather than climbing out of it, except for a leap.
func _swim(delta: float, depth: float) -> void:
	var input := Vector2.ZERO
	var rise := 0.0
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		rise = Input.get_action_strength("jump") - Input.get_action_strength("swim_down")
	var direction := (_head.global_basis * Vector3(input.x, 0.0, input.y) + Vector3(0.0, rise, 0.0)).limit_length(1.0)
	var speed := swim_sprint_speed if controls_enabled and Input.is_action_pressed("sprint") else swim_speed
	velocity = velocity.move_toward(direction * speed, swim_accel * delta)
	# At the surface: no higher than floating, and back to it if above,
	# unless you come up fast and away from the ground: then you leap out
	# with all your speed and gravity brings you back.
	if depth < float_depth:
		if velocity.y > breach_speed and not _grounded:
			swimming = false
		else:
			velocity.y = minf(velocity.y, (depth - float_depth) * surface_pull)
	move_and_slide()
	# Swimming into a slope (a beach) rides up it rather than sliding along
	# it, so you come out of the water there.
	_grounded = is_on_floor()
	var moving := direction.length() > 0.1
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().y > SLOPE_NORMAL:
			_grounded = true
			if moving:
				velocity.y = maxf(velocity.y, speed * 0.8)


## Puts the player at the spawn point, on the platform, out of the water.
func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
	swimming = false
