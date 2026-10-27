extends "res://../tests/support/suite.gd"

## Converts each Unity avatar package of a private corpus that never enters this repository and checks each wears
## within the limits: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_private_avatars.gd
## The corpus is the folder CAIRNFOLD_PRIVATE_AVATARS names, or ~/.local/share/cairnfold-avatars/vrchat, holding
## .unitypackage files and avatars.json, each package's file name to the name of the avatar in it to convert ("" for
## the only one). Without it the test says so and checks nothing.

const UnityAvatar = preload("res://../scripts/unity_avatar.gd")


func _initialize() -> void:
	_run.call_deferred()


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


## The package converts, writes, reads back within Avatar.read's limits and poses with its eyes on its head.
func _wears(label: String, package: String, avatar: String) -> void:
	var started := Time.get_ticks_msec()
	var dir := UnityAvatar.unpacked(package)
	check(dir != "", "%s unpacks" % label)
	var model := UnityAvatar.avatar_scene(dir, avatar) if dir != "" else null
	check(model != null, "%s converts" % label)
	if model == null:
		return
	var joints := 0
	for chain: Dictionary in (model.get_meta("springs") as Dictionary).get("springs", []):
		joints += (chain.joints as Array).size()
	check(joints <= Avatar.MAX_SPRING_JOINTS, "%s keeps %d spring joints, within the limit" % [label, joints])
	var path := ProjectSettings.globalize_path("user://corpus.vrm")
	Vrm.write(model, path)
	print("%s: %d ms, %s" % [label, Time.get_ticks_msec() - started, model.get_meta("report")])
	model.free()
	var scene := Avatar.read(FileAccess.get_file_as_bytes(path))
	check(scene != null, "%s reads within the limits" % label)
	if scene == null:
		return
	var a := Avatar.open(scene, Color.WHITE, label)
	root.add_child(a)
	var eyes := Transform3D(Basis(), Vector3(0, 1.6, 0))
	a.pose(eyes, eyes * Avatar.AT_SIDES[0], eyes * Avatar.AT_SIDES[1])
	var gap := a.bone("head").origin.distance_to(eyes.origin)
	check(gap < 0.5, "%s: the head bone is %.2f m from the eyes" % [label, gap])
	a.queue_free()
