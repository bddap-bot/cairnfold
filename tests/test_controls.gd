extends SceneTree

## Headless checks of the Steam Frame's buttons, the tool ring and the shared undo history, all pressed
## through the driver: godot4 --headless --path game --script ../tests/test_controls.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	var rig: Rig = main.rig
	var walls: Array[Wall] = main.tool.walls
	await _play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "wall", "points": [[-6, -1], [-3, -3.5], [1, -4.5], [5, -3]], "seconds": 0.5},
		{"op": "wall", "points": [[-7, 3], [-6.5, 0]], "seconds": 0.3},
	])
	for b in ["A", "B", "X", "Y", "left_stick_click", "right_stick_click"]:
		await _play([{"op": "press", "button": b}])
	_check(walls.size() == 2, "a tap of every button but the D-pad leaves %d of 2 walls" % walls.size())
	_check(rig.left.tool == Hand.Tool.FLOWERS and rig.right.tool == Hand.Tool.WALLS, "a stick click without a push keeps both tools")

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == 1, "a tap of D-pad down undoes one wall, leaving %d" % walls.size())
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(walls.size() == 2, "a tap of D-pad up redoes it, %d walls" % walls.size())

	var stood := rig.global_position
	var at := rig.head.global_position + Vector3(-0.2, -0.4, -0.3)
	rig.left.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.4, -1), Vector3.UP), at)
	for t in Hand.MENU:
		await _play([{"op": "pick", "hand": "left", "tool": Hand.Tool.keys()[t].to_lower()}])
		_check(rig.left.tool == t, "the left ring picks %s, holding %s" % [Hand.Tool.keys()[t], Hand.Tool.keys()[rig.left.tool]])
	_check(rig.right.tool == Hand.Tool.WALLS, "the left ring leaves the right hand's tool alone")
	await _play([{"op": "wait", "seconds": 0.3}])
	_check(rig.global_position.is_equal_approx(stood), "pushing the left stick in the ring never teleports")
	await _play([{"op": "pick", "hand": "right", "tool": "trees"}])
	_check(rig.right.tool == Hand.Tool.TREES, "the right ring picks trees")

	var flora: Flora = main.flora_tool.flora
	var patch := Vector3(9, 0, 9)
	await _play([
		{"op": "paint", "tool": "flowers", "points": [[9, 9], [9.5, 9]], "radius": 1.0, "seconds": 0.5},
		{"op": "tree", "x": -9, "z": 9},
		{"op": "delete", "x": 0, "z": -4.4},
	])
	var tree := flora.tree_near(Terrain.ground(-9, 9), 0.5)
	_check(not _painted(flora, patch).is_empty(), "painting adds flowers")
	_check(not tree.is_empty(), "a tree stands where it was planted")
	_check(walls.size() == 1, "delete takes the one wall it points at, leaving %d" % walls.size())

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == 2, "undo puts the deleted wall back")
	await _play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	_check(not tree[0].shown(), "the next undo takes the tree away")
	_check(_painted(flora, patch).is_empty(), "and the next the painted flowers")
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(not _painted(flora, patch).is_empty(), "redo paints them back")
	await _play([{"op": "tree", "x": 9, "z": -9}, {"op": "press", "button": "dpad_up"}])
	_check(not tree[0].shown() and walls.size() == 2, "a new edit after an undo drops the redo steps")

	await _play([
		{"op": "delete", "x": 9.2, "z": 9, "height": 14},
		{"op": "delete", "x": -9, "z": 9},
	])
	_check(_painted(flora, patch).is_empty(), "delete clears the painted patch it points at")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(not _painted(flora, patch).is_empty(), "undo brings a deleted patch back")

	var before := walls.size()
	await _play([{"op": "house", "a": [12, 0], "b": [17, 0], "to_b": [18, 1], "seconds": 0.3}])
	_check(walls.size() == before + 1, "a scripted house stands with flowers in the left hand, %d walls" % walls.size())
	_check(rig.left.tool == Hand.Tool.WALLS, "and the left hand took walls to lay it out")

	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _painted(flora: Flora, at: Vector3) -> Array:
	return flora.painted_near(at, 1.5)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
