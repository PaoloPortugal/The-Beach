extends SceneTree
## Headless test for W05's cluster model (SessionClusters): grouping by
## repository and worktree, folders outside git, manual choices, names,
## freeing, and the layout.
##
##   godot --headless --path . --script res://tests/world/clusters_test.gd

var _failed := false


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
	var offsets := {}
	for i in 19:
		offsets[SessionClusters.island_offset(i)] = true
	_check(offsets.size() == 19, "island spots don't repeat")
	if not _failed:
		print("PASS clusters_test")
	quit(1 if _failed else 0)


func _s(path: String, project_name: String, repo := "") -> Dictionary:
	var project := {"path": path, "name": project_name}
	if not repo.is_empty():
		project["repo"] = repo
	return {"project": project}


func _check(ok: bool, what: String) -> void:
	print(("  ok  " if ok else "FAIL ") + what)
	if not ok:
		_failed = true
