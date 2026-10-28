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
## [member providers] changed: a (re)connect's hello, a provider notice
## ([code]provider.notice[/code], e.g. S08's [code]outside_sessions_off[/code]),
## or the program a provider found ([code]provider.program[/code], S02).
signal providers_changed

enum Status { STOPPED, STARTING, CONNECTING, SYNCING, READY, FAILED }

const PROTOCOL_VERSION := 1
## A start that fails in a way that can pass is tried again (user's
## decision, 2026-10-28): three attempts, each waiting longer for the
## handshake (a cold first start is the likely cause of a slow one), with
## these waits between them. [signal failed] comes once, after the last.
const HANDSHAKE_TIMEOUTS_S: Array[float] = [20.0, 30.0, 45.0]
const RETRY_WAITS_S: Array[float] = [2.0, 5.0]
## The longest a start can take before [signal failed], every attempt and
## wait included (the connect and sync after the handshake aren't).
const START_TIMEOUT_S: float = HANDSHAKE_TIMEOUTS_S[0] + RETRY_WAITS_S[0] \
		+ HANDSHAKE_TIMEOUTS_S[1] + RETRY_WAITS_S[1] + HANDSHAKE_TIMEOUTS_S[2]
## Largest message Godot accepts. Chat history comes in one message; the
## default (64 KiB) would drop a long reply.
const INBOUND_BUFFER := 32 * 1024 * 1024
const OUTBOUND_BUFFER := 4 * 1024 * 1024

## Where the player's settings are (C10's file, [Settings]): its
## [code][game] outside_sessions[/code] (S08) and [code][programs][/code]
## (S02) are read before the sidecar starts. The suites point it elsewhere
## ([code]tests/error_watch.gd[/code]).
static var settings_file := "user://settings.cfg"

var status: Status = Status.STOPPED
## The providers from hello: [code]{provider, name, launch_options,
## capabilities, notices, program}[/code], their notices and program kept
## up from [code]provider.notice[/code] and [code]provider.program[/code].
var providers: Array = []
## Whether sessions started outside the game get islands (S08; the
## player's setting, [method set_outside_sessions]).
var outside_sessions := true
## The programs set by hand (S02; the player's setting,
## [method set_program_path]): provider id → absolute path. Saved in the
## settings file's [code][programs][/code] section, and given to the
## sidecar at start ([code]serve --program-path[/code]).
var program_paths := {}
## [constant HANDSHAKE_TIMEOUTS_S] and [constant RETRY_WAITS_S] as used;
## the suites shorten them.
var handshake_timeouts_s := HANDSHAKE_TIMEOUTS_S
var retry_waits_s := RETRY_WAITS_S

var _attempt := 0 # this start's attempt, from 0
var _starting := false # from start() to the first sync.completed
var _retry_at := 0.0 # > 0: waiting to try again at this time (s)
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
		if cfg.has_section("programs"):
			for provider: String in cfg.get_section_keys("programs"):
				var p: Variant = cfg.get_value("programs", provider)
				if p is String and not (p as String).is_empty():
					program_paths[provider] = p
	start()


func _process(_delta: float) -> void:
	_drain_stderr()
	match status:
		Status.STARTING:
			if _retry_at <= 0.0:
				_check_handshake()
			elif _now() >= _retry_at:
				_retry_at = 0.0
				_launch()
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


## Sets a provider's program by hand ([param path] absolute), or clears it
## (empty: found as usual) (S02). The sidecar checks it first: refused,
## the setting stays. Accepted, it's saved and used from then on.
## [param on_reply] gets the reply ([code]ok[/code] with
## [code]{program}[/code], or [code]error[/code]: [code]invalid_program[/code]
## says why, [code]disconnected[/code] if the sidecar isn't there).
func set_program_path(provider: String, path: String, on_reply := Callable()) -> void:
	var done := func(reply: Dictionary) -> void:
		if reply.get("type") == "ok":
			_program_set(provider, path, reply.get("result", {}).get("program", {}))
		if on_reply.is_valid():
			on_reply.call(reply)
	if send_command("client.set_program_path", {"provider": provider, "path": path if not path.is_empty() else null}, done) == "":
		done.call({"type": "error", "code": "disconnected", "message": "The sidecar isn't running."})


## Has a provider look for its program again now (S02's Look again; the
## one set by hand, if any, is checked again). [param on_reply] gets the
## reply ([code]ok[/code] with [code]{program}[/code], found or not, or
## [code]error[/code]; [code]disconnected[/code] if the sidecar isn't
## there). What it found is kept and shown.
func find_program(provider: String, on_reply := Callable()) -> void:
	var done := func(reply: Dictionary) -> void:
		if reply.get("type") == "ok":
			_set_program(provider, reply.get("result", {}).get("program", {}))
		if on_reply.is_valid():
			on_reply.call(reply)
	if send_command("client.find_program", {"provider": provider}, done) == "":
		done.call({"type": "error", "code": "disconnected", "message": "The sidecar isn't running."})


## The providers that can start a session now (S02): all but those whose
## program wasn't found. One still looking counts: it may yet be found.
func startable_providers() -> Array:
	return providers.filter(func(p: Dictionary) -> bool:
		var program: Dictionary = p.get("program", {})
		return not (program.has("path") and program["path"] == null))


## What a provider found for its program (S02): [code]{path, version,
## set_by_hand}[/code], [code]{path: null, set_by_hand, message}[/code], or
## empty if it hasn't looked yet.
func provider_program(provider: String) -> Dictionary:
	for p: Dictionary in providers:
		if p.get("provider") == provider:
			return p.get("program", {})
	return {}


# Accepted: kept, saved with the player's other settings, and shown.
func _program_set(provider: String, path: String, program: Dictionary) -> void:
	if path.is_empty():
		program_paths.erase(provider)
	else:
		program_paths[provider] = path
	var cfg := ConfigFile.new()
	cfg.load(settings_file) # keep the other settings
	if path.is_empty():
		if cfg.has_section_key("programs", provider):
			cfg.erase_section_key("programs", provider)
	else:
		cfg.set_value("programs", provider, path)
	cfg.save(settings_file)
	_set_program(provider, program)


func _set_program(provider: String, program: Dictionary) -> void:
	for p: Dictionary in providers:
		if p.get("provider") == provider:
			p["program"] = program
	providers_changed.emit()


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


## Starts the sidecar, trying again if a start fails in a way that can
## pass ([constant HANDSHAKE_TIMEOUTS_S]). Does nothing while one runs or
## is starting.
func start() -> void:
	if status != Status.STOPPED and status != Status.FAILED:
		return
	_attempt = 0
	_starting = true
	_launch()


# One attempt. Not being able to start a process at all isn't tried again.
func _launch() -> void:
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
	_started_at = _now()
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
	_retry_at = 0.0
	if status != Status.FAILED:
		status = Status.STOPPED


func _sidecar_command() -> Array:
	var user_args := _cmdline_args()
	for arg in user_args:
		if arg.begins_with("--sidecar="):
			# Relative paths are relative to the working directory.
			var given := arg.trim_prefix("--sidecar=")
			if given.is_relative_path():
				given = DirAccess.open(".").get_current_dir().path_join(given)
			given = given.simplify_path()
			# Checked here, as below: on Linux and macOS a missing program
			# would only show as a sidecar that stopped while starting.
			if not FileAccess.file_exists(given):
				_fail("There's no sidecar at %s." % given)
				return []
			return [given] + _serve_args()
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


# Godot's command line after "--" (the suites give their own).
func _cmdline_args() -> PackedStringArray:
	return OS.get_cmdline_user_args()


# The server mode's arguments: the player's outside-sessions setting (S08),
# so none shows at start when it's off, and the programs set by hand (S02).
# Only well-formed provider ids, and paths without a quote or a control
# character (Windows' command line could split one into another argument):
# the sidecar refuses a malformed flag and won't start, and a hand-edited
# settings file mustn't lock the game out.
func _serve_args() -> Array:
	var args := [] if outside_sessions else ["--no-outside-sessions"]
	var id_pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	var bad_path := RegEx.create_from_string("[\"\\x00-\\x1f\\x7f]")
	var ids := program_paths.keys().filter(func(id: Variant) -> bool:
		return id is String and id_pattern.search(id) != null and bad_path.search(str(program_paths[id])) == null)
	ids.sort()
	for provider: String in ids:
		args.append_array(["--program-path", "%s=%s" % [provider, program_paths[provider]]])
	return [] if args.is_empty() else ["serve"] + args


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
		if _now() - _started_at > handshake_timeouts_s[_attempt]:
			_start_failed("The sidecar didn't start in time.")
		return
	# Empty if it exited first. Parsed without JSON.parse_string, which logs
	# an error for that (a start that's tried again isn't one).
	var json := JSON.new()
	var hs: Variant = json.data if json.parse(line) == OK else null
	if typeof(hs) != TYPE_DICTIONARY or hs.get("type") != "ready":
		_start_failed("The sidecar stopped while starting.")
		return
	if int(hs.get("protocol", 0)) != PROTOCOL_VERSION:
		_fail("The sidecar speaks a different protocol version; reinstall the game.")
		return
	_port = int(hs.get("port", 0))
	_token = str(hs.get("token", ""))
	if _port <= 0 or _port > 65535 or _token.length() != 64:
		_start_failed("The sidecar sent a bad handshake.")
		return
	var err := _connect()
	if err != OK:
		_start_failed("Couldn't connect to the sidecar (error %d)." % err)


# An attempt failed in a way that can pass: the next one after a wait, or,
# after the last, [method _fail]. Its process is ended first (stop() kills
# it if it won't exit), so there are never two sidecars.
func _start_failed(reason: String) -> void:
	if _attempt + 1 >= handshake_timeouts_s.size():
		_fail(reason)
		return
	var wait := retry_waits_s[mini(_attempt, retry_waits_s.size() - 1)]
	var old_pid := _pid
	stop()
	if old_pid > 0 and OS.is_process_running(old_pid):
		# It couldn't be ended: another would make two.
		_fail(reason)
		return
	push_warning("Sidecar: %s Trying again in %s s (attempt %d of %d)." % [reason, wait, _attempt + 2, handshake_timeouts_s.size()])
	_attempt += 1
	_retry_at = _now() + wait
	status = Status.STARTING


func _connect() -> Error:
	_ws = WebSocketPeer.new()
	_ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + _token])
	_ws.inbound_buffer_size = INBOUND_BUFFER
	_ws.outbound_buffer_size = OUTBOUND_BUFFER
	var err := _ws.connect_to_url("ws://127.0.0.1:%d/" % _port)
	if err != OK:
		return err
	status = Status.CONNECTING
	return OK


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
			var alive := _pid > 0 and OS.is_process_running(_pid)
			if _starting:
				# Closed (refused, say) before the first sync: this attempt failed.
				if alive:
					_start_failed("Couldn't connect to the sidecar (closed, code %d)." % code)
				else:
					_start_failed("The sidecar stopped while starting.")
			elif alive:
				# The sidecar is alive: connect again (it replaces the old link).
				push_warning("Sidecar connection closed (code %d); reconnecting." % code)
				var err := _connect()
				if err != OK:
					_fail("Couldn't connect to the sidecar (error %d)." % err)
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
			_starting = false
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
		"provider.program":
			_set_program(str(msg.get("provider", "")), msg.get("program", {}))
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


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
