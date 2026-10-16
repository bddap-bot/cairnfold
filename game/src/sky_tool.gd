class_name SkyTool
extends Node

## Time of day, whatever a hand holds: grip with the hand pointed at open sky to grab the sky, and it turns
## about the sun's arc with the pointer, the sun riding on it, until the grip lets go. Not an edit, so undo
## leaves it be.

const BEAM := Color(1.0, 0.9, 0.6, 0.6)
## A soft click in the hand every this much of the day turned past.
const TICK := 1.0 / 24.0

var rig: Rig
var look: Look
## Whether a hand is in the middle of an edit, which its grip may have started this frame.
var editing: Callable
var holder: Hand
var _start := 0.0
var _turned := 0.0
var _last := 0.0
var _ticked := 0
var _grips: Array[Buttons] = []


func _init(player: Rig, sky: Look, busy: Callable) -> void:
	rig = player
	look = sky
	editing = busy
	for h in rig.hands:
		_grips.append(Buttons.new(h).watch(["grip_click"]))


func _process(_delta: float) -> void:
	for b in _grips:
		var hand: Hand = b.hand
		if holder == hand and (b.released("grip_click") or not hand.tracked()):
			holder = null
		if hand.tracked() and not hand.picking:
			var dir := -hand.global_basis.z
			if holder == hand:
				aim(dir)
				hand.point(null, BEAM, 30.0)
			elif holder == null and b.pressed("grip_click") and not hand.taken() and not editing.call(hand) and Terrain.raycast(hand.global_position, dir) == null:
				take(hand, dir)
				hand.point(null, BEAM, 30.0)
		b.latch()


func take(hand: Hand, dir: Vector3) -> void:
	holder = hand
	_start = Daylight.angle(look.time)
	_turned = 0.0
	_last = Daylight.turn_of(dir)
	_ticked = floori(look.time / TICK)


## Turns the sky by however far `dir` went round the arc's axis since the last aim, so the point grabbed
## stays under the pointer; past dawn or dusk the sky waits for the pointer to come back.
func aim(dir: Vector3) -> void:
	var now := Daylight.turn_of(dir)
	_turned += wrapf(now - _last, -PI, PI)
	_last = now
	look.set_time(inverse_lerp(Daylight.DAWN, Daylight.DUSK, _start + _turned))
	var tick := floori(look.time / TICK)
	if tick != _ticked:
		holder.trigger_haptic_pulse(&"haptic", 0.0, 0.2, 0.02, 0.0)
	_ticked = tick
