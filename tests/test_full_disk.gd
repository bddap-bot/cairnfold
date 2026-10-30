extends "res://../tests/support/suite.gd"

## Headless check that a save the disk refuses partway leaves the last garden whole: the test runs itself again with
## files capped at LIMIT_KB, as a full disk would cap them, then keeps a small garden and grows it past the cap:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_full_disk.gd

const LIMIT_KB := 60
const CAPPED := "CAIRNFOLD_FILES_CAPPED"


func _initialize() -> void:
	if OS.get_environment(CAPPED) == "":
		var out := []
		var run := "trap '' XFSZ; ulimit -f %d; %s=1 exec '%s' --headless --fixed-fps 60 --path '%s' --script '%s'" % [LIMIT_KB, CAPPED,
			OS.get_executable_path(), ProjectSettings.globalize_path("res://"), ProjectSettings.globalize_path(get_script().resource_path)]
		var code := OS.execute("bash", ["-c", run], out, true)
		printraw(out[0])
		Main.quit(self, code)
		return
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	main.world.limit = INF
	var path := OS.get_user_data_dir().path_join("cairnfold-full-%d.save" % OS.get_process_id())
	main.world.load_from(path)
	await play([{"op": "wall", "points": [[-6, -4], [6, -4]], "seconds": 0.3}, {"op": "tree", "x": 4, "z": 4}])
	await process_frame
	main.world.flush()
	var kept := FileAccess.get_file_as_bytes(path)
	var picture := var_to_str(main.world.digest())
	await play([{"op": "sculpt", "x": 10, "z": 10, "lift": 1.5, "seconds": 0.3}])
	await process_frame
	main.world.flush()
	check(var_to_bytes(main.world.snapshot()).size() > LIMIT_KB * 1024, "the grown garden outgrows the cap")
	check(FileAccess.get_file_as_bytes(path) == kept and not FileAccess.file_exists(path + ".new"), "a save the disk refused leaves the last garden, and nothing beside it")
	main.world.restore({"seq": 0, "cmds": []})
	main.world.load_from(path)
	check(var_to_str(main.world.digest()) == picture, "and the last garden loads")
	for f in [path, path + ".bad"]:
		DirAccess.remove_absolute(f)
	finish()
