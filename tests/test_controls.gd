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

	await _carry_a_house(rig, walls)

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
## The house tool in tracked hands: the trigger takes up a square house where it points and carries it; the other
## hand's grip joins to spread and turn it; letting go builds it.
func _carry_a_house(rig: Rig, walls: Array[Wall]) -> void:
	await _play([{"op": "place", "x": 14, "z": 12}, {"op": "pick", "hand": "right", "tool": "house"}])
	_check(rig.right.tool == Hand.Tool.HOUSE, "the right ring picks the house")
	var trackers := {}
	for side in [&"left_hand", &"right_hand"]:
		var t := XRPositionalTracker.new()
		t.type = XRServer.TRACKER_CONTROLLER
		t.name = side
		XRServer.add_tracker(t)
		trackers[side] = t
	var head := rig.head.global_position
	var hold := func(side: StringName, offset: Vector3, look: Vector3) -> void:
		var at := head + offset
		trackers[side].set_pose(&"aim", rig.global_transform.affine_inverse() * Transform3D(Basis.looking_at(look - at, Vector3.UP), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var spot := Terrain.ground(14, 5)
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), spot)
	hold.call(&"left_hand", Vector3(-0.2, -0.4, -0.3), spot)
	await _frames(2)
	var before := walls.size()
	trackers[&"right_hand"].set_input(&"trigger_click", true)
	await _frames(2)
	var tool: WallTool = main.tool
	_check(tool.house != null, "the trigger takes up a house")
	if tool.house == null:
		return
	_check(Vector2(tool.house_at.center.x - spot.x, tool.house_at.center.z - spot.z).length() < 0.5, "where the hand points: %s" % tool.house_at.center)
	_check(tool.house_at.size == WallTool.HOUSE_SIZE and is_equal_approx(tool.house_at.size.x, tool.house_at.size.y), "a square house")
	for i in 300:
		if not tool.house.laying() and not tool.house.layout.laid_points.is_empty():
			break
		await _frames(1)
	var laid: int = tool.house.layout.laid
	var start: Vector3 = tool.house_at.center
	for i in 10:
		hold.call(&"right_hand", Vector3(0.2 + 0.03 * (i + 1), -0.4, -0.3), spot)
		await _frames(1)
		var stands: Vector3 = tool.house.transform * Vector3(start.x, 0.0, start.z)
		if Vector2(stands.x - tool.house_at.center.x, stands.z - tool.house_at.center.z).length() > 0.01:
			_check(false, "frame %d: the laid house stands at %s, carried to %s" % [i, stands, tool.house_at.center])
			break
	_check(tool.house_at.center.x > spot.x + 1.0, "moving the hand carries it: %s" % tool.house_at.center)
	_check(tool.house.layout.laid == laid, "carried, not laid again: walls, roof and all move as one")
	_check(tool.house.roof.corners == tool.house.layout.laid_points, "the roof stands on the walls as laid")
	trackers[&"left_hand"].set_input(&"grip_click", true)
	await _frames(2)
	var square: Vector2 = tool.house_at.size
	var askew := 0
	for i in 20:
		hold.call(&"left_hand", Vector3(-0.2 - 0.015 * (i + 1), -0.4, -0.3), spot)
		await _frames(1)
		if tool.house.roof.corners != tool.house.layout.laid_points:
			askew += 1
	_check(askew == 0, "while it stretches the roof stays on the walls as laid, askew on %d frames" % askew)
	_check(tool.house_at.size.x > square.x * 1.3, "the left grip joins, and spreading the hands stretches it: %s" % tool.house_at.size)
	_check(rig.left._holding and rig.right._holding and not rig.right._beam.visible and not rig.left._beam.visible, "both hands holding it show no pointer")
	var yaw: float = tool.house_at.yaw
	for i in 10:
		hold.call(&"left_hand", Vector3(-0.5, -0.4, -0.3 + 0.06 * (i + 1)), spot)
		await _frames(1)
	_check(absf(angle_difference(yaw, tool.house_at.yaw)) > 0.3, "turning the pair turns it: %f to %f" % [yaw, tool.house_at.yaw])
	await _frames(4)
	_check(walls.size() == before, "nothing stands while it is held")
	trackers[&"right_hand"].set_input(&"trigger_click", false)
	await _frames(2)
	_check(tool.house != null, "the left hand alone still holds it")
	trackers[&"left_hand"].set_input(&"grip_click", false)
	await _frames(4)
	_check(tool.house == null and walls.size() == before + 1, "letting go builds it, %d walls" % walls.size())
	if walls.size() == before + 1:
		_check(walls[-1].roof != null and walls[-1].layout.closed, "a roofed house")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == before, "undo takes the house away")
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(walls.size() == before + 1, "redo puts it back")
	for t in trackers.values():
		XRServer.remove_tracker(t)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


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
