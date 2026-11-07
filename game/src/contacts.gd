class_name Contacts
extends RefCounted

## VRChat's contacts (https://creators.vrchat.com/common-components/contacts/): senders are tagged spheres and capsules
## on bodies, and each receiver writes its parameter from the senders whose tags it lists that touch it: "constant" 1
## while one does, "onEnter" 1 for the frame one arrives at least `minVelocity` fast, "proximity" from 0 at its edge
## to 1 at its centre. Every humanoid body carries the senders VRChat gives every avatar (BODY), so the wearer's
## hands and every other player touch what an avatar's receivers reach for, whatever avatar they wear.

const RECEIVERS := ["constant", "onEnter", "proximity"]
## The senders VRChat makes on every humanoid avatar, by the name of the descriptor collider each comes from: [tags,
## the humanoid bones it may sit on, first found, the bones its capsule may run to or none for a sphere, radius as a
## fraction of the eyes' height, as VRChat's automatic colliders size a typical avatar]. A VRChat avatar's file carries
## its own ("body" contacts); these stand in on any other.
const BODY := {
	"head": [["Head"], ["head"], [], 0.05],
	"torso": [["Torso"], ["chest", "spine"], ["upperChest", "neck"], 0.075],
	"handL": [["Hand", "HandL"], ["leftHand"], ["leftMiddleProximal"], 0.014],
	"handR": [["Hand", "HandR"], ["rightHand"], ["rightMiddleProximal"], 0.014],
	"footL": [["Foot", "FootL"], ["leftToes", "leftFoot"], [], 0.05],
	"footR": [["Foot", "FootR"], ["rightToes", "rightFoot"], [], 0.05],
	"fingerIndexL": [["Finger", "FingerL", "FingerIndex", "FingerIndexL"], ["leftIndexIntermediate"], ["leftIndexDistal"], 0.0065],
	"fingerIndexR": [["Finger", "FingerR", "FingerIndex", "FingerIndexR"], ["rightIndexIntermediate"], ["rightIndexDistal"], 0.0065],
	"fingerMiddleL": [["Finger", "FingerL", "FingerMiddle", "FingerMiddleL"], ["leftMiddleIntermediate"], ["leftMiddleDistal"], 0.0065],
	"fingerMiddleR": [["Finger", "FingerR", "FingerMiddle", "FingerMiddleR"], ["rightMiddleIntermediate"], ["rightMiddleDistal"], 0.0065],
	"fingerRingL": [["Finger", "FingerL", "FingerRing", "FingerRingL"], ["leftRingIntermediate"], ["leftRingDistal"], 0.0065],
	"fingerRingR": [["Finger", "FingerR", "FingerRing", "FingerRingR"], ["rightRingIntermediate"], ["rightRingDistal"], 0.0065],
	"fingerLittleL": [["Finger", "FingerL", "FingerLittle", "FingerLittleL"], ["leftLittleIntermediate"], ["leftLittleDistal"], 0.0065],
	"fingerLittleR": [["Finger", "FingerR", "FingerLittle", "FingerLittleR"], ["rightLittleIntermediate"], ["rightLittleDistal"], 0.0065],
}
## The scene group of the players' bodies, each giving `contact_senders()`: Array of [from, to, radius, tags (a Dictionary
## of them), body, a key naming the sender from frame to frame] in world space.
const BODIES := &"contact_bodies"

var _receivers: Array[Dictionary] = []
var _senders: Array[Dictionary] = []
var _touching: Array[Dictionary] = []
## Each sender's world origin a frame ago, by its key, while a receiver is "onEnter".
var _last := {}
## Whether the file gives the body's own senders, which stand in for BODY.
var carries_body := false
var _entering := false
static var _gathered := []
static var _gathered_frame := -1


## The contacts of an avatar's expressions, each placed on the bone `bone.call(node name)` answers as [skeleton, bone
## index]; one whose bone the model lacks is left out.
func _init(contacts: Array, bone: Callable) -> void:
	for c: Dictionary in contacts:
		var at: Array = bone.call(c.node)
		if at.is_empty():
			continue
		var shape: Dictionary = c.shape
		var entry := {"at": at, "from": _vector(shape.offset), "to": _vector(shape.get("tail", shape.offset)), "radius": float(shape.radius), "tags": _tagged(c.tags), "when": c.when}
		if c.has("receiver"):
			entry.merge(c.receiver)
			_entering = _entering or c.receiver.type == "onEnter"
			_receivers.append(entry)
			_touching.append({})
		else:
			entry.key = _senders.size()
			_senders.append(entry)
			carries_body = carries_body or c.get("body", false)


func receives() -> bool:
	return not _receivers.is_empty()


## This avatar's own senders that `outputs` switch on, in world space, as BODIES members give them.
func senders(outputs: Array[float], owner: Object) -> Array:
	var out := []
	for s: Dictionary in _senders:
		if ExpressionPlayer.shows(outputs, s.when):
			out.append(_placed(s) + [s.tags, owner, [owner.get_instance_id(), s.key]])
	return out


## Every sender of every body in `tree` this frame.
static func gather(tree: SceneTree) -> Array:
	var frame := Engine.get_process_frames()
	if frame != _gathered_frame:
		_gathered_frame = frame
		_gathered = []
		for b: Node in tree.get_nodes_in_group(BODIES):
			_gathered.append_array(b.contact_senders())
	return _gathered


## Writes each receiver's parameter into `state` from the `senders` (gather) touching it, `owner` being its own body;
## `local` whether the avatar is its wearer's own, where alone a local-only receiver runs; `delta` the time since the last.
func sense(state: ExpressionState, senders: Array, owner: Object, local: bool, delta: float) -> void:
	for i in _receivers.size():
		var r: Dictionary = _receivers[i]
		var now := {}
		var value := 0.0
		if ExpressionPlayer.shows(state.outputs, r.when) and (local or not r.local):
			var placed := _placed(r)
			var middle: Vector3 = (placed[0] + placed[1]) * 0.5
			var reach: float = placed[2] + placed[0].distance_to(placed[1]) * 0.5
			for s: Array in senders:
				if (s[4] == owner and not r.self) or (s[4] != owner and not r.others):
					continue
				if middle.distance_to((s[0] + s[1]) * 0.5) > reach + s[2] + s[0].distance_to(s[1]) * 0.5 or not _shares(r.tags, s[3]):
					continue
				var closest := Geometry3D.get_closest_points_between_segments(placed[0], placed[1], s[0], s[1])
				var gap: float = closest[0].distance_to(closest[1]) - s[2]
				if gap > placed[2]:
					continue
				now[s[5]] = true
				match r.type:
					"constant": value = 1.0
					"proximity": value = maxf(value, 1.0 - maxf(gap, 0.0) / placed[2] if placed[2] > 0.0 else 1.0)
					_:
						var was: Variant = _last.get(s[5])
						if not _touching[i].has(s[5]) and (was == null or delta <= 0.0 or (s[0] as Vector3).distance_to(was) / delta >= float(r.minVelocity)):
							value = 1.0
		_touching[i] = now
		state.put(r.parameter, value)
	if _entering:
		_last.clear()
		for s: Array in senders:
			_last[s[5]] = s[0]


## A humanoid body's VRChat senders (BODY) in world space: `joint.call(bone)` gives a humanoid bone's world origin, or
## null where the body has none; `height` its eyes' height.
static func body_senders(joint: Callable, height: float, owner: Object) -> Array:
	var out := []
	for key: String in BODY:
		var b: Array = BODY[key]
		var from: Variant = _first(joint, b[1])
		if from == null:
			continue
		var to: Variant = _first(joint, b[2])
		out.append([from, to if to != null else from, b[3] * height, _TAGS[key], owner, [owner.get_instance_id(), key]])
	return out


static var _TAGS := _body_tags()


static func _body_tags() -> Dictionary:
	var out := {}
	for key: String in BODY:
		out[key] = _tagged(BODY[key][0])
	return out


static func _first(joint: Callable, bones: Array) -> Variant:
	for b: String in bones:
		var at: Variant = joint.call(b)
		if at != null:
			return at
	return null


func _placed(c: Dictionary) -> Array:
	var sk: Skeleton3D = c.at[0]
	var t := sk.global_transform * sk.get_bone_global_pose(c.at[1])
	return [t * (c.from as Vector3), t * (c.to as Vector3), float(c.radius) * t.basis.get_scale().x]


static func _shares(a: Dictionary, b: Dictionary) -> bool:
	for tag: String in a:
		if b.has(tag):
			return true
	return false


static func _tagged(tags: Array) -> Dictionary:
	var out := {}
	for t: Variant in tags:
		out[str(t)] = true
	return out


static func _vector(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])
