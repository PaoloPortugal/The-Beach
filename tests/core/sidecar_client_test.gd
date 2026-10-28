extends SceneTree
## Headless smoke test for the sidecar client (S01): Godot starts the real
## sidecar, connects with the token (so the server's Origin, Host and token
## checks accept Godot's client), sends commands and stops it again. Then
## the start retry, on fake sidecars that fail to start
## ([code]fake_sidecar.mjs[/code]; Node on PATH, as for the sidecar itself).
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

	# S01 restart: the sidecar dies in play: a new one starts and syncs
	# (hello, snapshots, sync.completed, so the session store resyncs), no
	# failure said.
	var restarts := []
	var fails := []
	sidecar.restarting.connect(func(r: String) -> void: restarts.append(r))
	sidecar.failed.connect(func(r: String) -> void: fails.append(r))
	var first_pid: int = sidecar._pid
	sidecar._ready_at -= SidecarClient.STEADY_S # up a while: a fresh start
	OS.kill(first_pid)
	await _until(func() -> bool: return syncs[0] == 2, 60.0)
	_check(syncs[0] == 2 and sidecar.status == SidecarClient.Status.READY and restarts == ["The sidecar stopped."] and fails.is_empty() and sidecar._attempt == 0, "S01 restart: a sidecar that dies in play is started again and synced, no failure said")
	_check(sidecar._pid != first_pid and not OS.is_process_running(first_pid) and sidecar.has_synced, "S01 restart: a new process")
	reply = await _command(sidecar, "session.list_stored", {"provider": "nope"})
	_check(reply.get("code") == "unknown_provider", "S01 restart: commands work after it")
	# Dead again right after: it goes on with that start's attempts (the
	# next, after its wait).
	OS.kill(sidecar._pid)
	await _until(func() -> bool: return syncs[0] == 3, 90.0)
	_check(syncs[0] == 3 and sidecar.status == SidecarClient.Status.READY and sidecar._attempt == 1 and restarts.size() == 2 and fails.is_empty(), "S01 restart: dead again soon after: the next attempt of the same start (attempt %d)" % (sidecar._attempt + 1))

	var pid: int = sidecar._pid
	sidecar.stop()
	_check(not OS.is_process_running(pid), "sidecar exits when stopped")
	await _start_retries()
	if not _failed and _errors.ok():
		print("PASS sidecar_client_test")
		quit(0)


# A start that fails in a way that can pass is tried again; one that
# can't, isn't (user's decision, 2026-10-28). On fake sidecars
# (fake_sidecar.mjs) that are slow, exit early or send a bad handshake,
# with the attempts' times shortened.
func _start_retries() -> void:
	_check(SidecarClient.START_TIMEOUT_S == 20.0 + 2.0 + 30.0 + 5.0 + 45.0 and LoadingCover.TIMEOUT_S > SidecarClient.START_TIMEOUT_S, "S01 retry: the longest start counts every attempt and wait, and the loading cover waits past it")
	var reasons := {
		"slow": "The sidecar didn't start in time.",
		"exit": "The sidecar stopped while starting.",
		"bad": "The sidecar sent a bad handshake.",
		"refuse": "Couldn't connect to the sidecar (closed, code",
	}
	for mode: String in reasons:
		var client := Starting.new()
		client.commands = [_fake(mode)]
		if mode != "slow":
			# Its failure, not the short timeout, on a slow machine.
			client.handshake_timeouts_s = [10.0, 10.0, 10.0]
		_errors.expect("Sidecar: " + reasons[mode])
		var seen := await _follow_start(client, 15.0)
		_check(client.status == SidecarClient.Status.FAILED and seen["failed"].size() == 1 and str(seen["failed"][0]).begins_with(reasons[mode]), "S01 retry (%s): failed once, after the last attempt (%s)" % [mode, seen["failed"]])
		_check(seen["pids"].size() == 3, "S01 retry (%s): three attempts (%d)" % [mode, seen["pids"].size()])
		_check(not seen["two"] and not seen["pids"].any(func(p: int) -> bool: return OS.is_process_running(p)), "S01 retry (%s): each attempt's sidecar ended before the next; none left" % mode)
		if mode == "slow":
			# Each attempt waits its own time, with the waits between them.
			_check(seen["seconds"] >= 0.5 + 0.2 + 0.7 + 0.3 + 0.9, "S01 retry: each attempt waits longer, with a wait between them (%.1f s)" % seen["seconds"])
		client.free()

	# Stopped while waiting to try again: no attempt after it.
	var halted := Starting.new()
	halted.commands = [_fake("exit")]
	halted.handshake_timeouts_s = [10.0, 10.0, 10.0]
	halted.retry_waits_s = [0.5, 0.5]
	root.add_child(halted)
	await _until(func() -> bool: return halted._retry_at > 0.0, 10.0)
	halted.stop()
	await _until(func() -> bool: return false, 1.0)
	_check(halted._retry_at == 0.0 and halted._pid == -1 and halted.status == SidecarClient.Status.STOPPED, "S01 retry: stopped while waiting to try again: nothing started after")
	halted.queue_free()

	# Not tried again: another protocol version, or no sidecar at the given path.
	var old := Starting.new()
	old.commands = [_fake("old")]
	old.handshake_timeouts_s = [10.0, 10.0, 10.0] # its handshake, not the timeout
	_errors.expect("Sidecar: The sidecar speaks a different protocol version")
	var seen_old := await _follow_start(old, 10.0)
	_check(old.status == SidecarClient.Status.FAILED and seen_old["pids"].size() == 1 and seen_old["failed"].size() == 1, "S01 retry: a protocol version mismatch fails at once")
	old.free()
	var missing := Starting.new()
	missing.args = PackedStringArray(["--sidecar=" + OS.get_user_data_dir().path_join("no-such-sidecar")])
	_errors.expect("Sidecar: There's no sidecar at")
	var seen_missing := await _follow_start(missing, 5.0)
	_check(missing.status == SidecarClient.Status.FAILED and seen_missing["pids"].is_empty() and seen_missing["failed"].size() == 1 and str(seen_missing["failed"][0]).begins_with("There's no sidecar at"), "S01 retry: --sidecar=<path> with nothing there fails at once")
	missing.free()

	# A retry that works: ready, and nothing failed.
	var flaky := Starting.new()
	flaky.handshake_timeouts_s = [20.0, 20.0, 20.0]
	flaky.commands = [_fake("exit"), ["node", ProjectSettings.globalize_path("res://sidecar/test/dev-fake.ts"), "serve", "--no-outside-sessions"]]
	var seen_flaky := await _follow_start(flaky, 30.0)
	_check(flaky.status == SidecarClient.Status.READY and seen_flaky["failed"].is_empty() and seen_flaky["pids"].size() == 2 and not seen_flaky["two"], "S01 retry: a start that fails once is ready on the next attempt, no failure said")
	var flaky_pid: int = flaky._pid
	flaky.stop()
	flaky.queue_free()
	_check(not OS.is_process_running(flaky_pid), "S01 retry: and stops as usual")
	# A good handshake whose connect fails at once: that sidecar is ended
	# (it got as far as the pipe) and the next attempt works.
	var no_connect := Starting.new()
	no_connect.handshake_timeouts_s = [20.0, 20.0, 20.0]
	no_connect.connect_errors = 1
	no_connect.commands = [["node", ProjectSettings.globalize_path("res://sidecar/test/dev-fake.ts"), "serve", "--no-outside-sessions"]]
	var seen_connect := await _follow_start(no_connect, 30.0)
	_check(no_connect.status == SidecarClient.Status.READY and seen_connect["failed"].is_empty() and seen_connect["pids"].size() == 2 and not seen_connect["two"] and not OS.is_process_running(seen_connect["pids"][0]), "S01 retry: a connect that fails at once: that sidecar ended, the next attempt ready")
	no_connect.stop()
	no_connect.queue_free()
	# S01 restart: a reconnect that fails at once while the sidecar still
	# runs. That sidecar is ended before a new one starts (never two), and
	# the new one syncs, no failure said. On the real sidecar.
	var reconnect := Starting.new()
	reconnect.handshake_timeouts_s = [20.0, 20.0, 20.0]
	var seen_reconnect := await _follow_start(reconnect, 30.0)
	_check(reconnect.status == SidecarClient.Status.READY and seen_reconnect["failed"].is_empty(), "S01 restart: the real sidecar up for a failed reconnect")
	var reconnect_restarts := []
	var reconnect_syncs := [0]
	reconnect.restarting.connect(func(r: String) -> void: reconnect_restarts.append(r))
	reconnect.synced.connect(func(_p: Array) -> void: reconnect_syncs[0] += 1)
	var alive_pid: int = reconnect._pid
	var new_pid := [-1]
	var old_running_then := [true]
	reconnect._ready_at -= SidecarClient.STEADY_S # up a while: a fresh start
	reconnect.connect_errors = 1
	reconnect._ws.close()
	var waited := Time.get_ticks_msec()
	while Time.get_ticks_msec() < waited + 30000 and reconnect_syncs[0] == 0:
		var now_pid: int = reconnect._pid
		if new_pid[0] == -1 and now_pid > 0 and now_pid != alive_pid:
			new_pid[0] = now_pid
			old_running_then[0] = OS.is_process_running(alive_pid)
		await process_frame
	_check(reconnect_restarts.size() == 1 and str(reconnect_restarts[0]).begins_with("Couldn't connect to the sidecar"), "S01 restart: a reconnect that fails at once while the sidecar runs restarts it (%s)" % [reconnect_restarts])
	_check(new_pid[0] > 0 and not old_running_then[0], "S01 restart: the old sidecar has stopped before the new one appears")
	_check(reconnect_syncs[0] == 1 and reconnect.status == SidecarClient.Status.READY and seen_reconnect["failed"].is_empty(), "S01 restart: and it ends ready, no failure said")
	reconnect.stop()
	reconnect.queue_free()
	# S01 restart: a sidecar that keeps dying once up fails within the
	# start's attempts, once, instead of restarting forever.
	var dying := Starting.new()
	dying.handshake_timeouts_s = [20.0, 20.0, 20.0]
	dying.commands = [["node", ProjectSettings.globalize_path("res://sidecar/test/dev-fake.ts"), "serve", "--no-outside-sessions"]]
	var deaths := [0]
	dying.synced.connect(func(_p: Array) -> void:
		deaths[0] += 1
		OS.kill(dying._pid))
	_errors.expect("Sidecar: The sidecar stopped.")
	var seen_dying := await _follow_start(dying, 60.0)
	await _until(func() -> bool: return dying.status == SidecarClient.Status.FAILED, 60.0)
	_check(dying.status == SidecarClient.Status.FAILED and deaths[0] == 3 and seen_dying["failed"] == ["The sidecar stopped."], "S01 restart: one that keeps dying fails after the start's three attempts, once (%d up)" % deaths[0])
	_check(not OS.is_process_running(dying._pid) and dying._pid == -1, "S01 restart: none left")
	dying.queue_free()


func _fake(mode: String) -> Array:
	return ["node", ProjectSettings.globalize_path("res://tests/core/fake_sidecar.mjs"), mode]


# Starts [param client] and follows it until it's ready or has failed:
# every sidecar it ran, whether one ran while an earlier one still did,
# its failures and how long it took.
func _follow_start(client: SidecarClient, timeout_s: float) -> Dictionary:
	var seen := {"pids": [], "two": false, "failed": []}
	client.failed.connect(func(reason: String) -> void: seen["failed"].append(reason))
	var started := Time.get_ticks_msec()
	root.add_child(client) # _ready starts it
	while Time.get_ticks_msec() < started + int(timeout_s * 1000):
		var pid: int = client._pid
		if pid > 0 and not seen["pids"].has(pid):
			if seen["pids"].any(func(p: int) -> bool: return OS.is_process_running(p)):
				seen["two"] = true
			seen["pids"].append(pid)
		if client.status in [SidecarClient.Status.READY, SidecarClient.Status.FAILED]:
			break
		await process_frame
	seen["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	return seen


## Runs [member commands] instead of a sidecar, one per attempt (the last
## for the rest), with short attempts; or, with none, the usual command
## from [member args] as Godot's command line.
class Starting extends SidecarClient:
	var commands: Array = []
	var args := PackedStringArray()
	var connect_errors := 0 # the first this many connects fail at once

	func _connect() -> Error:
		if connect_errors > 0:
			connect_errors -= 1
			return ERR_CANT_CONNECT
		return super()

	func _init() -> void:
		handshake_timeouts_s = [0.5, 0.7, 0.9]
		retry_waits_s = [0.2, 0.3]

	func _sidecar_command() -> Array:
		if commands.is_empty():
			return super()
		return commands[mini(_attempt, commands.size() - 1)]

	func _cmdline_args() -> PackedStringArray:
		return args


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
