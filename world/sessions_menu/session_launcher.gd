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
	"confirm_in_terminal": "Confirm in the terminal to start this session.", # TRANSLATE
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
## What it says, untranslated: the English text and its placeholders'
## values, said again in a new language.
var _said := ["", {}]

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
			_say("The session didn't start.")) # TRANSLATE
	sidecar.failed.connect(func(reason: String) -> void: _say("{reason}", {"reason": reason}))


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
	_say("Stopped waiting. If that session starts later, it joins the sessions ring.") # TRANSLATE


## Asks for a new session in the folder [param path], to join
## [param cluster] (a [SessionClusters] choice), on an island of
## [param biome] (a [enum Biome.Kind] or [constant Biome.RANDOM]), started
## with [param launch]: the model, effort and mode picked (C12), ids from
## the provider's [code]launch_options[/code]; one left out is Default.
func create(path: String, cluster := SessionClusters.AUTOMATIC, biome := Biome.RANDOM, launch := {}) -> void:
	if sidecar.providers.is_empty():
		_say("Not connected to the sidecar yet.") # TRANSLATE
		return
	var provider: String = new_session_provider().get("provider", "")
	_start("session.create", _with_launch({"provider": provider, "project": {"path": path}}, launch), "Couldn't start a session: {reason}", cluster, biome) # TRANSLATE


## The provider a new session uses: the first that can start one (S02:
## not one whose program wasn't found), else the first. Choosing one is
## for S03 proper. Empty with no sidecar.
func new_session_provider() -> Dictionary:
	var startable := sidecar.startable_providers()
	if not startable.is_empty():
		return startable[0]
	return sidecar.providers[0] if not sidecar.providers.is_empty() else {}


## Asks to resume the stored session [param native_id] of [param provider],
## to join [param cluster], on an island of [param biome], with
## [param launch] as for [method create].
func resume(provider: String, native_id: String, cluster := SessionClusters.AUTOMATIC, biome := Biome.RANDOM, launch := {}) -> void:
	_start("session.resume", _with_launch({"provider": provider, "native_id": native_id}, launch), "Couldn't resume the session: {reason}", cluster, biome) # TRANSLATE


# Adds the launch choices, if any were made: none is Default throughout.
static func _with_launch(fields: Dictionary, launch: Dictionary) -> Dictionary:
	if not launch.is_empty():
		fields["launch"] = launch
	return fields


func _start(command: String, fields: Dictionary, refused: String, cluster: String, biome: int) -> void:
	if busy():
		_say("A session is already starting.") # TRANSLATE
		return
	var id := sidecar.send_command(command, fields, func(reply: Dictionary) -> void:
		_asking = false
		if reply.get("type") == "error":
			var by := sidecar.provider(str(fields.get("provider", "")))
			# Worded when said, so again in a new language (SidecarText).
			_say(refused, {"reason": func() -> String: return SidecarText.error(reply, by)})
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
			if NOTICE_TEXT.has(notice["code"]):
				_say(NOTICE_TEXT[notice["code"]])
			else: # the sidecar's English, or ours for its code
				var by := sidecar.provider(str(fields.get("provider", "")))
				_say("{reason}", {"reason": func() -> String: return SidecarText.notice(notice, by)}))
	_asking = not id.is_empty()
	_say("Starting…" if _asking else "Not connected to the sidecar.") # TRANSLATE


func _process(_delta: float) -> void:
	if not pending.is_empty() and not _still_said and Time.get_ticks_msec() / 1000.0 - _asked_at > STILL_STARTING_S:
		_still_said = true
		_say("Still starting; check the terminal, or stop waiting in the sessions menu (hold Tab, click +).") # TRANSLATE


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not status.is_empty():
		_say(_said[0], _said[1])


# Says [param text] (English, "" for nothing) translated, its
# placeholders filled from [param values]. A value may be a Callable,
# called each time it's said (so text worded from the sidecar's reasons
# follows the language too).
func _say(text: String, values := {}) -> void:
	_said = [text, values]
	var shown := {}
	for k: String in values:
		shown[k] = values[k].call() if values[k] is Callable else values[k]
	status = Languages.fill(tr(text), shown) if not text.is_empty() else ""
	status_changed.emit(status)
