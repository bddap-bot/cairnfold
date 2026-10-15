class_name PlayLog
extends RefCounted

const DIRECTORY := "user://sessions"
const MAX_BYTES := 1048576
const MAX_FILES := 16
var directory: String
var session_id: String
var metadata: Dictionary
var _file: FileAccess
var _part := 0
var _ended := false


static func enabled(args: Dictionary) -> bool:
	return args.has("record-sessions") or FileAccess.file_exists("user://record-sessions")


static func open_enabled(args: Dictionary) -> PlayLog:
	if args.has("forget-sessions"):
		DirAccess.remove_absolute("user://record-sessions")
		return null
	if not enabled(args):
		return null
	var folder := DIRECTORY
	if FileAccess.file_exists("user://record-sessions"):
		var saved := FileAccess.get_file_as_string("user://record-sessions").strip_edges()
		if not saved.is_empty():
			folder = saved
	if args.has("record-sessions"):
		folder = str(args.get("session-directory", folder))
		var consent := FileAccess.open("user://record-sessions", FileAccess.WRITE)
		if consent != null:
			consent.store_string(folder)
	return PlayLog.new(folder)


func _init(folder := DIRECTORY) -> void:
	directory = folder
	DirAccess.make_dir_recursive_absolute(directory)
	var started := Time.get_unix_time_from_system()
	session_id = "%d-%d-%d" % [started * 1000, OS.get_process_id(), Time.get_ticks_usec()]
	var revision := "development"
	if ResourceLoader.exists("res://revision.tres"):
		revision = str(load("res://revision.tres").get_meta("revision", revision))
	metadata = {"schema": 1, "session": session_id, "started": started, "revision": revision,
		"os": OS.get_name(), "device": OS.get_model_name()}
	_open()


func _open() -> void:
	_file = null
	var files := Array(DirAccess.get_files_at(directory)).filter(func(f): return f.ends_with(".jsonl"))
	files.sort()
	while files.size() >= MAX_FILES:
		DirAccess.remove_absolute(directory.path_join(files.pop_front()))
	_file = FileAccess.open(directory.path_join("%s-%04d.jsonl" % [session_id, _part]), FileAccess.WRITE)
	_part += 1
	if _file != null:
		_file.store_line(JSON.stringify(metadata.merged({"event": "start", "part": _part})))
		_file.flush()


func sample(row: Dictionary) -> void:
	if _file == null or _ended:
		return
	var line := JSON.stringify(row.merged({"event": "frame", "session": session_id}))
	if _file.get_position() + line.length() + 1024 > MAX_BYTES:
		_open()
	if _file == null:
		return
	_file.store_line(line)
	_file.flush()
	# Rename keeps readers from seeing half of the current sample.
	var latest := FileAccess.open(directory.path_join("latest.new"), FileAccess.WRITE)
	if latest != null:
		latest.store_line(JSON.stringify(metadata.merged(row)))
		latest.close()
		DirAccess.rename_absolute(directory.path_join("latest.new"), directory.path_join("latest.json"))


func finish() -> void:
	if _ended:
		return
	_ended = true
	if _file != null:
		_file.store_line(JSON.stringify({"event": "end", "session": session_id, "ended": Time.get_unix_time_from_system()}))
		_file.close()
