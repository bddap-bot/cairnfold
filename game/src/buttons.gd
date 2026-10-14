class_name Buttons
extends RefCounted

## Press and release edges of a controller's buttons, latched once per frame.

const HOLD_MSEC := 500

## Presses the driver injects, keyed "tracker/action", read alongside the controller's own.
static var injected := {}

var hand: XRController3D
var _was := {}
var _down_at := {}


func _init(controller: XRController3D) -> void:
	hand = controller


func pressed(action: String) -> bool:
	return _down(action) and not _was.get(action, false)


func held(action: String) -> bool:
	return _down(action)


func released(action: String) -> bool:
	return not _down(action) and _was.get(action, false)


## True once per press, when the button has been held for HOLD_MSEC.
func held_long(action: String) -> bool:
	var t: int = _down_at.get(action, -1)
	if t < 0 or not _down(action) or Time.get_ticks_msec() - t < HOLD_MSEC:
		return false
	_down_at[action] = -1
	return true


func latch() -> void:
	for a in _was.keys():
		var down := _down(a)
		if down and not _was[a]:
			_down_at[a] = Time.get_ticks_msec()
		elif not down:
			_down_at.erase(a)
		_was[a] = down


func watch(actions: Array) -> Buttons:
	for a in actions:
		_was[a] = false
	return self


func _down(action: String) -> bool:
	return hand.is_button_pressed(action) or injected.has("%s/%s" % [hand.tracker, action])
