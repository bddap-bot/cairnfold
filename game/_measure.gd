extends SceneTree
func _initialize() -> void:
	await process_frame
	for k in [Beast.Kind.DEER, Beast.Kind.FOX]:
		var b := Beast.new(k, 1.0, 0.0)
		root.add_child(b)
		await process_frame
		var mi: MeshInstance3D = b.find_children("*", "MeshInstance3D", true, false)[0]
		var sk: Skeleton3D = b.find_children("*", "Skeleton3D", true, false)[0]
		var sz := (sk.global_transform * sk.get_bone_global_rest(sk.find_bone("FrontShoulder.L")).origin).z
		var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var top := 0.0
		for v in verts:
			var w := mi.global_transform * v
			if absf(w.z - sz) < 0.03 * aabb.size.z and w.y > top: top = w.y
		print(Beast.Kind.keys()[k], " len=", aabb.size.z, " ears=", aabb.size.y, " withers=", top)
	quit()
