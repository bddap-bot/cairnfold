extends "res://../tests/support/suite.gd"

## Another player in their own file stands as a built-in body while the quality step draws no one's own file, and in
## their file again once it does, posed where they were: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_people_drawn.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await frames(3)
	var session := main.session
	var file := Avatar.read(FileAccess.get_file_as_bytes("res://../tests/avatars/crimsom-1.0.vrm"))
	session._looks[7] = [1, Color.GREEN]
	session._wearing[7] = "file"
	session._scenes["file"] = file
	session._dress(7, file, "file")
	var eyes := Transform3D(Basis.IDENTITY, Vector3(1, 1.5, 2))
	(session.avatars[7] as Avatar).pose(eyes, eyes.translated(Vector3(-0.3, -0.5, -0.2)), eyes.translated(Vector3(0.3, -0.5, -0.2)))
	await frames(2)
	check((session.avatars[7] as Avatar).scene == file, "a player in their own file stands in it at a step that draws files")
	main.quality.pin = Quality.ladder.size() - 1
	await frames(2)
	var a: Avatar = session.avatars[7]
	check(a.scene == Avatar.built_in(1) and a.tint == file.get_meta("colour") and a.source == "file", "at a step that draws none they stand as their built-in body in the file's colour")
	check(a.eyes.origin.is_equal_approx(eyes.origin), "posed where they stood")
	main.quality.pin = Quality.ladder.size() - 2
	await frames(2)
	check((session.avatars[7] as Avatar).scene == file, "and in their file again once the step draws files")
	finish()
