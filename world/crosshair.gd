class_name Crosshair
extends CanvasLayer
## The crosshair (C11; user's design, 2026-10-12): a small ring in the
## middle of the screen that grows when you look at something you can use
## and are near enough ([Interactable]), with what E does under it ("E
## Talk"). E acts on that thing and nothing else. Shown while you have the
## controls (not in the chat, a menu, the sessions ring or the map); the
## settings' Game tab can hide the ring, not the aiming or the hint.

## The ring's radius at rest and grown, pixels.
const REST := 5.5
const GROWN := 11.0
## How long it takes to grow or shrink, seconds.
const GROW_TIME := 0.1

const LINE := Color(1, 1, 1, 0.9)
const OUTLINE := Color(0, 0, 0, 0.6)

var player: Player
## Whether the ring shows (the setting); the hint shows either way.
var ring_on := true

var _target: Interactable
var _grow := 0.0
var _canvas := Control.new()


func _ready() -> void:
	layer = 1
	_canvas.name = "Draw"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_paint)
	add_child(_canvas)


## What the crosshair is on, or null.
func target() -> Interactable:
	return _target


## The hint shown under the ring, or "".
func hint_text() -> String:
	if _target == null or not shown():
		return ""
	return "%s  %s" % [_key_name(), _target.hint]


## Whether the crosshair shows at all (you have the controls).
func shown() -> bool:
	return player != null and player.controls_enabled


## How far the ring has grown, 0 at rest to 1.
func grown() -> float:
	return _grow


func _physics_process(_delta: float) -> void:
	_target = _pick()


func _process(delta: float) -> void:
	var goal := 1.0 if _target != null and shown() else 0.0
	_grow = move_toward(_grow, goal, delta / GROW_TIME)
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or not shown():
		return
	_target = _pick()
	if _target != null:
		get_viewport().set_input_as_handled()
		_target.used.emit(player)


# The interactable nearest the middle of the view, within its reach and
# radius, with nothing in between; null if none (or riding, or without
# the controls).
func _pick() -> Interactable:
	if not shown() or player.riding:
		return null
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var from := camera.global_position
	var forward := -camera.global_basis.z
	var best: Interactable = null
	var best_angle := INF
	for node in get_tree().get_nodes_in_group("interactables"):
		var it := node as Interactable
		if it == null or not it.enabled or not it.is_visible_in_tree():
			continue
		var to := it.global_position - from
		var along := to.dot(forward)
		if along <= 0.0 or to.length() > it.reach:
			continue
		var off := (to - forward * along).length()
		if off > it.radius:
			continue
		var angle := off / along
		if angle < best_angle and _clear(from, it):
			best = it
			best_angle = angle
	return best


# Nothing but the interactable's own owner's colliders in the way.
func _clear(from: Vector3, it: Interactable) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, it.global_position)
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit["collider"] as Node
	var owner_node := it.get_parent()
	return collider != null and owner_node != null and (collider == owner_node or owner_node.is_ancestor_of(collider))


# The key E is bound to, as the keyboard's layout names it.
static func _key_name() -> String:
	for event in InputMap.action_get_events("interact"):
		var key := event as InputEventKey
		if key:
			var code := key.keycode
			if code == KEY_NONE:
				# A physical key is named as on a US keyboard where the
				# display server can't map it (headless).
				code = key.physical_keycode if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
			return OS.get_keycode_string(code)
	return "E"


func _paint() -> void:
	if not shown():
		return
	var c := _canvas.size / 2.0
	if ring_on:
		var r := lerpf(REST, GROWN, smoothstep(0.0, 1.0, _grow))
		_canvas.draw_arc(c, r, 0.0, TAU, 32, OUTLINE, 3.5, true)
		_canvas.draw_arc(c, r, 0.0, TAU, 32, LINE, 1.5, true)
	var text := hint_text()
	if not text.is_empty():
		var font := ThemeDB.fallback_font
		var width := 400.0
		var at := c + Vector2(-width / 2.0, GROWN + 26.0)
		_canvas.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 18, 6, OUTLINE)
		_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, 18, LINE)
