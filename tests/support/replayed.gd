extends "res://../tests/support/suite.gd"

## Replays the record --replay names in a fresh game and writes to --out what tests/test_replay.gd compares with the
## session it recorded: each frame's delta and the head's pose, the garden once the replay ends and every command
## is in, the id it played as each frame, and where the replay diverged from the record (Replayer.diverged).

const Suite := preload("res://../tests/support/suite.gd")


class Probe:
	extends Node
	var main: Main
	var deltas: Array[float] = []
	var heads: Array[Transform3D] = []
	var ids: Array[int] = []

	func _process(delta: float) -> void:
		deltas.append(delta)
		heads.append(main.rig.head.global_transform)
		ids.append(main.multiplayer.get_unique_id())


## Watches `main`'s head each frame from the one it boots in, after every node has moved it.
static func watch(on: Main) -> Probe:
	var probe := Probe.new()
	probe.main = on
	probe.process_priority = 1
	on.add_child(probe)
	return probe


## What this script makes of replaying `chunk` in a fresh game, its player's own files in `avatars`; {} when it fails,
## which `by` checks.
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


func _initialize() -> void:
	boot_main()
	Budget.frame_deadline = "--deadline" in OS.get_cmdline_user_args()
	var probe := watch(main)
	await process_frame
	await main.replayer.finished
	main.world.settle()
	var out := FileAccess.open(main.args.out, FileAccess.WRITE)
	out.store_var({"deltas": probe.deltas.duplicate(), "heads": probe.heads.duplicate(), "garden": main.world.snapshot(), "ids": probe.ids.duplicate(), "diverged": main.replayer.diverged})
	out.close()
	main.queue_free()
	await process_frame
	finish()
