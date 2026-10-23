class_name SidecarClient
extends Node
## Starts the sidecar and talks to it over the local WebSocket (NOTES.md → S01).
##
## Autoloaded as [code]Sidecar[/code]. Starts the sidecar with an argument
## array and a pipe, reads the one-line handshake (port and token) from its
## stdout, then connects with the token. The sidecar exits when the pipe
## closes, so it never outlives the game, even after a crash.
##
## Which sidecar runs:
## - exported game: the [code]sidecar[/code] executable next to the game's;
## - editor / dev: [code]node sidecar/src/main.ts[/code] (Node 22.18+ on PATH);
## - [code]-- --sidecar=<path>[/code] on Godot's command line: that executable;
## - [code]-- --sidecar-dev-fake[/code]: the scripted fake provider, for
##   building the world without a real AI tool (dev only; see NOTES.md →
##   Running it).

## A (re)connect began: the live sessions' snapshots follow, then
## [signal synced].
signal sync_started

## The connection is up and the initial snapshots have been delivered.
signal synced(providers: Array)
## Any event from the sidecar: snapshots, session and agent events,
## extension messages. Stale ones (seq already covered) are filtered out.
signal event_received(msg: Dictionary)
## The sidecar can't be used. [param reason] is for the player.
signal failed(reason: String)
## [member providers] changed: a (re)connect's hello, or a provider notice
## ([code]provider.notice[/code], e.g. S08's [code]outside_sessions_off[/code]).
signal providers_changed

enum Status { STOPPED, STARTING, CONNECTING, SYNCING, READY, FAILED }

const PROTOCOL_VERSION := 1
const HANDSHAKE_TIMEOUT_S := 20.0
## Largest message Godot accepts. Chat history comes in one message; the
## default (64 KiB) would drop a long reply.
const INBOUND_BUFFER := 32 * 1024 * 1024
const OUTBOUND_BUFFER := 4 * 1024 * 1024

## Where the player's settings are (C10's file, [Settings]): its
## [code][game] outside_sessions[/code] is read before the sidecar starts
## (S08). The suites point it elsewhere ([code]tests/error_watch.gd[/code]).
static var settings_file := "user://settings.cfg"

var status: Status = Status.STOPPED
## The providers from hello: [code]{provider, name, launch_options,
## capabilities, notices}[/code], their notices kept up from
## [code]provider.notice[/code].
var providers: Array = []
## Whether sessions started outside the game get islands (S08; the
## player's setting, [method set_outside_sessions]).
var outside_sessions := true

var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _out_thread: Thread
var _err_thread: Thread
var _mutex := Mutex.new()
var _handshake_line := ""
var _handshake_done := false
var _stderr_lines: PackedStringArray = []
var _started_at := 0.0
var _ws: WebSocketPeer
var _port := 0
var _token := ""
var _next_id := 0
var _pending := {} # command id → Callable(reply: Dictionary)
var _seq := {} # session id → last seq seen
var _resyncing := {} # session id → true while a get_snapshot is out
var _focused := true


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_file) == OK:
		outside_sessions = cfg.get_value("game", "outside_sessions", true) != false
	start()


func _process(_delta: float) -> void:
	_drain_stderr()
	match status:
		Status.STARTING:
			_check_handshake()
		Status.CONNECTING, Status.SYNCING, Status.READY:
			_poll_socket()


func _exit_tree() -> void:
	stop()


# The sidecar may look less often while the game is in the background
# (S08's poll).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		var focused := what == NOTIFICATION_APPLICATION_FOCUS_IN
		if focused != _focused:
			_focused = focused
			send_command("client.set_focus", {"focused": focused})


## Shows or hides the sessions started outside the game (S08): the sidecar
## ends theirs when off, and brings them up (rising) when on. A sidecar
## started later starts with it.
func set_outside_sessions(on: bool) -> void:
	if on == outside_sessions:
		return
	outside_sessions = on
	send_command("client.set_outside_sessions", {"enabled": on})


## A provider notice of that code from any provider (hello's, or a
## [code]provider.notice[/code] since), or an empty dictionary.
func provider_notice(code: String) -> Dictionary:
	for p: Dictionary in providers:
		for n: Dictionary in p.get("notices", []):
			if n.get("code") == code:
				return n
	return {}


## Whether any provider declares that capability of its own (hello).
func provider_capable(capability: String) -> bool:
	return providers.any(func(p: Dictionary) -> bool: return p.get("capabilities", {}).has(capability))


## Sends a command. [param fields] are its fields without [code]type[/code]
## and [code]id[/code]. [param on_reply] gets the [code]ok[/code] or
## [code]error[/code] reply; if the connection drops first, an
## [code]error[/code] with code [code]disconnected[/code] (the command may
## or may not have arrived). Returns the command id, or "" if not connected.
func send_command(type: String, fields: Dictionary = {}, on_reply := Callable()) -> String:
	if status != Status.READY and status != Status.SYNCING:
		return ""
	_next_id += 1
	var id := "g%d" % _next_id
	var msg := fields.duplicate()
	msg["type"] = type
	msg["id"] = id
	if on_reply.is_valid():
		_pending[id] = on_reply
	_ws.send_text(JSON.stringify(msg))
	return id


func start() -> void:
	if status != Status.STOPPED and status != Status.FAILED:
		return
	var cmd := _sidecar_command()
	if cmd.is_empty():
		return
	var result := OS.execute_with_pipe(cmd[0], PackedStringArray(cmd.slice(1)), true)
	if result.is_empty():
		_fail("Couldn't start the sidecar (%s)." % cmd[0])
		return
	_pid = result["pid"]
	_stdio = result["stdio"]
	_stderr = result["stderr"]
	_handshake_done = false
	_handshake_line = ""
	_started_at = Time.get_ticks_msec() / 1000.0
	status = Status.STARTING
	# Blocking reads, one thread per pipe. stderr must be drained all the
	# time, or the sidecar could stall writing its log.
	_out_thread = Thread.new()
	_out_thread.start(_read_handshake)
	_err_thread = Thread.new()
	_err_thread.start(_read_stderr)


func stop() -> void:
	if _ws:
		_ws.close()
		_ws = null
	if _pid > 0:
		_mutex.lock()
		var handshake_read := _handshake_done
		_mutex.unlock()
		if handshake_read and _stdio:
			# Closing our end of its stdin is how the sidecar is told to exit.
			_out_thread.wait_to_finish()
			_stdio.close()
			var deadline := Time.get_ticks_msec() + 3000
			while OS.is_process_running(_pid) and Time.get_ticks_msec() < deadline:
				OS.delay_msec(20)
		# Still running (or never got as far as the handshake, with a thread
		# blocked reading its stdout): end it, which also unblocks the reads.
		if OS.is_process_running(_pid):
			OS.kill(_pid)
	for t in [_out_thread, _err_thread]:
		if t and t.is_started():
			t.wait_to_finish()
	_out_thread = null
	_err_thread = null
	_drain_stderr()
	_pid = -1
	_stdio = null
	_stderr = null
	_pending.clear()
	_seq.clear()
	_resyncing.clear()
	if status != Status.FAILED:
		status = Status.STOPPED


func _sidecar_command() -> Array:
	var user_args := OS.get_cmdline_user_args()
	for arg in user_args:
		if arg.begins_with("--sidecar="):
			# Relative paths are relative to the working directory.
			var given := arg.trim_prefix("--sidecar=")
			if given.is_relative_path():
				given = DirAccess.open(".").get_current_dir().path_join(given)
			return [given.simplify_path()] + _serve_args()
	if OS.has_feature("editor"):
		var dir := ProjectSettings.globalize_path("res://sidecar")
		var entry := "test/dev-fake.ts" if "--sidecar-dev-fake" in user_args else "src/main.ts"
		return ["node", dir.path_join(entry)] + _serve_args()
	var exe := "sidecar.exe" if OS.get_name() == "Windows" else "sidecar"
	var path := OS.get_executable_path().get_base_dir().path_join(exe)
	if not FileAccess.file_exists(path):
		_fail("The sidecar is missing from the game folder. Reinstalling the game should fix this.")
		return []
	return [path] + _serve_args()


# The server mode's arguments: the player's outside-sessions setting (S08),
# so none shows at start when it's off.
func _serve_args() -> Array:
	return [] if outside_sessions else ["serve", "--no-outside-sessions"]


# ---- pipes (threads) ----

func _read_handshake() -> void:
	# The sidecar writes exactly one line to stdout. Reading stops after it,
	# so no thread is left blocked on this pipe.
	var line := _stdio.get_line()
	_mutex.lock()
	_handshake_line = line
	_handshake_done = true
	_mutex.unlock()


func _read_stderr() -> void:
	while true:
		var line := _stderr.get_line()
		# When the sidecar exits, a Windows pipe reports ERR_FILE_CANT_READ
		# without eof_reached; treat any read error as the end.
		if _stderr.eof_reached() or _stderr.get_error() != OK:
			if not line.is_empty():
				_mutex.lock()
				_stderr_lines.append(line)
				_mutex.unlock()
			break
		_mutex.lock()
		_stderr_lines.append(line)
		_mutex.unlock()


func _drain_stderr() -> void:
	_mutex.lock()
	var lines := _stderr_lines
	_stderr_lines = []
	_mutex.unlock()
	# The sidecar never logs session content, so its lines are safe to print.
	for line in lines:
		print(line)


# ---- startup ----

func _check_handshake() -> void:
	_mutex.lock()
	var done := _handshake_done
	var line := _handshake_line
	_mutex.unlock()
	if not done:
		if Time.get_ticks_msec() / 1000.0 - _started_at > HANDSHAKE_TIMEOUT_S:
			_fail("The sidecar didn't start in time.")
		return
	var hs = JSON.parse_string(line)
	if typeof(hs) != TYPE_DICTIONARY or hs.get("type") != "ready":
		_fail("The sidecar stopped while starting.")
		return
	if int(hs.get("protocol", 0)) != PROTOCOL_VERSION:
		_fail("The sidecar speaks a different protocol version; reinstall the game.")
		return
	_port = int(hs.get("port", 0))
	_token = str(hs.get("token", ""))
	if _port <= 0 or _port > 65535 or _token.length() != 64:
		_fail("The sidecar sent a bad handshake.")
		return
	_connect()


func _connect() -> void:
	_ws = WebSocketPeer.new()
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + _token])
	_ws.inbound_buffer_size = INBOUND_BUFFER
	_ws.outbound_buffer_size = OUTBOUND_BUFFER
	var err := _ws.connect_to_url("ws://127.0.0.1:%d/" % _port)
	if err != OK:
		_fail("Couldn't connect to the sidecar (error %d)." % err)
		return
	status = Status.CONNECTING


# ---- socket ----

func _poll_socket() -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if status == Status.CONNECTING:
				status = Status.SYNCING
			while _ws and _ws.get_available_packet_count() > 0:
				var packet := _ws.get_packet()
				if not _ws.was_string_packet():
					continue
				_handle(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code := _ws.get_close_code()
			_ws = null
			# The replies on their way are lost with the connection.
			_drop_pending()
			if _pid > 0 and OS.is_process_running(_pid):
				# The sidecar is alive: connect again (it replaces the old link).
				push_warning("Sidecar connection closed (code %d); reconnecting." % code)
				_connect()
			else:
				_fail("The sidecar stopped.")


func _handle(text: String) -> void:
	var msg = JSON.parse_string(text)
	if typeof(msg) != TYPE_DICTIONARY or not msg.has("type"):
		push_warning("Sidecar sent something that isn't a message.")
		return
	var type: String = msg["type"]
	match type:
		"hello":
			if int(msg.get("protocol", 0)) != PROTOCOL_VERSION:
				_fail("The sidecar speaks a different protocol version; reinstall the game.")
				return
			providers = msg.get("providers", [])
			sync_started.emit()
			providers_changed.emit()
			return
		"sync.completed":
			status = Status.READY
			# Until told, the sidecar takes the window as focused.
			if not _focused:
				send_command("client.set_focus", {"focused": false})
			# A change made while reconnecting was lost (S08); the sidecar
			# ignores one that isn't a change.
			send_command("client.set_outside_sessions", {"enabled": outside_sessions})
			synced.emit(providers)
			return
		"provider.notice":
			var notice: Dictionary = msg.get("notice", {})
			for p: Dictionary in providers:
				if p.get("provider") == msg.get("provider"):
					var notices: Array = p.get("notices", []).filter(func(n: Dictionary) -> bool: return n.get("code") != notice.get("code"))
					notices.append(notice)
					p["notices"] = notices
			providers_changed.emit()
			return
		"ok", "error":
			var id = msg.get("id")
			if id == null:
				push_warning("Sidecar protocol error: %s" % msg.get("message", ""))
			elif _pending.has(id):
				var cb: Callable = _pending[id]
				_pending.erase(id)
				cb.call(msg)
			return
	if _is_stale(msg):
		return
	event_received.emit(msg)


## Tracks each session's seq. Returns true for events a snapshot already
## covers. On a gap, asks for a fresh snapshot (once) and still passes the
## event on.
func _is_stale(msg: Dictionary) -> bool:
	var type: String = msg["type"]
	if type == "session.snapshot" or type == "session.created":
		var s: Dictionary = msg["session"]
		_seq[s["session"]] = int(s["seq"])
		_resyncing.erase(s["session"])
		return false
	if not msg.has("session") or not msg.has("seq"):
		return false
	var id: String = msg["session"]
	var seq := int(msg["seq"])
	if type == "session.ended":
		_seq.erase(id)
		_resyncing.erase(id)
		return false
	if not _seq.has(id):
		return false
	var last: int = _seq[id]
	if seq <= last:
		return true
	if seq > last + 1 and not _resyncing.has(id):
		_resyncing[id] = true
		send_command("session.get_snapshot", {"session": id})
	_seq[id] = seq
	return false


# Answers every command still waiting for a reply with an error, so no
# caller waits forever (a card stuck on "sending", say).
func _drop_pending() -> void:
	var waiting := _pending
	_pending = {}
	for id in waiting:
		(waiting[id] as Callable).call({"type": "error", "id": id, "code": "disconnected",
			"message": "the connection to the sidecar dropped, so it may not have arrived."})


func _fail(reason: String) -> void:
	push_error("Sidecar: " + reason)
	status = Status.FAILED
	failed.emit(reason)
	stop()
