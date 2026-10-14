class_name Buttons
extends RefCounted

## Press and release edges of a controller's buttons, latched once per frame.

var hand: XRController3D
var _was := {}


func _init(controller: XRController3D) -> void:
	hand = controller


func pressed(action: String) -> bool:
	return hand.is_button_pressed(action) and not _was.get(action, false)


func held(action: String) -> bool:
	return hand.is_button_pressed(action)


func released(action: String) -> bool:
	return not hand.is_button_pressed(action) and _was.get(action, false)


func latch() -> void:
	for a in _was.keys():
		_was[a] = hand.is_button_pressed(a)


func watch(actions: Array) -> Buttons:
	for a in actions:
		_was[a] = false
	return self
