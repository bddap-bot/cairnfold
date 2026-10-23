class_name Torso

## The body under a head: it hangs from the neck, upright, and turns only once the head has turned further from it
## than a neck turns, so a head turned aside looks over its own shoulder.

## The neck, in the eyes' frame: below the eyes and behind them, where the head turns about.
const NECK := Vector3(0, -0.1, 0.08)
const TURN := deg_to_rad(70.0)
## The top of each shoulder at its outer edge, left then right, in the torso's frame.
const SHOULDERS: Array[Vector3] = [Vector3(-0.21, -0.13, -0.04), Vector3(0.21, -0.13, -0.04)]


## The torso's turn about up after the eyes' basis `eyes`, from `yaw` (NAN for none yet, which faces the head).
static func follow(yaw: float, eyes: Basis) -> float:
	var head := eyes.get_euler().y
	if is_nan(yaw):
		return head
	var off := wrapf(head - yaw, -PI, PI)
	return yaw + off - signf(off) * TURN if absf(off) > TURN else yaw


## The torso's frame, at the neck under `eyes`, turned `yaw`.
static func frame(eyes: Transform3D, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), eyes * NECK)
