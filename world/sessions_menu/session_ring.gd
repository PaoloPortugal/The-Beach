class_name SessionRing
extends Control
## The sessions ring (W07; user's design, 2026-10-12, after the ability
## wheel in The Legend of Zelda: Tears of the Kingdom): while Tab is held,
## the running sessions sit in a ring, each cluster's together as one arc
## (W05) with its name on the rim, "⌂ Platform" fixed at the top and a big
## ➕ in the middle. [SessionsMenu] opens and closes it and acts on what it
## points at; this draws it and works out the pointing.
##
## Pointing goes by direction from the middle, past the ➕ circle. Up to
## [constant MAX_SEGMENTS] sessions get a segment each; past that the
## busiest clusters fold into one segment each, and pointing at one a
## moment ([constant FAN_DELAY]) fans its sessions out in a small outer
## ring. A segment shows its island's biome (RingIcons, placeholders) with
## the session's state as a coloured rim, the waiting ones pulsing. A
## session still starting is a faded segment, not pointable.

## Most segments for sessions before clusters fold.
const MAX_SEGMENTS := 12
## How long a folded cluster is pointed at before it fans out, seconds.
const FAN_DELAY := 0.3
## The gap between clusters, in segments.
const GAP := 0.4
## The widest a segment is drawn, radians.
const MAX_WIDTH := deg_to_rad(64.0)
## A fanned-out session's width, radians.
const FAN_WIDTH := deg_to_rad(26.0)

const FILL := Color(0.06, 0.08, 0.11, 0.86)
const FILL_POINTED := Color(0.17, 0.22, 0.28, 0.95)
const FILL_CENTRE := Color(0.09, 0.12, 0.16, 0.92)
const TEXT := Color(0.94, 0.95, 0.97)
const TEXT_DIM := Color(1, 1, 1, 0.6)
const OUTLINE := Color(0, 0, 0, 0.8)
## How urgent each state is, for a folded cluster's rim.
const URGENCY := {"waiting": 3, "error": 2, "working": 1, "idle": 0}

var store: SessionStore
var clusters: SessionClusters
var islands: SessionIslands
var launcher: SessionLauncher
## Most segments for sessions before clusters fold (tests lower it).
var max_segments := MAX_SEGMENTS

## The segments, clockwise from the top: dictionaries with "kind"
## ("platform", "session", "fold", "starting"), "id" (a session's or a
## cluster's), "cluster", "angle" (its middle, radians clockwise from the
## top) and "width" (radians).
var _segments: Array[Dictionary] = []
## The cluster fanned out, and its sessions' segments.
var _fanned := ""
var _fan: Array[Dictionary] = []
## What is pointed at: {} for nothing, {"kind": "centre"}, or a segment.
var _pointed: Dictionary = {}
## How long the pointed fold has been pointed at, seconds.
var _fold_time := 0.0
var _pointer := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Shows the ring with nothing pointed at, the pointer in the middle.
func open() -> void:
	_fanned = ""
	_fan = []
	_pointed = {}
	_fold_time = 0.0
	visible = true
	_pointer = centre()
	refresh()


func close() -> void:
	visible = false
	_pointed = {}


## Builds the segments again from the store and the clusters.
func refresh() -> void:
	_segments = []
	var groups: Array[Array] = [[{"kind": "platform", "id": "", "cluster": ""}]]
	var folded := _folded()
	for cid in clusters.ids():
		var ids := clusters.sessions(cid).filter(func(id: String) -> bool: return store.sessions.has(id))
		if ids.is_empty():
			continue
		if cid in folded:
			groups.append([{"kind": "fold", "id": cid, "cluster": cid}])
		else:
			groups.append(ids.map(func(id: String) -> Dictionary: return {"kind": "session", "id": id, "cluster": cid}))
	if launcher != null and launcher.busy():
		groups.append([{"kind": "starting", "id": launcher.pending, "cluster": ""}])
	var count := 0
	for g in groups:
		count += g.size()
	var units := count + (GAP * groups.size() if groups.size() > 1 else 0.0)
	var unit := TAU / units
	# The platform's middle at the top.
	var at := -unit / 2.0
	for g in groups:
		for s: Dictionary in g:
			s["angle"] = at + unit / 2.0
			s["width"] = minf(unit * 0.94, MAX_WIDTH)
			_segments.append(s)
			at += unit
		at += GAP * unit if groups.size() > 1 else 0.0
	if not _fanned.is_empty() and not (_fanned in folded):
		_fanned = ""
	_build_fan()
	point_at(_pointer)


## The segments as shown, clockwise from the top, then the fanned ones.
func segments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _all():
		out.append(s.duplicate())
	return out


## What is pointed at: {} for nothing, {"kind": "centre"} for the ➕, or a
## segment ("kind", "id").
func pointed() -> Dictionary:
	return _pointed.duplicate()


## The cluster fanned out, or "".
func fanned() -> String:
	return _fanned


## Fans a folded cluster's sessions out at once (a click on it).
func fan_out(cluster: String) -> void:
	if _find("fold", cluster).is_empty():
		return
	_fanned = cluster
	_build_fan()
	queue_redraw()


## The middle's lines: what the pointed thing is, or the ➕'s.
func centre_text() -> PackedStringArray:
	var kind: String = _pointed.get("kind", "")
	match kind:
		"session":
			var s: Dictionary = store.session(_pointed["id"])
			return PackedStringArray([SessionsMenu.display_title(s.get("title")), SessionsMenu.project_name(s.get("project", {})), SessionsMenu.state_text(store.activity(_pointed["id"]))])
		"platform":
			return PackedStringArray(["Platform", "the spawn platform"])
		"fold":
			var n := clusters.sessions(_pointed["id"]).size()
			return PackedStringArray([clusters.cluster_name(_pointed["id"]), "%d sessions" % n])
	return PackedStringArray(["New session", "click"])


## Where the middle is, in the ring's coordinates.
func centre() -> Vector2:
	return size / 2.0


## The ring's outer and inner radii and the ➕ circle's, pixels.
func radii() -> Vector3:
	var outer := clampf(minf(size.x, size.y) * 0.3, 150.0, 320.0)
	return Vector3(outer, outer * 0.56, outer * 0.46)


## Where to point to reach a segment (its middle), in the ring's
## coordinates; for tests and the live check's steps.
func position_of(kind: String, id: String) -> Vector2:
	var s := _find(kind, id)
	if s.is_empty():
		return centre()
	var r := radii()
	var radius := (r.x + r.y) / 2.0
	if s in _fan:
		radius = _fan_radii().x + (_fan_radii().y - _fan_radii().x) / 2.0
	return centre() + _direction(s["angle"]) * radius


## Points at what is at [param at] (the mouse, in the ring's coordinates).
func point_at(at: Vector2) -> void:
	_pointer = at
	var before := _pointed
	var v := at - centre()
	var r := radii()
	if v.length() < r.z:
		_pointed = {"kind": "centre"}
		_fanned = ""
		_fan = []
	else:
		var angle := wrapf(v.angle() + PI / 2.0, 0.0, TAU)
		var in_fan := _nearest(_fan, angle) if not _fan.is_empty() and v.length() > r.x + 6.0 else {}
		if not in_fan.is_empty() and _angle_between(angle, in_fan["angle"]) < FAN_WIDTH:
			_pointed = in_fan
		else:
			_pointed = _nearest(_segments.filter(func(s: Dictionary) -> bool: return s["kind"] != "starting"), angle)
			if _pointed.get("kind") != "fold" or _pointed["id"] != _fanned:
				_fanned = ""
				_fan = []
	if _pointed.get("kind") != before.get("kind") or _pointed.get("id") != before.get("id"):
		_fold_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if _pointed.get("kind") == "fold" and _fanned != _pointed["id"]:
		_fold_time += delta
		if _fold_time >= FAN_DELAY:
			fan_out(_pointed["id"])
	refresh()


# The clusters folded into one segment: the busiest first, until the
# sessions fit in max_segments.
func _folded() -> Array[String]:
	var out: Array[String] = []
	var sizes := {}
	var count := 0
	for cid in clusters.ids():
		var n := clusters.sessions(cid).filter(func(id: String) -> bool: return store.sessions.has(id)).size()
		sizes[cid] = n
		count += n
	if launcher != null and launcher.busy():
		count += 1
	while count > max_segments:
		var busiest := ""
		for cid in clusters.ids():
			if not (cid in out) and sizes[cid] >= 2 and (busiest.is_empty() or sizes[cid] > sizes[busiest]):
				busiest = cid
		if busiest.is_empty():
			break
		out.append(busiest)
		count -= sizes[busiest] - 1
	return out


func _build_fan() -> void:
	_fan = []
	var fold := _find("fold", _fanned) if not _fanned.is_empty() else {}
	if fold.is_empty():
		_fanned = ""
		return
	var ids := clusters.sessions(_fanned).filter(func(id: String) -> bool: return store.sessions.has(id))
	var width := minf(FAN_WIDTH, PI / ids.size())
	var at: float = fold["angle"] - width * (ids.size() - 1) / 2.0
	for id: String in ids:
		_fan.append({"kind": "session", "id": id, "cluster": _fanned, "angle": wrapf(at, 0.0, TAU), "width": width * 0.92})
		at += width


func _find(kind: String, id: String) -> Dictionary:
	for s in _all():
		if s["kind"] == kind and s["id"] == id:
			return s
	return {}


# The fanned-out segments first: a session there is also in a fold.
func _all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_fan)
	out.append_array(_segments)
	return out


func _nearest(among: Array, angle: float) -> Dictionary:
	var best: Dictionary = {}
	for s: Dictionary in among:
		if best.is_empty() or _angle_between(angle, s["angle"]) < _angle_between(angle, best["angle"]):
			best = s
	return best


static func _angle_between(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


# A direction clockwise from the top, as on screen.
static func _direction(angle: float) -> Vector2:
	return Vector2.from_angle(angle - PI / 2.0)


func _fan_radii() -> Vector2:
	var r := radii()
	var inner := r.x + 18.0
	return Vector2(inner, inner + (r.x - r.y) * 0.85)


func _draw() -> void:
	var c := centre()
	var r := radii()
	var font := ThemeDB.fallback_font
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 1.2)
	for s in _segments:
		_draw_segment(s, r.y, r.x, pulse)
	if not _fan.is_empty():
		var fr := _fan_radii()
		for s in _fan:
			_draw_segment(s, fr.x, fr.y, pulse)
	# Each cluster's name outside the rim, by the middle of its arc; not
	# while a cluster is fanned out over them.
	var spans := {}
	for s in _segments:
		if s["cluster"].is_empty():
			continue
		var span: Array = spans.get(s["cluster"], [s["angle"], s["angle"]])
		span[1] = s["angle"]
		spans[s["cluster"]] = span
	for cid: String in (spans if _fanned.is_empty() else {}):
		var mid: float = (spans[cid][0] + spans[cid][1]) / 2.0
		var dir := _direction(mid)
		var name := clusters.cluster_name(cid)
		var half := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x / 2.0
		# Grown by a pointed segment's 12 %, then out by half the name's
		# width sideways, so it never covers the ring.
		var at := c + dir * (r.x + (r.x - r.y) * 0.12 + 16.0) + Vector2(dir.x * half, 0)
		_text(font, name, at, 16, TEXT_DIM, half * 2.0 + 8.0)
	# The middle: the ➕, or what is pointed at.
	var on_centre: bool = _pointed.get("kind") == "centre"
	draw_circle(c, r.z, FILL_POINTED if on_centre else FILL_CENTRE)
	var lines := centre_text()
	if _pointed.get("kind") in ["session", "platform", "fold"]:
		_text(font, lines[0], c + Vector2(0, -r.z * 0.22), 20, TEXT, r.z * 1.8)
		_text(font, lines[1], c + Vector2(0, r.z * 0.08), 15, TEXT_DIM, r.z * 1.8)
		if lines.size() > 2:
			var colour: Color = WorldMap.STATE_COLOURS.get(store.activity(_pointed["id"]), TEXT_DIM)
			_text(font, lines[2], c + Vector2(0, r.z * 0.34), 15, colour, r.z * 1.8)
	else:
		RingIcons.plus(self, c + Vector2(0, -r.z * 0.12), r.z * 0.8, TEXT if on_centre else TEXT_DIM)
		_text(font, "New session (click)" if on_centre else "New session", c + Vector2(0, r.z * 0.52), 15, TEXT_DIM, r.z * 1.8)
	_text(font, "Release Tab to go  ·  click + for a new session  ·  Esc to cancel", c + Vector2(0, r.x + 70.0), 15, TEXT_DIM, size.x)


func _draw_segment(s: Dictionary, inner: float, outer: float, pulse: float) -> void:
	var c := centre()
	var pointed: bool = _pointed.get("kind") == s["kind"] and _pointed.get("id") == s["id"]
	if pointed:
		outer += (outer - inner) * 0.12
	var half: float = s["width"] / 2.0
	var points := PackedVector2Array()
	var steps := maxi(int(s["width"] / deg_to_rad(4.0)), 2)
	for i in steps + 1:
		points.append(c + _direction(s["angle"] - half + s["width"] * i / steps) * outer)
	for i in range(steps, -1, -1):
		points.append(c + _direction(s["angle"] - half + s["width"] * i / steps) * inner)
	var faded: bool = s["kind"] == "starting"
	var fill := FILL_POINTED if pointed else FILL
	draw_colored_polygon(points, Color(fill, fill.a * 0.5) if faded else fill)
	# The state's rim along the outer edge.
	var state := _state(s)
	if not state.is_empty():
		var colour: Color = WorldMap.STATE_COLOURS.get(state, TEXT_DIM)
		if state == "waiting":
			colour.a = pulse
		var rim := PackedVector2Array()
		for i in steps + 1:
			rim.append(c + _direction(s["angle"] - half + s["width"] * i / steps) * (outer - 3.0))
		draw_polyline(rim, colour, 6.0)
	var at := c + _direction(s["angle"]) * (inner + outer) / 2.0
	var icon := minf((outer - inner) * 0.5, s["width"] * (inner + outer) / 2.0 * 0.6)
	match s["kind"]:
		"platform":
			RingIcons.house(self, at, icon)
		"session":
			var island := islands.island(s["id"]) if islands != null else null
			RingIcons.biome(self, island.biome if island != null else Biome.Kind.BEACH, at, icon)
		"fold":
			var n := clusters.sessions(s["id"]).size()
			_text(ThemeDB.fallback_font, "%d ▸" % n, at, 20, TEXT, icon * 2.0)
		"starting":
			RingIcons.dots(self, at, icon, TEXT_DIM)


# A segment's state for its rim: a session's, a folded cluster's most
# urgent one; none for the platform.
func _state(s: Dictionary) -> String:
	match s["kind"]:
		"session":
			return store.activity(s["id"])
		"fold":
			var most := "idle"
			for id in clusters.sessions(s["id"]):
				var a := store.activity(id)
				if URGENCY.get(a, 0) > URGENCY.get(most, 0):
					most = a
			return most
	return ""


func _text(font: Font, text: String, at: Vector2, font_size: int, colour: Color, width: float) -> void:
	var baseline := at + Vector2(-width / 2.0, font_size * 0.35)
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 6, OUTLINE)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, colour)
