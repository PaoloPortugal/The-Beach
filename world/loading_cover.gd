class_name LoadingCover
extends CanvasLayer
## Covers the world while the game starts (S07; user's decision,
## 2026-10-13): the sidecar first looks for sessions still running from
## before a restart, which takes about a second, and the world shows once
## it has (the client's first [signal SidecarClient.synced]), so their
## islands are standing from the first frame instead of popping in. Lifted
## then, when the sidecar fails, or after [constant TIMEOUT_S] whatever
## happens. The player's controls and every key and click wait under it.
## A PLACEHOLDER, like all UI. Unused since C14: the game opens on the
## main menu over the world instead; kept in case it's wanted again
## (user's, 2026-10-26).

## Past the client's own handshake timeout, plus the sync: never stuck.
const TIMEOUT_S := SidecarClient.HANDSHAKE_TIMEOUT_S + 10.0

signal lifted

var _player: Player
var _controls_before := true
var _covered := false


func _init() -> void:
	layer = 20 # above everything, the quit dialog included
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.12, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var label := Label.new()
	label.name = "Text"
	label.text = "Loading…"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bg.add_child(label)
	visible = false


## Covers the world until [param sidecar] has synced, failed or timed out.
## A sidecar already synced, failed or not started lifts it at once.
func setup(sidecar: SidecarClient, player: Player) -> void:
	_player = player
	if sidecar.status in [SidecarClient.Status.READY, SidecarClient.Status.FAILED, SidecarClient.Status.STOPPED]:
		lift()
		return
	_covered = true
	visible = true
	_controls_before = player.controls_enabled
	player.controls_enabled = false
	sidecar.synced.connect(func(_providers: Array) -> void: lift(), CONNECT_ONE_SHOT)
	sidecar.failed.connect(func(_reason: String) -> void: lift(), CONNECT_ONE_SHOT)
	get_tree().create_timer(TIMEOUT_S).timeout.connect(lift)


func is_covering() -> bool:
	return _covered


## Shows the world and gives the controls back. Once only.
func lift() -> void:
	if not _covered:
		visible = false
		return
	_covered = false
	visible = false
	if is_instance_valid(_player):
		_player.controls_enabled = _controls_before
	lifted.emit()


func _input(_event: InputEvent) -> void:
	if _covered:
		get_viewport().set_input_as_handled()
