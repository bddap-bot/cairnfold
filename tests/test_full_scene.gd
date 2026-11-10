extends "res://../tests/support/suite.gd"

## demo/full.json builds all it must within the frame budget, and its all_fit step fails a run the budget turned down:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_full_scene.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	var steps := Driver.read("res://../demo/full.json")
	var full := await play(steps.slice(0, steps.find_custom(func(s: Dictionary) -> bool: return s.op == "all_fit") + 1))
	check(not full.failed, "the full scene's trees, strokes, pond and house all fit")
	check(main.tool.walls.size() == 1, "and its house stands")
	var refused := await play([{"op": "budget", "bounded": true, "fill": 0.0}, {"op": "village", "radius": 9, "spacing": 7}, {"op": "all_fit"}])
	check(refused.failed, "a village the budget turns down fails all_fit")
	finish()
