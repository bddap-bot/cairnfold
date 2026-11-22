class_name WeatherTool
extends Node

## A hand holding the weather shapes it while its trigger is held: the wrist turned clockwise thickens the fog and the
## hand raised lifts it off the ground; in a winter, aimed above the horizon, the turn sets how hard it snows instead.
## Shown on this machine while shaped, sent to every player on release. Not an edit, so undo leaves it be.

const BEAM := Color(0.9, 0.95, 1.0, 0.6)
## Degrees of wrist turn from none to the most.
const FULL_TURN := 180.0
## Metres the hand rises from no fog on the ground to the fog standing highest.
const FULL_RISE := 0.5
## A soft click in the hand each step of this share.
const CLICK := 0.1


class Shaping:
	var snow := false
	var start: Dictionary
	var shown: Dictionary
	var frame: Basis
	var degrees := 0.0
	var y := 0.0
	var clicks := Vector2i.ZERO


var rig: Rig
var look: Look
var world: World
var shaping := {}


func _init(player: Rig, sky: Look, garden: World) -> void:
	rig = player
	look = sky
	world = garden


## `hand` null: any. One hand at a time, so two never shape from stale starts.
func busy(hand: Hand = null) -> bool:
	return shaping.has(hand) if hand != null else not shaping.is_empty()


func _process(_delta: float) -> void:
	for hand in rig.hands:
		var b := hand.buttons
		var s: Shaping = shaping.get(hand)
		if s != null and (hand.tool != Hand.Tool.WEATHER or b.released("tool") or not hand.tracked()):
			close(hand)
		elif s != null:
			shape(hand, Dial.unwound(s.degrees, s.frame, hand.global_basis), hand.global_position.y - s.y)
		elif hand.tool == Hand.Tool.WEATHER and hand.tracked() and not hand.picking and rig.aim_hand != hand:
			hand.point(null, BEAM)
			if b.pressed("tool") and not busy():
				open(hand)


func open(hand: Hand) -> void:
	var s := Shaping.new()
	s.snow = Palette.wintry() and -hand.global_basis.z.y > 0.0
	s.start = world.weather.duplicate()
	s.shown = s.start
	s.frame = hand.global_basis.orthonormalized()
	s.y = hand.global_position.y
	s.clicks = _clicks(s)
	shaping[hand] = s


## `degrees` of wrist turn, clockwise positive, and `rise` metres since the trigger went down.
func shape(hand: Hand, degrees: float, rise: float) -> void:
	var s: Shaping = shaping[hand]
	s.degrees = degrees
	s.shown = shaped(s.start, s.snow, degrees, rise)
	look.show_weather(s.shown)
	var clicks := _clicks(s)
	if clicks != s.clicks:
		Cues.play(Cues.Act.DIAL_TURN, hand.global_position, hand)
	s.clicks = clicks


func close(hand: Hand) -> void:
	var s: Shaping = shaping[hand]
	shaping.erase(hand)
	if s.shown == s.start:
		look.show_weather(world.weather)
		return
	world.submit({"op": "weather"}.merged(s.shown), func() -> void: look.show_weather(world.weather))


static func _clicks(s: Shaping) -> Vector2i:
	return Vector2i(floori((s.shown.snow if s.snow else s.shown.thick) / CLICK), floori(s.shown.high / CLICK))


static func shaped(start: Dictionary, snow: bool, degrees: float, rise: float) -> Dictionary:
	var out := start.duplicate()
	if snow:
		out.snow = clampf(start.snow + degrees / FULL_TURN, 0.0, 1.0)
	else:
		out.thick = clampf(start.thick + degrees / FULL_TURN, 0.0, 1.0)
		out.high = clampf(start.high + rise / FULL_RISE, 0.0, 1.0)
	return out
