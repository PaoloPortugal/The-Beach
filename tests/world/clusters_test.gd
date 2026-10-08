extends SceneTree
## Headless test for W05's cluster model (SessionClusters): grouping by
## repository and worktree, folders outside git, manual choices, names,
## freeing, holding an ended session's island spot (W04), and the layout
## in wedges with its far spots (W06).
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
	var passed := not _failed and _errors.ok()
	if passed:
		print("PASS clusters_test")
	quit(0 if passed else 1)


# W06: every spot of 16 wedges well apart, inside its wedge, growing
# outward; corridors between inner wedges clear for outer bridges.
func _layout() -> void:
	var all: Array[Vector3] = []
	var outward := true
	var inside := true
	for slot in 16:
		var last := 0.0
		for index in (SessionClusters.INNER_ISLANDS if slot < 8 else 14):
			var p := SessionClusters.spot(slot, index)
			outward = outward and p.length() >= last - 60.0
			last = p.length()
			var axis := (slot % 8 + (0.5 if slot >= 8 else 0.0)) * TAU / 8.0
			var off := absf(angle_difference(axis, atan2(p.z, p.x)))
			inside = inside and p.length() * sin(TAU / 16.0 - off) >= SessionClusters.EDGE_MARGIN - 0.01
			all.append(p)
	var closest := INF
	for i in all.size():
		for j in i:
			closest = minf(closest, all[i].distance_to(all[j]))
	_check(closest >= SessionClusters.ISLAND_SPACING - 0.01, "layout: island spots at least 100 m apart in all 16 wedges (closest %.1f m)" % closest)
	_check(inside, "layout: every spot inside its wedge, clear of its edges")
	_check(outward, "layout: a cluster fills its wedge nearest the platform first")
	var first := SessionClusters.cluster_position(0).length()
	_check(first > 100.0 and first < 150.0, "layout: an inner cluster's first island %.0f m out" % first)
	_check(SessionClusters.cluster_position(8).length() >= SessionClusters.OUTER_START - 0.01, "layout: outer wedges start further out")
	var corridor := true
	for slot in 8:
		for index in SessionClusters.INNER_ISLANDS:
			var p := SessionClusters.spot(slot, index)
			for k in 8:
				var a := (k + 0.5) * TAU / 8.0
				# Distance from the corridor's line (through the platform).
				corridor = corridor and absf(-p.x * sin(a) + p.z * cos(a)) >= SessionClusters.EDGE_MARGIN - 0.01
	_check(corridor, "layout: the corridors to outer wedges are clear of inner islands")


# A 17th cluster, and an inner cluster's 11th island: far spots, no bridges.
func _overflow() -> void:
	var c := SessionClusters.new()
	for k in 17:
		c.add("s%d" % k, _s("/c%d" % k, "c%d" % k))
	_check(c.is_bridged("s15") and not c.is_bridged("s16"), "overflow: 16 clusters in wedges, the 17th in a far spot")
	_check(c.island_position("s16").length() >= SessionClusters.FAR_RADIUS - 0.01, "far out")
	for k in 11:
		c.add("t%d" % k, _s("/c0", "c0"))
	_check(c.is_bridged("t8") and not c.is_bridged("t9"), "an inner cluster's 11th island goes to a far spot")
	_check(c.island_position("t9").distance_to(c.island_position("s16")) > 150.0, "not on another's far spot")
	var held := c.hold("t9")
	_check(not c.is_bridged(held) and c.island_position(held).length() >= SessionClusters.FAR_RADIUS - 0.01, "a held far island keeps its spot")
	c.add("u", _s("/c0", "c0"))
	_check(c.island_position("u") != c.island_position(held), "and nobody else gets it")
	c.remove(held)
	c.remove("s16")
	c.add("v", _s("/new", "new"))
	_check(c.island_position("v") == SessionClusters.far_spot(0), "freed far spots are reused")
	var spots := {}
	for k in 300:
		spots[SessionClusters.far_spot(k)] = true
	_check(spots.size() == 300, "far spots don't repeat")


func _s(path: String, project_name: String, repo := "") -> Dictionary:
	var project := {"path": path, "name": project_name}
	if not repo.is_empty():
		project["repo"] = repo
	return {"project": project}


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
