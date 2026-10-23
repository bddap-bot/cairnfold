class_name Warmup
extends Node

## What the game makes ahead of its first use, each step made on first use having held a Quest's frame: the steps that
## need this thread run in the frame loading ends in, where a frame is already long, and a step that reaches a worker
## (`ToolModels.prepare_styles`) only queues its work there, which is laid in here each frame.

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
