class_name Hotbar
extends CanvasLayer
## The hotbar (C15; user's design, 2026-10-27): the tools you carry, in a
## row of slots at the bottom of the screen. The number keys pick a slot,
## the mouse wheel steps through them (round from the last to the first).
## Slot 1 is empty hands; the fishing rod (D01) is slot 2, the bug net
## comes later. It shows when you switch and fades out after a moment, and
## does nothing while you don't have the controls (the chat, a menu, the
## sessions ring, the map).

signal held_changed(tool: String)

## The tools, in slot order, and what each slot says (in English: shown
## translated under the context "hotbar", C16).
const TOOLS: Array[String] = ["hands", "rod"]
const NAMES := {"hands": "Hands", "rod": "Rod"} # TRANSLATE: hotbar
## Number keys 1 to 9 are bound (hotbar_1 to hotbar_9); one past the last
## tool does nothing.
const SLOT_KEYS := 9

## Seconds it stays fully shown after a switch, then fading out.
const SHOW_TIME := 1.5
const FADE_TIME := 0.5

## A slot's size and the gap between slots, pixels; the row's distance
## from the bottom of the screen.
const SLOT := 56.0
const GAP := 6.0
const BOTTOM := 28.0

const FILL := Color(0, 0, 0, 0.35)
const LINE := Color(1, 1, 1, 0.45)
const HELD := Color(1, 1, 1, 0.95)
const OUTLINE := Color(0, 0, 0, 0.6)

var player: Player
## The text it painted last, in order (for tests; C16).
var drawn := PackedStringArray()

var _held := 0
# Seconds since the last switch; starts past the fade, so it starts hidden.
var _since := SHOW_TIME + FADE_TIME
var _canvas := Control.new()


func _ready() -> void:
	layer = 1
	_canvas.name = "Draw"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_paint)
	add_child(_canvas)


## The tool in hand ("hands" when none).
func held_tool() -> String:
	return TOOLS[_held]


## The slot in hand, from 0.
func held_slot() -> int:
	return _held


## Takes the tool in [param slot] (from 0) in hand and shows the hotbar.
## A slot with no tool does nothing.
func select(slot: int) -> void:
	if slot < 0 or slot >= TOOLS.size():
		return
	_since = 0.0
	if slot == _held:
		return
	_held = slot
	held_changed.emit(held_tool())


## Steps to the next slot (1) or the one before (-1), round the ends.
func step(by: int) -> void:
	select(posmod(_held + by, TOOLS.size()))


## How visible the hotbar is, 0 hidden to 1.
func shown() -> float:
	if player == null or not player.controls_enabled:
		return 0.0
	return clampf(1.0 - (_since - SHOW_TIME) / FADE_TIME, 0.0, 1.0)


func _process(delta: float) -> void:
	_since += delta
	_canvas.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.controls_enabled:
		return
	if event.is_action_pressed("hotbar_next"):
		step(1)
	elif event.is_action_pressed("hotbar_previous"):
		step(-1)
	else:
		var slot := _slot_key(event)
		if slot < 0:
			return
		select(slot)
	get_viewport().set_input_as_handled()


# The slot (from 0) whose number key [param event] presses, or -1.
static func _slot_key(event: InputEvent) -> int:
	for i in SLOT_KEYS:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			return i
	return -1


func _paint() -> void:
	drawn.clear()
	var alpha := shown()
	if alpha <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var width := TOOLS.size() * SLOT + (TOOLS.size() - 1) * GAP
	var left := (_canvas.size.x - width) / 2.0
	var top := _canvas.size.y - BOTTOM - SLOT
	for i in TOOLS.size():
		var rect := Rect2(left + i * (SLOT + GAP), top, SLOT, SLOT)
		var held := i == _held
		_canvas.draw_rect(rect, _faded(FILL, alpha))
		_canvas.draw_rect(rect, _faded(HELD if held else LINE, alpha), false, 2.5 if held else 1.0)
		var number := str(i + 1)
		var corner := rect.position + Vector2(5, 15)
		_canvas.draw_string_outline(font, corner, number, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, _faded(OUTLINE, alpha))
		_canvas.draw_string(font, corner, number, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _faded(HELD, alpha))
		var name := tr(NAMES[TOOLS[i]], "hotbar")
		drawn.append(name)
		var at := rect.position + Vector2(0, SLOT / 2.0 + 9)
		_canvas.draw_string_outline(font, at, name, HORIZONTAL_ALIGNMENT_CENTER, SLOT, 14, 4, _faded(OUTLINE, alpha))
		_canvas.draw_string(font, at, name, HORIZONTAL_ALIGNMENT_CENTER, SLOT, 14, _faded(HELD if held else LINE, alpha))


static func _faded(c: Color, alpha: float) -> Color:
	return Color(c, c.a * alpha)
