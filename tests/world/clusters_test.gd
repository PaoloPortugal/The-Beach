extends SceneTree
## Headless test for W05's cluster model (SessionClusters): grouping by
## repository and worktree, folders outside git, manual choices, names,
## freeing, holding an ended session's island spot (W04), and the layout:
## 8 near wedges growing without limit, then far clusters (W06).
## W12: islands kept across restarts (IslandMemory, and SessionIslands
## bringing them back after a sync).
##
##   godot --headless --path . --script res://tests/world/clusters_test.gd

const ErrorWatch := preload("res://tests/error_watch.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	var c := SessionClusters.new()
	var a := c.add("a", _s("/r/game", "game", "/r/game"))
	var b := c.add("b", _s("/r/.claude/worktrees/x", "x", "/r/game"))
	_check(a == b and c.cluster_name(a) == "game", "a worktree joins its repository's cluster, named after the repository")
	var p := c.add("p", _s("/notes", "notes"))
	_check(p != a and c.cluster_name(p) == "notes", "outside git, a folder gets its own, named after it")
	_check(c.add("p2", _s("/notes", "notes")) == p, "and the same folder joins it")
	c.choose("m", SessionClusters.NEW)
	var m := c.add("m", _s("/r/game", "game", "/r/game"))
	_check(m != a and c.cluster_name(m) == "game 2", "a new cluster when asked, with a name of its own")
	c.choose("j", p)
	_check(c.add("j", _s("/r/game", "game", "/r/game")) == p, "or a chosen running cluster")
	c.choose("h", m)
	c.add("h", _s("/elsewhere", "elsewhere", "/elsewhere"))
	c.remove("a")
	c.remove("b")
	_check(c.add("a2", _s("/r/game", "game", "/r/game")) != m, "a session moved by hand doesn't take its repository's next ones along")
	c.remove("a2")
	_check(c.add("e", _s("/elsewhere", "elsewhere", "/elsewhere")) != m, "nor does one of another repository moved in")
	c.remove("e")
	c.remove("h")
	a = c.add("a", _s("/r/game", "game", "/r/game"))
	b = c.add("b", _s("/r/.claude/worktrees/x", "x", "/r/game"))
	c.choose("k", "gone")
	_check(c.add("k", _s("/r/game", "game", "/r/game")) == a, "a cluster gone meanwhile: back to automatic")
	_check(Array(c.ids()) == [a, p, m], "clusters in the order of their spots")
	_check(Array(c.sessions(a)) == ["a", "b", "k"], "sessions in the order of their islands")
	_check(c.island_position("a").is_equal_approx(SessionClusters.cluster_position(0)), "the first island is its wedge's spot nearest the platform")
	_check(c.island_position("b").distance_to(c.island_position("a")) > 90.0, "the next ones close by")
	_check(c.island_position("a").distance_to(c.island_position("p")) > 90.0 and c.island_position("a").length() < 150.0, "clusters in their own wedges, close to the platform")
	c.remove("b")
	c.choose("n", SessionClusters.AUTOMATIC)
	c.add("n", _s("/r/game", "game", "/r/game"))
	_check(c.island_position("n") == SessionClusters.spot(0, 1), "a freed island spot is reused")
	for s in ["p", "p2", "j"]:
		c.remove(s)
	_check(not p in c.ids() and c.cluster_name(p) == "", "a cluster goes with its last session")
	var q := c.add("q", _s("/other", "other"))
	_check(c.island_position("q").is_equal_approx(SessionClusters.cluster_position(1)), "and its spot is reused")
	# W04: an ended session's island keeps its spot until it has sunk.
	var held := c.hold("q")
	_check(held != "" and c.cluster_of("q") == "" and c.sessions(q).is_empty() and not q in c.ids(), "a held island's session is out, and its cluster isn't listed")
	c.add("t", _s("/third", "third"))
	_check(c.island_position("t").is_equal_approx(SessionClusters.cluster_position(3)), "but its cluster's spot stays taken")
	_check(c.add("q2", _s("/other", "other")) == q and c.island_position("q2").is_equal_approx(SessionClusters.spot(1, 1)), "its repository's next session joins it, beside the held island")
	_check(q in c.ids() and Array(c.sessions(q)) == ["q2"], "listed again, with only its live session")
	c.remove(held)
	c.remove("q2")
	_check(c.cluster_name(q) == "" and c.add("r", _s("/fourth", "fourth")) != q and c.island_position("r").is_equal_approx(SessionClusters.cluster_position(1)), "once released, the cluster and its spot are freed")
	_check(c.hold("never") == "", "a session never added holds nothing")
	_layout()
	_overflow()
	_w12_clusters()
	_w12_memory()
	await process_frame # islands are made in the tree
	_w12_islands()
	var passed := not _failed and _errors.ok()
	if passed:
		print("PASS clusters_test")
	quit(0 if passed else 1)


# W06: the 8 near wedges' spots well apart, inside their wedges, growing
# outward without limit; far clusters' spots well apart, round their
# first islands, away from the platform, never reaching another's.
func _layout() -> void:
	var all: Array[Vector3] = []
	var outward := true
	var inside := true
	for slot in 8:
		var last := 0.0
		for index in 120:
			var p := SessionClusters.spot(slot, index)
			# How far along the wedge's middle: rows fill outward.
			var along := p.dot(Vector3(cos(slot * TAU / 8.0), 0.0, sin(slot * TAU / 8.0)))
			outward = outward and along >= last - 0.01
			last = along
			var off := absf(angle_difference(slot * TAU / 8.0, atan2(p.z, p.x)))
			inside = inside and p.length() * sin(TAU / 16.0 - off) >= SessionClusters.EDGE_MARGIN - 0.01
			all.append(p)
	var closest := _closest(all)
	_check(closest >= SessionClusters.ISLAND_SPACING - 0.01, "layout: 120 islands in each of the 8 wedges, at least 100 m apart (closest %.1f m)" % closest)
	_check(inside, "layout: every spot inside its wedge, clear of its edges")
	_check(outward, "layout: a cluster fills its wedge nearest the platform first")
	_check(SessionClusters.spot(0, 119).length() > 1500.0, "layout: and keeps growing outward (the 120th %.0f m out)" % SessionClusters.spot(0, 119).length())
	var first := SessionClusters.cluster_position(0).length()
	_check(first > 100.0 and first < 150.0, "layout: a near cluster's first island %.0f m out" % first)
	# Far clusters: the first 26 (two rings), 60 islands each.
	var around := true
	var away := true
	var nearest_first := true
	for k in 26:
		var start := SessionClusters.far_spot(k)
		var out := start.normalized()
		var last := 0.0
		for index in 60:
			var p := SessionClusters.spot(8 + k, index)
			var d := p.distance_to(start)
			nearest_first = nearest_first and d >= last - 0.01
			last = d
			away = away and (p - start).dot(out) >= -0.01
			around = around and d < 600.0
			all.append(p)
	_check(SessionClusters.cluster_position(8).length() >= SessionClusters.FAR_RADIUS - 0.01, "layout: far clusters start far out")
	_check(nearest_first and around, "layout: a far cluster's islands round its first one, nearest first")
	_check(away, "layout: fanning away from the platform")
	closest = _closest(all)
	_check(closest >= SessionClusters.ISLAND_SPACING - 0.01, "layout: far clusters' 60 islands each and the near wedges' 120 never closer than 100 m (closest %.1f m)" % closest)


# The 9th cluster goes far; a near cluster keeps growing in its wedge.
func _overflow() -> void:
	var c := SessionClusters.new()
	for k in 9:
		c.add("s%d" % k, _s("/c%d" % k, "c%d" % k))
	_check(not c.is_far(c.cluster_of("s7")) and c.is_far(c.cluster_of("s8")), "overflow: 8 near clusters, the 9th far")
	_check(c.island_position("s8").is_equal_approx(SessionClusters.far_spot(0)), "its first island at the first far cluster's place")
	for k in 30:
		c.add("t%d" % k, _s("/c0", "c0"))
	_check(c.cluster_of("t29") == c.cluster_of("s0") and c.island_position("t29").is_equal_approx(SessionClusters.spot(0, 30)), "a near cluster's 31st island is still in its wedge")
	for k in 3:
		c.add("f%d" % k, _s("/c8", "c8"))
	var far := c.cluster_of("s8")
	_check(c.cluster_of("f2") == far and c.island_position("f2").is_equal_approx(SessionClusters.spot(8, 3)), "a far cluster grows round its first island")
	var held := c.hold("f0")
	c.add("u", _s("/c8", "c8"))
	_check(c.island_position(held).is_equal_approx(SessionClusters.spot(8, 1)) and c.island_position("u").is_equal_approx(SessionClusters.spot(8, 4)), "a held far island keeps its spot")
	for id in ["s8", "f1", "f2", "u"]:
		c.remove(id)
	_check(c.cluster_name(far) != "", "a far cluster with only a held island keeps its spot")
	_check(c.is_far(c.add("w", _s("/c9", "c9"))) and not c.island_position("w").is_equal_approx(SessionClusters.far_spot(0)), "so a new far cluster takes the next one")
	c.remove(held)
	c.add("v", _s("/new", "new"))
	_check(c.island_position("v").is_equal_approx(SessionClusters.far_spot(0)), "a freed far cluster's place is reused")
	var spots := {}
	for k in 100:
		spots[SessionClusters.far_spot(k)] = true
	_check(spots.size() == 100, "far clusters' places don't repeat")


# W12: sessions taken back go to the clusters they were in, in their
# saved order, slots and indexes closed up.
func _w12_clusters() -> void:
	var c := SessionClusters.new()
	var x := {"cluster": "7", "name": "game", "repo_key": "/r/game", "slot": 3, "index": 0}
	var y := {"cluster": "9", "name": "game 2", "repo_key": "", "slot": 5, "index": 2}
	c.restore("x1", x)
	var cx := c.add("x1", _s("/r/game", "game", "/r/game"))
	c.restore("x2", x.merged({"index": 4}, true))
	c.add("x2", _s("/r/game", "game", "/r/game"))
	c.restore("y1", y)
	var cy := c.add("y1", _s("/r/game", "game", "/r/game"))
	_check(c.cluster_of("x2") == cx and cy != cx, "W12: each back in its saved cluster")
	_check(c.cluster_name(cx) == "game" and c.cluster_name(cy) == "game 2" and c.cluster_key(cy) == "", "W12: with its name, a hand-made one still hand-made")
	_check(c.slot_of(cx) == 0 and c.slot_of(cy) == 1, "W12: clusters close up their wedges, in order")
	_check(c.index_of("x1") == 0 and c.index_of("x2") == 1 and c.index_of("y1") == 0, "W12: islands close up, in order")
	_check(c.add("n", _s("/r/game", "game", "/r/game")) == cx, "W12: its repository's next session joins the cluster made for it")


# W12: the file: entries kept, read back, ordered and dropped; a damaged
# file or entry ignored.
func _w12_memory() -> void:
	var s := {"provider": "claude", "started_at": "2026-10-19T10:00:00.000Z", "project": {"path": "/r/game"}}
	var k := IslandMemory.key(s)
	_check(k != "" and IslandMemory.key({"provider": "claude"}) == "", "W12: a key from provider, start and project; none without them")
	var m := IslandMemory.new()
	m.load_file()
	_check(not m.has(k), "W12: the suites start with no remembered islands")
	m.put(k, _entry("1", 2, 1))
	m.put("b", _entry("1", 2, 0))
	m.put("a", _entry("2", 0, 3))
	var again := IslandMemory.new()
	again.load_file()
	_check(again.entry(k) == m.entry(k) and int(again.entry(k)["seed"]) == 1234, "W12: read back from the file")
	_check(again.ordered([k, "b", "a", "none"]) == ["a", "b", k], "W12: ordered by slot, then index; unknown keys left out")
	again.keep_only({k: true, "a": true})
	m.load_file()
	_check(m.has(k) and m.has("a") and not m.has("b"), "W12: ones not kept are dropped from the file")
	var f := FileAccess.open(IslandMemory.file, FileAccess.WRITE)
	f.store_string('{"version": 1, "islands": {"bad": {"biome": 99, "seed": 1, "cluster": "1", "name": "x", "repo_key": "", "slot": 0, "index": 0}, "ok": %s}}' % JSON.stringify(_entry("1", 0, 0)))
	f.close()
	m.load_file()
	_check(m.has("ok") and not m.has("bad"), "W12: a damaged entry is ignored")
	f = FileAccess.open(IslandMemory.file, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	m.load_file()
	_check(not m.has("ok"), "W12: a damaged file is ignored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IslandMemory.file))


# W12: islands of sessions taken back wait for the sync, then come back
# as they were: biome, seed, cluster, order; ones that didn't come back
# are forgotten, and one that ends is too.
func _w12_islands() -> void:
	var m := IslandMemory.new()
	m.put(IslandMemory.key(_live("k1")), _entry("7", 3, 0, Biome.Kind.SNOWY, 111))
	m.put(IslandMemory.key(_live("k2")), _entry("7", 3, 4, Biome.Kind.DESERT, 222))
	m.put(IslandMemory.key(_live("k3")), _entry("9", 5, 0, Biome.Kind.FOREST, 333, "mine"))
	m.put(IslandMemory.key(_live("gone")), _entry("7", 3, 2))
	var store := SessionStore.new()
	var islands := SessionIslands.new()
	root.add_child(islands)
	islands.setup(store)
	store.syncing = true
	for id in ["n", "k3", "k2", "k1"]:
		store.apply({"type": "session.snapshot", "session": _live(id)})
	_check(islands.session_ids().is_empty(), "W12: islands taken back wait for the sync")
	store._on_synced()
	var c := islands.clusters
	_check(islands.session_ids().size() == 4, "W12: then all come")
	var k1 := islands.island("k1")
	_check(k1.biome == Biome.Kind.SNOWY and k1.island_seed == 111 and islands.island("k2").island_seed == 222, "W12: each with its biome and seed")
	_check(c.cluster_of("k2") == c.cluster_of("k1") and c.slot_of(c.cluster_of("k1")) == 0 and c.index_of("k1") == 0 and c.index_of("k2") == 1, "W12: in its cluster, in order, gaps closed")
	_check(c.cluster_name(c.cluster_of("k3")) == "mine" and c.slot_of(c.cluster_of("k3")) == 1, "W12: the next cluster in the next wedge")
	_check(c.cluster_of("n") == c.cluster_of("k1") and c.index_of("n") == 2, "W12: one with nothing saved comes after them (here into its repository's cluster)")
	var saved := IslandMemory.new()
	saved.load_file()
	_check(not saved.has(IslandMemory.key(_live("gone"))), "W12: one that didn't come back is forgotten")
	_check(int(saved.entry(IslandMemory.key(_live("k2")))["index"]) == 1 and saved.has(IslandMemory.key(_live("n"))), "W12: the file now holds where each is")
	store.apply({"type": "session.ended", "session": "k2", "seq": 2, "reason": "exited"})
	saved.load_file()
	_check(not saved.has(IslandMemory.key(_live("k2"))), "W12: one that ends is forgotten")
	islands.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IslandMemory.file))


func _entry(cluster: String, slot: int, index: int, biome := Biome.Kind.BEACH, island_seed := 1234, name := "game") -> Dictionary:
	return {"biome": biome, "seed": island_seed, "cluster": cluster, "name": name, "repo_key": "/r/game" if name == "game" else "", "slot": slot, "index": index}


# A session's snapshot, its start told apart by its id.
func _live(id: String) -> Dictionary:
	return {
		"session": id, "seq": 1, "provider": "fake", "native_id": null, "origin": "app",
		"project": {"path": "/r/game", "name": "game", "repo": "/r/game"}, "title": null,
		"started_at": "2026-10-19T10:00:00.%s" % id, "capabilities": {}, "extensions": [],
		"permissions": [], "notices": [],
		"agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
	}


func _closest(points: Array[Vector3]) -> float:
	var closest := INF
	for i in points.size():
		for j in i:
			closest = minf(closest, points[i].distance_to(points[j]))
	return closest


func _s(path: String, project_name: String, repo := "") -> Dictionary:
	var project := {"path": path, "name": project_name}
	if not repo.is_empty():
		project["repo"] = repo
	return {"project": project}


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
