extends SceneTree

## Headless checks of the Steam Frame's buttons, the tool wheel and the shared undo history, all pressed
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
	for b in ["A", "B", "X", "Y", "view", "left_stick_click", "right_stick_click"]:
		await _play([{"op": "press", "button": b}])
	_check(walls.size() == 2, "a tap of every button but the D-pad leaves %d of 2 walls" % walls.size())
	_check(rig.left.tool == Hand.Tool.FLOWERS and rig.right.tool == Hand.Tool.WALLS, "a tap of a wheel button without a sweep keeps both tools")

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == 1, "a tap of D-pad down undoes one wall, leaving %d" % walls.size())
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(walls.size() == 2, "a tap of D-pad up redoes it, %d walls" % walls.size())

	var stood := rig.global_position
	var at := rig.head.global_position + Vector3(-0.2, -0.4, -0.3)
	rig.left.global_transform = Transform3D(Basis.looking_at(Vector3(0, -0.4, -1), Vector3.UP), at)
	for t in ToolWheel.paths(Hand.TREE):
		await _play([{"op": "pick", "hand": "left", "tool": Hand.Tool.keys()[t].to_lower()}])
		_check(rig.left.tool == t, "the left wheel picks %s, holding %s" % [Hand.Tool.keys()[t], Hand.Tool.keys()[rig.left.tool]])
	_check(rig.right.tool == Hand.Tool.WALLS, "the left wheel leaves the right hand's tool alone")
	await _play([{"op": "wait", "seconds": 0.3}])
	_check(rig.global_position.is_equal_approx(stood), "picking from the left wheel never teleports")
	await _play([{"op": "pick", "hand": "right", "tool": "trees"}])
	_check(rig.right.tool == Hand.Tool.TREES, "the right wheel picks trees")
	await _sweep_by_hand(rig.left, at)

	rig.left.tool = Hand.Tool.FLOWERS
	rig.right.tool = Hand.Tool.WALLS

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
	var ruined := func() -> int: return walls.filter(func(w: Wall) -> bool: return not w.layout.ruins.is_empty()).size()
	_check(walls.size() == 2 and ruined.call() == 1, "a tap of delete breaks a gap in the one wall it points at: %d walls, %d ruined" % [walls.size(), ruined.call()])

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == 2 and ruined.call() == 0, "undo closes the gap")
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


## Moves the hand itself, not an injected reach: down onto delete, then right onto planting and back left onto
## trees, in a wheel standing upright and facing the head.
func _sweep_by_hand(hand: Hand, at: Vector3) -> void:
	var key := "%s/%s" % [hand.tracker, Hand.WHEEL_BUTTON[hand.tracker]]
	var toward: Vector3 = main.rig.head.global_position - at
	toward.y = 0.0
	var right := Vector3.UP.cross(toward.normalized())
	var planting: Array = Hand.TREE[2]
	var back := ToolWheel.fan_dirs(planting.size(), -1.0)[planting.find(Hand.Tool.TREES)]
	for case in [[Hand.Tool.DELETE, [Vector3.DOWN]], [Hand.Tool.TREES, [right, right * back.x + Vector3.UP * back.y]]]:
		hand.global_position = at
		Buttons.injected[key] = true
		await process_frame
		await process_frame
		var from := at
		for step: Vector3 in case[1]:
			var to := from + step * ToolWheel.RADIUS
			for f in 6:
				hand.global_position = from.lerp(to, (f + 1) / 6.0)
				await process_frame
			from = to
		Buttons.injected.erase(key)
		await process_frame
		await process_frame
		_check(hand.tool == case[0], "sweeping the hand itself picks %s, holding %s" % [Hand.Tool.keys()[case[0]], Hand.Tool.keys()[hand.tool]])
	hand.global_position = at


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
