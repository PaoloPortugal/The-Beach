class_name SessionClusters
extends RefCounted
## Clusters (W05; user's decisions, 2026-10-02): islands of the same git
## repository, worktrees included, sit together. A session joins its
## repository's cluster on its own (by project folder outside git); the
## first one of a repository makes a new cluster, named after it, and
## later ones join that cluster (not one a session of it was moved to). When
## starting or resuming, the sessions menu can pick another running
## cluster or a new one instead. A cluster lasts while it has sessions:
## with the last one gone, it and its spot are freed.
##
## Layout, until bridges (W06): each cluster takes a spot on rings around
## the spawn platform; its islands sit close together around that spot,
## the first in the middle.

## Cluster membership or names changed.
signal changed

## Choices for [method choose]: by repository, or a new cluster. Any other
## value is a cluster id.
const AUTOMATIC := ""
const NEW := "new"

## Distance from the platform to the first ring of clusters, and between
## rings, metres; six clusters per ring.
const RING_SPACING := 360.0
const PER_RING := 6
## Distance between neighbouring islands of a cluster, metres. An island's
## land reaches about 40 m from its centre (its sea floor, about 67 m).
const ISLAND_SPACING := 100.0

## Cluster id → {"name": String, "slot": int, "sessions": {session id →
## island index}, "key": the repository (or folder outside git) it was
## made for automatically, "" for one made by hand}.
var _clusters := {}
## Session id → cluster id.
var _of := {}
## Session id → the choice made when it was started, until it comes up.
var _choices := {}
var _next_id := 1


## Records where a session being started should go (a [constant AUTOMATIC],
## [constant NEW] or a cluster id), before it comes up.
func choose(session_id: String, choice: String) -> void:
	_choices[session_id] = choice


## Puts a session that came up in its cluster; returns the cluster id.
## [param session] is the protocol's session object.
func add(session_id: String, session: Dictionary) -> String:
	if _of.has(session_id):
		return _of[session_id]
	var project: Dictionary = session.get("project", {})
	var choice: String = _choices.get(session_id, AUTOMATIC)
	_choices.erase(session_id)
	var id := ""
	if choice == NEW:
		id = _new_cluster(SessionsMenu.project_name(project), "")
	elif _clusters.has(choice):
		id = choice
	else:
		id = _cluster_for(_key(project))
		if id.is_empty():
			var repo: String = project.get("repo", "")
			id = _new_cluster(repo.get_file() if not repo.is_empty() else SessionsMenu.project_name(project), _key(project))
	var members: Dictionary = _clusters[id]["sessions"]
	var index := 0
	while index in members.values():
		index += 1
	members[session_id] = index
	_of[session_id] = id
	changed.emit()
	return id


## Takes a session out; its cluster goes with its last session.
func remove(session_id: String) -> void:
	_choices.erase(session_id)
	if not _of.has(session_id):
		return
	var id: String = _of[session_id]
	_of.erase(session_id)
	_clusters[id]["sessions"].erase(session_id)
	if _clusters[id]["sessions"].is_empty():
		_clusters.erase(id)
	changed.emit()


## The cluster ids, in the order of their spots.
func ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_clusters.keys())
	out.sort_custom(func(a: String, b: String) -> bool: return _clusters[a]["slot"] < _clusters[b]["slot"])
	return out


func cluster_of(session_id: String) -> String:
	return _of.get(session_id, "")


func cluster_name(cluster_id: String) -> String:
	return _clusters.get(cluster_id, {}).get("name", "")


## A cluster's sessions, in the order of their islands.
func sessions(cluster_id: String) -> Array[String]:
	var members: Dictionary = _clusters.get(cluster_id, {}).get("sessions", {})
	var out: Array[String] = []
	out.assign(members.keys())
	out.sort_custom(func(a: String, b: String) -> bool: return members[a] < members[b])
	return out


## Where a session's island goes.
func island_position(session_id: String) -> Vector3:
	var id: String = _of[session_id]
	return cluster_position(_clusters[id]["slot"]) + island_offset(_clusters[id]["sessions"][session_id])


## The middle of the cluster in spot [param slot]: on rings around the
## platform, each ring turned half a step so clusters don't line up.
static func cluster_position(slot: int) -> Vector3:
	var ring := slot / PER_RING
	var angle := (slot % PER_RING + ring * 0.5) * TAU / PER_RING
	var r := RING_SPACING * (ring + 1)
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)


## Island [param index] of a cluster, from its middle: the first in the
## middle, then rings of 6, 12, 18... at whole multiples of
## [constant ISLAND_SPACING].
static func island_offset(index: int) -> Vector3:
	if index == 0:
		return Vector3.ZERO
	var ring := 1
	var first := 1
	while index >= first + 6 * ring:
		first += 6 * ring
		ring += 1
	var angle := float(index - first) * TAU / (6 * ring)
	var r := ISLAND_SPACING * ring
	return Vector3(cos(angle) * r, 0.0, sin(angle) * r)


static func _key(project: Dictionary) -> String:
	var repo: String = project.get("repo", "")
	return repo if not repo.is_empty() else str(project.get("path", ""))


## The cluster made automatically for this repository, or "". Sessions
## of it put elsewhere by hand don't count.
func _cluster_for(key: String) -> String:
	for id in _clusters:
		if _clusters[id]["key"] == key:
			return id
	return ""


func _new_cluster(base: String, key: String) -> String:
	var names := {}
	for c in _clusters.values():
		names[c["name"]] = true
	if base.is_empty():
		base = "Cluster"
	var cluster_name := base
	var n := 2
	while names.has(cluster_name):
		cluster_name = "%s %d" % [base, n]
		n += 1
	var slots := {}
	for c in _clusters.values():
		slots[c["slot"]] = true
	var slot := 0
	while slots.has(slot):
		slot += 1
	var id := str(_next_id)
	_next_id += 1
	_clusters[id] = {"name": cluster_name, "slot": slot, "sessions": {}, "key": key}
	return id
