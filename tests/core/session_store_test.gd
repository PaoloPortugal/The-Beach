extends SceneTree
## Headless test for the session store: events applied by hand, then (with
## the scripted fake) a live session through the real sidecar.
##
##   godot --headless --path . --script res://tests/core/session_store_test.gd
##   ... -- --sidecar-dev-fake      also drives the fake provider's scenarios

const ErrorWatch := preload("res://tests/error_watch.gd")

var _failed := false
var _errors := ErrorWatch.new(self)


func _initialize() -> void:
	_run()


func _run() -> void:
	_by_hand()
	_usage_by_hand()
	_usage_text()
	if "--sidecar-dev-fake" in OS.get_cmdline_user_args():
		await _live()
	if not _failed and _errors.ok():
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
	_check(store.session("a")["tools"]["t1"]["after"] == "m1", "a tool call comes after the latest message")

	store.apply({"type": "permission.requested", "session": "a", "seq": 9, "permission": {"permission": "p1", "agent": "main", "tool": "Bash", "summary": "Run: ls"}})
	_check(store.session("a")["permissions"].size() == 1, "permission pending")
	store.apply({"type": "permission.resolved", "session": "a", "seq": 10, "permission": "p1", "decision": "allow", "by": "app"})
	_check(store.session("a")["permissions"].is_empty(), "permission resolved")

	# Pending requests in the order they came, across both kinds.
	var question := {"question": "q1", "agent": "main", "items": [{"text": "?", "options": [], "multi_select": false}]}
	store.apply({"type": "question.asked", "session": "b", "seq": 2, "question": question})
	store.apply({"type": "permission.requested", "session": "b", "seq": 3, "permission": {"permission": "p2", "agent": "main", "tool": "Bash", "summary": "Run: ls"}})
	var kinds := func() -> Array: return store.pending("b").map(func(c: Dictionary) -> String: return "%s %s" % [c["kind"], c["item"][c["kind"]]])
	_check(kinds.call() == ["question q1", "permission p2"], "pending: oldest first, both kinds")
	var resync := _snapshot("b", 4)
	resync["permissions"] = [{"permission": "p2", "agent": "main", "tool": "Bash", "summary": "Run: ls"}, {"permission": "p3", "agent": "main", "tool": "Bash", "summary": "Run: pwd"}]
	resync["questions"] = [question]
	store.apply({"type": "session.snapshot", "session": resync})
	_check(kinds.call() == ["question q1", "permission p2", "permission p3"], "a resync keeps their order; new ones go last")
	store.apply({"type": "question.resolved", "session": "b", "seq": 5, "question": "q1", "by": "external"})
	_check(kinds.call() == ["permission p2", "permission p3"], "a resolved one leaves the queue")

	# A session first seen in a snapshot: its requests go by asked_at,
	# whatever their kind, and keep it.
	var seen := _snapshot("c")
	seen["permissions"] = [{"permission": "p9", "agent": "main", "tool": "Bash", "summary": "Run: ls", "asked_at": "2026-09-29T10:00:05.000Z"}]
	seen["questions"] = [{"question": "q9", "agent": "main", "asked_at": "2026-09-29T10:00:01.000Z", "items": [{"text": "?", "options": [], "multi_select": false}]}]
	store.apply({"type": "session.snapshot", "session": seen})
	var waits: Array = store.pending("c").map(func(c: Dictionary) -> String: return "%s %s" % [c["item"][c["kind"]], c["item"]["asked_at"]])
	_check(waits == ["q9 2026-09-29T10:00:01.000Z", "p9 2026-09-29T10:00:05.000Z"], "a snapshot's requests go oldest first by asked_at")
	store.sessions.erase("c")

	# Modes and plans (C06, C07).
	var planned := _snapshot("d")
	planned["capabilities"] = {"permission_modes": {}, "plans": {}}
	planned["mode"] = "plan"
	planned["permissions"] = [{"permission": "p8", "agent": "main", "tool": "Bash", "summary": "Run: ls", "options": [{"option": "auto", "label": "Yes, and switch to auto mode"}], "asked_at": "2026-09-29T10:00:09.000Z"}]
	planned["plans"] = [{"plan": "x1", "agent": "main", "text": "# Plan", "modes": ["auto", "default"], "asked_at": "2026-09-29T10:00:02.000Z"}]
	store.apply({"type": "session.snapshot", "session": planned})
	var d_kinds := func() -> Array: return store.pending("d").map(func(c: Dictionary) -> String: return "%s %s" % [c["kind"], c["item"][c["kind"]]])
	_check(store.session("d")["mode"] == "plan" and d_kinds.call() == ["plan x1", "permission p8"], "a snapshot's mode, and its plans by asked_at with the rest")
	var plan_signals := []
	store.plans_changed.connect(func(id: String) -> void: plan_signals.append(id))
	store.apply({"type": "plan.asked", "session": "d", "seq": 2, "plan": {"plan": "x2", "agent": "main", "text": "# Again", "modes": ["acceptEdits", "default"]}})
	_check(d_kinds.call() == ["plan x1", "permission p8", "plan x2"] and plan_signals == ["d"], "plan.asked queues it")
	store.apply({"type": "plan.resolved", "session": "d", "seq": 3, "plan": "x1", "decision": "approved", "by": "app"})
	_check(d_kinds.call() == ["permission p8", "plan x2"] and store.session("d")["plans"].size() == 1 and plan_signals == ["d", "d"], "plan.resolved clears it")
	var mode_changes := []
	store.session_changed.connect(func(id: String, fields: Array) -> void: mode_changes.append([id, fields]))
	store.apply({"type": "session.updated", "session": "d", "seq": 4, "mode": "auto"})
	_check(store.session("d")["mode"] == "auto" and mode_changes == [["d", ["mode"]]], "session.updated changes the mode")
	var resynced := planned.duplicate(true)
	resynced["seq"] = 5
	resynced["mode"] = "default"
	store.apply({"type": "session.snapshot", "session": resynced})
	_check(mode_changes.back() == ["d", ["mode"]], "a resync that changes the mode says so")
	store.apply({"type": "message.started", "session": "d", "seq": 6, "message": "pm", "agent": "main", "role": "assistant", "kind": "plan"})
	store.load_history("d", [
		{"message": "hp", "agent": "main", "role": "assistant", "kind": "plan", "text": "# Old plan", "at": "2026-09-29T09:00:00Z"},
		{"message": "hm", "agent": "main", "role": "assistant", "text": "Hi", "at": "2026-09-29T09:00:01Z"},
	])
	var d_chat := store.messages("d")
	_check(d_chat.map(func(m: Dictionary) -> String: return m.get("kind", "-")) == ["plan", "-", "plan"], "a message's kind, live and from the history")
	store.replace_history("d", [{"message": "rp", "agent": "main", "role": "assistant", "kind": "plan", "text": "# R", "at": "2026-09-29T09:00:00Z"}])
	_check(store.messages("d")[0].get("kind") == "plan", "and after a switch")
	store.sessions.erase("d")

	store.apply({"type": "session.notice", "session": "a", "seq": 11, "notice": {"code": "transcripts_off", "message": "x"}})
	store.apply({"type": "session.notice", "session": "a", "seq": 12, "notice": {"code": "transcripts_off", "message": "y"}})
	var notices: Array = store.session("a")["notices"]
	_check(notices.size() == 1 and notices[0]["message"] == "y", "one notice per code")
	var notice_signals := [0]
	store.notices_changed.connect(func(_id: String) -> void: notice_signals[0] += 1)
	store.apply({"type": "session.notice", "session": "a", "seq": 13, "notice": {"code": "sign_in_needed", "message": "z"}})
	store.apply({"type": "session.notice_cleared", "session": "a", "seq": 14, "code": "sign_in_needed"})
	notices = store.session("a")["notices"]
	_check(notices.size() == 1 and notices[0]["code"] == "transcripts_off" and notice_signals[0] == 2, "a cleared notice goes, the others stay")
	store.apply({"type": "session.notice_cleared", "session": "a", "seq": 15, "code": "sign_in_needed"})
	_check(store.session("a")["notices"].size() == 1 and notice_signals[0] == 2, "clearing one that isn't there changes nothing")

	var changed := []
	store.session_changed.connect(func(id: String, fields: Array) -> void: changed.append([id, fields]))
	store.apply({"type": "session.updated", "session": "a", "seq": 13, "native_id": "n2"})
	_check(store.session("a")["native_id"] == "n2" and changed == [["a", ["native_id"]]], "session.updated")

	store.apply({"type": "ext.fake.ping", "session": "a", "seq": 14})
	_check(log.back() == "ext a ext.fake.ping", "extension messages pass through")

	store.load_history("a", [
		{"message": "u0", "agent": "main", "role": "user", "text": "hi", "at": "2026-09-29T09:00:00Z"},
		{"message": "m1", "agent": "main", "role": "assistant", "text": "old copy", "at": "2026-09-29T09:00:01Z"},
	])
	var chat := store.messages("a")
	_check(chat.size() == 2 and chat[0]["text"] == "hi" and chat[1]["text"] == "Hello.", "history goes first; live messages win")

	# Tool calls in the history (C04): older ones go first, a known one
	# takes the history's copy, a subagent's call goes within its Agent call.
	var loaded := []
	store.tools_loaded.connect(func(id: String) -> void: loaded.append(id))
	store.load_history("a", [], [
		{"tool_call": "t0", "agent": "main", "tool": "Agent", "summary": "Agent: look", "status": "ok", "after": "u0"},
		{"tool_call": "t2", "agent": "s1", "tool": "Read", "summary": "Read x", "input": {"file_path": "x"}, "status": "error", "result": "No such file", "after": null, "within": "t0"},
		{"tool_call": "t1", "agent": "s1", "tool": "Bash", "summary": "Run: ls", "status": "denied", "after": "m1", "extra": 1},
	])
	var calls: Array = store.tool_calls("a").map(func(c: Dictionary) -> String: return c["tool_call"])
	_check(calls == ["t0", "t2", "t1"] and loaded == ["a"], "history's tool calls go first")
	_check(store.session("a")["tools"]["t2"]["result"] == "No such file" and not store.session("a")["tools"]["t1"].has("extra"), "they keep their result, only known fields")
	var tree := store.tool_tree("a")
	_check(tree["after"] == {"u0": ["t0"], "m1": ["t1"]} and tree["within"] == {"t0": ["t2"]}, "the log's tree: after messages, within calls")
	_check(store.top_tool("a", "t2")["tool_call"] == "t0" and store.top_tool("a", "t1")["tool_call"] == "t1", "a subagent's call belongs to its Agent call")
	store.apply({"type": "tool.started", "session": "a", "seq": 14, "tool_call": "t3", "agent": "s1", "tool": "Read", "summary": "Read y", "within": "gone"})
	_check(store.tool_tree("a")["after"]["m1"] == ["t1", "t3"], "within an unknown call: after its message instead")

	# Switching conversations (/resume): the chat is replaced by the
	# sidecar's history; a message that came after the switch is kept.
	store.apply({"type": "session.updated", "session": "a", "seq": 15, "native_id": "n3"})
	store.apply({"type": "message.started", "session": "a", "seq": 16, "message": "live", "agent": "main", "role": "assistant"})
	store.apply({"type": "tool.started", "session": "a", "seq": 17, "tool_call": "t9", "agent": "main", "tool": "Read", "summary": "Read z"})
	var replaced := []
	store.messages_replaced.connect(func(id: String) -> void: replaced.append(id))
	store.replace_history("a", [{"message": "r1", "agent": "main", "role": "user", "text": "earlier", "at": "2026-09-29T08:00:00Z"}],
		[{"tool_call": "rt1", "agent": "main", "tool": "Read", "summary": "Read NOTES.md", "status": "ok", "after": "r1"}])
	chat = store.messages("a")
	_check(chat.map(func(m: Dictionary) -> String: return m["message"]) == ["r1", "live"] and replaced == ["a"], "a switch replaces the chat, keeping what came after it")
	calls = store.tool_calls("a").map(func(c: Dictionary) -> String: return c["tool_call"])
	_check(calls == ["rt1", "t9"] and store.tool_tree("a")["after"] == {"r1": ["rt1"], "live": ["t9"]}, "and its tool calls")

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


func _usage(turn_message, turn_tokens: int, limits := [], context = null) -> Dictionary:
	return {
		"tokens": {"input": 40, "output": 1200, "cache_read": 52000, "cache_write": 9000},
		"context": context, "turn": {"message": turn_message, "output_tokens": turn_tokens}, "limits": limits,
	}


# Token usage (C08): the session's figures, each turn's tokens on its user
# message, and the plan's limits across sessions.
func _usage_by_hand() -> void:
	var store := SessionStore.new()
	var changed := []
	store.usage_changed.connect(func(id: String) -> void: changed.append(id))
	var snap := _snapshot("u")
	snap["capabilities"] = {"usage": {}}
	snap["usage"] = null
	store.apply({"type": "session.snapshot", "session": snap})
	_check(store.session("u")["usage"] == null and changed.is_empty(), "usage: null until the first count")
	store.load_history("u", [
		{"message": "h1", "agent": "main", "role": "user", "text": "hi", "at": "2026-10-08T09:00:00Z", "turn_tokens": 1840},
		{"message": "h2", "agent": "main", "role": "assistant", "text": "Hello", "at": "2026-10-08T09:00:01Z"},
	])
	_check(store.messages("u")[0]["turn_tokens"] == 1840 and not store.messages("u")[1].has("turn_tokens"), "usage: the history's turn tokens")
	store.apply({"type": "message.started", "session": "u", "seq": 2, "message": "m1", "agent": "main", "role": "user"})
	store.apply({"type": "message.completed", "session": "u", "seq": 3, "message": "m1", "text": "go"})
	store.apply({"type": "usage.updated", "session": "u", "seq": 4, "usage": _usage("m1", 0)})
	store.apply({"type": "usage.updated", "session": "u", "seq": 5, "usage": _usage("m1", 350)})
	_check(changed == ["u", "u"] and store.session("u")["usage"]["turn"]["output_tokens"] == 350, "usage: usage.updated replaces the figures")
	_check(store.messages("u")[2]["turn_tokens"] == 350 and store.messages("u")[0]["turn_tokens"] == 1840, "usage: the turn going on counts on its user message")
	store.apply({"type": "message.started", "session": "u", "seq": 6, "message": "a1", "agent": "main", "role": "assistant"})
	store.apply({"type": "usage.updated", "session": "u", "seq": 7, "usage": _usage("a1", 99)})
	_check(not store.messages("u")[3].has("turn_tokens"), "usage: turn tokens only ever go on a user message")
	var gap := snap.duplicate(true)
	gap["seq"] = 9
	gap["usage"] = _usage("m1", 900)
	store.apply({"type": "session.snapshot", "session": gap})
	_check(changed.size() == 4 and store.messages("u")[2]["turn_tokens"] == 900, "usage: a resync with new figures says so")
	store.apply({"type": "session.snapshot", "session": gap})
	_check(changed.size() == 4, "usage: the same figures again aren't news")

	# The plan's limits: per limit, the latest window, and in one window
	# the highest use; a window that's over is left out.
	var now := SessionStore.unix_time("2026-10-08T12:00:00Z")
	_check(now == 1791460800.0 and SessionStore.unix_time("2026-10-08T12:00:00.000Z") == now and SessionStore.unix_time(null) == 0.0, "usage: timestamps read as UTC")
	var lim := func(id: String, used: float, at: String) -> Dictionary:
		return {"id": id, "label": {"five_hour": "5-hour", "seven_day": "Weekly"}.get(id, id), "used_percent": used, "resets_at": at}
	# A provider's limits as [id, used_percent], in order.
	var figures := func(limits: Array) -> Array: return limits.map(func(l: Dictionary) -> Array: return [l["id"], roundi(l["used_percent"])])
	store.apply({"type": "usage.updated", "session": "u", "seq": 10, "usage": _usage("m1", 900,
		[lim.call("five_hour", 70, "2026-10-08T14:00:00.000Z"), lim.call("seven_day", 94, "2026-10-10T09:00:00.000Z")])})
	var other := _snapshot("v")
	other["capabilities"] = {"usage": {}}
	other["usage"] = _usage(null, 0, [lim.call("five_hour", 75, "2026-10-08T14:00:00.000Z"), lim.call("seven_day", 90, "2026-10-10T09:00:00.000Z")])
	store.apply({"type": "session.snapshot", "session": other})
	var limits: Array = store.usage_limits(now)["fake"]
	_check(figures.call(limits) == [["five_hour", 75], ["seven_day", 94]], "usage: the same window: the highest use, across sessions")
	_check(limits[0]["label"] == "5-hour" and limits[1]["label"] == "Weekly", "usage: each limit keeps the provider's label")
	store.apply({"type": "usage.updated", "session": "u", "seq": 11, "usage": _usage("m1", 900,
		[lim.call("five_hour", 3, "2026-10-08T19:00:00.000Z")])})
	limits = store.usage_limits(now)["fake"]
	_check(figures.call(limits) == [["five_hour", 3], ["seven_day", 90]], "usage: a later window wins; an absent limit leaves the other session's")
	# The provider's order holds across sessions, whichever has which.
	store.apply({"type": "usage.updated", "session": "u", "seq": 12, "usage": _usage("m1", 900,
		[lim.call("seven_day", 91, "2026-10-10T09:00:00.000Z")])})
	_check(figures.call(store.usage_limits(now)["fake"]) == [["five_hour", 75], ["seven_day", 91]], "usage: the provider's order across sessions")
	store.apply({"type": "usage.updated", "session": "u", "seq": 13, "usage": _usage("m1", 900,
		[lim.call("five_hour", 3, "2026-10-08T19:00:00.000Z")])})
	# Another provider's limits are its own account's, its own ids and
	# words, kept apart.
	var codex := _snapshot("w")
	codex["provider"] = "codex"
	codex["capabilities"] = {"usage": {}}
	codex["usage"] = _usage(null, 0, [lim.call("daily", 99, "2026-10-08T23:00:00.000Z"), lim.call("five_hour", 10, "2026-10-08T15:00:00.000Z")])
	store.apply({"type": "session.snapshot", "session": codex})
	var both := store.usage_limits(now)
	_check(both.size() == 2 and both["codex"] == codex["usage"]["limits"]
		and figures.call(both["fake"]) == [["five_hour", 3], ["seven_day", 90]], "usage: limits per provider, never mixed")
	limits = store.usage_limits(SessionStore.unix_time("2026-10-08T20:00:00Z"))["fake"]
	_check(figures.call(limits) == [["seven_day", 90]], "usage: a limit past its reset is left out")
	_check(store.usage_limits(SessionStore.unix_time("2026-10-11T00:00:00Z")).is_empty(), "usage: none once every window is over, nor its provider")
	var none := _snapshot("x")
	none["capabilities"] = {"usage": {}}
	none["usage"] = _usage(null, 0)
	store.apply({"type": "session.snapshot", "session": none})
	_check(not store.usage_limits(now).has("") and store.usage_limits(now)["fake"].size() == 2, "usage: an empty list adds nothing")


func _usage_text() -> void:
	var cases := {0: "0", 950: "950", 999: "999", 1000: "1k", 1234: "1.2k", 9949: "9.9k", 9950: "10k",
		34400: "34k", 999499: "999k", 999500: "1M", 1100000: "1.1M", 9949999: "9.9M", 9950000: "10M", 12400000: "12M"}
	var wrong := []
	for n in cases:
		if UsageText.tokens(n) != cases[n]:
			wrong.append("%d → %s" % [n, UsageText.tokens(n)])
	_check(wrong.is_empty(), "usage text: compact counts %s" % [wrong])
	_check(UsageText.exact(1234567) == "1,234,567" and UsageText.exact(12) == "12", "usage text: exact counts")
	var u := _usage("m1", 1234, [], {"tokens": 62200, "percent": 31.4, "window": 200000})
	_check(UsageText.header(u) == "Context 31% · ↑ 61k in · ↓ 1.2k out", "usage text: the header with a context %%: %s" % UsageText.header(u))
	u["context"] = {"tokens": 62200, "percent": null, "window": null}
	_check(UsageText.header(u) == "Context 62k · ↑ 61k in · ↓ 1.2k out", "usage text: without the status line, context in tokens")
	u["context"] = null
	_check(UsageText.header(u) == "↑ 61k in · ↓ 1.2k out" and UsageText.header(null) == "", "usage text: no context yet; no usage")
	var nothing := _usage(null, 0)
	nothing["tokens"] = {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0}
	_check(UsageText.header(nothing) == "", "usage text: nothing counted yet")
	nothing["context"] = {"tokens": 64000, "percent": 32, "window": 200000}
	_check(UsageText.header(nothing) == "Context 32%", "usage text: the status line's context only (transcripts off)")
	_check(UsageText.header_details(u) == "Input: 40
Cache reads: 52,000
Cache writes: 9,000
Output: 1,200", "usage text: the exact figures")
	_check(UsageText.turn(1234) == "↓ 1.2k tokens", "usage text: a turn's hint")
	# Times read in local time: build them from local noon today.
	var bias := float(Time.get_time_zone_from_system()["bias"]) * 60.0
	var t := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system() + bias))
	var noon := Time.get_unix_time_from_datetime_dict({"year": t["year"], "month": t["month"], "day": t["day"], "hour": 12, "minute": 0, "second": 0}) - bias
	_check(UsageText.when(noon + 3.0 * 3600 + 40 * 60, noon) == "3:40 PM" and UsageText.when(noon - 12 * 3600 + 5 * 60, noon - 12 * 3600) == "12:05 AM", "usage text: a time today")
	var day: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(int(t["weekday"]) + 2) % 7]
	_check(UsageText.when(noon + 2 * 86400 - 3 * 3600, noon) == "%s 9:00 AM" % day, "usage text: a day this week")
	_check(UsageText.limit("5-hour", 74.4, noon + 3600, noon) == "5-hour 74% · resets 1:00 PM", "usage text: a limit")


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
	_check(str(store.session(id)["permissions"][0].get("asked_at", "")).length() > 0, "live: the sidecar timed the request")
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

	# S06: the turn fails on the account, then the next message goes through.
	await _until(func() -> bool: return store.agent(id, "main")["state"] == "idle", 5.0)
	await _command(sidecar, "message.send", {"session": id, "text": "signin"})
	await _until(func() -> bool: return store.agent(id, "main")["state"] == "waiting", 5.0)
	_check(store.agent(id, "main")["reason"] == "sign_in" and store.session(id)["notices"].any(func(n: Dictionary) -> bool: return n["code"] == "sign_in_needed"), "live: the sign-in notice, waiting to sign in")
	await _command(sidecar, "message.send", {"session": id, "text": "hello"})
	await _until(func() -> bool: return store.agent(id, "main")["state"] == "idle", 5.0)
	_check(store.session(id)["notices"].map(func(n: Dictionary) -> String: return n["code"]) == ["transcripts_off"], "live: the next message clears it")

	await _command(sidecar, "message.send", {"session": id, "text": "use some tools"})
	await _until(func() -> bool: return store.messages(id).back()["text"].begins_with("One test failed") and store.messages(id).back()["complete"], 8.0)
	var history := await _command(sidecar, "session.get_history", {"session": id})
	_check(history["result"]["messages"].size() >= 8, "live: history")
	var live := store.tool_calls(id)
	var from_history: Array = history["result"]["tools"]
	_check(live.size() == from_history.size() and from_history.size() == 1 + 2 * 4 + 3, "live: every tool call is in the history too")
	var same := true
	for i in live.size():
		for key in ["tool_call", "status", "after", "within", "result"]:
			same = same and live[i].get(key) == from_history[i].get(key)
	_check(same, "live: the store places them as the sidecar does")
	var tree := store.tool_tree(id)
	var agent_calls: Array = store.tool_calls(id).filter(func(c: Dictionary) -> bool: return c["tool"] == "Agent")
	_check(agent_calls.size() == 2 and agent_calls.all(func(c: Dictionary) -> bool: return tree["within"].get(c["tool_call"], []).size() == 3), "live: each subagent's calls within its Agent call")
	var last_turn: Array = tree["after"].get(store.messages(id)[-2]["message"], [])
	_check(last_turn.size() == 3 and store.session(id)["tools"][last_turn[2]]["status"] == "error", "live: the tools turn's calls after its message, one failed")

	# Token usage (C08): the fake counts every reply and tool call as an
	# API call; "usage" plays a heavy turn.
	_check(store.session(id)["capabilities"].has("usage") and store.session(id)["usage"] is Dictionary, "live: usage counted")
	await _command(sidecar, "message.send", {"session": id, "text": "usage"})
	await _until(func() -> bool: return store.messages(id).back()["text"].begins_with("Done. The context") and store.agent(id, "main")["state"] == "idle", 10.0)
	var usage: Dictionary = store.session(id)["usage"]
	var asked: Dictionary = store.messages(id).filter(func(m: Dictionary) -> bool: return m["role"] == "user").back()
	_check(usage["context"]["percent"] >= 80 and usage["context"]["window"] == 200000, "live: the heavy turn fills the context")
	var fake_limits: Array = store.usage_limits(Time.get_unix_time_from_system())["fake"]
	_check(fake_limits.map(func(l: Dictionary) -> String: return l["label"]) == ["5-hour", "Weekly"] and fake_limits[0]["id"] == "five_hour"
		and fake_limits[0]["used_percent"] >= 85, "live: and the 5-hour limit, in the provider's order and words")
	_check(usage["turn"]["message"] == asked["message"] and asked["turn_tokens"] == usage["turn"]["output_tokens"] and asked["turn_tokens"] >= 4 * 2500, "live: the turn's tokens are on its message")
	history = await _command(sidecar, "session.get_history", {"session": id})
	# A turn with no tokens may have 0 here and none there: neither shows.
	var turns := func(list: Array) -> Array:
		return list.filter(func(m: Dictionary) -> bool: return m.get("turn_tokens", 0) > 0) \
			.map(func(m: Dictionary) -> Array: return [m["message"], int(m["turn_tokens"])])
	_check(turns.call(history["result"]["messages"]) == turns.call(store.messages(id)), "live: the history agrees")
	await _command(sidecar, "message.send", {"session": id, "text": "clear"})
	await _until(func() -> bool: return store.session(id)["usage"]["turn"]["message"] == null, 5.0)
	usage = store.session(id)["usage"]
	_check(usage["tokens"]["output"] == 0 and usage["context"] == null and usage["limits"].size() == 2, "live: /clear starts the counts over, keeping the limits")

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
