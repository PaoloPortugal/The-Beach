class_name Player
extends CharacterBody3D
## First-person player (W03): walk, sprint and jump, with coyote time and
## jump buffering so parkour stays possible later. In deep water it swims
## (W08): toward where you look, Space up, Ctrl down, floating at the
## surface or leaping out of it when you come up fast; out of the water
## only by walking up a beach. Holding Ctrl on land crouches, and slides
## when you crouch at a run (W11). A click captures the mouse when it's
## free (Esc opens the settings menu, which frees it: C10).

@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var jump_velocity := 5.5
@export var ground_accel := 50.0
@export var air_accel := 12.0
## Radians per pixel of mouse movement: the settings' sensitivity (C10)
## times BASE_SENSITIVITY.
@export var mouse_sensitivity := BASE_SENSITIVITY
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
## Crouching (W11): the body's height and the eyes', and walking speed.
@export var crouch_height := 1.1
@export var crouch_eye_height := 0.95
@export var crouch_speed := 2.5
## Seconds the eyes take to go down or up.
@export var crouch_ease := 0.15
## Sliding (W11): crouching on the ground at least this fast slides.
@export var slide_min_speed := 6.5
## The burst a slide starts with, m/s; a slide never starts slower than
## you were going.
@export var slide_speed := 11.0
## How quickly a slide slows on flat ground, m/s²: from the burst to
## crouching speed in about 1 s.
@export var slide_friction := 8.5
## How strongly slopes speed a slide up or slow it down: gravity along the
## slope times this, so downhill outweighs the friction from about 13°.
@export var slide_gravity_scale := 4.0
## No slide goes faster than this, m/s, however long the slope.
@export var slide_max_speed := 20.0
## How quickly you can steer a slide towards where you move, radians/s.
@export var slide_turn := 1.2
## Seconds on the ground after a slide before the next one gets a burst.
@export var slide_cooldown := 0.5

## The water level (W02).
const WATER_Y := 0.0
## Ground facing up at least this much (about 70° from flat) is a slope you
## can swim up and stand on from the water, not a wall.
const SLOPE_NORMAL := 0.35
const BASE_SENSITIVITY := 0.0025
const STAND_HEIGHT := 1.8
const STAND_EYE_HEIGHT := 1.6

var spawn_point := Vector3.ZERO
## Off while something else has the keyboard and mouse (the chat, C01):
## no walking, jumping or looking, and a click doesn't capture the mouse.
var controls_enabled := true
## In the water and swimming, not walking.
var swimming := false
## Carried by something else (W10's zipline), which moves the player:
## no walking, falling or swimming, but you can still look round.
var riding := false
## Crouched (W11): holding Ctrl, or still under something too low to stand.
var crouching := false
## Sliding on the ground after crouching at a run (W11).
var sliding := false

var _jump := JumpAssist.new()
# Swimming touched sloping ground on its last move (W08).
var _grounded := false
# Holding Ctrl to crouch; kept while the controls are off.
var _want_crouch := false
# In the air from a slide (a slide jump or off an edge): the speed is kept
# rather than slowed to walking or sprinting speed.
var _momentum := false
# Time on the ground left before a slide gets its burst again.
var _slide_wait := 0.0

@onready var _head: Node3D = $Head
@onready var _body: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_body.shape = _body.shape.duplicate() # its height changes when crouching


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		rotate_y(-event.screen_relative.x * mouse_sensitivity)
		_head.rotation.x = clampf(_head.rotation.x - event.screen_relative.y * mouse_sensitivity, -PI / 2 + 0.01, PI / 2 - 0.01)
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
	if controls_enabled:
		_want_crouch = Input.is_action_pressed("crouch")
	# In the water Ctrl swims down instead.
	_set_crouching(_want_crouch and not swimming)
	_head.position.y = move_toward(_head.position.y, crouch_eye_height if crouching else STAND_EYE_HEIGHT,
			(STAND_EYE_HEIGHT - crouch_eye_height) / crouch_ease * delta)
	if swimming:
		sliding = false
		_momentum = false
		_swim(delta, depth)
		return
	_grounded = false
	var on_floor := is_on_floor()
	if not on_floor:
		velocity += get_gravity() * delta
	var horizontal := Vector2(velocity.x, velocity.z)
	if on_floor:
		_momentum = false
		if not sliding:
			_slide_wait = maxf(_slide_wait - delta, 0.0)
		if crouching and not sliding and horizontal.length() >= slide_min_speed:
			sliding = true
			if _slide_wait <= 0.0:
				horizontal = horizontal.normalized() * maxf(horizontal.length(), slide_speed)
	if sliding and (not crouching or not on_floor):
		_end_slide(not on_floor)
	var jump_pressed := controls_enabled and Input.is_action_just_pressed("jump")
	if _jump.step(delta, on_floor, jump_pressed):
		velocity.y = jump_velocity
		if sliding:
			_end_slide(true) # a slide jump keeps the slide's speed

	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish3 := global_basis * Vector3(input.x, 0.0, input.y)
	var wish := Vector2(wish3.x, wish3.z)
	if sliding:
		horizontal = _slide(delta, horizontal, wish)
	else:
		var speed := walk_speed
		if crouching:
			speed = crouch_speed
		elif Input.is_action_pressed("sprint"):
			speed = sprint_speed
		var target := wish * speed
		if _momentum:
			# Steer but don't slow: towards where you move at the speed you have.
			target = wish.normalized() * maxf(horizontal.length(), speed) if wish != Vector2.ZERO else horizontal
		horizontal = horizontal.move_toward(target, (ground_accel if on_floor else air_accel) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	move_and_slide()


# A slide's speed this frame: friction slows it, slopes speed it up or slow
# it more, and it turns a little towards where you move. It ends at
# crouching speed.
func _slide(delta: float, horizontal: Vector2, wish: Vector2) -> Vector2:
	var n := get_floor_normal()
	# Gravity along the slope, its horizontal part.
	var downhill := Vector2(n.x, n.z) * n.y * get_gravity().length() * slide_gravity_scale
	var speed := horizontal.length()
	var along := horizontal / speed if speed > 0.0 else Vector2.ZERO
	if wish != Vector2.ZERO and along != Vector2.ZERO:
		var turn := clampf(along.angle_to(wish), -slide_turn * delta, slide_turn * delta)
		horizontal = horizontal.rotated(turn)
	horizontal += downhill * delta
	speed = horizontal.length()
	speed = minf(maxf(speed - slide_friction * delta, 0.0), slide_max_speed)
	if speed <= crouch_speed:
		_end_slide(false)
		return horizontal.normalized() * crouch_speed if wish != Vector2.ZERO else Vector2.ZERO
	return horizontal.normalized() * speed


func _end_slide(airborne: bool) -> void:
	sliding = false
	_momentum = airborne
	_slide_wait = slide_cooldown


# Crouches or stands up, if there's room above to stand.
func _set_crouching(want: bool) -> void:
	if want == crouching:
		return
	var capsule := _body.shape as CapsuleShape3D
	if not want and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - capsule.height)):
		return # something low above: stay down
	crouching = want
	capsule.height = crouch_height if want else STAND_HEIGHT
	_body.position.y = capsule.height / 2.0


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
	sliding = false
	_momentum = false
