class_name DrawDistance
extends RefCounted
## Hides geometry the fog hides completely (NOTES → Architecture →
## Performance): its visibility range ends at the draw distance plus its
## own size, measured from its middle, so only what is fully fogged goes.
## [SessionIslands] applies it to everything under it, the agents and
## bridges that come later included.

## The geometry this limits, so a new distance can be applied to it again.
const GROUP := &"draw_distance"
## Set this meta on geometry that must show at any distance (A05's
## beacons, which ignore the fog).
const UNLIMITED := &"draw_distance_unlimited"


## Limits [param geometry] to [param distance] metres plus its own size;
## 0 is no limit. Geometry with a visibility range of its own (a bridge's
## near version, the message bubble) keeps it.
static func limit(geometry: GeometryInstance3D, distance: float) -> void:
	if geometry.has_meta(UNLIMITED):
		return
	if not geometry.is_in_group(GROUP):
		if geometry.visibility_range_end > 0.0:
			return
		geometry.add_to_group(GROUP)
	geometry.visibility_range_end = distance + radius(geometry) if distance > 0.0 else 0.0


## Half the diagonal of [param geometry]'s own box, unscaled (agents pop
## in and out by scaling, and nothing limited is scaled up).
static func radius(geometry: GeometryInstance3D) -> float:
	return geometry.get_aabb().size.length() / 2.0
