extends RefCounted

## Unity scenes and prefabs flattened into one object table per document, as Unity would instantiate them: each
## prefab instance (of a .prefab, or of a model, whose objects are synthesized from the model file) is expanded with
## its modifications applied, and its objects take the file IDs Unity gives them in the instancing document,
## (instance ID ^ source ID) & 0x7FFFFFFFFFFFFFFF. A stripped object, the instancing document's handle on an object of
## an instance, is the same entry as that object.

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const XXHash = preload("res://../scripts/unity/xxhash.gd")

const MASK := 0x7FFFFFFFFFFFFFFF
## The path Unity's model importer hashes the model's own GameObject by; its nodes' paths extend it.
const ROOT := "//RootNode/root"
const MODELS := ["fbx", "obj", "dae", "blend", "gltf", "glb"]

var assets: Assets
## Models by GUID: {"state": the FBXState, "scene": the scene Godot made of it, "objects": its Unity objects, "names": node index to its Unity name}.
var models := {}
var _flat := {}
## What was met and not followed, each once: a prefab GUID missing from the package, a model Godot cannot read.
var missing := {}


func _init(from: Assets) -> void:
	assets = from


## The objects of the scene or prefab with this GUID, or of a path's file, by file ID: {"type", "data", "guid" of the
## document that defined it}.
func flatten(guid: String) -> Dictionary:
	if not _flat.has(guid):
		_flat[guid] = _flatten_document(Yaml.objects(assets.text(guid)), guid) if not assets.extension(guid) in MODELS else _model_objects(guid)
	return _flat[guid]


func _flatten_document(objs: Dictionary, guid: String) -> Dictionary:
	var out := {}
	for id: int in objs:
		var o: Dictionary = objs[id]
		if not o.stripped and o.class != 1001:
			out[id] = {"type": o.type, "data": o.data, "guid": guid}
	for id: int in objs:
		var o: Dictionary = objs[id]
		if o.class != 1001:
			continue
		var pi: Dictionary = o.data
		var source: Dictionary = pi.get("m_SourcePrefab", pi.get("m_ParentPrefab", {}))
		var sguid: String = source.get("guid", "")
		if not assets.by_guid.has(sguid):
			missing["prefab " + sguid] = true
			continue
		var inner := flatten(sguid)
		var copies := {}
		for sid: int in inner:
			copies[sid] = {"type": inner[sid].type, "data": (inner[sid].data as Dictionary).duplicate(true), "guid": inner[sid].guid}
		for sid: int in copies:
			_remap(copies[sid].data, id)
		var mod: Dictionary = pi.get("m_Modification", {})
		for m: Variant in _list(mod.get("m_Modifications")):
			var t: Dictionary = m.get("target", {})
			var sid := str(t.get("fileID", "0")).to_int()
			if copies.has(sid):
				_modify(copies[sid].data, str(m.get("propertyPath", "")), m.get("value", ""), m.get("objectReference", {}))
		for r: Variant in _list(mod.get("m_RemovedComponents")):
			copies.erase(str((r as Dictionary).get("fileID", "0")).to_int())
		for r: Variant in _list(mod.get("m_RemovedGameObjects")):
			copies.erase(str((r as Dictionary).get("fileID", "0")).to_int())
		var parent := str((mod.get("m_TransformParent", {}) as Dictionary).get("fileID", "0")).to_int()
		for sid: int in copies:
			var c: Dictionary = copies[sid]
			if c.type == "Transform" or c.type == "RectTransform":
				var father: Dictionary = c.data.get("m_Father", {})
				if str(father.get("fileID", "0")) == "0":
					c.data["m_Father"] = {"fileID": str(parent)}
			out[(id ^ sid) & MASK] = c
	for id: int in objs:
		var o: Dictionary = objs[id]
		if not o.stripped:
			continue
		var src: Dictionary = o.data.get("m_CorrespondingSourceObject", o.data.get("m_PrefabParentObject", {}))
		var instance := str((o.data.get("m_PrefabInstance", o.data.get("m_PrefabInternal", {})) as Dictionary).get("fileID", "0")).to_int()
		var key := (instance ^ str(src.get("fileID", "0")).to_int()) & MASK
		if out.has(key):
			out[id] = out[key]
	return out


## Rewrites every same-document reference in `data` as the instancing document sees it.
static func _remap(data: Variant, instance: int) -> void:
	if data is Dictionary:
		if data.has("fileID") and not data.has("guid") and data.size() <= 2:
			var f := str(data.fileID).to_int()
			if f != 0:
				data.fileID = str((instance ^ f) & MASK)
			return
		for k: Variant in data:
			_remap(data[k], instance)
	elif data is Array:
		for v: Variant in data:
			_remap(v, instance)


## Applies one modification: `path` is a field path such as m_LocalScale.x or m_Materials.Array.data[2].
static func _modify(data: Dictionary, path: String, value: Variant, reference: Variant) -> void:
	var parts := path.replace(".Array.data[", ".[").split(".")
	var at: Variant = data
	for i in parts.size():
		var p := parts[i]
		var last := i == parts.size() - 1
		var ref := reference is Dictionary and str((reference as Dictionary).get("fileID", "0")) != "0"
		var v: Variant = reference if ref else value
		if p == "Array" and i + 1 < parts.size() and parts[i + 1] == "size":
			return
		if p.begins_with("[") and at is Array:
			var k := p.trim_prefix("[").trim_suffix("]").to_int()
			while (at as Array).size() <= k:
				(at as Array).append("" if last else {})
			if last:
				at[k] = v
				return
			at = at[k]
		elif at is Dictionary:
			if last:
				at[p] = v
				return
			if parts[i + 1] == "Array" and parts.size() > i + 2 and parts[i + 2] == "size":
				var n := str(value).to_int()
				var arr: Array = at.get(p) if at.get(p) is Array else []
				arr.resize(n)
				for j in n:
					if arr[j] == null:
						arr[j] = ""
				at[p] = arr
				return
			if not at.get(p) is Dictionary and not at.get(p) is Array:
				at[p] = [] if parts[i + 1].begins_with("[") else {}
			at = at[p]
		else:
			return


static func _list(v: Variant) -> Array:
	return v if v is Array else []


## A model's objects as Unity's importer makes them: a GameObject and Transform for the model and each node in it, and
## for each node with a mesh a SkinnedMeshRenderer (or MeshFilter and MeshRenderer for an unskinned one) whose
## materials are those the model's .meta remaps, by name, or a material of that name in the package.
func _model_objects(guid: String) -> Dictionary:
	var model := model(guid)
	return model.objects if not model.is_empty() else {}


## The model with this GUID, imported once; empty if Godot cannot read it.
func model(guid: String) -> Dictionary:
	if models.has(guid):
		return models[guid]
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.create_animations = false
	state.handle_binary_image = GLTFState.HANDLE_BINARY_DISCARD_TEXTURES
	if not assets.extension(guid) == "fbx" or doc.append_from_file(assets.by_guid[guid].file, state) != OK:
		missing["model " + assets.by_guid[guid].path] = true
		models[guid] = {}
		return {}
	var scene := doc.generate_scene(state) as Node3D
	var meta := assets.meta(guid)
	var importer: Dictionary = meta.get("ModelImporter", {})
	var recycled := {}
	for id: Variant in (importer.get("fileIDToRecycleName", {}) as Dictionary):
		recycled[[str(id).to_int() / 100000, importer.fileIDToRecycleName[id]]] = str(id).to_int()
	for e: Variant in _list(importer.get("internalIDToNameTable")):
		var first: Dictionary = (e as Dictionary).get("first", {})
		for cls: Variant in first:
			recycled[[str(cls).to_int(), str(e.get("second", ""))]] = str(first[cls]).to_int()
	var remapped := {}
	for e: Variant in _list(importer.get("externalObjects")):
		var first: Dictionary = (e as Dictionary).get("first", {})
		if str(first.get("type", "")) == "UnityEngine:Material":
			remapped[str(first.get("name", ""))] = e.get("second", {})
	var by_name := {}
	for m: String in assets.of(["mat"]):
		by_name.get_or_add(assets.name(m), m)
	var nodes := state.get_nodes()
	var objects := {}
	var names := {}
	var used := {}
	var dupes := {}
	var id_of := func(cls: int, type: String, unity_path: String, name: String) -> int:
		var k := [cls, name]
		if not recycled.is_empty():
			var n: int = used.get(k, 0)
			used[k] = n + 1
			return recycled.get([cls, name if n == 0 else "%s %d" % [name, n]], 0)
		var key := "Type:%s->%s" % [type, unity_path]
		var d: int = dupes.get(key, 0)
		dupes[key] = d + 1
		return XXHash.file_id(type, unity_path, d)
	var root_name := assets.name(guid)
	var root_go: int = id_of.call(1, "GameObject", ROOT, "//RootNode")
	var root_tf: int = id_of.call(4, "Transform", ROOT + "/Transform", "//RootNode")
	objects[root_go] = {"type": "GameObject", "guid": guid, "data": {"m_Name": root_name, "m_IsActive": "1", "m_Component": [{"component": {"fileID": str(root_tf)}}]}}
	objects[root_tf] = {"type": "Transform", "guid": guid, "data": {"m_GameObject": {"fileID": str(root_go)}, "m_Father": {"fileID": "0"}, "m_LocalScale": {"x": "1", "y": "1", "z": "1"}}}
	var pending := []
	var transforms := {}
	var renderer_skins := {}
	for r in state.root_nodes:
		pending.append([r, root_tf, ROOT])
	while not pending.is_empty():
		var item: Array = pending.pop_front()
		var node := nodes[item[0]]
		var name := node.original_name if node.original_name != "" else String(node.resource_name)
		var unity_path: String = item[2] + "/" + name
		names[item[0]] = name
		var go: int = id_of.call(1, "GameObject", unity_path, name)
		var tf: int = id_of.call(4, "Transform", unity_path + "/Transform", name)
		transforms[item[0]] = tf
		var components := [{"component": {"fileID": str(tf)}}]
		var s := node.scale
		var p := node.position
		var q := node.rotation
		objects[tf] = {"type": "Transform", "guid": guid, "node": item[0], "data": {"m_GameObject": {"fileID": str(go)}, "m_Father": {"fileID": str(item[1])}, "m_LocalPosition": {"x": str(-p.x), "y": str(p.y), "z": str(p.z)}, "m_LocalRotation": {"x": str(q.x), "y": str(-q.y), "z": str(-q.z), "w": str(q.w)}, "m_LocalScale": {"x": str(s.x), "y": str(s.y), "z": str(s.z)}}}
		if node.mesh >= 0:
			var gm := state.get_meshes()[node.mesh]
			var materials := []
			for i in gm.mesh.get_surface_count():
				var mat := gm.mesh.get_surface_material(i)
				var mname := String(mat.resource_name) if mat != null else ""
				var ref: Dictionary = remapped.get(mname, {})
				if ref.is_empty() and by_name.has(mname):
					ref = {"fileID": "2100000", "guid": by_name[mname]}
				materials.append(ref if not ref.is_empty() else {"fileID": "0", "name": mname})
			var skinned := node.skin >= 0 or gm.mesh.get_blend_shape_count() > 0
			var type := "SkinnedMeshRenderer" if skinned else "MeshRenderer"
			var r: int = id_of.call(137 if skinned else 23, type, unity_path + "/" + type, name)
			var mesh_id: int = id_of.call(43, "Mesh", name, name)
			components.append({"component": {"fileID": str(r)}})
			objects[r] = {"type": type, "guid": guid, "node": item[0], "data": {"m_GameObject": {"fileID": str(go)}, "m_Enabled": "1", "m_Mesh": {"fileID": str(mesh_id), "guid": guid}, "m_Materials": materials, "m_BlendShapeWeights": []}}
			if node.skin >= 0:
				renderer_skins[r] = node.skin
			if not skinned:
				var mf: int = id_of.call(33, "MeshFilter", unity_path + "/MeshFilter", name)
				components.append({"component": {"fileID": str(mf)}})
				objects[mf] = {"type": "MeshFilter", "guid": guid, "node": item[0], "data": {"m_GameObject": {"fileID": str(go)}, "m_Mesh": {"fileID": str(mesh_id), "guid": guid}}}
		objects[go] = {"type": "GameObject", "guid": guid, "node": item[0], "data": {"m_Name": name, "m_IsActive": "1", "m_Component": components}}
		for c in node.children:
			pending.append([c, tf, unity_path])
	for renderer: int in renderer_skins:
		var bones := []
		for joint in state.get_skins()[renderer_skins[renderer]].joints_original:
			bones.append({"fileID": str(transforms[joint])})
		objects[renderer].data["m_Bones"] = bones
	models[guid] = {"state": state, "scene": scene, "objects": objects, "names": names}
	return models[guid]
