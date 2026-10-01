class_name Player
extends CharacterBody3D
## First-person player (W03): walk, sprint and jump, with coyote time and
## jump buffering so parkour stays possible later. Esc frees the mouse and
## a click captures it again.

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 5.5
@export var ground_accel := 50.0
@export var air_accel := 12.0
## Radians per pixel of mouse movement.
@export var mouse_sensitivity := 0.0025
## Feet this far under the water put the player back at the spawn point.
@export var respawn_depth := -1.2

var spawn_point := Vector3.ZERO
## Off while something else has the keyboard and mouse (the chat, C01):
## no walking, jumping or looking, and a click doesn't capture the mouse.
var controls_enabled := true

var _jump := JumpAssist.new()

@onready var _head: Node3D = $Head


func _ready() -> void:
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
	if global_position.y < respawn_depth:
		respawn()
		return
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


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO
