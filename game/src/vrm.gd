class_name Vrm
extends GLTFDocumentExtension

## The humanoid part of VRM 1.0 (VRMC_vrm) and VRM 0.x (VRM): which glTF nodes are the head, hands and the rest
## of the body, where the eyes sit relative to the head bone, and which way the model faces. Export writes VRM
## 1.0 from nodes named after the bones, the scene root's "eyes" metadata and its "faces" (each VRM expression's
## name, a preset where PRESETS has it and custom otherwise, to its [{"node": mesh node name, "shape": blend shape
## name, "weight" 0 to 1}]) and its "springs" with the "spring_N" paths in its "humanoid", as import records them;
## import records on the scene root the metadata "humanoid" (bone name to the node's path from the root, with the bone's name as the subname when
## it is a skeleton's bone), "eyes" where the file gives them, "forward", "look" and "springs": the avatar data of
## Avatar.model. VRCHAT_expressions carries imported menu controls and FX targets.
##
## "look" is how the model points its eyes (VRM lookAt): {"type": BONE or EXPRESSION, "ranges": the horizontal inner,
## horizontal outer, vertical down and vertical up range maps, each Vector2(largest input angle in degrees, output at
## it: degrees for eye bones, a weight for expressions), "shapes": for an expression model, each of LOOKS to its
## morph targets as [mesh node path, blend shape index, weight]}. Export writes "look"'s type and ranges.

const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")

## VRM 1.0 humanoid bones.
const BONES := ["hips", "spine", "chest", "upperChest", "neck", "head", "leftEye", "rightEye", "jaw", "leftUpperLeg", "leftLowerLeg", "leftFoot", "leftToes", "leftShoulder", "leftUpperArm", "leftLowerArm", "leftHand", "leftThumbMetacarpal", "leftThumbProximal", "leftThumbDistal", "leftIndexProximal", "leftIndexIntermediate", "leftIndexDistal", "leftMiddleProximal", "leftMiddleIntermediate", "leftMiddleDistal", "leftRingProximal", "leftRingIntermediate", "leftRingDistal", "leftLittleProximal", "leftLittleIntermediate", "leftLittleDistal", "rightUpperLeg", "rightLowerLeg", "rightFoot", "rightToes", "rightShoulder", "rightUpperArm", "rightLowerArm", "rightHand", "rightThumbMetacarpal", "rightThumbProximal", "rightThumbDistal", "rightIndexProximal", "rightIndexIntermediate", "rightIndexDistal", "rightMiddleProximal", "rightMiddleIntermediate", "rightMiddleDistal", "rightRingProximal", "rightRingIntermediate", "rightRingDistal", "rightLittleProximal", "rightLittleIntermediate", "rightLittleDistal"]
## VRM 0.x thumb bones by their VRM 1.0 names.
const THUMBS_0X := {"leftThumbProximal": "leftThumbMetacarpal", "leftThumbIntermediate": "leftThumbProximal", "rightThumbProximal": "rightThumbMetacarpal", "rightThumbIntermediate": "rightThumbProximal"}
const BONE := "bone"
const EXPRESSIONS := "VRCHAT_expressions"
const EXPRESSION := "expression"
const RANGES := ["rangeMapHorizontalInner", "rangeMapHorizontalOuter", "rangeMapVerticalDown", "rangeMapVerticalUp"]
const LOOKS := ["lookLeft", "lookRight", "lookUp", "lookDown"]
## VRM 1.0 preset expressions.
const PRESETS := ["happy", "angry", "sad", "relaxed", "surprised", "aa", "ih", "ou", "ee", "oh", "blink", "blinkLeft", "blinkRight", "lookUp", "lookDown", "lookLeft", "lookRight", "neutral"]
## Each kept blend shape is a pass over its mesh's vertices every frame, so a file's look binds are cut to these.
const BINDS_PER_LOOK := 2
const PNG := [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]


func _get_supported_extensions() -> PackedStringArray:
	return PackedStringArray(["VRMC_vrm", "VRM", "VRMC_springBone", EXPRESSIONS])


## Files come from other players, so every field is checked for its type before use.
func _import_post(state: GLTFState, root: Node) -> Error:
	var exts: Variant = state.json.get("extensions")
	exts = exts if exts is Dictionary else {}
	var found := {}
	var eyes := Vector3.INF
	var forward := Vector3.BACK
	var look := {"type": look_type(state), "ranges": [], "shapes": {}}
	var ranges := []
	if exts.get("VRMC_vrm") is Dictionary:
		var vrm: Dictionary = exts.VRMC_vrm
		var human: Variant = _field(_field(vrm, "humanoid"), "humanBones")
		if human is Dictionary:
			for bone in human:
				_bind(found, str(bone), _field(human[bone], "node"), state, root)
		var off: Variant = _field(_field(vrm, "lookAt"), "offsetFromHeadBone")
		if off is Array and off.size() == 3 and off.all(func(x: Variant) -> bool: return x is float):
			eyes = Vector3(off[0], off[1], off[2])
		for r in RANGES:
			var m: Variant = _field(_field(vrm, "lookAt"), r)
			ranges.append([_field(m, "inputMaxValue"), _field(m, "outputScale")])
	elif exts.get("VRM") is Dictionary:
		# VRM 0.x faces -Z, and stores its first-person offset in Unity's axes, whose Z is glTF's reversed.
		forward = Vector3.FORWARD
		var human: Variant = _field(_field(exts.VRM, "humanoid"), "humanBones")
		if human is Array:
			for b: Variant in human:
				_bind(found, THUMBS_0X.get(str(_field(b, "bone")), str(_field(b, "bone"))), _field(b, "node"), state, root)
		var off: Variant = _field(_field(exts.VRM, "firstPerson"), "firstPersonBoneOffset")
		if off is Dictionary and [off.get("x"), off.get("y"), off.get("z")].all(func(x: Variant) -> bool: return x is float):
			eyes = Vector3(off.x, off.y, -off.z)
		var first: Variant = _field(exts.VRM, "firstPerson")
		for r in ["lookAtHorizontalInner", "lookAtHorizontalOuter", "lookAtVerticalDown", "lookAtVerticalUp"]:
			ranges.append([_field(_field(first, r), "xRange"), _field(_field(first, r), "yRange")])
	var most := 90.0 if look.type == BONE else 1.0
	for i in RANGES.size():
		var r: Array = ranges[i] if i < ranges.size() else [null, null]
		look.ranges.append(Vector2(_number(r[0], 1.0, 180.0, 90.0), _number(r[1], 0.0, most, 10.0 if look.type == BONE else 1.0)))
	# Skinned meshes are rebuilt under their skeleton, out of reach of the state's node map; their names are unique.
	var meshes := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		meshes[String(mi.name)] = root.get_path_to(mi)
	# Godot reads each mesh's default morph weights but leaves its instances at zero; a shape saved at a weight rests at it.
	for node: GLTFNode in state.get_nodes():
		if node.mesh >= 0 and meshes.has(node.resource_name):
			var mi: MeshInstance3D = root.get_node(meshes[node.resource_name])
			var weights := state.get_meshes()[node.mesh].blend_weights
			for k in mini(weights.size(), mi.get_blend_shape_count()):
				mi.set_blend_shape_value(k, clampf(weights[k], 0.0, 1.0) if is_finite(weights[k]) else 0.0)
	var binds := look_binds(state)
	for dir: String in binds:
		for b: Array in binds[dir]:
			var path: Variant = meshes.get(state.get_nodes()[b[0]].resource_name)
			if path != null:
				look.shapes.get_or_add(dir, []).append([path, b[1], b[2]])
	var springs := SpringDefinition.read(state.json)
	var spring_nodes := {}
	for chain: Dictionary in springs.springs:
		for joint: Dictionary in chain.joints:
			spring_nodes[joint.node] = true
		if chain.center >= 0:
			spring_nodes[chain.center] = true
	for collider: Dictionary in springs.colliders:
		if collider.node >= 0:
			spring_nodes[collider.node] = true
	for index: int in spring_nodes:
		_bind(found, "spring_" + str(index), float(index), state, root)
	if exts.get(EXPRESSIONS) is Dictionary and ExpressionDefinition.valid(exts[EXPRESSIONS]):
		root.set_meta("expressions", _named(exts[EXPRESSIONS], state))
	root.set_meta("springs", springs)
	root.set_meta("humanoid", found)
	root.set_meta("look", look)
	if eyes.is_finite() and eyes.length() < 1.0:
		root.set_meta("eyes", eyes)
	root.set_meta("forward", forward)
	return OK


## Has each skin keep only the bones its mesh's vertices weigh, sharing one binding among identical ones, while the
## meshes are still the importer's arrays: Godot's own import turns them into renderer meshes, and reading one of those
## back costs the main thread a wait on the GPU. Registered ahead of that import, so it runs on the thread that reads
## the file.
class Skins extends GLTFDocumentExtension:
	func _import_post(_state: GLTFState, root: Node) -> Error:
		var compacted := {}
		for mi: ImporterMeshInstance3D in root.find_children("*", "ImporterMeshInstance3D", true, false):
			if mi.mesh != null and mi.skin != null:
				var key := [mi.mesh, mi.skin]
				if not compacted.has(key):
					compacted[key] = compact(mi.mesh, mi.skin)
				mi.mesh = compacted[key][0]
				mi.skin = compacted[key][1]
		return OK

	static func compact(mesh: ImporterMesh, skin: Skin) -> Array:
		var used := {}
		for i in mesh.get_surface_count():
			var arrays := mesh.get_surface_arrays(i)
			if arrays[Mesh.ARRAY_BONES] == null:
				continue
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for j in bones.size():
				if weights[j] > 0.0:
					used[bones[j]] = true
		if used.is_empty() or used.keys().min() < 0 or used.keys().max() >= skin.get_bind_count():
			return [mesh, skin]
		var indices := PackedInt32Array()
		indices.resize(skin.get_bind_count())
		var bindings := {}
		var kept := Skin.new()
		for i in skin.get_bind_count():
			if not used.has(i):
				continue
			var key := [skin.get_bind_bone(i), skin.get_bind_name(i), skin.get_bind_pose(i)]
			if not bindings.has(key):
				kept.add_bind(key[0], key[2])
				kept.set_bind_name(kept.get_bind_count() - 1, key[1])
				bindings[key] = kept.get_bind_count() - 1
			indices[i] = bindings[key]
		if kept.get_bind_count() == skin.get_bind_count():
			return [mesh, skin]
		var out := ImporterMesh.new()
		out.resource_name = mesh.resource_name
		out.set_blend_shape_mode(mesh.get_blend_shape_mode())
		for k in mesh.get_blend_shape_count():
			out.add_blend_shape(mesh.get_blend_shape_name(k))
		for i in mesh.get_surface_count():
			var arrays := mesh.get_surface_arrays(i).duplicate()
			if arrays[Mesh.ARRAY_BONES] != null:
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				for j in bones.size():
					bones[j] = indices[bones[j]]
				arrays[Mesh.ARRAY_BONES] = bones
			var lods := {}
			for l in mesh.get_surface_lod_count(i):
				lods[mesh.get_surface_lod_size(i, l)] = mesh.get_surface_lod_indices(i, l)
			var shapes := range(mesh.get_blend_shape_count()).map(func(k: int) -> Array: return mesh.get_surface_blend_shape_arrays(i, k))
			out.add_surface(mesh.get_surface_primitive_type(i), arrays, shapes, lods, mesh.get_surface_material(i), mesh.get_surface_name(i), mesh.get_surface_format(i) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		return [out, kept]


## Measures each image from its PNG, JPEG or WebP header and, if the read's `fits` takes that size, decodes it as the
## format measured and hands it to the read's `image` before it becomes a texture; anything else, or an image that does
## not decode, marks the read refused and leaves Godot's decoders nothing to try. A decal image (VRCHAT_expressions'
## looks) is kept aside as the image the definition names, and only a texel of it becomes a texture. Registered ahead of
## Godot's own decoders, so it sees every image first, apart from Vrm, whose import follows Godot's. Reading a texture
## back calls the rendering server, which answers a worker thread only from the main thread, so a game quitting
## mid-read would wait on the read forever.
class Images extends GLTFDocumentExtension:
	func _parse_image_data(state: GLTFState, data: PackedByteArray, _mime: String, out: Image) -> Error:
		var fits: Variant = state.get_additional_data(&"vrm_fits")
		if not (fits is Callable and fits.is_valid()):
			return OK
		var at: int = state.get_additional_data(&"vrm_image_at")
		state.set_additional_data(&"vrm_image_at", at + 1)
		var size := Vrm._image_size(data)
		if size.x > 0 and size.y > 0 and fits.call(size):
			if data[0] == Vrm.PNG[0]:
				out.load_png_from_buffer(data)
			elif data[0] == 0xFF:
				out.load_jpg_from_buffer(data)
			else:
				out.load_webp_from_buffer(data)
		if out.is_empty():
			state.set_additional_data(&"vrm_refused", true)
			out.set_data(1, 1, false, Image.FORMAT_L8, PackedByteArray([0]))
			return OK
		var image: Variant = state.get_additional_data(&"vrm_image")
		if image is Callable and image.is_valid():
			image.call(out)
		(state.get_additional_data(&"vrm_means") as Array).append(Vrm._mean(out))
		if at in Vrm._decal_indices(state.json):
			(state.get_additional_data(&"vrm_decals") as Dictionary)[at] = out.duplicate()
			out.set_data(1, 1, false, Image.FORMAT_RGBA8, PackedByteArray([0, 0, 0, 0]))
		return OK


## Each image of a binary glTF, in order, measured from its header before any is decoded: "size", zero for an image not
## held in the file's own binary chunk.
static func images(glb: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if glb.size() < 28:
		return out
	var json_size := glb.decode_u32(12)
	var json: Variant = JSON.parse_string(glb.slice(20, 20 + json_size).get_string_from_utf8())
	if not json is Dictionary or not json.get("images") is Array or not json.get("bufferViews") is Array:
		return out
	var views: Array = json.bufferViews
	var images: Array = json.images
	for i in images.size():
		var view: Variant = _field(images[i], "bufferView")
		var size := Vector2i.ZERO
		if view is float and view >= 0 and view < views.size() and views[int(view)] is Dictionary and _number(views[int(view)].get("buffer", 0.0), -1, 1, -1) == 0:
			var at := 28 + json_size + int(_number(views[int(view)].get("byteOffset", 0), 0, glb.size(), 0))
			size = _image_size(glb.slice(at, at + int(_number(views[int(view)].get("byteLength", 0), 0, glb.size(), 0))))
		out.append({"size": size})
	return out


## The glTF images VRCHAT_expressions' looks name as decals.
static func _decal_indices(json: Dictionary) -> Array:
	var decals: Variant = _field(_field(_field(json.get("extensions"), EXPRESSIONS), "looks"), "decals")
	return (decals as Array).filter(func(k: Variant) -> bool: return k is float or k is int).map(func(k: Variant) -> int: return int(k)) if decals is Array else []


## The width and height in the header of a PNG, a JPEG or a WebP; zero if it is none.
static func _image_size(d: PackedByteArray) -> Vector2i:
	if d.size() >= 24 and Array(d.slice(0, 8)) == PNG and d.slice(12, 16).get_string_from_ascii() == "IHDR":
		return Vector2i(_u16(d, 16) << 16 | _u16(d, 18), _u16(d, 20) << 16 | _u16(d, 22))
	if d.size() >= 32 and d.slice(0, 4).get_string_from_ascii() == "RIFF" and d.slice(8, 12).get_string_from_ascii() == "WEBP":
		match d.slice(12, 16).get_string_from_ascii():
			"VP8L":
				var bits := d.decode_u32(21)
				return Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
			"VP8X":
				return Vector2i((d.decode_u32(24) & 0xFFFFFF) + 1, (d.decode_u32(27) & 0xFFFFFF) + 1)
			"VP8 ":
				return Vector2i(d.decode_u16(26) & 0x3FFF, d.decode_u16(28) & 0x3FFF)
		return Vector2i.ZERO
	if d.size() < 4 or d[0] != 0xFF or d[1] != 0xD8:
		return Vector2i.ZERO
	var i := 2
	while i + 8 < d.size() and d[i] == 0xFF:
		var marker := d[i + 1]
		if marker == 0xFF:
			i += 1
		elif marker == 0x01 or marker >= 0xD0 and marker <= 0xD7:
			i += 2
		elif marker >= 0xC0 and marker <= 0xCF and not marker in [0xC4, 0xC8, 0xCC]:
			return Vector2i(_u16(d, i + 7), _u16(d, i + 5))
		elif marker == 0xD9 or marker == 0xDA:
			break
		else:
			i += 2 + _u16(d, i + 2)
	return Vector2i.ZERO


static func _u16(d: PackedByteArray, at: int) -> int:
	return d[at] << 8 | d[at + 1]


static func look_type(state: GLTFState) -> String:
	var exts: Variant = state.json.get("extensions")
	if _field(_field(_field(exts, "VRMC_vrm"), "lookAt"), "type") == EXPRESSION or _field(_field(_field(exts, "VRM"), "firstPerson"), "lookAtTypeName") == "BlendShape":
		return EXPRESSION
	return BONE


## The morph targets each of LOOKS sets, as [node, morph target, weight 0 to 1], in a model whose eyes look by
## expression: VRM 1.0 binds them by node, VRM 0.x by mesh, which may hang from several nodes.
static func look_binds(state: GLTFState) -> Dictionary:
	var exts: Variant = state.json.get("extensions")
	var nodes := state.get_nodes()
	var out := {}
	if look_type(state) != EXPRESSION:
		return out
	var add := func(dir: String, node: int, morph: Variant, weight: Variant) -> void:
		var mesh := nodes[node].mesh
		if mesh < 0 or out.get(dir, []).size() >= BINDS_PER_LOOK or not (morph is float and morph >= 0 and morph < 1 << 16 and weight is float and is_finite(weight)):
			return
		out.get_or_add(dir, []).append([node, int(morph), clampf(weight, 0.0, 1.0)])
	var preset: Variant = _field(_field(_field(exts, "VRMC_vrm"), "expressions"), "preset")
	if preset is Dictionary:
		for dir: String in LOOKS:
			var binds: Variant = _field(preset.get(dir), "morphTargetBinds")
			for b: Variant in (binds.slice(0, BINDS_PER_LOOK) if binds is Array else []):
				var node: Variant = _field(b, "node")
				if node is float and node >= 0 and node < nodes.size():
					add.call(dir, int(node), _field(b, "index"), _field(b, "weight"))
	var groups: Variant = _field(_field(_field(exts, "VRM"), "blendShapeMaster"), "blendShapeGroups")
	for g: Variant in (groups if groups is Array else []):
		var dir: String = {"lookleft": "lookLeft", "lookright": "lookRight", "lookup": "lookUp", "lookdown": "lookDown"}.get(str(_field(g, "presetName")), "")
		var binds: Variant = _field(g, "binds")
		if dir == "" or not binds is Array:
			continue
		for b: Variant in binds.slice(0, BINDS_PER_LOOK):
			var mesh: Variant = _field(b, "mesh")
			var weight: Variant = _field(b, "weight")
			for i in nodes.size():
				if mesh is float and nodes[i].mesh == int(mesh) and weight is float:
					add.call(dir, i, _field(b, "index"), weight / 100.0)
	return out


static func _number(x: Variant, low: float, high: float, otherwise: float) -> float:
	return clampf(x, low, high) if x is float and is_finite(x) else otherwise


static func _field(d: Variant, key: String) -> Variant:
	return d.get(key) if d is Dictionary else null


static func _bind(found: Dictionary, bone: String, node: Variant, state: GLTFState, root: Node) -> void:
	if not ((bone in BONES or bone.begins_with("spring_")) and node is float and node >= 0 and node < state.get_nodes().size()):
		return
	var n := state.get_scene_node(int(node))
	if n is BoneAttachment3D:
		n = (n as BoneAttachment3D).get_skeleton()
	if n is Skeleton3D:
		var name := state.get_nodes()[int(node)].resource_name
		if (n as Skeleton3D).find_bone(name) >= 0:
			found[bone] = NodePath("%s:%s" % [root.get_path_to(n), name])
	elif n is Node3D:
		found[bone] = root.get_path_to(n)


func _export_preflight(state: GLTFState, root: Node) -> Error:
	var springs := _spring_extension(root)
	state.set_additional_data(&"springs", springs)
	state.set_additional_data(&"constraints", root.get_meta("constraints", []))
	state.set_additional_data(&"eyes", root.get_meta("eyes", Vector3(0, 0.06, 0)))
	state.set_additional_data(&"look", root.get_meta("look", {}))
	state.set_additional_data(&"expressions", root.get_meta("expressions", {}))
	state.set_additional_data(&"faces", root.get_meta("faces", {}))
	state.set_additional_data(&"weights", {})
	state.add_used_extension("VRMC_vrm", false)
	if not springs.is_empty():
		state.add_used_extension("VRMC_springBone", false)
		if (springs.colliders as Array).any(func(c: Dictionary) -> bool: return c.has("extensions")):
			state.add_used_extension("VRMC_springBone_extended_collider", false)
	if not root.get_meta("constraints", []).is_empty():
		state.add_used_extension("UNITY_constraints", false)
	if not root.get_meta("expressions", {}).is_empty():
		state.add_used_extension(EXPRESSIONS, false)
	return OK


## The root's "springs" as VRMC_springBone, each node named as export names it. A chain with a joint the humanoid gives
## no path is left out, as import leaves out a chain with a joint it cannot find.
static func _spring_extension(root: Node) -> Dictionary:
	var definition: Dictionary = root.get_meta("springs", {})
	var human: Dictionary = root.get_meta("humanoid", {})
	var named := func(n: int) -> String:
		var path: Variant = human.get("spring_%d" % n)
		if not path is NodePath:
			return ""
		return (path as NodePath).get_concatenated_subnames() if (path as NodePath).get_subname_count() > 0 else String(root.get_node(path).name)
	var v := func(x: Vector3) -> Array: return [x.x, x.y, x.z]
	var colliders := []
	for c: Dictionary in definition.get("colliders", []):
		var collider := {"shape": {"capsule": {"offset": v.call(c.offset), "tail": v.call(c.tail), "radius": c.radius}} if c.offset != c.tail else {"sphere": {"offset": v.call(c.offset), "radius": c.radius}}}
		var node: String = named.call(c.node)
		if node != "":
			collider.node = node
		if c.has("extensions"):
			collider.extensions = c.extensions
		colliders.append(collider)
	var groups := []
	var springs := []
	for chain: Dictionary in definition.get("springs", []):
		var joints := []
		for j: Dictionary in chain.joints:
			var g: Vector3 = j.gravity
			var joint := {"node": named.call(j.node), "stiffness": j.stiffness, "dragForce": j.drag, "hitRadius": j.radius, "gravityPower": g.length(), "gravityDir": v.call(g.normalized() if g.length() > 0.0 else Vector3.DOWN)}
			if j.has("extras"):
				joint.extras = j.extras
			joints.append(joint)
		if joints.any(func(j: Dictionary) -> bool: return j.node == ""):
			continue
		var spring := {"joints": joints, "extras": {"collide": _hands(chain.collide), "grab": _hands(chain.grab)}}
		var center: String = named.call(chain.center)
		if center != "":
			spring.center = center
		if not (chain.colliders as Array).is_empty():
			spring.colliderGroups = [groups.size()]
			groups.append({"colliders": chain.colliders})
		springs.append(spring)
	if springs.is_empty() and colliders.is_empty():
		return {}
	return {"specVersion": "1.0", "springs": springs, "colliders": colliders, "colliderGroups": groups}


## WEARER and OTHERS bits as a spring's extras list them.
static func _hands(bits: int) -> Array:
	return (["wearer"] if bits & SpringDefinition.WEARER else []) + (["others"] if bits & SpringDefinition.OTHERS else [])


## Godot exports every morph weight as zero; a mesh carries the values its node sets, as glTF's default weights.
func _export_node(state: GLTFState, gltf_node: GLTFNode, _json: Dictionary, node: Node) -> Error:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh is ArrayMesh and gltf_node.mesh >= 0 and mi.mesh.get_blend_shape_count() > 0:
		var weights: Dictionary = state.get_additional_data(&"weights")
		weights[gltf_node.mesh] = range(mi.mesh.get_blend_shape_count()).map(func(k: int) -> float: return mi.get_blend_shape_value(k))
	return OK


func _export_post(state: GLTFState) -> Error:
	var weights: Dictionary = state.get_additional_data(&"weights")
	for mesh: int in weights:
		state.json.meshes[mesh].weights = weights[mesh]
	var bones := {}
	var nodes := state.get_nodes()
	for i in nodes.size():
		var name := nodes[i].resource_name
		if name in BONES:
			bones[name] = {"node": i}
	var eyes: Vector3 = state.get_additional_data(&"eyes")
	var look_at := {"offsetFromHeadBone": [eyes.x, eyes.y, eyes.z]}
	var look: Dictionary = state.get_additional_data(&"look")
	if not look.is_empty():
		look_at.type = look.type
		for i in RANGES.size():
			look_at[RANGES[i]] = {"inputMaxValue": look.ranges[i].x, "outputScale": look.ranges[i].y}
	var morphs := {}
	for i in nodes.size():
		if nodes[i].mesh >= 0:
			var mesh := state.get_meshes()[nodes[i].mesh].mesh
			for k in mesh.get_blend_shape_count():
				morphs[[str(nodes[i].resource_name), str(mesh.get_blend_shape_name(k))]] = {"node": i, "index": k}
	var faces := {"preset": {}, "custom": {}}
	var wanted: Dictionary = state.get_additional_data(&"faces")
	for name: String in wanted:
		var binds := []
		for b: Dictionary in wanted[name]:
			var at: Variant = morphs.get([str(b.node), str(b.shape)])
			if at != null:
				binds.append({"node": at.node, "index": at.index, "weight": b.weight})
		if not binds.is_empty():
			faces["preset" if name in PRESETS else "custom"][name] = {"morphTargetBinds": binds}
	var exts: Dictionary = state.json.get_or_add("extensions", {})
	exts["VRMC_vrm"] = {
		"specVersion": "1.0",
		"meta": {"name": state.get_scene_name(), "authors": [ProjectSettings.get_setting("application/config/name")], "licenseUrl": "https://vrm.dev/licenses/1.0/", "avatarPermission": "everyone", "commercialUsage": "corporation", "modification": "allowModificationRedistribution"},
		"humanoid": {"humanBones": bones},
		"lookAt": look_at,
		"expressions": faces,
	}
	var indices := {}
	for i in nodes.size():
		indices[nodes[i].resource_name] = i
	var springs: Dictionary = state.get_additional_data(&"springs")
	if not springs.is_empty():
		for chain: Dictionary in springs.springs:
			if chain.has("center"):
				chain.center = indices[chain.center]
			for joint: Dictionary in chain.joints:
				joint.node = indices[joint.node]
		for collider: Dictionary in springs.colliders:
			if collider.has("node"):
				collider.node = indices[collider.node]
		exts["VRMC_springBone"] = springs
	var constraints: Array = state.get_additional_data(&"constraints")
	if not constraints.is_empty():
		var encoded := constraints.duplicate(true)
		for c: Dictionary in encoded:
			c.node = indices[c.node]
			for source: Dictionary in c.sources:
				if source.has("node"):
					source.node = indices[source.node]
		exts["UNITY_constraints"] = {"constraints": encoded}
	var expressions: Dictionary = state.get_additional_data(&"expressions")
	if not expressions.is_empty():
		exts[EXPRESSIONS] = _indexed(expressions, state, indices)
	return OK


static func _indexed(expressions: Dictionary, state: GLTFState, index: Dictionary) -> Dictionary:
	var out := expressions.duplicate(true)
	if out.get("looks") is Dictionary and out.looks.has("decals"):
		out.looks.decals = (out.looks.decals as Array).map(func(img: Image) -> int: return _add_image(state, img.save_webp_to_buffer()))
	var nodes := state.get_nodes()
	var morph := func(bind: Array) -> Array:
		var mesh := nodes[index[bind[0]]].mesh
		var shapes: ImporterMesh = state.get_meshes()[mesh].mesh
		return [mesh, range(shapes.get_blend_shape_count()).filter(func(k: int) -> bool: return shapes.get_blend_shape_name(k) == bind[1])[0]]
	for t: Dictionary in out.targets:
		if t.effect is Dictionary and t.effect.has("morph"):
			t.effect.morph = t.effect.morph.map(morph)
		elif ExpressionDefinition.region(t.effect) != "":
			for region: Dictionary in t.effect.values()[0]:
				region.node = index[region.node]
		elif t.effect is Dictionary:
			for kind: String in ["scale", "rotation", "translation", "material"]:
				if t.effect.has(kind):
					t.effect[kind].node = index[t.effect[kind].node]
	for s: Dictionary in out.shown:
		s.node = index[s.node]
	for s: Dictionary in out.get("springs", []):
		s.joints = s.joints.map(func(n: String) -> int: return index[n])
	return out


## Appends the encoded image `bytes` (lossless WebP) to the binary buffer as a glTF image no texture uses: its index.
static func _add_image(state: GLTFState, bytes: PackedByteArray) -> int:
	var buffers := state.get_buffers()
	if buffers.is_empty():
		buffers.append(PackedByteArray())
	var data: PackedByteArray = buffers[0]
	data.resize((data.size() + 3) & ~3)
	var views: Array = state.json.get_or_add("bufferViews", [])
	views.append({"buffer": 0, "byteOffset": data.size(), "byteLength": bytes.size()})
	data.append_array(bytes)
	buffers[0] = data
	state.set_buffers(buffers)
	var images: Array = state.json.get_or_add("images", [])
	images.append({"bufferView": views.size() - 1, "mimeType": "image/webp"})
	return images.size() - 1


static func _named(definition: Dictionary, state: GLTFState) -> Dictionary:
	var out := definition.duplicate(true)
	var nodes := state.get_nodes()
	var name_of := func(ref: Dictionary) -> String:
		var index := int(ref.get("node", -1))
		return nodes[index].resource_name if index >= 0 and index < nodes.size() else ""
	for t: Dictionary in out.get("targets", []):
		if not t.get("effect") is Dictionary:
			continue
		var effect: Dictionary = t.effect
		if effect.has("morph"):
			var binds := []
			for b: Array in effect.morph:
				for n in nodes:
					if n.mesh == int(b[0]) and n.mesh >= 0 and n.mesh < state.get_meshes().size():
						var mesh: ImporterMesh = state.get_meshes()[n.mesh].mesh
						if int(b[1]) >= 0 and int(b[1]) < mesh.get_blend_shape_count():
							binds.append([n.resource_name, str(mesh.get_blend_shape_name(int(b[1])))])
			effect.morph = binds
		for kind: String in ["scale", "material"]:
			if effect.has(kind):
				effect[kind].node = name_of.call(effect[kind])
		for region: Dictionary in effect.values()[0] if ExpressionDefinition.region(effect) != "" else []:
			region.node = name_of.call(region)
	for shown: Dictionary in out.get("shown", []):
		shown.node = name_of.call(shown)
	var looks: Variant = out.get("looks")
	if looks is Dictionary and looks.has("decals"):
		var kept: Variant = state.get_additional_data(&"vrm_decals")
		kept = kept if kept is Dictionary else {}
		looks.decals = _decal_indices(state.json).map(func(k: int) -> Variant: return kept.get(k))
	return out


static var _registered := false


static func _doc() -> GLTFDocument:
	if not _registered:
		GLTFDocument.register_gltf_document_extension(Images.new(), true)
		GLTFDocument.register_gltf_document_extension(Skins.new(), true)
		GLTFDocument.register_gltf_document_extension(Vrm.new())
		_registered = true
	return GLTFDocument.new()


## Reads a .vrm (binary glTF) into a scene whose root carries the humanoid metadata; `fits`, given each image's size
## before it is decoded, refuses the file by answering false; `image` may change each image as it is decoded, and
## `shape`, given the parsed state, its meshes and materials before the scene is made, refuses the file by answering
## false. Null if the file is not one.
static func read(bytes: PackedByteArray, fits: Callable, shape: Callable, image: Callable) -> Node3D:
	var doc := _doc()
	var state := GLTFState.new()
	state.set_additional_data(&"vrm_fits", fits)
	state.set_additional_data(&"vrm_image", image)
	state.set_additional_data(&"vrm_refused", false)
	state.set_additional_data(&"vrm_means", [])
	state.set_additional_data(&"vrm_image_at", 0)
	state.set_additional_data(&"vrm_decals", {})
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	state.create_animations = false
	if doc.append_from_buffer(bytes, "", state) != OK or state.get_additional_data(&"vrm_refused"):
		return null
	var colour := _colour(state.json, state.get_additional_data(&"vrm_means"))
	if not shape.call(state):
		return null
	var root := doc.generate_scene(state) as Node3D
	if root != null:
		root.set_meta("colour", colour)
	return root


## An image's mean colour over its covered texels, each weighed by its alpha: a hair card's clear texels show nothing.
static func _mean(img: Image) -> Color:
	var m := img.duplicate() as Image
	m.clear_mipmaps()
	m.convert(Image.FORMAT_RGBA8)
	m.premultiply_alpha()
	m.generate_mipmaps()
	var c := Image.create_from_data(1, 1, false, Image.FORMAT_RGBA8, m.get_data().slice(m.get_mipmap_offset(m.get_mipmap_count()))).get_pixel(0, 0)
	return Color(c.r / c.a, c.g / c.a, c.b / c.a) if c.a > 0.0 else Color.WHITE


## The model's colour: each primitive's base colour, its material's factor times the mean of its base colour image
## (`means`, one for each of the file's images), averaged weighed by the primitive's indices, or vertices where it has
## none. The file is a player's, so any part not shaped as glTF has it counts as white or nothing rather than failing.
static func _colour(json: Dictionary, means: Array) -> Color:
	var materials: Variant = json.get("materials")
	var textures: Variant = json.get("textures")
	var accessors: Variant = json.get("accessors")
	var meshes: Variant = json.get("meshes")
	if not (materials is Array and textures is Array and accessors is Array and meshes is Array):
		return Color.WHITE
	var sum := Color(0, 0, 0, 0)
	for mesh: Variant in meshes:
		var primitives: Variant = mesh.get("primitives") if mesh is Dictionary else null
		if not primitives is Array:
			continue
		for primitive: Variant in primitives:
			if not primitive is Dictionary:
				continue
			var attributes: Variant = primitive.get("attributes")
			var counted: Variant = primitive.get("indices", attributes.get("POSITION") if attributes is Dictionary else null)
			var accessor: Variant = accessors[int(counted)] if _index(counted, accessors) else null
			var n: Variant = accessor.get("count") if accessor is Dictionary else null
			if not (n is int or n is float) or n <= 0:
				continue
			var c := Color.WHITE
			var material: Variant = materials[int(primitive.material)] if _index(primitive.get("material"), materials) else null
			var pbr: Variant = material.get("pbrMetallicRoughness") if material is Dictionary else null
			if pbr is Dictionary:
				var f: Variant = pbr.get("baseColorFactor")
				if f is Array and f.size() >= 3 and f.slice(0, 3).all(func(v: Variant) -> bool: return v is int or v is float):
					c = Color(f[0], f[1], f[2])
				var tex: Variant = pbr.get("baseColorTexture")
				var texture: Variant = textures[int(tex.index)] if tex is Dictionary and _index(tex.get("index"), textures) else null
				if texture is Dictionary and _index(texture.get("source"), means):
					c *= (means[int(texture.source)] as Color).srgb_to_linear()
			sum += Color(c.r * n, c.g * n, c.b * n, n)
	if sum.a <= 0.0:
		return Color.WHITE
	return Color(sum.r / sum.a, sum.g / sum.a, sum.b / sum.a).linear_to_srgb()


## Whether `i` is a whole number indexing `into`.
static func _index(i: Variant, into: Array) -> bool:
	return (i is int or (i is float and i == floorf(i))) and int(i) >= 0 and int(i) < into.size()


## Each skin is written binding every bone of its skeleton: a bone no skin binds would read back as a plain node, and
## a read skin keeps only the bones its vertices weigh (Skins).
static func write(root: Node3D, path: String) -> void:
	var doc := _doc()
	doc.visibility_mode = GLTFDocument.VISIBILITY_MODE_INCLUDE_OPTIONAL
	doc.image_format = "Lossless WebP"
	var state := GLTFState.new()
	var worn := {}
	var full := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if mi.skin != null and skeleton != null:
			worn[mi] = mi.skin
			if not full.has([mi.skin, skeleton]):
				full[[mi.skin, skeleton]] = _binding_every_bone(mi.skin, skeleton)
			mi.skin = full[[mi.skin, skeleton]]
	var err := doc.append_from_scene(root, state)
	var glb := doc.generate_buffer(state) if err == OK else PackedByteArray()
	for mi: MeshInstance3D in worn:
		mi.skin = worn[mi]
	assert(err == OK, "vrm: cannot export %s" % root.name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(_positional(glb))


static func _binding_every_bone(skin: Skin, skeleton: Skeleton3D) -> Skin:
	var bound := {}
	for i in skin.get_bind_count():
		bound[skin.get_bind_bone(i) if skin.get_bind_bone(i) >= 0 else skeleton.find_bone(skin.get_bind_name(i))] = true
	var full := skin.duplicate() as Skin
	for b in skeleton.get_bone_count():
		if not bound.has(b):
			full.add_bind(b, skeleton.get_bone_global_rest(b).affine_inverse())
			full.set_bind_name(full.get_bind_count() - 1, skeleton.get_bone_name(b))
	return full


## The binary glTF `glb` with each morph target's normals the turn its positions give its mesh's smooth normals, and no
## tangents. Godot writes a target's normals and tangents as unit vectors rather than their change and keeps none an
## importer hands it, so its own would turn every normal of the mesh; a shape's normals follow from its moved surface, as
## Unity computes them by default.
static func _positional(glb: PackedByteArray) -> PackedByteArray:
	var json_size := glb.decode_u32(12)
	var json: Dictionary = JSON.parse_string(glb.slice(20, 20 + json_size).get_string_from_utf8())
	var bin := glb.slice(28 + json_size, 28 + json_size + glb.decode_u32(20 + json_size))
	var views: Array = json.bufferViews
	var accessors: Array = json.accessors
	var data := views.map(func(v: Dictionary) -> PackedByteArray: return bin.slice(int(v.get("byteOffset", 0)), int(v.get("byteOffset", 0)) + int(v.byteLength)))
	for mesh: Dictionary in json.get("meshes", []):
		for primitive: Dictionary in mesh.primitives:
			var targets: Array = primitive.get("targets", [])
			for target: Dictionary in targets:
				for k: String in ["NORMAL", "TANGENT"]:
					if target.has(k):
						(accessors[int(target[k])] as Dictionary).erase("bufferView")
						target.erase(k)
			if targets.is_empty():
				continue
			var turns := _shape_normals(primitive, accessors, views, data)
			for t in targets.size():
				var vertices: PackedInt32Array = turns[t][0]
				if vertices.is_empty():
					continue
				var values: PackedVector3Array = turns[t][1]
				var indices := PackedByteArray()
				indices.resize(vertices.size() * 4)
				var floats := PackedByteArray()
				floats.resize(values.size() * 12)
				for k in vertices.size():
					indices.encode_u32(k * 4, vertices[k])
					for c in 3:
						floats.encode_float(k * 12 + c * 4, values[k][c])
				for bytes: PackedByteArray in [indices, floats]:
					views.append({"buffer": 0, "byteLength": bytes.size()})
					data.append(bytes)
				accessors.append({"componentType": 5126, "count": accessors[int(primitive.attributes.POSITION)].count, "type": "VEC3", "sparse": {"count": vertices.size(), "indices": {"bufferView": views.size() - 2, "componentType": 5125}, "values": {"bufferView": views.size() - 1}}})
				(targets[t] as Dictionary).NORMAL = accessors.size() - 1
	var refs := []
	for acc: Dictionary in accessors:
		refs.append([acc, "bufferView"])
		if acc.has("sparse"):
			refs.append([acc.sparse.indices, "bufferView"])
			refs.append([acc.sparse.values, "bufferView"])
	for image: Dictionary in json.get("images", []):
		refs.append([image, "bufferView"])
	var kept := {}
	for r: Array in refs:
		if (r[0] as Dictionary).has(r[1]):
			kept[int(r[0][r[1]])] = true
	var renumbered := {}
	var out_views := []
	var out_bin := PackedByteArray()
	for v in views.size():
		if not kept.has(v):
			continue
		renumbered[v] = out_views.size()
		var view: Dictionary = views[v].duplicate()
		view.byteOffset = out_bin.size()
		out_views.append(view)
		out_bin.append_array(data[v])
		out_bin.resize((out_bin.size() + 3) & ~3)
	for r: Array in refs:
		if (r[0] as Dictionary).has(r[1]):
			r[0][r[1]] = renumbered[int(r[0][r[1]])]
	json.bufferViews = out_views
	json.buffers = [{"byteLength": out_bin.size()}]
	var text := JSON.stringify(_whole(json), "", false, true).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var out := PackedByteArray()
	out.resize(28 + text.size())
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(12, text.size())
	out.encode_u32(16, 0x4E4F534A)
	for i in text.size():
		out[20 + i] = text[i]
	out.encode_u32(20 + text.size(), out_bin.size())
	out.encode_u32(24 + text.size(), 0x004E4942)
	out.append_array(out_bin)
	out.encode_u32(8, out.size())
	return out


## For each of `primitive`'s morph targets [the vertices whose normal it turns, ascending, and each one's change]: a
## vertex's normal is the area-weighted sum of the faces around every vertex at its position, with the target's positions
## moved and without.
static func _shape_normals(primitive: Dictionary, accessors: Array, views: Array, data: Array) -> Array:
	var positions := _vec3s(accessors[int(primitive.attributes.POSITION)], views, data)
	var count := positions.size()
	var faces: PackedInt32Array
	if primitive.has("indices"):
		var acc: Dictionary = accessors[int(primitive.indices)]
		faces = _integers(acc, int(acc.count), data)
	else:
		faces = PackedInt32Array(range(count))
	var welded := PackedInt32Array()
	welded.resize(count)
	var first := {}
	for i in count:
		welded[i] = first.get_or_add(positions[i], i)
	var base := PackedVector3Array()
	base.resize(count)
	for f in range(0, faces.size(), 3):
		var n := _face(positions, faces, f)
		for c in 3:
			base[welded[faces[f + c]]] += n
	var corners := PackedInt32Array()
	corners.resize(faces.size())
	for k in faces.size():
		corners[k] = k - k % 3
	var around := _groups(count, faces, corners)
	var faces_at: PackedInt32Array = around[0]
	var faces_of: PackedInt32Array = around[1]
	var members := _groups(count, welded, PackedInt32Array(range(count)))
	var members_at: PackedInt32Array = members[0]
	var members_of: PackedInt32Array = members[1]
	var out := []
	for target: Dictionary in primitive.targets:
		var moves := _vec3s(accessors[int(target.POSITION)], views, data)
		var moved := positions.duplicate()
		var touched := {}
		for i in count:
			if moves[i] != Vector3.ZERO:
				moved[i] += moves[i]
				for k in range(faces_at[i], faces_at[i + 1]):
					touched[faces_of[k]] = true
		var sums := {}
		for f: int in touched:
			var change := _face(moved, faces, f) - _face(positions, faces, f)
			for c in 3:
				var w := welded[faces[f + c]]
				sums[w] = sums.get(w, base[w]) + change
		var vertices := PackedInt32Array()
		var values := PackedVector3Array()
		for w: int in sums:
			var turn: Vector3 = (sums[w] as Vector3).normalized() - base[w].normalized()
			if turn.length_squared() < 1e-12:
				continue
			for k in range(members_at[w], members_at[w + 1]):
				vertices.append(members_of[k])
				values.append(turn)
		var order := Array(range(vertices.size()))
		order.sort_custom(func(a: int, b: int) -> bool: return vertices[a] < vertices[b])
		out.append([PackedInt32Array(order.map(func(k: int) -> int: return vertices[k])), PackedVector3Array(order.map(func(k: int) -> Vector3: return values[k]))])
	return out


## The face at `faces[f]`, `faces[f + 1]`, `faces[f + 2]` of `positions`: counterclockwise, as glTF winds a front face,
## its normal scaled by twice its area.
static func _face(positions: PackedVector3Array, faces: PackedInt32Array, f: int) -> Vector3:
	var a := positions[faces[f]]
	return (positions[faces[f + 1]] - a).cross(positions[faces[f + 2]] - a)


## `values` grouped by their `keys`, each below `count`, as [offsets, grouped]: key i's values are grouped[offsets[i]] to
## grouped[offsets[i + 1]], in their order in `values`.
static func _groups(count: int, keys: PackedInt32Array, values: PackedInt32Array) -> Array:
	var offsets := PackedInt32Array()
	offsets.resize(count + 1)
	for key in keys:
		offsets[key + 1] += 1
	for i in count:
		offsets[i + 1] += offsets[i]
	var grouped := PackedInt32Array()
	grouped.resize(keys.size())
	var next := offsets.duplicate()
	for k in keys.size():
		grouped[next[keys[k]]] = values[k]
		next[keys[k]] += 1
	return [offsets, grouped]


## A float VEC3 accessor's values, its sparse ones over its dense or zero base.
static func _vec3s(acc: Dictionary, views: Array, data: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(int(acc.count))
	if acc.has("bufferView"):
		var bytes: PackedByteArray = data[int(acc.bufferView)]
		var stride := int((views[int(acc.bufferView)] as Dictionary).get("byteStride", 12))
		var at := int(acc.get("byteOffset", 0))
		for i in out.size():
			out[i] = _vec3(bytes, at + i * stride)
	if acc.has("sparse"):
		var sparse: Dictionary = acc.sparse
		var indices := _integers(sparse.indices, int(sparse.count), data)
		var bytes: PackedByteArray = data[int(sparse.values.bufferView)]
		var at := int(sparse.values.get("byteOffset", 0))
		for k in indices.size():
			out[indices[k]] = _vec3(bytes, at + k * 12)
	return out


static func _vec3(bytes: PackedByteArray, at: int) -> Vector3:
	return Vector3(bytes.decode_float(at), bytes.decode_float(at + 4), bytes.decode_float(at + 8))


## `count` unsigned integers from `ref`'s buffer view, as an index accessor or a sparse accessor's indices hold them.
static func _integers(ref: Dictionary, count: int, data: Array) -> PackedInt32Array:
	var bytes: PackedByteArray = data[int(ref.bufferView)]
	var at := int(ref.get("byteOffset", 0))
	var out := PackedInt32Array()
	out.resize(count)
	match int(ref.componentType):
		5121:
			for i in count:
				out[i] = bytes.decode_u8(at + i)
		5123:
			for i in count:
				out[i] = bytes.decode_u16(at + i * 2)
		_:
			for i in count:
				out[i] = bytes.decode_u32(at + i * 4)
	return out


## `v` with every whole number JSON read as a float an integer again, as glTF writes its indices and counts.
static func _whole(v: Variant) -> Variant:
	if v is Dictionary:
		for k: String in v:
			v[k] = _whole(v[k])
	elif v is Array:
		for i in (v as Array).size():
			v[i] = _whole(v[i])
	elif v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	return v
