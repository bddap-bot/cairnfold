class_name SkyTool
extends Node

## Turns the time of day, whatever a hand holds; every player's sky follows on release. Not an edit, so undo leaves it be.

const BEAM := Color(1.0, 0.9, 0.6, 0.6)
## Of a day.
const TICK := 1.0 / 24.0

var rig: Rig
var look: Look
var world: World
## Whether `hand` is mid-edit, which its grip may have started this frame.
var editing: Callable
var holder: Hand
## Time wraps round the day, so a pointer crossing the arc's seam need not be unwound.
var _offset := 0.0
var _ticked := 0


func _init(player: Rig, sky: Look, garden: World, busy: Callable) -> void:
	rig = player
	look = sky
	world = garden
	editing = busy


func _process(_delta: float) -> void:
	for hand in rig.hands:
		var b := hand.buttons
		if holder == hand and (b.released("grab") or not hand.tracked()):
			holder = null
			world.submit({"op": "sky", "time": look.time}, func() -> void: look.set_time(world.time))
		if hand.tracked() and not hand.picking:
			var dir := -hand.global_basis.z
			if holder == hand:
				aim(dir)
			elif holder == null and b.pressed("grab") and not hand.taken() and not editing.call(hand) and opens(hand.global_position, dir):
				take(hand, dir)
			if holder == hand:
				hand.point(null, BEAM)


func opens(from: Vector3, dir: Vector3) -> bool:
	return Daylight.aims_at_body(dir, look.time) or world.terrain.raycast(from, dir) == null and not Mountains.hides(from, dir)


func take(hand: Hand, dir: Vector3) -> void:
	holder = hand
	_offset = Daylight.angle(look.time) - Daylight.turn_of(dir)
	_ticked = floori(look.time / TICK)
	Cues.play(Cues.Act.SKY_TAKE, hand.global_position, hand)


func aim(dir: Vector3) -> void:
	look.set_time(Daylight.time_at(_offset + Daylight.turn_of(dir)))
	var tick := floori(look.time / TICK)
	if tick != _ticked:
		Cues.play(Cues.Act.SKY_TURN, holder.global_position, holder)
	_ticked = tick
