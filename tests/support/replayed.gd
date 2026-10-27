extends "res://../tests/support/suite.gd"

## Replays the record --replay names in a fresh game and writes to --out what tests/test_replay.gd compares with the
## session it recorded: each frame's delta and the head's pose, and the garden once the replay ends and every command
## is in.


class Probe:
	extends Node
	var main: Main
	var deltas: Array[float] = []
	var heads: Array[Transform3D] = []

	func _process(delta: float) -> void:
		deltas.append(delta)
		heads.append(main.rig.head.global_transform)


## Watches `main`'s head each frame from the one it boots in, after every node has moved it.
static func watch(on: Main) -> Probe:
	var probe := Probe.new()
	probe.main = on
	probe.process_priority = 1
	on.add_child(probe)
	return probe


func _initialize() -> void:
	boot_main()
	var probe := watch(main)
	await process_frame
	await main.replayer.finished
	main.world.settle()
	var out := FileAccess.open(main.args.out, FileAccess.WRITE)
	out.store_var({"deltas": probe.deltas.duplicate(), "heads": probe.heads.duplicate(), "garden": main.world.snapshot()})
	out.close()
	main.queue_free()
	await process_frame
	finish()
