extends "res://../tests/support/suite.gd"

## Imports each Unity avatar package of a private corpus that never enters this repository and checks each wears
## within the limits: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_private_avatars.gd
## The corpus is the folder CAIRNFOLD_PRIVATE_AVATARS names, or ~/.local/share/cairnfold-avatars/vrchat, holding
## .unitypackage files and avatars.json, each package's file name to the name of the avatar in it to convert ("" for
## the only one). Without it the test says so and checks nothing.

const UnityAvatar = preload("res://../scripts/unity_avatar.gd")
const Materials = preload("res://../scripts/unity/materials.gd")


func _run() -> void:
	var dir := OS.get_environment("CAIRNFOLD_PRIVATE_AVATARS")
	if dir == "":
		dir = OS.get_environment("HOME").path_join(".local/share/cairnfold-avatars/vrchat")
	var listed: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("avatars.json"))) if FileAccess.file_exists(dir.path_join("avatars.json")) else null
	if not listed is Dictionary:
		print("SKIPPED: no private avatar corpus at %s" % dir)
		finish()
		return
	var n := 0
	for file: String in listed:
		n += 1
		_wears("corpus avatar %d" % n, dir.path_join(file), str(listed[file]))
	check(n > 0, "the corpus lists packages")
	finish()


## The package imports as an avatar model within the limits, writes, reads back and poses with its eyes on its head.
func _wears(label: String, package: String, avatar: String) -> void:
	var started := Time.get_ticks_msec()
	var dir := UnityAvatar.unpacked(package)
	check(dir != "", "%s unpacks" % label)
	# A widest-atlas conversion of a heavy package passes the suite's 4 GB data limit. The corpus holds no shader
	# packages, and this checks fit, not looks.
	var none := ProjectSettings.globalize_path("user://no-packages")
	DirAccess.make_dir_recursive_absolute(none)
	var model := UnityAvatar.avatar_scene(dir, [], avatar, none, Materials.LAYER) if dir != "" else null
	check(model != null, "%s imports" % label)
	if model == null:
		return
	var carried := 0
	for chain: Dictionary in (model.get_meta("springs") as Dictionary).springs:
		carried += (chain.joints as Array).size()
	print("%s: %d ms, %d spring joints, %s" % [label, Time.get_ticks_msec() - started, carried, model.get_meta("report")])
	var running := _running(model)
	var scene := Avatar.read(UnityAvatar.write(model, ProjectSettings.globalize_path("user://corpus.vrm")))
	check(scene != null, "%s's VRM, the file a player wears, reads into the avatar model within the limits" % label)
	if scene == null:
		return
	var held := scene.instantiate()
	var human: Dictionary = held.get_meta("humanoid")
	var joints := 0
	var off := []
	for chain: Dictionary in (held.get_meta("springs") as Dictionary).springs:
		joints += (chain.joints as Array).size()
		var bones: Array = chain.joints.map(func(j: Dictionary) -> String: return (human["spring_%d" % j.node] as NodePath).get_concatenated_subnames())
		if not running.has(bones):
			off.append(bones)
	check(joints <= Avatar.MAX_SPRING_JOINTS, "%s simulates %d spring joints, within the limit" % [label, joints])
	check(off.is_empty(), "%s simulates no spring chain its menu switches off by default: %d of them" % [label, off.size()])
	held.free()
	var a := Avatar.open(scene, Color.WHITE, label)
	root.add_child(a)
	var eyes := Transform3D(Basis(), Vector3(0, 1.6, 0))
	a.pose(eyes, eyes * Avatar.AT_SIDES[0], eyes * Avatar.AT_SIDES[1])
	var gap := a.bone("head").origin.distance_to(eyes.origin)
	check(gap < 0.5, "%s: the head bone is %.2f m from the eyes" % [label, gap])
	a.free()


## The bones of each spring chain of the converter's `model` that its menu's default state leaves running, as the worn
## file's reader decides that over bone indices (Avatar._switched_off).
func _running(model: Node3D) -> Dictionary:
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var expressions: Dictionary = model.get_meta("expressions", {}).duplicate(true)
	for s: Dictionary in expressions.get("springs", []):
		s.joints = s.joints.map(func(n: String) -> int: return sk.find_bone(n))
	var probe := Node3D.new()
	probe.set_meta("expressions", expressions)
	probe.set_meta("springs", (model.get_meta("springs") as Dictionary).duplicate(true))
	Avatar._switched_off(probe)
	var out := {}
	for chain: Dictionary in probe.get_meta("springs").springs:
		out[chain.joints.map(func(j: Dictionary) -> String: return sk.get_bone_name(j.node))] = true
	probe.free()
	return out
