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
	var input := Controls.input(action, hand.tracker)
	if injected.has("%s/%s" % [hand.tracker, input]):
		return true
	return hand.flick == input if Hand.FLICKS.has(input) else hand.is_button_pressed(input)
