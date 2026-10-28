class_name FishSpecies
extends RefCounted
## What can bite (D01): the fish and where and when each lives. What bites
## depends only on the world, never on agents: the water under the bobber,
## the nearest island's biome (W10), the time of day and the weather (W09).
## Placeholders, one per kind of water, until the user's real list.
##
## Each species:
## - id: kept in the collection's file (CatchLog); never change one.
## - name: as the catch card shows it.
## - water: the kinds of water it lives in: "shallows", "drop_off",
##   "open_sea" (see [method water_at]).
## - biomes: the islands it lives by ([enum Biome.Kind]); [] anywhere,
##   also away from any island (the platform, the open sea).
## - hours: [from, to] on a 24-hour clock, past midnight if from > to;
##   [] any time.
## - weather: the weathers it's out in (Weather.NAMES); [] any.
## - size: [smallest, biggest] in cm; big ones are rarer.
## - weight: how common it is among those that match.
## - pull, stamina, temper: how it fights ([FishFight]): how hard it
##   pulls (about 1 strains the line to its limit between runs while
##   reeled with the rod on its side; on a run it pulls twice as hard),
##   how long before it tires, seconds, and how often it turns and runs.
const SPECIES := [
	{"id": "shallows_fish", "name": "Shallows fish", "water": ["shallows"], "biomes": [], "hours": [], "weather": [], "size": [12, 30], "weight": 1.0, "pull": 0.5, "stamina": 18.0, "temper": 0.7},
	{"id": "drop_off_fish", "name": "Drop-off fish", "water": ["drop_off"], "biomes": [], "hours": [], "weather": [], "size": [25, 60], "weight": 1.0, "pull": 0.85, "stamina": 30.0, "temper": 0.5},
	{"id": "open_sea_fish", "name": "Open sea fish", "water": ["open_sea"], "biomes": [], "hours": [], "weather": [], "size": [40, 120], "weight": 1.0, "pull": 1.2, "stamina": 50.0, "temper": 0.4},
]

## The kinds of water, by the depth under the bobber: the islands' shelf
## (4 m down, W08) is the shallows, the sea floor (14 m and deeper) the
## open sea, and between them the drop-off.
const WATERS: Array[String] = ["shallows", "drop_off", "open_sea"]
const DROP_OFF_FROM := 4.5
const OPEN_SEA_FROM := 12.0


## The kind of water [param depth] metres deep is.
static func water_at(depth: float) -> String:
	if depth < DROP_OFF_FROM:
		return "shallows"
	if depth < OPEN_SEA_FROM:
		return "drop_off"
	return "open_sea"


## The species of [param table] that live in [param conditions]:
## {"water": String, "biome": int ([enum Biome.Kind], -1 for none),
## "hour": float, "weather": String}.
static func matching(conditions: Dictionary, table: Array = SPECIES) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in table:
		if not conditions["water"] in s["water"]:
			continue
		if not s["biomes"].is_empty() and not conditions["biome"] in s["biomes"]:
			continue
		if not s["weather"].is_empty() and not conditions["weather"] in s["weather"]:
			continue
		if not s["hours"].is_empty() and not _in_hours(conditions["hour"], s["hours"][0], s["hours"][1]):
			continue
		out.append(s)
	return out


## The species that comes for a roll [param r] in [0, 1), by weight among
## those matching; {} if none lives there.
static func pick(conditions: Dictionary, r: float, table: Array = SPECIES) -> Dictionary:
	var found := matching(conditions, table)
	var total := 0.0
	for s in found:
		total += s["weight"]
	var at := r * total
	for s in found:
		at -= s["weight"]
		if at < 0.0:
			return s
	return {} if found.is_empty() else found[-1]


## A fish's size in whole cm for a roll [param r] in [0, 1): the big ones
## rarer.
static func size_for(species: Dictionary, r: float) -> int:
	var lo: float = species["size"][0]
	var hi: float = species["size"][1]
	return roundi(lo + (hi - lo) * pow(r, 1.6))


## The species with [param id], or {}.
static func named(id: String, table: Array = SPECIES) -> Dictionary:
	for s: Dictionary in table:
		if s["id"] == id:
			return s
	return {}


static func _in_hours(hour: float, from: float, to: float) -> bool:
	if from <= to:
		return hour >= from and hour < to
	return hour >= from or hour < to
