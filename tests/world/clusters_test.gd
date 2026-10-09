extends SceneTree
## Headless test for W05's cluster model (SessionClusters): grouping by
## repository and worktree, folders outside git, manual choices, names,
## freeing, holding an ended session's island spot (W04), and the layout:
## 8 near wedges growing without limit, then far clusters (W06).
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
	_check(c.island_position("s8").is_equal_approx(SessionClusters.far_spot(0)), "its first island in the first far spot")
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
	_check(c.island_position("v").is_equal_approx(SessionClusters.far_spot(0)), "freed far spots are reused")
	var spots := {}
	for k in 100:
		spots[SessionClusters.far_spot(k)] = true
	_check(spots.size() == 100, "far spots don't repeat")


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
