extends RefCounted

## Unity scenes and prefabs flattened into one object table per document, as Unity would instantiate them: each
## prefab instance (of a .prefab, or of a model, whose objects are synthesized from the model file) is expanded with
## its modifications applied, and its objects take the file IDs Unity gives them in the instancing document,
## (instance ID ^ source ID) & 0x7FFFFFFFFFFFFFFF. A stripped object, the instancing document's handle on an object of
## an instance, is the same entry as that object.

const Yaml = preload("res://../scripts/unity/yaml.gd")
const Assets = preload("res://../scripts/unity/assets.gd")
const XXHash = preload("res://../scripts/unity/xxhash.gd")
const FbxSlots = preload("res://../scripts/unity/fbx_slots.gd")

const MASK := 0x7FFFFFFFFFFFFFFF
## The path Unity's model importer hashes the model's own GameObject by; its nodes' paths extend it.
const ROOT := "//RootNode/root"
const MODELS := ["fbx", "obj", "dae", "blend", "gltf", "glb"]
## The renderer components, by the class ID an animation clip names each with.
const RENDERERS := {"SkinnedMeshRenderer": "137", "MeshRenderer": "23"}

var assets: Assets
## Models by GUID: {"state": the FBXState, "scene": the scene Godot made of it, "objects": its Unity objects}.
var models := {}
var _flat := {}
## The paths of the models Godot cannot read.
var unread := {}


func _init(from: Assets) -> void:
	assets = from


## The objects of the scene or prefab with this GUID, or of a path's file, by file ID: {"type", "data", "guid" of the
## document that defined it}.
func flatten(guid: String) -> Dictionary:
	if not _flat.has(guid):
		_flat[guid] = _flatten_document(Yaml.objects(assets.text(guid)), guid) if not assets.extension(guid) in MODELS else model(guid).get("objects", {})
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
			continue
		var inner := flatten(sguid)
		var copies := {}
		for sid: int in inner:
			copies[sid] = {"type": inner[sid].type, "data": (inner[sid].data as Dictionary).duplicate(true), "guid": inner[sid].guid}
		for sid: int in copies:
			_remap(copies[sid].data, id)
		var mod: Dictionary = pi.get("m_Modification", {})
		for m: Variant in Yaml.list(mod.get("m_Modifications")):
			var t: Dictionary = m.get("target", {})
			var sid := Yaml.file_id(t)
			if copies.has(sid):
				_modify(copies[sid].data, str(m.get("propertyPath", "")), m.get("value", ""), m.get("objectReference", {}))
		for r: Variant in Yaml.list(mod.get("m_RemovedComponents")):
			copies.erase(Yaml.file_id(r))
		for r: Variant in Yaml.list(mod.get("m_RemovedGameObjects")):
			copies.erase(Yaml.file_id(r))
		var parent := Yaml.file_id(mod.get("m_TransformParent"))
		for sid: int in copies:
			var c: Dictionary = copies[sid]
			if c.type == "Transform" or c.type == "RectTransform":
				if Yaml.file_id(c.data.get("m_Father", {})) == 0:
					c.data["m_Father"] = {"fileID": str(parent)}
			out[(id ^ sid) & MASK] = c
	for id: int in objs:
		var o: Dictionary = objs[id]
		if not o.stripped:
			continue
		var src: Dictionary = o.data.get("m_CorrespondingSourceObject", o.data.get("m_PrefabParentObject", {}))
		var instance := Yaml.file_id(o.data.get("m_PrefabInstance", o.data.get("m_PrefabInternal")))
		var key := (instance ^ Yaml.file_id(src)) & MASK
		if out.has(key):
			out[id] = out[key]
	# A component this document adds to an instanced object names the object, whose own list holds only its source's.
	for id: int in objs:
		var o: Dictionary = objs[id]
		var go := Yaml.file_id(o.data.get("m_GameObject"))
		if o.stripped or o.class == 1001 or not objs.has(go) or not objs[go].stripped or not out.has(go):
			continue
		var listed := Yaml.list(out[go].data.get("m_Component"))
		listed.append({"component": {"fileID": str(id)}})
		out[go].data["m_Component"] = listed
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
	var v: Variant = reference if Yaml.file_id(reference) != 0 else value
	for i in parts.size():
		var p := parts[i]
		var last := i == parts.size() - 1
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


## The file ids of a GameObject's components in `objs`, in its order.
static func components(objs: Dictionary, go: int) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in Yaml.list(objs.get(go, {}).get("data", {}).get("m_Component")):
		out.append(Yaml.file_id((c as Dictionary).get("component")))
	return out


## The transform `t` in `objs` and each transform above it, nearest first, up its m_Father chain.
static func ancestors(objs: Dictionary, t: int) -> Array[int]:
	var out: Array[int] = []
	while objs.has(t) and not out.has(t):
		out.append(t)
		t = Yaml.file_id(objs[t].data.get("m_Father"))
	return out


## Whether GameObject `go` is tagged EditorOnly, which Unity strips from every build.
static func editor_only(objs: Dictionary, go: int) -> bool:
	return str(objs.get(go, {}).get("data", {}).get("m_TagString", "")) == "EditorOnly"


## The Transform of a GameObject in `objs`, or 0.
static func transform_of(objs: Dictionary, go: int) -> int:
	for id: int in components(objs, go):
		if objs.has(id) and objs[id].type in ["Transform", "RectTransform"]:
			return id
	return 0


## The renderer on a GameObject in `objs`, or 0.
static func renderer_of(objs: Dictionary, go: int) -> int:
	for id: int in components(objs, go):
		if objs.has(id) and RENDERERS.has(objs[id].type):
			return id
	return 0


## The names of the materials on `mesh`'s surfaces (an ArrayMesh or ImporterMesh), in surface order; "" for none.
static func surface_names(mesh: Variant) -> Array:
	var names := []
	for i: int in mesh.get_surface_count():
		var m: Material = mesh.surface_get_material(i) if mesh is Mesh else mesh.get_surface_material(i)
		names.append(String(m.resource_name) if m != null else "")
	return names


## The model with this GUID, imported once; empty if Godot cannot read it. Its "objects" are as Unity's importer makes
## them: a GameObject and Transform for the model and each node in it, and for each node with a mesh a
## SkinnedMeshRenderer (or MeshFilter and MeshRenderer for an unskinned one) whose materials are those the model's .meta
## remaps, by name, or a material of that name in the package, in Unity's slot order: the order the node's polygons first
## use them, which Godot's surfaces need not keep. Its "slots" are that order by FBX model name (FbxSlots).
func model(guid: String) -> Dictionary:
	if models.has(guid):
		return models[guid]
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.create_animations = false
	state.handle_binary_image = GLTFState.HANDLE_BINARY_DISCARD_TEXTURES
	if not assets.extension(guid) == "fbx" or doc.append_from_file(assets.by_guid[guid].file, state) != OK:
		unread[assets.by_guid[guid].path] = true
		models[guid] = {}
		return {}
	var scene := doc.generate_scene(state) as Node3D
	var meta := assets.meta(guid)
	var importer: Dictionary = meta.get("ModelImporter", {})
	var recycled := {}
	for id: Variant in (importer.get("fileIDToRecycleName", {}) as Dictionary):
		recycled[[str(id).to_int() / 100000, importer.fileIDToRecycleName[id]]] = str(id).to_int()
	for e: Variant in Yaml.list(importer.get("internalIDToNameTable")):
		var first: Dictionary = (e as Dictionary).get("first", {})
		for cls: Variant in first:
			recycled[[str(cls).to_int(), str(e.get("second", ""))]] = str(first[cls]).to_int()
	var remapped := {}
	for e: Variant in Yaml.list(importer.get("externalObjects")):
		var first: Dictionary = (e as Dictionary).get("first", {})
		if str(first.get("type", "")) == "UnityEngine:Material":
			remapped[str(first.get("name", ""))] = e.get("second", {})
	var slots := FbxSlots.slots(assets.by_guid[guid].file)
	var by_name := {}
	for m: String in assets.of(["mat"]):
		by_name.get_or_add(assets.name(m), m)
	var nodes := state.get_nodes()
	var objects := {}
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
			var surfaces := surface_names(gm.mesh)
			var order: Array = slots.get(name, [])
			var listed: Array = order if not order.is_empty() and surfaces.all(func(n: String) -> bool: return n in order) else surfaces
			var materials := []
			for mname: String in listed:
				var ref: Dictionary = remapped.get(mname, {})
				if ref.is_empty() and by_name.has(mname):
					ref = {"fileID": "2100000", "guid": by_name[mname]}
				materials.append(ref if not ref.is_empty() else {"fileID": "0", "name": mname})
			var skinned := node.skin >= 0 or gm.mesh.get_blend_shape_count() > 0
			var type := "SkinnedMeshRenderer" if skinned else "MeshRenderer"
			var r: int = id_of.call(137 if skinned else 23, type, unity_path + "/" + type, name)
			var mesh_id: int = id_of.call(43, "Mesh", name, name)
			components.append({"component": {"fileID": str(r)}})
			objects[r] = {"type": type, "guid": guid, "node": item[0], "data": {"m_GameObject": {"fileID": str(go)}, "m_Enabled": "1", "m_Mesh": {"fileID": str(mesh_id), "guid": guid}, "m_Materials": materials, "m_BlendShapeWeights": Array(gm.get_blend_weights()).map(func(w: float) -> String: return str(snappedf(w * 100.0, 1e-4)))}}
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
	models[guid] = {"state": state, "scene": scene, "objects": objects, "slots": slots}
	return models[guid]


## Field `k` of a Unity vector or quaternion `v`, `otherwise` where it has none.
static func number(v: Variant, k: String, otherwise := 0.0) -> float:
	return str((v as Dictionary).get(k, otherwise)).to_float() if v is Dictionary else otherwise


## A Unity rotation in Godot's axes (X mirrored), the identity where it has none.
static func turn(q: Variant) -> Quaternion:
	var rot := Quaternion(number(q, "x"), -number(q, "y"), -number(q, "z"), number(q, "w", 1.0))
	return rot.normalized() if rot.length() > 0.0 else Quaternion.IDENTITY


## A Unity position in Godot's axes (X mirrored), the origin where it has none.
static func mirrored(v: Variant) -> Vector3:
	return Vector3(-number(v, "x"), number(v, "y"), number(v, "z"))


## A transform as glTF's column-major matrix.
static func matrix(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, 0, t.basis.y.x, t.basis.y.y, t.basis.y.z, 0, t.basis.z.x, t.basis.z.y, t.basis.z.z, 0, t.origin.x, t.origin.y, t.origin.z, 1]
