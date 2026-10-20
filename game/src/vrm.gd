class_name Vrm
extends GLTFDocumentExtension

## The humanoid part of VRM 1.0 (VRMC_vrm) and VRM 0.x (VRM): which glTF nodes are the head, hands and the rest
## of the body, where the eyes sit relative to the head bone, and which way the model faces. Export writes VRM
## 1.0 from nodes named after the bones (and the scene root's "eyes" metadata); import records on the scene root
## the metadata "humanoid" (bone name to the node's path from the root, with the bone's name as the subname when
## it is a skeleton's bone), "eyes", "forward" and "look". Materials, spring bones and expressions other than the
## four that point the eyes are not read.
##
## "look" is how the model points its eyes (VRM lookAt): {"type": BONE or EXPRESSION, "ranges": the horizontal inner,
## horizontal outer, vertical down and vertical up range maps, each Vector2(largest input angle in degrees, output at
## it: degrees for eye bones, a weight for expressions), "shapes": for an expression model, each of LOOKS to its
## morph targets as [mesh node path, blend shape name, weight]}. Export writes "look"'s type and ranges.

const BONES := ["hips", "spine", "head", "leftEye", "rightEye", "leftUpperArm", "leftLowerArm", "leftHand", "rightUpperArm", "rightLowerArm", "rightHand", "leftUpperLeg", "leftLowerLeg", "leftFoot", "rightUpperLeg", "rightLowerLeg", "rightFoot"]
const BONE := "bone"
const EXPRESSION := "expression"
const RANGES := ["rangeMapHorizontalInner", "rangeMapHorizontalOuter", "rangeMapVerticalDown", "rangeMapVerticalUp"]
const LOOKS := ["lookLeft", "lookRight", "lookUp", "lookDown"]
## Each kept blend shape is a pass over its mesh's vertices every frame, so a file's look binds are cut to these.
const BINDS_PER_LOOK := 2


func _get_supported_extensions() -> PackedStringArray:
	return PackedStringArray(["VRMC_vrm", "VRM"])


## Files come from other players, so every field is checked for its type before use.
func _import_post(state: GLTFState, root: Node) -> Error:
	var exts: Variant = state.json.get("extensions")
	exts = exts if exts is Dictionary else {}
	var found := {}
	var eyes := Vector3(0, 0.06, 0)
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
				_bind(found, str(_field(b, "bone")), _field(b, "node"), state, root)
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
	var binds := look_binds(state)
	if not binds.is_empty():
		# Skinned meshes are rebuilt under their skeleton, out of reach of the state's node map; their names are unique.
		var meshes := {}
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			meshes[String(mi.name)] = root.get_path_to(mi)
		for dir: String in binds:
			for b: Array in binds[dir]:
				var path: Variant = meshes.get(state.get_nodes()[b[0]].resource_name)
				if path != null:
					look.shapes.get_or_add(dir, []).append([path, morph_name(b[1]), b[2]])
	root.set_meta("humanoid", found)
	root.set_meta("look", look)
	root.set_meta("eyes", eyes if eyes.is_finite() and eyes.length() < 1.0 else Vector3(0, 0.06, 0))
	root.set_meta("forward", forward)
	return OK


## Decodes each image as Godot's glTF reader does and hands it to the read's `image` before it becomes a texture:
## reading a texture back calls the rendering server, which answers a worker thread only from the main thread, so a
## game quitting mid-read would wait on the read forever.
func _parse_image_data(state: GLTFState, data: PackedByteArray, mime: String, out: Image) -> Error:
	var image: Variant = state.get_additional_data(&"vrm_image")
	if not (image is Callable and image.is_valid()):
		return OK
	if mime == "image/png":
		out.load_png_from_buffer(data)
	elif mime == "image/jpeg":
		out.load_jpg_from_buffer(data)
	if out.is_empty():
		out.load_png_from_buffer(data)
	if out.is_empty():
		out.load_jpg_from_buffer(data)
	if not out.is_empty():
		image.call(out)
	return OK


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


## The name a kept morph target goes by: Avatar.read keeps only the ones LOOKS set, and renames them so.
static func morph_name(morph: int) -> String:
	return "look %d" % morph


static func _number(x: Variant, low: float, high: float, otherwise: float) -> float:
	return clampf(x, low, high) if x is float and is_finite(x) else otherwise


static func _field(d: Variant, key: String) -> Variant:
	return d.get(key) if d is Dictionary else null


static func _bind(found: Dictionary, bone: String, node: Variant, state: GLTFState, root: Node) -> void:
	if not (bone in BONES and node is float and node >= 0 and node < state.get_nodes().size()):
		return
	var n := state.get_scene_node(int(node))
	if n is Skeleton3D:
		var name := state.get_nodes()[int(node)].resource_name
		if (n as Skeleton3D).find_bone(name) >= 0:
			found[bone] = NodePath("%s:%s" % [root.get_path_to(n), name])
	elif n is Node3D:
		found[bone] = root.get_path_to(n)


func _export_preflight(state: GLTFState, root: Node) -> Error:
	state.set_additional_data(&"eyes", root.get_meta("eyes", Vector3(0, 0.06, 0)))
	state.set_additional_data(&"look", root.get_meta("look", {}))
	return OK


func _export_post(state: GLTFState) -> Error:
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
	var exts: Dictionary = state.json.get_or_add("extensions", {})
	exts["VRMC_vrm"] = {
		"specVersion": "1.0",
		"meta": {"name": state.get_scene_name(), "authors": [ProjectSettings.get_setting("application/config/name")], "licenseUrl": "https://vrm.dev/licenses/1.0/", "avatarPermission": "everyone", "commercialUsage": "corporation", "modification": "allowModificationRedistribution"},
		"humanoid": {"humanBones": bones},
		"lookAt": look_at,
	}
	var used: Array = state.json.get_or_add("extensionsUsed", [])
	if not used.has("VRMC_vrm"):
		used.append("VRMC_vrm")
	return OK


static var _registered := false


static func _doc() -> GLTFDocument:
	if not _registered:
		GLTFDocument.register_gltf_document_extension(Vrm.new())
		_registered = true
	return GLTFDocument.new()


## Reads a .vrm (binary glTF) into a scene whose root carries the humanoid metadata; `image` may change each image
## as it is decoded, and `shape`, given the parsed state, its meshes and materials before the scene is made. Null if
## the file is not one.
static func read(bytes: PackedByteArray, shape := Callable(), image := Callable()) -> Node3D:
	var doc := _doc()
	var state := GLTFState.new()
	state.set_additional_data(&"vrm_image", image)
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	state.create_animations = false
	if doc.append_from_buffer(bytes, "", state) != OK:
		return null
	if shape.is_valid() and not shape.call(state):
		return null
	return doc.generate_scene(state) as Node3D


static func write(root: Node3D, path: String) -> void:
	var doc := _doc()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	assert(err == OK, "vrm: cannot export %s" % root.name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(doc.generate_buffer(state))
