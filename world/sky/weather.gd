class_name Weather
extends Node
## The weather (W09): random and gentle, and it never means anything (so
## it can't be mistaken for an agent's state, A03/A05). Mostly clear,
## drifting now and then into cloud, rain, wind or a thunderstorm for a
## few minutes. Each kind sets targets for four levels, which ease toward
## them over about a minute, so it changes smoothly: [member cover]
## (cloud), [member rain], [member wind] and [member storm]. A storm
## brings lightning: soft and rare (see [member flash]).

enum Kind { CLEAR, CLOUDY, RAIN, WINDY, STORM }

## Each kind's targets: cover, rain, wind, storm.
const TARGETS := {
	Kind.CLEAR: [0.1, 0.0, 0.1, 0.0],
	Kind.CLOUDY: [0.65, 0.0, 0.3, 0.0],
	Kind.RAIN: [0.85, 0.6, 0.4, 0.0],
	Kind.WINDY: [0.35, 0.0, 1.0, 0.0],
	Kind.STORM: [1.0, 1.0, 1.0, 1.0],
}
## How often each kind comes next (clear most of the time).
const WEIGHTS := {
	Kind.CLEAR: 0.5,
	Kind.CLOUDY: 0.2,
	Kind.RAIN: 0.12,
	Kind.WINDY: 0.12,
	Kind.STORM: 0.06,
}
const NAMES := ["clear", "cloudy", "rain", "windy", "storm"]
## How long a kind lasts, seconds.
const MIN_SPELL := 180.0
const MAX_SPELL := 480.0
## How fast the levels move toward their targets, per second (a full
## change in about a minute).
const EASE := 1.0 / 60.0
## Lightning, during a storm: at most one every MIN_GAP to MAX_GAP
## seconds, a short soft brightening (never a white-out).
const MIN_GAP := 10.0
const MAX_GAP := 20.0
const FLASH_TIME := 0.35
const FLASH_PEAK := 0.6

## Emitted at each lightning strike, with the direction (horizontal, from
## the camera) the bolt is in.
signal lightning(direction: Vector2)

var kind := Kind.CLEAR
var cover := 0.1
var rain := 0.0
var wind := 0.1
var storm := 0.0
## How bright the lightning's flash is now, 0 to FLASH_PEAK; DayNight
## lifts the sky and the light by it.
var flash := 0.0
## Off: no lightning at all (the settings menu's switch, later).
var lightning_enabled := true
## Off: the kind stays as set (tests, --weather).
var changes := true

var rng := RandomNumberGenerator.new()
var _spell := 0.0
var _until_lightning := 0.0
var _flash_age := -1.0


func _ready() -> void:
	rng.randomize()
	_spell = rng.randf_range(MIN_SPELL, MAX_SPELL)
	_until_lightning = rng.randf_range(MIN_GAP, MAX_GAP)


func _process(delta: float) -> void:
	step(delta)


## Moves the weather on by [param delta] seconds.
func step(delta: float) -> void:
	if changes:
		_spell -= delta
		if _spell <= 0.0:
			set_kind(pick_next(rng.randf()), false)
	var t: Array = TARGETS[kind]
	cover = move_toward(cover, t[0], EASE * delta)
	rain = move_toward(rain, t[1], EASE * delta)
	wind = move_toward(wind, t[2], EASE * delta)
	storm = move_toward(storm, t[3], EASE * delta)

	# Lightning, once the storm is well under way.
	_until_lightning -= delta
	if storm > 0.6 and lightning_enabled and _until_lightning <= 0.0:
		strike()
	if _flash_age >= 0.0:
		_flash_age += delta
		# Two soft pulses, the second smaller, then gone.
		var a := _flash_age / FLASH_TIME
		flash = FLASH_PEAK * maxf(_pulse(a, 0.0, 0.35), 0.6 * _pulse(a, 0.45, 0.4))
		if a >= 1.0:
			flash = 0.0
			_flash_age = -1.0


## A lightning strike now, storm or not (also C09's /lightning): the
## flash, and the bolt through [signal lightning].
func strike() -> void:
	_until_lightning = rng.randf_range(MIN_GAP, MAX_GAP)
	_flash_age = 0.0
	lightning.emit(Vector2.from_angle(rng.randf() * TAU))


## Changes to [param p_kind]. With [param now], the levels jump to it
## (tests, --weather); otherwise they ease there.
func set_kind(p_kind: Kind, now: bool) -> void:
	kind = p_kind
	_spell = rng.randf_range(MIN_SPELL, MAX_SPELL)
	if now:
		var t: Array = TARGETS[kind]
		cover = t[0]
		rain = t[1]
		wind = t[2]
		storm = t[3]


## The kind for a roll [param r] in [0, 1), by WEIGHTS.
static func pick_next(r: float) -> Kind:
	var total := 0.0
	for k in WEIGHTS:
		total += WEIGHTS[k]
	var at := r * total
	for k in WEIGHTS:
		at -= WEIGHTS[k]
		if at < 0.0:
			return k
	return Kind.CLEAR


## The kind called [param name] ("clear", "storm", ...), or -1.
static func kind_named(name: String) -> int:
	return NAMES.find(name)


# A bump from 0 up to 1 and back over [start, start + width] (of 0..1).
static func _pulse(a: float, start: float, width: float) -> float:
	var x := (a - start) / width
	if x <= 0.0 or x >= 1.0:
		return 0.0
	return sin(x * PI)
