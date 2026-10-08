class_name SessionStore
extends RefCounted
## Godot's copy of every live session (NOTES.md → Protocol), kept up to date
## from the sidecar's events. The world and the chat panel read it and listen
## to its signals instead of parsing protocol messages themselves.
##
## Provider-neutral: it only knows the generic protocol. Extension messages
## are passed on untouched through [signal extension_event], for the
## provider's own UI module.
##
## [codeblock]
## var store := SessionStore.new()
## store.attach(Sidecar)
## store.session_added.connect(func(id, created): ...)
## [/codeblock]

## A session appeared: [param created] is true for a new one (the island
## rises), false for one that already existed (placed as is).
signal session_added(session: String, created: bool)
signal session_removed(session: String, reason: String)
signal agent_added(session: String, agent: String)
## An agent's [code]state[/code] or [code]reason[/code] changed.
signal agent_changed(session: String, agent: String)
## A chat message started, grew, or completed.
signal message_changed(session: String, message: String)
## A tool call started or finished (C04).
signal tool_changed(session: String, tool_call: String)
## Tool calls were added or changed in bulk ([method load_history]): lay the
## log out again.
signal tools_loaded(session: String)
signal permissions_changed(session: String)
signal questions_changed(session: String)
## A plan was asked for approval or resolved (C07, the [code]plans[/code]
## capability).
signal plans_changed(session: String)
signal notices_changed(session: String)
## Some of the session's own fields changed (e.g. [code]native_id[/code]
## after the provider started a new conversation in it, or [code]mode[/code],
## the permission mode, C06); [param fields] names them.
signal session_changed(session: String, fields: Array)
## The chat was replaced as a whole ([method replace_history]): lay it out
## again.
signal messages_replaced(session: String)
## The session's token usage changed (C08, the [code]usage[/code]
## capability): its [code]usage[/code], and the turn's
## [code]turn_tokens[/code] on the user message that started it.
signal usage_changed(session: String)
## A provider extension message ([code]ext.<provider>.<name>[/code]).
signal extension_event(session: String, msg: Dictionary)

## Chat messages kept per session; the oldest go first.
const MAX_MESSAGES := 2000
## Tool calls kept per session, for the tool-call log (C04); the oldest go
## first. As many as the sidecar's history keeps.
const MAX_TOOLS := 5000

## Session id → the protocol's session object (agents, permissions,
## questions, plans, mode, notices, ...), plus [code]messages[/code] (id →
## message, with [code]kind[/code] when the protocol gives one, e.g.
## [code]"plan"[/code]) and
## [code]message_order[/code] (ids, oldest first), [code]tools[/code]
## (tool call id → call, shaped like the protocol's [code]history_tool[/code])
## A user message may have [code]turn_tokens[/code]: the output tokens of the
## turn it started (C08), from the history and kept up from
## [code]usage.updated[/code]. [code]usage[/code] is the session's latest
## figures (null until the first count).
## and [code]tool_order[/code], and
## [code]pending_order[/code] ([code][kind, id][/code] per pending permission,
## question and plan, oldest first; read it through [method pending]).
var sessions := {}

var _seen_since_sync := {}


## Follows a [SidecarClient]: every event, and each (re)connect's snapshots.
func attach(client: SidecarClient) -> void:
	client.event_received.connect(apply)
	client.sync_started.connect(func() -> void: _seen_since_sync.clear())
	client.synced.connect(func(_providers: Array) -> void: _on_synced())


## The session, or an empty dictionary.
func session(id: String) -> Dictionary:
	return sessions.get(id, {})


## One agent of a session, or an empty dictionary.
func agent(session_id: String, agent_id: String) -> Dictionary:
	for a in session(session_id).get("agents", []):
		if a["agent"] == agent_id:
			return a
	return {}


## A session's orchestrator (the agent with no parent), or an empty
## dictionary.
func orchestrator(session_id: String) -> Dictionary:
	for a in session(session_id).get("agents", []):
		if a["role"] == "orchestrator":
			return a
	return {}


## What the session waits on the user for, oldest first: permission
## prompts, questions and plans, each as [code]{"kind": "permission",
## "question" or "plan", "item": <the protocol's object>}[/code]. Each item's
## [code]asked_at[/code] is when the sidecar first saw it: it orders a
## snapshot's new items, and times how long the session has waited.
func pending(session_id: String) -> Array[Dictionary]:
	var s := session(session_id)
	var out: Array[Dictionary] = []
	for key in s.get("pending_order", []):
		var item := _find(s, key[0], key[1])
		if not item.is_empty():
			out.append({"kind": key[0], "item": item})
	return out


## What the whole session is doing, subagents included: "waiting" if any
## agent waits on you, else "working" if any works (so a session whose
## orchestrator is idle while its subagents work counts as working), else
## "error" if the orchestrator stopped on one, else "idle".
func activity(session_id: String) -> String:
	var states := {}
	for a in session(session_id).get("agents", []):
		states[a["state"]] = true
	if states.has("waiting"):
		return "waiting"
	if states.has("working"):
		return "working"
	if orchestrator(session_id).get("state", "") == "error":
		return "error"
	return "idle"


## The chat so far, oldest first.
func messages(session_id: String) -> Array[Dictionary]:
	var s := session(session_id)
	var out: Array[Dictionary] = []
	for id in s.get("message_order", []):
		out.append(s["messages"][id])
	return out


## The plans' usage limits (C08), per provider, across its sessions:
## [code]{provider: {five_hour, seven_day}}[/code], each the most recent
## figures, [code]{used_percent, resets_at}[/code]. Each provider's are its
## own account's (a user may run several tools at once). A session's
## figures stay as they were until it hears again, so the newest is the
## one with the latest [code]resets_at[/code] (a later window) and, in the
## same window, the highest use (use only grows within a window). One whose
## [code]resets_at[/code] has passed by [param now] (Unix seconds) is left
## out: that window is over and its figures say nothing about the next
## (Claude Code drops it too). A provider with none is left out.
func usage_limits(now: float) -> Dictionary:
	var out := {}
	for id in sessions:
		var usage = sessions[id].get("usage")
		if not usage is Dictionary:
			continue
		var provider := str(sessions[id].get("provider", ""))
		var limits: Dictionary = usage.get("limits", {})
		for key in ["five_hour", "seven_day"]:
			var limit = limits.get(key)
			if not limit is Dictionary:
				continue
			var resets := unix_time(limit["resets_at"])
			if resets <= now:
				continue
			var theirs: Dictionary = out.get(provider, {})
			var best: Dictionary = theirs.get(key, {})
			var at := unix_time(best.get("resets_at"))
			if best.is_empty() or resets > at or (resets == at and limit["used_percent"] > best["used_percent"]):
				theirs[key] = limit
				out[provider] = theirs
	return out


## A protocol timestamp ([code]2026-10-08T12:00:00.000Z[/code], UTC) in Unix
## seconds, or 0 if it can't be read.
static func unix_time(timestamp) -> float:
	if not timestamp is String or timestamp.length() < 19:
		return 0.0
	return float(Time.get_unix_time_from_datetime_string(timestamp.substr(0, 19)))


## The tool calls, oldest first.
func tool_calls(session_id: String) -> Array[Dictionary]:
	var s := session(session_id)
	var out: Array[Dictionary] = []
	for id in s.get("tool_order", []):
		out.append(s["tools"][id])
	return out


## The tool-call log as the chat shows it (C04), in one pass:
## [code]{"after": {message id → [call ids]}, "within": {call id → [call
## ids]}}[/code], each list oldest first. A call goes [code]within[/code]
## the call that started its subagent when that one is known, else
## [code]after[/code] the message it followed ([code]""[/code]: before the
## first).
func tool_tree(session_id: String) -> Dictionary:
	var s := session(session_id)
	var tree := {"after": {}, "within": {}}
	for id in s.get("tool_order", []):
		place_tool(tree, s["tools"], s["tools"][id])
	return tree


## Adds one call to a [method tool_tree] ([param tools]: the session's
## [code]tools[/code]). Returns the list it went in.
static func place_tool(tree: Dictionary, tools: Dictionary, call: Dictionary) -> Array:
	var within = call.get("within")
	var list: Array
	if within is String and tools.has(within):
		list = tree["within"].get_or_add(within, [])
	else:
		var after = call.get("after")
		list = tree["after"].get_or_add(after if after is String else "", [])
	list.append(call["tool_call"])
	return list


## The top-level call a call is part of (itself, unless it's a subagent's
## call within another), or an empty dictionary.
func top_tool(session_id: String, tool_call: String) -> Dictionary:
	var tools: Dictionary = session(session_id).get("tools", {})
	var call: Dictionary = tools.get(tool_call, {})
	# Bounded, in case of a loop.
	for i in 16:
		var within = call.get("within")
		if not (within is String and tools.has(within)):
			break
		call = tools[within]
	return call


## Fills in the chat from [code]session.get_history[/code]'s messages and
## tool calls. Messages already known (seen live) are kept as they are; a
## tool call already known takes the history's copy, which is as new (the
## reply comes after every event before it) and knows where the call goes
## ([code]after[/code]) even when it was seen before the chat had loaded.
func load_history(session_id: String, history: Array, tools := []) -> void:
	var s := session(session_id)
	if s.is_empty():
		return
	var order: Array = []
	for m in history:
		var id: String = m["message"]
		if not s["messages"].has(id):
			s["messages"][id] = _message(m)
			order.append(id)
	s["message_order"] = order + s["message_order"]
	_trim_messages(s)
	var tool_order: Array = []
	for t in tools:
		var id: String = t["tool_call"]
		if not s["tools"].has(id):
			tool_order.append(id)
		s["tools"][id] = _tool(t)
	s["tool_order"] = tool_order + s["tool_order"]
	_trim_tools(s)
	for id in order:
		message_changed.emit(session_id, id)
	if not tools.is_empty():
		tools_loaded.emit(session_id)


## Replaces the chat with [code]session.get_history[/code]'s messages,
## after the provider switched conversations ([code]native_id[/code]
## changed), and the tool calls with [param tools]. Messages and calls that
## arrived since the switch and aren't in the history are kept after it (a
## reply still streaming, say).
func replace_history(session_id: String, history: Array, tools := []) -> void:
	var s := session(session_id)
	if s.is_empty():
		return
	var before: Array = s.get("chat_before_switch", [])
	var messages := {}
	var order: Array = []
	for m in history:
		var id: String = m["message"]
		messages[id] = _message(m)
		order.append(id)
	for id in s["message_order"]:
		if not before.has(id) and not messages.has(id):
			messages[id] = s["messages"][id]
			order.append(id)
	s["messages"] = messages
	s["message_order"] = order
	s.erase("chat_before_switch")
	_trim_messages(s)
	var tools_before: Array = s.get("tools_before_switch", [])
	var calls := {}
	var tool_order: Array = []
	for t in tools:
		calls[t["tool_call"]] = _tool(t)
		tool_order.append(t["tool_call"])
	for id in s["tool_order"]:
		if not tools_before.has(id) and not calls.has(id):
			calls[id] = s["tools"][id]
			tool_order.append(id)
	s["tools"] = calls
	s["tool_order"] = tool_order
	s.erase("tools_before_switch")
	_trim_tools(s)
	messages_replaced.emit(session_id)


## Applies one event from the sidecar.
func apply(msg: Dictionary) -> void:
	var type: String = msg.get("type", "")
	if type == "session.snapshot" or type == "session.created":
		_put_session(msg["session"], type == "session.created")
		return
	var id: String = msg.get("session", "")
	if type.begins_with("ext."):
		extension_event.emit(id, msg)
		return
	var s := session(id)
	if s.is_empty():
		return
	match type:
		"session.ended":
			sessions.erase(id)
			session_removed.emit(id, msg["reason"])
		"session.notice":
			var notice: Dictionary = msg["notice"]
			var notices: Array = s["notices"]
			notices.assign(notices.filter(func(n: Dictionary) -> bool: return n["code"] != notice["code"]))
			notices.append(notice)
			notices_changed.emit(id)
		"session.updated":
			var fields := []
			for key in msg:
				if key not in ["type", "session", "seq"]:
					s[key] = msg[key]
					fields.append(key)
			if "native_id" in fields:
				# Messages from now on belong to the new conversation, whatever
				# replace_history() brings.
				s["chat_before_switch"] = s["message_order"].duplicate()
				s["tools_before_switch"] = s["tool_order"].duplicate()
			session_changed.emit(id, fields)
		"agent.spawned":
			s["agents"].append(msg["agent"])
			agent_added.emit(id, msg["agent"]["agent"])
		"agent.state_changed":
			var a := agent(id, msg["agent"])
			if not a.is_empty():
				a["state"] = msg["state"]
				a["reason"] = msg["reason"]
				agent_changed.emit(id, msg["agent"])
		"message.started":
			var m := {
				"message": msg["message"], "agent": msg["agent"], "role": msg["role"],
				"text": "", "at": Time.get_datetime_string_from_system(true), "complete": false,
			}
			if msg.has("kind"):
				m["kind"] = msg["kind"]
			if not s["messages"].has(m["message"]):
				s["message_order"].append(m["message"])
			s["messages"][m["message"]] = m
			_trim_messages(s)
			message_changed.emit(id, m["message"])
		"message.delta":
			var m: Dictionary = s["messages"].get(msg["message"], {})
			if not m.is_empty():
				m["text"] += msg["text"]
				message_changed.emit(id, msg["message"])
		"message.completed":
			var m: Dictionary = s["messages"].get(msg["message"], {})
			if not m.is_empty():
				m["text"] = msg["text"]
				m["complete"] = true
				message_changed.emit(id, msg["message"])
		"tool.started":
			# It came after the latest message started, like the sidecar's
			# history has it.
			var order: Array = s["message_order"]
			var call := _tool(msg)
			call["status"] = "running"
			call["after"] = order.back() if not order.is_empty() else null
			if not s["tools"].has(call["tool_call"]):
				s["tool_order"].append(call["tool_call"])
			s["tools"][call["tool_call"]] = call
			_trim_tools(s)
			tool_changed.emit(id, call["tool_call"])
		"tool.finished":
			var call: Dictionary = s["tools"].get(msg["tool_call"], {})
			if not call.is_empty():
				call["status"] = msg["status"]
				if msg.has("summary"):
					call["result"] = msg["summary"]
				tool_changed.emit(id, msg["tool_call"])
		"permission.requested":
			s["permissions"].append(msg["permission"])
			s["pending_order"].append(["permission", msg["permission"]["permission"]])
			permissions_changed.emit(id)
		"permission.resolved":
			var list: Array = s["permissions"]
			list.assign(list.filter(func(p: Dictionary) -> bool: return p["permission"] != msg["permission"]))
			s["pending_order"].erase(["permission", msg["permission"]])
			permissions_changed.emit(id)
		"question.asked":
			s["questions"].append(msg["question"])
			s["pending_order"].append(["question", msg["question"]["question"]])
			questions_changed.emit(id)
		"question.resolved":
			var list: Array = s["questions"]
			list.assign(list.filter(func(q: Dictionary) -> bool: return q["question"] != msg["question"]))
			s["pending_order"].erase(["question", msg["question"]])
			questions_changed.emit(id)
		"plan.asked":
			s["plans"].append(msg["plan"])
			s["pending_order"].append(["plan", msg["plan"]["plan"]])
			plans_changed.emit(id)
		"plan.resolved":
			var list: Array = s["plans"]
			list.assign(list.filter(func(p: Dictionary) -> bool: return p["plan"] != msg["plan"]))
			s["pending_order"].erase(["plan", msg["plan"]])
			plans_changed.emit(id)
		"usage.updated":
			s["usage"] = msg["usage"]
			_note_turn(s)
			usage_changed.emit(id)


# The turn's tokens so far go on the user message that started it.
static func _note_turn(s: Dictionary) -> void:
	var usage = s.get("usage")
	if not usage is Dictionary:
		return
	var m: Dictionary = s["messages"].get(usage["turn"]["message"], {})
	if m.get("role") == "user":
		m["turn_tokens"] = int(usage["turn"]["output_tokens"])


func _put_session(snapshot: Dictionary, created: bool) -> void:
	var id: String = snapshot["session"]
	var old := session(id)
	var s := snapshot.duplicate(true)
	s["seq"] = int(s["seq"])
	if not s.has("questions"):
		s["questions"] = []
	if not s.has("plans"):
		s["plans"] = []
	if not s.has("notices"):
		s["notices"] = []
	# Keep the order we saw them in; ones new in the snapshot go last, by
	# when they were asked (without asked_at, permissions, then questions,
	# then plans).
	var order: Array = []
	for key in old.get("pending_order", []):
		if _find(s, key[0], key[1]).size() > 0:
			order.append(key)
	var added: Array = []
	for kind in ["permission", "question", "plan"]:
		for item in s[kind + "s"]:
			if not order.has([kind, item[kind]]):
				added.append({"key": [kind, item[kind]], "at": str(item.get("asked_at", ""))})
	# Stable: sort_custom isn't, so ties keep their place through the index.
	for i in added.size():
		added[i]["i"] = i
	added.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["at"] < b["at"] if a["at"] != b["at"] else a["i"] < b["i"])
	for a in added:
		order.append(a["key"])
	s["pending_order"] = order
	# A snapshot replaces the state, but the chat and tool log are ours.
	s["messages"] = old.get("messages", {})
	s["message_order"] = old.get("message_order", [])
	s["tools"] = old.get("tools", {})
	s["tool_order"] = old.get("tool_order", [])
	var known := not old.is_empty()
	sessions[id] = s
	_note_turn(s)
	_seen_since_sync[id] = true
	if known:
		# Everything may have changed (a resync after a gap).
		var fields := []
		for key in ["title", "mode"]:
			if s.get(key) != old.get(key):
				fields.append(key)
		if not fields.is_empty():
			session_changed.emit(id, fields)
		for a in s["agents"]:
			agent_changed.emit(id, a["agent"])
		permissions_changed.emit(id)
		questions_changed.emit(id)
		plans_changed.emit(id)
		notices_changed.emit(id)
		if s.get("usage") != old.get("usage"):
			usage_changed.emit(id)
	else:
		session_added.emit(id, created)


## After a (re)connect's snapshots: sessions the sidecar no longer has
## ended while we weren't listening.
func _on_synced() -> void:
	for id in sessions.keys():
		if not _seen_since_sync.has(id):
			sessions.erase(id)
			session_removed.emit(id, "exited")


# A chat message as the store keeps it, from a history_message.
static func _message(m: Dictionary) -> Dictionary:
	var out := {
		"message": m["message"], "agent": m["agent"], "role": m["role"],
		"text": m["text"], "at": m["at"], "complete": true,
	}
	if m.has("kind"):
		out["kind"] = m["kind"]
	if m.has("turn_tokens"):
		out["turn_tokens"] = int(m["turn_tokens"])
	return out


# A tool call as the store keeps it, from tool.started or a history_tool.
static func _tool(t: Dictionary) -> Dictionary:
	var call := {}
	for key in ["tool_call", "agent", "tool", "summary", "input", "status", "result", "after", "within"]:
		if t.has(key):
			call[key] = t[key]
	return call


# A pending permission, question or plan ([param kind]) by id, or {}.
static func _find(s: Dictionary, kind: String, id: String) -> Dictionary:
	for item in s[kind + "s"]:
		if item[kind] == id:
			return item
	return {}


func _trim_messages(s: Dictionary) -> void:
	var order: Array = s["message_order"]
	while order.size() > MAX_MESSAGES:
		s["messages"].erase(order.pop_front())


func _trim_tools(s: Dictionary) -> void:
	var order: Array = s["tool_order"]
	while order.size() > MAX_TOOLS:
		s["tools"].erase(order.pop_front())
