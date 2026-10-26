class_name IslandMemory
extends RefCounted
## What each live session's island was (W12): its biome and seed, its
## cluster, and its spot in it, kept in a file so a session taken back
## after a restart (S07) gets its island back as it was. Keyed by
## [method key], which stays the same across a restart and a /clear, and
## by [method alias], which stays the same when an app relaunches a
## session's process (S08). A
## missing or damaged file, or a damaged entry, is ignored: that island
## comes back as a new one would.

## Where it's kept. The suites use their own (tests/error_watch.gd), and
## so does a run with the fake provider, whose sessions would otherwise
## replace the real ones' entries.
static var file := "user://dev-fake-islands.json" if "--sidecar-dev-fake" in OS.get_cmdline_user_args() else "user://islands.json"

const VERSION := 1
const NUMBERS: Array[String] = ["biome", "seed", "slot", "index"]
const MAX_TEXT := 4096 # a long project path (Linux allows 4096)

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


## Its second key: its provider and the provider's own id for it, or ""
## without one. Entries are kept under both, so one is found when the
## other changed: a session started outside the game (S08) whose app
## relaunched its process starts again, and /clear gives a new id.
static func alias(session: Dictionary) -> String:
	var provider: Variant = session.get("provider")
	var native: Variant = session.get("native_id")
	if not (provider is String and native is String and not native.is_empty()):
		return ""
	return "%s|id|%s" % [provider, native]


## The first of [param keys] with an entry, or "".
func find(keys: Array) -> String:
	for k: String in keys:
		if not k.is_empty() and _entries.has(k):
			return k
	return ""


## The saved entry for a key, or {}: {"biome", "seed", "cluster" (the
## cluster's id when saved), "name", "repo_key" ("" for one made by
## hand), "slot", "index"}.
func entry(k: String) -> Dictionary:
	return _entries.get(k, {})


func has(k: String) -> bool:
	return _entries.has(k)


## Keeps [param e] under each of [param keys] ("" ones skipped).
func put(keys: Array, e: Dictionary) -> void:
	var changed := false
	for k: String in keys:
		if not k.is_empty():
			_entries[k] = e
			changed = true
	if changed:
		_save()


func erase(keys: Array) -> void:
	var changed := false
	for k: String in keys:
		changed = _entries.erase(k) or changed
	if changed:
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


## Owner-only where the system has permissions (macOS, Linux), like the
## sidecar's run folders: it holds running sessions' project paths. Written
## to a .tmp first and renamed over, so a crash never leaves half a file.
func _save() -> void:
	var tmp := file + ".tmp"
	# Created empty and restricted before anything is written to it.
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f != null:
		f.close()
		var err := FileAccess.set_unix_permissions(tmp, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
		f = FileAccess.open(tmp, FileAccess.READ_WRITE) if err == OK or err == ERR_UNAVAILABLE else null
	if f == null:
		push_warning("IslandMemory: can't write %s" % tmp)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return
	f.store_string(JSON.stringify({"version": VERSION, "islands": _entries}))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(file))
	if err != OK:
		push_warning("IslandMemory: can't write %s (%s)" % [file, error_string(err)])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


## An entry as [method put] writes it: its strings at most [constant
## MAX_TEXT] long, its numbers within 32 bits, a known biome, a seed not 0.
static func _valid(e: Variant) -> bool:
	if not e is Dictionary:
		return false
	for f: String in ["cluster", "name", "repo_key"]:
		if not (e.get(f) is String and e[f].length() <= MAX_TEXT):
			return false
	for f: String in NUMBERS:
		var n: Variant = e.get(f)
		if not ((n is float or n is int) and n >= -2147483648 and n <= 2147483647):
			return false
	return Biome.NAMES.has(int(e["biome"])) and int(e["seed"]) != 0
