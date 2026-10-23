class_name HandShape
extends RefCounted

## A tracked hand's joints (`XRHandTracker.HandJoint` order, all in one space) read as the gesture they make, and made
## from a gesture, so the driver and the tests play a gesture through the same reading a headset's hands go through.
## A gesture is a pinch named by its finger ("index", "middle", "ring", "little"), "fist", or "" for none.

const PALM := 0
const WRIST := 1
const THUMB_TIP := 5
const MIDDLE_KNUCKLE := 12
const TIPS := {"index": 10, "middle": 15, "ring": 20, "little": 25}
const JOINTS := 26
## In hand lengths (wrist to the middle knuckle): a pinch closes inside PINCH and opens past PINCH_OPEN.
const PINCH := 0.2
const PINCH_OPEN := 0.4
## A fist is the middle, ring and little tips all inside FIST of the palm; it opens once one is past FIST_OPEN.
const FIST := 0.5
const FIST_OPEN := 0.65


static func reach(joints: Array) -> float:
	return joints[WRIST].origin.distance_to(joints[MIDDLE_KNUCKLE].origin)


## The gesture `joints` make, `held` being the one they made last.
static func read(joints: Array, held: String) -> String:
	var l := reach(joints)
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


## A hand of 9 cm making `gesture` with its palm at `palm`: fingers ahead (-z), back of the hand up (+y).
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


## A bare hand at `frame` pressing the controller's `input` ("" for none) as `Controls.HAND` has it: that input's
## gesture, or for a stick direction (a `Hand.FLICKS` input) the little pinch, the palm moved `push` of
## `Hand.STICK_REACH` that way, ahead being `facing`'s flat forward.
static func pressing(frame: Transform3D, left: bool, input: String, facing: Basis, push := 1.0) -> Array[Transform3D]:
	if not Hand.FLICKS.has(input):
		var g: Variant = Controls.HAND.find_key(input)
		return make(frame, left, g if g != null else "")
	var right := Vector3(facing.x.x, 0.0, facing.x.z).normalized()
	var way: Vector2 = Hand.FLICKS[input]
	var moved := (right * way.x + Vector3.UP.cross(right) * way.y) * Hand.STICK_REACH * push
	return make(Transform3D(frame.basis, frame.origin + moved), left, "little")
