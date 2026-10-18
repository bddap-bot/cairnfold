class_name Vrm
extends GLTFDocumentExtension

## The humanoid part of VRM 1.0 (VRMC_vrm) and VRM 0.x (VRM): which glTF nodes are the head, hands and the rest
## of the body, where the eyes sit relative to the head bone, and which way the model faces. Export writes VRM
## 1.0 from nodes named after the bones (and the scene root's "eyes" metadata); import records on the scene root
## the metadata "humanoid" (bone name to the node's path from the root, with the bone's name as the subname when
## it is a skeleton's bone), "eyes" and "forward". Materials, spring bones and expressions are not read.

const BONES := ["hips", "spine", "head", "leftUpperArm", "leftLowerArm", "leftHand", "rightUpperArm", "rightLowerArm", "rightHand", "leftUpperLeg", "leftLowerLeg", "leftFoot", "rightUpperLeg", "rightLowerLeg", "rightFoot"]


func _get_supported_extensions() -> PackedStringArray:
	return PackedStringArray(["VRMC_vrm", "VRM"])


## Files come from other players, so every field is checked for its type before use.
func _import_post(state: GLTFState, root: Node) -> Error:
	var exts: Variant = state.json.get("extensions")
	exts = exts if exts is Dictionary else {}
	var found := {}
	var eyes := Vector3(0, 0.06, 0)
	var forward := Vector3.BACK
	if exts.get("VRMC_vrm") is Dictionary:
		var vrm: Dictionary = exts.VRMC_vrm
		var human: Variant = _field(_field(vrm, "humanoid"), "humanBones")
		if human is Dictionary:
			for bone in human:
				_bind(found, str(bone), _field(human[bone], "node"), state, root)
		var off: Variant = _field(_field(vrm, "lookAt"), "offsetFromHeadBone")
		if off is Array and off.size() == 3 and off.all(func(x: Variant) -> bool: return x is float):
			eyes = Vector3(off[0], off[1], off[2])
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
	root.set_meta("humanoid", found)
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
	return OK


func _export_post(state: GLTFState) -> Error:
	var bones := {}
	var nodes := state.get_nodes()
	for i in nodes.size():
		var name := nodes[i].resource_name
		if name in BONES:
			bones[name] = {"node": i}
	var eyes: Vector3 = state.get_additional_data(&"eyes")
	var exts: Dictionary = state.json.get_or_add("extensions", {})
	exts["VRMC_vrm"] = {
		"specVersion": "1.0",
		"meta": {"name": state.get_scene_name(), "authors": [ProjectSettings.get_setting("application/config/name")], "licenseUrl": "https://vrm.dev/licenses/1.0/", "avatarPermission": "everyone", "commercialUsage": "corporation", "modification": "allowModificationRedistribution"},
		"humanoid": {"humanBones": bones},
		"lookAt": {"offsetFromHeadBone": [eyes.x, eyes.y, eyes.z]},
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
