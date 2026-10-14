extends SceneTree

## Headless checks of the Steam Frame's buttons, pressed through the driver: godot4 --headless --path game --script ../tests/test_controls.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "wall", "points": [[-6, -1], [-3, -3.5], [1, -4.5], [5, -3]], "seconds": 0.5},
		{"op": "wall", "points": [[-7, 3], [-6.5, 0]], "seconds": 0.3},
		{"op": "press", "button": "X"},
	])
	_check(main.tool.walls.size() == 2, "X with walls built leaves %d of 2 walls" % main.tool.walls.size())
	_check(main.flora_tool.mode == FloraTool.Mode.GRASS, "X switches flowers to grass")
	for b in Driver.FRAME_BUTTONS:
		await _play([{"op": "press", "button": b}])
	_check(main.tool.walls.size() == 2, "a tap of every Frame button leaves %d of 2 walls" % main.tool.walls.size())
	await _play([{"op": "press", "button": "dpad_down", "seconds": 0.8}])
	_check(main.tool.walls.size() == 1, "holding D-pad down undoes one wall, leaving %d" % main.tool.walls.size())
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
