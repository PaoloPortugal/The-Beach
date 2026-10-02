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
signal tool_changed(session: String, tool_call: String)
signal permissions_changed(session: String)
signal questions_changed(session: String)
signal notices_changed(session: String)
## Some of the session's own fields changed (e.g. [code]native_id[/code]
## after the provider started a new conversation in it); [param fields]
## names them.
signal session_changed(session: String, fields: Array)
## The chat was replaced as a whole ([method replace_history]): lay it out
## again.
signal messages_replaced(session: String)
## A provider extension message ([code]ext.<provider>.<name>[/code]).
signal extension_event(session: String, msg: Dictionary)

## Chat messages kept per session; the oldest go first.
const MAX_MESSAGES := 2000
## Finished tool calls kept per session, for the tool-call log (C04).
const MAX_TOOLS := 500

## Session id → the protocol's session object (agents, permissions,
## questions, notices, ...), plus [code]messages[/code] (id → message) and
## [code]message_order[/code] (ids, oldest first), [code]tools[/code]
## (tool call id → call) and [code]tool_order[/code], and
## [code]pending_order[/code] ([code][kind, id][/code] per pending permission
## and question, oldest first; read it through [method pending]).
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
## prompts and questions, each as [code]{"kind": "permission" or
## "question", "item": <the protocol's object>}[/code]. A snapshot doesn't
## say which of the two kinds came first, so a snapshot's permissions count
## as older than its questions.
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


## Fills in the chat from [code]session.get_history[/code]'s messages. Ones
## already known (seen live) are kept as they are.
func load_history(session_id: String, history: Array) -> void:
	var s := session(session_id)
	if s.is_empty():
		return
	var order: Array = []
	for m in history:
		var id: String = m["message"]
		if not s["messages"].has(id):
			s["messages"][id] = {
				"message": id, "agent": m["agent"], "role": m["role"],
				"text": m["text"], "at": m["at"], "complete": true,
			}
			order.append(id)
	s["message_order"] = order + s["message_order"]
	_trim_messages(s)
	for id in order:
		message_changed.emit(session_id, id)


## Replaces the chat with [code]session.get_history[/code]'s messages,
## after the provider switched conversations ([code]native_id[/code]
## changed). Messages that arrived since the switch and aren't in
## [param history] are kept after it (a reply still streaming, say).
func replace_history(session_id: String, history: Array) -> void:
	var s := session(session_id)
	if s.is_empty():
		return
	var before: Array = s.get("chat_before_switch", [])
	var messages := {}
	var order: Array = []
	for m in history:
		var id: String = m["message"]
		messages[id] = {
			"message": id, "agent": m["agent"], "role": m["role"],
			"text": m["text"], "at": m["at"], "complete": true,
		}
		order.append(id)
	for id in s["message_order"]:
		if not before.has(id) and not messages.has(id):
			messages[id] = s["messages"][id]
			order.append(id)
	s["messages"] = messages
	s["message_order"] = order
	s.erase("chat_before_switch")
	_trim_messages(s)
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
			var call := {
				"tool_call": msg["tool_call"], "agent": msg["agent"], "tool": msg["tool"],
				"summary": msg["summary"], "status": "running",
			}
			if msg.has("input"):
				call["input"] = msg["input"]
			s["tools"][call["tool_call"]] = call
			s["tool_order"].append(call["tool_call"])
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


func _put_session(snapshot: Dictionary, created: bool) -> void:
	var id: String = snapshot["session"]
	var old := session(id)
	var s := snapshot.duplicate(true)
	s["seq"] = int(s["seq"])
	if not s.has("questions"):
		s["questions"] = []
	if not s.has("notices"):
		s["notices"] = []
	# Keep the order we saw them in; ones new in the snapshot go last.
	var order: Array = []
	for key in old.get("pending_order", []):
		if _find(s, key[0], key[1]).size() > 0:
			order.append(key)
	for kind in ["permission", "question"]:
		for item in s[kind + "s"]:
			if not order.has([kind, item[kind]]):
				order.append([kind, item[kind]])
	s["pending_order"] = order
	# A snapshot replaces the state, but the chat and tool log are ours.
	s["messages"] = old.get("messages", {})
	s["message_order"] = old.get("message_order", [])
	s["tools"] = old.get("tools", {})
	s["tool_order"] = old.get("tool_order", [])
	var known := not old.is_empty()
	sessions[id] = s
	_seen_since_sync[id] = true
	if known:
		# Everything may have changed (a resync after a gap).
		if s.get("title") != old.get("title"):
			session_changed.emit(id, ["title"])
		for a in s["agents"]:
			agent_changed.emit(id, a["agent"])
		permissions_changed.emit(id)
		questions_changed.emit(id)
		notices_changed.emit(id)
	else:
		session_added.emit(id, created)


## After a (re)connect's snapshots: sessions the sidecar no longer has
## ended while we weren't listening.
func _on_synced() -> void:
	for id in sessions.keys():
		if not _seen_since_sync.has(id):
			sessions.erase(id)
			session_removed.emit(id, "exited")


# A pending permission or question ([param kind]) by id, or {}.
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
