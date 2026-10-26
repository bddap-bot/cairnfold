extends SceneTree

## Writes the built-in avatars (game/avatars/*.vrm): run from game/ as
## godot4 --headless --path . --script ../scripts/avatars.gd
## Each is a VRM 1.0 humanoid in T-pose facing +Z with a floating head, mittens and a small smock, skinned as any VRM
## body is; surfaces whose material name starts with "tint" take the player's colour. Its eyes look by bone: both eye
## bones sit behind the face, so a turned eye slides over it.

const STONE := Color(0.78, 0.74, 0.66)
const DARK := Color(0.12, 0.1, 0.09)
const BARK := Color(0.42, 0.29, 0.17)
## A look this many degrees off ahead turns the eyes their full range.
const LOOK_REACH := 30.0


func _init() -> void:
	for a in [_pebble(), _acorn(), _hood()]:
		_tassel(a)
		var body := _skinned(a)
		a.free()
		Vrm.write(body, "res://avatars/%s.vrm" % body.name)
		print("avatars: ", body.name)
		body.free()
	quit()


func _pebble() -> Node3D:
	var root := _skeleton("pebble")
	var head: Node3D = root.find_child("head", true, false)
	_part(head, Meshes.rounded_box(0.45, 3, 11), _tint(), Vector3(0, 0.12, 0), Vector3(0.24, 0.22, 0.22))
	_eyes(root, DARK, 0.12, Vector3(0, 0.12, -0.05), Vector2(12, 8))
	_mittens(root, _tint())
	_smock(root, _mat(STONE))
	return root


func _acorn() -> Node3D:
	var root := _skeleton("acorn")
	var head: Node3D = root.find_child("head", true, false)
	_part(head, _sphere(0.11, 10, 6), _mat(STONE), Vector3(0, 0.11, 0), Vector3(1, 1.1, 1))
	var cap := _sphere(0.125, 10, 6, true)
	_part(head, cap, _tint(), Vector3(0, 0.14, 0), Vector3(1, 0.7, 1))
	_part(head, _cylinder(0.012, 0.02, 0.05, 5), _mat(BARK), Vector3(0, 0.25, 0), Vector3.ONE)
	_eyes(root, DARK, 0.1, Vector3(0, 0.11, 0), Vector2(20, 15))
	_mittens(root, _mat(STONE))
	_smock(root, _tint())
	return root


func _hood() -> Node3D:
	var root := _skeleton("hood")
	var head: Node3D = root.find_child("head", true, false)
	_part(head, _cylinder(0.0, 0.15, 0.36, 10), _tint(), Vector3(0, 0.2, -0.02), Vector3(1, 1, 0.95))
	_part(head, _sphere(0.1, 10, 6), _mat(DARK), Vector3(0, 0.1, 0.04), Vector3(1, 0.9, 0.8))
	_eyes(root, Color(0.98, 0.9, 0.6), 0.1, Vector3(0, 0.1, -0.03), Vector2(12, 8))
	_mittens(root, _tint())
	_smock(root, _tint())
	return root


## A figure built of bone nodes and the parts they carry, as one skeleton of those bones and a skinned mesh of one
## surface per material, each vertex weighed wholly to the bone its part hangs from. Parts on spring joints make a
## mesh of their own, bound to those joints alone, which the wearer sees (Rig.wear).
func _skinned(figure: Node3D) -> Node3D:
	var out := Node3D.new()
	out.name = figure.name
	for key in figure.get_meta_list():
		out.set_meta(key, figure.get_meta(key))
	var skeleton := Skeleton3D.new()
	skeleton.name = "skeleton"
	out.add_child(skeleton)
	var swaying := {}
	for chain: Dictionary in figure.get_meta("springs").springs:
		for joint: Dictionary in chain.joints:
			swaying[joint.node] = true
	var meshes := [{"binds": {}, "surfaces": {}}, {"binds": {}, "surfaces": {}}]
	_add_bones(figure, skeleton, -1, Transform3D.IDENTITY, swaying, meshes)
	skeleton.reset_bone_poses()
	# Every bone is a joint of the body's skin, so that a glTF reader makes each one a bone of the skeleton.
	for bone in skeleton.get_bone_count():
		meshes[0].binds.get_or_add(bone, meshes[0].binds.size())
	for k in meshes.size():
		var m: Dictionary = meshes[k]
		if m.surfaces.is_empty():
			continue
		var mesh := ArrayMesh.new()
		for key: Array in m.surfaces:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surfaces[key][1])
			mesh.surface_set_material(mesh.get_surface_count() - 1, m.surfaces[key][0])
		var skin := Skin.new()
		for bone: int in m.binds:
			skin.add_named_bind(skeleton.get_bone_name(bone), skeleton.get_bone_global_rest(bone).affine_inverse())
		var mi := MeshInstance3D.new()
		mi.name = ["body", "sway"][k]
		mi.mesh = mesh
		mi.skin = skin
		skeleton.add_child(mi)
		mi.skeleton = mi.get_path_to(skeleton)
	return out


func _add_bones(node: Node3D, skeleton: Skeleton3D, parent: int, at: Transform3D, swaying: Dictionary, meshes: Array) -> void:
	for c: Node3D in node.get_children():
		if c is MeshInstance3D:
			var m: Dictionary = meshes[1 if swaying.has(skeleton.get_bone_name(parent)) else 0]
			var bind: int = m.binds.get_or_add(parent, m.binds.size())
			var mat: StandardMaterial3D = (c as MeshInstance3D).mesh.surface_get_material(0)
			var surface: Array = m.surfaces.get_or_add([mat.resource_name, mat.albedo_color], [mat, []])
			var part := _placed((c as MeshInstance3D).mesh.surface_get_arrays(0), at * c.transform, bind)
			if surface[1].is_empty():
				surface[1] = part
			else:
				Meshes.join(surface[1], part)
			continue
		var bone := skeleton.add_bone(c.name)
		skeleton.set_bone_parent(bone, parent)
		skeleton.set_bone_rest(bone, c.transform)
		_add_bones(c, skeleton, bone, at * c.transform, swaying, meshes)


## A part's arrays placed by `at` in the skeleton's frame, every vertex weighed wholly to bind `bind`.
func _placed(arrays: Array, at: Transform3D, bind: int) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var vertex := PackedVector3Array()
	var normal := PackedVector3Array()
	var turn := at.basis.inverse().transposed()
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		vertex.append(at * v)
	for n: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
		normal.append((turn * n).normalized())
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in vertex.size():
		bones.append_array([bind, 0, 0, 0])
		weights.append_array([1.0, 0.0, 0.0, 0.0])
	out[Mesh.ARRAY_VERTEX] = vertex
	out[Mesh.ARRAY_NORMAL] = normal
	out[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertex.size()))
	out[Mesh.ARRAY_BONES] = bones
	out[Mesh.ARRAY_WEIGHTS] = weights
	return out


## The VRM bone hierarchy in T-pose, eyes 1.65 m up.
func _skeleton(name: String) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.set_meta("eyes", Vector3(0, 0.12, 0.09))
	var hips := _bone(root, "hips", Vector3(0, 0.95, 0))
	var spine := _bone(hips, "spine", Vector3(0, 0.2, 0))
	_bone(spine, "head", Vector3(0, 0.38, 0))
	for side in [["left", 1.0], ["right", -1.0]]:
		var upper := _bone(spine, side[0] + "UpperArm", Vector3(0.18 * side[1], 0.25, 0))
		var lower := _bone(upper, side[0] + "LowerArm", Vector3(0.27 * side[1], 0, 0))
		_bone(lower, side[0] + "Hand", Vector3(0.25 * side[1], 0, 0))
		var thigh := _bone(hips, side[0] + "UpperLeg", Vector3(0.1 * side[1], -0.05, 0))
		var shin := _bone(thigh, side[0] + "LowerLeg", Vector3(0, -0.42, 0))
		_bone(shin, side[0] + "Foot", Vector3(0, -0.4, 0))
	return root


func _bone(parent: Node3D, name: String, at: Vector3) -> Node3D:
	var b := Node3D.new()
	b.name = name
	b.position = at
	parent.add_child(b)
	return b


## Both eyes turn about `middle`, at most `turn` degrees across and up or down, which keeps them on the face.
func _eyes(root: Node3D, colour: Color, height: float, middle: Vector3, turn: Vector2) -> void:
	var across := Vector2(LOOK_REACH, turn.x)
	var upward := Vector2(LOOK_REACH, turn.y)
	root.set_meta("look", {"type": Vrm.BONE, "ranges": [across, across, upward, upward]})
	var head: Node3D = root.find_child("head", true, false)
	for side in [["leftEye", 0.045], ["rightEye", -0.045]]:
		var eye := _bone(head, side[0], middle)
		_part(eye, _sphere(0.018, 6, 4), _mat(colour), Vector3(side[1], height, 0.1) - middle, Vector3(1, 1.3, 0.9))


## Mittens lie along the arms, palms down, as VRM's T-pose holds hands.
func _mittens(root: Node3D, mat: Material) -> void:
	for side in [["leftHand", 1.0], ["rightHand", -1.0]]:
		var hand: Node3D = root.find_child(side[0], true, false)
		_part(hand, Meshes.rounded_box(0.45, 2, 5), mat, Vector3(-0.03 * side[1], -0.01, 0), Vector3(0.11, 0.05, 0.07))


func _smock(root: Node3D, mat: Material) -> void:
	_part(root.find_child("spine", true, false), _cylinder(0.11, 0.2, 0.5, 10), mat, Vector3(0, -0.02, 0), Vector3(1, 1, 0.8))


func _part(bone: Node3D, mesh: Mesh, mat: Material, at: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "%s_%d" % [bone.name, bone.get_child_count()]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	am.surface_set_material(0, mat)
	mi.mesh = am
	mi.position = at
	mi.scale = size
	bone.add_child(mi)


func _sphere(r: float, segs: int, rings: int, half := false) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = rings
	m.is_hemisphere = half
	return m


func _cylinder(top: float, bottom: float, h: float, segs: int) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return m


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _tint() -> StandardMaterial3D:
	var m := _mat(Color(0.8, 0.5, 0.35))
	m.resource_name = "tint"
	return m


func _tassel(root: Node3D) -> void:
	var head: Node3D = root.find_child("head", true, false)
	var parent := head
	var joints := []
	for i in 3:
		var name := "tassel%d" % i
		parent = _bone(parent, name, Vector3(0.1, 0.12, -0.04) if i == 0 else Vector3(0, -0.09, 0))
		_part(parent, _cylinder(0.012, 0.016, 0.09, 5), _tint(), Vector3(0, -0.045, 0), Vector3.ONE)
		joints.append({"node": name, "stiffness": 0.35, "gravityPower": 0.08, "gravityDir": [0, -1, 0], "dragForce": 0.25, "hitRadius": 0.015})
	_bone(parent, "tasselTip", Vector3(0, -0.09, 0))
	joints.append({"node": "tasselTip"})
	root.set_meta("springs", {"specVersion": "1.0", "springs": [{"joints": joints, "colliderGroups": [0]}], "colliders": [{"node": "head", "shape": {"sphere": {"offset": [0, 0.12, 0], "radius": 0.145}}}], "colliderGroups": [{"colliders": [0]}]})
