extends SceneTree
## Headless smoke test for the sidecar client (S01): Godot starts the real
## sidecar, connects with the token (so the server's Origin, Host and token
## checks accept Godot's client), sends commands and stops it again.
##
##   godot --headless --path . --script res://tests/core/sidecar_client_test.gd
##   ... -- --sidecar-dev-fake      also runs a chat turn with the fake provider
##   ... -- --sidecar=<executable>  tests a packaged sidecar

var _events: Array[Dictionary] = []
const ErrorWatch := preload("res://tests/error_watch.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_run()


func _run() -> void:
	var sidecar: SidecarClient = root.get_node("Sidecar")
	sidecar.event_received.connect(func(m: Dictionary) -> void: _events.append(m))
	var fake := "--sidecar-dev-fake" in OS.get_cmdline_user_args()

	await _until(func() -> bool: return sidecar.status in [SidecarClient.Status.READY, SidecarClient.Status.FAILED], 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "connected and synced")
	var ids := sidecar.providers.map(func(p: Dictionary) -> String: return p["provider"])
	_check(ids == (["fake"] if fake else ["claude"]), "hello lists the providers")

	var reply := await _command(sidecar, "session.list_stored", {"provider": "nope"})
	_check(reply.get("type") == "error" and reply.get("code") == "unknown_provider", "command round trip")

	if fake:
		var project := OS.get_user_data_dir()
		reply = await _command(sidecar, "session.create", {"provider": "fake", "project": {"path": project}})
		_check(reply.get("type") == "ok", "session.create ok")
		var id: String = reply["result"]["session"]
		var created := await _event(func(m: Dictionary) -> bool: return m["type"] == "session.created" and m["session"]["session"] == id)
		_check(not created.is_empty(), "session.created")
		reply = await _command(sidecar, "message.send", {"session": id, "text": "hello\nworld"})
		_check(reply.get("type") == "ok", "message.send ok")
		var done := await _event(func(m: Dictionary) -> bool: return m["type"] == "message.completed" and str(m["text"]).contains("> world"))
		_check(not done.is_empty(), "streamed reply completed")
		var deltas := _events.filter(func(m: Dictionary) -> bool: return m["type"] == "message.delta")
		_check(deltas.size() >= 3, "reply streamed in several deltas")
		var idle := await _event(func(m: Dictionary) -> bool: return m["type"] == "agent.state_changed" and m["state"] == "idle")
		_check(not idle.is_empty(), "orchestrator back to idle")
		reply = await _command(sidecar, "session.end", {"session": id})
		_check(reply.get("type") == "ok", "session.end ok")
		var ended := await _event(func(m: Dictionary) -> bool: return m["type"] == "session.ended")
		_check(ended.get("reason") == "user", "session.ended")

	# A dropped connection while the sidecar runs: the client reconnects and syncs again.
	var syncs := [0]
	sidecar.synced.connect(func(_p: Array) -> void: syncs[0] += 1)
	var lost := [{}]
	sidecar.send_command("session.list_stored", {"provider": "nope"}, func(r: Dictionary) -> void: lost[0] = r)
	sidecar._ws.close()
	await _until(func() -> bool: return syncs[0] == 1, 10.0)
	_check(syncs[0] == 1 and sidecar.status == SidecarClient.Status.READY, "reconnects after a dropped connection")
	_check(lost[0].get("type") == "error" and lost[0].get("code") == "disconnected", "a reply lost with the connection comes back as an error")
	reply = await _command(sidecar, "session.list_stored", {"provider": "nope"})
	_check(reply.get("code") == "unknown_provider", "commands work after reconnecting")

	var pid: int = sidecar._pid
	sidecar.stop()
	_check(not OS.is_process_running(pid), "sidecar exits when stopped")
	if not _failed and _errors.ok():
		print("PASS sidecar_client_test")
		quit(0)


func _command(sidecar: SidecarClient, type: String, fields: Dictionary) -> Dictionary:
	var box := {}
	sidecar.send_command(type, fields, func(m: Dictionary) -> void: box["reply"] = m)
	await _until(func() -> bool: return box.has("reply"), 5.0)
	return box.get("reply", {})


func _event(pred: Callable) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		for m in _events:
			if pred.call(m):
				return m
		await process_frame
	return {}


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
