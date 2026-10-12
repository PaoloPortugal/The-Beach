class_name RingIcons
## The sessions ring's icons (W07), drawn in code: the platform's house,
## the middle's plus and one per biome (W10). PLACEHOLDERS (user's,
## 2026-10-12): flat shapes until real icons, the user's or CC0, replace
## them in the UI pass. Each is drawn on [param canvas] around [param at],
## about [param size] pixels across.

## Each biome's icon colour.
const BIOME_COLOURS := {
	Biome.Kind.BEACH: Color(0.98, 0.84, 0.5),
	Biome.Kind.FOREST: Color(0.5, 0.82, 0.42),
	Biome.Kind.MOUNTAIN: Color(0.76, 0.77, 0.82),
	Biome.Kind.SNOWY: Color(0.84, 0.94, 1.0),
	Biome.Kind.DESERT: Color(0.96, 0.66, 0.36),
}
const HOUSE_COLOUR := Color(0.98, 0.93, 0.84)
const SNOW := Color(1, 1, 1)
const DARK := Color(0.06, 0.08, 0.11)


static func biome(canvas: CanvasItem, kind: int, at: Vector2, size: float) -> void:
	var c: Color = BIOME_COLOURS.get(kind, BIOME_COLOURS[Biome.Kind.BEACH])
	match kind:
		Biome.Kind.FOREST:
			_tree(canvas, at, size, c)
		Biome.Kind.MOUNTAIN:
			_mountain(canvas, at, size, c)
		Biome.Kind.SNOWY:
			_snowflake(canvas, at, size, c)
		Biome.Kind.DESERT:
			_cactus(canvas, at, size, c)
		_:
			_palm(canvas, at, size, c)


static func house(canvas: CanvasItem, at: Vector2, size: float) -> void:
	canvas.draw_colored_polygon(_points(at, size, [Vector2(-0.44, 0.0), Vector2(0, -0.42), Vector2(0.44, 0.0)]), HOUSE_COLOUR)
	canvas.draw_rect(Rect2(at + Vector2(-0.3, -0.02) * size, Vector2(0.6, 0.4) * size), HOUSE_COLOUR)
	canvas.draw_rect(Rect2(at + Vector2(-0.08, 0.14) * size, Vector2(0.16, 0.24) * size), DARK)


static func plus(canvas: CanvasItem, at: Vector2, size: float, colour: Color) -> void:
	canvas.draw_rect(Rect2(at + Vector2(-0.35, -0.07) * size, Vector2(0.7, 0.14) * size), colour)
	canvas.draw_rect(Rect2(at + Vector2(-0.07, -0.35) * size, Vector2(0.14, 0.7) * size), colour)


## Three dots: a session still starting.
static func dots(canvas: CanvasItem, at: Vector2, size: float, colour: Color) -> void:
	for i in 3:
		canvas.draw_circle(at + Vector2((i - 1) * 0.28, 0) * size, 0.08 * size, colour)


static func _palm(canvas: CanvasItem, at: Vector2, size: float, c: Color) -> void:
	var trunk := Color(0.72, 0.52, 0.32)
	canvas.draw_polyline(_points(at, size, [Vector2(-0.04, 0.42), Vector2(0.04, 0.15), Vector2(0.06, -0.12), Vector2(0.02, -0.28)]), trunk, 0.09 * size)
	var top := at + Vector2(0.02, -0.28) * size
	# Fronds: thin triangles drooping out from the top.
	for deg in [-170.0, -135.0, -90.0, -45.0, -10.0]:
		var dir := Vector2.from_angle(deg_to_rad(deg))
		var side := dir.orthogonal() * 0.06 * size
		var tip := top + (dir * 0.42 + Vector2(0, 0.12)) * size
		canvas.draw_colored_polygon(PackedVector2Array([top + side, tip, top - side]), Color(0.42, 0.78, 0.36))
	canvas.draw_rect(Rect2(at + Vector2(-0.42, 0.38) * size, Vector2(0.84, 0.08) * size), c)


static func _tree(canvas: CanvasItem, at: Vector2, size: float, c: Color) -> void:
	canvas.draw_rect(Rect2(at + Vector2(-0.06, 0.1) * size, Vector2(0.12, 0.34) * size), Color(0.6, 0.42, 0.26))
	canvas.draw_circle(at + Vector2(-0.16, 0.02) * size, 0.2 * size, c.darkened(0.15))
	canvas.draw_circle(at + Vector2(0.16, 0.02) * size, 0.2 * size, c.darkened(0.15))
	canvas.draw_circle(at + Vector2(0, -0.14) * size, 0.27 * size, c)


static func _mountain(canvas: CanvasItem, at: Vector2, size: float, c: Color) -> void:
	canvas.draw_colored_polygon(_points(at, size, [Vector2(-0.46, 0.38), Vector2(-0.18, -0.08), Vector2(0.1, 0.38)]), c.darkened(0.25))
	canvas.draw_colored_polygon(_points(at, size, [Vector2(-0.3, 0.38), Vector2(0.08, -0.4), Vector2(0.46, 0.38)]), c)
	canvas.draw_colored_polygon(_points(at, size, [Vector2(-0.07, -0.12), Vector2(0.08, -0.4), Vector2(0.22, -0.12)]), SNOW)


static func _snowflake(canvas: CanvasItem, at: Vector2, size: float, c: Color) -> void:
	for i in 6:
		var dir := Vector2.from_angle(i * TAU / 6.0 - PI / 2.0)
		canvas.draw_line(at, at + dir * 0.42 * size, c, 0.07 * size)
		var fork := at + dir * 0.26 * size
		for turn in [-0.7, 0.7]:
			canvas.draw_line(fork, fork + dir.rotated(turn) * 0.13 * size, c, 0.05 * size)


static func _cactus(canvas: CanvasItem, at: Vector2, size: float, c: Color) -> void:
	var w := 0.15 * size
	var lines := [
		[Vector2(0, 0.4), Vector2(0, -0.36)],
		[Vector2(-0.22, 0.06), Vector2(0, 0.06)], [Vector2(-0.22, 0.06), Vector2(-0.22, -0.18)],
		[Vector2(0.22, -0.04), Vector2(0, -0.04)], [Vector2(0.22, -0.04), Vector2(0.22, -0.26)],
	]
	for l: Array in lines:
		canvas.draw_line(at + l[0] * size, at + l[1] * size, c, w)
	for end: Vector2 in [Vector2(0, -0.36), Vector2(-0.22, -0.18), Vector2(0.22, -0.26)]:
		canvas.draw_circle(at + end * size, w / 2.0, c)
	canvas.draw_rect(Rect2(at + Vector2(-0.42, 0.38) * size, Vector2(0.84, 0.08) * size), Color(0.98, 0.84, 0.5))


static func _points(at: Vector2, size: float, unit: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in unit:
		out.append(at + p * size)
	return out
