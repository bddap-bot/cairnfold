class_name Buttons
extends RefCounted

## Press and release edges of a hand's actions (see `Controls.ACTIONS`), between the samples its `Hand` takes once a
## frame before any reader runs, so every reader sees the same edges whatever order it processes in.

## Inputs the driver injects, keyed "tracker/input", read alongside the controller's own.
static var injected := {}
## Counts the game's returns from a pause. Nothing samples while paused, so a button pressed in the system menu and
## still held would read as pressed on return; each set of edges takes the controls as they are once per return.
static var resumes := 0

var hand: Hand
var _now := {}
var _was := {}
var _resumes := 0


func _init(controller: Hand) -> void:
	hand = controller
	_resumes = resumes
	for a: String in Controls.ACTIONS:
		if Controls.ACTIONS[a].has(hand.tracker):
			_now[a] = false
	_was = _now.duplicate()


func pressed(action: String) -> bool:
	_resumed()
	return _now[action] and not _was[action]


func held(action: String) -> bool:
	return down(hand, Controls.input(action, hand.tracker))


func released(action: String) -> bool:
	_resumed()
	return _was[action] and not _now[action]


func sample() -> void:
	_was = _now.duplicate()
	for a: String in _now:
		_now[a] = held(a)


func _resumed() -> void:
	if _resumes != resumes:
		_resumes = resumes
		sample()
		_was = _now.duplicate()


## Whether `controller`'s `input` is held: a button pressed, or the stick flicked that way.
static func down(controller: Hand, input: String) -> bool:
	if injected.has("%s/%s" % [controller.tracker, input]):
		return true
	if Hand.FLICKS.has(input):
		return controller.flick == input
	if controller.bare:
		return Controls.HAND.get(controller.gesture, "") == input
	return controller.is_button_pressed(input)
