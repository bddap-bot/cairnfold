extends SceneTree

## Imports the avatar in a Unity source package as the avatar model (Avatar.model) and writes it as a Godot scene: run
## from game/ as
## godot4 --headless --path . --script ../scripts/unity_avatar.gd -- PACKAGE OUT.scn [AVATAR]
## OUT.vrm writes it instead as the VRM a player wears: the avatars folder reads only VRM, since a worn file travels to
## every player met and a Godot scene can run code; Avatar.read reads it back into the same model.
## PACKAGE is a .unitypackage or an Assets folder with each asset's .meta beside it. The avatar is the GameObject
## bearing a VRChat avatar descriptor (AVATAR names it where there are several), as its scene or prefab instantiates
## it: the renderers active there, with their materials and blend shape weights, over the skeleton of its humanoid
## model, whose Unity Avatar definition is the bone map. A package without a descriptor converts its one humanoid model.
## The avatar becomes one mesh of every triangle its drawn renderers have and one atlas of the materials' colour
## textures; its blend shapes stay, set to their saved weights, and its PhysBones become spring chains. No VRM lies
## between: VRM cannot carry what later importer work adds to the model. The importer prints what it kept and dropped.

const Assets = preload("res://../scripts/unity/assets.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")
const FbxSlots = preload("res://../scripts/unity/fbx_slots.gd")
const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")

## Unity's HumanBodyBones names for the thumb, by the VRM 1.0 bone each one is.
const THUMB := {"ThumbProximal": "ThumbMetacarpal", "ThumbIntermediate": "ThumbProximal"}
const RENDERERS := ["SkinnedMeshRenderer", "MeshRenderer"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 3:
		printerr("usage: unity_avatar.gd PACKAGE OUT.scn [AVATAR]")
		quit(2)
		return
	var dir := unpacked(args[0])
	if dir == "":
		printerr("unity_avatar: cannot unpack %s" % args[0])
		quit(1)
		return
	var root := avatar_scene(dir, args[2] if args.size() == 3 else "")
	if root == null:
		quit(1)
		return
	var report: Dictionary = root.get_meta("report")
	if args[1].get_extension() == "vrm":
		wearable(root)
		Vrm.write(root, args[1])
		root.free()
		if Avatar.read(FileAccess.get_file_as_bytes(args[1])) == null:
			printerr("unity_avatar: Avatar.read refuses %s" % args[1])
			quit(1)
			return
		report["file bytes"] = FileAccess.get_size(args[1])
		for k: String in report:
			print("unity_avatar: %s: %s" % [k, report[k]])
		quit()
		return
	var scene := Avatar.model(root)
	if scene == null:
		printerr("unity_avatar: Avatar.model refuses it: it needs %s as bones of one skeleton and at most %d surfaces" % [Avatar.NEEDS, Avatar.MAX_SURFACES])
		quit(1)
		return
	if ResourceSaver.save(scene, args[1]) != OK:
		printerr("unity_avatar: cannot write %s" % args[1])
		quit(1)
		return
	report["file bytes"] = FileAccess.get_size(args[1])
	for k: String in report:
		print("unity_avatar: %s: %s" % [k, report[k]])
	quit()


## Makes the avatar's root exportable by Vrm.write: each humanoid bone renamed to its VRM name, and its springs as
## VRMC_springBone, each node by its bone's name.
static func wearable(root: Node3D) -> void:
	var human: Dictionary = root.get_meta("humanoid")
	var sk: Skeleton3D = root.get_node(str(human.hips).get_slice(":", 0))
	var renamed := {}
	for b: String in human:
		if b in Vrm.BONES:
			renamed[sk.find_bone((human[b] as NodePath).get_concatenated_subnames())] = b
	# Two passes, so a bone may take the name another humanoid bone is about to give up.
	for i: int in renamed:
		sk.set_bone_name(i, "unity_avatar %d" % i)
	for i: int in renamed:
		sk.set_bone_name(i, renamed[i])
	var chains: Dictionary = root.get_meta("springs")
	var v := func(x: Vector3) -> Array: return [x.x, x.y, x.z]
	var colliders := []
	for c: Dictionary in chains.get("colliders", []):
		colliders.append({"node": sk.get_bone_name(c.node), "shape": {"capsule": {"offset": v.call(c.offset), "tail": v.call(c.tail), "radius": c.radius}} if c.offset != c.tail else {"sphere": {"offset": v.call(c.offset), "radius": c.radius}}})
	var groups := []
	var springs := []
	for chain: Dictionary in chains.get("springs", []):
		var joints := []
		for j: Dictionary in chain.joints:
			var g: Vector3 = j.gravity
			joints.append({"node": sk.get_bone_name(j.node), "stiffness": j.stiffness, "dragForce": j.drag, "hitRadius": j.radius, "gravityPower": g.length(), "gravityDir": v.call(g.normalized() if g.length() > 0.0 else Vector3.DOWN)})
		var spring := {"joints": joints}
		if not (chain.colliders as Array).is_empty():
			spring["colliderGroups"] = [groups.size()]
			groups.append({"colliders": chain.colliders})
		springs.append(spring)
	root.set_meta("springs", {} if springs.is_empty() else {"specVersion": "1.0", "springs": springs, "colliders": colliders, "colliderGroups": groups})


## A .unitypackage unpacked into a temporary folder removed at exit, or any other path as it is; "" if tar fails.
static func unpacked(path: String) -> String:
	if path.get_extension() != "unitypackage":
		return path
	var temp := DirAccess.create_temp("unity_avatar", false)
	_unpacked.append(temp)
	return temp.get_current_dir() if OS.execute("tar", ["-xzf", path, "-C", temp.get_current_dir()]) == 0 else ""


## Godot removes a temporary folder once nothing holds its DirAccess.
static var _unpacked: Array[DirAccess] = []


## The package's avatar as the scene and avatar data Avatar.model takes, its root also carrying "report" (what was kept
## and dropped, by kind). Null, with the reason printed, if the package holds no avatar to convert.
static func avatar_scene(dir: String, pick := "") -> Node3D:
	var prefabs := Prefabs.new(Assets.new(dir))
	var root := _convert(prefabs, pick)
	for m: Dictionary in prefabs.models.values():
		if m.has("scene"):
			(m.scene as Node).free()
	return root


static func _convert(prefabs: Prefabs, pick: String) -> Node3D:
	var assets := prefabs.assets
	var found := _avatar(assets, prefabs, pick)
	if found.is_empty():
		return null
	var objs: Dictionary = found.objects
	var report := {"avatar": found.name}
	var renderers := _renderers(objs, found.transform, report)
	var main := _main_model(assets, prefabs, objs, found.go, renderers)
	if main == "":
		printerr("unity_avatar: %s: no renderer's model is a humanoid with a Unity Avatar definition" % found.name)
		return null
	var model: Dictionary = prefabs.model(main)
	var skeletons: Array = (model.scene as Node).find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1:
		printerr("unity_avatar: %s has %d skeletons, not one" % [assets.by_guid[main].path, skeletons.size()])
		return null
	var definition := avatar_definition(FileAccess.get_file_as_string(assets.by_guid[main].meta))
	var source: Skeleton3D = skeletons[0]
	var scale := _world_scale(objs, _model_root(objs, main, renderers, found.transform))
	var from := Transform3D.IDENTITY.scaled(Vector3.ONE * scale) * _in_model(source)
	var k := from.basis.get_scale().y
	var root := Node3D.new()
	root.name = found.name
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	root.add_child(sk)
	var rests: Array[Transform3D] = []
	var taken := {}
	for b in source.get_bone_count():
		rests.append(from * source.get_bone_global_rest(b) * Transform3D.IDENTITY.scaled(Vector3.ONE / k))
		# Bones become glTF nodes, which Godot names as it would name nodes.
		var name := source.get_bone_name(b).validate_node_name()
		while taken.has(name):
			name += "_"
		taken[name] = true
		sk.add_bone(name)
	for b in source.get_bone_count():
		var p := source.get_bone_parent(b)
		sk.set_bone_parent(b, p)
		sk.set_bone_rest(b, rests[b] if p < 0 else rests[p].affine_inverse() * rests[b])
	sk.reset_bone_poses()
	var materials := Materials.new(assets)
	var merged := _merge(prefabs, materials, objs, renderers, sk, rests, scale, report)
	if merged.is_empty():
		printerr("unity_avatar: %s draws nothing" % found.name)
		root.free()
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	sk.add_child(mi)
	mi.mesh = merged.mesh
	mi.skin = merged.skin
	mi.skeleton = NodePath("..")
	for name: String in merged.weights:
		mi.set_blend_shape_value(mi.find_blend_shape_by_name(name), merged.weights[name])
	var named := _human_bones(sk, definition, assets.by_guid[main].path)
	if named.is_empty():
		root.free()
		return null
	var springs := _springs(objs, found.transform, sk, named, k, report)
	var human := {}
	var bone_path := func(b: int) -> NodePath: return NodePath("%s:%s" % [root.get_path_to(sk), sk.get_bone_name(b)])
	for i: int in named:
		human[named[i][0]] = bone_path.call(i)
	var nodes := []
	nodes.resize(sk.get_bone_count())
	nodes.fill({})
	var chains := SpringDefinition.read({"nodes": nodes, "extensions": {"VRMC_springBone": springs}}) if not springs.is_empty() else {"springs": [], "colliders": []}
	for chain: Dictionary in chains.springs:
		for j: Dictionary in chain.joints:
			human["spring_%d" % j.node] = bone_path.call(j.node)
		if chain.center >= 0:
			human["spring_%d" % chain.center] = bone_path.call(chain.center)
	for c: Dictionary in chains.colliders:
		if c.node >= 0:
			human["spring_%d" % c.node] = bone_path.call(c.node)
	root.set_meta("humanoid", human)
	root.set_meta("eyes", _eyes(sk, found.descriptor, human))
	root.set_meta("springs", chains)
	report["not translated"] = _untranslated(objs, found.transform, found.descriptor)
	if not prefabs.missing.is_empty():
		report["not in the package"] = prefabs.missing.keys()
	if not materials.undecoded.is_empty():
		report["textures not decoded"] = materials.undecoded.keys()
	root.set_meta("report", report)
	return root


## The avatar to convert: {"objects" of the document it is in, "go", "transform", "name", "descriptor" (its fields, or
## empty for a package's lone humanoid model)}; empty, with the reason printed, if there is none or several and `pick`
## names none of them.
static func _avatar(assets: Assets, prefabs: Prefabs, pick: String) -> Dictionary:
	var found := []
	for guid: String in assets.of(["unity", "prefab"]):
		if not assets.text(guid).contains("\n  ViewPosition:"):
			continue
		var objs := prefabs.flatten(guid)
		for id: int in objs:
			var o: Dictionary = objs[id]
			if o.type != "MonoBehaviour" or not o.data.has("ViewPosition"):
				continue
			var go := _ref(o.data.get("m_GameObject"))
			if not objs.has(go):
				continue
			var name := str(objs[go].data.get("m_Name", ""))
			if pick == "" or name == pick:
				found.append({"objects": objs, "go": go, "transform": _transform(objs, go), "name": name, "descriptor": o.data, "scene": assets.extension(guid) == "unity", "path": assets.by_guid[guid].path})
	if found.any(func(f: Dictionary) -> bool: return f.scene):
		found = found.filter(func(f: Dictionary) -> bool: return f.scene)
	var names := {}
	for f: Dictionary in found:
		names[f.name] = true
	if names.size() > 1:
		printerr("unity_avatar: several avatars, name one: %s" % ", ".join(found.map(func(f: Dictionary) -> String: return "%s (%s)" % [f.name, f.path])))
		return {}
	if not found.is_empty():
		return found[0]
	if pick != "":
		printerr("unity_avatar: no avatar named %s" % pick)
		return {}
	var models := assets.of(Prefabs.MODELS).filter(func(g: String) -> bool: return not avatar_definition(FileAccess.get_file_as_string(assets.by_guid[g].meta)).human.is_empty() and str((assets.meta(g).get("ModelImporter", {}) as Dictionary).get("animationType", "")) == "3")
	if models.size() != 1:
		printerr("unity_avatar: no avatar descriptor, and %d humanoid models, not one" % models.size())
		return {}
	var objs := prefabs.flatten(models[0])
	for id: int in objs:
		if objs[id].type == "GameObject" and not objs[id].has("node"):
			return {"objects": objs, "go": id, "transform": _transform(objs, id), "name": assets.name(models[0]), "descriptor": {}}
	return {}


static func _ref(v: Variant) -> int:
	return str((v as Dictionary).get("fileID", "0")).to_int() if v is Dictionary else 0


static func _transform(objs: Dictionary, go: int) -> int:
	for c: Variant in Prefabs._list(objs[go].data.get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if objs.has(id) and objs[id].type in ["Transform", "RectTransform"]:
			return id
	return 0


## Every transform under `top`, itself included, with its GameObject: [[transform, go], ...] parents first.
static func _under(objs: Dictionary, top: int) -> Array:
	var children := {}
	for id: int in objs:
		if objs[id].type in ["Transform", "RectTransform"]:
			children.get_or_add(_ref(objs[id].data.get("m_Father")), []).append(id)
	var out := []
	var pending := [top]
	var seen := {}
	while not pending.is_empty():
		var t: int = pending.pop_front()
		if seen.has(t):
			continue
		seen[t] = true
		out.append([t, _ref(objs[t].data.get("m_GameObject"))])
		pending.append_array(children.get(t, []))
	return out


static func _active(objs: Dictionary, go: int) -> bool:
	var d: Dictionary = objs.get(go, {}).get("data", {})
	return str(d.get("m_IsActive", "1")) == "1" and str(d.get("m_TagString", "")) != "EditorOnly"


## The renderers that draw when the avatar is worn: every enabled renderer whose GameObject and its parents up to the
## avatar are active and not editor-only. [[renderer id, go], ...]
static func _renderers(objs: Dictionary, top: int, report: Dictionary) -> Array:
	var on := {}
	var placed := {}
	var out := []
	var left := []
	var inside := {}
	for e: Array in _under(objs, top):
		inside[e[0]] = true
	for e: Array in _under(objs, top):
		var father := _ref(objs[e[0]].data.get("m_Father"))
		var live: bool = _active(objs, e[1]) and (e[0] == top or on.get(father, false))
		on[e[0]] = live
		placed[e[0]] = e[0] != top and (placed.get(father, false) or _constrained(objs, e[1], inside))
		if not live or not objs.has(e[1]):
			continue
		for c: Variant in Prefabs._list(objs[e[1]].data.get("m_Component")):
			var id := _ref((c as Dictionary).get("component"))
			if objs.has(id) and objs[id].type in RENDERERS and str(objs[id].data.get("m_Enabled", "1")) == "1":
				if placed[e[0]]:
					left.append(str(objs[e[1]].data.get("m_Name", "")))
				else:
					out.append([id, e[1]])
	if not left.is_empty():
		report["renderers a constraint places from outside the avatar, not drawn"] = left
	return out


## Whether a constraint places the GameObject from outside the avatar: a follower or world-fixed prop goes where a
## source the avatar's bones do not move puts it, so drawn at its authored offset it would stand glued to the body.
static func _constrained(objs: Dictionary, go: int, inside: Dictionary) -> bool:
	for c: Variant in Prefabs._list(objs.get(go, {}).get("data", {}).get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if not objs.has(id):
			continue
		var d: Dictionary = objs[id].data
		var sources := []
		if objs[id].type in ["ParentConstraint", "PositionConstraint"]:
			for e: Variant in Prefabs._list(d.get("m_Sources")):
				sources.append([(e as Dictionary).get("sourceTransform"), (e as Dictionary).get("weight", "1")])
		elif objs[id].type == "MonoBehaviour" and d.get("Sources") is Dictionary and (d.has("PositionAtRest") or d.has("PositionOffset")):
			for k: String in d.Sources:
				if k.begins_with("source") and d.Sources[k] is Dictionary:
					sources.append([d.Sources[k].get("SourceTransform"), d.Sources[k].get("Weight", "1")])
		for e: Array in sources:
			var ref: Dictionary = e[0] if e[0] is Dictionary else {}
			if str(e[1]).to_float() > 0.0 and (ref.has("guid") or not inside.has(_ref(ref))):
				return true
	return false


## The GUID of the humanoid model the avatar's Animator names, or failing that, of the humanoid model most of its
## renderers draw from.
static func _main_model(assets: Assets, prefabs: Prefabs, objs: Dictionary, go: int, renderers: Array) -> String:
	var humanoid := func(g: String) -> bool:
		return assets.by_guid.has(g) and assets.extension(g) in Prefabs.MODELS and not avatar_definition(FileAccess.get_file_as_string(assets.by_guid[g].meta)).human.is_empty()
	for c: Variant in Prefabs._list(objs[go].data.get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if objs.has(id) and objs[id].type == "Animator":
			var g := str((objs[id].data.get("m_Avatar", {}) as Dictionary).get("guid", ""))
			if humanoid.call(g) and not prefabs.model(g).is_empty():
				return g
	var counts := {}
	for r: Array in renderers:
		var g := _mesh_model(objs, r[0], objs[r[0]].type)
		if humanoid.call(g):
			counts[g] = counts.get(g, 0) + 1
	var best := ""
	for g: String in counts:
		if best == "" or counts[g] > counts[best]:
			best = g
	return best if best == "" or not prefabs.model(best).is_empty() else ""


static func _mesh_model(objs: Dictionary, renderer: int, type: String) -> String:
	if type == "SkinnedMeshRenderer":
		return str((objs[renderer].data.get("m_Mesh", {}) as Dictionary).get("guid", ""))
	var go := _ref(objs[renderer].data.get("m_GameObject"))
	for c: Variant in Prefabs._list(objs[go].data.get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if objs.has(id) and objs[id].type == "MeshFilter":
			return str((objs[id].data.get("m_Mesh", {}) as Dictionary).get("guid", ""))
	return ""


static func _mesh_ref(objs: Dictionary, renderer: int) -> Dictionary:
	if objs[renderer].type == "SkinnedMeshRenderer":
		return objs[renderer].data.get("m_Mesh", {})
	var go := _ref(objs[renderer].data.get("m_GameObject"))
	for c: Variant in Prefabs._list(objs[go].data.get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if objs.has(id) and objs[id].type == "MeshFilter":
			return objs[id].data.get("m_Mesh", {})
	return {}


## The transform of the main model's own GameObject in the avatar, or the avatar's where the model is not instanced
## whole (an unpacked scene).
static func _model_root(objs: Dictionary, model: String, renderers: Array, top: int) -> int:
	for e: Array in _under(objs, top):
		var o: Dictionary = objs.get(e[1], {})
		if o.get("guid", "") == model and not o.has("node"):
			return e[0]
	return top


## The scale a transform takes in its document, from its own and its parents' local scales.
static func _world_scale(objs: Dictionary, t: int) -> float:
	var s := 1.0
	var seen := {}
	while objs.has(t) and not seen.has(t):
		seen[t] = true
		var l: Variant = objs[t].data.get("m_LocalScale")
		if l is Dictionary:
			s *= absf(str(l.get("y", "1")).to_float())
		t = _ref(objs[t].data.get("m_Father"))
	return s


## A node's transform from its scene's root.
static func _in_model(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Every drawn renderer's surfaces as one mesh over `sk`, its skin binding each source bone to the output bone of its
## name (or its nearest ancestor that has one): blend shapes kept, those of one name in several renderers one shape,
## up to Avatar.MAX_BLEND_VERTICES (the rest baked at their saved weights),
## UVs moved into the material atlas. {"mesh", "skin", "weights": each
## blend shape's saved weight}, or empty if nothing draws.
static func _merge(prefabs: Prefabs, materials: Materials, objs: Dictionary, renderers: Array, sk: Skeleton3D, rests: Array[Transform3D], scale: float, report: Dictionary) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var skin := Skin.new()
	var corners := {}
	var shapes := {}
	var saved_weights := {}
	var drawn := []
	var skipped := []
	var tiled := {}
	var humanoid_bones := sk.get_bone_count()
	for r: Array in renderers:
		var o: Dictionary = objs[r[0]]
		var go_name := str(objs[r[1]].data.get("m_Name", ""))
		var ref := _mesh_ref(objs, r[0])
		var model: Dictionary = prefabs.model(str(ref.get("guid", ""))) if prefabs.assets.by_guid.has(str(ref.get("guid", ""))) else {}
		var mi := _mesh_node(model, str(ref.get("fileID", "0")).to_int())
		if mi == null or mi.mesh == null:
			skipped.append(go_name)
			continue
		var place := _binder(mi, sk, rests, scale, objs, r[0], model.objects.has(_ref(objs[r[0]].data.get("m_GameObject"))), humanoid_bones)
		if place.is_empty():
			skipped.append(go_name)
			continue
		drawn.append(go_name)
		var offset := skin.get_bind_count()
		for b: Array in place.binds:
			skin.add_bind(b[0], b[1])
		var mesh: ArrayMesh = mi.mesh
		var saved: Array = Prefabs._list(o.data.get("m_BlendShapeWeights"))
		var refs: Array = Prefabs._list(o.data.get("m_Materials"))
		var slots := _slot_of(mesh, refs, prefabs.assets, _slots(prefabs, str(ref.get("guid", ""))).get(_model_name(model, mi), []))
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			n.resize(v.size())
			var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
			var surface_shapes := mesh.surface_get_blend_shape_arrays(s)
			for k in surface_shapes.size():
				var name := mesh.get_blend_shape_name(k)
				var moved: Dictionary = shapes.get_or_add(name, {})
				var sv: PackedVector3Array = surface_shapes[k][Mesh.ARRAY_VERTEX]
				var sn: Variant = surface_shapes[k][Mesh.ARRAY_NORMAL]
				for i in v.size():
					var dv := sv[i] if relative else sv[i] - v[i]
					var dn := Vector3.ZERO if not sn is PackedVector3Array else (sn as PackedVector3Array)[i] if relative else (sn as PackedVector3Array)[i] - n[i]
					if not (dv.is_zero_approx() and dn.is_zero_approx()):
						moved[verts.size() + i] = [dv, dn]
				if k < saved.size():
					saved_weights[name] = maxf(saved_weights.get(name, 0.0), str(saved[k]).to_float() / 100.0)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			uv.resize(v.size())
			var fallback := Color.WHITE
			var sm := mesh.surface_get_material(s)
			if sm is BaseMaterial3D:
				fallback = (sm as BaseMaterial3D).albedo_color
			var slot: int = slots[s]
			var mref: Dictionary = refs[mini(slot, refs.size() - 1)] if not refs.is_empty() and refs[mini(slot, refs.size() - 1)] is Dictionary else {"name": String(sm.resource_name) if sm != null else ""}
			var key := materials.use(mref, fallback)
			var src_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var src_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var per := src_bones.size() / maxi(v.size(), 1)
			var base := verts.size()
			for i in v.size():
				verts.append(v[i])
				normals.append(n[i].normalized() if not n[i].is_zero_approx() else Vector3.UP)
				uvs.append(uv[i])
				corners[base + i] = key
				var top := _top4(src_bones, src_weights, i, per)
				for j in 4:
					bones.append(offset + place.remap.call(top[0][j]))
					weights.append(top[1][j])
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			for i in idx:
				indices.append(base + i)
	if indices.is_empty():
		return {}
	var used := {}
	for i: int in corners:
		used[corners[i]] = true
	materials.pack(used.keys())
	for i in uvs.size():
		var at: Array = materials.place(corners[i], uvs[i])
		uvs[i] = at[0]
		if at[1]:
			tiled[materials.materials[corners[i]].name] = true
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var names := shapes.keys().filter(func(name: String) -> bool: return not (shapes[name] as Dictionary).is_empty())
	var room := Avatar.MAX_BLEND_VERTICES / maxi(verts.size(), 1)
	var dropped := names.slice(room)
	names = names.slice(0, room)
	var baked := 0
	for name: String in dropped:
		var w: float = saved_weights.get(name, 0.0)
		if is_zero_approx(w):
			continue
		baked += 1
		for i: int in shapes[name]:
			verts[i] += w * (shapes[name][i][0] as Vector3)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var blends := []
	for name: String in names:
		var dv := PackedVector3Array()
		var dn := PackedVector3Array()
		dv.resize(verts.size())
		dn.resize(verts.size())
		for i: int in shapes[name]:
			dv[i] = shapes[name][i][0]
			dn[i] = shapes[name][i][1]
		var b := []
		b.resize(Mesh.ARRAY_MAX)
		b[Mesh.ARRAY_VERTEX] = dv
		b[Mesh.ARRAY_NORMAL] = dn
		blends.append(b)
	var out := ArrayMesh.new()
	out.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
	for name: String in names:
		out.add_blend_shape(name)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, blends)
	out.surface_set_material(0, materials.material())
	report["renderers drawn"] = drawn
	if not skipped.is_empty():
		report["renderers not found in their model"] = skipped
	report["triangles"] = indices.size() / 3
	report["materials"] = used.keys().map(func(k: String) -> String: return _describe(materials.materials[k]))
	report["blend shapes"] = "%d kept, %d moving nothing dropped, %d past Avatar.MAX_BLEND_VERTICES dropped (%d of them baked at their saved weights)" % [names.size(), shapes.size() - names.size() - dropped.size(), dropped.size(), baked]
	if not tiled.is_empty():
		report["tiled textures clamped to one tile"] = tiled.keys()
	return {"mesh": out, "skin": skin, "weights": names.reduce(func(kept_weights: Dictionary, name: String) -> Dictionary:
		kept_weights[name] = saved_weights.get(name, 0.0)
		return kept_weights, {})}


static func _describe(m: Dictionary) -> String:
	var texture := "no texture" if m.texture == "" else ("texture" if m.image != null else "texture not decoded")
	return "%s [%s, %s, %s%s]" % [m.name, m.shader if m.shader != "" else "not in package", texture, ["opaque", "cutout", "blended→cutout"][m.alpha], "" if m.cull else ", two-sided→one"]


## The four heaviest bone influences of vertex `i`, weights summing to one.
static func _top4(bones: PackedInt32Array, weights: PackedFloat32Array, i: int, per: int) -> Array:
	var pairs := []
	for j in per:
		pairs.append([bones[i * per + j], weights[i * per + j]])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var b := [0, 0, 0, 0]
	var w := [0.0, 0.0, 0.0, 0.0]
	var sum := 0.0
	for j in mini(4, pairs.size()):
		b[j] = pairs[j][0]
		w[j] = pairs[j][1]
		sum += w[j]
	if sum <= 0.0:
		w[0] = 1.0
		sum = 1.0
	return [b, w.map(func(x: float) -> float: return x / sum)]


## Each surface's slot in the renderer's materials. Where the renderer has a slot for each surface the FBX's polygons
## use, they pair in the FBX's connection order; otherwise a surface takes the slot whose material is named like its
## FBX material ("Head" for "Head.003", "Eye" for "Eye Left"), and the rest pair in order.
static func _slot_of(mesh: ArrayMesh, refs: Array, assets: Assets, order: Array) -> Array:
	var names := []
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		names.append(String(m.resource_name) if m != null else "")
	var out := []
	for s in names.size():
		var i := order.find(names[s])
		out.append(i if i >= 0 and refs.size() == order.size() else -1)
	if not out.has(-1):
		return out
	out.fill(-1)
	var plain := func(n: String) -> String:
		var b := n.to_lower()
		while b.length() > 4 and b[-4] == "." and b.right(3).is_valid_int():
			b = b.left(-4)
		return b.strip_edges()
	var taken := {}
	for loose in 2:
		for s in names.size():
			if out[s] >= 0:
				continue
			var n: String = plain.call(names[s])
			for i in refs.size():
				var r: String = plain.call(assets.name(str((refs[i] as Dictionary).get("guid", ""))) if refs[i] is Dictionary else "")
				if taken.has(i) or r == "" or n == "":
					continue
				if r == n or (loose == 1 and (n.contains(r) or r.contains(n))):
					out[s] = i
					taken[i] = true
					break
	for s in names.size():
		if out[s] < 0:
			var i := 0
			while taken.has(i) and i < refs.size():
				i += 1
			out[s] = mini(i, maxi(refs.size() - 1, 0))
			taken[i] = true
	return out


static var _slot_cache := {}


## The model's material slots by FBX model name (FbxSlots), read once.
static func _slots(prefabs: Prefabs, guid: String) -> Dictionary:
	if not _slot_cache.has(guid):
		_slot_cache[guid] = FbxSlots.slots(prefabs.assets.by_guid[guid].file) if prefabs.assets.by_guid.has(guid) else {}
	return _slot_cache[guid]


## The FBX name of the model node Godot made `mi` of.
static func _model_name(model: Dictionary, mi: MeshInstance3D) -> String:
	var state: GLTFState = model.state
	for i in state.get_nodes().size():
		if String(state.get_nodes()[i].resource_name).validate_node_name() == String(mi.name):
			return state.get_nodes()[i].original_name
	return String(mi.name)


## The MeshInstance3D Godot made of the model's node whose mesh has this file ID, or null.
static func _mesh_node(model: Dictionary, file_id: int) -> MeshInstance3D:
	if model.is_empty():
		return null
	for id: int in model.objects:
		var o: Dictionary = model.objects[id]
		if o.type in RENDERERS and _ref(o.data.get("m_Mesh")) == file_id:
			var name := String((model.state as GLTFState).get_nodes()[o.node].resource_name)
			var found := (model.scene as Node).find_children(name.validate_node_name(), "MeshInstance3D", true, false)
			return found[0] if found.size() == 1 else null
	return null


## How a source mesh binds to the output skeleton: {"binds": [[output bone, bind pose]...], "remap": source bind index
## to output bind index within the mesh}. A skinned mesh's bones bind by name; a bone the humanoid's model lacks is
## added to the output from the avatar's Unity transforms, past `humanoid_bones`, and binds as they place it, or failing
## that binds to its nearest named ancestor in its own skeleton. An
## unskinned mesh of the humanoid's model binds wholly to the bone it hangs from; one of another model is added as a
## bone from the avatar's Unity transforms. Each bind keeps the vertex where its source placed it at rest, in a model
## scaled by `scale`.
static func _binder(mi: MeshInstance3D, sk: Skeleton3D, rests: Array[Transform3D], scale: float, objs: Dictionary, renderer: int, own_model: bool, humanoid_bones: int) -> Dictionary:
	var scaled := Transform3D.IDENTITY.scaled(Vector3.ONE * scale)
	var target := func(src: Skeleton3D, b: int) -> int:
		while b >= 0:
			var t := _find_bone(sk, src.get_bone_name(b))
			if t >= 0:
				return t
			b = src.get_bone_parent(b)
		return 0
	if mi.skin != null and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
		var src: Skeleton3D = mi.get_node(mi.skeleton)
		var at := scaled * _in_model(src)
		var unity := {}
		for t: Variant in Prefabs._list(objs[renderer].data.get("m_Bones")):
			var go := _ref(objs.get(_ref(t), {}).get("data", {}).get("m_GameObject"))
			unity[str(objs.get(go, {}).get("data", {}).get("m_Name", "")).validate_node_name()] = _ref(t)
		var binds := []
		for i in mi.skin.get_bind_count():
			var b := mi.skin.get_bind_bone(i)
			if b < 0:
				b = src.find_bone(mi.skin.get_bind_name(i))
			var name := src.get_bone_name(maxi(b, 0))
			var t := _find_bone(sk, name)
			if unity.has(name) and (t < 0 or t >= humanoid_bones):
				t = t if t >= 0 else _as_bone(objs, unity[name], sk, rests)
				if t >= 0:
					binds.append([t, mi.skin.get_bind_pose(i)])
					continue
			t = target.call(src, b)
			binds.append([t, rests[t].affine_inverse() * at * src.get_bone_global_rest(maxi(b, 0)) * mi.skin.get_bind_pose(i)])
		return {"binds": binds, "remap": func(i: int) -> int: return i}
	if not own_model:
		var b := _as_bone(objs, _transform(objs, _ref(objs[renderer].data.get("m_GameObject"))), sk, rests)
		if b >= 0:
			return {"binds": [[b, Transform3D.IDENTITY]], "remap": func(_i: int) -> int: return 0}
	var n := mi.get_parent()
	var bone := -1
	while n != null and bone < 0:
		if n is BoneAttachment3D:
			bone = _find_bone(sk, (n as BoneAttachment3D).bone_name)
		n = n.get_parent()
	bone = maxi(bone, 0)
	return {"binds": [[bone, rests[bone].affine_inverse() * scaled * _in_model(mi)]], "remap": func(_i: int) -> int: return 0}


## A Unity transform added to the skeleton as a bone, with each ancestor up to its nearest one (itself excluded) that is
## a bone, placed by the transforms' local positions, rotations and scales in Godot's axes (X mirrored) and that bone's
## own scale in the avatar, so a PhysBone over them turns what they carry; -1, adding none, if no ancestor is a bone.
static func _as_bone(objs: Dictionary, t: int, sk: Skeleton3D, rests: Array[Transform3D]) -> int:
	var name_of := func(at: int) -> String:
		return str(objs.get(_ref(objs.get(at, {}).get("data", {}).get("m_GameObject")), {}).get("data", {}).get("m_Name", ""))
	var path := []
	var seen := {}
	var b := -1
	while objs.has(t) and not seen.has(t) and b < 0:
		seen[t] = true
		path.append(t)
		t = _ref(objs[t].data.get("m_Father"))
		b = _find_bone(sk, name_of.call(t))
	if b < 0:
		return -1
	var rest := Transform3D.IDENTITY.scaled(Vector3.ONE * _world_scale(objs, t))
	for i in range(path.size() - 1, -1, -1):
		rest = rest * _local(objs[path[i]].data)
		var name: String = name_of.call(path[i]).replace(":", "_").replace("/", "_").validate_node_name()
		while sk.find_bone(name) >= 0:
			name += "_"
		var added := sk.get_bone_count()
		sk.add_bone(name)
		sk.set_bone_parent(added, b)
		sk.set_bone_rest(added, rest)
		sk.reset_bone_pose(added)
		rests.append(rests[b] * rest)
		rest = Transform3D.IDENTITY
		b = added
	return b


static func _local(d: Dictionary) -> Transform3D:
	var f := func(v: Variant, k: String, otherwise: float) -> float:
		return str((v as Dictionary).get(k, otherwise)).to_float() if v is Dictionary else otherwise
	var p: Variant = d.get("m_LocalPosition")
	var q: Variant = d.get("m_LocalRotation")
	var sc: Variant = d.get("m_LocalScale")
	var rot := Quaternion(f.call(q, "x", 0.0), -f.call(q, "y", 0.0), -f.call(q, "z", 0.0), f.call(q, "w", 1.0))
	rot = rot.normalized() if rot.length() > 0.0 else Quaternion.IDENTITY
	return Transform3D(Basis(rot).scaled_local(Vector3(f.call(sc, "x", 1.0), f.call(sc, "y", 1.0), f.call(sc, "z", 1.0))), Vector3(-f.call(p, "x", 0.0), f.call(p, "y", 0.0), f.call(p, "z", 0.0)))


## The bones the Avatar definition maps, by index: [humanoid (VRM 1.0) name, the Unity bone it is]; empty, with the
## reason printed, if the definition names a bone the skeleton lacks, two humanoid bones for one, or a bone the humanoid
## has not.
static func _human_bones(sk: Skeleton3D, avatar: Dictionary, model: String) -> Dictionary:
	var named := {}
	var refuse := func(why: String) -> Dictionary:
		printerr("unity_avatar: %s: %s" % [model, why])
		return {}
	for unity_bone: String in avatar.human:
		var vrm := vrm_bone(avatar.human[unity_bone])
		var b := _bone_of(sk, unity_bone, avatar.parents)
		if b < 0:
			return refuse.call("the Avatar definition's %s (%s) is no bone of it" % [unity_bone, avatar.human[unity_bone]])
		if not vrm in Vrm.BONES:
			return refuse.call("the Avatar definition's %s is no VRM bone" % avatar.human[unity_bone])
		if named.has(b):
			return refuse.call("the Avatar definition maps %s twice" % unity_bone)
		named[b] = [vrm, unity_bone]
	return named


## Where the eyes are from the head bone: the descriptor's view position (Unity's axes, X mirrored), or between the eye
## bones, or a little above the head bone.
static func _eyes(sk: Skeleton3D, descriptor: Dictionary, human: Dictionary) -> Vector3:
	var rest := func(b: String) -> Transform3D: return sk.get_bone_global_rest(sk.find_bone((human[b] as NodePath).get_concatenated_subnames()))
	var head: Transform3D = rest.call("head")
	var view: Variant = descriptor.get("ViewPosition")
	if view is Dictionary:
		return head.affine_inverse() * Vector3(-str(view.get("x", "0")).to_float(), str(view.get("y", "0")).to_float(), str(view.get("z", "0")).to_float())
	if human.has("leftEye") and human.has("rightEye"):
		return head.affine_inverse() * (((rest.call("leftEye") as Transform3D).origin + (rest.call("rightEye") as Transform3D).origin) / 2.0)
	return Vector3(0, 0.06, 0)


## The avatar's PhysBones as VRM spring chains, one per path from a PhysBone's root to each leaf of its bones and on to
## the endpoint past that leaf where the PhysBone sets one, a bone added to the skeleton there: a VRM spring ends at a
## node, and a PhysBone of one bone swings about its endpoint alone. Its PhysBone colliders become VRM colliders. A bone
## the output skeleton lacks ends its chain. A root with several children stays still, as PhysBones leave it unless its
## multiChildType is First, so its chains start at its children: a VRM spring turns its first joint, which would swing
## every branch under that root.
static func _springs(objs: Dictionary, top: int, sk: Skeleton3D, human: Dictionary, k: float, report: Dictionary) -> Dictionary:
	var bone_of := func(t: int) -> int:
		return _find_bone(sk, str(objs.get(_ref(objs.get(t, {}).get("data", {}).get("m_GameObject")), {}).get("data", {}).get("m_Name", "")))
	var children := {}
	for id: int in objs:
		if objs[id].type == "Transform":
			children.get_or_add(_ref(objs[id].data.get("m_Father")), []).append(id)
	var colliders := []
	var collider_index := {}
	var springs := []
	var physbones := 0
	var live := {}
	for e: Array in _under(objs, top):
		live[e[0]] = true
	# A component may sit outside the avatar (a tool merges it in at upload) while its root is a bone of it.
	var ours := func(d: Dictionary) -> bool:
		var t := _ref(d.get("rootTransform"))
		return live.has(t if t != 0 else _transform(objs, _ref(d.get("m_GameObject"))))
	for id: int in objs:
		var d: Dictionary = objs[id].data
		if objs[id].type != "MonoBehaviour" or not ours.call(d):
			continue
		if d.has("shapeType") and d.has("insideBounds"):
			var t := _ref(d.get("rootTransform"))
			if t == 0:
				t = _transform(objs, _ref(d.get("m_GameObject")))
			var bone: int = bone_of.call(t)
			if bone < 0:
				continue
			var p: Variant = d.get("position", {})
			var offset := [-str(p.get("x", "0")).to_float(), str(p.get("y", "0")).to_float(), str(p.get("z", "0")).to_float()] if p is Dictionary else [0, 0, 0]
			var radius := str(d.get("radius", "0")).to_float()
			var height := str(d.get("height", "0")).to_float()
			var shape := {"sphere": {"offset": offset, "radius": radius}}
			if str(d.shapeType) == "1" and height > 2.0 * radius:
				shape = {"capsule": {"offset": [offset[0], offset[1] - (height / 2.0 - radius), offset[2]], "tail": [offset[0], offset[1] + (height / 2.0 - radius), offset[2]], "radius": radius}}
			collider_index[id] = colliders.size()
			colliders.append({"node": bone, "shape": shape})
	for id: int in objs:
		var d: Dictionary = objs[id].data
		if objs[id].type != "MonoBehaviour" or not d.has("pull") or not d.has("rootTransform") or not ours.call(d):
			continue
		physbones += 1
		var root_t := _ref(d.get("rootTransform"))
		if root_t == 0:
			root_t = _transform(objs, _ref(d.get("m_GameObject")))
		var ignored := {}
		for t: Variant in Prefabs._list(d.get("ignoreTransforms")):
			ignored[_ref(t)] = true
		var joint := {"stiffness": 4.0 * str(d.get("pull", "0.2")).to_float() * (1.0 + str(d.get("stiffness", "0")).to_float()), "dragForce": clampf(1.0 - str(d.get("spring", "0.2")).to_float(), 0.0, 1.0), "gravityPower": str(d.get("gravity", "0")).to_float(), "gravityDir": [0, -1, 0], "hitRadius": str(d.get("radius", "0")).to_float() * k}
		var e: Variant = d.get("endpointPosition")
		var endpoint := Vector3(-str(e.get("x", "0")).to_float(), str(e.get("y", "0")).to_float(), str(e.get("z", "0")).to_float()) if e is Dictionary else Vector3.ZERO
		var groups := []
		for c: Variant in Prefabs._list(d.get("colliders")):
			if collider_index.has(_ref(c)):
				groups.append(collider_index[_ref(c)])
		var kids_of := func(t: int) -> Array:
			return children.get(t, []).filter(func(c: int) -> bool: return not ignored.has(c) and bone_of.call(c) >= 0)
		var starts: Array = kids_of.call(root_t)
		if starts.size() < 2 or str(d.get("multiChildType", "0")) == "1":
			starts = [root_t]
		var pending := starts.map(func(t: int) -> Array: return [t, []])
		while not pending.is_empty():
			var item: Array = pending.pop_back()
			var bone: int = bone_of.call(item[0])
			var joints: Array = (item[1] as Array).duplicate()
			if bone >= 0 and not human.has(bone) and not ignored.has(item[0]):
				var j := joint.duplicate()
				j["node"] = bone
				joints.append(j)
			elif not joints.is_empty():
				if joints.size() >= 2:
					springs.append({"joints": joints, "colliders": groups})
				continue
			var kids: Array = kids_of.call(item[0])
			if kids.is_empty():
				if not joints.is_empty() and endpoint != Vector3.ZERO:
					var j := joint.duplicate()
					j["node"] = _endpoint(sk, bone, endpoint * _world_scale(objs, item[0]))
					joints.append(j)
				if joints.size() >= 2:
					springs.append({"joints": joints, "colliders": groups})
				continue
			for i in kids.size():
				pending.append([kids[i], joints if i == 0 else []])
	report["PhysBones"] = "%d components as %d spring chains, %d colliders; parameters mapped approximately (pull, spring, stiffness, gravity, radius); limits, grabbing and posing dropped" % [physbones, springs.size(), colliders.size()]
	if springs.is_empty():
		return {}
	var groups := []
	var out_springs := []
	for s: Dictionary in springs:
		var g := -1
		if not (s.colliders as Array).is_empty():
			g = groups.size()
			groups.append({"colliders": s.colliders})
		var spring := {"joints": s.joints}
		if g >= 0:
			spring["colliderGroups"] = [g]
		out_springs.append(spring)
	return {"specVersion": "1.0", "springs": out_springs, "colliders": colliders, "colliderGroups": groups}


## A bone added under `leaf` at `offset` in its axes.
static func _endpoint(sk: Skeleton3D, leaf: int, offset: Vector3) -> int:
	var name := "%s endpoint" % sk.get_bone_name(leaf)
	while sk.find_bone(name) >= 0:
		name += "_"
	var b := sk.get_bone_count()
	sk.add_bone(name)
	sk.set_bone_parent(b, leaf)
	sk.set_bone_rest(b, Transform3D(Basis.IDENTITY, offset))
	sk.reset_bone_pose(b)
	return b


## The kinds of component under the avatar this converter does not translate, with how many of each.
static func _untranslated(objs: Dictionary, top: int, descriptor: Dictionary) -> Dictionary:
	var kinds := {}
	var known := {"Transform": true, "SkinnedMeshRenderer": true, "MeshFilter": true, "MeshRenderer": true}
	for e: Array in _under(objs, top):
		for c: Variant in Prefabs._list(objs.get(e[1], {}).get("data", {}).get("m_Component")):
			var id := _ref((c as Dictionary).get("component"))
			if not objs.has(id) or known.has(objs[id].type):
				continue
			var d: Dictionary = objs[id].data
			var kind: String = objs[id].type
			if kind == "MonoBehaviour":
				if d.has("ViewPosition"):
					continue
				if d.has("pull") or d.has("insideBounds"):
					continue
				kind = "Contact" if d.has("collisionTags") else "Constraint" if d.has("Sources") or d.has("sources") else "script"
			kinds[kind] = kinds.get(kind, 0) + 1
	if Prefabs._list(descriptor.get("VisemeBlendShapes")).size() > 0:
		kinds["visemes"] = Prefabs._list(descriptor.get("VisemeBlendShapes")).size()
	if descriptor.has("customExpressions") and str(descriptor.customExpressions) == "1":
		kinds["expression menu and parameters"] = 1
	return kinds


## The Unity Avatar definition in a model's .meta text: "human", each mapped bone's name to its HumanBodyBones name, and
## "parents", each of the model's transforms by name to its parent's.
static func avatar_definition(meta: String) -> Dictionary:
	var human := {}
	var parents := {}
	var section := ""
	var name := ""
	for line in meta.split("\n"):
		var s := line.strip_edges()
		if line.begins_with("    human:"):
			section = "human"
		elif line.begins_with("    skeleton:"):
			section = "skeleton"
		elif not line.begins_with("    "):
			section = ""
		elif section == "human" and s.begins_with("- boneName: "):
			name = _scalar(s.trim_prefix("- boneName: "))
		elif section == "human" and s.begins_with("humanName: "):
			human[name] = _scalar(s.trim_prefix("humanName: "))
		elif section == "skeleton" and s.begins_with("- name: "):
			name = _scalar(s.trim_prefix("- name: "))
		elif section == "skeleton" and s.begins_with("parentName:"):
			parents[name] = _scalar(s.trim_prefix("parentName:").strip_edges())
	return {"human": human, "parents": parents}


## A Unity HumanBodyBones name ("Left Thumb Proximal") as the VRM 1.0 humanoid bone it is ("leftThumbMetacarpal").
static func vrm_bone(unity: String) -> String:
	var s := unity.replace(" ", "")
	for k: String in THUMB:
		if s.ends_with(k):
			s = s.trim_suffix(k) + THUMB[k]
			break
	return s.left(1).to_lower() + s.substr(1)


static func _scalar(s: String) -> String:
	if s.length() >= 2 and s[0] in ["'", "\""] and s[-1] == s[0]:
		return s.substr(1, s.length() - 2).replace("''", "'")
	return s


## The skeleton bone of a Unity transform's name, as Godot's importer and then this converter name bones; -1 if none.
static func _find_bone(sk: Skeleton3D, unity: String) -> int:
	return sk.find_bone(unity.replace(":", "_").replace("/", "_").validate_node_name())


## The skeleton bone a Unity transform name is. Unity gives a transform named like another in the model a " 1", " 2"...
## suffix (Seed-san's head bone is "head 1" beside its "head" mesh), which Godot's importer does not, so a name the
## skeleton lacks is matched without its suffix, under the bone its Unity parent is.
static func _bone_of(sk: Skeleton3D, unity: String, parents: Dictionary) -> int:
	var b := _find_bone(sk, unity)
	if b >= 0:
		return b
	var plain := unity
	while plain.length() > 0 and plain[-1] >= "0" and plain[-1] <= "9":
		plain = plain.left(-1)
	if not plain.ends_with(" ") or not parents.has(unity):
		return -1
	b = sk.find_bone(plain.strip_edges())
	if b < 0 or sk.get_bone_parent(b) < 0:
		return b
	return b if sk.get_bone_parent(b) == _bone_of(sk, parents[unity], parents) else -1
