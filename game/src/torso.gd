class_name Torso

## Turns only once the head is more than TURN from it, so a head turned aside looks over its own shoulder.

## In the eyes' frame; the head turns about it.
const NECK := Vector3(0, -0.1, 0.08)
const TURN := deg_to_rad(70.0)
## Outer shoulder tops, left then right, in the torso's frame.
const SHOULDERS: Array[Vector3] = [Vector3(-0.21, -0.13, -0.04), Vector3(0.21, -0.13, -0.04)]


## `yaw` NAN (none yet) faces the head.
static func follow(yaw: float, eyes: Basis) -> float:
	var head := eyes.get_euler().y
	if is_nan(yaw):
		return head
	var off := wrapf(head - yaw, -PI, PI)
	return yaw + off - signf(off) * TURN if absf(off) > TURN else yaw


static func frame(eyes: Transform3D, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), eyes * NECK)
