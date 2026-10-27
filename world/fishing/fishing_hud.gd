class_name FishingHud
extends CanvasLayer
## Fishing's bits of screen (D01), drawn in code like the hotbar (C15)
## and placeholders like it: the cast's meter under the crosshair while
## you charge, a "!" under it while a fish bites (time to click), a
## short line under it ("It got away"), and the catch card ("You caught
## a ...! 34 cm", marked New on a species' first). Hidden without the
## controls (the chat, a menu, the sessions ring, the map).

## The meter's size and its distance under the middle of the screen,
## pixels.
const METER := Vector2(64, 6)
const METER_BELOW := 26.0
## The bite's "!": its size, pixels.
const BITE_SIZE := 26
## Seconds a line and the catch card stay up, then fading out.
const SAY_TIME := 2.0
const CARD_TIME := 3.5
const FADE_TIME := 0.4
## The card's top, as a share of the screen's height.
const CARD_AT := 0.24

const FILL := Color(0, 0, 0, 0.45)
const LINE := Color(1, 1, 1, 0.9)
const NEW := Color(1.0, 0.82, 0.3)
const OUTLINE := Color(0, 0, 0, 0.6)

var fishing: Fishing

var _said := ""
var _said_age := INF
var _card: Array[String] = [] # [the line, the size, "New" or ""]
var _card_age := INF
var _canvas := Control.new()


func _ready() -> void:
	layer = 1
	_canvas.name = "Draw"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_paint)
	add_child(_canvas)


## Shows [param text] under the crosshair for a moment.
func say(text: String) -> void:
	_said = text
	_said_age = 0.0


## The line under the crosshair now, or "".
func said() -> String:
	return _said if _said_age < SAY_TIME + FADE_TIME else ""


## Whether the bite's "!" shows now.
func bite_mark() -> bool:
	return fishing != null and fishing.state == Fishing.State.BITE and fishing.player.controls_enabled


## Shows the catch card.
func show_catch(species_name: String, size_cm: int, first: bool) -> void:
	var article := "an" if species_name.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a"
	_card = ["You caught %s %s!" % [article, species_name], "%d cm" % size_cm, "New" if first else ""]
	_card_age = 0.0


## The catch card's text now ("You caught a ...! 34 cm", " · New" on a
## first), or "".
func card_text() -> String:
	if _card.is_empty() or _card_age >= CARD_TIME + FADE_TIME:
		return ""
	return "%s %s%s" % [_card[0], _card[1], " · New" if _card[2] != "" else ""]


func _process(delta: float) -> void:
	_said_age += delta
	_card_age += delta
	_canvas.queue_redraw()


func _paint() -> void:
	if fishing == null or fishing.player == null or not fishing.player.controls_enabled:
		return
	var font := ThemeDB.fallback_font
	var middle := _canvas.size / 2.0
	if fishing.state == Fishing.State.CHARGING:
		var rect := Rect2(middle + Vector2(-METER.x / 2.0, METER_BELOW), METER)
		_canvas.draw_rect(rect.grow(1.5), FILL)
		_canvas.draw_rect(Rect2(rect.position, Vector2(METER.x * fishing.charge, METER.y)), LINE)
	if bite_mark():
		_text(font, middle + Vector2(0, METER_BELOW + 8), "!", BITE_SIZE, NEW, 1.0)
	var alpha := _alpha(_said_age, SAY_TIME)
	if alpha > 0.0 and _said != "":
		_text(font, middle + Vector2(0, METER_BELOW + 30), _said, 15, LINE, alpha)
	alpha = _alpha(_card_age, CARD_TIME)
	if alpha > 0.0 and not _card.is_empty():
		var top := _canvas.size.y * CARD_AT
		var width := 360.0
		var height := 70.0 if _card[2] == "" else 92.0
		var rect := Rect2(middle.x - width / 2.0, top, width, height)
		_canvas.draw_rect(rect, Color(FILL, FILL.a * alpha))
		_canvas.draw_rect(rect, Color(LINE, 0.45 * alpha), false, 1.0)
		_text(font, Vector2(middle.x, top + 30), _card[0], 20, LINE, alpha)
		_text(font, Vector2(middle.x, top + 56), _card[1], 17, LINE, alpha)
		if _card[2] != "":
			_text(font, Vector2(middle.x, top + 80), _card[2], 16, NEW, alpha)


# Text centred on [param at]'s x, its baseline at [param at]'s y.
func _text(font: Font, at: Vector2, text: String, size: int, colour: Color, alpha: float) -> void:
	var left := Vector2(at.x - 400.0, at.y)
	_canvas.draw_string_outline(font, left, text, HORIZONTAL_ALIGNMENT_CENTER, 800.0, size, 4, Color(OUTLINE, OUTLINE.a * alpha))
	_canvas.draw_string(font, left, text, HORIZONTAL_ALIGNMENT_CENTER, 800.0, size, Color(colour, colour.a * alpha))


# 1 while shown, fading to 0 after [param time].
static func _alpha(age: float, time: float) -> float:
	return clampf(1.0 - (age - time) / FADE_TIME, 0.0, 1.0)
