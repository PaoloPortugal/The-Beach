class_name Settings
extends RefCounted
## The game's settings (C10), saved in `user://settings.cfg` with the
## sections and keys of [constant DEFAULTS] ("section/key"). A change is
## saved at once and announced by [signal changed]; `world.gd` applies
## them. A05's chime keeps its own `[attention] sound` there ([Attention]).
## Values that are missing, of the wrong type or out of range are the
## defaults.

signal changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"graphics/window_mode": "windowed",
	"graphics/vsync": true,
	"graphics/fps_cap": 0,
	"graphics/render_scale": 1.0,
	"graphics/shadows": "high",
	"graphics/msaa": "off",
	"graphics/screen_space_aa": "off",
	"graphics/lightning": true,
	"controls/mouse_sensitivity": 1.0,
	"controls/fov": 80.0,
	"game/go_to_new_island": true,
}

## The choices a text or whole-number setting can take, in menu order.
const CHOICES := {
	"graphics/window_mode": ["windowed", "borderless", "fullscreen"],
	"graphics/fps_cap": [0, 30, 60, 120, 144, 240],
	"graphics/shadows": ["off", "low", "high"],
	"graphics/msaa": ["off", "2x", "4x", "8x"],
	"graphics/screen_space_aa": ["off", "fxaa", "smaa"],
}

## The range of each decimal setting: [min, max, step].
const RANGES := {
	"graphics/render_scale": [0.5, 1.0, 0.05],
	"controls/mouse_sensitivity": [0.25, 3.0, 0.05],
	"controls/fov": [60.0, 110.0, 1.0],
}

## Where they're saved; tests point it elsewhere.
var path := PATH

var _values := DEFAULTS.duplicate()


func value(key: String) -> Variant:
	return _values[key]


## Sets one, saves and announces it; a value it can't take is ignored.
func set_value(key: String, v: Variant) -> void:
	if not _valid(key, v):
		return
	if v is float:
		var r: Array = RANGES[key]
		v = clampf(snappedf(v, r[2]), r[0], r[1])
	if _values[key] == v:
		return
	_values[key] = v
	save()
	changed.emit()


## Every setting back to its default, saved.
func reset() -> void:
	_values = DEFAULTS.duplicate()
	save()
	changed.emit()


func load_file() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in DEFAULTS:
		var parts := key.split("/")
		var v: Variant = cfg.get_value(parts[0], parts[1], DEFAULTS[key])
		if v is int and DEFAULTS[key] is float:
			v = float(v)
		if _valid(key, v):
			_values[key] = clampf(v, RANGES[key][0], RANGES[key][1]) if v is float else v


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path) # keep the others' settings (A05's chime)
	for key: String in _values:
		var parts := key.split("/")
		cfg.set_value(parts[0], parts[1], _values[key])
	cfg.save(path)


func _valid(key: String, v: Variant) -> bool:
	if not DEFAULTS.has(key) or typeof(v) != typeof(DEFAULTS[key]):
		return false
	if CHOICES.has(key):
		return v in CHOICES[key]
	if v is float:
		return is_finite(v)
	return true
