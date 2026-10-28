class_name FishFight
extends RefCounted
## A fight with a hooked fish (D01), on the water's plane, seen from
## above: [Fishing] steps it each frame and shows it in the world (the
## rod bending, the line, the shadow), never as a bar. The fish swims one
## way and another, turning now and then (more often the higher its
## temper). Holding the click reels the line in; letting go, the reel
## gives line as the fish runs. The fish drags the rod's tip toward the
## side it swims to, and the mouse pushes it back: held against the fish,
## the rod takes some of its pull and tires it faster. Reeling into a
## run, or with the rod on the fish's side, strains the line. It snaps
## after a moment at its limit or when the fish has run out all the line;
## the hook slips off after a while slack. The fish is landed at the
## rod's tip. A bigger fish pulls harder; a tired one, less.

## How fast the line comes in, m/s, against a fish not pulling.
const REEL := 1.6
## How fast a fresh fish of pull 1 swims, m/s.
const SPEED := 1.6
## The line's strain from reeling alone, at the limit 1.
const REEL_STRAIN := 0.25
## How quickly the strain follows the pull, per second.
const EASE := 5.0
## Seconds at the limit before the line snaps.
const SNAP_TIME := 0.7
## Slack beyond this, metres, for SLIP_TIME seconds, and the hook slips.
const SLIP_SLACK := 0.4
const SLIP_TIME := 2.0
## How fast a fish of pull 1 swims the rod to its side, per second (the
## rod goes from -1, left, to 1, right).
const ROD_DRAG := 1.5
## How much faster a fish tires while the rod is held against it.
const TIRE_AGAINST := 1.5
## A fish heads this far off straight away from you, radians, at most
## on a run, and turns toward you on one in TOWARD of its turns.
const RUN_ANGLE := 1.4
const TOWARD := 0.15

## How hard it runs, about 1 near the line's limit; how long before it
## tires, seconds; how often it turns, per second ([FishSpecies]).
var pull := 0.5
var stamina := 5.0
var temper := 0.5
## Where the fish is, on the water's plane (x, z).
var fish := Vector2.ZERO
## How much line is out, metres.
var line := 0.0
## The line's longest, metres; landed this near the rod's tip.
var max_line := 30.0
var back := 1.5
## Where it heads, radians off straight away from the rod's tip:
## positive to your right, past ±PI/2 toward you.
var heading := 0.0
## 1 fresh, 0 tired out.
var energy := 1.0
## The line's strain, 0 slack, 1 at its limit.
var strain := 0.0
## Where the rod's tip is pushed, -1 left to 1 right.
var rod := 0.0
## "" while it lasts, then "landed", "snapped" or "slipped".
var outcome := ""
## Set when the fish starts a run (a splash); [Fishing] clears it.
var ran := false
## Whether the fish can swim to a point (x, z): water, not land. Every
## point by default.
var swimmable: Callable = func(_at: Vector2) -> bool: return true

var _rng: RandomNumberGenerator
var _size := 1.0 # pull's scale for the fish's size
var _turn_in := 0.0
var _snap_timer := 0.0
var _slack_timer := 0.0


## A fight with a fish of [param species] [param size_cm] long at
## [param at], with [param p_line] metres of line out.
func _init(species: Dictionary, size_cm: int, at: Vector2, p_line: float, rng: RandomNumberGenerator) -> void:
	pull = species.get("pull", pull)
	stamina = species.get("stamina", stamina)
	temper = species.get("temper", temper)
	var lo: float = species["size"][0]
	var hi: float = species["size"][1]
	_size = lerpf(0.8, 1.25, clampf((size_cm - lo) / maxf(hi - lo, 1.0), 0.0, 1.0))
	fish = at
	line = p_line
	_rng = rng
	_turn()


## Pushes the rod's tip by [param by] (the mouse; positive to the right).
func push(by: float) -> void:
	rod = clampf(rod + by, -1.0, 1.0)


## How hard the fish pulls now: its pull, for its size, as tired as it is.
func power() -> float:
	return pull * _size * (0.35 + 0.65 * energy)


## How much the rod is held against the fish's side, -1 (with it) to 1.
func against() -> float:
	var lat := sin(heading)
	return clampf(-rod * signf(lat) * minf(absf(lat) * 2.0, 1.0), -1.0, 1.0)


## The fight's next [param delta] seconds, the rod's tip at [param tip]
## (x, z), the click held or not.
func step(delta: float, tip: Vector2, reeling: bool) -> void:
	if outcome != "":
		return
	_turn_in -= delta
	if _turn_in <= 0.0:
		_turn()
	var p := power()
	var away := (fish - tip).normalized() if fish.distance_to(tip) > 0.01 else Vector2.UP
	var lat := sin(heading)
	var ahead := fish + away.rotated(heading) * SPEED * p * delta
	if swimmable.call(ahead):
		fish = ahead
	else:
		_turn()
	if reeling:
		line -= REEL * maxf(1.0 - 0.8 * maxf(cos(heading), 0.0) * p, 0.1) * delta
	var dist := fish.distance_to(tip)
	if dist > line:
		if reeling:
			fish = tip + (fish - tip).normalized() * line
			dist = line
		else:
			line = dist # the reel's drag gives line
	var slack := line - dist
	var aim := 0.0
	var pushing := against()
	if slack <= 0.05:
		if reeling:
			aim = REEL_STRAIN + p * (maxf(cos(heading), 0.0) * (1.0 - 0.5 * maxf(pushing, 0.0)) + 0.8 * maxf(-pushing, 0.0))
		else:
			aim = 0.1 + 0.5 * p * maxf(cos(heading), 0.0)
		energy = maxf(energy - delta / stamina * (1.0 + TIRE_AGAINST * maxf(pushing, 0.0)), 0.0)
	strain = move_toward(strain, aim, EASE * delta)
	rod = clampf(rod + lat * p * ROD_DRAG * delta, -1.0, 1.0)
	_snap_timer = _snap_timer + delta if strain >= 1.0 else 0.0
	_slack_timer = _slack_timer + delta if slack > SLIP_SLACK else 0.0
	if _snap_timer >= SNAP_TIME or line > max_line:
		outcome = "snapped"
	elif _slack_timer >= SLIP_TIME:
		outcome = "slipped"
	elif dist < back:
		outcome = "landed"


## The slack in the line, metres, the rod's tip at [param tip].
func slack(tip: Vector2) -> float:
	return maxf(line - fish.distance_to(tip), 0.0)


# A new way to swim: mostly away and to a side, now and then toward you.
func _turn() -> void:
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	if _rng.randf() < TOWARD:
		heading = side * _rng.randf_range(1.9, 2.6)
	else:
		heading = side * _rng.randf_range(0.0, RUN_ANGLE)
	_turn_in = _rng.randf_range(0.6, 1.4) / temper
	ran = true
