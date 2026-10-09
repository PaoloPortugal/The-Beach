class_name Biome
extends RefCounted
## The kinds of island (W10): each sets an island's heights, colours and
## props (see IslandGenerator and IslandProps). Picked per island in the
## sessions menu; "Random" rolls one (user's, 2026-10-08).

enum Kind { BEACH, FOREST, MOUNTAIN, SNOWY, DESERT }

## The sessions menu's choice for "roll one for this island".
const RANDOM := -1

## Names as the sessions menu shows them, by [enum Kind].
const NAMES := {
	Kind.BEACH: "Beach",
	Kind.FOREST: "Forest",
	Kind.MOUNTAIN: "Mountain",
	Kind.SNOWY: "Snowy",
	Kind.DESERT: "Desert",
}

## Each kind's shape, colours and props. Heights in metres above the water.
## - edge: where bridges meet the island (W06), the top of the slope up
##   from the beach; a shoulder that high runs round the island.
## - plateau: the flat middle, where the orchestrator stands.
## - hills: how high the hills between the shoulder and the middle reach;
##   hill_gain (2.5 if absent) scales the noise before it is clipped to
##   0-1, so a lower gain gives pointed peaks rather than flat tops.
## - wet, shore, ground, high, rock, peak: colours (sRGB) for the wet
##   sand, the beach, the ground, the ground higher up (from high_from
##   metres), steep slopes, and the tops (from peak_from metres; 0 none).
## - props: [IslandProps.Prop, weight] pairs; density: props per 100 m².
## - shore_props, shore_density: the same for the sand by the water.
## Optional, for the mountain's high meadow (user's, 2026-10-09):
## - radius, wobble: the island's rough radius and how far the noise moves
##   its shoreline (IslandGenerator's radius and 0.45 if absent).
## - meadow: the flat middle's radius (7 m if absent).
## - valley: the valleys' width (IslandGenerator's VALLEY_WIDTH if absent).
## - slope, shoulder: the rise per metre up from the beach and the
##   shoulder's width (IslandGenerator's SLOPE and SHOULDER if absent).
## - peaks: spires between the valleys (IslandGenerator._make_peaks):
##   "each" peaks per side between two valleys, "height" and, for "tall"
##   of them, "tall_height", in metres over the middle; "base" their
##   footprint's radius.
## - zipline: a zipline from the beach up to the shoulder (Zipline).
## The beach keeps W01's shape exactly (legacy).
const PROFILES := {
	Kind.BEACH: {
		"legacy": true, "edge": 0.5, "plateau": 2.0, "hills": 1.2,
		"wet": Color(0.82, 0.72, 0.52), "shore": Color(0.94, 0.85, 0.63),
		"ground": Color(0.94, 0.85, 0.63), "high": Color(0.48, 0.68, 0.34), "high_from": 2.4,
		"rock": Color(0.94, 0.85, 0.63), "peak": Color(0.48, 0.68, 0.34), "peak_from": 0.0,
		"props": [[IslandProps.Prop.PALM, 6], [IslandProps.Prop.TROPICAL_PLANT, 3]],
		"density": 1.3,
		"shore_props": [[IslandProps.Prop.SAND_CASTLE, 3], [IslandProps.Prop.STARFISH, 2], [IslandProps.Prop.SHELL, 2]],
		"shore_density": 1.0,
	},
	Kind.FOREST: {
		"legacy": false, "edge": 2.0, "plateau": 3.0, "hills": 2.0,
		"wet": Color(0.80, 0.70, 0.50), "shore": Color(0.92, 0.83, 0.60),
		"ground": Color(0.42, 0.64, 0.31), "high": Color(0.34, 0.55, 0.27), "high_from": 4.0,
		"rock": Color(0.52, 0.50, 0.45), "peak": Color(0.34, 0.55, 0.27), "peak_from": 0.0,
		"props": [[IslandProps.Prop.TREE, 6], [IslandProps.Prop.PINE, 2], [IslandProps.Prop.BUSH, 3], [IslandProps.Prop.ROCK, 1]],
		"density": 2.4,
	},
	Kind.MOUNTAIN: {
		"legacy": false, "edge": 18.0, "plateau": 20.0, "hills": 2.5,
		"radius": 36.0, "wobble": 0.15, "meadow": 11.0, "slope": 3.0, "shoulder": 3.0, "valley": 6.0,
		"peaks": {"each": [2, 3], "height": [28.0, 40.0], "tall": 2, "tall_height": [48.0, 54.0], "base": [7.0, 10.0]},
		"zipline": true,
		"wet": Color(0.74, 0.68, 0.56), "shore": Color(0.80, 0.75, 0.64),
		"ground": Color(0.47, 0.60, 0.34), "high": Color(0.56, 0.54, 0.50), "high_from": 26.0,
		"rock": Color(0.52, 0.50, 0.47), "peak": Color(0.93, 0.94, 0.96), "peak_from": 46.0,
		"props": [[IslandProps.Prop.PINE, 4], [IslandProps.Prop.ROCK, 3]],
		"density": 0.8,
	},
	Kind.SNOWY: {
		"legacy": false, "edge": 3.0, "plateau": 4.5, "hills": 3.5,
		"wet": Color(0.58, 0.60, 0.60), "shore": Color(0.74, 0.75, 0.74),
		"ground": Color(0.92, 0.94, 0.97), "high": Color(0.96, 0.97, 0.99), "high_from": 6.0,
		"rock": Color(0.50, 0.53, 0.57), "peak": Color(0.96, 0.97, 0.99), "peak_from": 0.0,
		"props": [[IslandProps.Prop.SNOW_PINE, 5], [IslandProps.Prop.ROCK, 2]],
		"density": 1.2,
	},
	Kind.DESERT: {
		"legacy": false, "edge": 0.8, "plateau": 2.5, "hills": 2.4,
		"wet": Color(0.80, 0.62, 0.44), "shore": Color(0.92, 0.74, 0.50),
		"ground": Color(0.90, 0.70, 0.46), "high": Color(0.86, 0.64, 0.42), "high_from": 3.5,
		"rock": Color(0.72, 0.48, 0.34), "peak": Color(0.86, 0.64, 0.42), "peak_from": 0.0,
		"props": [[IslandProps.Prop.CACTUS, 3], [IslandProps.Prop.DRY_SHRUB, 4], [IslandProps.Prop.RED_ROCK, 2]],
		"density": 0.6,
	},
}


static func profile(kind: int) -> Dictionary:
	return PROFILES[kind]


## A kind at random, each equally likely.
static func random_kind() -> int:
	return Kind.values().pick_random()


## [param choice] itself, or a random kind for [constant RANDOM].
static func resolve(choice: int) -> int:
	return random_kind() if choice == RANDOM else choice
