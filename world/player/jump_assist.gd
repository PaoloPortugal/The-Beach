class_name JumpAssist
extends RefCounted
## Coyote time and jump buffering (W03). A jump still counts if it's
## pressed shortly before landing (buffer) or shortly after walking off an
## edge (coyote time). Call step() once per physics frame.

var coyote_time := 0.12
var buffer_time := 0.12

var _since_floor := INF
var _since_press := INF


## Returns true when the player should jump this frame.
func step(delta: float, on_floor: bool, pressed: bool) -> bool:
	_since_floor = 0.0 if on_floor else _since_floor + delta
	_since_press = 0.0 if pressed else _since_press + delta
	if _since_press <= buffer_time and _since_floor <= coyote_time:
		# Used up: no second jump from the same press or the same ledge.
		_since_press = INF
		_since_floor = INF
		return true
	return false
