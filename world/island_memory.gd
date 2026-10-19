class_name IslandMemory
extends RefCounted
## What each live session's island was (W12): its biome and seed, its
## cluster, and its spot in it, kept in a file so a session taken back
## after a restart (S07) gets its island back as it was. Keyed by
## [method key], which stays the same across a restart and a /clear. A
## missing or damaged file, or a damaged entry, is ignored: that island
## comes back as a new one would.

## Where it's kept. The suites use their own (tests/error_watch.gd).
static var file := "user://islands.json"

const VERSION := 1
const NUMBERS: Array[String] = ["biome", "seed", "slot", "index"]

var _entries := {} # key → entry


## Reads the file, if any.
func load_file() -> void:
	_entries.clear()
	if not FileAccess.file_exists(file):
		return
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(file)) == OK else null
	if not (data is Dictionary and data.get("version") == VERSION and data.get("islands") is Dictionary):
		push_warning("IslandMemory: %s isn't usable; islands come back as new" % file)
		return
	for k: Variant in data["islands"]:
		var e: Variant = data["islands"][k]
		if k is String and _valid(e):
			for f: String in NUMBERS:
				e[f] = int(e[f]) # JSON gives floats
			_entries[k] = e


## The session's key: its provider, start and project, or "" when the
## snapshot lacks them.
static func key(session: Dictionary) -> String:
	var provider: Variant = session.get("provider")
	var started: Variant = session.get("started_at")
	var project: Variant = session.get("project")
	if not (provider is String and started is String and project is Dictionary and project.get("path") is String):
		return ""
	return "%s|%s|%s" % [provider, started, project["path"]]


## The saved entry for a key, or {}: {"biome", "seed", "cluster" (the
## cluster's id when saved), "name", "repo_key" ("" for one made by
## hand), "slot", "index"}.
func entry(k: String) -> Dictionary:
	return _entries.get(k, {})


func has(k: String) -> bool:
	return _entries.has(k)


func put(k: String, e: Dictionary) -> void:
	if k.is_empty():
		return
	_entries[k] = e
	_save()


func erase(k: String) -> void:
	if _entries.erase(k):
		_save()


## Drops every entry whose key isn't in [param live].
func keep_only(live: Dictionary) -> void:
	var gone := _entries.keys().filter(func(k: String) -> bool: return not live.has(k))
	for k: String in gone:
		_entries.erase(k)
	if not gone.is_empty():
		_save()


## The keys, ordered as their islands were: by slot, then index.
func ordered(keys: Array) -> Array:
	var out := keys.filter(func(k: String) -> bool: return _entries.has(k))
	out.sort_custom(func(a: String, b: String) -> bool:
		var ea: Dictionary = _entries[a]
		var eb: Dictionary = _entries[b]
		return ea["slot"] < eb["slot"] or (ea["slot"] == eb["slot"] and ea["index"] < eb["index"]))
	return out


func _save() -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		push_warning("IslandMemory: can't write %s (%s)" % [file, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify({"version": VERSION, "islands": _entries}))


static func _valid(e: Variant) -> bool:
	if not e is Dictionary:
		return false
	for f: String in ["cluster", "name", "repo_key"]:
		if not e.get(f) is String:
			return false
	for f: String in NUMBERS:
		if not (e.get(f) is float or e.get(f) is int):
			return false
	return Biome.NAMES.has(int(e["biome"])) and int(e["seed"]) != 0
