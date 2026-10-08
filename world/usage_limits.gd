class_name UsageLimits
extends CanvasLayer
## The plan's usage limits (C08), once for the whole account, in the
## bottom-right corner: "5-hour 74% · resets 3:40 PM   Weekly 94% · resets
## Fri 9:00 AM". The most recent figures across sessions
## ([method SessionStore.usage_limits]); a limit whose window is over is
## hidden until a session hears the new one. Always shown, the chat and
## the maps included (user's choice, 2026-10-08). A PLACEHOLDER, like all
## UI for now.

## How often it looks again for a window that ended, in seconds.
const RECHECK := 15.0

var store: SessionStore
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


func setup(p_store: SessionStore) -> void:
	store = p_store
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
	var parts: PackedStringArray = []
	for key in ["five_hour", "seven_day"]:
		if limits.has(key):
			var l: Dictionary = limits[key]
			parts.append(UsageText.limit("5-hour" if key == "five_hour" else "Weekly",
				float(l["used_percent"]), SessionStore.unix_time(l["resets_at"]), t))
	_text.text = "   ".join(parts)
	_text.visible = not parts.is_empty()
