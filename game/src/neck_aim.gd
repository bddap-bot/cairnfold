class_name NeckAim
extends SkeletonModifier3D

## Applied after the clip; only the neck and head rotate, never the torso or limbs.
const BONES := ["Neck1", "Neck2", "Neck3", "Head"]
const LIMITS := [1.05, 0.95, 0.95, 0.9]
const CLEARANCE := 0.03
const CONTACT := 0.035
const BLEND := 5.0
const PASSES := 32

var offer: Node3D
var muzzle := Vector3.ZERO
var chain: Array[int] = []
var reach := 0.0
var rest_base := Vector3.ZERO
var amount := 0.0
var error := INF
var mouth := Vector3.ZERO
var _last_target := Vector3.ZERO
var _solved: Array[Quaternion] = []


func configure(skeleton: Skeleton3D, tip: Vector3) -> void:
	muzzle = tip
	for bone in BONES:
		chain.append(skeleton.find_bone(bone))
	assert(not chain.has(-1))
	for i in range(1, chain.size()):
		reach += skeleton.get_bone_rest(chain[i]).origin.length()
	reach += muzzle.length()
	rest_base = skeleton.get_bone_global_rest(chain[0]).origin
	skeleton.add_child(self)


static func food(h: Node3D) -> Vector3:
	var seen: Node3D = h.body if h is Hand else h
	return seen.global_transform * (Hand.TOP + Vector3(0, 0.0155, 0))


static func target(h: Node3D) -> Vector3:
	var seen: Node3D = h.body if h is Hand else h
	return seen.global_transform * (Hand.TOP + Vector3(0, CLEARANCE, 0))


## Keep some bend in the neck, reserving reach for a hand drifting while it eats.
func stand_off(animal: Node3D, h: Node3D) -> float:
	var s := get_skeleton()
	var base := animal.to_local(s.to_global(rest_base))
	var length := reach * s.global_basis.get_scale().x
	var height := target(h).y - (animal.global_position.y + base.y)
	var forward := sqrt(maxf(0.0, pow(length * 0.80, 2) - height * height))
	return Vector2(base.x, base.z).length() + forward


func reachable(animal: Node3D, h: Node3D, ground: float) -> bool:
	var s := get_skeleton()
	var base := animal.to_local(s.to_global(rest_base))
	var seen: Node3D = h.body if h is Hand else h
	return seen.global_basis.y.normalized().dot(Vector3.UP) > 0.35 and absf(target(h).y - ground - base.y) < reach * s.global_basis.get_scale().x * 0.85


func touching(h: Node3D) -> bool:
	var seen: Node3D = h.body if h is Hand else h
	return amount > 0.99 and mouth.distance_to(target(h)) < CONTACT and seen.to_local(mouth).y > Hand.TOP.y + 0.015


func _process_modification() -> void:
	var s := get_skeleton()
	var wanted := is_instance_valid(offer) and offer.is_inside_tree()
	if wanted:
		var next := target(offer)
		if next.distance_to(_last_target) > 0.1:
			_solved.clear()
		_last_target = next
	amount = move_toward(amount, 1.0 if wanted else 0.0, get_process_delta_time() * BLEND)
	error = INF
	if amount == 0.0:
		return
	var goal := s.to_local(_last_target)
	var original: Array[Quaternion] = []
	for bone in chain:
		original.append(s.get_bone_pose_rotation(bone))
		s.set_bone_pose_rotation(bone, _solved[original.size() - 1] if not _solved.is_empty() else s.get_bone_rest(bone).basis.get_rotation_quaternion())
	for step in PASSES:
		if s.to_global(s.get_bone_global_pose(chain[-1]) * muzzle).distance_to(_last_target) < 0.001:
			break
		for i in range(chain.size() - 1, -1, -1):
			var bone := chain[i]
			var pose := s.get_bone_global_pose(bone)
			var tip := s.get_bone_global_pose(chain[-1]) * muzzle
			var from := tip - pose.origin
			var to := goal - pose.origin
			if from.length_squared() < 1e-12 or to.length_squared() < 1e-12:
				continue
			var turn := Quaternion(from.normalized(), to.normalized())
			var parent := s.get_bone_global_pose(s.get_bone_parent(bone)).basis.get_rotation_quaternion()
			var rotation := parent.inverse() * turn * pose.basis.get_rotation_quaternion()
			var rest := s.get_bone_rest(bone).basis.get_rotation_quaternion()
			var angle := rest.angle_to(rotation)
			if angle > LIMITS[i]:
				rotation = rest.slerp(rotation, LIMITS[i] / angle)
			s.set_bone_pose_rotation(bone, rotation.normalized())
	_solved.clear()
	for i in chain.size():
		var bone := chain[i]
		_solved.append(s.get_bone_pose_rotation(bone))
		s.set_bone_pose_rotation(bone, original[i].slerp(s.get_bone_pose_rotation(bone), amount))
	mouth = s.to_global(s.get_bone_global_pose(chain[-1]) * muzzle)
	error = mouth.distance_to(_last_target)
