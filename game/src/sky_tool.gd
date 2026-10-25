class_name SkyTool
extends Node

## Time of day, whatever a hand holds: grip with the hand pointed at open sky, over the mountains, or at the sun or the moon
## wherever they stand, under the ground too, to grab the sky, and it turns round the whole day about the
## sun's arc with the pointer, sun and moon riding on it, until the grip lets go and every player's sky
## turns to it (World's `sky`). Not an edit, so undo leaves it be.

const BEAM := Color(1.0, 0.9, 0.6, 0.6)
## A soft click in the hand every this much of the day turned past.
const TICK := 1.0 / 24.0

var rig: Rig
var look: Look
var world: World
## Whether a hand is in the middle of an edit, which its grip may have started this frame.
var editing: Callable
var holder: Hand
var _start := 0.0
var _turned := 0.0
var _last := 0.0
var _ticked := 0
var _grips: Array[Buttons] = []


func _init(player: Rig, sky: Look, garden: World, busy: Callable) -> void:
	rig = player
	look = sky
	world = garden
	editing = busy
	for h in rig.hands:
		_grips.append(Buttons.new(h).watch(["grab"]))


func _process(_delta: float) -> void:
	for b in _grips:
		var hand: Hand = b.hand
		if holder == hand and (b.released("grab") or not hand.tracked()):
			holder = null
			world.submit({"op": "sky", "time": look.time}, func() -> void: look.set_time(world.time))
		if hand.tracked() and not hand.picking:
			var dir := -hand.global_basis.z
			if holder == hand:
				aim(dir)
				hand.point(null, BEAM)
			elif holder == null and b.pressed("grab") and not hand.taken() and not editing.call(hand) and (Daylight.aims_at_body(dir, look.time) or world.terrain.raycast(hand.global_position, dir) == null and not Mountains.hides(hand.global_position, dir, look.lake())):
				take(hand, dir)
				hand.point(null, BEAM)
		b.latch()


func take(hand: Hand, dir: Vector3) -> void:
	holder = hand
	_start = Daylight.angle(look.time)
	_turned = 0.0
	_last = Daylight.turn_of(dir)
	_ticked = floori(look.time / TICK)
	Cues.play(Cues.Act.SKY_TAKE, hand.global_position, hand)


## Turns the sky by however far `dir` went round the arc's axis since the last aim, so the point grabbed
## stays under the pointer.
func aim(dir: Vector3) -> void:
	var now := Daylight.turn_of(dir)
	_turned += wrapf(now - _last, -PI, PI)
	_last = now
	look.set_time(Daylight.time_at(_start + _turned))
	var tick := floori(look.time / TICK)
	if tick != _ticked:
		Cues.play(Cues.Act.SKY_TURN, holder.global_position, holder)
	_ticked = tick
