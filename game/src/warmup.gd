class_name Warmup
extends Node

## Steps that stalled a Quest frame when made on first use; they run in the frame loading ends in, already long. A worker
## step (`ToolModels.prepare_styles`) only queues there; its work is laid in here each frame.

var _steps: Array[Callable] = []


func _init(steps: Array[Callable]) -> void:
	name = "Warmup"
	_steps = steps


func _process(_delta: float) -> void:
	for step in _steps:
		var began := Time.get_ticks_usec()
		step.call()
		Metrics.note("warm: %s" % step.get_method(), (Time.get_ticks_usec() - began) / 1000.0)
	_steps.clear()
	ToolModels.deliver()


func _exit_tree() -> void:
	ToolModels.stop_styles()
