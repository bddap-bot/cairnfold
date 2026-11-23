extends "res://../tests/support/suite.gd"

## Replays --replay in a fresh process, writing to --out what tests/test_replay.gd compares with the recording.

const Suite := preload("res://../tests/support/suite.gd")


class Probe:
	extends Node
	var main: Main
	var deltas: Array[float] = []
	var heads: Array[Transform3D] = []
	var ids: Array[int] = []
	## Garden seq -> the frame its command came into the garden.
	var applied_at := {}
	## The ops of this machine's own commands that waited for a refill ahead of them.
	var waited := []

	func _process(delta: float) -> void:
		var w := main.world
		if not w.applied.is_connected(_applied):
			w.applied.connect(_applied)
		deltas.append(delta)
		heads.append(main.rig.head.global_transform)
		ids.append(main.multiplayer.get_unique_id())
		if w._ahead_task >= 0 and w._queue[0].by == w.me() and not w._queue[0].cmd in waited:
			waited.append(w._queue[0].cmd)

	func _applied(cmd: Dictionary) -> void:
		if cmd.get("seq") == main.world.seq and not applied_at.has(cmd.seq):
			applied_at[cmd.seq] = heads.size()


## Runs `act` once, right after World's turn of the next frame in which World keeps the garden, as a tool would.
class AfterKeep:
	extends Node
	var world: World
	var act := Callable()

	func _process(_delta: float) -> void:
		if act.is_valid() and world._keep_wait == World.KEEP_EVERY:
			var run := act
			act = Callable()
			run.call()


static func after_keep(on: Main) -> AfterKeep:
	var node := AfterKeep.new()
	node.world = on.world
	on.add_child(node)
	on.move_child(node, on.world.get_index() + 1)
	return node


## Reads the head after every node has moved it.
static func watch(on: Main) -> Probe:
	var probe := Probe.new()
	probe.main = on
	probe.process_priority = 1
	on.add_child(probe)
	return probe


## {} when the replay fails, which `by` checks.
static func replay(by: Suite, chunk: String, avatars: String) -> Dictionary:
	var out := ProjectSettings.globalize_path(chunk.get_base_dir().path_join("replayed"))
	DirAccess.remove_absolute(out)
	var said := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--fixed-fps", "64", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "../tests/support/replayed.gd", "--", "--replay", ProjectSettings.globalize_path(chunk), "--out", out,
		"--avatars", avatars], said, true)
	by.check(code == 0 and FileAccess.file_exists(out), "the replay of %s runs: exit %d\n%s" % [chunk.get_base_dir().get_file(), code, said[0].right(4000)])
	if not FileAccess.file_exists(out):
		return {}
	var f := FileAccess.open(out, FileAccess.READ)
	var replayed: Dictionary = f.get_var()
	f.close()
	return replayed


## A copy of the session `chunk` is part of, each event put through `change`, in a folder `name` beside it.
static func copy(chunk: String, name: String, change: Callable) -> String:
	var into := chunk.get_base_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(into)
	for file in DirAccess.get_files_at(chunk.get_base_dir()):
		if not file.ends_with(".jsonl"):
			continue
		var lines := []
		for line in FileAccess.get_file_as_string(chunk.get_base_dir().path_join(file)).split("\n", false):
			lines.append(JSON.stringify(change.call(JSON.parse_string(line))))
		var f := FileAccess.open(into.path_join(file), FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
		f.close()
	return into.path_join(chunk.get_file())


func _initialize() -> void:
	boot_main()
	Budget.frame_deadline = "--deadline" in OS.get_cmdline_user_args()
	var probe := watch(main)
	await process_frame
	await main.replayer.finished
	main.world.settle()
	var out := FileAccess.open(main.args.out, FileAccess.WRITE)
	out.store_var({"deltas": probe.deltas.duplicate(), "heads": probe.heads.duplicate(), "garden": main.world.snapshot(), "ids": probe.ids.duplicate(), "applied_at": probe.applied_at.duplicate(), "diverged": main.replayer.diverged})
	out.close()
	main.queue_free()
	await process_frame
	finish()
