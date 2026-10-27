class_name Posture
extends RefCounted

## Which body pose a player is in, read from their three tracked poses over what is under them, and how far each pose
## has blended in. The poses are standing, the body hanging upright below the head, and single frames of people
## lying and sitting recorded by CMU's motion capture (animations/poses.json, converted by scripts/mocap.gd): on the
## back, on either side, on the front, sitting on the ground with the hands forward or leaning back on them, and
## sitting on a ledge with the feet on lower ground.
##
## The inputs, each compared with the same reading of every recorded pose: the eyes' height over the support behind
## them (the ground, a floor or a stair, where the hips would be), how far the support ahead (where the feet would be)
## drops below it while the head is upright, which way is up as the eyes see it (so lying on the back, a side or the
## front, and sitting up, differ), and each hand's place as the eyes see it and its height over that support (hands
## forward, behind or under the head). The nearest pose wins once it has been nearer than the shown one by
## HYSTERESIS for DWELL seconds, and then blends in over BLEND seconds.
##
## Three tracked points do not tell sitting on the ground from crouching or kneeling: the head is low and upright in
## all three, and the legs are not tracked. Standing therefore takes every upright head from STAND_LOW up, whatever the
## hands do, and the recorded poses must be nearer than it by HYSTERESIS for DWELL: a head lowered for a moment to
## work the ground keeps the standing body, as every avatar showed before these poses. A head held low and upright
## sits; a head on its support lies.

const STANDING := 0
## An upright head at least this high over its support stands.
const STAND_LOW := 1.0
## A ledge is a support that drops at least this far ahead of the hips.
const LEDGE := 0.25
## Where the hips and feet are looked for: behind the eyes and ahead of them, along where an upright head faces.
const SEAT_BACK := 0.1
const FEET_AHEAD := 0.45
## A head whose forward leans less than this from level (its horizontal length) is upright.
const UPRIGHT := 0.6
## How far each reading may differ before it counts as much as the others: heights, the ledge's drop, up as the eyes
## see it (standing's head looks up and down at what it builds, so a wider one), hands relative to the eyes, and their
## heights.
const HEIGHT_SPREAD := 0.12
const DROP_SPREAD := 0.12
const UP_SPREAD := 0.35
const STAND_UP_SPREAD := 0.7
const HAND_SPREAD := 0.3
const HAND_HEIGHT_SPREAD := 0.15
const HYSTERESIS := 2.0
const DWELL := 0.4
const BLEND := 0.6
## The tracked poses are read this often, in seconds; DWELL is several readings.
const READ_EVERY := 0.1
## What is under the eyes is probed again once they have moved this far, turned this far from where they faced, or
## this many seconds have passed: a probe asks every build, and a player lying or sitting holds still.
const PROBE_MOVE := 0.2
const PROBE_TURN := deg_to_rad(20.0)
const PROBE_EVERY := 2.0
## How far the eyes may turn from where a lying or sitting pose's eyes look before its body turns after them.
const YAW_SLACK := deg_to_rad(50.0)

## Each pose: {name, turns: humanoid bone -> its turn from the T-pose (absent while standing), eyes, hands, seat}.
static var poses: Array[Dictionary] = _read()
## Each pose's readings, as `reading` gives them for a player.
static var _templates: Array[Array] = []

## How much of each pose shows, summing to one.
var weights := PackedFloat32Array()
## The pose blending in, or shown.
var target := STANDING
## Each lying or sitting pose's heading: where its body faces. A standing body faces where the head does.
var yaws := PackedFloat32Array()
var _candidate := STANDING
var _since := 0.0
var _unread := INF
## The last probe, and the eyes and seconds since it was taken.
var _under := Vector2.ZERO
var _probed := Transform3D()
var _unprobed := INF


func _init() -> void:
	weights.resize(poses.size())
	weights[STANDING] = 1.0
	yaws.resize(poses.size())


static func _read() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"name": "standing", "turns": {}, "seat": 0.0}]
	for p: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://animations/poses.json")):
		var turns := {}
		for b: String in p.bones:
			var q: Array = p.bones[b]
			turns[b] = Quaternion(q[0], q[1], q[2], q[3])
		var e: Array = p.eyes
		var eyes := Transform3D(Basis(Vector3(e[0], e[1], e[2]), Vector3(e[3], e[4], e[5]), Vector3(e[6], e[7], e[8])), Vector3(e[9], e[10], e[11]))
		var hands: Array[Vector3] = []
		for h: Array in p.hands:
			hands.append(Vector3(h[0], h[1], h[2]))
		out.append({"name": p.name, "turns": turns, "eyes": eyes, "hands": hands, "seat": float(p.seat)})
	return out


## The readings of eyes and hands over `support` (a point to the height of what is under it): the eyes' height over
## the support behind them, the drop ahead, up as the eyes see it, and the left then right hand as the eyes see it
## and its height. The lengths are over `size`, the body's eye height over Rig.EYE, the recorded people's: an avatar is
## drawn at its own size, so a short one's player lies, sits and stands lower.
static func reading(eyes: Transform3D, l: Vector3, r: Vector3, support: Callable, size := 1.0) -> Array:
	return reading_over(eyes, l, r, probe(eyes, support, size), size)


## What is under the eyes, as `reading` needs it: the support behind them (where the hips would be) and how far it
## drops ahead (where the feet would be) while the head is upright.
static func probe(eyes: Transform3D, support: Callable, size := 1.0) -> Vector2:
	var forward := -eyes.basis.z
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() <= UPRIGHT:
		return Vector2(support.call(eyes.origin), 0.0)
	flat = flat.normalized()
	var under: float = support.call(eyes.origin - flat * SEAT_BACK * size)
	return Vector2(under, under - support.call(eyes.origin + flat * FEET_AHEAD * size))


## `reading` over a support already probed.
static func reading_over(eyes: Transform3D, l: Vector3, r: Vector3, under: Vector2, size := 1.0) -> Array:
	var to_eyes := eyes.basis.transposed()
	return [(eyes.origin.y - under.x) / size, under.y / size, to_eyes * Vector3.UP, to_eyes * (l - eyes.origin) / size, (l.y - under.x) / size, to_eyes * (r - eyes.origin) / size, (r.y - under.x) / size]


## Recorded pose `k`'s eyes and left and right hands, held by a body whose eyes stand `eye_height` up, on a floor at 0
## (standing: the eyes level, the hands at the sides).
static func held(k: int, eye_height := Rig.EYE) -> Array[Transform3D]:
	if k == STANDING:
		var at := Transform3D(Basis.IDENTITY, Vector3(0, eye_height, 0))
		return [at, at * Avatar.AT_SIDES[0], at * Avatar.AT_SIDES[1]]
	var size := eye_height / Rig.EYE
	var p: Dictionary = poses[k]
	var eyes: Transform3D = p.eyes
	return [Transform3D(eyes.basis, eyes.origin * size), Transform3D(eyes.basis, p.hands[0] * size), Transform3D(eyes.basis, p.hands[1] * size)]


## How far a reading is from pose `k`'s, each difference over its spread, squared and summed; once the height's
## alone reaches `beyond`, that much, since no nearer pose can come of it.
static func distance(k: int, f: Array, beyond := INF) -> float:
	if k == STANDING:
		var low := maxf(0.0, STAND_LOW - f[0]) / HEIGHT_SPREAD
		return low * low + (f[2] - Vector3.UP).length_squared() / (STAND_UP_SPREAD * STAND_UP_SPREAD)
	if _templates.is_empty():
		for p in poses:
			_templates.append([] if p.turns.is_empty() else _template(p))
	var t: Array = _templates[k]
	var h: float = (f[0] - t[0]) / HEIGHT_SPREAD
	if h * h >= beyond:
		return h * h
	var drop: float = (maxf(0.0, LEDGE - f[1]) if t[1] > 0.0 else f[1]) / DROP_SPREAD
	var lh: float = (f[4] - t[4]) / HAND_HEIGHT_SPREAD
	var rh: float = (f[6] - t[6]) / HAND_HEIGHT_SPREAD
	return h * h + drop * drop + lh * lh + rh * rh + (f[2] - t[2]).length_squared() / (UP_SPREAD * UP_SPREAD) \
		+ ((f[3] - t[3]).length_squared() + (f[5] - t[5]).length_squared()) / (HAND_SPREAD * HAND_SPREAD)


## A recorded pose's reading, on a floor at 0; on a ledge its seat is the support behind the eyes, the floor ahead.
static func _template(p: Dictionary) -> Array:
	var seat: float = p.seat
	var f := reading(p.eyes, p.hands[0], p.hands[1], func(_at: Vector3) -> float: return 0.0)
	f[0] -= seat
	f[1] = seat
	f[4] -= seat
	f[6] -= seat
	return f


## The pose nearest a reading, kept while nothing is nearer by HYSTERESIS.
static func nearest(f: Array, shown: int) -> int:
	var best := shown
	var best_d := distance(shown, f) - HYSTERESIS
	for k in poses.size():
		var d := distance(k, f, best_d)
		if d < best_d:
			best = k
			best_d = d
	return best


## Where lying or sitting pose `k`'s body faces for eyes at `eyes`: the heading that best turns its recorded eyes
## onto them.
static func heading(k: int, eyes: Basis) -> float:
	var n := eyes * (poses[k].eyes as Transform3D).basis.transposed()
	return atan2(n.z.x - n.x.z, n.x.x + n.z.z)


## Reads the tracked poses of a body `size` times the recorded people's and moves the blend `delta` seconds on.
func update(eyes: Transform3D, l: Vector3, r: Vector3, support: Callable, delta: float, size := 1.0) -> void:
	_unread += delta
	_unprobed += delta
	if _unread >= READ_EVERY:
		_unread = 0.0
		if _unprobed >= PROBE_EVERY or eyes.origin.distance_to(_probed.origin) > PROBE_MOVE or (-eyes.basis.z).angle_to(-_probed.basis.z) > PROBE_TURN:
			_under = probe(eyes, support, size)
			_probed = eyes
			_unprobed = 0.0
		var near := nearest(reading_over(eyes, l, r, _under, size), target)
		if near != _candidate:
			_candidate = near
			_since = 0.0
	_since += delta
	if _candidate != target and _since >= DWELL:
		target = _candidate
		if target != STANDING and weights[target] == 0.0:
			yaws[target] = heading(target, eyes.basis)
	if weights[target] == 1.0 and target == STANDING:
		return
	var step := delta / BLEND
	var sum := 0.0
	for k in weights.size():
		weights[k] = move_toward(weights[k], 1.0 if k == target else 0.0, step)
		sum += weights[k]
	for k in weights.size():
		weights[k] /= sum
		if k != STANDING and weights[k] > 0.0:
			var off := angle_difference(yaws[k], heading(k, eyes.basis))
			yaws[k] += off - clampf(off, -YAW_SLACK, YAW_SLACK)


## Carries on from another avatar's posture, when a player's avatar is changed.
func take(other: Posture) -> void:
	weights = other.weights.duplicate()
	yaws = other.yaws.duplicate()
	target = other.target
	_candidate = other._candidate
	_since = other._since
	_unread = other._unread
	_under = other._under
	_probed = other._probed
	_unprobed = other._unprobed
