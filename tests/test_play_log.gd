extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	check(not PlayLog.enabled({}), "default does not opt in")
	check(PlayLog.open_enabled({}) == null, "default creates no recorder")
	check(PlayLog.enabled({"record-sessions": true}), "explicit launch opts in")
	FileAccess.open(Main.player_path(PlayLog.SWITCH), FileAccess.WRITE).close()
	var switched := PlayLog.open_enabled({})
	check(switched != null and switched.directory == Main.player_path("sessions"), "the switch file in the player folder opts in, recording beside it")
	switched.finish()
	for name in DirAccess.get_files_at(switched.directory):
		DirAccess.remove_absolute(switched.directory.path_join(name))
	check(PlayLog.open_enabled({"forget-sessions": true}) == null and not PlayLog.enabled({}), "forgetting removes the switch")
	var folder := "user://test-play-%d" % OS.get_process_id()
	check(not DirAccess.dir_exists_absolute(folder), "default constructs no logger and writes nothing")
	var logger := PlayLog.new(folder)
	for i in PlayLog.MAX_FILES + 4:
		logger.sample({"unix": float(i), "head_position": [1, 2, 3], "view_direction": [0, 0, -1]})
		logger._join()
		logger._open()
	logger.sample({"unix": 21.0, "padding": "x".repeat(PlayLog.MAX_BYTES * 3 / 5)})
	logger._join()
	logger.sample({"unix": 21.0, "padding": "x".repeat(PlayLog.MAX_BYTES * 3 / 5)})
	logger.finish()
	var files := DirAccess.get_files_at(folder)
	check(files.size() == PlayLog.MAX_FILES + 1, "the ring retains its chunks and latest")
	check(JSON.parse_string(FileAccess.get_file_as_string(folder + "/latest.json")).unix == 21.0, "latest is a whole current sample")
	for name in files:
		var f := FileAccess.open(folder.path_join(name), FileAccess.READ)
		check(f.get_length() <= PlayLog.MAX_BYTES, "chunk is bounded")
		f.close()
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	finish()
