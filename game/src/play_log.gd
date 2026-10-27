class_name PlayLog
extends RefCounted

## Recording is on only where this file is in the player folder (Main.player_path): written by --record-sessions or
## by a dev tool on a device of ours, never by the game unasked. It may name another folder to record into.
## Beside each second's metrics row it keeps every frame's input (Replay) and every message the network brought, so
## the ring holds hours of all three.
const SWITCH := "record-sessions"
const MAX_BYTES := 4194304
const MAX_FILES := 64
var directory: String
var session_id: String
var metadata: Dictionary
var _file: FileAccess
var _part := 0
var _ended := false
var _task := -1
var _skipped := 0
var _write_us := 0
## Frames recorded since the last write, and how many the session recorded before them.
var _input := PackedByteArray()
var _frames := 0
## Messages heard since the last write, each [frame, from, whose, call, args], and how many the session heard before them.
var _heard := []
var _messages := 0


static func enabled(args: Dictionary) -> bool:
	return args.has("record-sessions") or FileAccess.file_exists(Main.player_path(SWITCH))


static func open_enabled(args: Dictionary) -> PlayLog:
	if args.has("forget-sessions"):
		DirAccess.remove_absolute(Main.player_path(SWITCH))
		return null
	if not enabled(args):
		return null
	var folder := Main.player_path("sessions")
	if FileAccess.file_exists(Main.player_path(SWITCH)):
		var saved := FileAccess.get_file_as_string(Main.player_path(SWITCH)).strip_edges()
		if not saved.is_empty():
			folder = saved
	if args.has("record-sessions"):
		folder = str(args.get("session-directory", folder))
		var consent := FileAccess.open(Main.player_path(SWITCH), FileAccess.WRITE)
		if consent != null:
			consent.store_string(folder)
	return PlayLog.new(folder)


func _init(folder: String) -> void:
	directory = folder
	DirAccess.make_dir_recursive_absolute(directory)
	var started := Time.get_unix_time_from_system()
	session_id = "%d-%d-%d" % [started * 1000, OS.get_process_id(), Time.get_ticks_usec()]
	metadata = {"schema": 2, "session": session_id, "started": started, "revision": Main.revision(),
		"os": OS.get_name(), "device": OS.get_model_name(), "input": Replay.layout()}
	_open()


## What the session replays from: the seeds it drew from and the garden it starts in, as World.snapshot gives it.
## The garden is serialized here, so the edits that follow cannot change it under the writer.
func begin(seeds: Dictionary, garden: Dictionary) -> void:
	_join()
	_task = WorkerThreadPool.add_task(_write_replay.bind(seeds, var_to_bytes(garden)))


func _write_replay(seeds: Dictionary, save: PackedByteArray) -> void:
	_store({"event": "replay", "session": session_id, "seeds": seeds, "save_bytes": save.size(),
		"save": Marshalls.raw_to_base64(save.compress(FileAccess.COMPRESSION_DEFLATE))})


## Keeps this frame's input (Replay.frame) for the next write.
func record(frame: PackedByteArray) -> void:
	_input.append_array(frame)


## Keeps a message for the next write, stamped with the frame it came in before (the count of frames recorded): a
## networked `call` with `args` as it arrived from peer `from`, or 0 for what this machine did itself (a command it
## ordered as host, a join), about player `whose` (the one who made a build command, the one who came or went).
func heard(from: int, whose: int, call: String, args: Array) -> void:
	if not _ended:
		_heard.append([_frames + _input.size() / Replay.FRAME_BYTES, from, whose, call, args.duplicate(true)])


func _open() -> void:
	_file = null
	var files := Array(DirAccess.get_files_at(directory)).filter(func(f): return f.ends_with(".jsonl"))
	files.sort()
	while files.size() >= MAX_FILES:
		DirAccess.remove_absolute(directory.path_join(files.pop_front()))
	_part += 1
	# Renamed into place holding its start record, so no reader meets a chunk without one.
	var fresh := directory.path_join("chunk.new")
	var start := FileAccess.open(fresh, FileAccess.WRITE)
	if start == null:
		return
	start.store_line(JSON.stringify(metadata.merged({"event": "start", "part": _part})))
	start.close()
	var chunk := directory.path_join("%s-%04d.jsonl" % [session_id, _part - 1])
	if DirAccess.rename_absolute(fresh, chunk) != OK:
		return
	_file = FileAccess.open(chunk, FileAccess.READ_WRITE)
	if _file != null:
		_file.seek_end()


func sample(row: Dictionary) -> void:
	if _task != -1 and not WorkerThreadPool.is_task_completed(_task):
		_skipped += 1
		return
	_join()
	var snapshot := row.duplicate(true)
	snapshot.skipped_log_samples = _skipped
	snapshot.writer_us = _write_us
	_skipped = 0
	_task = WorkerThreadPool.add_task(_write.bind(snapshot, _take_input(), _take_heard()))


## The frames kept since the last write, as their "input" event; {} for none.
func _take_input() -> Dictionary:
	if _input.is_empty():
		return {}
	var block := {"first": _frames, "frames": _input.size() / Replay.FRAME_BYTES, "raw": _input}
	_frames += block.frames
	_input = PackedByteArray()
	return block


## The messages heard since the last write, as their "net" event before encoding; {} for none.
func _take_heard() -> Dictionary:
	if _heard.is_empty():
		return {}
	var block := {"first": _messages, "messages": _heard}
	_messages += _heard.size()
	_heard = []
	return block


func _join() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _write(row: Dictionary, input: Dictionary, net: Dictionary) -> void:
	var begin := Time.get_ticks_usec()
	if _file == null or _ended:
		return
	_write_input(input)
	_write_net(net)
	_store(row.merged({"event": "frame", "session": session_id}))
	_flush()
	_write_us = Time.get_ticks_usec() - begin


func _write_input(input: Dictionary) -> void:
	if input.is_empty():
		return
	var raw: PackedByteArray = input.raw
	_store({"event": "input", "session": session_id, "first": input.first, "frames": input.frames, "bytes": raw.size(),
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))})


## Each message's arguments in Godot's own binary encoding, the bytes the network carries, which `bytes_to_var` reads.
func _write_net(net: Dictionary) -> void:
	if net.is_empty():
		return
	var raw := var_to_bytes(net.messages.map(func(m: Array) -> Array: return _without_files(m[4])))
	var index: Array = net.messages.map(func(m: Array) -> Array: return m.slice(0, 4))
	_store({"event": "net", "session": session_id, "first": net.first, "messages": index, "bytes": raw.size(),
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))})


## A file a message carries, the only bytes any does (an avatar), is kept as its SHA-256 and length, never the file.
static func _without_files(args: Array) -> Array:
	return args.map(func(a: Variant) -> Variant:
		if a is PackedByteArray and not a.is_empty():
			var h := HashingContext.new()
			h.start(HashingContext.HASH_SHA256)
			h.update(a)
			return {"sha256": h.finish().hex_encode(), "bytes": a.size()}
		return a)


## Appends `record` as a line of the current chunk, opening the next first when it would outgrow MAX_BYTES.
func _store(record: Dictionary) -> void:
	if _file == null:
		return
	var line := JSON.stringify(record)
	if _file.get_position() + line.length() + 1024 > MAX_BYTES:
		_open()
	if _file == null:
		return
	_file.store_line(line)


## Once a write: each flush of a Quest's shared storage costs the writer milliseconds.
func _flush() -> void:
	if _file != null:
		_file.flush()


func finish() -> void:
	_join()
	if _ended:
		return
	_write_input(_take_input())
	_write_net(_take_heard())
	_ended = true
	if _file != null:
		_file.store_line(JSON.stringify({"event": "end", "session": session_id, "ended": Time.get_unix_time_from_system()}))
		_file.close()
		_file = null
