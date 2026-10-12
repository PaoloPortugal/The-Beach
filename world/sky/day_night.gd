class_name DayNight
extends Node
## The day and night cycle (W09): a 28-minute day, half of it night. The
## sun rises in the east, crosses the south and sets in the west, and the
## moon follows it across the night sky, opposite it. The world's one
## directional light (world.tscn's Sun) is the sun by day and the moon by
## night; they swap at the horizon, where both are dim. The sky, the
## ambient light and the fog follow the time of day, greyed by the
## weather (W09's [Weather]) and briefly lifted by its lightning. Night
## stays moonlit and readable; islands light up (NightLight).

## A whole day and night, seconds.
const CYCLE := 28.0 * 60.0
## Every launch starts here: mid-morning (0 is sunrise, 0.5 sunset).
const START := 0.12
## The highest the sun and the moon climb, radians.
const MAX_ELEVATION := deg_to_rad(60.0)

const SUN_COLOUR := Color(1.0, 0.97, 0.92)
const SUNSET_COLOUR := Color(1.0, 0.62, 0.38)
const MOON_COLOUR := Color(0.62, 0.72, 1.0)
const SUN_ENERGY := 1.1
const MOON_ENERGY := 0.12

## The sky's top and horizon colours by day, at sunset and by night.
const DAY_TOP := Color(0.32, 0.56, 0.86)
const DAY_HORIZON := Color(0.66, 0.8, 0.9)
const DUSK_TOP := Color(0.22, 0.32, 0.58)
const DUSK_HORIZON := Color(0.98, 0.58, 0.30)
const NIGHT_TOP := Color(0.03, 0.05, 0.13)
const NIGHT_HORIZON := Color(0.10, 0.15, 0.27)
## Overcast skies tend to this grey (times the light of the hour), and
## a storm's to a darker one.
const OVERCAST := Color(0.56, 0.60, 0.64)
const STORM_SKY := Color(0.27, 0.30, 0.34)

## Ambient light, day and night: night keeps enough to find your way.
const DAY_AMBIENT := Color(0.66, 0.8, 0.9)
const NIGHT_AMBIENT := Color(0.32, 0.40, 0.62)
const DAY_AMBIENT_ENERGY := 0.6
const NIGHT_AMBIENT_ENERGY := 0.35

## The darkness now, for night lights made after it was last sent.
static var current_darkness := 0.0

## Where the day is: 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight.
var time := START
## Seconds of a whole day; shorter for checking (--day-minutes).
var cycle := CYCLE
## 0 by day, 1 by night, easing through dusk and dawn. Night lights
## (NightLight) follow it.
var darkness := 0.0

## Set up by setup().
var weather: Weather
var underwater: Underwater
var _environment: Environment
var _light: DirectionalLight3D
var _sky: ShaderMaterial
var _sent_darkness := -1.0
# The sky's colours and levels as last set (_set_sky).
var _sky_values := {}


func setup(environment: Environment, light: DirectionalLight3D, p_weather: Weather, p_underwater: Underwater) -> void:
	_environment = environment
	_light = light
	weather = p_weather
	underwater = p_underwater
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://world/sky/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky
	# The sun's direction changes every frame, and each change redraws the
	# reflection map: at 64 px that's cheap and looks the same as 256.
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	_environment.sky = sky
	# The ambient light is set here, by the hour, not taken from the sky.
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	apply()


func _process(delta: float) -> void:
	time = fposmod(time + delta / cycle, 1.0)
	apply()


## Sets the time of day from a 24-hour clock: sunrise is 6:00, sunset
## 18:00.
func set_hour(hour: float) -> void:
	time = fposmod((hour - 6.0) / 24.0, 1.0)
	apply()


## The time of day on a 24-hour clock.
func hour() -> float:
	return fposmod(time * 24.0 + 6.0, 24.0)


## The direction toward the sun, at [param t] (default: now).
static func sun_direction(t: float) -> Vector3:
	var a := t * TAU
	return Vector3(cos(a), sin(a) * sin(MAX_ELEVATION), sin(a) * cos(MAX_ELEVATION))


## The sun's height in the sky now, as the sine of its elevation:
## positive by day, negative by night.
func sun_height() -> float:
	return sun_direction(time).y


## How far into night it is at a sun height: 0 with the sun 6° up or
## more, 1 with it 6° down or more.
static func darkness_at(height: float) -> float:
	return smoothstep(0.1, -0.1, height)


## Puts the light, sky, ambient and fog where the time and the weather
## say. Called every frame.
func apply() -> void:
	if _environment == null:
		return
	var sun := sun_direction(time)
	var h := sun.y
	darkness = darkness_at(h)
	var cover := weather.cover if weather else 0.0
	var storm := weather.storm if weather else 0.0
	var flash := weather.flash if weather else 0.0

	# The light: the sun above the horizon, the moon (opposite) below it.
	var day := h >= 0.0
	var toward := sun if day else -sun
	var up := absf(h)
	var energy: float
	var colour: Color
	if day:
		energy = SUN_ENERGY * smoothstep(0.0, 0.25, up)
		colour = SUNSET_COLOUR.lerp(SUN_COLOUR, smoothstep(0.0, 0.35, up))
	else:
		energy = MOON_ENERGY * smoothstep(0.0, 0.2, up)
		colour = MOON_COLOUR
	energy *= (1.0 - 0.6 * cover) * (1.0 - 0.3 * storm)
	# Under the water at night the sea floor would stand out pale against
	# the dark water's fog: less light reaches down there.
	var below := 1.0
	if underwater and underwater.active:
		below = lerpf(1.0, 0.4, darkness)
	energy *= below
	_light.light_color = colour
	_light.light_energy = energy + flash * 0.6
	_light.visible = energy > 0.001 or flash > 0.0
	# A directional light shines along its -Z; point that away from the sky.
	_light.look_at_from_position(_light.position, _light.position - toward, Vector3.UP if absf(toward.y) < 0.99 else Vector3.FORWARD)

	# The sky: day, golden near the horizon at dusk, night; greyed by cloud.
	var dusk := 1.0 - smoothstep(0.0, 0.3, absf(h))
	var top := DAY_TOP.lerp(NIGHT_TOP, darkness)
	var horizon := DAY_HORIZON.lerp(NIGHT_HORIZON, darkness)
	top = top.lerp(DUSK_TOP, dusk * 0.6)
	horizon = horizon.lerp(DUSK_HORIZON, dusk * (1.0 - darkness * 0.6))
	var light_of_hour := lerpf(1.0, 0.18, darkness)
	top = top.lerp(OVERCAST * light_of_hour, cover * 0.75)
	horizon = horizon.lerp(OVERCAST * light_of_hour, cover * 0.75)
	top = top.lerp(STORM_SKY * light_of_hour, storm * 0.85)
	horizon = horizon.lerp(STORM_SKY * light_of_hour, storm * 0.75)
	# Lightning lifts the sky for a moment, never to white.
	top = top.lerp(Color(0.72, 0.76, 0.88), flash * 0.7)
	horizon = horizon.lerp(Color(0.72, 0.76, 0.88), flash * 0.7)
	_set_sky("top_colour", top)
	_set_sky("horizon_colour", horizon)
	_set_sky("sun_direction", sun)
	_set_sky("sun_colour", colour if day else SUNSET_COLOUR)
	_set_sky("stars", darkness * (1.0 - cover))
	_set_sky("discs", 1.0 - cover * 0.9)

	# Ambient light: dimmer and bluer by night, never dark.
	var ambient := DAY_AMBIENT.lerp(NIGHT_AMBIENT, darkness)
	ambient = ambient.lerp(OVERCAST, cover * 0.4)
	_environment.ambient_light_color = ambient
	_environment.ambient_light_energy = lerpf(DAY_AMBIENT_ENERGY, NIGHT_AMBIENT_ENERGY, darkness) * (1.0 - 0.2 * cover) * (1.0 - 0.25 * storm) * below + flash * 0.6

	# The fog fades into the horizon above the water; under it, the
	# water's own blue, darker by night.
	if underwater:
		underwater.set_above("fog_light_color", horizon)
		underwater.light = lerpf(1.0, 0.3, darkness) * (1.0 - 0.3 * cover)
	else:
		_environment.fog_light_color = horizon

	current_darkness = darkness
	if absf(darkness - _sent_darkness) > 0.005:
		_sent_darkness = darkness
		get_tree().call_group(NightLight.GROUP, "set_darkness", darkness)


# Sets a sky uniform when it has changed: each change makes Godot redraw
# the sky's reflection map (64 px, so cheap). While the clock runs the sun
# moves every frame, smoothly; stopped (/time speed 0), nothing is redrawn.
func _set_sky(key: String, value: Variant) -> void:
	if _sky_values.get(key) == value:
		return
	_sky_values[key] = value
	_sky.set_shader_parameter(key, value)
