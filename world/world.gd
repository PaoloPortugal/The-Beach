extends Node3D
## The world scene: the player starts on a platform in the open sea. Tab
## opens the sessions menu, to start, resume or go to a session. Each live
## session gets an island with its orchestrator, rising out of the sea for
## a new one; one you started takes you there once it's up. Plus the ocean and the chat. Closing the window while sessions
## run asks first (S05). Sessions waiting on you draw attention (A05).
## Bridges join each cluster's islands and the platform, a minimap
## shows the cluster you're in, and M opens a map of the world (W06).
## The plan's usage limits are in the bottom-right corner (C08). The day
## turns to night and back, and the weather changes (W09).

## Godot's copy of the live sessions, fed by the sidecar.
var store := SessionStore.new()
## Asks before quitting while sessions run.
var quit_guard := QuitGuard.new()
## Says when sessions wait on you (A05; the beacons are on the agents).
var attention := Attention.new()
## Points to new sessions' islands while they're off-screen (W04).
var pointers := NewIslandPointers.new()
## The map of the cluster you're in or nearest to (W06).
var minimap := Minimap.new()
## The big map of the whole world, M (W06).
var world_map := WorldMap.new()
## The plan's usage limits, bottom right (C08).
var usage_limits := UsageLimits.new()
## The view under the water (W08).
var underwater := Underwater.new()
## The day and night cycle and the weather (W09), with the clouds, rain and
## lightning they bring.
var day_night := DayNight.new()
var weather := Weather.new()
var clouds := Clouds.new()
var rain := Rain.new()
var lightning_bolt := LightningBolt.new()

## The spawn platform's deck: half its width and its top (world.tscn).
const PLATFORM_HALF := 6.0
const PLATFORM_TOP := 1.0

# The session whose island is rising, to take the player to once it's up.
var _teleport_when_risen := ""

@onready var _player: Player = $Player
@onready var _islands: SessionIslands = $SessionIslands
@onready var _menu: SessionsMenu = $SessionsMenu
@onready var _chat: ChatController = $ChatController


func _ready() -> void:
	# Under the Compatibility renderer, sun shadows wash the island out to
	# white (Godot 4.7.2, seen on AMD; NOTES → Watch items), so they're off
	# there.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		$Sun.shadow_enabled = false
	# The platform's deck is at y = 1. The sessions menu's "Platform" and
	# the big map bring you back here (W08).
	_player.spawn_point = Vector3(0.0, 1.1, 3.0)
	_player.respawn()
	_menu.player = _player
	add_child(underwater)
	underwater.setup($WorldEnvironment.environment)
	_setup_sky()

	# Order matters: the islands hear of a new session first, so its island
	# exists by the time the menu's launcher says it started.
	_islands.setup(store)
	fit_draw_distance()
	# The platform is in every cluster's bridge tree (W06).
	_islands.bridges.add_hub("platform", Vector3.ZERO, PLATFORM_HALF * sqrt(2.0), platform_edge)
	_chat.setup(store, Sidecar)
	_menu.setup(store, Sidecar, _islands.clusters)
	add_child(quit_guard)
	quit_guard.setup(store, _player)
	add_child(attention)
	attention.setup(store)
	add_child(usage_limits)
	usage_limits.setup(store, Sidecar)
	add_child(pointers)
	pointers.setup(_islands, store)
	add_child(minimap)
	minimap.setup(_islands, _player)
	minimap.hidden_when = func() -> bool: return _chat.is_open() or _menu.is_open() or world_map.is_open()
	add_child(world_map)
	world_map.setup(_islands, _player, store, minimap)
	world_map.go_to.connect(teleport)
	world_map.go_to_platform.connect(go_to_platform)
	_menu.attention = attention
	_islands.player = _player
	_islands.island_added.connect(func(_id: String, _island: Island, orchestrator: Orchestrator) -> void:
		_chat.watch(orchestrator))
	_islands.island_risen.connect(func(id: String) -> void:
		if id == _teleport_when_risen:
			teleport(id))
	_menu.launcher.session_started.connect(teleport)
	_menu.go_to.connect(teleport)
	_menu.go_to_platform.connect(go_to_platform)
	store.attach(Sidecar)
	# Dev tool: the current live check's steps, top left (NOTES → Running it).
	if "--checklist" in OS.get_cmdline_user_args():
		add_child(load("res://tests/live/checklist.tscn").instantiate())
		minimap.top = 56.0 # under it


# W09: the sky, the weather and what they bring. Dev flags (NOTES →
# Running it): --hour <0-24> sets the time of day, --weather <kind> fixes
# the weather (clear, cloudy, rain, windy, storm), --day-minutes <n>
# shortens the day.
func _setup_sky() -> void:
	weather.name = "Weather"
	add_child(weather)
	day_night.name = "DayNight"
	add_child(day_night)
	day_night.setup($WorldEnvironment.environment, $Sun, weather, underwater)
	clouds.name = "Clouds"
	clouds.weather = weather
	add_child(clouds)
	rain.name = "Rain"
	rain.weather = weather
	rain.wind_direction = clouds.wind_direction
	add_child(rain)
	lightning_bolt.name = "LightningBolt"
	add_child(lightning_bolt)
	weather.lightning.connect(lightning_bolt.strike)
	$Ocean.weather = weather
	var args := OS.get_cmdline_user_args()
	var hour := args.find("--hour")
	if hour >= 0 and hour + 1 < args.size():
		day_night.set_hour(args[hour + 1].to_float())
	var kind := args.find("--weather")
	if kind >= 0 and kind + 1 < args.size() and Weather.kind_named(args[kind + 1]) >= 0:
		weather.set_kind(Weather.kind_named(args[kind + 1]) as Weather.Kind, true)
		weather.changes = false
	var minutes := args.find("--day-minutes")
	if minutes >= 0 and minutes + 1 < args.size() and args[minutes + 1].to_float() > 0.0:
		day_night.cycle = args[minutes + 1].to_float() * 60.0


## Puts the player back on the spawn platform (W08: the sea no longer
## does), from the sessions menu and the big map. It replaces a teleport
## still waiting for its island to rise.
func go_to_platform() -> void:
	_teleport_when_risen = ""
	_player.respawn()


## Puts the player on a session's island, facing its orchestrator, once
## the island has risen (W04). From the sessions menu (W07) and the big
## map (W06).
func teleport(session_id: String) -> void:
	_teleport_when_risen = ""
	if _islands.island(session_id) == null:
		return
	if _islands.is_rising(session_id):
		_teleport_when_risen = session_id
		return
	_player.global_position = _islands.arrival_point(session_id)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0 # the orchestrator is straight ahead (-z)


## Islands, agents and bridges the fog hides fully aren't drawn
## (SessionIslands.draw_distance): the fog's end is the one source. Call
## again after turning the fog on or off.
func fit_draw_distance() -> void:
	var env: Environment = $WorldEnvironment.environment
	_islands.draw_distance = env.fog_depth_end if env.fog_enabled else 0.0


## Where a bridge heading for [param toward] leaves the platform: its
## deck's edge, with the bridge's overrun (Bridge.OVERRUN) ending there.
static func platform_edge(toward: Vector3) -> Vector3:
	var dir := Vector2(toward.x, toward.z).normalized()
	var out := PLATFORM_HALF / maxf(absf(dir.x), absf(dir.y)) + Bridge.OVERRUN
	return Vector3(dir.x * out, PLATFORM_TOP, dir.y * out)
