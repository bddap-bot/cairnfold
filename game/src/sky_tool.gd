class_name SkyTool
extends Node

## Turns the time of day, whatever a hand holds; every player's sky follows on release. Let go while turning, the sky
## runs on the same way by itself. Not an edit, so undo leaves it be.

const BEAM := Color(1.0, 0.9, 0.6, 0.6)
## Of a day.
const TICK := 1.0 / 24.0
## Degrees a second: let go turning it slower, the sky stands, so a hand's tremor or the jolt of opening the grip
## sets nothing running.
const STILL := 15.0
## Degrees a second: let go turning it this fast or faster, the sky runs FASTEST; between, the pace grows with the square
## of the turn past STILL, so slow days are as easy to choose as fast ones.
const FLUNG := 180.0
## Of a day a second.
const FASTEST := 1.0 / 60.0
## Seconds over which the turn at release is measured.
const WINDOW := 0.15

var rig: Rig
var look: Look
var world: World
## Whether `hand` is mid-edit, which its grip may have started this frame.
var editing: Callable
var holder: Hand
## Time wraps round the day, so a pointer crossing the arc's seam need not be unwound.
var _offset := 0.0
var _ticked := 0
## Radians turned since the take, unwound, by the clock: (seconds, radians) a frame, the last WINDOW of them.
var _turns: Array[Vector2] = []
var _turned := 0.0
var _clock := 0.0
## While the sky a hand let go is on its way to the garden, the garden's own clock would show the old sky.
var _sending := false


func _init(player: Rig, sky: Look, garden: World, busy: Callable) -> void:
	rig = player
	look = sky
	world = garden
	editing = busy


func _process(delta: float) -> void:
	_clock += delta
	for hand in rig.hands:
		var b := hand.buttons
		if holder == hand and (b.released("grab") or not hand.tracked()):
			holder = null
			_sending = true
			world.submit({"op": "sky", "time": look.time, "pace": pace_of(turning())}, func() -> void:
				_sending = false
				look.set_time(world.time))
		if hand.tracked() and not hand.picking:
			var dir := -hand.global_basis.z
			if holder == hand:
				aim(dir)
				_turns.append(Vector2(_clock, _turned))
				while _turns[0].x < _clock - WINDOW:
					_turns.pop_front()
			elif holder == null and b.pressed("grab") and not hand.taken() and not editing.call(hand) and opens(hand.global_position, dir):
				take(hand, dir)
			if holder == hand:
				hand.point(null, BEAM)
	if holder == null and not _sending:
		world.run_sky(delta)


func opens(from: Vector3, dir: Vector3) -> bool:
	return Daylight.aims_at_body(dir, look.time) or world.terrain.raycast(from, dir) == null and not Mountains.hides(from, dir)


func take(hand: Hand, dir: Vector3) -> void:
	holder = hand
	_offset = Daylight.angle(look.time) - Daylight.turn_of(dir)
	_ticked = floori(look.time / TICK)
	_turned = 0.0
	_turns.clear()
	Cues.play(Cues.Act.SKY_TAKE, hand.global_position, hand)


func aim(dir: Vector3) -> void:
	var was := Daylight.angle(look.time)
	look.set_time(Daylight.time_at(_offset + Daylight.turn_of(dir)))
	_turned += wrapf(Daylight.angle(look.time) - was, -PI, PI)
	var tick := floori(look.time / TICK)
	if tick != _ticked:
		Cues.play(Cues.Act.SKY_TURN, holder.global_position, holder)
	_ticked = tick


## Radians a second.
func turning() -> float:
	if _turns.size() < 2 or _turns[-1].x <= _turns[0].x:
		return 0.0
	return (_turns[-1].y - _turns[0].y) / (_turns[-1].x - _turns[0].x)


## Of a day a second, the sky let go turning `rate` radians a second runs on at.
static func pace_of(rate: float) -> float:
	var past := clampf((absf(rad_to_deg(rate)) - STILL) / (FLUNG - STILL), 0.0, 1.0)
	return signf(rate) * FASTEST * past * past


## Radians a second to turn the sky, let go, to run it at `pace`.
static func rate_for(pace: float) -> float:
	if pace == 0.0:
		return 0.0
	return signf(pace) * deg_to_rad(STILL + sqrt(minf(absf(pace) / FASTEST, 1.0)) * (FLUNG - STILL))
