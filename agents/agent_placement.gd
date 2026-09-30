class_name AgentPlacement
extends RefCounted
## Where subagents sit around their orchestrator (A04): rings of fixed
## slots. Slot 0 is the first place on the innermost ring; each ring holds
## as many slots as fit at [constant SPACING] apart, and there are as many
## rings as needed (no maximum). Positions are relative to the
## orchestrator, on the ground plane (x, z). A slot's small jitter comes
## from its number, so a slot is always in the same place.

## Radius of the first ring, metres: outside the orchestrator's chat zone.
const FIRST_RING := 10.0
## Distance between rings, and between slots along a ring.
const RING_GAP := 3.0
const SPACING := 3.0
## Up to this far off the exact spot, in each direction.
const JITTER := 0.4


static func ring_radius(ring: int) -> float:
	return FIRST_RING + RING_GAP * ring


static func slots_in_ring(ring: int) -> int:
	return int(TAU * ring_radius(ring) / SPACING)


## The ring a slot is on, and its place along it: Vector2i(ring, index).
static func ring_of(slot: int) -> Vector2i:
	var ring := 0
	while slot >= slots_in_ring(ring):
		slot -= slots_in_ring(ring)
		ring += 1
	return Vector2i(ring, slot)


static func slot_position(slot: int) -> Vector2:
	var at := ring_of(slot)
	var n := slots_in_ring(at.x)
	# Each ring is turned half a step so agents don't line up behind each other.
	var angle := (at.y + 0.5 * (at.x % 2)) * TAU / n
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot)
	var r := ring_radius(at.x) + rng.randf_range(-JITTER, JITTER)
	angle += rng.randf_range(-JITTER, JITTER) / r
	return Vector2(cos(angle), sin(angle)) * r
