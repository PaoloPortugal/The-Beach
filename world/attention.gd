class_name Attention
extends CanvasLayer
## The attention cue's screen and window side (A05; the beacons are on the
## agents, [AttentionBeacon]). While any session waits on you, a corner
## says how many. When an agent starts waiting while the game window isn't
## focused, the window asks for attention once (taskbar flash, Dock
## bounce, urgent hint) and a chime plays, if the sound is on and its file
## is there. Never while you're in the game. A PLACEHOLDER, like all UI for
## now.

## The chime: a CC0 sound the user picked (NOTES → A05). Silent without it.
const CHIME := "res://assets/audio/attention.ogg"
const SETTINGS := "user://settings.cfg"

var store: SessionStore
## Whether the game window has focus; tests replace it.
var is_focused: Callable = func() -> bool: return get_window().has_focus()
## Asks the system to draw attention to the window; tests replace it.
var request_attention: Callable = func() -> void: DisplayServer.window_request_attention()
## Plays the chime; tests replace it.
var play_chime: Callable = _play_chime
## Where the sound setting is saved; tests point it elsewhere.
var settings_path := SETTINGS
## Play the chime with the background cue. Saved between runs.
var sound_on := true:
	set(on):
		sound_on = on
		_save()

var _waiting := {} # "session\nagent" → true, for every agent waiting now
var _count := Label.new()
var _player := AudioStreamPlayer.new()


func _init() -> void:
	layer = 1
	_count.name = "Count"
	_count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_count.offset_left = -420.0
	_count.offset_right = -24.0
	_count.offset_top = 24.0
	_count.offset_bottom = 60.0
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.add_theme_font_size_override("font_size", 22)
	_count.add_theme_color_override("font_color", AgentStateMarker.WAITING)
	_count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_count.add_theme_constant_override("outline_size", 8)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.visible = false
	add_child(_count)
	_player.volume_db = -12.0 # quiet
	add_child(_player)


func setup(p_store: SessionStore) -> void:
	store = p_store
	_load()
	store.agent_added.connect(_on_agent)
	store.agent_changed.connect(_on_agent)
	# A new session's snapshot only says session_added; a resync after a
	# gap also says permissions_changed, and may have dropped agents.
	store.session_added.connect(func(id: String, _created: bool) -> void: _scan(id))
	store.permissions_changed.connect(_scan)
	store.session_removed.connect(func(id: String, _reason: String) -> void: _scan(id))
	for id in store.sessions:
		_scan(id)


## How many sessions wait on you.
func waiting_sessions() -> int:
	var sessions := {}
	for key in _waiting:
		sessions[key.get_slice("\n", 0)] = true
	return sessions.size()


## The corner's text, "" when hidden.
func count_text() -> String:
	return _count.text if _count.visible else ""


func _on_agent(session: String, agent_id: String) -> void:
	var key := session + "\n" + agent_id
	if store.agent(session, agent_id).get("state", "") == "waiting":
		if not _waiting.has(key):
			_waiting[key] = true
			if not is_focused.call():
				request_attention.call()
				if sound_on:
					play_chime.call()
	else:
		_waiting.erase(key)
	_refresh()


## Forgets the session's agents that are gone, then looks at the rest.
func _scan(session: String) -> void:
	for key in _waiting.keys():
		if key.get_slice("\n", 0) == session and store.agent(session, key.get_slice("\n", 1)).is_empty():
			_waiting.erase(key)
	for a in store.session(session).get("agents", []):
		_on_agent(session, a["agent"])
	_refresh()


func _refresh() -> void:
	var n := waiting_sessions()
	_count.visible = n > 0
	_count.text = "1 session waiting" if n == 1 else "%d sessions waiting" % n


func _play_chime() -> void:
	if _player.stream == null and ResourceLoader.exists(CHIME):
		_player.stream = load(CHIME)
	if _player.stream:
		_player.play()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		sound_on = cfg.get_value("attention", "sound", true)


func _save() -> void:
	if store == null:
		return # not set up yet: nothing loaded, nothing to save
	var cfg := ConfigFile.new()
	cfg.load(settings_path) # keep any other settings
	cfg.set_value("attention", "sound", sound_on)
	cfg.save(settings_path)
