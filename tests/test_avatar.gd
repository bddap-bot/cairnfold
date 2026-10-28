extends "res://../tests/support/suite.gd"

## Headless checks of the VRM avatars: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_avatar.gd

## Public sample avatars (tests/avatars/README.md).
const SAMPLES := ["crimsom-1.0.vrm", "crimsom-0.x.vrm", "godette-0.x.vrm"]
const UnityAvatar = preload("res://../scripts/unity_avatar.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for i in Avatar.BUILT_IN.size():
		_built_in_reads_as_humanoid(i)
		var file := FileAccess.get_file_as_bytes(Avatar.BUILT_IN[i])
		_skin_bends_as(Avatar.built_in(i), Avatar.BUILT_IN[i].get_file(), _gltf_skin.bind(file, Avatar.BUILT_IN[i].get_file()))
	_pose_puts_the_eyes_on_the_head(Avatar.built_in(0), "pebble")
	for path in SAMPLES:
		var scene := Avatar.read(FileAccess.get_file_as_bytes(_sample(path)))
		check(scene != null, "%s reads as an avatar" % path)
		if scene != null:
			_within_limits(scene, path, _gltf_json(FileAccess.get_file_as_bytes(_sample(path))))
			_pose_puts_the_eyes_on_the_head(scene, path)
			_arms_join_shoulders_to_hands(scene, path)
			_skin_bends_as(scene, path, _gltf_skin.bind(FileAccess.get_file_as_bytes(_sample(path)), path))
	_both_versions_stand_alike()
	_unweighted_children_keep_humanoid_bones()
	_simulates_the_longest_chains_within_the_limit()
	_unity_package_converts()
	for i in Avatar.BUILT_IN.size():
		_eye_bones_follow_the_look(Avatar.built_in(i), "built-in %d" % i)
	_expressions_follow_the_look()
	check(Avatar.read("not a vrm".to_utf8_buffer()) == null, "a file that is not glTF reads as nothing")
	var big := PackedByteArray()
	big.resize(Avatar.MAX_BYTES + 1)
	check(Avatar.read(big) == null, "a file over the size limit is not read")
	_images_are_measured_before_decoding()
	_blend_shapes_are_bounded()
	_shape_normals_turn_with_the_shape()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## A file naming images too large or too many is refused from their headers, before any is decoded: a beacon makes every
## Quest nearby read the file it names.
func _images_are_measured_before_decoding() -> void:
	var bytes := FileAccess.get_file_as_bytes(_sample("crimsom-1.0.vrm"))
	var png := func(w: int, h: int) -> PackedByteArray: return Image.create_empty(w, h, false, Image.FORMAT_L8).save_png_to_buffer()
	var jpg := func(w: int, h: int) -> PackedByteArray: return Image.create_empty(w, h, false, Image.FORMAT_RGB8).save_jpg_to_buffer()
	var side := Avatar.MAX_IMAGE_SIDE
	check(Avatar.read(_with_images(bytes, [png.call(side, 1), jpg.call(1, side)])) != null, "images at the side limit are read")
	check(Avatar.read(_with_images(bytes, [png.call(side + 1, 1)])) == null, "a PNG wider than the limit is refused")
	check(Avatar.read(_with_images(bytes, [jpg.call(1, side + 1)])) == null, "a JPEG taller than the limit is refused")
	var cut: PackedByteArray = png.call(64, 64)
	check(Avatar.read(_with_images(bytes, [cut.slice(0, cut.size() - 20)])) == null, "an image that does not decode is refused, not handed to other decoders")
	check(Avatar.read(_with_images(bytes, [Image.create_empty(4, 4, false, Image.FORMAT_RGBA8).save_webp_to_buffer()])) == null, "an image that is neither PNG nor JPEG is refused")
	var many := []
	for i in Avatar.MAX_IMAGES:
		many.append(png.call(1, 1))
	check(Avatar.read(_with_images(bytes, many)) != null, "a file with as many images as the limit is read")
	check(Avatar.read(_with_images(bytes, many + [png.call(1, 1)])) == null, "a file with more images than the limit is refused")
	var full: PackedByteArray = png.call(side, side)
	var fill := Avatar.MAX_PIXELS / (side * side)
	check(Avatar.read(_with_images(bytes, Array(range(fill)).map(func(_i: int) -> PackedByteArray: return full))) != null, "images filling the pixel limit are read")
	check(Avatar.read(_with_images(bytes, Array(range(fill)).map(func(_i: int) -> PackedByteArray: return full) + [png.call(1, 1)])) == null, "a file with more pixels than the limit is refused")


func _unweighted_children_keep_humanoid_bones() -> void:
	var bytes := FileAccess.get_file_as_bytes(_sample("crimsom-1.0.vrm"))
	var json := _gltf_json(bytes)
	var bin := bytes.slice(28 + bytes.decode_u32(12))
	for bone: String in ["hips", "head"]:
		var node := int(json.extensions.VRMC_vrm.humanoid.humanBones[bone].node)
		json.nodes[node].get_or_add("children", []).append(json.nodes.size())
		json.nodes.append({"name": bone + " unweighted child", "translation": [0, 0.1, 0]})
	check(Avatar.read(_glb(json, bin)) != null, "unweighted children leave hips and head bound to their skeleton bones")


func _blend_shapes_are_bounded() -> void:
	var bytes := FileAccess.get_file_as_bytes(_sample("crimsom-1.0.vrm"))
	var json := _gltf_json(bytes)
	var bin := bytes.slice(28 + bytes.decode_u32(12))
	var prim: Dictionary = json.meshes[0].primitives[0]
	var vertices: int = json.accessors[int(prim.attributes.POSITION)].count
	var targets: Array = prim.targets
	var times := Avatar.MAX_BLEND_VERTICES / (vertices * targets.size()) + 1
	var many := []
	for i in times:
		many.append_array(targets)
	prim.targets = many
	json.meshes[0].erase("weights")
	json.meshes[0].get("extras", {}).erase("targetNames")
	check(Avatar.read(_glb(json, bin)) == null, "a file of %d blend shapes over %d vertices is refused" % [many.size(), vertices])


## A written blend shape turns the normals of the surface it tilts, and only those: a flat grid whose x > 0 half a shape
## raises into a ramp reads, once written, as normals up on the flat and across the ramp's slope on the ramp.
func _shape_normals_turn_with_the_shape() -> void:
	var side := 9
	var slope := 0.5
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var raised := PackedVector3Array()
	for z in side:
		for x in side:
			var at := Vector3(x - side / 2, 0, z - side / 2)
			vertices.append(at)
			normals.append(Vector3.UP)
			raised.append(Vector3(0, slope * maxf(at.x, 0.0), 0))
	var indices := PackedInt32Array()
	for z in side - 1:
		for x in side - 1:
			var i := z * side + x
			indices.append_array([i, i + 1, i + side, i + 1, i + side + 1, i + side])
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var shape := []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = raised
	var unturned := PackedVector3Array()
	unturned.resize(vertices.size())
	shape[Mesh.ARRAY_NORMAL] = unturned
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	mesh.add_blend_shape("ramp")
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [shape])
	var root := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	root.add_child(instance)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	check(doc.append_from_scene(root, state) == OK, "a ramp shape exports")
	root.free()
	var glb := Vrm._positional(doc.generate_buffer(state))
	var json := _gltf_json(glb)
	var bin := glb.slice(28 + glb.decode_u32(12))
	var data: Array = json.bufferViews.map(func(v: Dictionary) -> PackedByteArray: return bin.slice(int(v.get("byteOffset", 0)), int(v.get("byteOffset", 0)) + int(v.byteLength)))
	var primitive: Dictionary = json.meshes[0].primitives[0]
	var target: Dictionary = primitive.targets[0]
	check(not target.has("TANGENT"), "a written shape carries no tangents")
	check(target.has("NORMAL"), "a written shape carries its normals' turn")
	if not target.has("NORMAL"):
		return
	var positions := Vrm._vec3s(json.accessors[int(primitive.attributes.POSITION)], json.bufferViews, data)
	var base := Vrm._vec3s(json.accessors[int(primitive.attributes.NORMAL)], json.bufferViews, data)
	var turns := Vrm._vec3s(json.accessors[int(target.NORMAL)], json.bufferViews, data)
	var across := Vector3(-slope, 1, 0).normalized()
	for i in positions.size():
		var p := positions[i]
		if p.x < -1.0:
			check(turns[i] == Vector3.ZERO, "the flat at %s keeps its normal" % p)
		elif p.x > 0.5:
			check((base[i] + turns[i]).normalized().distance_to(across) < 1e-4, "the ramp at %s faces across its slope: %s" % [p, (base[i] + turns[i]).normalized()])


## `bytes`, a binary glTF, holding `images` in place of its own, each in a buffer view appended to its binary chunk.
func _with_images(bytes: PackedByteArray, images: Array) -> PackedByteArray:
	var length := bytes.decode_u32(12)
	var json := _gltf_json(bytes)
	var bin := bytes.slice(28 + length, 28 + length + bytes.decode_u32(20 + length))
	json.images = []
	for image: PackedByteArray in images:
		json.images.append({"bufferView": json.bufferViews.size(), "mimeType": "image/png"})
		json.bufferViews.append({"buffer": 0, "byteOffset": bin.size(), "byteLength": image.size()})
		bin.append_array(image)
		while bin.size() % 4:
			bin.append(0)
	json.buffers[0].byteLength = bin.size()
	return _glb(json, bin)


## A binary glTF of `json` and its binary chunk `bin`.
func _glb(json: Dictionary, bin: PackedByteArray) -> PackedByteArray:
	var text := JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4:
		text.append(0x20)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 28 + text.size() + bin.size())
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(text)
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, bin.size())
	head.encode_u32(4, 0x004E4942)
	return out + head + bin


## The Unity sample package imports as the avatar model straight from its FBX and .meta: its skeleton, skin and blend
## shapes, its humanoid bones as the package's Avatar definition maps them, keeping Unity's bone names; written as a
## scene and read back, it opens, poses and bends as the engine's own import of the FBX does.
func _unity_package_converts() -> void:
	var model := UnityAvatar.avatar_scene(_sample("seed-san"))
	check(model != null, "the Unity package imports")
	if model == null:
		return
	var avatar := UnityAvatar.avatar_definition(FileAccess.get_file_as_string(_sample("seed-san/Models/new_seedsan_betterfbx.fbx.meta")))
	var human: Dictionary = model.get_meta("humanoid")
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var bone_of := func(b: String) -> String: return (human[b] as NodePath).get_concatenated_subnames()
	_rests_in_the_avatar_definitions_pose(sk, bone_of.call("leftUpperArm"), FileAccess.get_file_as_string(_sample("seed-san/Models/new_seedsan_betterfbx.fbx.meta")))
	check(human.size() == avatar.human.size() and avatar.human.keys().all(func(b: String) -> bool:
		var as_bone := UnityAvatar.vrm_bone(avatar.human[b])
		return human.has(as_bone) and sk.find_bone(bone_of.call(as_bone)) >= 0), "every bone the Avatar definition maps is a skeleton bone under its humanoid name (%d of %d)" % [human.size(), avatar.human.size()])
	check(bone_of.call("hips") == "hips" and bone_of.call("head") == "head" and bone_of.call("leftThumbMetacarpal") == "thumb_01_L", "the bones keep Unity's names, made fit for nodes: its de-duplicated head is the skeleton's head, its thumb proximal VRM's metacarpal")
	var path := ProjectSettings.globalize_path("user://seed-san.scn")
	var report: Dictionary = model.get_meta("report")
	check((report["renderers drawn"] as Array).size() == 5, "all five of the model's renderers draw (%s)" % [report["renderers drawn"]])
	_writes_expressions(model)
	var started := Time.get_ticks_usec()
	var packed := Avatar.model(model)
	check(packed != null and ResourceSaver.save(packed, path) == OK, "the model packs and saves as a scene")
	var scene := load(path) as PackedScene
	print("unity package: modelled and written in %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	check(scene != null, "the written scene reads back as the avatar model")
	if scene == null:
		return
	_pose_puts_the_eyes_on_the_head(scene, "seed-san")
	_arms_join_shoulders_to_hands(scene, "seed-san")
	var fbx := _sample("seed-san/Models/new_seedsan_betterfbx.fbx")
	var reference := _imported(fbx)
	var skins := reference.find_children("*", "MeshInstance3D", true, false).filter(func(mi: MeshInstance3D) -> bool: return mi.skin != null)
	var shapes := {}
	for mi: MeshInstance3D in skins:
		shapes[mi.mesh] = mi.mesh.get_blend_shape_count()
	check(skins.size() == 5 and shapes.values().has(43), "the engine's import of the FBX has five skinned meshes and the face's 43 blend shapes")
	_keeps_skins_and_shapes(scene, "seed-san", shapes.values().reduce(func(n: int, k: int) -> int: return n + k, 0))
	_skin_bends_as(scene, "seed-san", _scene_skin.bind(reference))
	reference.free()
	var lowered := ProjectSettings.globalize_path("user://seed-san-lowered/Models")
	DirAccess.make_dir_recursive_absolute(lowered)
	DirAccess.copy_absolute(_sample("seed-san/Models/new_seedsan_betterfbx.fbx"), lowered.path_join("new_seedsan_betterfbx.fbx"))
	var meta := FileAccess.get_file_as_string(_sample("seed-san/Models/new_seedsan_betterfbx.fbx.meta"))
	var entry := meta.find("    - name: upper_arm.L\n")
	var start := meta.find("rotation: {", entry)
	var end := meta.find("}", start) + 1
	var turned := _unity_rotation(meta.substr(start, end - start)) * Quaternion(Vector3.FORWARD, PI / 4)
	meta = meta.substr(0, start) + "rotation: {x: %f, y: %f, z: %f, w: %f}" % [turned.x, turned.y, turned.z, turned.w] + meta.substr(end)
	FileAccess.open(lowered.path_join("new_seedsan_betterfbx.fbx.meta"), FileAccess.WRITE).store_string(meta)
	var moved := UnityAvatar.avatar_scene(lowered.get_base_dir())
	check(moved != null, "the package with its Avatar's arm turned imports")
	if moved != null:
		var moved_sk: Skeleton3D = moved.find_children("*", "Skeleton3D", true, false)[0]
		_rests_in_the_avatar_definitions_pose(moved_sk, bone_of.call("leftUpperArm"), meta)
		moved.free()
	var empty := ProjectSettings.globalize_path("user://no-humanoid")
	DirAccess.make_dir_recursive_absolute(empty)
	check(UnityAvatar.avatar_scene(empty) == null, "a package with no humanoid model imports as nothing")


## The humanoid rests in the pose its Unity Avatar definition records, whatever pose the model file binds its skin in:
## a model bound with its arms lowered converts with the T-pose its Avatar was configured in.
func _rests_in_the_avatar_definitions_pose(sk: Skeleton3D, bone: String, meta: String) -> void:
	var entry := meta.find("    - name: upper_arm.L\n")
	var start := meta.find("rotation: {", entry)
	var unity := _unity_rotation(meta.substr(start, meta.find("}", start) + 1 - start))
	var mirrored := Quaternion(unity.x, -unity.y, -unity.z, unity.w)
	var rest := sk.get_bone_rest(sk.find_bone(bone)).basis.get_rotation_quaternion()
	check(rest.angle_to(mirrored) < 0.01, "the upper arm rests as the Avatar definition turns it (%.1f degrees off)" % rad_to_deg(rest.angle_to(mirrored)))


func _unity_rotation(text: String) -> Quaternion:
	var q := {}
	for part in text.trim_prefix("rotation: {").trim_suffix("}").split(","):
		q[part.get_slice(":", 0).strip_edges()] = part.get_slice(":", 1).to_float()
	return Quaternion(q.x, q.y, q.z, q.w).normalized()


## An imported avatar's "faces" write as VRM expressions, preset or custom by name, each bound to the morph target
## of its shape's name, and the file lists every extension it carries.
func _writes_expressions(model: Node3D) -> void:
	var worn: Node3D = model.duplicate()
	var mi: MeshInstance3D = worn.find_children("*", "MeshInstance3D", true, false)[0]
	var shape: String = mi.mesh.get_blend_shape_name(mi.mesh.get_blend_shape_count() - 1)
	worn.set_meta("faces", {"happy": [{"shape": shape, "weight": 0.5}], "wink": [{"shape": shape, "weight": 1.0}], "none": [{"shape": "no such shape", "weight": 1.0}]})
	UnityAvatar.wearable(worn)
	var vrm := ProjectSettings.globalize_path("user://seed-san.vrm")
	Vrm.write(worn, vrm)
	worn.free()
	var json := _gltf_json(FileAccess.get_file_as_bytes(vrm))
	var used: Array = json.get("extensionsUsed", [])
	check((json.extensions as Dictionary).keys().all(func(e: String) -> bool: return used.has(e)), "the file lists the extensions it carries: %s of %s" % [used, (json.extensions as Dictionary).keys()])
	var expressions: Dictionary = json.extensions.VRMC_vrm.expressions
	var target := func(b: Dictionary) -> String: return json.meshes[json.nodes[int(b.node)].mesh].extras.targetNames[int(b.index)]
	var happy: Array = expressions.preset.get("happy", {}).get("morphTargetBinds", [])
	check(happy.size() == 1 and target.call(happy[0]) == shape and happy[0].weight == 0.5, "a preset binds its shape's morph target at its weight: %s" % [expressions])
	check(expressions.custom.has("wink") and expressions.preset.size() == 1 and expressions.custom.size() == 1, "a name no preset has is custom, and an expression binding nothing is left out: %s" % [expressions])


## The engine's own import of an FBX, unshaped.
func _imported(fbx: String) -> Node3D:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.create_animations = false
	doc.append_from_file(fbx, state)
	return doc.generate_scene(state)


## Every vertex of the posed avatar sits where its source's skin puts it (`expected`, given the posed avatar, each rest
## position to where the source's weights and binds over the same bones put it): the elbows bent by the tracked hands
## reaching in close and the knees bent back by hand. A vertex a rigid part carried, or a lost or reordered bind,
## would sit elsewhere wherever two bones share it.
func _skin_bends_as(scene: PackedScene, what: String, expected: Callable) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var sk := a._skeleton
	var at := Avatar._space(sk, a._model)
	var eyes := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	a.pose(eyes, Transform3D(), Transform3D())
	var held: Array[Transform3D] = []
	for side in ["left", "right"]:
		var shoulder := a.bone(side + "UpperArm").origin
		var reach: float = a._arms[held.size()].upper_length + a._arms[held.size()].lower_length
		held.append(Transform3D(Basis.IDENTITY, shoulder + Vector3(0.3 * signf(shoulder.x), -0.6, -0.6).normalized() * reach * 0.6))
	a.pose(eyes, held[0], held[1])
	for side in ["left", "right"]:
		var knee: Avatar.Joint = a._joints.get(side + "LowerLeg")
		if knee:
			var now := a._get_joint(knee)
			a._place(knee, Transform3D(Basis(Basis(Vector3.UP, a.torso) * Vector3.RIGHT, -1.2) * now.basis, now.origin))
	var want: Dictionary = expected.call(a)
	var worst := 0.0
	var moved := 0.0
	var unmatched := 0
	var count := 0
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		var binds: Array[Transform3D] = []
		for i in mi.skin.get_bind_count():
			binds.append(at * sk.get_bone_global_pose(a.bind_bone(mi.skin, i)) * mi.skin.get_bind_pose(i))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertex: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bone: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weight: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bone.size() / vertex.size()
			for v in vertex.size():
				var posed := Vector3.ZERO
				for c in stride:
					posed += binds[bone[v * stride + c]] * vertex[v] * weight[v * stride + c]
				var there: Variant = want.get(vertex[v].snappedf(1e-5))
				count += 1
				if there == null:
					unmatched += 1
					continue
				worst = maxf(worst, (there as Array).map(func(p: Vector3) -> float: return p.distance_to(posed)).min())
				moved = maxf(moved, posed.distance_to(vertex[v]))
	print("%s: %d vertices bent at elbows and knees, %.6f m from the source's skin at worst, moved up to %.2f m" % [what, count, worst, moved])
	check(count > 0 and unmatched == 0, "%s: every vertex is one of the source's (%d of %d unmatched)" % [what, unmatched, count])
	check(worst < 1e-3, "%s: bent at elbows and knees, every vertex sits where the source's skin puts it (%.6f m off at worst)" % [what, worst])
	check(moved > 0.1, "%s: and the bend moves the body (%.2f m at most)" % [what, moved])
	a.free()


## Where a binary glTF's own skins put each vertex over the posed avatar's bones, by rest position; its joints are
## checked to rest where the file's nodes do.
func _gltf_skin(a: Avatar, bytes: PackedByteArray, what: String) -> Dictionary:
	var json := _gltf_json(bytes)
	var bin := bytes.slice(28 + bytes.decode_u32(12))
	var sk := a._skeleton
	var at := Avatar._space(sk, a._model)
	# Godot's glTF reader names a bone after its node, with the characters a bone name cannot hold made underscores.
	var bone := func(name: String) -> int: return sk.find_bone(name.replace(":", "_").replace("/", "_"))
	var world := []
	world.resize(json.nodes.size())
	var place := func(place: Callable, n: int, parent: Transform3D) -> void:
		world[n] = parent * _node_transform(json.nodes[n])
		for c: float in json.nodes[n].get("children", []):
			place.call(place, int(c), world[n])
	for n: float in json.scenes[int(json.get("scene", 0))].nodes:
		place.call(place, int(n), Transform3D.IDENTITY)
	var resting := 0.0
	for skin: Dictionary in json.skins:
		for k: float in skin.joints:
			resting = maxf(resting, (at * sk.get_bone_global_rest(bone.call(json.nodes[int(k)].name))).origin.distance_to((world[int(k)] as Transform3D).origin))
	check(resting < 1e-4, "%s: its skeleton's joints rest where the file's nodes do (%.6f m apart)" % [what, resting])
	var out := {}
	for node: Dictionary in json.nodes:
		if not node.has("mesh") or not node.has("skin"):
			continue
		var skin: Dictionary = json.skins[int(node.skin)]
		var binds := _floats(json, bin, int(skin.inverseBindMatrices))
		var joints: Array[Transform3D] = []
		for k in skin.joints.size():
			var m := binds.slice(k * 16, k * 16 + 16)
			var ibm := Transform3D(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10]), Vector3(m[12], m[13], m[14]))
			joints.append(at * sk.get_bone_global_pose(bone.call(json.nodes[int(skin.joints[k])].name)) * ibm)
		for prim: Dictionary in json.meshes[int(node.mesh)].primitives:
			var position := _floats(json, bin, int(prim.attributes.POSITION))
			var bones := _floats(json, bin, int(prim.attributes.JOINTS_0))
			var weights := _floats(json, bin, int(prim.attributes.WEIGHTS_0))
			for v in position.size() / 3:
				var rest := Vector3(position[v * 3], position[v * 3 + 1], position[v * 3 + 2])
				var posed := Vector3.ZERO
				for c in 4:
					posed += joints[int(bones[v * 4 + c])] * rest * weights[v * 4 + c]
				out.get_or_add(rest.snappedf(1e-5), []).append(posed)
	return out


## Where an importer's own scene's skins put each vertex over the posed avatar's bones of the same names (as node names
## hold them), by rest position.
func _scene_skin(a: Avatar, source: Node3D) -> Dictionary:
	var sk := a._skeleton
	var at := Avatar._space(sk, a._model)
	var out := {}
	for mi: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var theirs := mi.get_node(mi.skeleton) as Skeleton3D
		var joints: Array[Transform3D] = []
		for i in mi.skin.get_bind_count():
			var b := mi.skin.get_bind_bone(i) if mi.skin.get_bind_bone(i) >= 0 else theirs.find_bone(mi.skin.get_bind_name(i))
			joints.append(at * sk.get_bone_global_pose(sk.find_bone(theirs.get_bone_name(b).validate_node_name())) * mi.skin.get_bind_pose(i))
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertex: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bone: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weight: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bone.size() / vertex.size()
			for v in vertex.size():
				var posed := Vector3.ZERO
				for c in stride:
					posed += joints[bone[v * stride + c]] * vertex[v] * weight[v * stride + c]
				out.get_or_add(vertex[v].snappedf(1e-5), []).append(posed)
	return out


## A glTF node's local transform.
func _node_transform(node: Dictionary) -> Transform3D:
	if node.has("matrix"):
		var m: Array = node.matrix
		return Transform3D(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10]), Vector3(m[12], m[13], m[14]))
	var r: Array = node.get("rotation", [0, 0, 0, 1])
	var t: Array = node.get("translation", [0, 0, 0])
	var s: Array = node.get("scale", [1, 1, 1])
	return Transform3D(Basis(Quaternion(r[0], r[1], r[2], r[3])).scaled_local(Vector3(s[0], s[1], s[2])), Vector3(t[0], t[1], t[2]))


## A glTF accessor's components as floats: float, or unsigned byte or short, plain or normalized.
func _floats(json: Dictionary, bin: PackedByteArray, index: int) -> PackedFloat32Array:
	var acc: Dictionary = json.accessors[index]
	var view: Dictionary = json.bufferViews[int(acc.bufferView)]
	var width: int = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc.type]
	var size: int = {5126: 4, 5121: 1, 5123: 2}[int(acc.componentType)]
	var stride: int = view.get("byteStride", width * size)
	var start := int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	var scale := 1.0 if not acc.get("normalized", false) else (255.0 if size == 1 else 65535.0)
	check(not acc.has("sparse"), "accessor %d is not sparse" % index)
	var out := PackedFloat32Array()
	out.resize(int(acc.count) * width)
	for i in int(acc.count):
		for c in width:
			var o := start + i * stride + c * size
			out[i * width + c] = bin.decode_float(o) if size == 4 else (bin[o] if size == 1 else bin.decode_u16(o)) / scale
	return out


## The JSON chunk of a binary glTF.
func _gltf_json(bytes: PackedByteArray) -> Dictionary:
	return JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())


func _sample(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tests/avatars").path_join(name)


func _built_in_reads_as_humanoid(i: int) -> void:
	var a := Avatar.open(Avatar.built_in(i), Color.RED)
	for b in ["head", "leftHand", "rightHand", "hips", "leftUpperArm", "rightLowerArm"]:
		check(a._joints.has(b) and a._skeleton.get_bone_name(a._joints[b].bone) == b, "built-in %d names its %s as VRM does" % [i, b])
	var tinted := 0
	var wrong := 0
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var own: Material = mi.mesh.surface_get_material(s)
			var shown: Variant = mi.get_surface_override_material(s)
			var should := own.resource_name.begins_with("tint")
			if should and shown is StandardMaterial3D and shown.albedo_color == Color.RED:
				tinted += 1
			elif should or shown != null:
				wrong += 1
	check(tinted > 0 and wrong == 0, "built-in %d takes the player's colour on its tint surfaces only (%d, %d wrong)" % [i, tinted, wrong])
	check((a._model.get_meta("eyes") as Vector3).is_equal_approx(Vector3(0, 0.12, 0.09)), "built-in %d carries its eye offset in the file" % i)
	check(a._eyes.size() == 2 and a._model.get_meta("look").type == Vrm.BONE, "built-in %d looks by its eye bones" % i)
	a.free()


## A file carrying more spring joints than an avatar simulates keeps its longest chains within the limit.
func _simulates_the_longest_chains_within_the_limit() -> void:
	var chain := func(length: int) -> Dictionary:
		var joints := []
		joints.resize(length)
		return {"joints": joints}
	var springs := {"springs": [chain.call(3), chain.call(Avatar.MAX_SPRING_JOINTS - 2), chain.call(2), chain.call(Avatar.MAX_SPRING_JOINTS)]}
	Avatar._keep_longest(springs)
	check(springs.springs.map(func(c: Dictionary) -> int: return c.joints.size()) == [Avatar.MAX_SPRING_JOINTS], "the longest chain fills the limit and the rest are not simulated")
	springs = {"springs": [chain.call(3), chain.call(Avatar.MAX_SPRING_JOINTS - 2), chain.call(2)]}
	Avatar._keep_longest(springs)
	check(springs.springs.map(func(c: Dictionary) -> int: return c.joints.size()) == [Avatar.MAX_SPRING_JOINTS - 2, 2], "chains are kept longest first while they fit")


func _within_limits(scene: PackedScene, what: String, json: Dictionary) -> void:
	var targets := 0
	var authored := 0
	for m: Dictionary in json.meshes:
		targets += (m.primitives[0] as Dictionary).get("targets", []).size()
		for p: Dictionary in m.primitives:
			authored += int(json.accessors[int(p.get("indices", p.attributes.POSITION))].count) / 3
	_keeps_skins_and_shapes(scene, what, targets)
	var a := Avatar.open(scene, Color.WHITE)
	var triangles := 0
	var surfaces := 0
	var plain := 0
	var materials := 0
	var textures := {}
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		surfaces += mi.mesh.get_surface_count()
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.albedo_texture != null:
				textures[m.albedo_texture] = true
			if m != null:
				plain += 1 if m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX and not m.normal_enabled and not m.emission_enabled and m.cull_mode == BaseMaterial3D.CULL_BACK and m.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] else 0
				materials += 1
			triangles += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	check(triangles == authored, "%s keeps every triangle its file has (%d of %d)" % [what, triangles, authored])
	check(surfaces <= Avatar.MAX_SURFACES, "%s keeps to the draw limit (%d)" % [what, surfaces])
	check(plain == materials, "%s draws its colour alone, lit once a vertex, front faces only, cut out where see-through (%d of %d)" % [what, plain, materials])
	check(not textures.is_empty(), "%s keeps its textures" % what)
	for tex: Texture2D in textures:
		check(maxi(tex.get_width(), tex.get_height()) <= Avatar.MAX_TEXTURE and tex.get_image().has_mipmaps(), "%s keeps its textures to the size limit, mipmapped (%dx%d)" % [what, tex.get_width(), tex.get_height()])
	a.free()


## Every mesh stays skinned over the one skeleton a pose moves and keeps all `targets` blend shapes its source has.
func _keeps_skins_and_shapes(scene: PackedScene, what: String, targets: int) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	var meshes := 0
	var skinned := 0
	var shapes := {}
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
		skinned += 1 if mi.skin != null and mi.get_node_or_null(mi.skeleton) == a._skeleton else 0
		shapes[mi.mesh] = mi.mesh.get_blend_shape_count()
	check(meshes > 0 and skinned == meshes and a.find_children("*", "Skeleton3D", true, false).size() == 1, "%s stands skinned: every mesh bends over the one skeleton a pose moves (%d of %d)" % [what, skinned, meshes])
	var kept: int = shapes.values().reduce(func(n: int, k: int) -> int: return n + k, 0)
	check(kept == targets, "%s keeps every blend shape (%d of %d)" % [what, kept, targets])
	a.free()


func _pose_puts_the_eyes_on_the_head(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var eyes := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1.7, -2))
	var l := Transform3D(Basis(Vector3.UP, 0.7), Vector3(2.75, 1.2, -2.35))
	var r := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.25, 1.2, -2.35))
	a.pose(eyes, l, r)
	var head := a.bone("head")
	var seen: Vector3 = head * (a._model.get_meta("eyes") as Vector3)
	check(seen.distance_to(eyes.origin) < 0.001, "%s: eyes sit at the tracked head (%s vs %s)" % [what, seen, eyes.origin])
	var face: Vector3 = head.basis * a._joints.head.rest.basis.inverse() * (a._model.get_meta("forward") as Vector3)
	check(face.normalized().dot(-eyes.basis.z) > 0.99, "%s: the face looks where the head looks" % what)
	check(a.bone("leftHand").origin.distance_to(l.origin) < 0.001 and a.bone("rightHand").origin.distance_to(r.origin) < 0.001, "%s: hands follow the controllers" % what)
	for s in 2:
		var side: String = ["left", "right"][s]
		var hand := a.bone(side + "Hand")
		var along: Vector3 = hand.basis * (a._joints[side + "Hand"].rest.basis.inverse() * (a._joints[side + "Hand"].rest.origin - a._joints[side + "LowerArm"].rest.origin))
		var held: Transform3D = [l, r][s]
		check(along.normalized().dot(-held.basis.z) > 0.99, "%s: the %s hand points where its controller points" % [what, side])
	check(a.bone("hips").origin.y < eyes.origin.y - 0.4, "%s: the body hangs below the head" % what)
	var tilted := Transform3D(Basis.from_euler(Vector3(0.5, 1.1, 0.3)), Vector3(1, a.eye_height, 1))
	a.pose(tilted, l, r)
	var hips: Basis = a.bone("hips").basis * a._joints.hips.rest.basis.inverse()
	check(hips.y.is_equal_approx(Vector3.UP), "%s: the body stays upright when the head tips" % what)
	var ahead: Vector3 = hips * a._facing.inverse() * Vector3.FORWARD
	check(Vector2(ahead.x, ahead.z).normalized().is_equal_approx(Vector2(-sin(0.7), -cos(0.7))), "%s: and keeps facing as it was while the head turns within a neck's reach" % what)
	a.pose(Transform3D(Basis(Vector3.UP, 0.7 + Torso.TURN + 0.3), tilted.origin), l, r)
	hips = a.bone("hips").basis * a._joints.hips.rest.basis.inverse()
	ahead = hips * a._facing.inverse() * Vector3.FORWARD
	check(Vector2(ahead.x, ahead.z).normalized().is_equal_approx(Vector2(-sin(1.0), -cos(1.0))), "%s: and turns once the head turns further" % what)
	a.free()


## The arms keep their length: each bends at the elbow to reach its hand, out and down from the body.
func _arms_join_shoulders_to_hands(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var eyes := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	a.pose(eyes, Transform3D(), Transform3D())
	var held: Array[Transform3D] = []
	for side in ["left", "right"]:
		var upper: Avatar.Joint = a._joints[side + "UpperArm"]
		var reach: float = upper.rest.origin.distance_to(a._joints[side + "LowerArm"].rest.origin) + a._joints[side + "LowerArm"].rest.origin.distance_to(a._joints[side + "Hand"].rest.origin)
		var shoulder := a.bone(side + "UpperArm").origin
		held.append(Transform3D(Basis.IDENTITY, shoulder + Vector3(0.3 * signf(shoulder.x), -0.6, -0.6).normalized() * reach * 0.7))
	a.pose(eyes, held[0], held[1])
	var bent := 0
	for side in ["left", "right"]:
		var upper: Avatar.Joint = a._joints[side + "UpperArm"]
		var lower: Avatar.Joint = a._joints[side + "LowerArm"]
		var hand: Avatar.Joint = a._joints[side + "Hand"]
		var s := a.bone(side + "UpperArm").origin
		var e := a.bone(side + "LowerArm").origin
		var h := a.bone(side + "Hand").origin
		check(absf(s.distance_to(e) - upper.rest.origin.distance_to(lower.rest.origin)) < 0.002, "%s: the %s upper arm keeps its length" % [what, side])
		check(absf(e.distance_to(h) - lower.rest.origin.distance_to(hand.rest.origin)) < 0.002 or s.distance_to(h) > 0.95 * (s.distance_to(e) + e.distance_to(h)), "%s: the %s forearm reaches its hand" % [what, side])
		if s.distance_to(h) < 0.95 * (s.distance_to(e) + e.distance_to(h)):
			check(e.y < (s.y + h.y) * 0.5, "%s: the %s elbow hangs down" % [what, side])
			check(signf(e.x - (s.x + h.x) * 0.5) == signf(s.x), "%s: the %s elbow points out" % [what, side])
			bent += 1
	check(bent == 2, "%s: both arms bend to reach hands held close" % what)
	a.free()


## VRM 0.x faces -Z and VRM 1.0 +Z; the same model in each stands the same way in the same pose.
func _both_versions_stand_alike() -> void:
	var at := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1, 1.6, 2))
	var l := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.8, 1.1, 1.7))
	var r := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.3, 1.1, 1.8))
	var posed := []
	for path in SAMPLES.slice(0, 2):
		var a := Avatar.open(Avatar.read(FileAccess.get_file_as_bytes(_sample(path))), Color.WHITE)
		root.add_child(a)
		a.pose(at, l, r)
		posed.append([a.bone("hips").origin, a.bone("leftLowerArm").origin, a.bone("rightUpperArm").origin, a.bone("leftHand").origin])
		a.free()
	for k in 4:
		check(posed[0][k].distance_to(posed[1][k]) < 0.01, "VRM 1.0 and 0.x stand alike (%d: %s vs %s)" % [k, posed[0][k], posed[1][k]])


## Where an eye bone points, turned from its rest as it is now.
func _eye_points(a: Avatar, side: String) -> Vector3:
	var rest: Transform3D = a._joints[side + "Eye"].rest
	return a.bone(side + "Eye").basis * rest.basis.inverse() * (a._model.get_meta("forward") as Vector3)


## Each eye turns by the model's range map: in proportion to the look up to its largest input, no further.
func _eye_bones_follow_the_look(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var at := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3, 1.7, -2))
	var ranges: Array = a._model.get_meta("look").ranges
	var ahead := -at.basis.z
	a.pose(at, at, at)
	for side in ["left", "right"]:
		check(_eye_points(a, side).angle_to(ahead) < 0.001, "%s: the %s eye looks ahead by default" % [what, side])
	var half: float = ranges[1].x * 0.5
	a.pose(at, at, at, Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(half)))
	var left := _eye_points(a, "left")
	check(absf(rad_to_deg(left.angle_to(ahead)) - ranges[1].y * 0.5) < 0.1 and left.dot(at.basis.x) < 0.0, "%s: looking left, the left eye turns outward by half its outer range" % what)
	check(absf(rad_to_deg(_eye_points(a, "right").angle_to(ahead)) - ranges[0].y * 0.5) < 0.1, "%s: and the right eye inward by half its inner range" % what)
	a.pose(at, at, at, Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(80.0)))
	check(absf(rad_to_deg(_eye_points(a, "left").angle_to(ahead)) - ranges[1].y) < 0.1, "%s: a look past the range turns the eye no further than the range allows" % what)
	a.pose(at, at, at, Vector3.FORWARD.rotated(Vector3.RIGHT, deg_to_rad(80.0)))
	var up := _eye_points(a, "right")
	check(absf(rad_to_deg(up.angle_to(ahead)) - ranges[3].y) < 0.1 and up.y > ahead.y, "%s: looking up, the eyes turn up, clamped" % what)
	a.free()


## A model that looks by expression weighs its look expressions: looking left sets lookLeft and none of the others.
func _expressions_follow_the_look() -> void:
	var a := Avatar.open(Avatar.read(FileAccess.get_file_as_bytes(_sample("godette-0.x.vrm"))), Color.WHITE)
	root.add_child(a)
	check(a._look_type == Vrm.EXPRESSION and a._shapes.all(func(sets: Array) -> bool: return not sets.is_empty()), "godette looks by its four look expressions")
	var at := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var ranges: Array = a._model.get_meta("look").ranges
	a.pose(at, at, at, Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(ranges[1].x * 0.5)))
	var weights := Vrm.LOOKS.map(func(dir: String) -> float:
		var b: Array = a._shapes[Vrm.LOOKS.find(dir)][0]
		return (b[0] as MeshInstance3D).get_blend_shape_value(b[1]))
	check(absf(weights[0] - ranges[1].y * 0.5) < 0.01 and weights.slice(1).all(func(w: float) -> bool: return w == 0.0), "looking left weighs lookLeft by the range map, and nothing else (%s)" % [weights])
	a.pose(at, at, at)
	check(Vrm.LOOKS.all(func(dir: String) -> bool:
		var b: Array = a._shapes[Vrm.LOOKS.find(dir)][0]
		return (b[0] as MeshInstance3D).get_blend_shape_value(b[1]) == 0.0), "looking ahead weighs none")
	a.free()
