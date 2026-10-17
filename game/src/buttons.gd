class_name Buttons
extends RefCounted

## Press and release edges of a controller's buttons, latched once per frame. A stick pushed one way reads as
## the button named for it ("primary_up" and so on): pressed past PUSH along it, more than across it, and
## held until it comes back inside LET_GO, so one flick is one press.

const STICK := {"primary_up": Vector2(0, 1), "primary_down": Vector2(0, -1), "primary_left": Vector2(-1, 0), "primary_right": Vector2(1, 0)}
const PUSH := 0.7
const LET_GO := 0.3

## Presses the driver injects, keyed "tracker/action", read alongside the controller's own.
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
	if injected.has("%s/%s" % [hand.tracker, action]):
		return true
	if not STICK.has(action):
		return hand.is_button_pressed(action)
	var s := hand.stick()
	var along := s.dot(STICK[action])
	if _was.get(action, false):
		return along > LET_GO
	return along > PUSH and along > absf(s.cross(STICK[action]))
