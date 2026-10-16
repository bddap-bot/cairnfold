class_name SunTool
extends Node

## Time of day, whatever a hand holds: point at the sun and it swells, grip to take it, and the sun follows
## the hand along its arc across the sky until the grip lets go. Not an edit, so undo leaves it be.

## How near the sun, in degrees, a pointing hand takes it.
const REACH := 7.0
const BEAM := Color(1.0, 0.9, 0.6, 0.6)
## Under the horizon the sun is taken where it went down, so a hand can bring back a sun it cannot see.
const LOWEST_HANDLE := deg_to_rad(2.0)
## A soft click in the hand every this much of the day dragged past.
const TICK := 1.0 / 24.0
const HANDLE_REACH := 1.2

var rig: Rig
var look: Look
## Whether a hand is in the middle of an edit, which its grip may have started this frame.
var editing: Callable
var holder: Hand
var _offset := 0.0
var _hand_start := Vector3.ZERO
var _direction := Vector3.ZERO
var _ticked := 0
var _grips: Array[Buttons] = []
var _lit := false


func _init(player: Rig, sky: Look, busy: Callable) -> void:
	rig = player
	look = sky
	editing = busy
	for h in rig.hands:
		_grips.append(Buttons.new(h).watch(["grip_click"]))


func _process(_delta: float) -> void:
	var hover := false
	for b in _grips:
		var hand: Hand = b.hand
		if holder == hand and (b.released("grip_click") or not hand.get_has_tracking_data()):
			let_go()
		if hand.get_has_tracking_data() and not hand.picking:
			var dir := -hand.global_basis.z
			if holder == hand:
				drag(Daylight.time_toward(_direction + (hand.global_position - _hand_start) / HANDLE_REACH) + _offset)
			elif holder == null and aims_at_sun(dir):
				hover = true
				if b.pressed("grip_click") and not editing.call(hand):
					take(hand, dir)
			if holder == hand or (holder == null and aims_at_sun(dir)):
				hand.point(null, BEAM, 30.0)
		if holder == hand:
			hand.hold()
		b.latch()
	var lit := hover or holder != null
	if lit != _lit:
		_lit = lit
		look.swell(lit)


func aims_at_sun(dir: Vector3) -> bool:
	var sun := Daylight.toward_sun(look.time)
	var flat := Vector3(sun.x, 0.0, sun.z).normalized()
	var handle := sun if sun.y >= sin(LOWEST_HANDLE) else flat * cos(LOWEST_HANDLE) + Vector3.UP * sin(LOWEST_HANDLE)
	return dir.angle_to(handle) < deg_to_rad(REACH)


func take(hand: Hand, dir: Vector3) -> void:
	holder = hand
	hand.holds_sun = true
	_hand_start = hand.global_position
	_direction = dir
	_offset = look.time - Daylight.time_toward(dir)
	_ticked = floori(look.time / TICK)


func let_go() -> void:
	holder.holds_sun = false
	holder = null


func drag(time: float) -> void:
	look.set_time(time)
	var tick := floori(look.time / TICK)
	if tick != _ticked and holder != null:
		holder.trigger_haptic_pulse(&"haptic", 0.0, 0.2, 0.02, 0.0)
	_ticked = tick
