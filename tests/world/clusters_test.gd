extends SceneTree
## Headless test for W05's cluster model (SessionClusters): grouping by
## repository and worktree, folders outside git, manual choices, names,
## freeing, holding an ended session's island spot (W04), and the layout.
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
	_check(c.island_position("a").is_equal_approx(SessionClusters.cluster_position(0)), "the first island is in the middle")
	_check(c.island_position("b").distance_to(c.island_position("a")) > 90.0, "the next ones close by")
	_check(c.island_position("a").distance_to(c.island_position("p")) > 300.0, "clusters far apart")
	c.remove("b")
	c.choose("n", SessionClusters.AUTOMATIC)
	c.add("n", _s("/r/game", "game", "/r/game"))
	_check(c.island_position("n") == c.island_position("a") + SessionClusters.island_offset(1), "a freed island spot is reused")
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
	_check(c.add("q2", _s("/other", "other")) == q and c.island_position("q2").is_equal_approx(SessionClusters.cluster_position(1) + SessionClusters.island_offset(1)), "its repository's next session joins it, beside the held island")
	_check(q in c.ids() and Array(c.sessions(q)) == ["q2"], "listed again, with only its live session")
	c.remove(held)
	c.remove("q2")
	_check(c.cluster_name(q) == "" and c.add("r", _s("/fourth", "fourth")) != q and c.island_position("r").is_equal_approx(SessionClusters.cluster_position(1)), "once released, the cluster and its spot are freed")
	_check(c.hold("never") == "", "a session never added holds nothing")
	var offsets := {}
	for i in 19:
		offsets[SessionClusters.island_offset(i)] = true
	_check(offsets.size() == 19, "island spots don't repeat")
	var passed := not _failed and _errors.ok()
	if passed:
		print("PASS clusters_test")
	quit(0 if passed else 1)


func _s(path: String, project_name: String, repo := "") -> Dictionary:
	var project := {"path": path, "name": project_name}
	if not repo.is_empty():
		project["repo"] = repo
	return {"project": project}


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
