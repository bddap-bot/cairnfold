extends "res://../tests/support/suite.gd"

## Provenance: tests/avatars/README.md.
const SAMPLES := ["crimsom-1.0.vrm", "crimsom-0.x.vrm", "godette-0.x.vrm", "twist-1.0.vrm"]
const UnityAvatar = preload("res://../scripts/unity_avatar.gd")
const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")
const SpringRuntime = preload("res://addons/avatar_workshop/spring_runtime.gd")


func _run() -> void:
	for i in Avatar.BUILT_IN.size():
		_built_in_reads_as_humanoid(i)
		var file := FileAccess.get_file_as_bytes(Avatar.BUILT_IN[i])
		_skin_bends_as(Avatar.built_in(i), Avatar.BUILT_IN[i].get_file(), _gltf_skin.bind(file, Avatar.BUILT_IN[i].get_file()))
		_springs_survive_a_rewrite(Avatar.BUILT_IN[i])
	_pose_puts_the_eyes_on_the_head(Avatar.built_in(0), "pebble")
	for i in Avatar.BUILT_IN.size():
		_headless_leaves_the_eyes_clear(Avatar.built_in(i), Avatar.BUILT_IN[i].get_file())
	for path in SAMPLES:
		var scene := Avatar.read(FileAccess.get_file_as_bytes(avatar_file(path)))
		check(scene != null, "%s reads as an avatar" % path)
		if scene != null:
			_within_limits(scene, path, Vrm.json_chunk(FileAccess.get_file_as_bytes(avatar_file(path))))
			_pose_puts_the_eyes_on_the_head(scene, path)
			_arms_join_shoulders_to_hands(scene, path)
			_fingers_curl_into_the_palm(scene, path)
			_headless_leaves_the_eyes_clear(scene, path)
			_skin_bends_as(scene, path, _gltf_skin.bind(FileAccess.get_file_as_bytes(avatar_file(path)), path))
	_an_extension_at_another_version_is_refused()
	_a_record_lacking_a_field_it_must_carry_is_refused_naming_it()
	_a_colour_averages_the_triangles_base_colours()
	_a_file_the_headset_does_not_draw_stands_in_a_built_in()
	_both_versions_stand_alike()
	_unweighted_children_keep_humanoid_bones()
	_simulates_the_longest_chains_within_the_limit()
	_import_settles_each_spring_chain()
	_a_later_physbone_over_the_same_bones_is_shadowed()
	_switched_off_physics_stays_out()
	await _a_switch_stops_and_restarts_a_chain_as_vrchat_does(false)
	await _a_switch_stops_and_restarts_a_chain_as_vrchat_does(true)
	_a_settled_joint_swings_about_its_authored_rotation()
	_outlined_materials_draw_their_hull()
	_many_surfaces_draw_with_their_outlines()
	_read_skins_bind_only_weighed_bones()
	_hidden_avatars_pause()
	_unity_package_converts()
	_physbones_keep_whose_hands_touch_them()
	for i in Avatar.BUILT_IN.size():
		_eye_bones_follow_the_look(Avatar.built_in(i), "built-in %d" % i)
	_expressions_follow_the_look()
	_a_worn_avatar_frees_its_animated_materials()
	check(Avatar.read("not a vrm".to_utf8_buffer()) == null, "a file that is not glTF reads as nothing")
	_read_limits_follow_memory()
	_unread_files_say_why()
	_images_are_measured_before_decoding()
	_textures_share_the_texel_limit()
	_blend_shapes_are_bounded()
	_shape_normals_turn_with_the_shape()
	_set_blend_shapes_are_written()
	_blended_surfaces_stay_blended()
	finish()


func _a_colour_averages_the_triangles_base_colours() -> void:
	var json := {
		"accessors": [{"count": 300}, {"count": 100}, {"count": 6}],
		"textures": [{"source": 1}],
		"materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}}, {"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
		"meshes": [{"primitives": [{"material": 0, "indices": 0}, {"material": 1, "indices": 1}]}, {"primitives": [{"attributes": {"POSITION": 2}}]}],
	}
	var blue := Color(0, 0, 1)
	var c := Vrm._colour(json, [Color.WHITE, blue])
	var want := (Color(306.0 / 406.0, 6.0 / 406.0, 106.0 / 406.0)).linear_to_srgb()
	check(c.is_equal_approx(want), "a model's colour is its triangles' base colours averaged: %s, want %s" % [c, want])
	check(Vrm._colour({}, []) == Color.WHITE, "a model with no materials is white")
	var odd := {
		"accessors": [{"count": 3}, 7, {"count": "x"}],
		"textures": [{"source": "a"}, 4],
		"materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 0], "baseColorTexture": 3}}, 2, {"pbrMetallicRoughness": {"baseColorTexture": {"index": 1.5}}}],
		"meshes": [{"primitives": [{"material": 0, "indices": 0}, {"material": 1, "indices": 1}, {"material": "m", "indices": 2}, {"material": 2, "indices": 0}, {"attributes": 5}, 9]}, 3, {"primitives": {}}],
	}
	check(Vrm._colour(odd, [blue]) == Color.WHITE, "a file's malformed materials, textures, accessors and meshes count as white or nothing")
	var card := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	card.fill(Color(0, 0, 0, 0))
	card.set_pixel(0, 0, Color(1, 0, 0, 1))
	var mean := Vrm._mean(card)
	check(mean.is_equal_approx(Color.RED) and not card.has_mipmaps(), "an image's mean weighs texels by alpha and leaves the image as it was: %s" % mean)
	var sample := Avatar.read(FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm")))
	var colour: Color = sample.get_meta("colour")
	check(not colour.is_equal_approx(Color.WHITE) and colour.r > colour.b, "a sample's colour reads from its images: %s" % colour)


func _a_file_the_headset_does_not_draw_stands_in_a_built_in() -> void:
	var sample := Avatar.read(FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm")))
	var whole := Avatar.drawn(sample, Color.RED, "file", true, 1)
	check(whole.scene == sample and whole.tint == Color.RED and whole.source == "file", "a file the headset draws stands as itself")
	var stand_in := Avatar.drawn(sample, Color.RED, "file", false, 1)
	check(not whole.stand_in and stand_in.stand_in and stand_in.scene == Avatar.built_in(1) and stand_in.tint == sample.get_meta("colour") and stand_in.source == "file", "a file it does not draw stands as built-in 1 in the file's colour")
	var built_in := Avatar.drawn(Avatar.built_in(2), Color.RED, "", false, 1)
	check(built_in.scene == Avatar.built_in(2) and built_in.tint == Color.RED, "a built-in stands as itself whatever the headset draws")
	for a: Avatar in [whole, stand_in, built_in]:
		a.free()


## A beacon makes every nearby Quest read the file it names, so images are refused from their headers.
func _images_are_measured_before_decoding() -> void:
	var bytes := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	var png := func(w: int, h: int) -> PackedByteArray: return Image.create_empty(w, h, false, Image.FORMAT_L8).save_png_to_buffer()
	var jpg := func(w: int, h: int) -> PackedByteArray: return Image.create_empty(w, h, false, Image.FORMAT_RGB8).save_jpg_to_buffer()
	var side := Avatar.MAX_IMAGE_SIDE
	check(Avatar.read(_with_images(bytes, [png.call(side, 1), jpg.call(1, side)])) != null, "images at the side limit are read")
	check(Avatar.read(_with_images(bytes, [png.call(side + 1, 1)])) == null, "a PNG wider than the limit is refused")
	check(Avatar.read(_with_images(bytes, [jpg.call(1, side + 1)])) == null, "a JPEG taller than the limit is refused")
	var square := Vector2i(4096, 4096)
	check(Avatar.decodes(square, 0) and not Avatar.decodes(square + Vector2i(1, 0), square.x * square.y * 4) and Avatar.decodes(square + Vector2i(1, 0), (square.x + 1) * square.y * 4), "an image past a 4096 px square is decoded only where its RGBA bytes fit the texture budget")
	var cut: PackedByteArray = png.call(64, 64)
	check(Avatar.read(_with_images(bytes, [cut.slice(0, cut.size() - 20)])) == null, "an image that does not decode is refused, not handed to other decoders")
	check(Avatar.read(_with_images(bytes, [Image.create_empty(4, 4, false, Image.FORMAT_RGBA8).save_webp_to_buffer()])) != null, "a lossless WebP is read")
	check(Avatar.read(_with_images(bytes, [Image.create_empty(4, 4, false, Image.FORMAT_RGB8).save_webp_to_buffer(true)])) != null, "a lossy WebP is read")
	# cwebp -exact -lossless -z 9 of one clear pixel: a lossless WebP states its size within its first 25 bytes.
	var smallest := PackedByteArray([0x52, 0x49, 0x46, 0x46, 0x14, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4c, 0x08, 0, 0, 0, 0x2f, 0, 0, 0, 0x10, 0x88, 0x88, 0x08])
	check(Vrm._image_size(smallest) == Vector2i(1, 1) and Avatar.read(_with_images(bytes, [smallest])) != null, "a lossless WebP shorter than any other header is measured and read: %s" % Vrm._image_size(smallest))
	var measured := _with_images(bytes, [png.call(64, 32), Image.create_empty(16, 8, false, Image.FORMAT_RGBA8).save_webp_to_buffer(), jpg.call(40, 20)])
	check(Avatar.texture_bytes(Vrm.images(measured)) == (64 * 32 + 16 * 8 + 40 * 20) * 4 * 4 / 3, "an avatar's texture memory is measured from its images' headers")
	check(Avatar.read(_with_images(bytes, ["GIF89a".to_ascii_buffer() + cut])) == null, "an image that is neither PNG, JPEG nor WebP is refused")
	var many := []
	for i in Avatar.MAX_IMAGES:
		many.append(png.call(1, 1))
	check(Avatar.read(_with_images(bytes, many)) != null, "a file with as many images as the limit is read")
	check(Avatar.read(_with_images(bytes, many + [png.call(1, 1)])) == null, "a file with more images than the limit is refused")
	var full: PackedByteArray = png.call(4096, 4096)
	check(Avatar.read(_with_images(bytes, Array(range(13)).map(func(_i: int) -> PackedByteArray: return full)), false, 0) != null, "13 images of a 4096 px square, 218 Mpx, are read with no memory to spare: a file's pixels bound its read by none")


func _read_limits_follow_memory() -> void:
	check(Avatar.reads(0) == 1.0 and Avatar.reads(1660 << 20) == 1.0 and Avatar.reads(2432 << 20) == 1.0, "a device with a Quest 2's memory or less reads at the floors")
	var heavy := 1.18
	check(Avatar.reads(Avatar.memory_to_read(heavy)) >= heavy and Avatar.reads(Avatar.memory_to_read(heavy) - 1) < heavy, "a file past the floors is read exactly where the memory it needs is available")
	var sample := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	var floor := _padded(sample, Avatar.FLOOR_BYTES)
	check(Avatar.read(floor, false, 0) != null, "a file at the size floor is read with no memory to spare")
	var past := _padded(sample, Avatar.FLOOR_BYTES + 4)
	var needs := Avatar.memory_to_read(float(past.size()) / Avatar.FLOOR_BYTES)
	check(Avatar.read(past, false, 0) == null, "a file past the size floor is refused with no memory to spare")
	check(Avatar.read(past, false, needs) != null, "a file past the size floor is read where the memory it needs is available")
	Avatar._reading = needs
	check(Avatar.read(past, false, needs) == null, "memory a read under way holds is not counted available to another")
	Avatar._reading = 0


## A file that is not read says what kept it, and only one weighed against the memory names a limit.
func _unread_files_say_why() -> void:
	var sample := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	check(Avatar.file_bytes(avatar_file("crimsom-1.0.vrm"), 0) == sample, "a file within the floors is read whole")
	var missing := ProjectSettings.globalize_path("user://no-such.vrm")
	var why := Avatar.unread(FileAccess.open(missing, FileAccess.READ), 0, 0)
	check(why.begins_with("it did not open") and not "memory" in why, "a file that does not open says so and names no limit: %s" % why)
	check(Avatar.file_bytes(missing).is_empty(), "a file that does not open gives no bytes")
	var empty := ProjectSettings.globalize_path("user://empty.vrm")
	FileAccess.open(empty, FileAccess.WRITE).close()
	why = Avatar.unread(FileAccess.open(empty, FileAccess.READ), 0, 0)
	check(why == "it is empty" and Avatar.file_bytes(empty).is_empty(), "an empty file says so and names no limit: %s" % why)
	var heavy := ProjectSettings.globalize_path("user://heavy.vrm")
	var f := FileAccess.open(heavy, FileAccess.WRITE)
	f.store_buffer(_padded(sample, Avatar.FLOOR_BYTES + 4))
	f.close()
	why = Avatar.unread(FileAccess.open(heavy, FileAccess.READ), Avatar.FLOOR_BYTES + 4, 0)
	check("memory reads" in why and Avatar.file_bytes(heavy, 0).is_empty(), "a file past what the memory reads names that limit: %s" % why)
	check(Avatar.file_bytes(heavy, Avatar.memory_to_read(float(Avatar.FLOOR_BYTES + 4) / Avatar.FLOOR_BYTES)).size() == Avatar.FLOOR_BYTES + 4, "the same file is read where the memory it needs is available")
	DirAccess.remove_absolute(empty)
	DirAccess.remove_absolute(heavy)


func _padded(bytes: PackedByteArray, size: int) -> PackedByteArray:
	var length := bytes.decode_u32(12)
	var json: Dictionary = Vrm.json_chunk(bytes)
	var bin := bytes.slice(28 + length, 28 + length + bytes.decode_u32(20 + length))
	var out := Vrm.glb(json, bin)
	while out.size() != size:
		bin.resize(bin.size() + size - out.size())
		json.buffers[0].byteLength = bin.size()
		out = Vrm.glb(json, bin)
	return out


## The texture budget is set from the headers before any image decodes.
func _textures_share_the_texel_limit() -> void:
	var bytes := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	var png := func(w: int, h: int) -> PackedByteArray: return Image.create_empty(w, h, false, Image.FORMAT_RGBA8).save_png_to_buffer()
	var three := _with_images(bytes, [png.call(64, 64), png.call(64, 64), png.call(64, 64)])
	check(Avatar.read(three) != null, "a file whose images are all measured is read")
	var hidden: Dictionary = Vrm.json_chunk(three)
	hidden.images[2] = {"uri": "data:image/png;base64," + Marshalls.raw_to_base64(png.call(4, 4)), "mimeType": "image/png"}
	check(Avatar.read(Vrm.glb(hidden, three.slice(28 + three.decode_u32(12)))) == null, "a file holding an image its headers were not measured from is refused")
	var lying: Dictionary = Vrm.json_chunk(three)
	lying.images.push_front({})
	check(Avatar.read(Vrm.glb(lying, three.slice(28 + three.decode_u32(12)))) == null, "a file whose images decode out of the places they were measured in is refused")


func _unweighted_children_keep_humanoid_bones() -> void:
	var bytes := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	var json: Dictionary = Vrm.json_chunk(bytes)
	var bin := bytes.slice(28 + bytes.decode_u32(12))
	for bone: String in ["hips", "head"]:
		var node := int(json.extensions.VRMC_vrm.humanoid.humanBones[bone].node)
		json.nodes[node].get_or_add("children", []).append(json.nodes.size())
		json.nodes.append({"name": bone + " unweighted child", "translation": [0, 0.1, 0]})
	check(Avatar.read(Vrm.glb(json, bin)) != null, "unweighted children leave hips and head bound to their skeleton bones")


func _blend_shapes_are_bounded() -> void:
	var bytes := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	var json: Dictionary = Vrm.json_chunk(bytes)
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
	check(Avatar.read(Vrm.glb(json, bin)) == null, "a file of %d blend shapes over %d vertices is refused" % [many.size(), vertices])


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
	var json: Dictionary = Vrm.json_chunk(glb)
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


func _with_images(bytes: PackedByteArray, images: Array) -> PackedByteArray:
	var length := bytes.decode_u32(12)
	var json: Dictionary = Vrm.json_chunk(bytes)
	var bin := bytes.slice(28 + length, 28 + length + bytes.decode_u32(20 + length))
	json.images = []
	for image: PackedByteArray in images:
		json.images.append({"bufferView": json.bufferViews.size(), "mimeType": "image/png"})
		json.bufferViews.append({"buffer": 0, "byteOffset": bin.size(), "byteLength": image.size()})
		bin.append_array(image)
		while bin.size() % 4:
			bin.append(0)
	json.buffers[0].byteLength = bin.size()
	return Vrm.glb(json, bin)


func _report_prints_names_only_when_asked(report: Dictionary, avatar: String) -> void:
	var parts: Array = report["renderers drawn"] + [avatar]
	UnityAvatar.Assets.print_names = false
	var plain := "\n".join(UnityAvatar.report_lines(report))
	UnityAvatar.Assets.print_names = true
	var named := "\n".join(UnityAvatar.report_lines(report))
	check(parts.all(func(n: String) -> bool: return not plain.contains(n)), "the report names none of the avatar's parts by default:\n%s" % plain)
	check((report["renderers drawn"] as Array).all(func(n: String) -> bool: return named.contains(n)), "with --names the report names each renderer drawn")


func _unity_package_converts() -> void:
	var model := UnityAvatar.avatar_scene(avatar_file("seed-san"))
	check(model != null, "the Unity package imports")
	if model == null:
		return
	var avatar := UnityAvatar.avatar_definition(avatar_file("seed-san/Models/new_seedsan_betterfbx.fbx.meta"))
	var human: Dictionary = model.get_meta("humanoid")
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var bone_of := func(b: String) -> String: return (human[b] as NodePath).get_concatenated_subnames()
	var upper_arm: String = bone_of.call("leftUpperArm")
	_rests_in_the_avatar_definitions_pose(sk, upper_arm, FileAccess.get_file_as_string(avatar_file("seed-san/Models/new_seedsan_betterfbx.fbx.meta")))
	check(human.size() == avatar.human.size() and avatar.human.keys().all(func(b: String) -> bool:
		var as_bone := UnityAvatar.vrm_bone(avatar.human[b])
		return human.has(as_bone) and sk.find_bone(bone_of.call(as_bone)) >= 0), "every bone the Avatar definition maps is a skeleton bone under its humanoid name (%d of %d)" % [human.size(), avatar.human.size()])
	check(bone_of.call("hips") == "hips" and bone_of.call("head") == "head" and bone_of.call("leftThumbMetacarpal") == "thumb_01_L", "the bones keep Unity's names, made fit for nodes: its de-duplicated head is the skeleton's head, its thumb proximal VRM's metacarpal")
	var path := ProjectSettings.globalize_path("user://seed-san.vrm")
	var report: Dictionary = model.get_meta("report")
	check((report["renderers drawn"] as Array).size() == 5, "all five of the model's renderers draw (%s)" % [report["renderers drawn"]])
	_report_prints_names_only_when_asked(report, model.name)
	_writes_expressions(model)
	var vrm_names := {}
	for b: String in human:
		if b in Vrm.BONES:
			vrm_names[bone_of.call(b)] = b
	var started := Time.get_ticks_usec()
	var scene := Avatar.read(UnityAvatar.write(model, path), true)
	print("unity package: written and read in %.0f ms" % ((Time.get_ticks_usec() - started) / 1000.0))
	check(scene != null, "the written VRM reads back as the avatar model")
	if scene == null:
		return
	_pose_puts_the_eyes_on_the_head(scene, "seed-san")
	_arms_join_shoulders_to_hands(scene, "seed-san")
	var fbx := avatar_file("seed-san/Models/new_seedsan_betterfbx.fbx")
	var reference := _imported(fbx)
	var skins := reference.find_children("*", "MeshInstance3D", true, false).filter(func(mi: MeshInstance3D) -> bool: return mi.skin != null)
	var shapes := {}
	for mi: MeshInstance3D in skins:
		shapes[mi.mesh] = mi.mesh.get_blend_shape_count()
	check(skins.size() == 5 and shapes.values().has(43), "the engine's import of the FBX has five skinned meshes and the face's 43 blend shapes")
	_keeps_skins_and_shapes(scene, "seed-san", shapes.values().reduce(func(n: int, k: int) -> int: return n + k, 0))
	_skin_bends_as(scene, "seed-san", _scene_skin.bind(reference, vrm_names))
	reference.free()
	var lowered := ProjectSettings.globalize_path("user://seed-san-lowered/Models")
	DirAccess.make_dir_recursive_absolute(lowered)
	DirAccess.copy_absolute(avatar_file("seed-san/Models/new_seedsan_betterfbx.fbx"), lowered.path_join("new_seedsan_betterfbx.fbx"))
	var meta := FileAccess.get_file_as_string(avatar_file("seed-san/Models/new_seedsan_betterfbx.fbx.meta"))
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
		_rests_in_the_avatar_definitions_pose(moved_sk, upper_arm, meta)
		moved.free()
	var empty := ProjectSettings.globalize_path("user://no-humanoid")
	DirAccess.make_dir_recursive_absolute(empty)
	check(UnityAvatar.avatar_scene(empty) == null, "a package with no humanoid model imports as nothing")
	_rest_weights_survive_the_vrm()


func _rest_weights_survive_the_vrm() -> void:
	var model := UnityAvatar.avatar_scene(avatar_file("seed-san"))
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D) -> bool: return m.get_blend_shape_count() > 1)[0]
	var shape: StringName = mi.mesh.get_blend_shape_name(1)
	mi.set_blend_shape_value(1, 0.6)
	var worn_name := str(mi.name)
	var bytes := UnityAvatar.write(model, ProjectSettings.globalize_path("user://seed-san.vrm"), {"converter": UnityAvatar.source()})
	var stamp: Variant = Vrm.json_chunk(bytes).asset.get("extras", {}).get("converter")
	var head := []
	var status := []
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://.."), "rev-parse", "HEAD"], head)
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://.."), "status", "--porcelain", "--untracked-files=no"], status)
	check(str(stamp) == str({"commit": str(head[0]).strip_edges(), "dirty": str(status[0]).strip_edges() != ""}), "the VRM names the converter checkout that wrote it: %s" % stamp)
	var a := Avatar.open(Avatar.read(bytes), Color.WHITE)
	var worn: Array = a.find_children(worn_name, "MeshInstance3D", true, false)
	var at := -1.0 if worn.size() != 1 else (worn[0] as MeshInstance3D).get_blend_shape_value((worn[0] as MeshInstance3D).find_blend_shape_by_name(shape))
	check(is_equal_approx(at, 0.6), "a shape saved at 0.6 is worn at 0.6, not %f" % at)
	a.free()


func _springs_survive_a_rewrite(file: String) -> void:
	var path := ProjectSettings.globalize_path("user://rewritten.vrm")
	var read := func(bytes: PackedByteArray) -> Node3D: return Vrm.read(bytes, func(_size: Vector2i) -> bool: return true, func(_state: GLTFState) -> bool: return true, func(_image: Image, _layer: String) -> void: pass)
	var first: Node3D = read.call(FileAccess.get_file_as_bytes(file))
	var turn := 0.0
	for chain: Dictionary in first.get_meta("springs").springs:
		for joint: Dictionary in chain.joints:
			turn += 0.01
			joint["settled"] = Quaternion(Vector3.RIGHT, turn)
	var before := _springs_by_bone(first)
	Vrm.write(first, path)
	first.free()
	var second: Node3D = read.call(FileAccess.get_file_as_bytes(path))
	var after := _springs_by_bone(second)
	second.free()
	var turns := [_settled(before), _settled(after)]
	var off := 0.0
	for i in mini(turns[0].size(), turns[1].size()):
		off = maxf(off, (turns[0][i] as Quaternion).angle_to(turns[1][i]))
	check(not (before.springs as Array).is_empty() and str(before) == str(after) and turns[0].size() == turns[1].size() and off < 2e-3, "%s's springs survive a write, each joint's settled rotation %.6f rad off at worst: %s, then %s" % [file.get_file(), off, before, after])


func _settled(springs: Dictionary) -> Array:
	var turns := []
	for chain: Dictionary in springs.springs:
		for joint: Dictionary in chain.joints:
			turns.append(joint.settled)
			joint.erase("settled")
	return turns


## Each node index swapped for the bone its "spring_N" names, "" for none.
func _springs_by_bone(root: Node3D) -> Dictionary:
	var human: Dictionary = root.get_meta("humanoid")
	var bone := func(n: int) -> String: return (human["spring_%d" % n] as NodePath).get_concatenated_subnames() if n >= 0 else ""
	var springs: Dictionary = root.get_meta("springs").duplicate(true)
	for chain: Dictionary in springs.springs:
		chain.center = bone.call(chain.center)
		for joint: Dictionary in chain.joints:
			joint.node = bone.call(joint.node)
	for collider: Dictionary in springs.colliders:
		collider.node = bone.call(collider.node)
	return springs


## The sample binds its skin with the arms lowered; its Avatar definition holds the T-pose.
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


func _writes_expressions(model: Node3D) -> void:
	var worn: Node3D = model.duplicate()
	var mi: MeshInstance3D = worn.find_children("*", "MeshInstance3D", true, false)[0]
	var shape: String = mi.mesh.get_blend_shape_name(mi.mesh.get_blend_shape_count() - 1)
	worn.set_meta("faces", {"happy": [{"node": mi.name, "shape": shape, "weight": 0.5}], "grimace": [{"node": mi.name, "shape": shape, "weight": 1.0}], "none": [{"node": mi.name, "shape": "no such shape", "weight": 1.0}]})
	var json: Dictionary = Vrm.json_chunk(UnityAvatar.write(worn, ProjectSettings.globalize_path("user://seed-san.vrm")))
	var used: Array = json.get("extensionsUsed", [])
	check((json.extensions as Dictionary).keys().all(func(e: String) -> bool: return used.has(e)), "the file lists the extensions it carries: %s of %s" % [used, (json.extensions as Dictionary).keys()])
	var expressions: Dictionary = json.extensions.VRMC_vrm.expressions
	var target := func(b: Dictionary) -> String: return json.meshes[json.nodes[int(b.node)].mesh].extras.targetNames[int(b.index)]
	var happy: Array = expressions.preset.get("happy", {}).get("morphTargetBinds", [])
	check(happy.size() == 1 and target.call(happy[0]) == shape and happy[0].weight == 0.5, "a preset binds its shape's morph target at its weight: %s" % [expressions])
	check(expressions.custom.has("grimace") and expressions.preset.size() == 1 and expressions.custom.size() == 1, "a name no preset has is custom, and an expression binding nothing is left out: %s" % [expressions])


func _physbones_keep_whose_hands_touch_them() -> void:
	var cases := [[{}, ["wearer", "others"]], [{"allowGrabbing": "0"}, []], [{"allowGrabbing": "1"}, ["wearer", "others"]], [{"allowGrabbing": "2", "grabFilter": {"allowSelf": "1", "allowOthers": "0"}}, ["wearer"]], [{"allowGrabbing": "2", "grabFilter": {"allowSelf": "0", "allowOthers": "1"}}, ["others"]]]
	for c: Array in cases:
		check(UnityAvatar._filter(c[0], "allowGrabbing", "grabFilter") == c[1], "a PhysBone's %s lets %s grab it" % [c[0], c[1]])
	for bits in 4:
		var spring := SpringDefinition.hands({"extras": {"collide": Vrm._hands(bits), "grab": Vrm._hands(3 - bits)}}, {})
		check(spring.collide == bits and spring.grab == 3 - bits, "hand bits %d survive the file" % bits)


func _imported(fbx: String) -> Node3D:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.create_animations = false
	doc.append_from_file(fbx, state)
	return doc.generate_scene(state)


## `expected(a)` maps each rest position to where the source's skin puts it over `a`'s posed bones. Bent elbows and
## knees move a vertex two bones share, which a rigid part or a lost or reordered bind misplaces.
func _skin_bends_as(scene: PackedScene, what: String, expected: Callable) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
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
		var skin := _skinned(a, mi)
		for v in skin[0].size():
			var posed: Vector3 = skin[1][v]
			var there: Variant = want.get(skin[0][v].snappedf(1e-5))
			count += 1
			if there == null:
				unmatched += 1
				continue
			worst = maxf(worst, (there as Array).map(func(p: Vector3) -> float: return p.distance_to(posed)).min())
			moved = maxf(moved, posed.distance_to(skin[0][v]))
	print("%s: %d vertices bent at elbows and knees, %.6f m from the source's skin at worst, moved up to %.2f m" % [what, count, worst, moved])
	check(count > 0 and unmatched == 0, "%s: every vertex is one of the source's (%d of %d unmatched)" % [what, unmatched, count])
	check(worst < 1e-3, "%s: bent at elbows and knees, every vertex sits where the source's skin puts it (%.6f m off at worst)" % [what, worst])
	check(moved > 0.1, "%s: and the bend moves the body (%.2f m at most)" % [what, moved])
	a.free()


func _gltf_skin(a: Avatar, bytes: PackedByteArray, what: String) -> Dictionary:
	var json: Dictionary = Vrm.json_chunk(bytes)
	var bin := bytes.slice(28 + bytes.decode_u32(12))
	var sk := a._skeleton
	var at := Meshes.relative(sk, a._model)
	# Godot's glTF reader makes a bone name's forbidden characters underscores.
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


## `renamed` maps a source bone name to the worn file's.
func _scene_skin(a: Avatar, source: Node3D, renamed: Dictionary) -> Dictionary:
	var sk := a._skeleton
	var at := Meshes.relative(sk, a._model)
	var out := {}
	for mi: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		var theirs := mi.get_node(mi.skeleton) as Skeleton3D
		var joints: Array[Transform3D] = []
		for i in mi.skin.get_bind_count():
			var b := Meshes.bind_bone(mi.skin, i, theirs)
			var name := theirs.get_bone_name(b).validate_node_name()
			joints.append(at * sk.get_bone_global_pose(sk.find_bone(renamed.get(name, name))) * mi.skin.get_bind_pose(i))
		var skin := _skin(mi, joints)
		for v in skin[0].size():
			out.get_or_add(skin[0][v].snappedf(1e-5), []).append(skin[1][v])
	return out


func _node_transform(node: Dictionary) -> Transform3D:
	if node.has("matrix"):
		var m: Array = node.matrix
		return Transform3D(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]), Vector3(m[8], m[9], m[10]), Vector3(m[12], m[13], m[14]))
	var r: Array = node.get("rotation", [0, 0, 0, 1])
	var t: Array = node.get("translation", [0, 0, 0])
	var s: Array = node.get("scale", [1, 1, 1])
	return Transform3D(Basis(Quaternion(r[0], r[1], r[2], r[3])).scaled_local(Vector3(s[0], s[1], s[2])), Vector3(t[0], t[1], t[2]))


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


func _a_later_physbone_over_the_same_bones_is_shadowed() -> void:
	var chain := func(nodes: Array) -> Dictionary: return {"joints": nodes.map(func(n: int) -> Dictionary: return {"node": n, "physbone": {}})}
	var first: Dictionary = chain.call([1, 2])
	var further: Dictionary = chain.call([1, 2, 3])
	var kept := SpringRuntime.unshadowed([first, chain.call([1, 2]), further])
	check(kept.size() == 2 and kept[0] == first and kept[1] == further, "a later chain over the same bones is shadowed, one reaching further is not: %s" % [kept])
	var root := Node3D.new()
	root.set_meta("humanoid", {})
	root.set_meta("springs", {"springs": [first, further]})
	Avatar._rank_springs(root)
	check(root.get_meta("springs").springs == [first, further], "the chains stay in the file's order, the first PhysBone on a bone first")
	root.free()


func _import_settles_each_spring_chain() -> void:
	var root := Node3D.new()
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	for b in 3:
		sk.add_bone("b%d" % b)
		sk.set_bone_parent(b, b - 1)
	sk.set_bone_rest(2, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0.1)))
	sk.reset_bone_poses()
	var physbone := {"version": "1.1", "integration": "simplified", "pull": 0.2, "spring": 0.2, "stiffness": 0.0, "gravity": 1.0, "immobileType": "allMotion"}
	var springs := SpringDefinition.read({"nodes": [{}, {}, {}], "extensions": {"VRMC_springBone": {"springs": [{"joints": [{"node": 1, "extras": {"physbone": physbone}}, {"node": 2}]}]}}})
	root.set_meta("springs", springs)
	root.set_meta("humanoid", {"spring_1": NodePath("Skeleton3D:b1"), "spring_2": NodePath("Skeleton3D:b2")})
	UnityAvatar.settle(root)
	var settled: Quaternion = springs.springs[0].joints[0].get("settled", Quaternion.IDENTITY)
	var hangs := settled * Vector3.BACK
	check(hangs.y < -0.9, "a bone its gravity pulls settles hanging down: %s" % hangs)
	check(sk.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY) and root.get_parent() == null, "the bones go back to rest and the root leaves the tree")
	root.free()


func _simulates_the_longest_chains_within_the_limit() -> void:
	var lengths := func(root: Node3D) -> Array:
		var chains: Array = root.get_meta("springs").springs
		var shown := func(c: int) -> bool: return (chains[c].drawn_by as Array).any(func(p: NodePath) -> bool: return Avatar._shown(root.get_node(p), root))
		var run := Avatar.running(chains, shown)
		return range(chains.size()).filter(func(c: int) -> bool: return run.has(c)).map(func(c: int) -> int: return chains[c].joints.size())
	var setup := func(chains_of: Array) -> Node3D:
		var root := Node3D.new()
		var sk := Skeleton3D.new()
		sk.name = "Skeleton3D"
		root.add_child(sk)
		var human := {}
		var chains := []
		for shape: Array in chains_of:
			var joints := []
			for i in shape[0]:
				var b := sk.get_bone_count()
				sk.add_bone("b%d" % b)
				if i > 0:
					sk.set_bone_parent(b, b - 1)
					sk.set_bone_rest(b, Transform3D(Basis(), Vector3(0, -shape[1], 0)))
				human["spring_%d" % b] = NodePath("Skeleton3D:b%d" % b)
				joints.append({"node": b, "settled": Quaternion(Vector3.RIGHT, 0.5)})
			chains.append({"joints": joints})
		human["hips"] = NodePath("Skeleton3D:b0")
		root.set_meta("humanoid", human)
		root.set_meta("springs", {"springs": chains})
		return root
	var n := Avatar.MAX_SPRING_JOINTS
	var root: Node3D = setup.call([[3, 0.1], [n - 2, 0.1], [2, 0.1], [n, 0.1]])
	var shared: Dictionary = root.get_meta("springs").springs[0].joints[0]
	root.get_meta("springs").springs[3].joints[0] = shared.duplicate()
	Avatar._rank_springs(root)
	check(lengths.call(root) == [n], "the longest chain fills the limit and the rest do not run")
	var sk: Skeleton3D = root.get_node("Skeleton3D")
	var turned := func(bone: int) -> bool: return sk.get_bone_rest(bone).basis.get_rotation_quaternion().is_equal_approx(Quaternion(Vector3.RIGHT, 0.5))
	check(turned.call(1) and turned.call(3 + n - 2), "a bone only chains left out move rests at its settled rotation")
	check((root.get_meta("springs").springs as Array).size() == 1, "a file with no menu keeps only the chains that run")
	check(not turned.call(0), "a bone a kept chain moves keeps its own rest")
	root.free()
	root = setup.call([[n, 0.1], [2, 0.1], [2, 0.1]])
	var off := {"length": 1.0, "curves": [{"target": 0, "step": false, "keys": [[0, 0.0]]}]}
	root.set_meta("expressions", {"parameters": [], "targets": [{"effect": "switch", "default": 1.0}], "clips": [off], "layers": [{"weight": 1.0, "default": 0, "states": [{"motion": {"clip": 0}, "transitions": []}]}], "springs": [{"joints": [n, n + 1], "when": [[0, 1]]}]})
	Avatar._rank_springs(root)
	var bones: Skeleton3D = root.get_node("Skeleton3D")
	var settled := func(bone: int) -> bool: return bones.get_bone_rest(bone).basis.get_rotation_quaternion().is_equal_approx(Quaternion(Vector3.RIGHT, 0.5))
	check(not settled.call(n + 1) and settled.call(n + 3), "a chain left out that the controller's first state switches off keeps its authored rest; one it leaves on rests where it settles")
	var kept: Array = root.get_meta("springs").springs
	check(kept.size() == 3 and (kept[2].joints[1].get("authored", Quaternion(Vector3.RIGHT, 0.5)) as Quaternion).is_equal_approx(Quaternion.IDENTITY) and not kept[1].joints[1].has("authored"), "a file with a menu keeps every chain, a joint rested where it settles keeping its authored rotation to swing about")
	root.free()
	root = setup.call([[3, 0.1], [n - 2, 0.1], [2, 0.1]])
	Avatar._rank_springs(root)
	check(lengths.call(root) == [n - 2, 2], "chains are kept longest first while they fit")
	root.free()
	root = setup.call([[4, 0.2], [10, 0.01], [n - 10, 0.01]])
	Avatar._rank_springs(root)
	check(lengths.call(root) == [4, n - 10], "a chain of few joints reaching far outranks one of many that reaches less")
	root.free()
	root = setup.call([[n - 20, 0.1], [30, 0.01]])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	for chain in 2:
		var skin := Skin.new()
		skin.add_named_bind("b%d" % (0 if chain == 0 else n - 20), Transform3D())
		var outfit := Node3D.new()
		outfit.visible = chain == 1
		root.add_child(outfit)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.skin = skin
		outfit.add_child(mi)
		mi.skeleton = mi.get_path_to(root.get_node("Skeleton3D"))
	Avatar._rank_springs(root)
	check(lengths.call(root) == [30], "a chain moving only a hidden mesh ranks after one moving a shown mesh")
	root.free()
	root = setup.call([[n - 20, 0.1], [30, 0.01]])
	var carrier := BoneAttachment3D.new()
	root.get_node("Skeleton3D").add_child(carrier)
	carrier.bone_idx = n + 9
	carrier.add_child(MeshInstance3D.new())
	Avatar._rank_springs(root)
	check(lengths.call(root) == [30], "a mesh riding a chain's tip unskinned shows that chain")
	root.free()
	root = setup.call([[2, 0.01], [n - 1, 0.005]])
	root.get_meta("springs").springs[0].end_length = 0.5
	Avatar._rank_springs(root)
	check(lengths.call(root) == [2], "a chain's tail past its last joint counts toward its length")
	root.free()


func _a_switch_stops_and_restarts_a_chain_as_vrchat_does(early: bool) -> void:
	var model := Node3D.new()
	var anchor := Node3D.new()
	model.add_child(anchor)
	var bone := Node3D.new()
	anchor.add_child(bone)
	var tail := Node3D.new()
	tail.position = Vector3(0, 0, 0.1)
	bone.add_child(tail)
	root.add_child(model)
	var physbone := {"version": "1.1", "integration": "simplified", "pull": 0.2, "spring": 0.2, "stiffness": 0.2, "gravity": 0.0, "gravityFalloff": 0.0, "immobile": 0.0, "immobileType": "allMotion", "maxSquish": 0.0, "maxStretch": 0.0, "stretchMotion": 0.0, "radius": [0.0, 0.02]}
	var collider := {"node": 2, "shape": {"sphere": {"offset": [0, -0.03, 0.1], "radius": 0.02}}}
	var definition := SpringDefinition.read({"nodes": [{}, {}, {}], "extensions": {"VRMC_springBone": {"springs": [{"joints": [{"node": 0, "extras": {"physbone": physbone}}, {"node": 1}], "colliderGroups": [0]}], "colliders": [collider], "colliderGroups": [{"colliders": [0]}]}}})
	definition.springs[0].drawn_by = []
	var clip := func(value: float) -> Dictionary: return {"length": 1.0, "curves": [{"target": 0, "step": false, "keys": [[0, value]]}]}
	model.set_meta("expressions", {"parameters": [{"name": "Tail", "type": "bool", "default": 0.0, "saved": true}], "targets": [{"effect": "switch", "default": 1.0}], "clips": [clip.call(0.0), clip.call(1.0)],
		"layers": [{"weight": 1.0, "default": 0, "states": [
			{"motion": {"clip": 0}, "transitions": [{"to": 1, "conditions": [{"parameter": "Tail", "mode": "if"}]}]},
			{"motion": {"clip": 1}, "transitions": [{"to": 0, "conditions": [{"parameter": "Tail", "mode": "ifNot"}]}]}]}],
		"springs": [{"joints": [0, 1], "when": [[0, 1]]}]})
	var a := Avatar.new()
	a._model = model
	a.expressions = ExpressionPlayer.new(model)
	a.expressions.switched.connect(a._budget)
	model.add_child(a.expressions)
	if early:
		a.expressions.state.put("Tail", 1.0)
		await frames(3)
	a.springs = SpringRuntime.new(definition, {0: bone, 1: tail, 2: anchor})
	var authored := tail.global_position
	a._prime()
	a._budget()
	var held := tail.global_position
	var what := "already on when the springs are made" if early else "off until switched"
	check(held.y > authored.y + 0.005 and held.distance_to(anchor.global_transform * Vector3(0, -0.03, 0.1)) > 0.039, "%s: the start-up steps lift a chain its first state switches off clear of the collider its authored pose overlaps: %s from %s" % [what, held, authored])
	a.springs.colliders[0].offset = Vector3(0, -1, 0)
	a.springs.colliders[0].tail = Vector3(0, -1, 0)
	if not early:
		check(a.springs.idle.has(0), "a chain switched off is idle")
		for i in 30:
			a.springs.advance(1.0 / 60.0)
		check(tail.global_position.is_equal_approx(held), "switched off it holds the pose it stopped in: %s" % tail.global_position)
		a.expressions.state.put("Tail", 1.0)
		await frames(3)
	check(not a.springs.idle.has(0), "%s: the switch has it running" % what)
	for i in 120:
		a.springs.advance(1.0 / 60.0)
	check(tail.global_position.distance_to(held) < 1e-4, "%s: it swings about the pose it was left in, not the authored one: %s, held %s, authored %s" % [what, tail.global_position, held, authored])
	bone.rotate_x(0.4)
	a._budget()
	for i in 240:
		a.springs.advance(1.0 / 60.0)
	check(tail.global_position.distance_to(held) < 0.005, "%s: choosing again leaves a running chain its rest: %s, held %s" % [what, tail.global_position, held])
	a.free()
	model.free()


func _a_settled_joint_swings_about_its_authored_rotation() -> void:
	var model := Node3D.new()
	var anchor := Node3D.new()
	model.add_child(anchor)
	var bone := Node3D.new()
	bone.rotation.x = 0.5
	anchor.add_child(bone)
	var tail := Node3D.new()
	tail.position = Vector3(0, 0, 0.1)
	bone.add_child(tail)
	root.add_child(model)
	var physbone := {"version": "1.1", "integration": "simplified", "pull": 0.2, "spring": 0.2, "stiffness": 0.2, "gravity": 0.0, "gravityFalloff": 0.0, "immobile": 0.0, "immobileType": "allMotion", "maxSquish": 0.0, "maxStretch": 0.0, "stretchMotion": 0.0, "radius": [0.0, 0.0]}
	var definition := SpringDefinition.read({"nodes": [{}, {}, {}], "extensions": {"VRMC_springBone": {"springs": [{"joints": [{"node": 0, "extras": {"physbone": physbone}}, {"node": 1}]}]}}})
	definition.springs[0].joints[0].authored = Quaternion.IDENTITY
	definition.springs[0].drawn_by = []
	var a := Avatar.new()
	a._model = model
	a.springs = SpringRuntime.new(definition, {0: bone, 1: tail, 2: anchor})
	a._prime()
	a._budget()
	check(tail.global_position.is_equal_approx(Vector3(0, 0, 0.1).rotated(Vector3.RIGHT, 0.5)), "until it runs the joint shows its settled pose: %s" % tail.global_position)
	for i in 240:
		a.springs.advance(1.0 / 60.0)
	check(tail.global_position.distance_to(Vector3(0, 0, 0.1)) < 1e-3, "with no gravity it swings back to its authored rotation: %s" % tail.global_position)
	a.free()
	model.free()


func _switched_off_physics_stays_out() -> void:
	var root := Node3D.new()
	root.set_meta("expressions", {"targets": [{"effect": "switch", "default": 0.0}, {"effect": "switch", "default": 1.0}], "springs": [{"joints": [3.0, 4.0], "when": [[0, 1]]}, {"joints": [5.0, 6.0], "when": [[1, 1]]}, {"joints": [3.0, 7.0], "when": [[1, 1]]}], "colliders": [{"collider": 0.0, "when": [[0, 1]]}]})
	root.set_meta("springs", {"springs": [{"joints": [{"node": 3}, {"node": 4}], "colliders": [0, 1]}, {"joints": [{"node": 5}, {"node": 6}], "colliders": [0, 1]}, {"joints": [{"node": 3}, {"node": 7}], "colliders": [0, 1]}], "colliders": [{}, {}]})
	Avatar._switched_off(root)
	var springs: Array = root.get_meta("springs").springs
	var ends := springs.map(func(c: Dictionary) -> int: return c.joints[-1].node)
	check(ends == [6, 7], "the chain switched off is out; the one switched on stays, and so does one sharing the first bone of the one off: %s" % [ends])
	check(springs.all(func(c: Dictionary) -> bool: return c.colliders == [1]), "the collider switched off presses on nothing: %s" % [springs])
	root.free()
	root = Node3D.new()
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	var human := {"hips": NodePath("Skeleton3D:b0")}
	for b in 8:
		sk.add_bone("b%d" % b)
		human["spring_%d" % b] = NodePath("Skeleton3D:b%d" % b)
	sk.set_bone_rest(4, Transform3D(Basis(), Vector3(0, -0.1, 0)))
	root.set_meta("humanoid", human)
	var turn := Quaternion(Vector3.RIGHT, 0.5)
	root.set_meta("expressions", {"targets": [{"effect": "switch", "default": 0.0}, {"effect": "switch", "default": 1.0}], "springs": [{"joints": [3.0, 4.0], "when": [[0, 1]]}, {"joints": [3.0, 7.0], "when": [[1, 1]]}]})
	root.set_meta("springs", {"springs": [{"joints": [{"node": 3, "settled": turn}, {"node": 4, "settled": turn}], "colliders": []}, {"joints": [{"node": 3}, {"node": 7}], "colliders": []}], "colliders": []})
	Avatar._switched_off(root)
	var left: Array = root.get_meta("left_out")
	check(left.size() == 1 and sk.get_bone_rest(4).basis.get_rotation_quaternion().is_equal_approx(Quaternion.IDENTITY), "a chain left out at load keeps its bones' authored rests while its switch is off: %s" % [left])
	var authored := {}
	Avatar.rest_left_out(sk, human, left, {}, {0: true}, authored)
	check(sk.get_bone_rest(4).basis.get_rotation_quaternion().is_equal_approx(turn) and sk.get_bone_pose_rotation(4).is_equal_approx(turn) and sk.get_bone_rest(4).origin.is_equal_approx(Vector3(0, -0.1, 0)), "switched on, a bone only it moves rests and stands at its settled rotation, as VRChat shows the chain running")
	check(sk.get_bone_rest(3).basis.get_rotation_quaternion().is_equal_approx(Quaternion.IDENTITY), "a bone a kept chain moves keeps its own rest")
	Avatar.rest_left_out(sk, human, left, {0: true}, {}, authored)
	check(sk.get_bone_rest(4).basis.get_rotation_quaternion().is_equal_approx(Quaternion.IDENTITY) and sk.get_bone_pose_rotation(4).is_equal_approx(Quaternion.IDENTITY), "switched off again, it returns to its authored rotation")
	var other := Quaternion(Vector3.UP, 0.3)
	var twice := [{"joints": [{"node": 4, "settled": turn, "shared": false}]}, {"joints": [{"node": 4, "settled": other, "shared": false}]}]
	Avatar.rest_left_out(sk, human, twice, {0: true}, {0: true, 1: true}, authored)
	Avatar.rest_left_out(sk, human, twice, {1: true}, {0: true}, authored)
	check(sk.get_bone_pose_rotation(4).is_equal_approx(turn), "a bone two chains left out move follows whichever one a switch has on, whatever order they turn in")
	Avatar.rest_left_out(sk, human, twice, {0: true, 1: true}, {1: true}, authored)
	check(sk.get_bone_pose_rotation(4).is_equal_approx(Quaternion.IDENTITY), "and its authored rotation once both are off")
	root.free()
	var pair := [{"joints": [{"node": 1}, {"node": 2}]}, {"joints": [{"node": 1}, {"node": 2}, {"node": 3}]}]
	var moved := Avatar.movers(pair, [{"joints": [1, 2]}, {"joints": [1, 2]}, {"joints": [9]}])
	check(Avatar.stopped(moved, [false, true, false]).is_empty(), "a segment an off PhysBone and an on one both move runs")
	check(Avatar.stopped(moved, [false, false, false]).keys() == [0], "a chain reaching past its switched-off PhysBone runs; one wholly under it is off")
	var full := range(Avatar.MAX_SPRING_JOINTS).map(func(i: int) -> Dictionary: return {"node": i})
	var both := [{"joints": full, "length": 2.0}, {"joints": full, "length": 1.0}]
	check(Avatar.running(both, func(_c: int) -> bool: return false).keys() == [0] and Avatar.running(both, func(_c: int) -> bool: return false, {0: true}).keys() == [1], "a chain switched off frees its joints for the next")


func _outlined_materials_draw_their_hull() -> void:
	var root := Node3D.new()
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var kinds: Array[StandardMaterial3D] = [StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	kinds[0].set_meta("extras", {"outline": true})
	kinds[1].set_meta("extras", {"outline": true})
	kinds[1].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	for m in kinds:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	check(not Avatar._outlined(root), "a material marked outlined without an outline layer refuses the model")
	var layer := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	root.set_meta("expressions", {"looks": {"outline": layer, "outlineWidth": 0.002}})
	check(Avatar._outlined(root), "a model whose looks carry the layer is drawn")
	var hull := kinds[0].next_pass as ShaderMaterial
	check(hull != null and hull.shader == Avatar.OUTLINE and is_equal_approx(hull.get_shader_parameter("width"), 0.002), "an opaque outlined material draws its hull whole, as wide as the looks say")
	check(kinds[1].next_pass is ShaderMaterial and (kinds[1].next_pass as ShaderMaterial).shader == Avatar.OUTLINE_CUT, "a cut-out one draws its hull cut out")
	check(kinds[2].next_pass == null, "a material not marked draws no hull")
	Avatar.show_outlines(false)
	check(kinds[0].next_pass == null and kinds[1].next_pass == null, "a step without outlines draws no hull")
	Avatar.show_outlines(true)
	check(kinds[0].next_pass == hull, "a step with them draws it again")
	root.free()


func _many_surfaces_draw_with_their_outlines() -> void:
	var root := Node3D.new()
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	var human := {}
	for bone in Avatar.NEEDS:
		human[bone] = NodePath("Skeleton3D:%s" % bone)
		sk.add_bone(bone)
	root.set_meta("humanoid", human)
	root.set_meta("expressions", {"looks": {"outline": Image.create_empty(4, 4, false, Image.FORMAT_RGBA8), "outlineWidth": 0.002}})
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var surfaces := 120
	for i in surfaces:
		var m := StandardMaterial3D.new()
		m.set_meta("extras", {"outline": true})
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(i, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	sk.add_child(mi)
	var scene := Avatar.model(root)
	check(scene != null, "a model of %d outlined surfaces loads" % surfaces)
	if scene == null:
		return
	var a := Avatar.open(scene, Color.WHITE)
	var hulled := 0
	for each: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		for i in each.mesh.get_surface_count():
			hulled += int(each.mesh.surface_get_material(i).next_pass is ShaderMaterial)
	check(hulled == surfaces, "each of its %d surfaces draws its outline (%d)" % [surfaces, hulled])
	a.free()
	var state := GLTFState.new()
	var gm := GLTFMesh.new()
	gm.mesh = ImporterMesh.new()
	for i in RenderingServer.MAX_MESH_SURFACES + 1:
		gm.mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, StandardMaterial3D.new())
	state.set_meshes([gm])
	check(not Avatar.shape(state), "a mesh of more materials than the renderer draws of one mesh is refused, not drawn in part")


func _within_limits(scene: PackedScene, what: String, json: Dictionary) -> void:
	var targets := 0
	var authored := 0
	for m: Dictionary in json.meshes:
		targets += (m.primitives[0] as Dictionary).get("targets", []).size()
		for p: Dictionary in m.primitives:
			authored += int(json.accessors[int(p.get("indices", p.attributes.POSITION))].count) / 3
	_keeps_skins_and_shapes(scene, what, targets)
	var a := Avatar.open(scene, Color.WHITE)
	var both_sides := {}
	for m: Dictionary in json.get("materials", []):
		both_sides[m.get("name", "")] = m.get("doubleSided", false)
	var triangles := 0
	var plain := 0
	var materials := 0
	var textures := {}
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.albedo_texture != null:
				textures[m.albedo_texture] = true
			if m != null:
				plain += 1 if m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX and m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC and not m.normal_enabled and not m.emission_enabled and m.cull_mode == (BaseMaterial3D.CULL_DISABLED if both_sides.get(m.resource_name, false) else BaseMaterial3D.CULL_BACK) and m.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA] else 0
				materials += 1
			triangles += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	check(triangles == authored, "%s keeps every triangle its file has (%d of %d)" % [what, triangles, authored])
	check(plain == materials, "%s draws its colour alone, sampled anisotropically, lit once a vertex, both sides only where its file says, cut out or blended where see-through (%d of %d)" % [what, plain, materials])
	check(not textures.is_empty(), "%s keeps its textures" % what)
	for tex: Texture2D in textures:
		check(tex.get_image().has_mipmaps(), "%s keeps its textures mipmapped (%dx%d)" % [what, tex.get_width(), tex.get_height()])
	a.free()


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
	var seen: Vector3 = head * a._eye_to_head.affine_inverse().origin
	check(seen.distance_to(eyes.origin) < 0.001, "%s: eyes sit at the tracked head (%s vs %s)" % [what, seen, eyes.origin])
	var face: Vector3 = head.basis * a._joints.head.rest.basis.inverse() * (a._model.get_meta("forward") as Vector3)
	check(face.normalized().dot(-eyes.basis.z) > 0.99, "%s: the face looks where the head looks" % what)
	var palms := [a.bone("leftHand") * a._arms[0].palm, a.bone("rightHand") * a._arms[1].palm]
	check(palms[0].distance_to(l.origin) < 0.001 and palms[1].distance_to(r.origin) < 0.001, "%s: the middles of the palms sit where the controllers' grips are (%s vs %s)" % [what, palms[0], l.origin])
	if a._joints.has("leftMiddleProximal"):
		var back := (l.origin - a.bone("leftHand").origin).dot(-l.basis.z)
		check(back > 0.02, "%s: the wrist sits %.3f m back from the palm, toward the elbow, not on the grip" % [what, back])
	for s in 2:
		var side: String = ["left", "right"][s]
		var hand := a.bone(side + "Hand")
		var along: Vector3 = hand.basis * (a._joints[side + "Hand"].rest.basis.inverse() * (a._joints[side + "Hand"].rest.origin - a._joints[side + "LowerArm"].rest.origin))
		var held: Transform3D = [l, r][s]
		check(along.normalized().dot(-held.basis.z) > 0.99, "%s: the %s hand points where its controller points" % [what, side])
	check(a.bone("hips").origin.y < eyes.origin.y - 0.4, "%s: the body hangs below the head" % what)
	var faced: Basis = a.bone("hips").basis * a._joints.hips.rest.basis.inverse() * a._facing.inverse()
	var tipped := Basis.from_euler(Vector3(0.5, 1.1, 0.3))
	var neck := Torso.NECK * a.eye_height / Rig.EYE
	var tilted := Transform3D(tipped, Vector3(1, a.eye_height, 1) + Basis(Vector3.UP, 1.1) * neck - tipped * neck)
	a.pose(tilted, l, r)
	var hips: Basis = a.bone("hips").basis * a._joints.hips.rest.basis.inverse()
	check(hips.y.is_equal_approx(Vector3.UP), "%s: the body stays upright when the head tips" % what)
	var ahead: Vector3 = hips * a._facing.inverse() * Vector3.FORWARD
	var was := faced * Vector3.FORWARD
	check(Vector2(ahead.x, ahead.z).normalized().is_equal_approx(Vector2(was.x, was.z).normalized()), "%s: and keeps facing as it was while the head turns within a neck's reach" % what)
	a.pose(Transform3D(Basis(Vector3.UP, 0.7 + Torso.TURN + 0.3), tilted.origin), l, r)
	hips = a.bone("hips").basis * a._joints.hips.rest.basis.inverse()
	ahead = hips * a._facing.inverse() * Vector3.FORWARD
	check(Vector2(ahead.x, ahead.z).normalized().is_equal_approx(Vector2(-sin(1.0), -cos(1.0))), "%s: and turns once the head turns further" % what)
	a.free()


## A vertex the head bones move wholly sits at the eyes; one they move in part, on the line from the eyes to where the
## other bones put it, so the eyes see only what the body places past the near clip.
func _headless_leaves_the_eyes_clear(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var whole := a._model.find_children("*", "MeshInstance3D", true, false)
	var swaying := a.swaying()
	var seen := a.headless()
	var eyes := Vector3(0, 1.6, 0)
	a.pose(Transform3D(Basis.IDENTITY, eyes), Transform3D(Basis.IDENTITY, Vector3(-0.25, 1.2, -0.4)), Transform3D(Basis.IDENTITY, Vector3(0.25, 1.2, -0.4)))
	var head := {}
	for b in a._skeleton.get_bone_count():
		var up := b
		while up >= 0 and up != a._joints.head.bone:
			up = a._skeleton.get_bone_parent(up)
		if up >= 0:
			head[b] = true
	var at := Meshes.relative(a._skeleton, a._model)
	var hands := [a.bone("leftHand").origin, a.bone("rightHand").origin]
	var gone := 0
	var off := 0.0
	var reach := [INF, INF]
	var meshes := whole.filter(func(mi: MeshInstance3D) -> bool: return mi.visible and mi not in swaying)
	for k in seen.size():
		var mi: MeshInstance3D = meshes[k]
		var p := _skinned(a, seen[k])[1]
		var binds: Array[Transform3D] = []
		for i in mi.skin.get_bind_count():
			binds.append(at * a._skeleton.get_bone_global_pose(Meshes.bind_bone(mi.skin, i, a._skeleton)) * mi.skin.get_bind_pose(i))
		var n := 0
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var vertex: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bone: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weight: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := bone.size() / vertex.size()
			for v in vertex.size():
				var body := Vector3.ZERO
				var w := 0.0
				for c in stride:
					var bind := bone[v * stride + c]
					if not head.has(Meshes.bind_bone(mi.skin, bind, a._skeleton)):
						body += binds[bind] * vertex[v] * weight[v * stride + c]
						w += weight[v * stride + c]
				var q := p[n]
				n += 1
				if w < 1e-3:
					gone += 1
					off = maxf(off, q.distance_to(eyes) * 0.1)
				elif w < 0.999 and q.distance_to(eyes) > Rig.NEAR:
					off = maxf(off, (q - eyes).normalized().cross((body / w - eyes).normalized()).length())
				for h in 2:
					reach[h] = minf(reach[h], q.distance_to(hands[h]))
	var full := [INF, INF]
	for mi: MeshInstance3D in whole:
		for q in _skinned(a, mi)[1]:
			for h in 2:
				full[h] = minf(full[h], q.distance_to(hands[h]))
	print("%s: %d meshes seen headless, %d vertices at the eyes, the rest %.5f rad off where the body puts them" % [what, seen.size(), gone, off])
	check(seen.size() == meshes.size() and seen.all(func(mi: MeshInstance3D) -> bool: return mi.get_node(mi.skeleton) == a._skeleton), "%s: the headless body is drawn on the avatar's own skeleton" % what)
	check(gone > 0, "%s: headless, the head is drawn at the eyes" % what)
	check(off < deg_to_rad(0.3), "%s: and every vertex shows within a third of a degree of where the body's own bones put it (%.5f rad off)" % [what, off])
	check(reach == full, "%s: headless, the body still reaches both hands" % what)
	a.free()


## [rest, posed], in the avatar's space.
func _skinned(a: Avatar, mi: MeshInstance3D) -> Array[PackedVector3Array]:
	var at := Meshes.relative(a._skeleton, a._model)
	var binds: Array[Transform3D] = []
	for i in mi.skin.get_bind_count():
		binds.append(at * a._skeleton.get_bone_global_pose(Meshes.bind_bone(mi.skin, i, a._skeleton)) * mi.skin.get_bind_pose(i))
	return _skin(mi, binds)


static func _skin(mi: MeshInstance3D, joints: Array[Transform3D]) -> Array[PackedVector3Array]:
	var rest := PackedVector3Array()
	var posed := PackedVector3Array()
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		var vertex: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bone: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weight: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := bone.size() / vertex.size()
		for v in vertex.size():
			var p := Vector3.ZERO
			for c in stride:
				p += joints[bone[v * stride + c]] * vertex[v] * weight[v * stride + c]
			rest.append(vertex[v])
			posed.append(p)
	return [rest, posed]


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


func _fingers_curl_into_the_palm(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	root.add_child(a)
	var at := func(b: String) -> Vector3: return (a._skeleton.global_transform * a._skeleton.get_bone_global_pose(a._joints[b].bone)).origin
	var tips := {}
	for side in ["left", "right"]:
		for finger in ["Thumb", "Index", "Little"]:
			if a._joints.has(side + finger + "Distal"):
				tips[side + finger + "Distal"] = at.call(side + finger + "Distal")
	check(tips.size() == 6, "%s has a thumb, index and little finger on each hand: %s" % [what, tips.keys()])
	var closed := PackedFloat32Array()
	closed.resize(10)
	closed.fill(1.0)
	a.curl(closed)
	for tip: String in tips:
		var hand: Vector3 = at.call(("left" if tip.begins_with("left") else "right") + "Hand")
		var now: Vector3 = at.call(tip)
		check(now.y < tips[tip].y - (0.003 if tip.contains("Thumb") else 0.01), "%s: the curled %s folds under the hand: %.3f m down" % [what, tip, tips[tip].y - now.y])
		if tip.contains("Thumb"):
			var little: Vector3 = at.call(tip.replace("Thumb", "Little").replace("Distal", "Proximal"))
			check(now.distance_to(little) < tips[tip].distance_to(little) - 0.01, "%s: the curled %s closes across the palm" % [what, tip])
		else:
			check(now.distance_to(hand) < 0.8 * tips[tip].distance_to(hand), "%s: the curled %s folds back toward the wrist" % [what, tip])
	closed.fill(0.0)
	a.curl(closed)
	for tip: String in tips:
		check((at.call(tip) as Vector3).is_equal_approx(tips[tip]), "%s: the %s straightens with its curl undone" % [what, tip])
	a.free()


## VRM 0.x faces -Z and VRM 1.0 +Z.
func _both_versions_stand_alike() -> void:
	var at := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1, 1.6, 2))
	var l := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.8, 1.1, 1.7))
	var r := Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.3, 1.1, 1.8))
	var posed := []
	for path in SAMPLES.slice(0, 2):
		var a := Avatar.open(Avatar.read(FileAccess.get_file_as_bytes(avatar_file(path))), Color.WHITE)
		root.add_child(a)
		a.pose(at, l, r)
		posed.append([a.bone("hips").origin, a.bone("leftLowerArm").origin, a.bone("rightUpperArm").origin, a.bone("leftHand").origin])
		a.free()
	for k in 4:
		check(posed[0][k].distance_to(posed[1][k]) < 0.01, "VRM 1.0 and 0.x stand alike (%d: %s vs %s)" % [k, posed[0][k], posed[1][k]])


func _eye_points(a: Avatar, side: String) -> Vector3:
	var rest: Transform3D = a._joints[side + "Eye"].rest
	return a.bone(side + "Eye").basis * rest.basis.inverse() * (a._model.get_meta("forward") as Vector3)


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


func _expressions_follow_the_look() -> void:
	var a := Avatar.open(Avatar.read(FileAccess.get_file_as_bytes(avatar_file("godette-0.x.vrm"))), Color.WHITE)
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


## Freed the frame it is added, no freed animated material may reach the renderer (scripts/test.sh fails on a null
## material). The first mesh freed flushes every queued update, so the hat, sole holder of its material, is re-added
## as its skeleton's last child, which is freed first.
func _a_worn_avatar_frees_its_animated_materials() -> void:
	var model: Node3D = preload("res://demo/expressions.gd").scene().instantiate()
	model.set_meta("springs", {})
	model.set_meta("expressions", preload("res://demo/expressions.gd").definition())
	Vrm.write(model, "user://worn.vrm")
	model.free()
	var a := Avatar.open(Avatar.read(FileAccess.get_file_as_bytes("user://worn.vrm")), Color.WHITE)
	var hat := a.find_child("ExpressionHat", true, false) as MeshInstance3D
	var holder := hat.get_parent()
	var skeleton := holder.get_parent()
	skeleton.remove_child(holder)
	skeleton.add_child(holder)
	root.add_child(a)
	check(hat.get_surface_override_material(0) is ShaderMaterial, "the worn avatar's hat draws with its own animated material")
	a.free()


func _set_blend_shapes_are_written() -> void:
	var root := Node3D.new()
	root.name = "shaped"
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for name: String in ["held", "rest"]:
		mesh.add_blend_shape(name)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var moved := []
	moved.resize(Mesh.ARRAY_MAX)
	moved[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.BACK])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [moved, moved])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	mi.set_blend_shape_value(0, 0.75)
	var path := ProjectSettings.globalize_path("user://shaped.vrm")
	Vrm.write(root, path)
	root.free()
	var json: Dictionary = Vrm.json_chunk(FileAccess.get_file_as_bytes(path))
	var weights: Array = json.meshes[0].get("weights", [])
	check(weights.size() == 2 and is_equal_approx(weights[0], 0.75) and is_zero_approx(weights[1]), "a set blend shape is written as its mesh's weight: %s" % [weights])


func _blended_surfaces_stay_blended() -> void:
	var root := Node3D.new()
	root.name = "veiled"
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	for depth: Variant in [null, false, true]:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 1, 1, 0.5)
		if depth != null:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.set_meta("extras", {"depthWrite": depth})
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	var path := ProjectSettings.globalize_path("user://veiled.vrm")
	Vrm.write(root, path)
	root.free()
	var state := GLTFState.new()
	check(GLTFDocument.new().append_from_buffer(FileAccess.get_file_as_bytes(path), "", state) == OK and Avatar.shape(state), "the blended file reads and shapes")
	var read: Array[BaseMaterial3D] = []
	read.assign(state.get_materials())
	check(read.size() == 3 and read[0].transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "an opaque material stays opaque")
	check(read.size() == 3 and read[1].transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and read[1].depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY, "a blended material draws blended, writing no depth")
	check(read.size() == 3 and read[2].transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and read[2].depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS, "a depth-written blended material writes depth")
	var shown := MeshInstance3D.new()
	shown.mesh = ArrayMesh.new()
	for m in read:
		(shown.mesh as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		shown.mesh.surface_set_material(shown.mesh.get_surface_count() - 1, m)
	var model := Node3D.new()
	var player := ExpressionPlayer.new(model)
	player._material(shown)
	var shaders := range(3).map(func(i: int) -> String: return (shown.get_surface_override_material(i) as ShaderMaterial).shader.resource_path.get_file())
	check(shaders == ["expression.gdshader", "expression_blended.gdshader", "expression_blended_depth.gdshader"], "every surface of an animated mesh draws as it did: %s" % [shaders])
	var turned := MeshInstance3D.new()
	turned.mesh = shown.mesh
	var turning := ExpressionPlayer.new(model)
	turning._turned[str(turned.name)] = true
	turning._material(turned)
	shaders = range(3).map(func(i: int) -> String: return (turned.get_surface_override_material(i) as ShaderMaterial).shader.resource_path.get_file())
	check(shaders == ["expression_hue.gdshader", "expression_blended_hue.gdshader", "expression_blended_depth_hue.gdshader"], "a mesh with a decal whose hue turns draws each way with the shader that turns it: %s" % [shaders])
	turned.free()
	turning.free()
	shown.free()
	player.free()
	model.free()


func _hidden_avatars_pause() -> void:
	var scene := Avatar.read(FileAccess.get_file_as_bytes(avatar_file("godette-0.x.vrm")))
	var holder := Node3D.new()
	holder.hide()
	root.add_child(holder)
	var wheel := Node3D.new()
	wheel.top_level = true
	holder.add_child(wheel)
	var a := Avatar.open(scene, Color.WHITE)
	var player := Node.new()
	a.add_child(player)
	wheel.add_child(a)
	check(not a.can_process() and not player.can_process(), "an avatar added under a hidden node does not process, nor do its children")
	holder.show()
	check(a.can_process() and player.can_process(), "showing it resumes its processing")
	holder.hide()
	check(not a.can_process() and not player.can_process(), "hiding it again pauses it")
	holder.free()
	var shown := Avatar.open(scene, Color.WHITE)
	root.add_child(shown)
	check(shown.can_process(), "an avatar added where it is seen processes")
	shown.free()


func _read_skins_bind_only_weighed_bones() -> void:
	var weighed := func(mesh: Mesh, skin: Skin) -> bool:
		var used := {}
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			for k in (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).size():
				if arrays[Mesh.ARRAY_WEIGHTS][k] > 0.0:
					used[arrays[Mesh.ARRAY_BONES][k]] = true
		return used.size() == skin.get_bind_count()
	var bytes := FileAccess.get_file_as_bytes(avatar_file("godette-0.x.vrm"))
	var json: Dictionary = Vrm.json_chunk(bytes)
	var joints: int = (json.skins as Array).map(func(skin: Dictionary) -> int: return (skin.joints as Array).size()).max()
	var model := Avatar.read(bytes).instantiate()
	var skinned := model.find_children("*", "MeshInstance3D", true, false).filter(func(mi: MeshInstance3D) -> bool: return mi.skin != null)
	check(not skinned.is_empty() and skinned.all(func(mi: MeshInstance3D) -> bool: return weighed.call(mi.mesh, mi.skin)), "a read avatar's skins bind only the bones its vertices weigh")
	check(skinned.any(func(mi: MeshInstance3D) -> bool: return mi.skin.get_bind_count() < joints), "the fixture's file binds bones its vertices do not weigh, so reading it compacts: %d joints" % joints)
	model.free()
	var importer := ImporterMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_BONES] = PackedInt32Array([2, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0])
	arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skin := Skin.new()
	for b in 4:
		skin.add_bind(b, Transform3D.IDENTITY.translated(Vector3.UP * b))
	var out: Array = Vrm.Skins.compact(importer, skin)
	check(importer.get_surface_arrays(0)[Mesh.ARRAY_BONES] == arrays[Mesh.ARRAY_BONES], "compacting leaves the mesh it read unchanged")
	var kept: Skin = out[1]
	var bones: PackedInt32Array = (out[0] as ImporterMesh).get_surface_arrays(0)[Mesh.ARRAY_BONES]
	check(kept.get_bind_count() == 2 and kept.get_bind_bone(bones[0]) == 2 and kept.get_bind_bone(bones[8]) == 3, "compacting keeps the weighed bones, each vertex still bound to its own")


func _an_extension_at_another_version_is_refused() -> void:
	var bytes := FileAccess.get_file_as_bytes(Avatar.BUILT_IN[0])
	var size := bytes.decode_u32(12)
	var bin := bytes.slice(28 + size, 28 + size + bytes.decode_u32(20 + size))
	check(Avatar.read(Vrm.glb(Vrm.json_chunk(bytes), bin)) != null, "a written file reads at the versions it was written at")
	for name: String in Vrm.VERSIONS:
		for extras: Variant in [{"version": Vrm.VERSIONS[name] + 1}, {}, null]:
			var json: Dictionary = Vrm.json_chunk(bytes)
			var ext: Dictionary = json.extensions.get_or_add(name, {})
			ext.erase("extras")
			if extras != null:
				ext.extras = extras
			check(Vrm.stale_extension(json) == name and Avatar.read(Vrm.glb(json, bin)) == null, "a file whose %s carries %s is refused" % [name, extras])


func _a_record_lacking_a_field_it_must_carry_is_refused_naming_it() -> void:
	var demo := preload("res://demo/expressions.gd")
	var model := demo.scene().instantiate() as Node3D
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := skeleton.get_bone_name(0)
	var identity := [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
	var definition: Dictionary = demo.definition()
	definition.parameters.append({"name": "Spare", "type": "float", "default": 0.0, "saved": false})
	definition.clips.append({"length": 0.0, "curves": []})
	definition.layers.append({"weight": 0.0, "default": 0, "states": [{"motion": {"blend": "1d", "parameters": ["Spare", ""], "children": [{"motion": {"clip": definition.clips.size() - 1}, "threshold": 0.0, "speed": 1.0, "offset": 0.0, "parameter": "", "position": [0.0, 0.0]}]},
		"drivers": [{"parameter": "Spare", "drive": "set", "value": 0.0, "min": 0.0, "max": 1.0, "chance": 1.0, "source": ""}], "transitions": [{"to": 0, "conditions": [], "exitTime": 1.0}]}]})
	definition.menu[2].controls.append({"name": "", "type": "radial", "parameter": "", "value": 1.0, "axes": ["Spare"]})
	var hued: Dictionary = definition.targets.filter(func(t: Dictionary) -> bool: return t.effect is Dictionary and t.effect.has("look") and t.effect.look[0].hue != null)[0]
	hued.effect.look[0].hue.space = 0.0
	definition.looks.index = Image.create_empty(4, 4, false, Image.FORMAT_L8)
	definition.looks.materials = [{"matcaps": [], "lighting": {"model": "flat"}, "emission": {"color": [0.0, 0.0, 0.0], "strength": 0.0, "replace": 0.0}}]
	model.set_meta("expressions", definition)
	model.set_meta("particles", {"meshes": [], "images": [], "systems": [
		{"node": bone, "loop": true, "shape": {"type": "point"}, "renderer": {"draw": false, "materials": []}, "velocity": {"world": false}, "subEmitters": [{"system": 1, "on": "birth", "inherit": []}]},
		{"node": bone, "loop": true, "shape": {"type": "point"}, "renderer": {"draw": true, "materials": [{"blend": "alpha"}]}}]})
	model.set_meta("constraints", [{"kind": "Parent", "node": bone, "weight": 1.0, "translation": [true, true, true], "rotation": [true, true, true], "rest": identity, "offset": identity,
		"sources": [{"world": identity, "weight": 0.0, "offset": identity}, {"world": identity, "weight": 1.0, "offset": identity}]}])
	model.set_meta("springs", {})
	Vrm.write(model, "user://fields.vrm")
	model.free()
	var bytes := FileAccess.get_file_as_bytes("user://fields.vrm")
	check(Avatar.read(bytes) != null, "a file whose every record carries the fields it must reads")
	var size := bytes.decode_u32(12)
	var bin := bytes.slice(28 + size, 28 + size + bytes.decode_u32(20 + size))
	var records := {
		Vrm.EXPRESSIONS: {
			"parameter": func(e: Dictionary) -> Dictionary: return e.parameters[-1],
			"target": func(e: Dictionary) -> Dictionary: return e.targets[0],
			"clip": func(e: Dictionary) -> Dictionary: return e.clips[-1],
			"curve": func(e: Dictionary) -> Dictionary: return e.clips[0].curves[0],
			"layer": func(e: Dictionary) -> Dictionary: return e.layers[-1],
			"driver": func(e: Dictionary) -> Dictionary: return e.layers[-1].states[0].drivers[0],
			"transition": func(e: Dictionary) -> Dictionary: return e.layers[-1].states[0].transitions[0],
			"control": func(e: Dictionary) -> Dictionary: return e.menu[2].controls[-1],
			"child": func(e: Dictionary) -> Dictionary: return e.layers[-1].states[0].motion.children[0],
			"emission": func(e: Dictionary) -> Dictionary: return e.looks.materials[0].emission,
			"material": func(e: Dictionary) -> Dictionary: return e.looks.materials[0],
			"hue": func(e: Dictionary) -> Dictionary: return e.targets.filter(func(t: Dictionary) -> bool: return t.effect is Dictionary and t.effect.has("look") and t.effect.look[0].hue != null)[0].effect.look[0].hue,
		},
		Vrm.PARTICLES: {
			"root": func(e: Dictionary) -> Dictionary: return e,
			"system": func(e: Dictionary) -> Dictionary: return e.systems[0],
			"shape": func(e: Dictionary) -> Dictionary: return e.systems[0].shape,
			"velocity": func(e: Dictionary) -> Dictionary: return e.systems[0].velocity,
			"subEmitter": func(e: Dictionary) -> Dictionary: return e.systems[0].subEmitters[0],
			"renderer": func(e: Dictionary) -> Dictionary: return e.systems[0].renderer,
			"material": func(e: Dictionary) -> Dictionary: return e.systems[1].renderer.materials[0],
		},
		Vrm.CONSTRAINTS: {
			"constraint": func(e: Dictionary) -> Dictionary: return e.constraints[0],
			"source": func(e: Dictionary) -> Dictionary: return e.constraints[0].sources[0],
		},
	}
	check(records.keys() == Vrm.REQUIRED.keys() and Vrm.REQUIRED.keys().all(func(name: String) -> bool: return records[name].keys() == Vrm.REQUIRED[name].keys()), "every kind of record is checked")
	var errors := Lines.new()
	OS.add_logger(errors)
	for name: String in Vrm.REQUIRED:
		for kind: String in Vrm.REQUIRED[name]:
			for field: String in Vrm.REQUIRED[name][kind]:
				var json: Dictionary = Vrm.json_chunk(bytes)
				(records[name][kind] as Callable).call(json.extensions[name]).erase(field)
				errors.lines.clear()
				var read := Avatar.read(Vrm.glb(json, bin))
				var named := "a %s %s lacks its '%s'" % [name, kind, field]
				check(read == null and Array(errors.lines).any(func(line: String) -> bool: return line.contains(named)), "a file whose %s %s lacks its %s is refused, naming it: %s" % [name, kind, field, errors.lines])
	OS.remove_logger(errors)
