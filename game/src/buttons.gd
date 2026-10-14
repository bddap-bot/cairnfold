class_name Buttons
extends RefCounted

## Press and release edges of a controller's buttons, latched once per frame.

## Presses the driver injects, keyed "tracker/action", read alongside the controller's own.
static var injected := {}

var hand: XRController3D
var _was := {}


func _init(controller: XRController3D) -> void:
	hand = controller


func pressed(action: String) -> bool:
	return _down(action) and not _was.get(action, false)


func held(action: String) -> bool:
	return _down(action)


func released(action: String) -> bool:
	return not _down(action) and _was.get(action, false)


func latch() -> void:
	for a in _was.keys():
		_was[a] = _down(a)


func watch(actions: Array) -> Buttons:
	for a in actions:
		_was[a] = false
	return self


func _down(action: String) -> bool:
	return hand.is_button_pressed(action) or injected.has("%s/%s" % [hand.tracker, action])
