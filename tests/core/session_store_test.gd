extends SceneTree
## Headless test for the session store: events applied by hand, then (with
## the scripted fake) a live session through the real sidecar.
##
##   godot --headless --path . --script res://tests/core/session_store_test.gd
##   ... -- --sidecar-dev-fake      also drives the fake provider's scenarios

var _failed := false


func _initialize() -> void:
	_run()


func _run() -> void:
	_by_hand()
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		await _live()
	if not _failed:
		print("PASS session_store_test")
		quit(0)


func _snapshot(id: String, seq := 1) -> Dictionary:
	return {
		"session": id, "seq": seq, "provider": "fake", "native_id": null, "origin": "app",
		"project": {"path": "/p"}, "title": null, "started_at": "2026-09-29T10:00:00Z",
		"capabilities": {}, "extensions": [], "permissions": [], "notices": [],
		"agents": [{"agent": "main", "role": "orchestrator", "parent": null, "state": "idle", "reason": null}],
	}


func _by_hand() -> void:
	var store := SessionStore.new()
	var log: Array[String] = []
	store.session_added.connect(func(id: String, created: bool) -> void: log.append("added %s %s" % [id, created]))
	store.session_removed.connect(func(id: String, reason: String) -> void: log.append("removed %s %s" % [id, reason]))
	store.extension_event.connect(func(id: String, m: Dictionary) -> void: log.append("ext %s %s" % [id, m["type"]]))

	store.apply({"type": "session.snapshot", "session": _snapshot("a")})
	store.apply({"type": "session.created", "session": _snapshot("b")})
	_check(log == ["added a false", "added b true"], "snapshot places, created rises")

	store.apply({"type": "agent.spawned", "session": "a", "seq": 2, "agent": {"agent": "s1", "role": "subagent", "parent": "main", "state": "working", "reason": null}})
	store.apply({"type": "agent.state_changed", "session": "a", "seq": 3, "agent": "main", "state": "waiting", "reason": "permission"})
	_check(store.agent("a", "s1")["parent"] == "main" and store.agent("a", "main")["reason"] == "permission", "agents spawn and change")
	_check(store.orchestrator("a")["agent"] == "main" and store.orchestrator("zzz").is_empty(), "finds the orchestrator")

	store.apply({"type": "message.started", "session": "a", "seq": 4, "message": "m1", "agent": "main", "role": "assistant"})
	store.apply({"type": "message.delta", "session": "a", "seq": 5, "message": "m1", "text": "Hel"})
	var streaming: Dictionary = store.messages("a")[0]
	_check(streaming["text"] == "Hel" and not streaming["complete"], "a message streams")
	store.apply({"type": "message.completed", "session": "a", "seq": 6, "message": "m1", "text": "Hello."})
	_check(store.messages("a")[0]["text"] == "Hello." and store.messages("a")[0]["complete"], "completed text replaces the deltas")

	store.apply({"type": "tool.started", "session": "a", "seq": 7, "tool_call": "t1", "agent": "s1", "tool": "Bash", "summary": "Run: ls"})
	store.apply({"type": "tool.finished", "session": "a", "seq": 8, "tool_call": "t1", "status": "denied"})
	_check(store.session("a")["tools"]["t1"]["status"] == "denied", "tool calls")

	store.apply({"type": "permission.requested", "session": "a", "seq": 9, "permission": {"permission": "p1", "agent": "main", "tool": "Bash", "summary": "Run: ls"}})
	_check(store.session("a")["permissions"].size() == 1, "permission pending")
	store.apply({"type": "permission.resolved", "session": "a", "seq": 10, "permission": "p1", "decision": "allow", "by": "app"})
	_check(store.session("a")["permissions"].is_empty(), "permission resolved")

	store.apply({"type": "session.notice", "session": "a", "seq": 11, "notice": {"code": "transcripts_off", "message": "x"}})
	store.apply({"type": "session.notice", "session": "a", "seq": 12, "notice": {"code": "transcripts_off", "message": "y"}})
	var notices: Array = store.session("a")["notices"]
	_check(notices.size() == 1 and notices[0]["message"] == "y", "one notice per code")

	store.apply({"type": "ext.fake.ping", "session": "a", "seq": 13})
	_check(log.back() == "ext a ext.fake.ping", "extension messages pass through")

	store.load_history("a", [
		{"message": "u0", "agent": "main", "role": "user", "text": "hi", "at": "2026-09-29T09:00:00Z"},
		{"message": "m1", "agent": "main", "role": "assistant", "text": "old copy", "at": "2026-09-29T09:00:01Z"},
	])
	var chat := store.messages("a")
	_check(chat.size() == 2 and chat[0]["text"] == "hi" and chat[1]["text"] == "Hello.", "history goes first; live messages win")

	# A resync after a gap: the snapshot replaces the state, not the chat.
	var fresh := _snapshot("a", 20)
	store.apply({"type": "session.snapshot", "session": fresh})
	_check(store.messages("a").size() == 2 and store.agent("a", "s1").is_empty(), "a resync keeps the chat, replaces agents")

	# A reconnect: sessions the sidecar no longer has are removed.
	var client := SidecarClient.new()
	store.attach(client)
	log.clear()
	client.sync_started.emit()
	store.apply({"type": "session.snapshot", "session": _snapshot("a", 21)})
	client.synced.emit([])
	_check(log == ["removed b exited"] and store.sessions.keys() == ["a"], "a reconnect drops sessions that ended meanwhile")
	client.free()

	store.apply({"type": "session.ended", "session": "a", "seq": 22, "reason": "user"})
	_check(store.sessions.is_empty(), "session.ended removes it")
	store.apply({"type": "agent.state_changed", "session": "zzz", "seq": 1, "agent": "main", "state": "idle", "reason": null})
	_check(store.sessions.is_empty(), "events for unknown sessions are ignored")


func _live() -> void:
	var sidecar: SidecarClient = root.get_node("Sidecar")
	var store := SessionStore.new()
	store.attach(sidecar)
	await _until(func() -> bool: return sidecar.status == SidecarClient.Status.READY, 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "live: connected")
	var reply := await _command(sidecar, "session.create", {"provider": "fake", "project": {"path": OS.get_user_data_dir()}})
	var id: String = reply["result"]["session"]
	await _until(func() -> bool: return store.sessions.has(id), 5.0)
	_check(store.sessions.has(id), "live: the session appears")

	await _command(sidecar, "message.send", {"session": id, "text": "ask for permission"})
	await _until(func() -> bool: return store.session(id)["permissions"].size() == 1, 5.0)
	# The agent's state change can land a frame later.
	await _until(func() -> bool: return store.agent(id, "main")["reason"] == "permission", 2.0)
	_check(store.agent(id, "main")["reason"] == "permission", "live: waiting on a permission")
	var p: String = store.session(id)["permissions"][0]["permission"]
	await _command(sidecar, "permission.respond", {"session": id, "permission": p, "decision": "allow"})
	await _until(func() -> bool: return store.agent(id, "main")["state"] == "idle", 8.0)
	_check(store.session(id)["permissions"].is_empty(), "live: answered from the world")

	await _command(sidecar, "message.send", {"session": id, "text": "agents 2"})
	var subagents := func() -> Array: return store.session(id)["agents"].filter(func(a: Dictionary) -> bool: return a["role"] == "subagent")
	await _until(func() -> bool: return subagents.call().size() == 2 and subagents.call().all(func(a: Dictionary) -> bool: return a["state"] == "done"), 15.0)
	_check(subagents.call().size() == 2, "live: two subagents came and finished")

	await _command(sidecar, "message.send", {"session": id, "text": "a notice"})
	await _until(func() -> bool: return store.session(id)["notices"].size() == 1, 5.0)
	_check(store.session(id)["notices"][0]["code"] == "transcripts_off", "live: a notice")

	var history := await _command(sidecar, "session.get_history", {"session": id})
	_check(history["result"]["messages"].size() >= 6, "live: history")
	await _command(sidecar, "session.end", {"session": id})
	await _until(func() -> bool: return not store.sessions.has(id), 5.0)
	_check(not store.sessions.has(id), "live: ended")
	sidecar.stop()


func _command(sidecar: SidecarClient, type: String, fields: Dictionary) -> Dictionary:
	var box := {}
	sidecar.send_command(type, fields, func(m: Dictionary) -> void: box["reply"] = m)
	await _until(func() -> bool: return box.has("reply"), 5.0)
	return box.get("reply", {})


func _until(cond: Callable, timeout_s: float) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if _failed:
		return
	if ok:
		print("  ok  ", what)
		return
	_failed = true
	printerr("FAIL ", what)
	quit(1)
