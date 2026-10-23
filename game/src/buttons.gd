class_name Buttons
extends RefCounted

## Press and release edges of a hand's actions (see `Controls.ACTIONS`), latched once per frame.

## Inputs the driver injects, keyed "tracker/input", read alongside the controller's own.
static var injected := {}

var hand: Hand
var _was := {}


func _init(controller: Hand) -> void:
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
	return down(hand, Controls.input(action, hand.tracker))


## Whether `controller`'s `input` is held: a button pressed, or the stick flicked that way.
static func down(controller: Hand, input: String) -> bool:
	if injected.has("%s/%s" % [controller.tracker, input]):
		return true
	if Hand.FLICKS.has(input):
		return controller.flick == input
	if controller.bare:
		return Controls.HAND.get(controller.gesture, "") == input
	return controller.is_button_pressed(input)
