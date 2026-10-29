class_name FishingHud
extends CanvasLayer
## Fishing's bits of screen (D01), drawn in code like the hotbar (C15)
## and placeholders like it: the cast's meter under the crosshair while
## you charge, a "!" under it while a fish bites (time to click), in a
## fight an arrow beside it on the side to push the rod (away from the
## fish's pull, fading as you hold it there), a
## short line under it ("It got away"), and the catch card ("Caught:
## Shallows fish! 34 cm", marked New on a species' first). Hidden without
## the controls (the chat, a menu, the sessions ring, the map). Its text
## is kept in English and translated as it's drawn, every frame (C16).

## The meter's size and its distance under the middle of the screen,
## pixels.
const METER := Vector2(64, 6)
const METER_BELOW := 26.0
## The bite's "!": its size, pixels.
const BITE_SIZE := 26
## The fight's arrow: how far beside the middle of the screen, pixels,
## its size at its biggest, and the push under which it's hidden (of
## [method FishFight.hint], 0 to 1).
const ARROW_OFF := 46.0
const ARROW_SIZE := 18.0
const ARROW_FROM := 0.15
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

## The text painted last frame, for tests (C16).
var drawn := PackedStringArray()

var _said := "" # in English
var _said_age := INF
var _card := {} # {species: its English name, size: cm, first: bool}
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


## The line under the crosshair now, translated, or "".
func said() -> String:
	return tr(_said) if _said_age < SAY_TIME + FADE_TIME and _said != "" else ""


## Whether the bite's "!" shows now.
func bite_mark() -> bool:
	return fishing != null and fishing.state == Fishing.State.BITE and fishing.player.controls_enabled


## The fight's arrow now: -1 (push left) to 1 (right) by how hard, 0
## hidden.
func arrow() -> float:
	if fishing == null or fishing.state != Fishing.State.FIGHT or not fishing.player.controls_enabled:
		return 0.0
	var h := fishing.fight.hint()
	return h if absf(h) >= ARROW_FROM else 0.0


## Shows the catch card. [param species_name] is the species' English
## name, translated under "fish" (C16).
func show_catch(species_name: String, size_cm: int, first: bool) -> void:
	_card = {"species": species_name, "size": size_cm, "first": first}
	_card_age = 0.0


## The catch card's lines now, translated: [the line, the size, "New" or
## ""], or [] when it isn't up.
func card_lines() -> PackedStringArray:
	if _card.is_empty() or _card_age >= CARD_TIME + FADE_TIME:
		return PackedStringArray()
	# No article picked in code (C16, user's 2026-10-29).
	return PackedStringArray([
		Languages.fill(tr("Caught: {species}!"), {"species": tr(_card["species"], "fish")}),
		Languages.fill(tr("{n} cm"), {"n": Languages.number(str(_card["size"]))}),
		# TRANSLATORS: on the catch card, the first of its species.
		tr("New", "catch") if _card["first"] else ""])


## The catch card's text now ("Caught: Shallows fish! 34 cm", " · New" on
## a first), or "".
func card_text() -> String:
	var lines := card_lines()
	if lines.is_empty():
		return ""
	return "%s %s%s" % [lines[0], lines[1], " · " + lines[2] if lines[2] != "" else ""]


func _process(delta: float) -> void:
	_said_age += delta
	_card_age += delta
	_canvas.queue_redraw()


func _paint() -> void:
	drawn.clear()
	if fishing == null or fishing.player == null or not fishing.player.controls_enabled:
		return
	var font := ThemeDB.fallback_font
	var middle := _canvas.size / 2.0
	if fishing.state == Fishing.State.CHARGING:
		var rect := Rect2(middle + Vector2(-METER.x / 2.0, METER_BELOW), METER)
		_canvas.draw_rect(rect.grow(1.5), FILL)
		_canvas.draw_rect(Rect2(rect.position, Vector2(METER.x * fishing.charge, METER.y)), LINE)
	if bite_mark():
		drawn.append("!")
		_text(font, middle + Vector2(0, METER_BELOW + 8), "!", BITE_SIZE, NEW, 1.0)
	var push := arrow()
	if push != 0.0:
		_arrow(middle, push)
	var alpha := _alpha(_said_age, SAY_TIME)
	if alpha > 0.0 and _said != "":
		drawn.append(said())
		_text(font, middle + Vector2(0, METER_BELOW + 30), said(), 15, LINE, alpha)
	alpha = _alpha(_card_age, CARD_TIME)
	var card := card_lines()
	if alpha > 0.0 and not card.is_empty():
		for line in card:
			if line != "":
				drawn.append(line)
		var top := _canvas.size.y * CARD_AT
		var width := 360.0
		var height := 70.0 if card[2] == "" else 92.0
		var rect := Rect2(middle.x - width / 2.0, top, width, height)
		_canvas.draw_rect(rect, Color(FILL, FILL.a * alpha))
		_canvas.draw_rect(rect, Color(LINE, 0.45 * alpha), false, 1.0)
		_text(font, Vector2(middle.x, top + 30), card[0], 20, LINE, alpha)
		_text(font, Vector2(middle.x, top + 56), card[1], 17, LINE, alpha)
		if card[2] != "":
			_text(font, Vector2(middle.x, top + 80), card[2], 16, NEW, alpha)


# The fight's arrow beside [param middle], pointing the way of [param
# push] (its sign), bigger and stronger the harder.
func _arrow(middle: Vector2, push: float) -> void:
	var side := signf(push)
	var t := clampf((absf(push) - ARROW_FROM) / (1.0 - ARROW_FROM), 0.0, 1.0)
	var size := ARROW_SIZE * lerpf(0.6, 1.0, t)
	var alpha := lerpf(0.45, 1.0, t)
	var at := middle + Vector2(side * ARROW_OFF, 0)
	var points := PackedVector2Array([at + Vector2(side * size * 0.6, 0), at + Vector2(-side * size * 0.4, -size * 0.55), at + Vector2(-side * size * 0.4, size * 0.55)])
	_canvas.draw_colored_polygon(points, Color(LINE, LINE.a * alpha))
	points.append(points[0])
	_canvas.draw_polyline(points, Color(OUTLINE, OUTLINE.a * alpha), 2.0, true)


# Text centred on [param at]'s x, its baseline at [param at]'s y.
func _text(font: Font, at: Vector2, text: String, size: int, colour: Color, alpha: float) -> void:
	var left := Vector2(at.x - 400.0, at.y)
	_canvas.draw_string_outline(font, left, text, HORIZONTAL_ALIGNMENT_CENTER, 800.0, size, 4, Color(OUTLINE, OUTLINE.a * alpha))
	_canvas.draw_string(font, left, text, HORIZONTAL_ALIGNMENT_CENTER, 800.0, size, Color(colour, colour.a * alpha))


# 1 while shown, fading to 0 after [param time].
static func _alpha(age: float, time: float) -> float:
	return clampf(1.0 - (age - time) / FADE_TIME, 0.0, 1.0)
