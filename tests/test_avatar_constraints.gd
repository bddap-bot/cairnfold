extends "res://../tests/support/suite.gd"

const RIGHT_ANGLE := Basis(Vector3.UP, PI / 2)

var _seen := {}
var _hips := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_malformed()
	var model := _fixture()
	Vrm.write(model, "user://constraints.vrm")
	model.free()
	var scene := Avatar.read(FileAccess.get_file_as_bytes("user://constraints.vrm"), true)
	check(scene != null, "the constrained fixture survives a VRM export and import")
	if scene == null:
		finish()
		return
	var avatar := Avatar.open(scene, Color.WHITE)
	avatar.transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.5), Vector3(3, 0.2, -2))
	root.add_child(avatar)
	var skeleton := avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	check(Constraints.of(skeleton) != null and Constraints.of(skeleton).constraints.size() == 3, "every constraint the file names solves on the skeleton")
	skeleton.skeleton_updated.connect(func() -> void:
		for bone: String in [_hips, "anchor", "prop", "follower", "pointer"]:
			_seen[bone] = skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone)))
	await frames(3)
	var hips: Transform3D = _seen[_hips]
	var anchor: Transform3D = _seen.anchor
	var held := hips * Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.2, 0))
	check(_near(_seen.prop, held), "a parent constraint saved at weight 0 holds its bone at its rest: %s, expected %s" % [_seen.prop, held])
	avatar.expressions.state.put("Hold", 1)
	await frames(3)
	var gripped := anchor * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.1))
	check(_near(_seen.prop, gripped), "the clip a toggle plays engages it, and its bone follows its source by the source's offset: %s, expected %s" % [_seen.prop, gripped])
	avatar.expressions.state.put("Hold", 0)
	await frames(3)
	check(_near(_seen.prop, held), "toggled off, it rests again")
	var world := Vector3(0.4, 1.1, -0.2)
	var target := (anchor.origin + world * 3.0) / 4.0 + Vector3(0.05, 0, 0)
	var placed := hips.origin.lerp(target, 0.5)
	var follower: Transform3D = _seen.follower
	var local := hips.affine_inverse() * placed
	check(is_equal_approx((hips.affine_inverse() * follower.origin).x, local.x) and is_equal_approx((hips.affine_inverse() * follower.origin).z, local.z), "a position constraint at half weight moves its bone halfway to its sources' weighted place and its offset: %s, expected %s" % [follower.origin, placed])
	check(is_equal_approx((hips.affine_inverse() * follower.origin).y, 0.0), "and leaves an axis it does not affect where the pose holds it")
	check(follower.basis.get_rotation_quaternion().is_equal_approx(hips.basis.get_rotation_quaternion()), "and never turns it")
	var pointer: Transform3D = _seen.pointer
	check(pointer.origin.is_equal_approx(hips * Vector3(0, 0.5, 0)), "a look-at constraint leaves its bone where it stands")
	check(pointer.basis.z.normalized().is_equal_approx((anchor.origin - pointer.origin).normalized()), "and turns its forward toward its source: %s, expected %s" % [pointer.basis.z.normalized(), (anchor.origin - pointer.origin).normalized()])
	check(is_zero_approx(pointer.basis.x.normalized().y), "keeping its side level under the world's up")
	avatar.free()
	finish()


## Cairnfold's built-in avatar with three props on its hips: one a toggle hands to an anchor, one following a weighted
## anchor and world point on two axes, one looking at the anchor.
func _fixture() -> Node3D:
	var model := Avatar.built_in(0).instantiate() as Node3D
	var bones: Dictionary = model.get_meta("humanoid")
	var skeleton := model.get_node(str(bones.hips).get_slice(":", 0)) as Skeleton3D
	var hips := skeleton.find_bone((bones.hips as NodePath).get_concatenated_subnames())
	_hips = skeleton.get_bone_name(hips)
	for bone: Array in [["anchor", Transform3D(RIGHT_ANGLE, Vector3(0.4, 0.1, 0))], ["prop", Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))], ["follower", Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.2))], ["pointer", Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))]]:
		skeleton.add_bone(bone[0])
		skeleton.set_bone_parent(skeleton.find_bone(bone[0]), hips)
		skeleton.set_bone_rest(skeleton.find_bone(bone[0]), bone[1])
	skeleton.reset_bone_poses()
	var identity := _matrix(Transform3D.IDENTITY)
	var every := [true, true, true]
	model.set_meta("constraints", [
		{"kind": "Parent", "node": "prop", "weight": 0.0, "translation": every, "rotation": every, "rest": _matrix(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.2, 0))), "offset": identity,
			"sources": [{"node": "anchor", "weight": 1.0, "offset": _matrix(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.1)))}]},
		{"kind": "Position", "node": "follower", "weight": 0.5, "translation": [true, false, true], "rotation": every, "rest": identity, "offset": _matrix(Transform3D(Basis.IDENTITY, Vector3(0.05, 0, 0))),
			"sources": [{"node": "anchor", "weight": 1.0, "offset": identity}, {"world": _matrix(Transform3D(Basis.IDENTITY, Vector3(0.4, 1.1, -0.2))), "weight": 3.0, "offset": identity}]},
		{"kind": "LookAt", "node": "pointer", "weight": 1.0, "translation": every, "rotation": every, "rest": identity, "offset": identity,
			"sources": [{"node": "anchor", "weight": 1.0, "offset": identity}]}])
	model.set_meta("expressions", {"parameters": [{"name": "Hold", "type": "bool", "default": 0.0, "saved": true}],
		"menu": [{"name": "Hold", "type": "toggle", "parameter": "Hold", "value": 1.0}], "icons": [], "shown": [],
		"targets": [{"effect": {"constraint": {"node": "prop"}}, "default": 0.0}],
		"clips": [{"length": 1.0, "curves": [{"target": 0, "step": false, "keys": [[0, 0]]}]}, {"length": 1.0, "curves": [{"target": 0, "step": false, "keys": [[0, 1]]}]}],
		"layers": [{"weight": 1.0, "default": 0, "states": [
			{"motion": {"clip": 0}, "transitions": [{"to": 1, "conditions": [{"parameter": "Hold", "mode": "if"}]}]},
			{"motion": {"clip": 1}, "transitions": [{"to": 0, "conditions": [{"parameter": "Hold", "mode": "ifNot"}]}]}]}]})
	return model


func _malformed() -> void:
	var node := GLTFNode.new()
	node.resource_name = "prop"
	var nodes: Array[GLTFNode] = [node]
	var identity := _matrix(Transform3D.IDENTITY)
	var good := {"kind": "Parent", "node": 0.0, "weight": 1.0, "translation": [true, true, true], "rotation": [true, true, true], "rest": identity, "offset": identity, "sources": [{"world": identity, "weight": 1.0, "offset": identity}]}
	check(Constraints.read({"constraints": [good]}, nodes).size() == 1, "a well-formed constraint reads, its node named")
	for bad: Dictionary in [{"kind": "Aim"}, {"node": 1.0}, {"weight": 2.0}, {"rotation": [true, true]}, {"rest": identity.slice(1)}, {"offset": identity.map(func(_x: float) -> float: return 0.0)}, {"sources": [{"node": 4.0, "weight": 1.0, "offset": identity}]}, {"sources": [{"weight": 1.0, "offset": identity}]}, {"sources": [{"world": identity, "weight": -1.0, "offset": identity}]}]:
		check(Constraints.read({"constraints": [good, good.merged(bad, true)]}, nodes).is_empty(), "a file with a malformed constraint keeps none: %s" % [bad])


static func _matrix(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, 0.0, t.basis.y.x, t.basis.y.y, t.basis.y.z, 0.0, t.basis.z.x, t.basis.z.y, t.basis.z.z, 0.0, t.origin.x, t.origin.y, t.origin.z, 1.0]


static func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 1e-4 and a.basis.orthonormalized().is_equal_approx(b.basis.orthonormalized())
