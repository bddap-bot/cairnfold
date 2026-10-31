extends SceneTree

## Imports the avatar in a Unity source package as the avatar model (Avatar.model) and writes it as a Godot scene: run
## from game/ as
## godot4 --headless --path . --script ../scripts/unity_avatar.gd -- PACKAGE OUT.scn [AVATAR]
## OUT.vrm writes it instead as the VRM a player wears: the avatars folder reads only VRM, since a worn file travels to
## every player met and a Godot scene can run code; Avatar.read reads it back into the same model.
## PACKAGE is a .unitypackage or an Assets folder with each asset's .meta beside it. The avatar is the GameObject
## bearing a VRChat avatar descriptor (AVATAR names it where there are several), as its scene or prefab instantiates
## it: the renderers active there, and those its Expressions Menu can turn on, with their materials and blend shape
## weights, over the skeleton of its humanoid model, whose Unity Avatar definition is the bone map. A package without a
## descriptor converts its one humanoid model. The avatar becomes a mesh for each set of menu switches its renderers
## draw under, every triangle kept and drawn on the sides its material's shader culls to, and one atlas of the
## materials' colour textures; its blend shapes stay, set to their saved weights, its PhysBones and DynamicBones become
## spring chains, and its menu, parameters and FX controller become the model's "expressions" (VRCHAT_expressions in a
## VRM); its visemes, eyelid blink and the faces its FX layer makes for hand gestures become VRM expressions, "faces" on
## the root as Vrm.write takes them. No VRM lies between: VRM cannot carry what later importer work adds to the model.
## The importer prints what it kept and dropped.

const Assets = preload("res://../scripts/unity/assets.gd")
const Prefabs = preload("res://../scripts/unity/prefabs.gd")
const Materials = preload("res://../scripts/unity/materials.gd")
const FbxSlots = preload("res://../scripts/unity/fbx_slots.gd")
const SpringDefinition = preload("res://addons/avatar_workshop/spring_definition.gd")
const Expressions = preload("res://../scripts/unity/expressions.gd")
const ExpressionCurves = preload("res://src/expression_state.gd")
const Yaml = preload("res://../scripts/unity/yaml.gd")

## Unity's HumanBodyBones names for the thumb, by the VRM 1.0 bone each one is.
const THUMB := {"ThumbProximal": "ThumbMetacarpal", "ThumbIntermediate": "ThumbProximal"}
const RENDERERS := ["SkinnedMeshRenderer", "MeshRenderer"]
## The side, in pixels, of a menu icon as the model carries it: a board row's height.
const ICON := 44.0
## VRM's mood presets by the words a gesture face's clip name says them with; the first the name says is its preset.
const MOODS := {"happy": ["happy", "smile"], "angry": ["angry", "mad"], "sad": ["sad", "cry"], "relaxed": ["sleep", "relax"], "surprised": ["shock", "surprise"]}
## VRM's viseme presets by their slot in a VRChat descriptor's VisemeBlendShapes.
const VISEMES := {"aa": 10, "ee": 11, "ih": 12, "oh": 13, "ou": 14}
## A Transform's Euler angle curves, by the names Unity's clips give them.
const EULERS := ["localEulerAnglesRaw", "localEulerAngles", "localEulerAnglesBaked"]


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
	for c: Dictionary in root.get_meta("constraints", []):
		c.node = sk.get_bone_name(c.node)
		for source: Dictionary in c.sources:
			if source.has("node"):
				source.node = sk.get_bone_name(source.node)
	var chains: Dictionary = root.get_meta("springs")
	var v := func(x: Vector3) -> Array: return [x.x, x.y, x.z]
	var colliders := []
	for c: Dictionary in chains.get("colliders", []):
		var collider := {"node": sk.get_bone_name(c.node), "shape": {"capsule": {"offset": v.call(c.offset), "tail": v.call(c.tail), "radius": c.radius}} if c.offset != c.tail else {"sphere": {"offset": v.call(c.offset), "radius": c.radius}}}
		if c.has("extensions"):
			collider["extensions"] = c.extensions
		colliders.append(collider)
	var groups := []
	var springs := []
	for chain: Dictionary in chains.get("springs", []):
		var joints := []
		for j: Dictionary in chain.joints:
			var g: Vector3 = j.gravity
			var joint := {"node": sk.get_bone_name(j.node), "stiffness": j.stiffness, "dragForce": j.drag, "hitRadius": j.radius, "gravityPower": g.length(), "gravityDir": v.call(g.normalized() if g.length() > 0.0 else Vector3.DOWN)}
			if j.has("extras"):
				joint["extras"] = j.extras
			joints.append(joint)
		var spring := {"joints": joints, "extras": {"collide": _hands(chain.collide), "grab": _hands(chain.grab)}}
		if not (chain.colliders as Array).is_empty():
			spring["colliderGroups"] = [groups.size()]
			groups.append({"colliders": chain.colliders})
		springs.append(spring)
	root.set_meta("springs", {} if springs.is_empty() else {"specVersion": "1.0", "springs": springs, "colliders": colliders, "colliderGroups": groups})


## A .unitypackage unpacked into a folder under TMPDIR removed at exit, or any other path as it is; "" if tar fails.
## Godot's own temporary folders go to /tmp whatever TMPDIR says, where a run killed before exit left gigabytes no caller
## cleans up; under TMPDIR the folder goes with the caller's.
static func unpacked(path: String) -> String:
	if path.get_extension() != "unitypackage":
		return path
	var temp := OS.get_environment("TMPDIR")
	var dir := (temp if temp != "" else "/tmp").path_join("unity_avatar-%d-%d" % [OS.get_process_id(), _unpacked.size()])
	_unpacked.append(Unpacked.new(dir))
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	return dir if OS.execute("tar", ["-xzf", path, "-C", dir]) == 0 else ""


static var _unpacked: Array[Unpacked] = []


class Unpacked:
	var path: String

	func _init(dir: String) -> void:
		path = dir

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE:
			OS.execute("rm", ["-rf", path])


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
	var expressions := Expressions.new(assets, found.descriptor)
	var paths := _paths(objs, found.transform)
	var switches := _switches(expressions, objs, paths)
	var renderers := _renderers(objs, found.transform, switches.by_object, report)
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
	var model_bones := _model_bones(objs, found.transform, main, renderers)
	_attach_armatures(objs, found.transform, model_bones, definition, report)
	var source: Skeleton3D = skeletons[0]
	# The model file's bind pose need not be a T-pose; the humanoid rests in the pose its Unity Avatar was configured in,
	# mirrored across X as Godot's FBX importer mirrors Unity's.
	var description: Dictionary = (assets.meta(main).get("ModelImporter", {}) as Dictionary).get("humanDescription", {})
	for bone: Dictionary in Prefabs._list(description.get("skeleton")):
		var b := source.find_bone(str(bone.get("name", "")))
		var q: Variant = bone.get("rotation")
		if b >= 0 and q is Dictionary:
			var rest := source.get_bone_rest(b)
			var turn := Quaternion(str(q.x).to_float(), -str(q.y).to_float(), -str(q.z).to_float(), str(q.w).to_float()).normalized()
			source.set_bone_rest(b, Transform3D(Basis(turn).scaled(rest.basis.get_scale()), rest.origin))
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
	var source_bones := {}
	for name: String in model_bones:
		var bone := _find_bone(sk, name)
		if bone >= 0:
			source_bones[_ref(objs[model_bones[name]].data.get("m_GameObject"))] = bone
	sk.set_meta("unity_bones", source_bones)
	sk.set_meta("unity_top", found.transform)
	sk.set_meta("unity_model", main)
	var avatar_frame := _world_transform(objs, found.transform)
	sk.set_meta("unity_frame", Transform3D(avatar_frame.basis.orthonormalized(), avatar_frame.origin).affine_inverse())
	var materials := Materials.new(assets)
	var face := _face(prefabs, objs, found.descriptor)
	var animated := {}
	var clips: Array = expressions.data.get("clips", [])
	for i in clips.size():
		for c: Dictionary in clips[i].curves:
			if c.attribute.begins_with("blendShape.") and c["class"] == "137" and paths.has(c.path) and not c.has("refs"):
				var renderer := _renderer_of(objs, _ref(objs[paths[c.path]].data.get("m_GameObject")))
				var shapes: Dictionary = animated.get_or_add(renderer, {})
				(shapes.get_or_add(c.attribute.trim_prefix("blendShape."), []) as Array).append([i, c["keys"]])
	var faced := {}
	for shape: String in face.shapes:
		faced[shape] = true
	var merged := _merge(prefabs, materials, objs, renderers, switches.slots, animated, faced, sk, rests, scale, report)
	if merged.is_empty():
		printerr("unity_avatar: %s draws nothing" % found.name)
		root.free()
		return null
	for part: Dictionary in merged.meshes:
		var mi := MeshInstance3D.new()
		mi.name = "Body" if (part.when as Array).is_empty() and not part.has("swap") else "Body %d" % sk.get_child_count()
		sk.add_child(mi)
		mi.mesh = part.mesh
		mi.skin = merged.skin
		mi.skeleton = NodePath("..")
		part.node = mi.name
		for name: String in part.weights:
			mi.set_blend_shape_value(mi.find_blend_shape_by_name(name), part.weights[name])
		mi.visible = (part.when as Array).all(func(w: Array) -> bool: return is_equal_approx(switches.targets[w[0]].default, w[1]))
	var named := _human_bones(sk, definition, assets.by_guid[main].path)
	if named.is_empty():
		root.free()
		return null
	sk.set_meta("humanoid_bones", named)
	var constraints := _constraints(prefabs, objs, found.transform, sk, rests)
	if constraints.has("error"):
		printerr("unity_avatar: " + str(constraints.error))
		root.free()
		return null
	root.set_meta("constraints", constraints.get("constraints", []))
	report["active transform constraints"] = constraints.get("constraints", []).size()
	var moved := {}
	for clip: Dictionary in clips:
		for c: Dictionary in clip.curves:
			if c["class"] == "4" and paths.has(c.path):
				moved[paths[c.path]] = true
	var springs := _springs(objs, found.transform, sk, named, k, report, switches, moved)
	var switched: Dictionary = springs.get("switched", {})
	springs.erase("switched")
	var human := {}
	var bone_path := func(b: int) -> NodePath: return NodePath("%s:%s" % [root.get_path_to(sk), sk.get_bone_name(b)])
	for i: int in named:
		human[named[i][0]] = bone_path.call(i)
	var nodes := []
	nodes.resize(sk.get_bone_count())
	nodes.fill({})
	var chains := _read_springs(springs, nodes) if not springs.is_empty() else {"springs": [], "colliders": []}
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
	if not expressions.data.is_empty():
		var bound := _bound(expressions, switches, merged.meshes, merged.shapes, objs, paths, sk, materials, report)
		for key: String in switched:
			if not (switched[key] as Array).is_empty():
				bound[key] = switched[key]
		root.set_meta("expressions", bound)
	for name: String in face.expressions:
		var binds := []
		for b: Dictionary in face.expressions[name]:
			var shapes := {}
			for r: int in merged.shapes:
				if merged.shapes[r].has(b.shape):
					shapes[merged.shapes[r][b.shape]] = true
			for m: Dictionary in merged.meshes:
				for s: String in shapes:
					if m.names.has(s):
						binds.append({"node": m.node, "shape": m.names[s], "weight": b.weight})
		face.expressions[name] = binds
	root.set_meta("faces", face.expressions)
	report["faces"] = (face.expressions as Dictionary).keys()
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


## The switches that must all be on for Unity to run a component (`id`, its fields `d`): its own enabled flag and the
## active flag of its GameObject and every parent, each either switched by `switches` or fixed; null if one fixed off
## means it never runs.
static func _when(objs: Dictionary, id: int, d: Dictionary, switches: Dictionary) -> Variant:
	var by: Dictionary = switches.get("by_object", {})
	var when := []
	if by.has(id):
		when.append([by[id], 1])
	elif str(d.get("m_Enabled", "1")) != "1":
		return null
	var go := _ref(d.get("m_GameObject"))
	var t := _transform(objs, go) if objs.has(go) else 0
	var seen := {}
	while objs.has(t) and not seen.has(t):
		seen[t] = true
		go = _ref(objs[t].data.get("m_GameObject"))
		if str(objs.get(go, {}).get("data", {}).get("m_TagString", "")) == "EditorOnly":
			return null
		if by.has(go):
			when.append([by[go], 1])
		elif not _active(objs, go):
			return null
		t = _ref(objs[t].data.get("m_Father"))
	return when


## The renderers that draw when the avatar is worn or its menu can show: every renderer, enabled or switched by
## `switches`, whose GameObject and its parents up to the avatar are active or switched, and not editor-only.
## [[renderer id, go, [[switch target, 1]...] each switch that must be on for it to draw], ...]
static func _renderers(objs: Dictionary, top: int, switches: Dictionary, report: Dictionary) -> Array:
	var on := {}
	var when := {}
	var placed := {}
	var out := []
	var left := []
	var inside := {}
	for e: Array in _under(objs, top):
		inside[e[0]] = true
	for e: Array in _under(objs, top):
		var father := _ref(objs[e[0]].data.get("m_Father"))
		var switched: bool = switches.has(e[1]) and str(objs.get(e[1], {}).get("data", {}).get("m_TagString", "")) != "EditorOnly"
		var live: bool = (_active(objs, e[1]) or switched) and (e[0] == top or on.get(father, false))
		on[e[0]] = live
		when[e[0]] = (when.get(father, []) as Array) + ([[switches[e[1]], 1]] if switched else [])
		placed[e[0]] = e[0] != top and (placed.get(father, false) or _constrained(objs, e[1], inside))
		if not live or not objs.has(e[1]):
			continue
		for c: Variant in Prefabs._list(objs[e[1]].data.get("m_Component")):
			var id := _ref((c as Dictionary).get("component"))
			if not objs.has(id) or not objs[id].type in RENDERERS or not (str(objs[id].data.get("m_Enabled", "1")) == "1" or switches.has(id)):
				continue
			if placed[e[0]]:
				left.append(str(objs[e[1]].data.get("m_Name", "")))
			else:
				out.append([id, e[1], (when[e[0]] as Array) + ([[switches[id], 1]] if switches.has(id) else [])])
	if not left.is_empty():
		report["renderers a constraint places from outside the avatar, not drawn"] = left
	return out


## Each transform under `top` by its path from it, as an animation clip names it: "" for `top`, then GameObject
## names joined by "/".
static func _paths(objs: Dictionary, top: int) -> Dictionary:
	var by_transform := {top: ""}
	var out := {"": top}
	for e: Array in _under(objs, top):
		if e[0] == top:
			continue
		var parent: String = by_transform.get(_ref(objs[e[0]].data.get("m_Father")), "")
		var path := ("%s/%s" % [parent, objs.get(e[1], {}).get("data", {}).get("m_Name", "")]).trim_prefix("/")
		by_transform[e[0]] = path
		out.get_or_add(path, e[0])
	return out


## The menu's switches: each GameObject whose active flag, renderer whose enabled flag, and renderer material slot
## whose material the controller's clips animate. {"targets": [{"effect": "switch", "default"}], "by_object": its
## target by GameObject or renderer ID, "slots": "renderer:slot" to [target, [each material reference it takes, the
## renderer's own first]], "by_curve": "path|attribute|class" to its target}.
static func _switches(expressions: Expressions, objs: Dictionary, paths: Dictionary) -> Dictionary:
	var out := {"targets": [], "by_object": {}, "slots": {}, "by_curve": {}}
	if expressions.data.is_empty():
		return out
	for clip: Dictionary in expressions.data.clips:
		for c: Dictionary in clip.curves:
			var key := "%s|%s|%s" % [c.path, c.attribute, c["class"]]
			if out.by_curve.has(key) or not paths.has(c.path):
				continue
			var go := _ref(objs[paths[c.path]].data.get("m_GameObject"))
			if c.attribute == "m_IsActive" and c["class"] == "1":
				out.by_curve[key] = _switch(out, go, 1.0 if str(objs.get(go, {}).get("data", {}).get("m_IsActive", "1")) == "1" else 0.0)
				continue
			if c.attribute == "m_Enabled" and c["class"] == "114":
				var physics := _physics_of(objs, go, str(c.get("script", "")))
				if physics != 0:
					out.by_curve[key] = _switch(out, physics, 1.0 if str(objs[physics].data.get("m_Enabled", "1")) == "1" else 0.0)
				continue
			var renderer := _renderer_of(objs, go)
			if renderer == 0 or not c["class"] in ["23", "137"]:
				continue
			if c.attribute == "m_Enabled":
				out.by_curve[key] = _switch(out, renderer, 1.0 if str(objs[renderer].data.get("m_Enabled", "1")) == "1" else 0.0)
			elif c.attribute.begins_with("m_Materials.Array.data[") and c.has("refs"):
				var slot: int = str(c.attribute).trim_prefix("m_Materials.Array.data[").trim_suffix("]").to_int()
				var refs: Array = Prefabs._list(objs[renderer].data.get("m_Materials"))
				var at := "%d:%d" % [renderer, slot]
				if not out.slots.has(at):
					out.slots[at] = [_switch(out, at, 0.0), [refs[slot] if slot < refs.size() else {}]]
				out.by_curve[key] = out.slots[at][0]
	for clip: Dictionary in expressions.data.clips:
		for c: Dictionary in clip.curves:
			var key := "%s|%s|%s" % [c.path, c.attribute, c["class"]]
			if not c.has("refs") or not out.by_curve.has(key):
				continue
			for slot: String in out.slots:
				if out.slots[slot][0] != out.by_curve[key]:
					continue
				var choices: Array = out.slots[slot][1]
				for k: Array in c.refs:
					if k[1] != "" and not choices.any(func(m: Variant) -> bool: return m is Dictionary and m.get("guid", "") == k[1]):
						choices.append({"guid": k[1], "fileID": "2100000"})
	return out


static func _switch(out: Dictionary, object: Variant, default: float) -> int:
	if not out.by_object.has(object):
		out.by_object[object] = out.targets.size()
		out.targets.append({"effect": "switch", "default": default})
	return out.by_object[object]


## The PhysBone, DynamicBone or collider on `go` that an m_Enabled curve naming `script` animates: Unity binds the first.
static func _physics_of(objs: Dictionary, go: int, script: String) -> int:
	for c: Variant in Prefabs._list(objs.get(go, {}).get("data", {}).get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		var d: Dictionary = objs.get(id, {}).get("data", {})
		if str((d.get("m_Script", {}) as Dictionary).get("guid", "")) == script and (_spring_component(d) or not _collider(d).is_empty()):
			return id
	return 0


static func _spring_component(d: Dictionary) -> bool:
	return (d.has("pull") and d.has("rootTransform")) or (d.has("m_Damping") and d.has("m_Root"))


static func _renderer_of(objs: Dictionary, go: int) -> int:
	for c: Variant in Prefabs._list(objs.get(go, {}).get("data", {}).get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if objs.has(id) and objs[id].type in RENDERERS:
			return id
	return 0


static func _scaled(keys: Array, by: float) -> Array:
	return keys.map(func(k: Array) -> Array:
		var out := k.duplicate()
		for i in range(1, mini(4, out.size())):
			if out[i] != null:
				out[i] *= by
		return out)


static func _bound(expressions: Expressions, switches: Dictionary, meshes: Array, shapes: Dictionary, objs: Dictionary, paths: Dictionary, sk: Skeleton3D, materials: Materials, report: Dictionary) -> Dictionary:
	var data: Dictionary = expressions.data.duplicate(true)
	var targets: Array = switches.targets.duplicate(true)
	for m: Dictionary in meshes:
		if m.has("swap"):
			targets[m.swap].effect = {"material": {"node": m.node, "choices": m.choices}}
	var by_curve: Dictionary = switches.by_curve.duplicate()
	var dropped := expressions.dropped.duplicate()
	for clip: Dictionary in data.clips:
		var curves := []
		for c: Dictionary in clip.curves:
			var key := "%s|%s|%s" % [c.path, c.attribute, c["class"]]
			if not by_curve.has(key):
				var target := _target(c, objs, paths, meshes, shapes, sk, targets, materials)
				if target < 0:
					var kind := "shader property" if c.attribute.begins_with("material.") else "%s on class %s" % [c.attribute.get_slice(".", 0), c["class"]]
					dropped[kind + " curve"] = dropped.get(kind + " curve", 0) + 1
					continue
				by_curve[key] = target
			var t: int = by_curve[key]
			var curve := {"target": t, "step": targets[t].effect is String or targets[t].effect.has("material")}
			if c.has("refs"):
				var choices: Array = switches.slots.values().filter(func(s: Array) -> bool: return s[0] == t)[0][1]
				curve.keys = c.refs.map(func(k: Array) -> Array: return [k[0], maxi(choices.find_custom(func(m: Variant) -> bool: return m is Dictionary and m.get("guid", "") == k[1]), 0)])
			elif targets[t].effect is Dictionary and targets[t].effect.has("scale"):
				var rest: float = targets[t].rest
				curve.keys = _scaled(c["keys"], 1.0 / rest) if rest != 0.0 else c["keys"].map(func(k: Array) -> Array: return [k[0], 1.0])
			elif targets[t].effect is Dictionary and targets[t].effect.has("translation"):
				var rest: float = targets[t].rest
				curve.keys = c["keys"].map(func(k: Array) -> Array:
					var moved := k.duplicate()
					moved[1] = k[1] - rest
					return moved)
			elif (targets[t].effect is Dictionary and targets[t].effect.has("rotation")) or ExpressionDefinition.region(targets[t].effect) != "":
				curve.keys = c["keys"].duplicate(true)
			elif targets[t].effect is Dictionary and targets[t].effect.has("morph"):
				curve.keys = _scaled(c["keys"], 0.01)
			else:
				curve.keys = c["keys"].map(func(k: Array) -> Array: return [k[0], 1.0 if k[1] != 0.0 else 0.0])
			curves.append(curve)
		clip.curves = curves
	for t: Dictionary in targets:
		t.erase("rest")
	var moving := func(motion: Dictionary, recurse: Callable) -> bool:
		return (motion.has("clip") and not (data.clips[motion.clip].curves as Array).is_empty()) or (motion.get("children", []) as Array).any(func(c: Dictionary) -> bool: return recurse.call(c.motion, recurse))
	var read_by := func(layer: Dictionary) -> Dictionary:
		var names := {}
		var add := func(motion: Dictionary, recurse: Callable) -> void:
			if motion.has("time"):
				names[motion.time] = true
			for p: String in motion.get("parameters", []):
				names[p] = true
			for c: Dictionary in motion.get("children", []):
				names[c.parameter] = true
				recurse.call(c.motion, recurse)
		for t: Dictionary in layer.entry + layer.any:
			for c: Dictionary in t.conditions:
				names[c.parameter] = true
		for s: Dictionary in layer.states:
			add.call(s.get("motion", {}), add)
			for t: Dictionary in s.transitions:
				for c: Dictionary in t.conditions:
					names[c.parameter] = true
			for d: Dictionary in s.drivers:
				names[d.source] = true
		return names
	var live := {}
	var reads := {}
	for i in (data.layers as Array).size():
		reads[i] = read_by.call(data.layers[i])
		if (data.layers[i].states as Array).any(func(s: Dictionary) -> bool: return moving.call(s.get("motion", {}), moving)):
			live[i] = true
	var effective := {}
	var grew := true
	while grew:
		grew = false
		for i: int in live:
			for p: String in reads[i]:
				if not effective.has(p):
					effective[p] = true
					grew = true
		for i in (data.layers as Array).size():
			if not live.has(i) and (data.layers[i].states as Array).any(func(s: Dictionary) -> bool: return (s.drivers as Array).any(func(d: Dictionary) -> bool: return effective.has(d.parameter))):
				live[i] = true
				grew = true
	data.layers = range((data.layers as Array).size()).filter(func(i: int) -> bool: return live.has(i)).map(func(i: int) -> Dictionary: return data.layers[i])
	var cut := []
	data.icons = []
	data.menu = _pruned(data.menu, effective, cut, materials, data.icons, {})
	if not cut.is_empty():
		dropped["menu controls moving nothing the model shows"] = cut.size()
	var looks := materials.looks()
	if not looks.is_empty():
		data.looks = looks
	var hue_mask := materials.hue_mask()
	if hue_mask != "":
		data.hueMask = hue_mask
	var color_atlas := materials.color_atlas()
	if color_atlas != "":
		data.colorAtlas = color_atlas
	data.targets = targets
	data.shown = meshes.filter(func(m: Dictionary) -> bool: return not (m.when as Array).is_empty()).map(func(m: Dictionary) -> Dictionary: return {"node": m.node, "when": m.when})
	report["menu"] = "%d controls over %d layers, %d targets" % [_controls(data.menu), (data.layers as Array).size(), targets.size()]
	if not dropped.is_empty():
		report["menu: not translated"] = dropped
	return data


static func _target(c: Dictionary, objs: Dictionary, paths: Dictionary, meshes: Array, shapes: Dictionary, sk: Skeleton3D, targets: Array, materials: Materials) -> int:
	if not paths.has(c.path) or c.has("refs"):
		return -1
	var transform: int = paths[c.path]
	var go := _ref(objs[transform].data.get("m_GameObject"))
	var effect := {}
	var rest := 1.0
	var bone: int = (sk.get_meta("unity_bones", {}) as Dictionary).get(go, sk.find_bone(str(objs.get(go, {}).get("data", {}).get("m_Name", "")).validate_node_name()))
	if c.attribute.begins_with("blendShape.") and c["class"] == "137":
		var renderer := _renderer_of(objs, go)
		var shape: String = shapes.get(renderer, {}).get(c.attribute.trim_prefix("blendShape."), "")
		var binds := []
		for m: Dictionary in meshes:
			if renderer in m.renderers and m.names.has(shape):
				binds.append([m.node, m.names[shape]])
				rest = m.weights[m.names[shape]]
		if binds.is_empty():
			return -1
		effect = {"morph": binds}
	elif c.attribute.begins_with("material.") and c["class"] == "137":
		var property: String = c.attribute.trim_prefix("material.")
		var channel := "rgb".find(property.right(1)) if property in ["_Color.r", "_Color.g", "_Color.b"] else -1
		var tone := ["MainGamma", "Saturation", "MainBrightness"].find(property.get_slice("_", 1))
		var look := Materials.field(property)
		if channel < 0 and tone < 0 and look.is_empty() and property not in ["_MainHueShift", "_HueShift"] and not property.begins_with("_MainHueShift_"):
			return -1
		var kind := "color" if channel >= 0 else "tone" if tone >= 0 else "look" if not look.is_empty() else "hue"
		var renderer := _renderer_of(objs, go)
		var regions := []
		for ref: Variant in Prefabs._list(objs.get(renderer, {}).get("data", {}).get("m_Materials")):
			if not ref is Dictionary:
				continue
			var key := str(ref.get("guid", ""))
			if not materials.materials.has(key):
				continue
			var material: Dictionary = materials.materials[key]
			if not material.has("cell") or not (material.get("properties", {}) as Dictionary).has("_Color" if channel >= 0 else property):
				continue
			var binding := {}
			if channel >= 0:
				var color: Color = material.colour
				binding = {"channel": channel, "color": [color.r, color.g, color.b]}
				rest = color[channel]
				materials.color_regions[key] = true
			else:
				var floats: Dictionary = material.get("floats", {})
				if not floats.has(property):
					continue
				if not look.is_empty():
					if not materials.draws(key, look):
						continue
					binding = look.duplicate()
					if look.field.begins_with("decal"):
						binding.merge(materials.decal(key, look.slot))
				elif tone >= 0:
					if str(floats.get("_MainColorAdjustToggle", "0")).to_float() == 0.0:
						continue
					binding = {"channel": tone}
					materials.hue_masks[key] = true
				else:
					var mobile := property == "_HueShift" and Materials.toon_standard(material)
					if mobile:
						if not "USE_HUE_SHIFT" in material.get("keywords", []):
							continue
					elif property == "_HueShift" or str(floats.get("_MainHueShiftToggle", "0")).to_float() == 0.0:
						continue
					binding = {"space": 2.0 if mobile else str(floats.get("_MainHueShiftColorSpace", "0")).to_float(), "shift": str(floats.get("_MainHueShiftSelectOrShift", "1")).to_float()}
					materials.hue_masks[key] = true
				rest = str(floats[property]).to_float()
			var cell: Rect2 = Rect2(material.cell)
			binding.rect = [cell.position.x / Materials.ATLAS, cell.position.y / Materials.ATLAS, cell.end.x / Materials.ATLAS, cell.end.y / Materials.ATLAS]
			for m: Dictionary in meshes:
				if renderer in m.renderers:
					var region := binding.duplicate(true)
					region.node = m.node
					regions.append(region)
		if regions.is_empty():
			return -1
		effect = {kind: regions}
	elif c.attribute.begins_with("m_LocalScale.") and c["class"] == "4":
		if bone < 0:
			return -1
		var axis := "xyz".find(c.attribute.right(1))
		var local: Variant = objs[transform].data.get("m_LocalScale")
		rest = str((local as Dictionary).get(c.attribute.right(1), "1")).to_float() if local is Dictionary else 1.0
		effect = {"scale": {"node": sk.get_bone_name(bone), "axis": axis}}
	elif c["class"] == "4" and (c.attribute.get_slice(".", 0) in EULERS or c.attribute.begins_with("m_LocalRotation.") or c.attribute.begins_with("m_LocalPosition.")):
		# VRChat masks FX transform curves off humanoid bones; the humanoid's pose is the muscles'.
		if bone < 0 or (sk.get_meta("humanoid_bones", {}) as Dictionary).has(bone):
			return -1
		var data: Dictionary = objs[transform].data
		var f := func(v: Variant, k: String, otherwise: float) -> float: return str((v as Dictionary).get(k, otherwise)).to_float() if v is Dictionary else otherwise
		var q: Variant = data.get("m_LocalRotation")
		var unity := Quaternion(f.call(q, "x", 0.0), f.call(q, "y", 0.0), f.call(q, "z", 0.0), f.call(q, "w", 1.0))
		if c.attribute.begins_with("m_LocalPosition."):
			var axis := "xyz".find(c.attribute.right(1))
			rest = f.call(data.get("m_LocalPosition"), c.attribute.right(1), 0.0)
			var along := Vector3.ZERO
			along[axis] = -1.0 if axis == 0 else 1.0
			var parent := sk.get_bone_parent(bone)
			var scene := sk.get_meta("unity_frame", Transform3D.IDENTITY) as Transform3D * _world_transform(objs, transform)
			# The bone's frame is the source's, X mirrored; only the units its parent measures in may differ.
			var direction := along * (scene * _local(data).affine_inverse()).basis.get_scale() / (sk.get_bone_global_rest(parent).basis.get_scale() if parent >= 0 else Vector3.ONE)
			effect = {"translation": {"node": sk.get_bone_name(bone), "direction": [direction.x, direction.y, direction.z]}}
		else:
			var euler: bool = c.attribute.get_slice(".", 0) in EULERS
			var at: Vector3 = Basis(unity.normalized() if unity.length() > 0.0 else Quaternion.IDENTITY).get_euler(EULER_ORDER_YXZ) * 180.0 / PI
			var hint: Variant = data.get("m_LocalEulerAnglesHint")
			if hint is Dictionary:
				at = Vector3(f.call(hint, "x", at.x), f.call(hint, "y", at.y), f.call(hint, "z", at.z))
			var values: Array = [at.x, at.y, at.z] if euler else [unity.x, unity.y, unity.z, unity.w]
			var axis := ("xyz" if euler else "xyzw").find(c.attribute.right(1))
			rest = values[axis]
			effect = {"rotation": {"node": sk.get_bone_name(bone), "axis": axis, "rest": values}}
	else:
		return -1
	for i in targets.size():
		if targets[i].effect is Dictionary and targets[i].effect == effect:
			return i
	var default := 1.0
	if effect.has("morph") or ExpressionDefinition.region(effect) != "" or effect.has("rotation"):
		default = rest
	elif effect.has("translation"):
		default = 0.0
	targets.append({"effect": effect, "default": default, "rest": rest if effect.has("scale") or effect.has("translation") else 1.0})
	return targets.size() - 1


## The menu without the controls whose parameters are not `effective`, nor the submenus left empty; each icon a
## Base64 PNG of at most ICON pixels a side in `icons`, by index.
static func _pruned(menu: Array, effective: Dictionary, cut: Array, materials: Materials, icons: Array, indices: Dictionary) -> Array:
	var out := []
	for c: Dictionary in menu:
		var icon: String = c.icon
		c.erase("icon")
		if icon != "" and materials.assets.by_guid.has(icon) and not indices.has(icon):
			var image := materials.image(icon)
			if image != null:
				var small := image.duplicate() as Image
				var side := maxf(small.get_width(), small.get_height())
				if side > ICON:
					small.resize(maxi(roundi(small.get_width() * ICON / side), 1), maxi(roundi(small.get_height() * ICON / side), 1), Image.INTERPOLATE_LANCZOS)
				indices[icon] = icons.size()
				icons.append(Marshalls.raw_to_base64(small.save_png_to_buffer()))
		if indices.has(icon):
			c.icon = indices[icon]
		if c.type == "submenu":
			c.controls = _pruned(c.controls, effective, cut, materials, icons, indices)
			if (c.controls as Array).is_empty():
				continue
		elif not (effective.has(c.parameter) or (c.axes as Array).any(func(a: String) -> bool: return effective.has(a))):
			cut.append(c.name)
			continue
		out.append(c)
	return out


static func _controls(menu: Array) -> int:
	return menu.reduce(func(n: int, c: Dictionary) -> int: return n + 1 + (_controls(c.controls) if c.has("controls") else 0), 0)


## Script constraints without a runtime representation still exclude externally placed geometry.
static func _constrained(objs: Dictionary, go: int, inside: Dictionary) -> bool:
	for c: Variant in Prefabs._list(objs.get(go, {}).get("data", {}).get("m_Component")):
		var id := _ref((c as Dictionary).get("component"))
		if not objs.has(id):
			continue
		var d: Dictionary = objs[id].data
		var sources := []
		if objs[id].type == "MonoBehaviour" and d.get("Sources") is Dictionary and (d.has("PositionAtRest") or d.has("PositionOffset")):
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


static func _world_transform(objs: Dictionary, t: int) -> Transform3D:
	var world := Transform3D.IDENTITY
	var seen := {}
	while objs.has(t) and not seen.has(t):
		seen[t] = true
		world = _local(objs[t].data) * world
		t = _ref(objs[t].data.get("m_Father"))
	return world


## The transforms of the avatar's own skeleton by name: those the main model's renderers skin to, and the model's own
## objects, so an armature unpacked into the scene, its objects no longer the model's, still counts.
static func _model_bones(objs: Dictionary, top: int, model: String, renderers: Array) -> Dictionary:
	var out := {}
	for r: Array in renderers:
		if _mesh_model(objs, r[0], objs[r[0]].type) != model:
			continue
		for t: Variant in Prefabs._list(objs[r[0]].data.get("m_Bones")):
			var go := _ref(objs.get(_ref(t), {}).get("data", {}).get("m_GameObject"))
			if objs.has(go):
				out.get_or_add(str(objs[go].data.get("m_Name", "")), _ref(t))
	for e: Array in _under(objs, top):
		var object: Dictionary = objs.get(e[1], {})
		if object.get("guid", "") == model:
			out[str(object.get("data", {}).get("m_Name", ""))] = e[0]
	return out


static func _attach_armatures(objs: Dictionary, top: int, bones: Dictionary, definition: Dictionary, report: Dictionary) -> void:
	var names := ["Hips", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot", "Spine", "Chest", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftToes", "RightToes", "LeftEye", "RightEye", "Jaw"]
	for side: String in ["Left", "Right"]:
		for finger: String in ["Thumb", "Index", "Middle", "Ring", "Little"]:
			for part: String in ["Proximal", "Intermediate", "Distal"]:
				names.append(side + finger + part)
	names.append("UpperChest")
	var targets := {}
	var inside := {}
	for e: Array in _under(objs, top):
		inside[e[1]] = true
	for name: String in definition.human:
		if bones.has(name):
			targets[definition.human[name]] = bones[name]
	var links := []
	var unlinked := []
	for id: int in objs:
		var d: Dictionary = objs[id].data
		if objs[id].type != "MonoBehaviour" or not inside.has(_ref(d.get("m_GameObject"))):
			continue
		for entry: Dictionary in Prefabs._list(d.get("references", {}).get("RefIds")):
			if entry.get("type", {}).get("class", "") != "ArmatureLink":
				continue
			var link: Dictionary = entry.data
			var go := _ref(link.get("propBone"))
			if not objs.has(go):
				continue
			var from := _transform(objs, go)
			var to := 0
			for target: Dictionary in Prefabs._list(link.get("linkTo")):
				if str(target.get("offset", "")) != "":
					continue
				var index := str(target.get("bone", "-1")).to_int()
				if str(target.get("useBone", "0")) == "1" and index >= 0 and index < names.size():
					to = targets.get(names[index], 0)
				elif str(target.get("useObj", "0")) == "1" and objs.has(_ref(target.get("obj"))):
					to = _transform(objs, _ref(target.get("obj")))
				if to != 0:
					break
			if from == 0 or to == 0 or from == to:
				if from != to:
					unlinked.append({"source_id": id, "from": go, "link": JSON.stringify(link.get("linkTo"))})
				continue
			var world := _world_transform(objs, from)
			var parent := _world_transform(objs, to)
			if str(link.get("alignPosition", "0")) == "1":
				world.origin = parent.origin
			if str(link.get("alignRotation", "0")) == "1":
				world.basis = parent.basis.orthonormalized().scaled_local(world.basis.get_scale())
			if str(link.get("alignScale", "0")) == "1":
				world.basis = world.basis.orthonormalized().scaled_local(parent.basis.get_scale() * str(link.get("skinRewriteScalingFactor", "1")).to_float())
			# Parent changes keep the authored world placement; only explicit alignment moves the prop.
			var local := parent.affine_inverse() * world
			var rotation := local.basis.orthonormalized().get_rotation_quaternion()
			var scale := local.basis.get_scale()
			var data: Dictionary = objs[from].data
			data.m_Father = {"fileID": str(to)}
			data.m_LocalPosition = {"x": str(-local.origin.x), "y": str(local.origin.y), "z": str(local.origin.z)}
			data.m_LocalRotation = {"x": str(rotation.x), "y": str(-rotation.y), "z": str(-rotation.z), "w": str(rotation.w)}
			data.m_LocalScale = {"x": str(scale.x), "y": str(scale.y), "z": str(scale.z)}
			links.append({"source_id": id, "from": go, "to": _ref(objs[to].data.get("m_GameObject"))})
	if not links.is_empty():
		report["armature attachments"] = JSON.stringify(links)
	if not unlinked.is_empty():
		report["armature links with no target in the avatar"] = JSON.stringify(unlinked)


## A node's transform from its scene's root.
static func _in_model(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## The drawn renderers' surfaces over `sk` as one mesh for each set of switches they draw under, its skin binding each
## source bone to the output bone of its name (or its nearest ancestor that has one), one bind per output bone since
## glTF lists a skin's joints once each (`_bind_once`): blend shapes kept, those of one
## name in several renderers one shape only where Unity always weighs them alike (one saved weight, the same clip curves
## in `animated`, renderer to shape name to [[clip, keys]]), while the vertices of the meshes each moves fit
## Avatar.MAX_BLEND_VERTICES together, those the menu's clips animate or the face uses (`faced`) first (the rest baked at their saved weights), UVs moved into the material atlas. A material slot the menu swaps (`slots`, "renderer:slot" to [switch
## target, [each material reference it can take]]) is a mesh of its own, its UVs in its first material's cell and
## "choices" moving them to each material's ([scale x, y, offset x, y]) under "swap", that switch.
## {"skin", "meshes": [{"mesh", "when", "renderers", "names": each of its shapes' name to its name in this mesh, "weights":
## each blend shape's saved weight}], "shapes": renderer to source shape name to its shape's name}, or empty if nothing
## draws.
static func _merge(prefabs: Prefabs, materials: Materials, objs: Dictionary, renderers: Array, slots: Dictionary, animated: Dictionary, faced: Dictionary, sk: Skeleton3D, rests: Array[Transform3D], scale: float, report: Dictionary) -> Dictionary:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var group_of := PackedInt32Array()
	var groups := {}
	var skin := Skin.new()
	var binds := {}
	var corners := {}
	var shapes := {}
	var saved_weights := {}
	var identities := {}
	var shape_of := {}
	var source_of := {}
	var live := {}
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
		var bind := _bind_once(place.binds, skin, binds, rests)
		var bound: Array = bind.bound
		var mesh: ArrayMesh = mi.mesh
		# Unity winds a renderer that its transforms mirror the other way, so its faces still face out.
		var mirrored := _world_transform(objs, _transform(objs, r[1])).basis.determinant() < 0.0
		var saved: Array = Prefabs._list(o.data.get("m_BlendShapeWeights"))
		var refs: Array = Prefabs._list(o.data.get("m_Materials"))
		var slot_of := _slot_of(mesh, refs, prefabs.assets, _slots(prefabs, str(ref.get("guid", ""))).get(_model_name(model, mi), []))
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			n.resize(v.size())
			var relative := mesh.blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
			var surface_shapes := mesh.surface_get_blend_shape_arrays(s)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			uv.resize(v.size())
			var fallback := Color.WHITE
			var sm := mesh.surface_get_material(s)
			if sm is BaseMaterial3D:
				fallback = (sm as BaseMaterial3D).albedo_color
			var slot: int = slot_of[s]
			var mref: Dictionary = refs[mini(slot, refs.size() - 1)] if not refs.is_empty() and refs[mini(slot, refs.size() - 1)] is Dictionary else {"name": String(sm.resource_name) if sm != null else ""}
			var swap: Array = slots.get("%d:%d" % [r[0], slot], [])
			var choices: Array = swap[1] if not swap.is_empty() else []
			var src_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var src_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var per := src_bones.size() / maxi(v.size(), 1)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			var group: Dictionary = groups.get_or_add("%s|%s" % [r[2], swap], {"index": groups.size(), "when": r[2], "renderers": {}})
			group.renderers[r[0]] = true
			var key := materials.use(mref, fallback)
			if not swap.is_empty():
				group.swap = swap[0]
				group.choices = choices.map(func(c: Variant) -> String: return materials.use(c if c is Dictionary else mref, fallback))
				key = group.choices[0]
			var base := verts.size()
			var tops := []
			var placed: Array[Transform3D] = []
			for i in v.size():
				var top := _top4(src_bones, src_weights, i, per)
				tops.append(top)
				placed.append(_at_rest(top, bind, place.remap))
			for k in surface_shapes.size():
				var source := mesh.get_blend_shape_name(k)
				var curves: Array = animated.get(r[0], {}).get(source, [])
				var weight := str(saved[k]).to_float() / 100.0 if k < saved.size() else 0.0
				var identity := JSON.stringify([source, weight, curves])
				if not identities.has(identity):
					var name := source
					var copy := 1
					while saved_weights.has(name):
						copy += 1
						name = "%s (%d)" % [source, copy]
					identities[identity] = name
					source_of[name] = source
					saved_weights[name] = weight
					if not curves.is_empty() or faced.has(source):
						live[name] = true
				var name: String = identities[identity]
				shape_of.get_or_add(r[0], {})[source] = name
				var moved: Dictionary = shapes.get_or_add(name, {})
				var sv: PackedVector3Array = surface_shapes[k][Mesh.ARRAY_VERTEX]
				var sn: Variant = surface_shapes[k][Mesh.ARRAY_NORMAL]
				for i in v.size():
					var dv := sv[i] if relative else sv[i] - v[i]
					var dn := Vector3.ZERO if not sn is PackedVector3Array else (sn as PackedVector3Array)[i] if relative else (sn as PackedVector3Array)[i] - n[i]
					if not (dv.is_zero_approx() and dn.is_zero_approx()):
						moved[base + i] = [placed[i].basis * dv, placed[i].basis * dn]
			for i in v.size():
				verts.append(placed[i] * v[i])
				var normal := placed[i].basis * n[i]
				normals.append(normal.normalized() if not normal.is_zero_approx() else Vector3.UP)
				uvs.append(uv[i])
				group_of.append(group.index)
				corners[base + i] = key
				var top: Array = tops[i]
				for j in 4:
					bones.append(bound[place.remap.call(top[0][j])])
					weights.append(top[1][j])
			for t in range(0, idx.size(), 3):
				for c: int in [0, 2, 1] if mirrored else [0, 1, 2]:
					indices.append(base + idx[t + c])
	if indices.is_empty():
		return {}
	var used := {}
	for i: int in corners:
		used[corners[i]] = true
	for group: Dictionary in groups.values():
		for key: String in group.get("choices", []):
			used[key] = true
	materials.pack(used.keys())
	for i in uvs.size():
		var at: Array = materials.place(corners[i], uvs[i])
		uvs[i] = at[0]
		if at[1]:
			tiled[materials.materials[corners[i]].name] = true
	var passes := materials.atlas_materials()
	var meshes := []
	var sizes := {}
	for g in group_of:
		sizes[g] = sizes.get(g, 0) + 1
	var kept := {}
	var budget := Avatar.MAX_BLEND_VERTICES
	var order := shapes.keys().filter(func(name: String) -> bool: return live.has(name)) + shapes.keys().filter(func(name: String) -> bool: return not live.has(name))
	for name: String in order:
		var moves := {}
		for i: int in shapes[name]:
			moves[group_of[i]] = true
		var cost: int = moves.keys().reduce(func(sum: int, g: int) -> int: return sum + sizes[g], 0)
		if cost <= budget:
			budget -= cost
			kept[name] = true
	var kept_shapes := 0
	var dropped_shapes := 0
	var baked := 0
	for group: Dictionary in groups.values():
		var faces: Array[PackedInt32Array] = []
		faces.resize(passes.size())
		var reversed := {}
		for t in range(0, indices.size(), 3):
			if group_of[indices[t]] == group.index:
				var m: Dictionary = materials.materials[corners[indices[t]]]
				faces[int(m.cull == Materials.Cull.OFF) + 2 * Materials.pass_of(m)].append(t)
				if m.cull == Materials.Cull.FRONT:
					reversed[t] = true
		var surfaces := []
		var touched := {}
		for slot in passes.size():
			if faces[slot].is_empty():
				continue
			var remap := {}
			var gi := PackedInt32Array()
			var gv := PackedVector3Array()
			var gn := PackedVector3Array()
			var gu := PackedVector2Array()
			var gb := PackedInt32Array()
			var gw := PackedFloat32Array()
			for t in faces[slot]:
				# A front-culled face shows its back: wound the other way, it is a back-culled face.
				for c: int in [0, 2, 1] if reversed.has(t) else [0, 1, 2]:
					var i := indices[t + c]
					if not remap.has(i):
						remap[i] = gv.size()
						touched[i] = true
						gv.append(verts[i])
						gn.append(normals[i])
						gu.append(uvs[i])
						gb.append_array(bones.slice(4 * i, 4 * i + 4))
						gw.append_array(weights.slice(4 * i, 4 * i + 4))
					gi.append(remap[i])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = gv
			arrays[Mesh.ARRAY_NORMAL] = gn
			arrays[Mesh.ARRAY_TEX_UV] = gu
			arrays[Mesh.ARRAY_BONES] = gb
			arrays[Mesh.ARRAY_WEIGHTS] = gw
			arrays[Mesh.ARRAY_INDEX] = gi
			surfaces.append({"arrays": arrays, "remap": remap, "material": passes[slot]})
		if surfaces.is_empty():
			continue
		var moving := shapes.keys().filter(func(name: String) -> bool: return (shapes[name] as Dictionary).keys().any(func(i: int) -> bool: return touched.has(i)))
		var names := moving.filter(func(name: String) -> bool: return kept.has(name))
		var dropped := moving.filter(func(name: String) -> bool: return not kept.has(name))
		kept_shapes += names.size()
		dropped_shapes += dropped.size()
		for name: String in dropped:
			var w: float = saved_weights.get(name, 0.0)
			if is_zero_approx(w):
				continue
			baked += 1
			for surface: Dictionary in surfaces:
				var gv: PackedVector3Array = surface.arrays[Mesh.ARRAY_VERTEX]
				for i: int in shapes[name]:
					if surface.remap.has(i):
						gv[surface.remap[i]] += w * (shapes[name][i][0] as Vector3)
				surface.arrays[Mesh.ARRAY_VERTEX] = gv
		# Shapes need distinct names only within one mesh, so each takes its source's name unless another shape of that
		# name shares the mesh.
		var sources: Array = names.map(func(name: String) -> String: return source_of[name])
		var named := {}
		for name: String in names:
			named[name] = source_of[name] if sources.count(source_of[name]) == 1 and not names.any(func(other: String) -> bool: return other != name and other == source_of[name]) else name
		var out := ArrayMesh.new()
		out.blend_shape_mode = Mesh.BLEND_SHAPE_MODE_RELATIVE
		for name: String in names:
			out.add_blend_shape(named[name])
		for surface: Dictionary in surfaces:
			var size: int = (surface.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var blends := []
			for name: String in names:
				var dv := PackedVector3Array()
				var dn := PackedVector3Array()
				dv.resize(size)
				dn.resize(size)
				for i: int in shapes[name]:
					if surface.remap.has(i):
						dv[surface.remap[i]] = shapes[name][i][0]
						dn[surface.remap[i]] = shapes[name][i][1]
				var b := []
				b.resize(Mesh.ARRAY_MAX)
				b[Mesh.ARRAY_VERTEX] = dv
				b[Mesh.ARRAY_NORMAL] = dn
				blends.append(b)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays, blends)
			out.surface_set_material(out.get_surface_count() - 1, surface.material)
		var part := {"mesh": out, "when": group.when, "renderers": group.renderers.keys(), "names": named, "weights": names.reduce(func(kept_weights: Dictionary, name: String) -> Dictionary:
			kept_weights[named[name]] = saved_weights.get(name, 0.0)
			return kept_weights, {})}
		if group.has("swap"):
			part.swap = group.swap
			part.choices = (group.choices as Array).map(func(c: String) -> Array:
				var m: Array = materials.moved(group.choices[0], c)
				return [m[0].x, m[0].y, m[1].x, m[1].y])
		meshes.append(part)
	report["renderers drawn"] = drawn
	if not skipped.is_empty():
		report["renderers not found in their model"] = skipped
	report["triangles"] = indices.size() / 3
	report["meshes"] = meshes.size()
	report["materials"] = used.keys().map(func(k: String) -> String: return _describe(materials.materials[k]))
	report["blend shapes"] = "%d kept over the meshes, %d past Avatar.MAX_BLEND_VERTICES dropped (%d of them baked at their saved weights)" % [kept_shapes, dropped_shapes, baked]
	if not tiled.is_empty():
		report["tiled textures clamped to one tile"] = tiled.keys()
	return {"skin": skin, "meshes": meshes, "shapes": shape_of}


## The avatar's face as {"expressions": each VRM expression's name to its [{"shape", "weight" 0 to 1}], "shapes": the
## blend shapes the descriptor and the FX layer's gesture faces use, in that order}: its visemes as VRM's (VISEMES) where
## it lip-syncs by blend shape, its eyelid blink shape as blink, and each gesture face, a clip a GestureLeft or
## GestureRight transition reaches, as the mood preset its name says (MOODS), once each, or else as itself by name.
static func _face(prefabs: Prefabs, objs: Dictionary, descriptor: Dictionary) -> Dictionary:
	var expressions := {}
	var used := []
	var visemes := Prefabs._list(descriptor.get("VisemeBlendShapes")) if str(descriptor.get("lipSync", "")) == "3" else []
	used.append_array(visemes)
	for preset: String in VISEMES:
		if VISEMES[preset] < visemes.size() and str(visemes[VISEMES[preset]]) != "":
			expressions[preset] = [{"shape": str(visemes[VISEMES[preset]]), "weight": 1.0}]
	var eyes: Variant = descriptor.get("customEyeLookSettings")
	if eyes is Dictionary and str(eyes.get("eyelidType", "")) == "2":
		var lids := _eyelid_shapes(prefabs, objs, eyes)
		used.append_array(lids)
		if not lids.is_empty() and lids[0] != "":
			expressions["blink"] = [{"shape": lids[0], "weight": 1.0}]
	for clip: Array in _gesture_faces(prefabs.assets, descriptor):
		var shapes: Dictionary = clip[1]
		used.append_array(shapes.keys())
		var name := _mood(clip[0])
		if name == "" or expressions.has(name):
			var base := (clip[0] as String).to_lower().strip_edges()
			name = base
			var n := 1
			while expressions.has(name) or name in Vrm.PRESETS:
				n += 1
				name = "%s %d" % [base, n]
		expressions[name] = shapes.keys().map(func(s: String) -> Dictionary: return {"shape": s, "weight": shapes[s]})
	return {"expressions": expressions, "shapes": used.filter(func(s: Variant) -> bool: return str(s) != "")}


## The mood preset (MOODS) a clip's name says, or "".
static func _mood(clip: String) -> String:
	var words := RegEx.create_from_string("[a-z]+").search_all(clip.to_lower()).map(func(m: RegExMatch) -> String: return m.get_string())
	for preset: String in MOODS:
		for word: String in words:
			if (MOODS[preset] as Array).any(func(k: String) -> bool: return word.begins_with(k)):
				return preset
	return ""


## The blend shapes a descriptor's eye-look settings close, raise and lower the eyelids with, by name ("" for none):
## eyelidsBlendshapes indexes eyelidsSkinnedMesh's shapes, written as little-endian 32-bit integers in hex.
static func _eyelid_shapes(prefabs: Prefabs, objs: Dictionary, eyes: Dictionary) -> Array:
	var renderer := _ref(eyes.get("eyelidsSkinnedMesh"))
	if not objs.has(renderer):
		return []
	var ref := _mesh_ref(objs, renderer)
	var guid := str(ref.get("guid", ""))
	var mi := _mesh_node(prefabs.model(guid) if prefabs.assets.by_guid.has(guid) else {}, str(ref.get("fileID", "0")).to_int())
	if mi == null or mi.mesh == null:
		return []
	var hex := str(eyes.get("eyelidsBlendshapes", ""))
	var out := []
	for at in range(0, hex.length() - 7, 8):
		var k := ("0x" + hex.substr(at + 6, 2) + hex.substr(at + 4, 2) + hex.substr(at + 2, 2) + hex.substr(at, 2)).hex_to_int()
		out.append(mi.mesh.get_blend_shape_name(k) if k < mi.mesh.get_blend_shape_count() else "")
	return out


## The clips the descriptor's FX controllers play on a GestureLeft or GestureRight transition that set blend shapes, as
## [clip name, {blend shape: its last keyed weight, 0 to 1}], each clip once.
static func _gesture_faces(assets: Assets, descriptor: Dictionary) -> Array:
	var out := []
	var seen := {}
	for layer: Variant in Prefabs._list(descriptor.get("baseAnimationLayers")):
		if not (layer is Dictionary and str(layer.get("type")) == "5" and layer.get("animatorController") is Dictionary):
			continue
		var controller := Yaml.objects(assets.text(str(layer.animatorController.get("guid", ""))))
		var trees := {}
		for t: Dictionary in controller.values():
			if t.type != "AnimatorStateTransition" or not Prefabs._list(t.data.get("m_Conditions")).any(func(c: Variant) -> bool: return c is Dictionary and str(c.get("m_ConditionEvent")) in ["GestureLeft", "GestureRight"]):
				continue
			var pending := [controller.get(_ref(t.data.get("m_DstState")), {}).get("data", {}).get("m_Motion")]
			while not pending.is_empty():
				var motion: Variant = pending.pop_front()
				var guid := str(motion.get("guid", "")) if motion is Dictionary else ""
				if guid == "":
					if not trees.has(_ref(motion)):
						trees[_ref(motion)] = true
						for child: Variant in Prefabs._list(controller.get(_ref(motion), {}).get("data", {}).get("m_Childs")):
							pending.append(child.get("m_Motion") if child is Dictionary else null)
					continue
				if seen.has(guid) or assets.extension(guid) != "anim":
					continue
				seen[guid] = true
				var shapes := _clip_shapes(assets.text(guid))
				if not shapes.is_empty():
					out.append([assets.name(guid), shapes])
	return out


## The blend shapes an animation clip sets above zero, each at the weight (0 to 1) of its curve's last key.
static func _clip_shapes(text: String) -> Dictionary:
	var shapes := {}
	for o: Dictionary in Yaml.objects(text).values():
		for c: Variant in Prefabs._list(o.data.get("m_FloatCurves")):
			if not (c is Dictionary and str(c.get("classID")) == "137" and str(c.get("attribute")).begins_with("blendShape.")):
				continue
			var keys := Prefabs._list((c.get("curve", {}) as Dictionary).get("m_Curve")) if c.get("curve") is Dictionary else []
			var w := clampf(str((keys[-1] as Dictionary).get("value", "0")).to_float() / 100.0, 0.0, 1.0) if not keys.is_empty() and keys[-1] is Dictionary else 0.0
			var name := str(c.attribute).trim_prefix("blendShape.")
			if w > 0.0:
				shapes[name] = maxf(shapes.get(name, 0.0), w)
	return shapes


static func _describe(m: Dictionary) -> String:
	var texture := "no texture" if m.texture == "" else ("texture" if m.image != null else "texture not decoded")
	return "%s [%s, %s, %s%s]" % [m.name, m.shader if m.shader != "" else "not in package", texture, ["opaque", "cutout", "blended, depth written" if m.depth else "blended"][m.alpha], [", two-sided", ", front faces culled", ""][m.cull]]


## A source's [[output bone, bind pose]...] bound into `skin`, which binds each output bone once (`binds`, bone to
## index), as {"bound": each one's index in `skin`, "moves": each one's move of the source's vertices into that bind,
## or null where its vertices blend "shared" and "own", each bind's (output rest * the skin's bind) and (output rest *
## the source's bind)}. A bone already bound keeps its bind; when the source binds such bones in other poses differing
## by one transform, as a second model of the package placed apart does, that transform moves its vertices and its new
## bones bind to match, which skins exactly in every pose.
static func _bind_once(source_binds: Array, skin: Skin, binds: Dictionary, rests: Array[Transform3D]) -> Dictionary:
	var known := []
	for b: Array in source_binds:
		if binds.has(b[0]):
			known.append(skin.get_bind_pose(binds[b[0]]).affine_inverse() * b[1])
	var move: Transform3D = known[0] if not known.is_empty() and not _same(known[0], Transform3D.IDENTITY) else Transform3D.IDENTITY
	var rigid := known.all(func(m: Transform3D) -> bool: return _same(m, move))
	var bound := []
	var shared := []
	var own := []
	for b: Array in source_binds:
		if not binds.has(b[0]):
			binds[b[0]] = skin.get_bind_count()
			skin.add_bind(b[0], b[1] * move.affine_inverse() if rigid else b[1])
		bound.append(binds[b[0]])
		shared.append(rests[b[0]] * skin.get_bind_pose(binds[b[0]]))
		own.append(rests[b[0]] * b[1])
	return {"bound": bound, "moves": source_binds.map(func(_b: Array) -> Variant: return move if rigid else null), "shared": shared, "own": own}


## Whether two binds' moves agree to within a tenth of a millimetre of a metre-scale bind, as an exporter's rounding does.
static func _same(a: Transform3D, b: Transform3D) -> bool:
	return (a.basis.x - b.basis.x).length() <= 1e-4 and (a.basis.y - b.basis.y).length() <= 1e-4 and (a.basis.z - b.basis.z).length() <= 1e-4 and (a.origin - b.origin).length() <= 1e-4


## What moves a vertex weighted `top` ([source bind indices, weights]) into the skin's binds (`bind`, from
## `_bind_once`): the source's one move when it has one, otherwise what puts the vertex where the source's binds do
## with the skeleton at rest.
static func _at_rest(top: Array, bind: Dictionary, remap: Callable) -> Transform3D:
	var move: Variant = bind.moves[remap.call(top[0][0])] if not bind.moves.is_empty() else null
	if move != null:
		return move
	return _blend(top, bind.shared, remap).affine_inverse() * _blend(top, bind.own, remap)


## The weighted blend of the transforms `top` ([indices, weights]) picks from `of`.
static func _blend(top: Array, of: Array, remap: Callable) -> Transform3D:
	var x := Vector3.ZERO
	var y := Vector3.ZERO
	var z := Vector3.ZERO
	var origin := Vector3.ZERO
	for j in 4:
		var at: Transform3D = of[remap.call(top[0][j])]
		var w: float = top[1][j]
		x += at.basis.x * w
		y += at.basis.y * w
		z += at.basis.z * w
		origin += at.origin * w
	return Transform3D(Basis(x, y, z), origin)


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
## use, they pair in the order those polygons first use them, as Unity pairs submeshes with slots; slots past the last
## submesh only draw it again, so they leave the pairing alone. Otherwise a surface takes the slot whose material is
## named like its FBX material ("Head" for "Head.003", "Eye" for "Eye Left"), and the rest pair in order.
static func _slot_of(mesh: ArrayMesh, refs: Array, assets: Assets, order: Array) -> Array:
	var names := []
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		names.append(String(m.resource_name) if m != null else "")
	var out := []
	for s in names.size():
		var i := order.find(names[s])
		out.append(i if i >= 0 and refs.size() >= order.size() else -1)
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
	var same_model: bool = not sk.has_meta("unity_model") or _mesh_model(objs, renderer, objs[renderer].type) == sk.get_meta("unity_model")
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
			var name := str(objs.get(go, {}).get("data", {}).get("m_Name", "")).validate_node_name()
			unity[name] = _ref(t)
			var bone := _find_bone(sk, name)
			if same_model and sk.has_meta("unity_bones") and bone >= 0 and bone < humanoid_bones:
				sk.get_meta("unity_bones")[go] = bone
		var binds := []
		for i in mi.skin.get_bind_count():
			var b := mi.skin.get_bind_bone(i)
			if b < 0:
				b = src.find_bone(mi.skin.get_bind_name(i))
			var name := src.get_bone_name(maxi(b, 0))
			var t := _find_bone(sk, name)
			if unity.has(name) and (not same_model or t < 0 or t >= humanoid_bones):
				t = _as_bone(objs, unity[name], sk, rests)
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


static func _as_bone(objs: Dictionary, t: int, sk: Skeleton3D, rests: Array[Transform3D]) -> int:
	var source_bones: Dictionary = sk.get_meta("unity_bones", {})
	var go_of := func(at: int) -> int: return _ref(objs.get(at, {}).get("data", {}).get("m_GameObject"))
	var name_of := func(at: int) -> String:
		return str(objs.get(go_of.call(at), {}).get("data", {}).get("m_Name", ""))
	if source_bones.has(go_of.call(t)):
		return source_bones[go_of.call(t)]
	var path := []
	var seen := {}
	var b := -1
	while objs.has(t) and not seen.has(t) and b < 0:
		seen[t] = true
		path.append(t)
		t = _ref(objs[t].data.get("m_Father"))
		b = source_bones.get(go_of.call(t), -1) if sk.has_meta("unity_bones") else _find_bone(sk, name_of.call(t))
	if b < 0 and (path.is_empty() or path.back() != sk.get_meta("unity_top", -1)):
		return -1
	var frame: Transform3D = sk.get_meta("unity_frame", Transform3D.IDENTITY)
	# The transforms keep their place relative to the bone they hang from, as it stands in the scene, wherever the
	# output skeleton's rest puts that bone.
	var follow := Transform3D.IDENTITY
	if b >= 0:
		var scene := frame * _world_transform(objs, t)
		follow = Transform3D(rests[b].basis.orthonormalized(), rests[b].origin) * Transform3D(scene.basis.orthonormalized(), scene.origin).affine_inverse()
	for i in range(path.size() - 1, -1, -1):
		var world := follow * frame * _world_transform(objs, path[i])
		var name: String = name_of.call(path[i]).replace(":", "_").replace("/", "_").validate_node_name()
		while sk.find_bone(name) >= 0:
			name += "_"
		var added := sk.get_bone_count()
		sk.add_bone(name)
		sk.set_bone_parent(added, b)
		sk.set_bone_rest(added, rests[b].affine_inverse() * world if b >= 0 else world)
		sk.reset_bone_pose(added)
		source_bones[go_of.call(path[i])] = added
		rests.append(world)
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


## VRM ends a spring at a node, so authored endpoints become bones beyond the leaves.
## PhysBone roots with several child chains remain fixed unless the source chooses First.
## A component runs as Unity runs it when the avatar loads or the menu's `switches` turn it on; "switched" lists those
## the menu switches, a PhysBone's joints or a collider's index with the switches it runs under. `moved` holds the
## transforms the menu's curves move.
static func _springs(objs: Dictionary, top: int, sk: Skeleton3D, human: Dictionary, k: float, report: Dictionary, switches := {}, moved := {}) -> Dictionary:
	var bone_of := func(t: int) -> int:
		var go := _ref(objs.get(t, {}).get("data", {}).get("m_GameObject"))
		return sk.get_meta("unity_bones").get(go, -1) if sk.has_meta("unity_bones") else _find_bone(sk, str(objs.get(go, {}).get("data", {}).get("m_Name", "")))
	var transforms := {}
	for id: int in objs:
		if objs[id].type == "Transform":
			var go := _ref(objs[id].data.get("m_GameObject"))
			if objs.has(go):
				transforms[go] = id
	var canonical := func(t: int) -> int:
		return transforms.get(_ref(objs.get(t, {}).get("data", {}).get("m_GameObject")), t)
	var children := {}
	# Aliases name the same source transform; unweighted organizational roots still own spring branches.
	for t: int in transforms.values():
		children.get_or_add(canonical.call(_ref(objs[t].data.get("m_Father"))), []).append(t)
	var colliders := []
	var collider_index := {}
	var springs := []
	var physbones := 0
	var dynamicbones := 0
	var coverage := []
	var live := {}
	for e: Array in _under(objs, top):
		live[_ref(objs[e[0]].data.get("m_GameObject"))] = true
	# A component may sit outside the avatar (a tool merges it in at upload) while its root is a bone of it.
	var ours := func(d: Dictionary) -> bool:
		var t := _ref(d.get("rootTransform", d.get("m_Root")))
		if t == 0:
			var go := _ref(d.get("m_GameObject"))
			t = _transform(objs, go) if objs.has(go) else 0
		return live.has(_ref(objs.get(t, {}).get("data", {}).get("m_GameObject")))
	var components := {}
	var component_when := {}
	var switched := {"springs": [], "colliders": []}
	var component_roots := {}
	var idle := 0
	for id: int in objs:
		var d: Dictionary = objs[id].data
		if objs[id].type != "MonoBehaviour" or not _spring_component(d) or not ours.call(d):
			continue
		var when: Variant = _when(objs, id, d, switches)
		if when == null:
			idle += 1
			continue
		components[id] = d
		if not when.is_empty():
			component_when[id] = when
		var t := _ref(d.get("rootTransform", d.get("m_Root")))
		if t == 0:
			t = _transform(objs, _ref(d.get("m_GameObject")))
		component_roots[canonical.call(t)] = true
	var rests: Array[Transform3D] = []
	var original_bones := sk.get_bone_count()
	for bone in original_bones:
		rests.append(sk.get_bone_global_rest(bone))
	var pending_bones := component_roots.keys()
	var visited := {}
	while not pending_bones.is_empty():
		var t: int = pending_bones.pop_front()
		if visited.has(t):
			continue
		visited[t] = true
		var bone: int = bone_of.call(t)
		if bone < 0:
			bone = _as_bone(objs, t, sk, rests)
		var parent: int = bone_of.call(_ref(objs.get(t, {}).get("data", {}).get("m_Father")))
		# An unweighted source parent may have been omitted while its weighted children survived.
		if bone >= 0 and parent >= original_bones and bone != parent and not human.has(bone):
			sk.set_bone_parent(bone, parent)
			sk.set_bone_rest(bone, rests[parent].affine_inverse() * rests[bone])
			sk.reset_bone_pose(bone)
		pending_bones.append_array(children.get(t, []))
	# A collider sits on a bone's unweighted child as often as on the bone, so it goes onto the nearest kept ancestor.
	var frame: Transform3D = sk.get_meta("unity_frame", Transform3D.IDENTITY)
	var dropped := 0
	for id: int in objs:
		var d: Dictionary = objs[id].data
		if objs[id].type != "MonoBehaviour" or not ours.call(d):
			continue
		var c := _collider(d)
		if c.is_empty():
			continue
		var when: Variant = _when(objs, id, d, switches)
		if when == null:
			idle += 1
			continue
		var t := _ref(d.get("rootTransform"))
		if t == 0:
			t = _transform(objs, _ref(d.get("m_GameObject")))
		# A collider the menu moves rides a bone of its own, which the menu's transform curves move.
		if moved.has(t):
			_as_bone(objs, t, sk, rests)
		var placed := frame * _world_transform(objs, t) * (c.local as Transform3D)
		var bone := -1
		var at := t
		var owner := t
		var seen := {}
		while objs.has(at) and not seen.has(at) and bone < 0:
			seen[at] = true
			bone = bone_of.call(at)
			owner = at
			at = _ref(objs[at].data.get("m_Father"))
		if bone < 0:
			dropped += 1
			continue
		var held := sk.get_bone_global_rest(bone)
		# The collider rides its bone as Unity places it there; the output rest may pose the bone elsewhere.
		var unity_held := frame * _world_transform(objs, owner)
		var local := Transform3D.IDENTITY.scaled(Vector3.ONE * unity_held.basis.get_scale().x / held.basis.get_scale().x) * (unity_held.affine_inverse() * placed)
		var scale: Vector3 = placed.basis.get_scale().abs()
		var radius: float = c.radius * maxf(scale.x, maxf(scale.y, scale.z)) / held.basis.get_scale().x
		var axis: Vector3 = c.axis
		var v := func(x: Vector3) -> Array: return [x.x, x.y, x.z]
		var offset: Array = v.call(local.origin)
		var geometry := {"offset": offset, "radius": radius}
		var kind := "sphere"
		if c.kind == "plane":
			kind = "plane"
			geometry = {"offset": offset, "normal": v.call((local.basis.inverse().transposed() * axis).normalized())}
		elif c.half > 0.0:
			kind = "capsule"
			geometry = {"offset": v.call(local * (-axis * c.half)), "tail": v.call(local * (axis * c.half)), "radius": radius}
		var collider := {"node": bone, "shape": {kind: geometry}}
		# VRM's own shapes cannot keep a joint inside or behind a plane; readers without the extension see a point.
		if c.inside or kind == "plane":
			if c.inside:
				geometry["inside"] = true
			collider = {"node": bone, "shape": {"sphere": {"offset": offset, "radius": 0.0}}, "extensions": {"VRMC_springBone_extended_collider": {"specVersion": "1.0", "shape": {kind: geometry}}}}
		collider_index[id] = colliders.size()
		if not when.is_empty():
			switched.colliders.append({"collider": colliders.size(), "when": when})
		colliders.append(collider)
	for id: int in components:
		var d: Dictionary = components[id]
		var legacy := d.has("m_Damping")
		physbones += int(not legacy)
		dynamicbones += int(legacy)
		var root_t := _ref(d.get("rootTransform", d.get("m_Root")))
		if root_t == 0:
			root_t = _transform(objs, _ref(d.get("m_GameObject")))
		root_t = canonical.call(root_t)
		var root_bone: int = bone_of.call(root_t)
		var component := {"source_id": id, "kind": "DynamicBone" if legacy else "PhysBone", "root": str(objs.get(_ref(objs.get(root_t, {}).get("data", {}).get("m_GameObject")), {}).get("data", {}).get("m_Name", "")), "chains": [], "simulated_joints": 0, "reason": "root absent from output skeleton" if root_bone < 0 else ""}
		coverage.append(component)
		var first_chain := springs.size()
		var ignored := {}
		if not legacy and str(d.get("ignoreOtherPhysBones", "1")) != "0":
			for other: int in component_roots:
				if other != root_t:
					ignored[other] = true
		for t: Variant in Prefabs._list(d.get("ignoreTransforms", d.get("m_Exclusions"))):
			ignored[canonical.call(_ref(t))] = true
		# A PhysBone's negative gravity pulls up; a VRM gravityPower may not be negative, so its direction carries the sign.
		var gravity := str(d.get("gravity", "0")).to_float()
		# A DynamicBone sizes its radius and end offset by its own transform, wherever its root bone lies.
		var holder := _transform(objs, _ref(d.get("m_GameObject"))) if objs.has(_ref(d.get("m_GameObject"))) else 0
		var held_by := frame * _world_transform(objs, holder if holder != 0 else root_t)
		var joint := {"stiffness": 4.0 * str(d.get("pull", d.get("m_Elasticity", "0.2"))).to_float() * (1.0 + str(d.get("stiffness", d.get("m_Stiffness", "0"))).to_float()), "dragForce": clampf(str(d.m_Damping).to_float() if legacy else 1.0 - str(d.get("spring", "0.2")).to_float(), 0.0, 1.0), "gravityPower": absf(gravity), "gravityDir": [0, 1 if gravity < 0.0 else -1, 0], "hitRadius": str(d.get("radius", d.get("m_Radius", "0"))).to_float() * (held_by.basis.get_scale().x if legacy else k)}
		# A PhysBone's limit keeps each bone's swing about its rest direction inside a cone (Angle), an arc in one plane
		# (Hinge) or an elliptical cone (Polar), turned by limitRotation, Unity's Euler angles (about Z, then X, then Y).
		var limit_shape: String = "" if legacy else ["", "angle", "hinge", "polar"][clampi(str(d.get("limitType", "0")).to_int(), 0, 3)]
		var turned: Variant = d.get("limitRotation")
		var about := func(axis: Vector3, key: String) -> Quaternion: return Quaternion(axis, deg_to_rad(str(turned.get(key, "0")).to_float()) if turned is Dictionary else 0.0)
		var tilt: Quaternion = about.call(Vector3.UP, "y") * about.call(Vector3.RIGHT, "x") * about.call(Vector3.BACK, "z")
		tilt = Quaternion(tilt.x, -tilt.y, -tilt.z, tilt.w)
		var limited := func(j: Dictionary, t: int) -> Dictionary:
			if limit_shape != "":
				var unity := sk.get_bone_global_rest(j.node).basis.orthonormalized().inverse() * (frame * _world_transform(objs, t)).basis.orthonormalized()
				var q := (unity.get_rotation_quaternion() * tilt).normalized()
				j["extras"] = {"limit": {"shape": limit_shape, "x": str(d.get("maxAngleX", "0")).to_float(), "z": str(d.get("maxAngleZ", "0")).to_float(), "rotation": [q.x, q.y, q.z, q.w]}}
			return j
		var e: Variant = d.get("endpointPosition", d.get("m_EndOffset"))
		var endpoint := Vector3(-str(e.get("x", "0")).to_float(), str(e.get("y", "0")).to_float(), str(e.get("z", "0")).to_float()) if e is Dictionary else Vector3.ZERO
		var touch := {"collide": _filter(d, "allowCollision", "collisionFilter"), "grab": _filter(d, "allowGrabbing", "grabFilter")}
		var deepest := _deepest(children, ignored, root_t)
		var physbone := func(j: Dictionary, depth: int, last: bool) -> Dictionary:
			if not legacy:
				var extras: Dictionary = j.get("extras", {})
				extras["physbone"] = _physbone(d, depth, deepest, endpoint != Vector3.ZERO, k)
				extras.physbone["endpoint"] = last
				j["extras"] = extras
			return j
		var groups := []
		for c: Variant in Prefabs._list(d.get("colliders", d.get("m_Colliders"))):
			if collider_index.has(_ref(c)):
				groups.append(collider_index[_ref(c)])
		var kids_of := func(t: int) -> Array:
			return children.get(t, []).filter(func(c: int) -> bool: return not ignored.has(c) and bone_of.call(c) >= 0)
		var starts: Array = kids_of.call(root_t)
		if starts.size() < 2 or str(d.get("multiChildType", "1" if legacy else "0")) == "1":
			starts = [root_t]
		var pending := starts.map(func(t: int) -> Array: return [t, [], 0 if t == root_t else 1])
		while not pending.is_empty():
			var item: Array = pending.pop_back()
			var bone: int = bone_of.call(item[0])
			var joints: Array = (item[1] as Array).duplicate()
			if bone >= 0 and not human.has(bone) and not ignored.has(item[0]):
				var j := joint.duplicate()
				j["node"] = bone
				joints.append(physbone.call(limited.call(j, item[0]), item[2], false))
			elif not joints.is_empty():
				if joints.size() >= 2:
					springs.append({"joints": joints, "colliders": groups, "extras": touch})
				continue
			var kids: Array = kids_of.call(item[0])
			if kids.is_empty():
				if not joints.is_empty() and endpoint != Vector3.ZERO:
					joints[-1] = physbone.call(joints[-1], item[2], true)
					var j := joint.duplicate()
					var offset := endpoint * _world_scale(objs, item[0])
					if legacy:
						offset = sk.get_bone_global_rest(bone).basis.inverse() * (held_by.basis * endpoint)
					j["node"] = _endpoint(sk, bone, offset)
					joints.append(j)
				if joints.size() >= 2:
					springs.append({"joints": joints, "colliders": groups, "extras": touch})
				continue
			for i in kids.size():
				pending.append([kids[i], joints if i == 0 else [], item[2] + 1])
		var driven := []
		for index in range(first_chain, springs.size()):
			driven.append_array(springs[index].joints.map(func(j: Dictionary) -> String: return sk.get_bone_name(j.node)))
		if component_when.has(id) and not driven.is_empty():
			switched.springs.append({"joints": driven, "when": component_when[id]})
		for index in range(first_chain, springs.size()):
			var joints: Array = springs[index].joints
			component.chains.append(joints.map(func(j: Dictionary) -> String: return sk.get_bone_name(j.node)))
			for index_in_chain in range(1, joints.size()):
				component.simulated_joints += int(sk.get_bone_rest(joints[index_in_chain].node).origin != Vector3.ZERO)
		if component.chains.is_empty() and component.reason == "":
			component.reason = "no segment after source exclusions, humanoid bones and endpoint are applied"
		elif not component.chains.is_empty():
			component.reason = ""
	report["spring coverage"] = JSON.stringify(coverage)
	report["spring components"] = "%d PhysBones, %d DynamicBones as %d spring chains, %d colliders (%d on no kept bone dropped, %d components no menu turns on dropped, %d that the menu switches); parameters mapped approximately, whose hands push and grab kept; limits kept without their curves; grab movement and posing dropped" % [physbones, dynamicbones, springs.size(), colliders.size(), dropped, idle, component_when.size() + switched.colliders.size()]
	if springs.is_empty():
		return {}
	var groups := []
	var out_springs := []
	for s: Dictionary in springs:
		var g := -1
		if not (s.colliders as Array).is_empty():
			g = groups.size()
			groups.append({"colliders": s.colliders})
		var spring := {"joints": s.joints, "extras": s.extras}
		if g >= 0:
			spring["colliderGroups"] = [g]
		out_springs.append(spring)
	return {"specVersion": "1.0", "springs": out_springs, "colliders": colliders, "colliderGroups": groups, "switched": switched}


## A PhysBone or DynamicBone collider in its transform's space (Unity's axes, X mirrored): `local` places it, `axis` is
## a capsule's length and a plane's normal there, `half` the distance from its middle to each end's centre (0 for a
## sphere). Empty for any other component.
static func _collider(d: Dictionary) -> Dictionary:
	var f := func(v: Variant, k: String) -> float: return str((v as Dictionary).get(k, "0")).to_float() if v is Dictionary else 0.0
	var mirrored := func(v: Variant) -> Vector3: return Vector3(-f.call(v, "x"), f.call(v, "y"), f.call(v, "z"))
	if d.has("shapeType") and d.has("insideBounds"):
		var q: Variant = d.get("rotation")
		var rot := Quaternion(f.call(q, "x"), -f.call(q, "y"), -f.call(q, "z"), f.call(q, "w")) if q is Dictionary else Quaternion.IDENTITY
		rot = rot.normalized() if rot.length() > 0.0 else Quaternion.IDENTITY
		var radius := str(d.get("radius", "0")).to_float()
		var height := str(d.get("height", "0")).to_float()
		var shape := str(d.shapeType)
		return {"local": Transform3D(Basis(rot), mirrored.call(d.get("position"))), "axis": Vector3.UP, "radius": radius, "half": maxf(height / 2.0 - radius, 0.0) if shape == "1" else 0.0, "kind": "plane" if shape == "2" else "round", "inside": shape != "2" and str(d.insideBounds) == "1"}
	if d.has("m_Bound") and d.has("m_Direction") and d.has("m_Center"):
		var axis: Vector3 = [Vector3.LEFT, Vector3.UP, Vector3.BACK][clampi(str(d.m_Direction).to_int(), 0, 2)]
		var inside := str(d.m_Bound) == "1"
		var local := Transform3D(Basis.IDENTITY, mirrored.call(d.m_Center))
		if not d.has("m_Radius"):
			return {"local": local, "axis": -axis if inside else axis, "radius": 0.0, "half": 0.0, "kind": "plane", "inside": false}
		var radius := str(d.m_Radius).to_float()
		return {"local": local, "axis": axis, "radius": radius, "half": maxf(str(d.get("m_Height", "0")).to_float() / 2.0 - radius, 0.0), "kind": "round", "inside": inside}
	return {}


## How many transforms down from `root` its PhysBone reaches: VRChat's maxBoneChainIndex, over every transform below it
## the PhysBone does not ignore, bones of the output skeleton or not.
static func _deepest(children: Dictionary, ignored: Dictionary, root: int) -> int:
	var deepest := 0
	var level: Array = [root]
	while true:
		level = level.reduce(func(next: Array, t: int) -> Array: return next + children.get(t, []).filter(func(c: int) -> bool: return not ignored.has(c)), [])
		if level.is_empty():
			return deepest
		deepest += 1
	return deepest


## A PhysBone's settings at the bone `depth` transforms below its root, each curve evaluated where VRChat's Calc
## functions evaluate it, as a joint's extras "physbone" carries them to the runtime; radii in the output's units.
static func _physbone(d: Dictionary, depth: int, deepest: int, endpoint: bool, k: float) -> Dictionary:
	var reach := deepest + (1 if endpoint else 0)
	var along := clampf(float(depth) / (reach - 1), 0.0, 1.0) if reach - 1 > 0 else 0.0
	var at := func(index: int) -> float: return clampf(float(index) / reach, 0.0, 1.0) if reach > 0 else 0.0
	var curved := func(field: String, t: float, fallback: float) -> float:
		var keys := Expressions._keys((d.get(field + "Curve", {}) as Dictionary).get("m_Curve") if d.get(field + "Curve") is Dictionary else [])
		return (ExpressionCurves.sample(keys, t, false) if not keys.is_empty() else 1.0) * str(d.get(field, fallback)).to_float()
	var radius := func(t: float) -> float: return curved.call("radius", t, 0.0) * k
	return {
		"version": "1.0" if str(d.get("version", "1")) == "0" else "1.1",
		"integration": "advanced" if str(d.get("integrationType", "0")) == "1" else "simplified",
		"pull": clampf(curved.call("pull", along, 0.2), 0.0, 1.0),
		"spring": clampf(curved.call("spring", along, 0.2), 0.0, 1.0),
		"stiffness": clampf(curved.call("stiffness", along, 0.2), 0.0, 1.0),
		"gravity": curved.call("gravity", along, 0.0),
		"gravityFalloff": clampf(curved.call("gravityFalloff", along, 0.0), 0.0, 1.0),
		"immobile": clampf(curved.call("immobile", along, 0.0), 0.0, 1.0),
		"immobileType": "world" if str(d.get("immobileType", "0")) == "1" else "allMotion",
		"maxStretch": maxf(curved.call("maxStretch", along, 0.0), 0.0),
		"maxSquish": clampf(curved.call("maxSquish", along, 0.0), 0.0, 1.0),
		"stretchMotion": clampf(curved.call("stretchMotion", along, 0.0), 0.0, 1.0),
		"radius": [radius.call(at.call(depth)), radius.call(at.call(depth + 1))],
		"depth": depth,
	}


## `springs` as SpringDefinition reads them, each collider keeping its extensions and each joint its extras, which the
## reader drops.
static func _read_springs(springs: Dictionary, nodes: Array) -> Dictionary:
	var chains := SpringDefinition.read({"nodes": nodes, "extensions": {"VRMC_springBone": springs}})
	for i in (chains.colliders as Array).size():
		if springs.colliders[i].has("extensions"):
			chains.colliders[i]["extensions"] = springs.colliders[i].extensions
	var extras := {}
	for spring: Dictionary in springs.springs:
		for joint: Dictionary in spring.joints:
			if joint.has("extras"):
				extras[joint.node] = joint.extras
	for chain: Dictionary in chains.springs:
		for joint: Dictionary in chain.joints:
			if extras.has(joint.node):
				joint["extras"] = extras[joint.node]
	return chains


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


## Whose hands a PhysBone lets touch it, as a spring's extras list them, from its allow field (False, True or Other)
## and, for Other, that field's filter.
static func _filter(d: Dictionary, allow: String, filter: String) -> Array:
	match str(d.get(allow, "1")):
		"0":
			return []
		"2":
			var f: Variant = d.get(filter, {})
			var by: Dictionary = f if f is Dictionary else {}
			return (["wearer"] if str(by.get("allowSelf", "1")) == "1" else []) + (["others"] if str(by.get("allowOthers", "1")) == "1" else [])
	return ["wearer", "others"]


## WEARER and OTHERS bits as a spring's extras list them.
static func _hands(bits: int) -> Array:
	return (["wearer"] if bits & SpringDefinition.WEARER else []) + (["others"] if bits & SpringDefinition.OTHERS else [])


## The kinds of component under the avatar this converter does not translate, with how many of each.
static func _untranslated(objs: Dictionary, top: int, descriptor: Dictionary) -> Dictionary:
	var kinds := {}
	var known := {"Transform": true, "SkinnedMeshRenderer": true, "MeshFilter": true, "MeshRenderer": true, "ParentConstraint": true, "PositionConstraint": true, "LookAtConstraint": true}
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


static func _matrix(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, 0, t.basis.y.x, t.basis.y.y, t.basis.y.z, 0, t.basis.z.x, t.basis.z.y, t.basis.z.z, 0, t.origin.x, t.origin.y, t.origin.z, 1]


static func _constraints(prefabs: Prefabs, objs: Dictionary, top: int, sk: Skeleton3D, rests: Array[Transform3D]) -> Dictionary:
	var out := []
	var on := {}
	for e: Array in _under(objs, top):
		var father := _ref(objs[e[0]].data.get("m_Father"))
		on[e[0]] = _active(objs, e[1]) and (e[0] == top or on.get(father, false))
		if not on[e[0]] or not objs.has(e[1]):
			continue
		for component: Variant in Prefabs._list(objs[e[1]].data.get("m_Component")):
			var o: Dictionary = objs.get(_ref(component.get("component")), {})
			if not o.get("type", "") in ["ParentConstraint", "PositionConstraint", "LookAtConstraint"]:
				continue
			var d: Dictionary = o.data
			if str(d.get("m_Enabled", "1")) != "1" or str(d.get("m_Active", "0")) != "1" or str(d.get("m_Weight", "1")).to_float() == 0.0:
				continue
			if o.type == "LookAtConstraint" and (str(d.get("m_UseUpObject", "0")) != "0" or str(d.get("m_Roll", "0")).to_float() != 0.0):
				return {"error": "LookAtConstraint up object or roll is unsupported"}
			var bone := _as_bone(objs, e[0], sk, rests)
			if bone < 0:
				return {"error": "constraint target has no output bone"}
			var c := {"kind": str(o.type).trim_suffix("Constraint"), "node": bone, "weight": str(d.get("m_Weight", "1")).to_float(), "sources": [], "translation": [], "rotation": []}
			for axis: String in ["X", "Y", "Z"]:
				c.translation.append(str(d.get("m_AffectTranslation" + axis, "1")) == "1")
				c.rotation.append(str(d.get("m_AffectRotation" + axis, "1")) == "1")
			c.rest = _matrix(_local({"m_LocalPosition": d.get("m_TranslationAtRest", {}), "m_LocalRotation": _constraint_rotation(d.get("m_RotationAtRest", {}))}))
			c.offset = _matrix(_local({"m_LocalPosition": d.get("m_TranslationOffset", {}), "m_LocalRotation": _constraint_rotation(d.get("m_RotationOffset", {}))}))
			var entries := Prefabs._list(d.get("m_Sources"))
			for i in entries.size():
				var entry: Dictionary = entries[i]
				var weight := str(entry.get("weight", "1")).to_float()
				if weight <= 0.0:
					continue
				var ref: Dictionary = entry.get("sourceTransform", {})
				var source := {"weight": weight}
				if ref.has("guid"):
					if not prefabs.assets.by_guid.has(str(ref.guid)):
						return {"error": "constraint source asset is missing"}
					var external := prefabs.flatten(str(ref.guid))
					if not external.has(_ref(ref)):
						return {"error": "constraint source transform is missing"}
					source.world = _matrix(_world_transform(external, _ref(ref)))
				else:
					var at := _as_bone(objs, _ref(ref), sk, rests)
					if at < 0:
						return {"error": "constraint source has no output bone"}
					source.node = at
				var positions := Prefabs._list(d.get("m_TranslationOffsets"))
				var rotations := Prefabs._list(d.get("m_RotationOffsets"))
				source.offset = _matrix(_local({"m_LocalPosition": positions[i] if i < positions.size() else {}, "m_LocalRotation": _constraint_rotation(rotations[i] if i < rotations.size() else {})}))
				c.sources.append(source)
			out.append(c)
	return {"constraints": out}


static func _constraint_rotation(v: Dictionary) -> Dictionary:
	var angles := Vector3(str(v.get("x", "0")).to_float(), str(v.get("y", "0")).to_float(), str(v.get("z", "0")).to_float()) * PI / 180.0
	var q := Quaternion.from_euler(angles)
	return {"x": q.x, "y": q.y, "z": q.z, "w": q.w}
