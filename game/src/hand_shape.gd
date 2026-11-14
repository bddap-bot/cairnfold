class_name HandShape
extends RefCounted

## Joints in `XRHandTracker.HandJoint` order, one space; made from gestures too, so the driver and tests share a
## headset's reading. A gesture: a pinch named by its finger (TIPS keys), "fist", or "" for none.

const PALM := 0
const WRIST := 1
const THUMB_TIP := 5
const MIDDLE_KNUCKLE := 12
const TIPS := {"index": 10, "middle": 15, "ring": 20, "little": 25}
const JOINTS := 26
## These four in hand lengths (wrist to middle knuckle); each _OPEN is the release threshold.
const PINCH := 0.2
const PINCH_OPEN := 0.4
const FIST := 0.5
const FIST_OPEN := 0.65
## Per finger, thumb to little: joints from palm to tip, and the summed bend that counts as closed.
const CHAINS := [[2, 3, 4, 5], [6, 7, 8, 9, 10], [11, 12, 13, 14, 15], [16, 17, 18, 19, 20], [21, 22, 23, 24, 25]]
const CLOSED := [PI * 0.5, PI * 1.3, PI * 1.3, PI * 1.3, PI * 1.3]


static func curls(joints: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f in 5:
		var chain: Array = CHAINS[f]
		var bend := 0.0
		for i in range(1, chain.size() - 1):
			var into: Vector3 = joints[chain[i]].origin - joints[chain[i - 1]].origin
			var on: Vector3 = joints[chain[i + 1]].origin - joints[chain[i]].origin
			bend += into.angle_to(on)
		out.append(clampf(bend / CLOSED[f], 0.0, 1.0))
	return out


static func read(joints: Array, held: String) -> String:
	var l: float = joints[WRIST].origin.distance_to(joints[MIDDLE_KNUCKLE].origin)
	if l < 1e-3:
		return ""
	var curl := 0.0
	for f in ["middle", "ring", "little"]:
		curl = maxf(curl, joints[TIPS[f]].origin.distance_to(joints[PALM].origin) / l)
	if curl < (FIST_OPEN if held == "fist" else FIST):
		return "fist"
	if TIPS.has(held) and _gap(joints, held) / l < PINCH_OPEN:
		return held
	var best := ""
	var nearest := PINCH
	for f in TIPS:
		var g := _gap(joints, f) / l
		if g < nearest:
			best = f
			nearest = g
	return best


static func _gap(joints: Array, finger: String) -> float:
	return joints[THUMB_TIP].origin.distance_to(joints[TIPS[finger]].origin)


## In `palm`'s space: fingers -z, back of the hand +y.
static func make(palm: Transform3D, left: bool, gesture: String) -> Array[Transform3D]:
	var at := {
		WRIST: Vector3(0, 0, 0.045), MIDDLE_KNUCKLE: Vector3(0, 0, -0.045), THUMB_TIP: Vector3(-0.075, -0.01, -0.04),
		TIPS.index: Vector3(-0.025, 0, -0.125), TIPS.middle: Vector3(0, 0, -0.135), TIPS.ring: Vector3(0.02, 0, -0.125),
		TIPS.little: Vector3(0.04, 0, -0.105),
	}
	if gesture == "fist":
		for f in TIPS:
			var tip: Vector3 = at[TIPS[f]]
			at[TIPS[f]] = Vector3(tip.x * 0.5, -0.025, -0.01)
		at[THUMB_TIP] = Vector3(-0.02, -0.035, -0.02)
	elif TIPS.has(gesture):
		var meet := Vector3(at[TIPS[gesture]].x * 0.5 - 0.03, -0.035, -0.07)
		at[TIPS[gesture]] = meet
		at[THUMB_TIP] = meet + Vector3(0, 0, 0.005)
	var out: Array[Transform3D] = []
	for j in JOINTS:
		var p: Vector3 = at.get(j, Vector3.ZERO)
		if left:
			p.x = -p.x
		out.append(Transform3D(palm.basis, palm * p))
	return out


## A `Hand.FLICKS` input: the little pinch, palm moved `push` of `Hand.STICK_REACH` that way off `facing`'s flat forward.
static func pressing(frame: Transform3D, left: bool, input: String, facing: Basis, push := 1.0) -> Array[Transform3D]:
	if not Hand.FLICKS.has(input):
		var g: Variant = Controls.HAND.find_key(input)
		return make(frame, left, g if g != null else "")
	var right := Vector3(facing.x.x, 0.0, facing.x.z).normalized()
	var way: Vector2 = Hand.FLICKS[input]
	var moved := (right * way.x + Vector3.UP.cross(right) * way.y) * Hand.STICK_REACH * push
	return make(Transform3D(frame.basis, frame.origin + moved), left, "little")
