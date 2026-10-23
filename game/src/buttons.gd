class_name Buttons
extends RefCounted

## Press and release edges of a hand's actions (see `Controls.ACTIONS`), latched once per frame.

## Inputs the driver injects, keyed "tracker/input", read alongside the controller's own.
static var injected := {}
## Counts the game's returns from a pause. Nothing latches while paused, so a button pressed in the system menu and
## still held would read as pressed on return; each set of edges takes the controls as they are once per return.
static var resumes := 0

var hand: Hand
var _was := {}
var _resumes := 0


func _init(controller: Hand) -> void:
	hand = controller
	_resumes = resumes


func pressed(action: String) -> bool:
	_resumed()
	return _down(action) and not _was.get(action, false)


func held(action: String) -> bool:
	return _down(action)


func released(action: String) -> bool:
	_resumed()
	return not _down(action) and _was.get(action, false)


func latch() -> void:
	_resumes = resumes
	for a in _was.keys():
		_was[a] = _down(a)


func _resumed() -> void:
	if _resumes != resumes:
		latch()


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
