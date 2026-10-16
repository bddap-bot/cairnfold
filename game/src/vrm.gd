class_name Vrm
extends GLTFDocumentExtension

## The humanoid part of VRM 1.0 (VRMC_vrm): which glTF nodes are the head, hands and the rest of the
## body, and where the eyes sit relative to the head bone. Export writes it from nodes named after
## the bones (and the scene root's "eyes" metadata); import records it on the scene root as metadata
## "humanoid" (bone name to the node's path from the root) and "eyes". Materials, spring bones and
## expressions are not read.

const BONES := ["hips", "spine", "head", "leftUpperArm", "leftLowerArm", "leftHand", "rightUpperArm", "rightLowerArm", "rightHand", "leftUpperLeg", "leftLowerLeg", "leftFoot", "rightUpperLeg", "rightLowerLeg", "rightFoot"]


func _get_supported_extensions() -> PackedStringArray:
	return PackedStringArray(["VRMC_vrm"])


func _import_post(state: GLTFState, root: Node) -> Error:
	var vrm: Dictionary = state.json.get("extensions", {}).get("VRMC_vrm", {})
	var human: Dictionary = vrm.get("humanoid", {}).get("humanBones", {})
	var found := {}
	for bone in human:
		var n := state.get_scene_node(int(human[bone].node))
		if n != null:
			found[bone] = root.get_path_to(n)
	root.set_meta("humanoid", found)
	var eyes: Array = vrm.get("lookAt", {}).get("offsetFromHeadBone", [0.0, 0.06, 0.0])
	root.set_meta("eyes", Vector3(eyes[0], eyes[1], eyes[2]))
	return OK


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


## Reads a .vrm (binary glTF) into a scene whose root carries the "humanoid" metadata.
static func read(path: String) -> Node3D:
	var doc := _doc()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(FileAccess.get_file_as_bytes(path), path.get_base_dir(), state)
	assert(err == OK, "vrm: cannot read %s (%s)" % [path, error_string(err)])
	return doc.generate_scene(state)


static func write(root: Node3D, path: String) -> void:
	var doc := _doc()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	assert(err == OK, "vrm: cannot export %s" % root.name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(doc.generate_buffer(state))
