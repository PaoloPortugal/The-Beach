class_name FishFight
extends RefCounted
## A fight with a hooked fish (D01), on the water's plane, seen from
## above: [Fishing] steps it each frame and shows it in the world (the
## rod bending, the line, the shadow, the view pulled with the rod) and
## by an arrow by the crosshair. Now and then the fish makes a run, hard
## away and to a side; between runs it swims weaker, one way and another.
## Holding the click reels the line in; letting go, the reel's drag gives
## line as the fish runs, keeping the line taut, and a run against the
## drag tires it fast. Reeling into a run snaps the line. The fish drags
## the rod's tip toward the side it swims to, and the mouse pushes it
## back: held against the fish, the rod takes some of its pull, tires it
## faster and turns its head round toward you, ending a run. Walking away
## while reeling tows it, straining the line too. The line snaps after a
## moment at its limit or when the fish has run out all the line; the
## hook slips off after a while slack. The fish is landed at the rod's
## tip. A bigger fish pulls harder; a tired one, less.

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
## How much faster a fish tires while the rod is held against it, and
## on a run.
const TIRE_AGAINST := 1.5
const RUN_TIRE := 3.0
## How much of the reel's gain is lost with the rod fully on the fish's
## side.
const WITH_SLOW := 0.8
## How fast the rod held fully against a fish turns its head toward you,
## radians/s.
const STEER := 1.5
## Let go, the drag's strain: 0.1 + DRAG_STRAIN × the pull, the pull
## counted up to DRAG_MOST (so at most 0.8: under the line's trembling,
## never its limit).
const DRAG_STRAIN := 0.5
const DRAG_MOST := 1.4
## Walking away while reeling: the strain per m/s, times (0.5 + power).
const WALK_STRAIN := 0.12
## Runs: how much harder it pulls on one and between them; the seconds
## between them (divided by 0.5 + temper) and of one (min, max, shorter
## tired); how far to a side it heads, radians (min, max); how far it
## jerks the rod; no runs below RUN_ENERGY.
const RUN_PULL := 2.0
const REST_PULL := 0.6
const RUN_GAP := Vector2(2.0, 4.0)
const RUN_TIME := Vector2(1.0, 2.0)
const RUN_SIDE := Vector2(0.4, 1.2)
const RUN_JERK := 0.3
const RUN_ENERGY := 0.1
## Between runs a fish heads this far off straight away from you,
## radians, at most, and turns toward you on one in TOWARD of its turns.
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
## Whether it's on a run.
var running := false
## Set when the fish starts a run (a splash); [Fishing] clears it.
var ran := false
## How fast the rod's tip is going away from the fish, m/s (walking).
var walk := 0.0
## Whether the fish can swim to a point (x, z): water, not land. Every
## point by default.
var swimmable: Callable = func(_at: Vector2) -> bool: return true

var _rng: RandomNumberGenerator
var _size := 1.0 # pull's scale for the fish's size
var _turn_in := 0.0
var _run_in := 0.0
var _tip_was := Vector2(NAN, NAN)
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
	_rest()
	_turn()
	_run_in *= 0.5 # the first run comes soon after the hook


## Pushes the rod's tip by [param by] (the mouse; positive to the right).
func push(by: float) -> void:
	rod = clampf(rod + by, -1.0, 1.0)


## How hard the fish pulls now: its pull, for its size, as tired as it
## is, harder on a run.
func power() -> float:
	return pull * _size * (0.35 + 0.65 * energy) * (RUN_PULL if running else REST_PULL)


## How much the rod is held against the fish's side, -1 (with it) to 1.
func against() -> float:
	var lat := sin(heading)
	return clampf(-rod * signf(lat) * minf(absf(lat) * 2.0, 1.0), -1.0, 1.0)


## The fight's next [param delta] seconds, the rod's tip at [param tip]
## (x, z), the click held or not.
func step(delta: float, tip: Vector2, reeling: bool) -> void:
	if outcome != "":
		return
	# Walking away from the fish, m/s, smoothed (the rod's tip also sways
	# with the rod).
	if not is_nan(_tip_was.x):
		var walked := (fish.distance_to(tip) - fish.distance_to(_tip_was)) / maxf(delta, 0.0001)
		walk = lerpf(walk, walked, minf(10.0 * delta, 1.0))
	_tip_was = tip
	_run_in -= delta
	if running:
		if _run_in <= 0.0 or absf(heading) > PI / 2.0:
			_rest()
	elif _run_in <= 0.0:
		_run()
	else:
		_turn_in -= delta
		if _turn_in <= 0.0:
			_turn()
	var p := power()
	var away := (fish - tip).normalized() if fish.distance_to(tip) > 0.01 else Vector2.UP
	var lat := sin(heading)
	var ahead := fish + away.rotated(heading) * SPEED * p * delta
	if swimmable.call(ahead):
		fish = ahead
	elif running:
		_rest()
	else:
		_turn()
	# Reeling: slowed by a fish running away, less so with the rod held
	# against it; with the rod on its side, the reel hardly gains.
	var pushing := against()
	if reeling:
		var gain := maxf(1.0 - 0.8 * maxf(cos(heading), 0.0) * p * (1.0 - 0.5 * maxf(pushing, 0.0)), 0.1)
		line -= REEL * gain * (1.0 - WITH_SLOW * maxf(-pushing, 0.0)) * delta
	var dist := fish.distance_to(tip)
	if dist > line:
		if reeling:
			fish = tip + (fish - tip).normalized() * line
			dist = line
		else:
			line = dist # the reel's drag gives line
	var slack := line - dist
	var aim := 0.0
	if slack <= 0.05:
		var pulling := maxf(cos(heading), 0.0) * p
		if reeling:
			aim = REEL_STRAIN + pulling * (1.0 - 0.5 * maxf(pushing, 0.0)) + 0.8 * p * maxf(-pushing, 0.0)
			aim += WALK_STRAIN * maxf(walk, 0.0) * (0.5 + p)
		else:
			aim = 0.1 + DRAG_STRAIN * minf(pulling, DRAG_MOST)
		energy = maxf(energy - delta / stamina * (1.0 + TIRE_AGAINST * maxf(pushing, 0.0)) * (RUN_TIRE if running else 1.0), 0.0)
		# Held against it, the rod turns its head round toward you.
		if pushing > 0.0:
			heading = signf(heading) * minf(absf(heading) + STEER * pushing * delta, PI)
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


## Which way to push the rod and how much, -1 (left) to 1 (right): away
## from the fish's side, as hard as it pulls there, less as the rod is
## held against it (the arrow by the crosshair).
func hint() -> float:
	var lat := sin(heading)
	var side := minf(absf(lat) * 2.0, 1.0) * minf(power(), 1.0)
	return -signf(lat) * side * (1.0 - maxf(against(), 0.0))


## The slack in the line, metres, the rod's tip at [param tip].
func slack(tip: Vector2) -> float:
	return maxf(line - fish.distance_to(tip), 0.0)


# A new way to swim between runs: mostly away and to a side, now and
# then toward you.
func _turn() -> void:
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	if _rng.randf() < TOWARD:
		heading = side * _rng.randf_range(1.9, 2.6)
	else:
		heading = side * _rng.randf_range(0.0, RUN_ANGLE)
	_turn_in = _rng.randf_range(0.6, 1.4) / temper


# A run: away and hard to a side, a splash, the rod jerked that way;
# shorter the more tired it is. Tired out, it doesn't run.
func _run() -> void:
	if energy < RUN_ENERGY:
		_run_in = INF
		return
	running = true
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	heading = side * _rng.randf_range(RUN_SIDE.x, RUN_SIDE.y)
	_run_in = _rng.randf_range(RUN_TIME.x, RUN_TIME.y) * (0.5 + 0.5 * energy)
	rod = clampf(rod + side * RUN_JERK, -1.0, 1.0)
	ran = true


# The run over: it swims on as it heads (turned by the rod, it keeps
# coming) until its next turn, and runs again later.
func _rest() -> void:
	running = false
	_run_in = _rng.randf_range(RUN_GAP.x, RUN_GAP.y) / (0.5 + temper)
	_turn_in = _rng.randf_range(0.6, 1.4) / temper
