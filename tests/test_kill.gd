extends "res://../tests/support/suite.gd"

## A process killed while it writes leaves the garden it last finished saving and session chunks that each
## open with their start record; a quit writes the garden and the end record before anything else:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_kill.gd
## Given `-- writer DIR` it is the process that gets killed, saving and logging into DIR until it is.

const ROUNDS := 6
const FILL := 1 << 22

var dir := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "writer":
		_write_until_killed(args[1])
		return
	_run.call_deferred()


static func _garden(n: int) -> PackedByteArray:
	var fill := PackedByteArray()
	fill.resize(FILL)
	fill.fill(n % 256)
	return var_to_bytes({"n": n, "fill": fill})


## The number of the garden saved at `path`, or -1 if it is not one whole garden.
static func _read(path: String) -> int:
	var snap: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
	if not (snap is Dictionary and snap.get("fill") is PackedByteArray):
		return -1
	var fill: PackedByteArray = snap.fill
	var n: int = snap.n
	return n if fill.size() == FILL and fill[0] == n % 256 and fill[-1] == n % 256 else -1


func _write_until_killed(into: String) -> void:
	var log := PlayLog.new(into.path_join("sessions"))
	var gardens := [_garden(1), _garden(2)]
	var n := 1
	while true:
		World._write(into.path_join("garden.save"), gardens[n % 2])
		log._write({"unix": float(n)})
		if n % 3 == 0:
			log._open()
		n += 1


func _run() -> void:
	dir = OS.get_user_data_dir().path_join("nestcombe-kill-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("garden.save")
	World._write(path, _garden(0))
	var cmdline := OS.get_cmdline_args()
	var script: String = cmdline[cmdline.find("--script") + 1]
	for round in ROUNDS:
		var before := _read(path)
		var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", script, "--", "writer", dir])
		var until := Time.get_ticks_msec() + 60000
		while _read(path) == before and Time.get_ticks_msec() < until:
			OS.delay_msec(5)
		OS.delay_msec(randi_range(10, 150))
		OS.kill(pid)
		while OS.is_process_running(pid):
			OS.delay_msec(1)
		check(_read(path) >= 0, "round %d: a kill mid-write leaves a whole garden" % round)
	_check_chunks()
	await _quit_writes_first()
	_remove(dir)
	finish()


func _check_chunks() -> void:
	var sessions := dir.path_join("sessions")
	var chunks := Array(DirAccess.get_files_at(sessions)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))
	check(chunks.size() > 0, "the killed writer left session chunks")
	for name: String in chunks:
		var text := FileAccess.get_file_as_string(sessions.path_join(name))
		var first: Variant = JSON.parse_string(text.get_slice("\n", 0))
		check(first is Dictionary and first.get("event") == "start", "%s opens with its start record" % name)


func _quit_writes_first() -> void:
	boot_main()
	await process_frame
	var world: World = main.world
	var sessions := dir.path_join("quit")
	main.metrics.play_log = PlayLog.new(sessions)
	var path := dir.path_join("quit.save")
	world.load_from(path)
	world.restore({"seq": 0, "cmds": [{"op": "plant", "kind": "tree", "seed": 1, "at": Terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}]})
	root.get_node("AudioLifetime")._quitting = true
	main.finish()
	root.get_node("AudioLifetime")._quitting = false
	var kept: Variant = bytes_to_var(FileAccess.get_file_as_bytes(path))
	check(kept is Dictionary and kept.get("cmds") is Array and kept.cmds.size() == 1, "a quit writes the garden changed in its own frame")
	var chunk: String = Array(DirAccess.get_files_at(sessions)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))[0]
	var lines := FileAccess.get_file_as_string(sessions.path_join(chunk)).strip_edges().split("\n")
	var last: Variant = JSON.parse_string(lines[-1])
	check(last is Dictionary and last.get("event") == "end", "and ends the session log")
	world.save_path = ""
	main.queue_free()
	await process_frame


func _remove(at: String) -> void:
	for d in DirAccess.get_directories_at(at):
		_remove(at.path_join(d))
	for f in DirAccess.get_files_at(at):
		DirAccess.remove_absolute(at.path_join(f))
	DirAccess.remove_absolute(at)
