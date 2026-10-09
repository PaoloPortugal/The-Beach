class_name SessionLauncher
extends Node
## Starts new sessions (S03) and resumes stored ones (S04) through the
## sidecar, one at a time, and says how it's going. A session only counts
## once it's up (the user may first have to confirm in its terminal), and
## only then does the world make its island (see SessionIslands).

## The session we asked for is up; its island exists by now.
signal session_started(session_id: String)
## What to tell the player about starting changed ("" when nothing).
signal status_changed(text: String)

## After this long, "Starting" becomes "Still starting; check the terminal".
const STILL_STARTING_S := 120.0

## Our own text for the start notices we know; others show the sidecar's.
const NOTICE_TEXT := {
	"confirm_in_terminal": "Confirm in the terminal to start this session.",
}

var store: SessionStore
var sidecar: SidecarClient
## Told which cluster a started session should join (W05).
var clusters: SessionClusters
## Told which biome a started session's island should be (W10).
var islands: SessionIslands
## The session being started, or "".
var pending := ""
## What [signal status_changed] last said.
var status := ""

## A start was sent and its reply hasn't come yet.
var _asking := false
var _asked_at := 0.0
var _still_said := false


## Call once. Connect SessionIslands to the store before this, so a new
## session's island exists by the time [signal session_started] fires.
func setup(p_store: SessionStore, p_sidecar: SidecarClient) -> void:
	store = p_store
	sidecar = p_sidecar
	store.session_added.connect(func(id: String, _created: bool) -> void:
		if id == pending:
			pending = ""
			_say("")
			session_started.emit(id))
	# A session that never comes up ends before the store ever sees it.
	sidecar.event_received.connect(func(msg: Dictionary) -> void:
		if msg["type"] == "session.ended" and msg["session"] == pending:
			pending = ""
			_say("The session didn't start."))
	sidecar.failed.connect(func(reason: String) -> void: _say(reason))


## Whether a start is under way.
func busy() -> bool:
	return _asking or not pending.is_empty()


## Stops waiting for the session being started, so another can start
## (S03). If it does come up later, it's just a running session: its
## island rises, and nobody is taken there.
func stop_waiting() -> void:
	if pending.is_empty():
		return
	pending = ""
	_say("Stopped waiting. If that session starts later, it's listed under Running.")


## Asks for a new session in the folder [param path], to join
## [param cluster] (a [SessionClusters] choice), on an island of
## [param biome] (a [enum Biome.Kind] or [constant Biome.RANDOM]).
func create(path: String, cluster := SessionClusters.AUTOMATIC, biome := Biome.RANDOM) -> void:
	if sidecar.providers.is_empty():
		_say("Not connected to the sidecar yet.")
		return
	# Only one provider exists for now; choosing one is for S03 proper.
	var provider: String = sidecar.providers[0]["provider"]
	_start("session.create", {"provider": provider, "project": {"path": path}}, "Couldn't start a session: %s", cluster, biome)


## Asks to resume the stored session [param native_id] of [param provider],
## to join [param cluster], on an island of [param biome].
func resume(provider: String, native_id: String, cluster := SessionClusters.AUTOMATIC, biome := Biome.RANDOM) -> void:
	_start("session.resume", {"provider": provider, "native_id": native_id}, "Couldn't resume the session: %s", cluster, biome)


func _start(command: String, fields: Dictionary, refused: String, cluster: String, biome: int) -> void:
	if busy():
		_say("A session is already starting.")
		return
	var id := sidecar.send_command(command, fields, func(reply: Dictionary) -> void:
		_asking = false
		if reply.get("type") == "error":
			_say(refused % reply.get("message", ""))
			return
		var result: Dictionary = reply.get("result", {})
		pending = result.get("session", "")
		if clusters != null and not pending.is_empty():
			clusters.choose(pending, cluster)
		if islands != null and not pending.is_empty():
			islands.choose_biome(pending, biome)
		_asked_at = Time.get_ticks_msec() / 1000.0
		_still_said = false
		var notice: Dictionary = result.get("notice", {})
		if not notice.is_empty():
			_say(NOTICE_TEXT.get(notice["code"], notice["message"])))
	_asking = not id.is_empty()
	_say("Starting…" if _asking else "Not connected to the sidecar.")


func _process(_delta: float) -> void:
	if not pending.is_empty() and not _still_said and Time.get_ticks_msec() / 1000.0 - _asked_at > STILL_STARTING_S:
		_still_said = true
		_say("Still starting; check the terminal, or stop waiting in the menu (Tab).")


func _say(text: String) -> void:
	status = text
	status_changed.emit(text)
