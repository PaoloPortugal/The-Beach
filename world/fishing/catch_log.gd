class_name CatchLog
extends RefCounted
## Every fish you've caught (D01), for the collection (D03), kept between
## runs: per species, how many, the biggest's size and the first catch
## (when, and where: the biome and the water). It never depends on agents
## or sessions. D03's field guide will show it.
##
## A damaged file is kept beside it as `.bad` and the log starts empty,
## so a catch never writes over what could still be recovered.

## Where it's kept; the suites use their own (tests/error_watch.gd).
static var file := "user://catches.json"

const VERSION := 1

var _species := {} # species id → {"count", "biggest_cm", "first": {"at", "biome", "water"}}
var _task := -1 # the WorkerThreadPool task writing the file, till waited for


## Reads the file, if any.
func load_file() -> void:
	flush()
	_species.clear()
	if not FileAccess.file_exists(file):
		return
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(file)) == OK else null
	if not (data is Dictionary and data.get("version") == VERSION and data.get("species") is Dictionary and _all_valid(data["species"])):
		push_warning("CatchLog: %s isn't usable; kept as .bad, starting empty" % file)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(file), ProjectSettings.globalize_path(file + ".bad"))
		return
	for id: String in data["species"]:
		var e: Dictionary = data["species"][id]
		e["count"] = int(e["count"]) # JSON gives floats
		e["biggest_cm"] = int(e["biggest_cm"])
		_species[id] = e


## Records a catch of [param id], [param size_cm] long, in [param biome]
## (a name, "" away from islands) and [param water]; saves. True when
## it's the species' first.
func record(id: String, size_cm: int, biome: String, water: String) -> bool:
	var first := not _species.has(id)
	if first:
		_species[id] = {"count": 0, "biggest_cm": 0,
			"first": {"at": Time.get_datetime_string_from_system(), "biome": biome, "water": water}}
	var e: Dictionary = _species[id]
	e["count"] += 1
	e["biggest_cm"] = maxi(e["biggest_cm"], size_cm)
	_save()
	return first


## The species caught, by id.
func caught() -> Array[String]:
	var out: Array[String] = []
	out.assign(_species.keys())
	return out


## A species' record ({} if never caught): "count", "biggest_cm" and
## "first" ({"at": local date and time, "biome", "water"}).
func entry(id: String) -> Dictionary:
	return _species.get(id, {})


## Waits till the last catch is in the file.
func flush() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


# Written on a worker thread (a write is several ms on Windows, W12), one
# at a time: catches are far apart.
func _save() -> void:
	flush()
	var path := file
	var text := JSON.stringify({"version": VERSION, "species": _species}, "\t")
	_task = WorkerThreadPool.add_task(CatchLog._write.bind(path, text), false, "Catch log")


# To a .tmp first and renamed over, so a crash never leaves half a file.
static func _write(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("CatchLog: can't write %s" % tmp)
		return
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("CatchLog: can't write %s (%s)" % [path, error_string(err)])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


static func _all_valid(species: Dictionary) -> bool:
	for id: Variant in species:
		var e: Variant = species[id]
		if not (id is String and e is Dictionary):
			return false
		for f: String in ["count", "biggest_cm"]:
			var n: Variant = e.get(f)
			if not ((n is float or n is int) and n >= 0 and n <= 2147483647):
				return false
		var first: Variant = e.get("first")
		if not first is Dictionary:
			return false
		for f: String in ["at", "biome", "water"]:
			if not first.get(f) is String:
				return false
	return true
