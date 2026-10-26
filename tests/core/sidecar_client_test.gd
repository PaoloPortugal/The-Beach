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
	# The sidecar isn't started yet (the autoload starts it next frame).
	var kept_port := OS.get_environment(ErrorWatch.TEST_SESSIONS_ENV).path_join("hook-port.json")
	DirAccess.remove_absolute(kept_port)

	await _until(func() -> bool: return sidecar.status in [SidecarClient.Status.READY, SidecarClient.Status.FAILED], 20.0)
	_check(sidecar.status == SidecarClient.Status.READY, "connected and synced")
	if not fake:
		_check(FileAccess.file_exists(kept_port), "S07: the test's sidecar keeps its run folders in the test's own folder, not the user's")
	var ids := sidecar.providers.map(func(p: Dictionary) -> String: return p["provider"])
	_check(ids == (["fake"] if fake else ["claude"]), "hello lists the providers")

	var reply := await _command(sidecar, "session.list_stored", {"provider": "nope"})
	_check(reply.get("type") == "error" and reply.get("code") == "unknown_provider", "command round trip")

	# S08: outside sessions. The suites start the sidecar with them off
	# (tests/error_watch.gd), so the user's own running sessions never show.
	_check(not sidecar.outside_sessions and sidecar._serve_args() == ["serve", "--no-outside-sessions"], "S08: started with the setting's outside sessions off")
	if not fake:
		_check(sidecar.provider_capable("outside_sessions"), "S08: hello's provider capabilities read")
	_check(not sidecar.provider_capable("nope"), "S08: and one nobody declares isn't")
	reply = await _command(sidecar, "client.set_outside_sessions", {"enabled": false})
	_check(reply.get("type") == "ok", "S08: client.set_outside_sessions answered")
	reply = await _command(sidecar, "client.set_focus", {"focused": true})
	_check(reply.get("type") == "ok", "S08: client.set_focus answered")
	# Focus changes go to the sidecar; one that isn't a change doesn't.
	var sent_before: int = sidecar._next_id
	sidecar._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	sidecar._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(sidecar._next_id == sent_before + 1 and not sidecar._focused, "S08: focus lost: told once")
	sidecar._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(sidecar._next_id == sent_before + 2 and sidecar._focused, "S08: focus back: told")
	sidecar.set_outside_sessions(false)
	_check(sidecar._next_id == sent_before + 2, "S08: the setting unchanged: nothing sent")
	# A change made while reconnecting is lost; the setting goes again
	# once synced. On a stand-in that records, so the test's sidecar never
	# looks for the user's own sessions.
	var rec := Recording.new()
	rec.status = SidecarClient.Status.CONNECTING
	rec.set_outside_sessions(false)
	_check(rec.sent.is_empty(), "S08: a change while reconnecting can't be sent")
	rec.status = SidecarClient.Status.SYNCING
	rec._handle(JSON.stringify({"type": "sync.completed"}))
	_check(rec.status == SidecarClient.Status.READY and rec.sent == [["client.set_outside_sessions", {"enabled": false}]], "S08: the setting sent again once synced")
	rec.outside_sessions = true
	rec.sent.clear()
	rec._handle(JSON.stringify({"type": "sync.completed"}))
	_check(rec.sent == [["client.set_outside_sessions", {"enabled": true}]], "S08: on as well as off")
	rec.free()
	# A provider notice: kept with its provider, announced, never passed on as a session event.
	var changes := [0]
	var count := func() -> void: changes[0] += 1
	sidecar.providers_changed.connect(count)
	var events_before := _events.size()
	var provider_id: String = sidecar.providers[0]["provider"]
	var notice := {"code": "outside_sessions_off", "message": "can't list them"}
	sidecar._handle(JSON.stringify({"type": "provider.notice", "provider": provider_id, "notice": notice}))
	sidecar._handle(JSON.stringify({"type": "provider.notice", "provider": provider_id, "notice": notice}))
	_check(changes[0] == 2 and sidecar.provider_notice("outside_sessions_off") == notice, "S08: provider.notice kept and announced")
	_check(sidecar.providers[0]["notices"].filter(func(n: Dictionary) -> bool: return n["code"] == "outside_sessions_off").size() == 1, "S08: the same code once")
	_check(_events.size() == events_before and sidecar.provider_notice("nope").is_empty(), "S08: not a session event")
	sidecar.providers_changed.disconnect(count)

	# S02: a program set by hand. Given at start after the outside setting.
	var args := Recording.new()
	_check(args._serve_args() == [], "S02: nothing set: the sidecar starts with no arguments")
	args.program_paths = {"zeta": "/z/zeta", "claude": "C:/Tools/claude.exe"}
	_check(args._serve_args() == ["serve", "--program-path", "claude=C:/Tools/claude.exe", "--program-path", "zeta=/z/zeta"], "S02: each program set by hand given at start, in a fixed order")
	args.outside_sessions = false
	_check(args._serve_args() == ["serve", "--no-outside-sessions", "--program-path", "claude=C:/Tools/claude.exe", "--program-path", "zeta=/z/zeta"], "S02: with the outside setting")
	args.program_paths = {"claude": "C:/Tools/claude.exe", "my-tool": "/x", "Claude": "/y", "": "/z"}
	_check(args._serve_args() == ["serve", "--no-outside-sessions", "--program-path", "claude=C:/Tools/claude.exe"], "S02: a malformed provider id from an edited settings file is left out, so the sidecar still starts")
	args.program_paths = {"claude": "C:/Tools/\" --x.exe", "zeta": "/z/ze\nta", "beta": "/b/be\u007fta"}
	_check(args._serve_args() == ["serve", "--no-outside-sessions"], "S02: a path with a quote or a control character is left out, so it can't become another argument")
	args.free()
	# provider.program: kept with its provider, announced, not a session event.
	changes[0] = 0
	sidecar.providers_changed.connect(count)
	var found := {"path": "/opt/x/prog", "version": "2.1.300", "set_by_hand": false}
	sidecar._handle(JSON.stringify({"type": "provider.program", "provider": provider_id, "program": found}))
	_check(changes[0] == 1 and sidecar.provider_program(provider_id) == found and _events.size() == events_before, "S02: provider.program kept and announced, not a session event")
	_check(sidecar.provider_program("nope").is_empty(), "S02: none for a provider that isn't there")
	sidecar.providers_changed.disconnect(count)
	# The setting: refused by the real sidecar's checks (nothing saved), or
	# accepted (saved in the settings file, given to the next start) and
	# cleared, on a stand-in that answers ok.
	if not fake:
		var refused := {}
		sidecar.set_program_path("claude", "claude.exe", func(m: Dictionary) -> void: refused.merge(m))
		await _until(func() -> bool: return not refused.is_empty(), 5.0)
		_check(refused.get("code") == "invalid_program" and str(refused.get("message")).contains("full path") and sidecar.program_paths.is_empty(), "S02: a path the sidecar refuses is said why, and not kept")
	var saved_cfg := ConfigFile.new()
	saved_cfg.load(SidecarClient.settings_file)
	_check(not saved_cfg.has_section("programs"), "S02: nothing saved for it")
	var replying := Replying.new()
	replying.providers = [{"provider": "claude", "name": "Claude Code"}]
	replying.reply = {"type": "ok", "result": {"program": {"path": "/home/u/bin/claude", "version": "2.1.300", "set_by_hand": true}}}
	var answered := {}
	replying.set_program_path("claude", "/home/u/bin/claude", func(m: Dictionary) -> void: answered.merge(m))
	saved_cfg = ConfigFile.new()
	saved_cfg.load(SidecarClient.settings_file)
	_check(answered.get("type") == "ok" and replying.program_paths == {"claude": "/home/u/bin/claude"} and replying.provider_program("claude").get("set_by_hand") == true, "S02: accepted: kept and shown")
	_check(saved_cfg.get_value("programs", "claude", "") == "/home/u/bin/claude" and saved_cfg.get_value("game", "outside_sessions", true) == false, "S02: saved in the settings file, the others kept")
	_check(replying.sent == [["client.set_program_path", {"provider": "claude", "path": "/home/u/bin/claude"}]], "S02: sent as client.set_program_path")
	replying.reply = {"type": "ok", "result": {"program": {"path": "/usr/bin/claude", "version": "2.1.301", "set_by_hand": false}}}
	replying.set_program_path("claude", "")
	saved_cfg = ConfigFile.new()
	saved_cfg.load(SidecarClient.settings_file)
	_check(replying.sent.back() == ["client.set_program_path", {"provider": "claude", "path": null}] and replying.program_paths.is_empty() and not saved_cfg.has_section_key("programs", "claude"), "S02: cleared: sent as null, forgotten, removed from the file")
	replying.reply = {"type": "error", "code": "invalid_program", "message": "There's no program at that path."}
	replying.set_program_path("claude", "/gone/claude")
	_check(replying.program_paths.is_empty(), "S02: refused: nothing kept")
	replying.free()
	var offline := SidecarClient.new()
	var gave := {}
	offline.set_program_path("claude", "/x/claude", func(m: Dictionary) -> void: gave.merge(m))
	_check(gave.get("code") == "disconnected" and offline.program_paths.is_empty(), "S02: no sidecar: said so, nothing kept")
	# Look again: found or not, the answer kept and shown; nothing saved.
	var looking := Replying.new()
	looking.providers = [{"provider": "claude", "name": "Claude Code"}]
	looking.reply = {"type": "ok", "result": {"program": {"path": null, "set_by_hand": false, "message": "Claude Code wasn't found."}}}
	var looked := {}
	looking.find_program("claude", func(m: Dictionary) -> void: looked.merge(m))
	_check(looking.sent == [["client.find_program", {"provider": "claude"}]] and looked.get("type") == "ok", "S02: Look again sent as client.find_program")
	_check(looking.provider_program("claude").get("message") == "Claude Code wasn't found." and looking.startable_providers().is_empty(), "S02: not found: kept, and no provider can start a session")
	looking.reply = {"type": "ok", "result": {"program": {"path": "/usr/bin/claude", "version": "2.1.301", "set_by_hand": false}}}
	looking.find_program("claude")
	_check(looking.provider_program("claude").get("path") == "/usr/bin/claude" and looking.startable_providers().size() == 1 and looking.program_paths.is_empty(), "S02: found: kept, it can start one, nothing set by hand")
	looking.providers.append({"provider": "other", "name": "Other"})
	looking.providers[0]["program"] = {"path": null, "set_by_hand": false, "message": "gone"}
	_check(looking.startable_providers().map(func(p: Dictionary) -> String: return p["provider"]) == ["other"], "S02: a provider without program_path can always start one")
	looking.providers[0]["program"] = {}
	_check(looking.startable_providers().size() == 2, "S02: one still looking counts")
	looking.free()
	var nobody := {}
	offline.find_program("claude", func(m: Dictionary) -> void: nobody.merge(m))
	_check(nobody.get("code") == "disconnected", "S02: Look again with no sidecar: said so")
	offline.free()
	# The sidecar's own answer to a provider it hasn't, or one without
	# program_path (nothing runs a real program).
	var asked := {}
	sidecar.find_program("fake" if fake else "nobody", func(m: Dictionary) -> void: asked.merge(m))
	await _until(func() -> bool: return not asked.is_empty(), 5.0)
	_check(asked.get("code") == ("not_supported" if fake else "unknown_provider"), "S02: client.find_program refused by the sidecar for %s (%s)" % ["the fake provider" if fake else "an unknown provider", asked.get("code")])

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


# Records commands instead of sending them, as the real one would while
# connected.
## Answers every command at once with [member reply], recording it.
class Replying extends SidecarClient:
	var sent: Array = []
	var reply := {}

	func send_command(type: String, fields: Dictionary = {}, on_reply := Callable()) -> String:
		sent.append([type, fields])
		if on_reply.is_valid():
			on_reply.call(reply)
		return "r%d" % sent.size()


class Recording extends SidecarClient:
	var sent: Array = []

	func send_command(type: String, fields: Dictionary = {}, _on_reply := Callable()) -> String:
		if status != Status.READY and status != Status.SYNCING:
			return ""
		sent.append([type, fields])
		return "r%d" % sent.size()


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
