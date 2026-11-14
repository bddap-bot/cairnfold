extends "res://../tests/support/booted.gd"


func _run() -> void:
	await frames(3)
	var session := main.session
	var file := Avatar.read(FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm")))
	session._looks[7] = [1, Color.GREEN]
	session._wearing[7] = "file"
	session._scenes["file"] = file
	session._dress(7, file, "file", true)
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
	session.refuse("file")
	check((session.avatars[7] as Avatar).stand_in, "a file its frames price past the headroom stands as the built-in body")
	session.refuse("other")
	session.reoffer()
	check(not (session.avatars[7] as Avatar).stand_in and (session.avatars[7] as Avatar).eyes.origin.is_equal_approx(eyes.origin), "offered again where the headroom lets it in, it is drawn whole where it stood")
	finish()
