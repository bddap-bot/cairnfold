extends "res://../tests/support/suite.gd"

## Headless checks of the VRM avatars: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_avatar.gd

## Public sample avatars (tests/avatars/README.md).
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
	_a_colour_averages_the_triangles_base_colours()
	_a_file_the_headset_does_not_draw_stands_in_a_built_in()
	_both_versions_stand_alike()
	_unweighted_children_keep_humanoid_bones()
	_simulates_the_longest_chains_within_the_limit()
	_import_settles_each_spring_chain()
	_a_later_physbone_over_the_same_bones_is_shadowed()
	_switched_off_physics_stays_out()
	_outlined_materials_draw_their_hull()
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
	_images_are_measured_before_decoding()
	_textures_share_the_texel_limit()
	_blend_shapes_are_bounded()
	_shape_normals_turn_with_the_shape()
	_set_blend_shapes_are_written()
	_blended_surfaces_stay_blended()
	finish()


## A model's colour weighs each primitive's base colour, its factor times its image's mean or glTF's white without a
## material, by its indices.
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


## Where the headset draws no one's own file, a player's file stands as a built-in body in its colour, keeping its
## identity; a built-in stands as itself.
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


## A file naming images too large or too many is refused from their headers, before any is decoded: a beacon makes every
## Quest nearby read the file it names.
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
	var measured := _with_images(bytes, [png.call(64, 32), Image.create_empty(16, 8, false, Image.FORMAT_RGBA8).save_webp_to_buffer(), jpg.call(40, 20)])
	check(Avatar.texture_bytes(Vrm.images(measured)) == (64 * 32 + 16 * 8 + 40 * 20) * 4 * 4 / 3, "an avatar's texture memory is measured from its images' headers")
	check(Avatar.read(_with_images(bytes, ["GIF89a".to_ascii_buffer() + cut])) == null, "an image that is neither PNG, JPEG nor WebP is refused")
	var many := []
	for i in Avatar.MAX_IMAGES:
		many.append(png.call(1, 1))
	check(Avatar.read(_with_images(bytes, many)) != null, "a file with as many images as the limit is read")
	check(Avatar.read(_with_images(bytes, many + [png.call(1, 1)])) == null, "a file with more images than the limit is refused")
	var full: PackedByteArray = png.call(4096, 4096)
	var fill := Array(range(Avatar.FLOOR_PIXELS / Avatar.UNGATED_DECODE_PIXELS)).map(func(_i: int) -> PackedByteArray: return full)
	check(Avatar.read(_with_images(bytes, fill), false, 0) != null, "images filling the pixel floor are read with no memory to spare")
	var over := _with_images(bytes, fill + [png.call(1, 1)])
	check(Avatar.read(over, false, 0) == null, "a file with more pixels than the floor is refused with no memory to spare")
	check(Avatar.read(over, false, Avatar.memory_to_read(Avatar.weight(over.size(), Avatar.FLOOR_PIXELS + 1))) != null, "a file past the pixel floor is read where the memory it needs is available")


## Every device reads a file within the floors; a heavier one is read exactly where the memory the converter names for
## it is available, less what reads under way hold.
func _read_limits_follow_memory() -> void:
	check(Avatar.reads(0) == 1.0 and Avatar.reads(1660 << 20) == 1.0 and Avatar.reads(2432 << 20) == 1.0, "a device with a Quest 2's memory or less reads at the floors")
	var heavy := 1.18
	check(Avatar.reads(Avatar.memory_to_read(heavy)) >= heavy and Avatar.reads(Avatar.memory_to_read(heavy) - 1) < heavy, "a file past the floors is read exactly where the memory it needs is available")
	var sample := FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm"))
	var floor := _padded(sample, Avatar.FLOOR_BYTES)
	check(Avatar.read(floor, false, 0) != null, "a file at the size floor is read with no memory to spare")
	var past := _padded(sample, Avatar.FLOOR_BYTES + 4)
	var needs := Avatar.memory_to_read(Avatar.weight(past.size(), Vrm.pixels(Vrm.images(past))))
	check(Avatar.read(past, false, 0) == null, "a file past the size floor is refused with no memory to spare")
	check(Avatar.read(past, false, needs) != null, "a file past the size floor is read where the memory it needs is available")
	Avatar._reading = needs
	check(Avatar.read(past, false, needs) == null, "memory a read under way holds is not counted available to another")
	Avatar._reading = 0


## `bytes`, a VRM file, grown to `size` bytes by a tail of its buffer that nothing refers to.
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


## A file's images are each the one its headers were measured from, in its place, or it is refused: the texture
## budget is set from those measurements before any image is decoded.
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


## `bytes`, a binary glTF, holding `images` in place of its own, each in a buffer view appended to its binary chunk.
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


## The Unity sample package imports as the avatar model straight from its FBX and .meta: its skeleton, skin and blend
## shapes, its humanoid bones as the package's Avatar definition maps them, keeping Unity's bone names; written as the
## VRM a player wears and read back, it opens, poses and bends as the engine's own import of the FBX does.
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


## A blend shape the package saves at a weight, drawn so by Unity at rest, keeps its weight in the VRM a player wears.
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


## A model Vrm.read made writes, and reads back with the same springs on the same bones, settled rotations included.
func _springs_survive_a_rewrite(file: String) -> void:
	var path := ProjectSettings.globalize_path("user://rewritten.vrm")
	var read := func(bytes: PackedByteArray) -> Node3D: return Vrm.read(bytes, func(_size: Vector2i) -> bool: return true, func(_state: GLTFState) -> bool: return true, func(_image: Image, _layer: String) -> void: pass)
	var first: Node3D = read.call(FileAccess.get_file_as_bytes(file))
	for chain: Dictionary in first.get_meta("springs").springs:
		for joint: Dictionary in chain.joints:
			joint["settled"] = Quaternion(Vector3.RIGHT, 0.5)
	var before := _springs_by_bone(first)
	Vrm.write(first, path)
	first.free()
	var second: Node3D = read.call(FileAccess.get_file_as_bytes(path))
	var after := _springs_by_bone(second)
	second.free()
	check(not (before.springs as Array).is_empty() and str(before) == str(after), "%s's springs survive a write: %s, then %s" % [file.get_file(), before, after])


## A read model's springs with each node as the bone its "spring_N" names, "" for none.
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
## of its shape's name on its node, and the file lists every extension it carries.
func _writes_expressions(model: Node3D) -> void:
	var worn: Node3D = model.duplicate()
	var mi: MeshInstance3D = worn.find_children("*", "MeshInstance3D", true, false)[0]
	var shape: String = mi.mesh.get_blend_shape_name(mi.mesh.get_blend_shape_count() - 1)
	worn.set_meta("faces", {"happy": [{"node": mi.name, "shape": shape, "weight": 0.5}], "wink": [{"node": mi.name, "shape": shape, "weight": 1.0}], "none": [{"node": mi.name, "shape": "no such shape", "weight": 1.0}]})
	var json: Dictionary = Vrm.json_chunk(UnityAvatar.write(worn, ProjectSettings.globalize_path("user://seed-san.vrm")))
	var used: Array = json.get("extensionsUsed", [])
	check((json.extensions as Dictionary).keys().all(func(e: String) -> bool: return used.has(e)), "the file lists the extensions it carries: %s of %s" % [used, (json.extensions as Dictionary).keys()])
	var expressions: Dictionary = json.extensions.VRMC_vrm.expressions
	var target := func(b: Dictionary) -> String: return json.meshes[json.nodes[int(b.node)].mesh].extras.targetNames[int(b.index)]
	var happy: Array = expressions.preset.get("happy", {}).get("morphTargetBinds", [])
	check(happy.size() == 1 and target.call(happy[0]) == shape and happy[0].weight == 0.5, "a preset binds its shape's morph target at its weight: %s" % [expressions])
	check(expressions.custom.has("wink") and expressions.preset.size() == 1 and expressions.custom.size() == 1, "a name no preset has is custom, and an expression binding nothing is left out: %s" % [expressions])


## A PhysBone's allowCollision and allowGrabbing, False, True or Other by its filter, become its springs' extras, which
## read back as the bits the spring runtime checks.
func _physbones_keep_whose_hands_touch_them() -> void:
	var cases := [[{}, ["wearer", "others"]], [{"allowGrabbing": "0"}, []], [{"allowGrabbing": "1"}, ["wearer", "others"]], [{"allowGrabbing": "2", "grabFilter": {"allowSelf": "1", "allowOthers": "0"}}, ["wearer"]], [{"allowGrabbing": "2", "grabFilter": {"allowSelf": "0", "allowOthers": "1"}}, ["others"]]]
	for c: Array in cases:
		check(UnityAvatar._filter(c[0], "allowGrabbing", "grabFilter") == c[1], "a PhysBone's %s lets %s grab it" % [c[0], c[1]])
	for bits in 4:
		var spring := SpringDefinition.hands({"extras": {"collide": Vrm._hands(bits), "grab": Vrm._hands(3 - bits)}}, {})
		check(spring.collide == bits and spring.grab == 3 - bits, "hand bits %d survive the file" % bits)


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


## Where a binary glTF's own skins put each vertex over the posed avatar's bones, by rest position; its joints are
## checked to rest where the file's nodes do.
func _gltf_skin(a: Avatar, bytes: PackedByteArray, what: String) -> Dictionary:
	var json: Dictionary = Vrm.json_chunk(bytes)
	var bin := bytes.slice(28 + bytes.decode_u32(12))
	var sk := a._skeleton
	var at := Meshes.relative(sk, a._model)
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
## hold them, each in `renamed` by the name the worn file gives it), by rest position.
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


## The first chain over a set of bones moves them; a later one over the same bones is not simulated, and one that
## reaches a bone of its own still is.
func _a_later_physbone_over_the_same_bones_is_shadowed() -> void:
	var chain := func(nodes: Array) -> Dictionary: return {"joints": nodes.map(func(n: int) -> Dictionary: return {"node": n, "physbone": {}})}
	var first: Dictionary = chain.call([1, 2])
	var further: Dictionary = chain.call([1, 2, 3])
	var kept := SpringRuntime.unshadowed([first, chain.call([1, 2]), further])
	check(kept.size() == 2 and kept[0] == first and kept[1] == further, "a later chain over the same bones is shadowed, one reaching further is not: %s" % [kept])
	var root := Node3D.new()
	root.set_meta("humanoid", {})
	root.set_meta("springs", {"springs": [first, further]})
	Avatar._keep_longest(root)
	check(root.get_meta("springs").springs == [first, further], "the kept chains stay in the file's order, the first PhysBone on a bone first")
	root.free()


## The importer records where each chain's PhysBone holds its bones in the rest pose, and leaves the bones at rest.
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


## A file carrying more spring joints than an avatar simulates keeps its longest chains, in metres, within the limit,
## those moving a shown mesh first; a bone only the chains left out move rests at its settled rotation, one a kept
## chain moves keeps its own rest.
func _simulates_the_longest_chains_within_the_limit() -> void:
	var lengths := func(springs: Dictionary) -> Array: return springs.springs.map(func(c: Dictionary) -> int: return c.joints.size())
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
	Avatar._keep_longest(root)
	check(lengths.call(root.get_meta("springs")) == [n], "the longest chain fills the limit and the rest are not simulated")
	var sk: Skeleton3D = root.get_node("Skeleton3D")
	var turned := func(bone: int) -> bool: return sk.get_bone_rest(bone).basis.get_rotation_quaternion().is_equal_approx(Quaternion(Vector3.RIGHT, 0.5))
	check(turned.call(1) and turned.call(3 + n - 2), "a bone only chains left out move rests at its settled rotation")
	check(not turned.call(0), "a bone a kept chain moves keeps its own rest")
	root.free()
	root = setup.call([[3, 0.1], [n - 2, 0.1], [2, 0.1]])
	Avatar._keep_longest(root)
	check(lengths.call(root.get_meta("springs")) == [n - 2, 2], "chains are kept longest first while they fit")
	root.free()
	root = setup.call([[4, 0.2], [10, 0.01], [n - 10, 0.01]])
	Avatar._keep_longest(root)
	check(lengths.call(root.get_meta("springs")) == [4, n - 10], "a chain of few joints reaching far outranks one of many that reaches less")
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
	Avatar._keep_longest(root)
	check(lengths.call(root.get_meta("springs")) == [30], "a chain moving only a hidden mesh ranks after one moving a shown mesh")
	root.free()
	root = setup.call([[n - 20, 0.1], [30, 0.01]])
	var carrier := BoneAttachment3D.new()
	root.get_node("Skeleton3D").add_child(carrier)
	carrier.bone_idx = n + 9
	carrier.add_child(MeshInstance3D.new())
	Avatar._keep_longest(root)
	check(lengths.call(root.get_meta("springs")) == [30], "a mesh riding a chain's tip unskinned shows that chain")
	root.free()
	root = setup.call([[2, 0.01], [n - 1, 0.005]])
	root.get_meta("springs").springs[0].end_length = 0.5
	Avatar._keep_longest(root)
	check(lengths.call(root.get_meta("springs")) == [2], "a chain's tail past its last joint counts toward its length")
	root.free()


## A spring chain or collider the expressions' default state switches off is not simulated; one it leaves on is, also
## where a switched-off PhysBone shares its first bone.
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


## A material its glTF extras mark outlined draws its hull next, drawn whole or cut out as the material is, from the
## looks' outline layer and width; one marked without a layer refuses the model.
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
	check(not Avatar._outlined(root, true), "a material marked outlined without an outline layer refuses the model")
	var layer := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	root.set_meta("expressions", {"looks": {"outline": layer, "outlineWidth": 0.002}})
	check(Avatar._outlined(root, true), "a model whose looks carry the layer is drawn")
	var hull := kinds[0].next_pass as ShaderMaterial
	check(hull != null and hull.shader == Avatar.OUTLINE and is_equal_approx(hull.get_shader_parameter("width"), 0.002), "an opaque outlined material draws its hull whole, as wide as the looks say")
	check(kinds[1].next_pass is ShaderMaterial and (kinds[1].next_pass as ShaderMaterial).shader == Avatar.OUTLINE_CUT, "a cut-out one draws its hull cut out")
	check(kinds[2].next_pass == null, "a material not marked draws no hull")
	var past := StandardMaterial3D.new()
	past.set_meta("extras", {"outline": true})
	mesh.surface_set_material(2, past)
	check(Avatar._outlined(root, false) and past.next_pass == null, "an avatar whose hulls would pass the draw limit draws without them")
	Avatar.show_outlines(false)
	check(kinds[0].next_pass == null and kinds[1].next_pass == null, "a step without outlines draws no hull")
	Avatar.show_outlines(true)
	check(kinds[0].next_pass == hull, "a step with them draws it again")
	root.free()


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
				plain += 1 if m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX and m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC and not m.normal_enabled and not m.emission_enabled and m.cull_mode == (BaseMaterial3D.CULL_DISABLED if both_sides.get(m.resource_name, false) else BaseMaterial3D.CULL_BACK) and m.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR, BaseMaterial3D.TRANSPARENCY_ALPHA] else 0
				materials += 1
			triangles += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	check(triangles == authored, "%s keeps every triangle its file has (%d of %d)" % [what, triangles, authored])
	check(surfaces <= Avatar.MAX_SURFACES, "%s keeps to the draw limit (%d)" % [what, surfaces])
	check(plain == materials, "%s draws its colour alone, sampled anisotropically, lit once a vertex, both sides only where its file says, cut out or blended where see-through (%d of %d)" % [what, plain, materials])
	check(not textures.is_empty(), "%s keeps its textures" % what)
	for tex: Texture2D in textures:
		check(tex.get_image().has_mipmaps(), "%s keeps its textures mipmapped (%dx%d)" % [what, tex.get_width(), tex.get_height()])
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


## The body as its wearer's eyes see it is drawn on the same skeleton, posed with it, and without its head: each vertex
## of it the head bone or one under it moves wholly sits at the eyes, and one it moves in part, between the eyes and
## where its other bones put it, so the eyes see there only what the body's own bones place, past their near clip.
## Both reach the hands.
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


## A mesh's vertices at rest and where its skin puts each over the avatar's posed bones, in the avatar's space.
func _skinned(a: Avatar, mi: MeshInstance3D) -> Array[PackedVector3Array]:
	var at := Meshes.relative(a._skeleton, a._model)
	var binds: Array[Transform3D] = []
	for i in mi.skin.get_bind_count():
		binds.append(at * a._skeleton.get_bone_global_pose(Meshes.bind_bone(mi.skin, i, a._skeleton)) * mi.skin.get_bind_pose(i))
	return _skin(mi, binds)


## Each vertex of `mi`'s surfaces at rest, and where `joints`, one per bind, skin it.
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


## At rest, palms down, each finger curled closed folds down under its hand and back toward the wrist, a thumb across
## the palm, and each comes back straight with its curl undone.
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


## VRM 0.x faces -Z and VRM 1.0 +Z; the same model in each stands the same way in the same pose.
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


## An avatar put in the world and freed in the same frame frees its animated materials without the renderer reading one
## already freed, which scripts/test.sh fails as a null material. The first mesh freed flushes every instance's queued
## update: the hat, the only holder of its animated material, is re-added so it is the last child its skeleton added,
## which a node frees first.
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


## A blend shape set on a mesh is written as its glTF default weight: an imported avatar's saved shapes (a toggle held
## on, a face edit) hold in the worn file.
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


## A blended material reads back from the VRM drawn blended, writing depth where its extras say so, and an animated
## mesh's blended surfaces draw through the blended expression shaders: none is cut out at half alpha.
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


## A figure kept under a closed wheel runs no expressions or springs until it is shown again.
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
