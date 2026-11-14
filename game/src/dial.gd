class_name Dial
extends Node3D

## Its owner reads its own button and acts on `pick`, the choice at the top.

const RADIUS := 0.07
const GAP := 0.045
## In the controller's frame when the dial opened.
const AT := Vector3(0, 0.06, -0.05)
const STEP := 28.0
const TOP := 1.6

## Set by a continuous puppet, in RADIUS units in the dial plane; INF when unset.
var cursor := Vector2.INF
var start := 0
var pick := 0
var degrees := 0.0
var frame := Basis()
## Seconds open.
var held := 0.0
var choices: Array[Node3D] = []
## Scale of the choices; GAP apart, they fit only at most GAP wide at it.
var size := 1.0


func _init() -> void:
	top_level = true


## Reparents `items` to itself until it is freed or `release`d.
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


func wrist(hand: Node3D) -> float:
	return unwound(degrees, frame, hand.global_basis)


## Nearest `last`, so it turns on past a half turn.
static func unwound(last: float, from: Basis, now: Basis) -> float:
	return last + wrapf(roll(from, now) - last, -180.0, 180.0)


## `by` degrees from where it opened, clockwise positive; true when the top choice changed.
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
		choices[k].position = Vector3(sin(a), cos(a), 0.0) * radius(n) if cursor == Vector2.INF else Vector3(cursor.x, cursor.y, 0.0) * RADIUS
		choices[k].scale = Vector3.ONE * size * (TOP if k == pick else 1.0)


func release() -> Array[Node3D]:
	var out := choices.duplicate()
	for c in out:
		remove_child(c)
	choices.clear()
	queue_free()
	return out


static func radius(count: int) -> float:
	return maxf(RADIUS, count * GAP / TAU)


static func step(count: int) -> float:
	return minf(STEP, 360.0 / count)


static func twisted(count: int, first: int, by: float) -> int:
	return posmod(first + roundi(by / step(count)), count)


## Degrees, clockwise as the hand sees it.
static func roll(from: Basis, now: Basis) -> float:
	var fwd := -from.z
	var x := now.x - fwd * now.x.dot(fwd)
	return rad_to_deg(atan2(fwd.dot(from.x.cross(x)), from.x.dot(x)))
