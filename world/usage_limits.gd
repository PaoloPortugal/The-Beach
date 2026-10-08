class_name UsageLimits
extends CanvasLayer
## The plans' usage limits (C08), once per provider (each its own
## account), in the bottom-right corner: "5-hour 74% · resets 3:40 PM
## Weekly 94% · resets Fri 9:00 AM", each limit by the provider's own
## label, in its order. The most recent figures across each provider's
## sessions ([method SessionStore.usage_limits]); a limit whose
## window is over is hidden until a session hears the new one. One line per
## provider, named ("Claude: 5-hour ...") only when more than one has
## limits. Always shown, the chat and the maps included (user's choice,
## 2026-10-08). A PLACEHOLDER, like all UI for now.

## How often it looks again for a window that ended, in seconds.
const RECHECK := 15.0

var store: SessionStore
## The providers the sidecar offers, [code][{provider, name}][/code], for
## their names; tests replace it.
var providers: Callable = func() -> Array: return []
## The time now in Unix seconds; tests replace it.
var now: Callable = func() -> float: return Time.get_unix_time_from_system()

var _text := Label.new()
var _timer := Timer.new()


func _init() -> void:
	layer = 4 # over the menu, the chat and the big map; under quitting's
	_text.name = "Limits"
	_text.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_text.offset_left = -720.0
	_text.offset_right = -24.0
	_text.offset_top = -40.0
	_text.offset_bottom = -12.0
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_text.grow_vertical = Control.GROW_DIRECTION_BEGIN # more lines grow upwards
	_text.add_theme_font_size_override("font_size", 16)
	_text.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_text.add_theme_constant_override("outline_size", 6)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.visible = false
	add_child(_text)
	_timer.wait_time = RECHECK
	_timer.autostart = true
	_timer.timeout.connect(refresh)
	add_child(_timer)


func setup(p_store: SessionStore, sidecar: SidecarClient = null) -> void:
	store = p_store
	if sidecar != null:
		providers = func() -> Array: return sidecar.providers
	store.usage_changed.connect(func(_id: String) -> void: refresh())
	store.session_added.connect(func(_id: String, _created: bool) -> void: refresh())
	store.session_removed.connect(func(_id: String, _reason: String) -> void: refresh())
	refresh()


## The corner's text, "" when hidden.
func text() -> String:
	return _text.text if _text.visible else ""


func refresh() -> void:
	if store == null:
		return
	var t: float = now.call()
	var limits := store.usage_limits(t)
	var offered: Array = providers.call()
	var order := limits.keys()
	# The sidecar's order, then any it no longer lists by id.
	order.sort_custom(func(a: String, b: String) -> bool:
		var ia := _index(offered, a)
		var ib := _index(offered, b)
		return ia < ib or (ia == ib and a < b))
	var lines: PackedStringArray = []
	for provider in order:
		var parts: PackedStringArray = []
		# In the provider's order, by its own words (plain text: untrusted).
		for l: Dictionary in limits[provider]:
			parts.append(UsageText.limit(str(l["label"]), float(l["used_percent"]),
				SessionStore.unix_time(l["resets_at"]), t))
		var line := "   ".join(parts)
		lines.append(line if order.size() == 1 else "%s: %s" % [_name(offered, provider), line])
	_text.text = "\n".join(lines)
	_text.visible = not lines.is_empty()


## A provider's place in the sidecar's list, or after them all.
static func _index(offered: Array, provider: String) -> int:
	for i in offered.size():
		if offered[i] is Dictionary and offered[i].get("provider") == provider:
			return i
	return offered.size()


## A provider's name from the sidecar's list, else its id.
static func _name(offered: Array, provider: String) -> String:
	var i := _index(offered, provider)
	return str(offered[i].get("name", provider)) if i < offered.size() else provider
