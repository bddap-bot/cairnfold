extends "res://../tests/support/suite.gd"

## A demo script's captures are what they are named: a view of something absent fails the script before it captures
## again, and a digest makes its folder as a capture does. A headless capture never draws, so scripts/test.sh runs this on the
## desktop renderer.


func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	var dir := OS.get_user_data_dir().path_join("driver-captures/fresh")
	root.add_child(main)
	await process_frame
	main.args["capture-dir"] = dir
	var driver := Driver.new(main, [
		{"op": "digest", "name": "first"},
		{"op": "view", "eye": [0, 1.6, 4], "at": [0, 1, 0]},
		{"op": "capture", "name": "seen"},
		{"op": "view", "subject": "no-such-group", "eye": [0, 1, 1], "at": [0, 0, 0]},
		{"op": "capture", "name": "missing"},
	])
	main.add_child(driver)
	await driver.finished
	check(FileAccess.file_exists(dir.path_join("first.json")), "a digest before any capture writes into the folder it makes")
	check(FileAccess.file_exists(dir.path_join("seen.png")), "a view of a place captures")
	check(driver.failed, "a view of an absent subject fails the script")
	check(not FileAccess.file_exists(dir.path_join("missing.png")), "and nothing after it is captured under its name")
	driver.queue_free()
	finish()
