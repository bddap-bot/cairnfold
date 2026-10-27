extends "res://../tests/support/suite.gd"

## The main thread keeps to the cores clocked above the slowest, and never to more than it was given:
## godot4 --headless --path game --script ../tests/test_fast_cores.gd


func _initialize() -> void:
	var frame := {0: 2265600, 1: 2265600, 2: 3148800, 3: 3148800, 4: 3148800, 5: 2956800, 6: 2956800, 7: 3052800}
	check(FastCores.fast([0, 1, 2, 3, 4] as Array[int], frame) == [2, 3, 4], "the Frame's game cores leave the two slow ones")
	check(FastCores.fast([2, 3] as Array[int], frame) == [2, 3], "a thread already off the slow cores keeps its cores")
	check(FastCores.fast([0, 1] as Array[int], frame) == [0, 1], "a thread given only slow cores keeps them")
	var even := {0: 3000000, 1: 3000000, 2: 3000000, 3: 3000000}
	check(FastCores.fast([0, 1, 2, 3] as Array[int], even) == [0, 1, 2, 3], "cores clocked alike are all kept")
	check(FastCores.fast([0, 1, 2] as Array[int], {1: 1, 2: 2}) == [0, 1, 2], "a core whose clock is unknown keeps all")
	check(FastCores._cpus("0-4,6\n") == [0, 1, 2, 3, 4, 6], "a cpu list reads as its cores")
	check(FastCores._cpus("x").is_empty(), "an unreadable cpu list names no cores")
	finish()
