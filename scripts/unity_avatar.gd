extends SceneTree

## Converts the humanoid model of a Unity source package (an Assets folder, its .meta files beside the assets) into a
## VRM 1.0 file Avatar.read opens: run from game/ as
## godot4 --headless --path . --script ../scripts/unity_avatar.gd -- PACKAGE_DIR OUT.vrm
## The model is the package's one FBX imported as a humanoid (its .meta's animationType 3). Godot's FBX importer reads
## its skeleton, skins and blend shapes; the bone map is the Unity Avatar definition in the .meta, its humanDescription.
## Textures, Unity materials, prefabs and animations are not translated; the converter prints what it dropped.

## Unity's HumanBodyBones names for the thumb, by the VRM 1.0 bone each one is.
const THUMB := {"ThumbProximal": "ThumbMetacarpal", "ThumbIntermediate": "ThumbProximal"}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: unity_avatar.gd PACKAGE_DIR OUT.vrm")
		quit(2)
		return
	var root := humanoid_scene(args[0])
	if root == null:
		quit(1)
		return
	Vrm.write(root, args[1])
	print("unity_avatar: wrote %s, %d humanoid bones" % [args[1], (root.get_meta("humanoid") as Dictionary).size()])
	root.free()
	quit()


## The package's humanoid as a scene Vrm.write exports: skeleton bones the Avatar definition maps renamed to VRM 1.0
## names, the map kept as metadata "humanoid" (VRM bone to the Unity bone it was). Null, with the reason printed, if the
## package holds no single humanoid FBX, or its map names a bone the model lacks, two VRM bones for one bone, or a
## bone VRM does not have, or another node already bears a mapped VRM name.
static func humanoid_scene(dir: String) -> Node3D:
	var models := _humanoid_models(dir)
	if models.size() != 1:
		printerr("unity_avatar: %s holds %d humanoid FBX models, not one" % [dir, models.size()])
		return null
	var fbx: String = models[0]
	var avatar := avatar_definition(FileAccess.get_file_as_string(fbx + ".meta"))
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.create_animations = false
	if doc.append_from_file(fbx, state) != OK:
		printerr("unity_avatar: Godot cannot read %s" % fbx)
		return null
	var root := doc.generate_scene(state) as Node3D
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = skeletons[0] if skeletons.size() == 1 else null
	var refuse := func(why: String) -> Node3D:
		printerr("unity_avatar: %s: %s" % [fbx, why])
		root.free()
		return null
	if sk == null:
		return refuse.call("%d skeletons, not one" % skeletons.size())
	var named := {}
	var human := {}
	for unity_bone: String in avatar.human:
		var vrm := vrm_bone(avatar.human[unity_bone])
		var b := _bone_of(sk, unity_bone, avatar.parents)
		if b < 0:
			return refuse.call("the Avatar definition's %s (%s) is no bone of it" % [unity_bone, avatar.human[unity_bone]])
		if not vrm in Vrm.BONES:
			return refuse.call("the Avatar definition's %s is no VRM bone" % avatar.human[unity_bone])
		if named.has(b):
			return refuse.call("the Avatar definition maps %s twice" % unity_bone)
		named[b] = vrm
		human[vrm] = unity_bone
	for i in sk.get_bone_count():
		if not named.has(i) and String(sk.get_bone_name(i)) in human:
			return refuse.call("its unmapped bone %s bears a mapped VRM name" % sk.get_bone_name(i))
	for n in root.find_children("*", "", true, false):
		if not n is Skeleton3D and String(n.name) in human:
			return refuse.call("its node %s bears a mapped VRM name" % n.name)
	# Two passes, so a bone may take the name another mapped bone is about to give up.
	for i: int in named:
		sk.set_bone_name(i, "unity_avatar %d" % i)
	for i: int in named:
		sk.set_bone_name(i, named[i])
	root.set_meta("humanoid", human)
	if human.has("leftEye") and human.has("rightEye"):
		var head := sk.get_bone_global_rest(sk.find_bone("head"))
		var middle := (sk.get_bone_global_rest(sk.find_bone("leftEye")).origin + sk.get_bone_global_rest(sk.find_bone("rightEye")).origin) / 2.0
		root.set_meta("eyes", head.affine_inverse() * middle)
	print("unity_avatar: %s: %d bones, %d mapped; not translated: textures, Unity materials, prefabs, animations" % [fbx.get_file(), sk.get_bone_count(), human.size()])
	return root


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


static func _humanoid_models(dir: String) -> Array[String]:
	var found: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if f.get_extension().to_lower() == "fbx" and FileAccess.file_exists(path + ".meta"):
			var meta := FileAccess.get_file_as_string(path + ".meta")
			if meta.contains("\n  animationType: 3") and not (avatar_definition(meta).human as Dictionary).is_empty():
				found.append(path)
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_humanoid_models(dir.path_join(sub)))
	return found


## The skeleton bone a Unity transform name is. Unity gives a transform named like another in the model a " 1", " 2"...
## suffix (Seed-san's head bone is "head 1" beside its "head" mesh), which Godot's importer does not, so a name the
## skeleton lacks is matched without its suffix, under the bone its Unity parent is.
static func _bone_of(sk: Skeleton3D, unity: String, parents: Dictionary) -> int:
	var b := sk.find_bone(unity)
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
