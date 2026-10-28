class_name Dial
extends Node3D

## A wheel of choices over a controller, turned by twisting the wrist like a dial: it stands in the hand's frame from
## when it opened and follows the hand without turning with it, the choice at the top standing larger. Its owner reads
## its own button and does what the choice at the top means: the style and colour tools' wheels (PaletteTool), the
## avatars to wear and the gardens to join (Hand, SessionWheel).

const RADIUS := 0.07
## A dial of many choices widens so neighbours stay this far apart around it.
const GAP := 0.045
## Where the dial stands from the controller, in its frame when it opened.
const AT := Vector3(0, 0.06, -0.05)
const STEP := 28.0
const TOP := 1.6

var start := 0
var pick := 0
var degrees := 0.0
var frame := Basis()
## Seconds it has been open.
var held := 0.0
var choices: Array[Node3D] = []
## How large its choices stand; GAP apart, they fit it at most that wide.
var size := 1.0


func _init() -> void:
	top_level = true


## Opens over `hand` on `first` of `items`, which it holds as its children until it is freed or `release`d.
func open(hand: Node3D, items: Array[Node3D], first: int) -> void:
	start = first
	pick = first
	frame = hand.global_basis.orthonormalized()
	for c in items:
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
		add_child(c)
		c.visible = true
		choices.append(c)
	follow(hand)


func _process(delta: float) -> void:
	held += delta


## The wrist's twist about the hand's pointing axis since the dial opened, unwound from the last twist so it turns on
## past a half turn.
func wrist(hand: Node3D) -> float:
	return degrees + wrapf(roll(frame, hand.global_basis) - degrees, -180.0, 180.0)


## Turns to `by` degrees of twist from where it opened, clockwise positive; whether the choice at the top changed.
func twist(hand: Node3D, by: float) -> bool:
	degrees = by
	var now := twisted(choices.size(), start, by)
	if now == pick:
		return false
	pick = now
	Cues.play(Cues.Act.DIAL_TURN, hand.global_position, hand as XRController3D)
	return true


func follow(hand: Node3D) -> void:
	global_transform = Transform3D(frame, hand.global_position + frame * AT)
	var n := choices.size()
	for k in n:
		var a := (degrees / step(n) - (k - start)) * TAU / n
		choices[k].position = Vector3(sin(a), cos(a), 0.0) * radius(n)
		choices[k].scale = Vector3.ONE * size * (TOP if k == pick else 1.0)


## Gives back its choices, its children no more, and frees itself.
func release() -> Array[Node3D]:
	var out := choices.duplicate()
	for c in out:
		remove_child(c)
	choices.clear()
	queue_free()
	return out


static func radius(count: int) -> float:
	return maxf(RADIUS, count * GAP / TAU)


## The twist from one of `count` choices to the next: STEP, or finer where a half turn either way would not reach them
## all.
static func step(count: int) -> float:
	return minf(STEP, 360.0 / count)


static func twisted(count: int, first: int, by: float) -> int:
	return posmod(first + roundi(by / step(count)), count)


## Degrees the hand has turned about its pointing axis since `from`, clockwise as the hand sees it.
static func roll(from: Basis, now: Basis) -> float:
	var fwd := -from.z
	var x := now.x - fwd * now.x.dot(fwd)
	return rad_to_deg(atan2(fwd.dot(from.x.cross(x)), from.x.dot(x)))
