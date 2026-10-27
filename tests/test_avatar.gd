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
	_pose_puts_the_eyes_on_the_head(Avatar.built_in(0), "pebble")
	for path in SAMPLES:
		var scene := Avatar.read(FileAccess.get_file_as_bytes(_sample(path)))
		check(scene != null, "%s reads as an avatar" % path)
		if scene != null:
			_within_limits(scene, path)
			_pose_puts_the_eyes_on_the_head(scene, path)
			_arms_join_shoulders_to_hands(scene, path)
	_both_versions_stand_alike()
	_unity_package_converts()
	for i in Avatar.BUILT_IN.size():
		_eye_bones_follow_the_look(Avatar.built_in(i), "built-in %d" % i)
	_expressions_follow_the_look()
	check(Avatar.read("not a vrm".to_utf8_buffer()) == null, "a file that is not glTF reads as nothing")
	var big := PackedByteArray()
	big.resize(Avatar.MAX_BYTES + 1)
	check(Avatar.read(big) == null, "a file over the size limit is not read")
	_images_are_measured_before_decoding()
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


## The Unity sample package converts to a VRM 1.0 of one skinned mesh over its skeleton, its humanoid bones as the
## package's Avatar definition maps them, that Avatar.read opens and poses as it does any VRM.
func _unity_package_converts() -> void:
	var model := UnityAvatar.avatar_scene(_sample("seed-san"))
	check(model != null, "the Unity package converts")
	if model == null:
		return
	var avatar := UnityAvatar.avatar_definition(FileAccess.get_file_as_string(_sample("seed-san/Models/new_seedsan_betterfbx.fbx.meta")))
	var human: Dictionary = model.get_meta("humanoid")
	check(human.size() == avatar.human.size() and avatar.human.keys().all(func(b: String) -> bool: return human.get(UnityAvatar.vrm_bone(avatar.human[b])) == b), "every bone the Avatar definition maps keeps its humanoid name (%d of %d)" % [human.size(), avatar.human.size()])
	check(human.hips == "hips" and human.head == "head 1" and human.leftThumbMetacarpal == "thumb.01.L", "the Avatar definition's own names: Unity's de-duplicated head, its thumb proximal as VRM's metacarpal")
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	check(human.keys().all(func(b: String) -> bool: return sk.find_bone(b) >= 0), "each humanoid bone is the skeleton bone of its VRM name")
	var report: Dictionary = model.get_meta("report")
	check((report["renderers drawn"] as Array).size() == 5, "all five of the model's renderers draw (%s)" % [report["renderers drawn"]])
	var path := ProjectSettings.globalize_path("user://seed-san.vrm")
	Vrm.write(model, path)
	model.free()
	var bytes := FileAccess.get_file_as_bytes(path)
	var json := _gltf_json(bytes)
	var bones: Dictionary = json.extensions.VRMC_vrm.humanoid.humanBones
	var skins: Array = json.get("skins", [])
	var joints := {}
	for k: Dictionary in skins:
		for j: float in k.joints:
			joints[int(j)] = true
	check(bones.size() == avatar.human.size() and bones.keys().all(func(b: String) -> bool: return joints.has(int(bones[b].node)) and json.nodes[int(bones[b].node)].name == b), "the VRM names every mapped humanoid bone as a skin joint of its name (%d)" % bones.size())
	check(skins.size() == 1 and json.meshes.size() == 1 and (json.meshes[0].primitives as Array).size() == 1, "the VRM is one mesh of one primitive over one skin")
	var triangles := 0
	for p: Dictionary in json.meshes[0].primitives:
		triangles += int(json.accessors[int(p.indices)].count) / 3
	check(triangles > 0 and triangles <= Avatar.MAX_TRIANGLES, "within the triangle limit (%d)" % triangles)
	var started := Time.get_ticks_usec()
	var scene := Avatar.read(bytes)
	print("unity package: Avatar.read %.0f ms, %d bytes" % [(Time.get_ticks_usec() - started) / 1000.0, bytes.size()])
	check(scene != null, "Avatar.read opens the converted package")
	if scene == null:
		return
	_pose_puts_the_eyes_on_the_head(scene, "seed-san")
	_arms_join_shoulders_to_hands(scene, "seed-san")
	var empty := ProjectSettings.globalize_path("user://no-humanoid")
	DirAccess.make_dir_recursive_absolute(empty)
	check(UnityAvatar.avatar_scene(empty) == null, "a package with no humanoid model converts to nothing")


## The JSON chunk of a binary glTF.
func _gltf_json(bytes: PackedByteArray) -> Dictionary:
	return JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())


func _sample(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tests/avatars").path_join(name)


func _built_in_reads_as_humanoid(i: int) -> void:
	var a := Avatar.open(Avatar.built_in(i), Color.RED)
	for b in ["head", "leftHand", "rightHand", "hips", "leftUpperArm", "rightLowerArm"]:
		check(a._joints.has(b) and a._joints[b].node.name == b, "built-in %d names its %s as VRM does" % [i, b])
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


func _within_limits(scene: PackedScene, what: String) -> void:
	var a := Avatar.open(scene, Color.WHITE)
	var triangles := 0
	var surfaces := 0
	var skinned := 0
	var plain := 0
	var materials := 0
	var textures := {}
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		surfaces += mi.mesh.get_surface_count()
		skinned += 1 if mi.skin != null else 0
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null and m.albedo_texture != null:
				textures[m.albedo_texture] = true
			if m != null:
				plain += 1 if m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_VERTEX and not m.normal_enabled and not m.emission_enabled and m.cull_mode == BaseMaterial3D.CULL_BACK and m.transparency in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] else 0
				materials += 1
			triangles += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		var looks: int = a._shapes.reduce(func(n: int, sets: Array) -> int: return n + sets.size(), 0)
		check(mi.mesh.get_blend_shape_count() <= mini(looks, Vrm.LOOKS.size() * Vrm.BINDS_PER_LOOK), "%s drops every expression but its eyes' (%d kept)" % [what, mi.mesh.get_blend_shape_count()])
	check(triangles > 0 and triangles <= Avatar.MAX_TRIANGLES, "%s keeps to the triangle limit (%d)" % [what, triangles])
	check(surfaces <= Avatar.MAX_SURFACES, "%s keeps to the draw limit (%d)" % [what, surfaces])
	check(skinned == 0 and a.find_children("*", "Skeleton3D", true, false).is_empty(), "%s stands in rigid parts on its moving bones, with no skeleton to skin" % what)
	check(plain == materials, "%s draws its colour alone, lit once a vertex, front faces only, cut out where see-through (%d of %d)" % [what, plain, materials])
	check(not textures.is_empty(), "%s keeps its textures" % what)
	for tex: Texture2D in textures:
		check(maxi(tex.get_width(), tex.get_height()) <= Avatar.MAX_TEXTURE and tex.get_image().has_mipmaps(), "%s keeps its textures to the size limit, mipmapped (%dx%d)" % [what, tex.get_width(), tex.get_height()])
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
	var tilted := Transform3D(Basis.from_euler(Vector3(0.5, 1.1, 0.3)), Vector3(1, 1.6, 1))
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
