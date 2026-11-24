class_name Torso

## Faces what the hands work on, and otherwise turns only once the head is more than TURN from it, so a head turned
## aside looks over its own shoulder.

## In the eyes' frame; the head turns about it.
const NECK := Vector3(0, -0.1, 0.08)
const TURN := deg_to_rad(70.0)
## Metres from a typical person's neck: nearer, level, hands hang or hold something to the chest; farther, no arm
## holds them.
const HELD_OUT := 0.25
const REACH := 1.0
## Outer shoulder tops, left then right, in the torso's frame.
const SHOULDERS: Array[Vector3] = [Vector3(-0.21, -0.13, -0.04), Vector3(0.21, -0.13, -0.04)]


## `yaw` NAN (none yet) faces the head. Both hands held out from the neck, their middle too, turn it to face between
## them, as a body turns to what it works on. `grips` are in the space `eyes` is in; `size` is the body's height over a
## typical person's, which lengths scale by.
static func follow(yaw: float, eyes: Transform3D, grips: Array[Vector3], size: float) -> float:
	var head := eyes.basis.get_euler().y
	var neck := eyes * (NECK * size)
	var toward := yaw if not is_nan(yaw) else head
	var out := (grips[0] + grips[1]) * 0.5 - neck
	var level := func(v: Vector3) -> float: return Vector2(v.x, v.z).length()
	if level.call(out) > HELD_OUT * size and grips.all(func(g: Vector3) -> bool: return level.call(g - neck) > HELD_OUT * size and g.distance_to(neck) < REACH * size):
		toward = atan2(-out.x, -out.z)
	var off := wrapf(head - toward, -PI, PI)
	return toward + off - signf(off) * TURN if absf(off) > TURN else toward


static func frame(eyes: Transform3D, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), eyes * NECK)
