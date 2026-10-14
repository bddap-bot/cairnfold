extends SceneTree

## Headless checks of the VRM avatars: godot4 --headless --path game --script ../tests/test_avatar.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path in Avatar.BUILT_IN:
		_built_in_reads_as_humanoid(path)
	_pose_puts_the_eyes_on_the_head()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _built_in_reads_as_humanoid(path: String) -> void:
	var a := Avatar.open(path, Color.RED)
	_check(a.head != null and a.left != null and a.right != null and a.hips != null, "%s has head, hands and hips" % path)
	_check(a.head.name == "head" and a.left.name == "leftHand" and a.hips.name == "hips", "%s names its bones as VRM does" % path)
	var tinted := 0
	var wrong := 0
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var own: Material = mi.mesh.surface_get_material(i)
			var shown: Variant = mi.get_surface_override_material(i)
			var should := own.resource_name.begins_with("tint")
			if should and shown is StandardMaterial3D and shown.albedo_color == Color.RED:
				tinted += 1
			elif should or shown != null:
				wrong += 1
	_check(tinted > 0 and wrong == 0, "%s takes the player's colour on its tint surfaces only (%d, %d wrong)" % [path, tinted, wrong])
	_check((a.get_child(0).get_meta("eyes") as Vector3).is_equal_approx(Vector3(0, 0.12, 0.09)), "%s carries its eye offset in the file" % path)
	a.free()


func _pose_puts_the_eyes_on_the_head() -> void:
	var a := Avatar.open(Avatar.BUILT_IN[0], Color.WHITE)
	root.add_child(a)
	var eyes := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1.7, -2))
	var l := Transform3D(Basis.IDENTITY, Vector3(2.7, 1.2, -2.3))
	var r := Transform3D(Basis.IDENTITY, Vector3(3.3, 1.2, -2.3))
	a.pose(eyes, l, r)
	var model: Node3D = a.get_child(0)
	var seen: Vector3 = a.head.global_transform * (model.get_meta("eyes") as Vector3)
	_check(seen.distance_to(eyes.origin) < 0.001, "eyes sit at the tracked head (%s vs %s)" % [seen, eyes.origin])
	var face: Vector3 = a.head.global_basis.z
	var look := -eyes.basis.z
	_check(face.dot(look) > 0.99, "the face looks where the head looks")
	_check(a.left.global_position.distance_to(l.origin) < 0.001 and a.right.global_position.distance_to(r.origin) < 0.001, "hands follow the controllers")
	_check(a.hips.global_position.y < eyes.origin.y - 0.5, "the body hangs below the head")
	_check(a.left.global_basis.is_equal_approx(l.basis * Avatar.FACING), "the mitten turns with its controller")
	var tilted := Transform3D(Basis.from_euler(Vector3(0.5, 1.1, 0.3)), Vector3(1, 1.6, 1))
	a.pose(tilted, l, r)
	_check(a.hips.global_basis.y.is_equal_approx(Vector3.UP), "the body stays upright when the head tips")
	var ahead := a.hips.global_basis.z
	_check(Vector2(ahead.x, ahead.z).normalized().is_equal_approx(Vector2(-sin(1.1), -cos(1.1))), "and faces where the head turns")
	a.free()
