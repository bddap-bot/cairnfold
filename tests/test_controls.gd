extends SceneTree

## Headless checks of the Steam Frame's controls, the tool wheel and the shared undo history, all pressed
## through the driver: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_controls.gd

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
	for b in ["B", "X", "Y", "dpad_up", "dpad_left", "dpad_right", "view", "left_stick_click", "right_stick_click", "left_stick_down", "left_stick_left", "left_stick_right", "right_stick_up", "right_stick_down"]:
		await _play([{"op": "press", "button": b}])
	_check(walls.size() == 2, "a tap of every button but undo and redo, and a flick of a stick that neither moves nor turns, leaves %d of 2 walls" % walls.size())
	_check(rig.left.tool == Hand.Tool.FLOWERS and rig.right.tool == Hand.Tool.WALLS, "a tap of a wheel button without a sweep keeps both tools")

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == 1, "a tap of D-pad down (Quest: left X) undoes one wall, leaving %d" % walls.size())
	await _play([{"op": "press", "button": "A"}])
	_check(walls.size() == 2, "a tap of A redoes it, %d walls" % walls.size())

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
	var tree: Array = flora.planted_trees()[0] if flora.planted_trees().size() == 1 else []
	_check(not _painted(flora, patch).is_empty(), "painting adds flowers")
	_check(not tree.is_empty(), "a tree stands where it was planted")
	var ruined := func() -> int: return walls.filter(func(w: Wall) -> bool: return not w.layout.ruins.is_empty()).size()
	_check(walls.size() == 2 and ruined.call() == 1, "a tap of delete breaks a gap in the one wall it points at: %d walls, %d ruined" % [walls.size(), ruined.call()])

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == 2 and ruined.call() == 0, "undo closes the gap")
	await _play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	_check(not tree[0].shown(), "the next undo takes the tree away")
	_check(_painted(flora, patch).is_empty(), "and the next the painted flowers")
	await _play([{"op": "press", "button": "A"}])
	_check(not _painted(flora, patch).is_empty(), "redo paints them back")
	await _play([{"op": "tree", "x": 9, "z": -9}, {"op": "press", "button": "A"}])
	_check(not tree[0].shown() and walls.size() == 2, "a new edit after an undo drops the redo steps")

	await _play([
		{"op": "delete", "x": 9.2, "z": 9, "height": 14},
		{"op": "delete", "x": -9, "z": 9},
	])
	_check(_painted(flora, patch).is_empty(), "delete clears the painted patch it points at")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(not _painted(flora, patch).is_empty(), "undo brings a deleted patch back")

	await _carry_a_house(rig, walls)
	await _round_a_tower(rig, walls)
	await _resize_a_built_house(rig, walls)
	await _a_loop_stays_a_wall(walls)

	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Moves the hand itself, not an injected reach: down onto delete, then right onto planting and back left onto
## trees, in a wheel standing upright and facing the head.
func _sweep_by_hand(hand: Hand, at: Vector3) -> void:
	var key := "%s/%s" % [hand.tracker, Controls.input("wheel", hand.tracker)]
	var toward: Vector3 = main.rig.head.global_position - at
	toward.y = 0.0
	var right := Vector3.UP.cross(toward.normalized())
	var planting: Array = Hand.TREE[2]
	var back := ToolWheel.fan_dirs(planting.size(), ToolWheel.ring_dirs()[2])[planting.find(Hand.Tool.TREES)]
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
	var trackers := _track_hands()
	var hold := _holder(rig, trackers)
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
		tool.house.lay_now()
		if not tool.house.layout.laid_points.is_empty():
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
	# Directive (verbatim): "When placing a building, you should be able to raise it higher up by raising your controller up"
	for i in 10:
		hold.call(&"right_hand", Vector3(0.5, -0.4 + 0.04 * (i + 1), -0.3), spot)
		await _frames(1)
	var rise: float = tool.house_at.rise
	_check(rise >= 0.3 and tool.house.layout.rise == rise, "raising the hand raises it onto a plinth: %.1f m" % rise)
	for i in 300:
		tool.house.lay_now()
		await _frames(1)
		if tool.house.layout.laid_rise == rise:
			break
	await _frames(1)
	var foot: float = (tool.house.transform * tool.house.layout.samples[0]).y
	var ground := WallTool._lowest(WallTool.outline(tool.house_at))
	_check(is_equal_approx(foot, ground + rise - WallLayout.SINK), "and shows it standing that high: foot %.2f over ground %.2f" % [foot, ground])
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
		_check(walls[-1].layout.arches.is_empty(), "with no door until one is added")
		_check(main.world.state.walls[walls[-1].id].rise == rise, "standing as high as it was raised: %.1f m" % main.world.state.walls[walls[-1].id].rise)
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(walls.size() == before, "undo takes the house away")
	await _play([{"op": "press", "button": "A"}])
	_check(walls.size() == before + 1, "redo puts it back")
	for t in trackers.values():
		XRServer.remove_tracker(t)


func _track_hands() -> Dictionary:
	var trackers := {}
	for side in [&"left_hand", &"right_hand"]:
		var t := XRPositionalTracker.new()
		t.type = XRServer.TRACKER_CONTROLLER
		t.name = side
		XRServer.add_tracker(t)
		trackers[side] = t
	return trackers


## Poses a tracked hand `offset` from the head, pointing at `look`.
func _holder(rig: Rig, trackers: Dictionary) -> Callable:
	var head := rig.head.global_position
	return func(side: StringName, offset: Vector3, look: Vector3) -> void:
		var at := head + offset
		trackers[side].set_pose(&"aim", rig.global_transform.affine_inverse() * Transform3D(Basis.looking_at(look - at, Vector3.UP), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


## Directive (verbatim): "I'd like for round towers to still be possible."
## Report (verbatim): "I don't think there's a way to make those rounded buildings anymore. Is that right"
## Directive (verbatim): "Let's um add a rounded building that you can place. It's another tool"
## The tower tool in tracked hands takes up a round tower under a cone and sets it down; the style tool on its roof
## thatches it or lays it flat and keeps it round, each one undo step.
func _round_a_tower(rig: Rig, walls: Array[Wall]) -> void:
	await _play([{"op": "place", "x": -14, "z": 12}, {"op": "pick", "hand": "right", "tool": "tower"}])
	_check(rig.right.tool == Hand.Tool.TOWER, "the right ring picks the tower")
	var trackers := _track_hands()
	var hold := _holder(rig, trackers)
	var spot := Terrain.ground(-14, 5)
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), spot)
	await _frames(2)
	var before := walls.size()
	trackers[&"right_hand"].set_input(&"trigger_click", true)
	await _frames(2)
	var tool: WallTool = main.tool
	_check(tool.house != null and tool.house_at.round and tool.house.roof.kind == RoofLayout.Kind.CONE, "the trigger takes up a round tower under a cone")
	trackers[&"right_hand"].set_input(&"trigger_click", false)
	await _frames(4)
	_check(walls.size() == before + 1, "letting go builds it")
	if walls.size() != before + 1:
		return
	var w := walls[-1]
	var round := func() -> bool:
		return w.roof.kind == RoofLayout.Kind.CONE and w.layout.points.size() >= 12 and w.layout.points.all(func(p: Vector3) -> bool: return absf(Vector2(p.x - w.roof.center.x, p.z - w.roof.center.z).length() - w.roof.radius) < 0.05)
	_check(round.call(), "its wall runs round under its cone, %.1f m across" % (w.roof.radius * 2.0))
	_check(is_equal_approx(w.roof.radius * 2.0, WallTool.TOWER_SIZE.x) and Vector2(w.roof.center.x - spot.x, w.roof.center.z - spot.z).length() < 0.5, "where the hand pointed, %.1f m across" % (w.roof.radius * 2.0))
	_check(is_equal_approx(w.layout.height, WallTool.TOWER_HEIGHT), "and stands a tower's height: %.1f m" % w.layout.height)
	await _play([{"op": "pick", "hand": "right", "tool": "style"}])
	var picker: PaletteTool = main.palette_tool
	var restyle := func(steps: int) -> void:
		var roof := _centre(w) + Vector3.UP * w.layout.height
		var at := roof + Vector3(0, 8, 6)
		var aim := Basis.looking_at(roof - at, Vector3.UP)
		var pose := func(b: Basis) -> void:
			trackers[&"right_hand"].set_pose(&"aim", rig.global_transform.affine_inverse() * Transform3D(b, at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		pose.call(aim)
		await _frames(2)
		trackers[&"right_hand"].set_input(&"trigger_click", true)
		await _frames(2)
		_check(picker.wheels.has(rig.right) and picker.wheels[rig.right].target.get("restyle") == PaletteTool.Restyle.ROOF, "the style tool's trigger on the roof opens its roof styles")
		pose.call(aim * Basis(Vector3.FORWARD, deg_to_rad(Palette.TWIST_STEP * steps)))
		await _frames(2)
		trackers[&"right_hand"].set_input(&"trigger_click", false)
		await _frames(6)
	var coat := func() -> bool:
		w.lay_now()
		return not w.roof.coat.is_empty() and w.roof.tiles.all(func(t: Dictionary) -> bool: return t.kind != "tile")
	await restyle.call(2)
	_check(w.roof.thatch and not w.roof.flat() and round.call() and coat.call(), "Directive (verbatim): \"Thatched roofs I want them as an option.\" A twist on to thatch thatches the cone, still round")
	_check(main.tool.thatch, "and builds laid after are thatched")
	await restyle.call(-1)
	_check(w.roof.flat() and round.call(), "a twist back lays it flat, still round")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(w.roof.thatch and not w.roof.flat() and round.call(), "undo stands the thatched cone again")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(not w.roof.thatch and not coat.call() and round.call(), "and the next tiles it again")
	for t in trackers.values():
		XRServer.remove_tracker(t)


static func _centre(w: Wall) -> Vector3:
	var sum := Vector3.ZERO
	for p in w.layout.points:
		sum += p
	return sum / w.layout.points.size()


## Directive (verbatim): "Eventually I'd like to be able to resize a house" / "in each dimension"
## A built house in tracked hands: one grip pulls its height, the other hand's grip joining stretches the side
## nearest the line between the hands, and a round tower's diameter; its fittings, roof and a wall it meets follow.
func _resize_a_built_house(rig: Rig, walls: Array[Wall]) -> void:
	await _play([
		{"op": "place", "x": 12, "z": -7},
		{"op": "wall", "points": [[22, -14], [17.5, -14]], "seconds": 0.3},
		{"op": "house", "at": [12, -14], "size": [6, 4], "seconds": 0.3},
		{"op": "fit", "what": "window", "index": -1, "s": 3.0, "y": 1.0},
		{"op": "fit", "what": "lantern", "index": -1, "s": 13.0, "y": 1.6, "side": -1.0},
		{"op": "fit", "what": "chimney", "index": -1, "at": [1.5, 0.6]},
		{"op": "wait", "seconds": 0.3},
	])
	var tool: WallTool = main.tool
	var world: World = main.world
	var house := walls[-1]
	var side := walls[-2]
	var data := func() -> Dictionary: return world.state.walls[house.id]
	var at := func() -> Dictionary: return WallTool.house_of(data.call())
	_check(at.call().size.is_equal_approx(Vector2(6, 4)) and data.call().windows.size() == 1 and data.call().lanterns.size() == 1 and data.call().roof.chimneys.size() == 1, "a 6 by 4 house with a window, a lantern and a chimney: %s" % at.call())
	side.lay_now()
	var side_stones := side.layout.stones.size()
	rig.right.tool = Hand.Tool.TREES
	rig.left.tool = Hand.Tool.FLOWERS
	var trackers := _track_hands()
	var hold := _holder(rig, trackers)
	var front := Terrain.ground(12, -12) + Vector3.UP * 1.2
	var grip := func(s: StringName, on: bool) -> void:
		trackers[s].set_input(&"grip_click", on)
		await _frames(3)
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), front)
	hold.call(&"left_hand", Vector3(-0.2, -0.4, -0.3), front)
	await _frames(2)
	var height: float = house.layout.height
	await grip.call(&"right_hand", true)
	for i in 10:
		hold.call(&"right_hand", Vector3(0.2, -0.4 + 0.03 * (i + 1), -0.3), front)
		await _frames(1)
	await grip.call(&"right_hand", false)
	await _frames(4)
	_check(data.call().height > height + 0.2 and at.call().size.is_equal_approx(Vector2(6, 4)), "one grip on the house raises it, %.1f to %.1f m, keeping its footprint" % [height, data.call().height])
	height = data.call().height
	var before: Dictionary = data.call().duplicate(true)

	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), front)
	await _frames(1)
	await grip.call(&"right_hand", true)
	hold.call(&"right_hand", Vector3(0.2, -0.25, -0.3), front)
	await _frames(2)
	await grip.call(&"left_hand", true)
	_check(tool.resizing == house and is_equal_approx(house.layout.height, height), "the other hand's grip on it joins, putting back the first hand's pull: %.1f m" % house.layout.height)
	for i in 20:
		hold.call(&"right_hand", Vector3(0.2 + 0.015 * (i + 1), -0.25, -0.3), front)
		await _frames(1)
	_check(rig.left._holding and rig.right._holding, "both hands hold it")
	_check(walls[-1] == house and world.state.walls[house.id].points == before.points, "nothing is sent while it is held")
	await grip.call(&"left_hand", false)
	await grip.call(&"right_hand", false)
	await _frames(4)
	var wide: Dictionary = at.call()
	_check(tool.resizing == null and is_equal_approx(wide.size.x, 10.5) and is_equal_approx(wide.size.y, 4.0) and is_equal_approx(data.call().height, height), "spreading the hands across its front stretches only its width: %s, %.1f m high" % [wide.size, data.call().height])
	_check(absf(wide.center.x - wide.size.x * 0.5 - (12 - 3)) < 0.05, "the still hand's wall stays put; the house grows toward the moving hand: %s" % wide.center)
	await _laid(house)
	_check(house.layout.laid_points.size() == 4 and house.roof.corners == house.layout.laid_points, "its roof covers the new walls")
	var window_at := func(d: Dictionary) -> float:
		var h := WallTool.house_of(d)
		var p := WallTool._loop_point(_points(d), d.windows[0].x)
		return (p - h.center).dot(Vector3.RIGHT.rotated(Vector3.UP, h.yaw)) / h.size.x
	var lantern_at := func(d: Dictionary) -> float:
		var h := WallTool.house_of(d)
		var p := WallTool._loop_point(_points(d), d.lanterns[0].x)
		return (p - h.center).dot(Vector3.RIGHT.rotated(Vector3.UP, h.yaw)) / h.size.x
	_check(is_equal_approx(window_at.call(before), window_at.call(data.call())) and is_equal_approx(lantern_at.call(before), lantern_at.call(data.call())), "its window and inside lantern keep their places in proportion")
	_check(data.call().lanterns[0].z == before.lanterns[0].z and is_equal_approx(data.call().lanterns[0].y, before.lanterns[0].y), "the lantern on its same face, as high")
	_check(absf(data.call().roof.chimneys[0].x / before.roof.chimneys[0].x - 1.75) < 0.01, "its chimney moves out along the longer ridge: %s" % data.call().roof.chimneys[0])
	side.lay_now()
	_check(side.layout.stones.size() < side_stones, "the wall it now meets lays nothing inside it: %d of %d stones" % [side.layout.stones.size(), side_stones])

	await _play([{"op": "press", "button": "dpad_down"}])
	_check(at.call().size.is_equal_approx(Vector2(6, 4)) and data.call().windows == before.windows and data.call().roof.chimneys == before.roof.chimneys, "undo puts its width, window and chimney back: %s" % at.call().size)
	side.lay_now()
	_check(side.layout.stones.size() == side_stones, "and the wall it met whole again")
	await _play([{"op": "press", "button": "A"}])
	_check(is_equal_approx(at.call().size.x, 10.5), "redo stretches it again: %s" % at.call().size)

	var flank := Terrain.ground(13, -12) + Vector3.UP * 1.2
	hold.call(&"right_hand", Vector3(0.1, -0.4, -0.25), flank)
	hold.call(&"left_hand", Vector3(0.12, -0.38, -0.55), flank)
	await _frames(2)
	await grip.call(&"right_hand", true)
	await grip.call(&"left_hand", true)
	_check(tool.resizing == house, "two grips take it again, the hands one behind the other")
	for i in 20:
		hold.call(&"left_hand", Vector3(0.12, -0.38, -0.55 - 0.02 * (i + 1)), flank)
		await _frames(1)
	await grip.call(&"right_hand", false)
	await grip.call(&"left_hand", false)
	await _frames(4)
	var deep: Dictionary = at.call()
	_check(is_equal_approx(deep.size.x, 10.5) and is_equal_approx(deep.size.y, WallTool.HOUSE_DEPTH) and is_equal_approx(data.call().height, height), "hands along its flank stretch only its depth, to the deepest a ridge spans: %s" % deep.size)

	await _raise_by_both_hands(house, trackers, hold, grip, front)

	await _play([
		{"op": "house", "round": true, "at": [4, -15], "size": [3.4, 3.4], "seconds": 0.3},
		{"op": "wait", "seconds": 0.3},
	])
	var tower := walls[-1]
	var face := Terrain.ground(4, -13.3) + Vector3.UP * 1.5
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), face)
	hold.call(&"left_hand", Vector3(-0.2, -0.4, -0.3), face)
	await _frames(2)
	var tall := tower.layout.height
	await grip.call(&"right_hand", true)
	await grip.call(&"left_hand", true)
	for i in 20:
		hold.call(&"left_hand", Vector3(-0.2 - 0.01 * (i + 1), -0.4, -0.3), face)
		await _frames(1)
	await grip.call(&"right_hand", false)
	await grip.call(&"left_hand", false)
	await _frames(4)
	var d: Dictionary = world.state.walls[tower.id]
	var round := WallTool.house_of(d)
	var off := Array(d.points).filter(func(p: Vector3) -> bool: return absf(Vector2(p.x - round.center.x, p.z - round.center.z).length() - round.size.x * 0.5) > 0.01)
	_check(round.round and round.size.x > 5.0 and round.size.x <= WallTool.HOUSE_DEPTH and off.is_empty() and is_equal_approx(d.height, tall), "two hands spread a round tower's diameter, round and as tall: %s" % round.size)
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(is_equal_approx(WallTool.house_of(world.state.walls[tower.id]).size.x, 3.4), "undo narrows it back")
	for t in trackers.values():
		XRServer.remove_tracker(t)


## Directive (verbatim): "If I grab a house or a building with two hands, I would like to be able to lift it up, raise it a little higher"
func _raise_by_both_hands(house: Wall, trackers: Dictionary, hold: Callable, grip: Callable, front: Vector3) -> void:
	var world: World = main.world
	var data := func() -> Dictionary: return world.state.walls[house.id]
	var before: Dictionary = data.call().duplicate(true)
	await _laid(house)
	var foot := house.layout.samples[0].y
	var both := func(up: float) -> void:
		hold.call(&"right_hand", Vector3(0.2, -0.4 + up, -0.3), front)
		hold.call(&"left_hand", Vector3(-0.2, -0.4 + up, -0.3), front)
	both.call(0.0)
	await _frames(2)
	await grip.call(&"right_hand", true)
	await grip.call(&"left_hand", true)
	for i in 20:
		both.call(0.03 * (i + 1))
		await _frames(1)
	_check(data.call().get("rise", 0.0) == 0.0, "nothing is sent while it is raised")
	await grip.call(&"left_hand", false)
	await grip.call(&"right_hand", false)
	await _frames(4)
	var rise: float = data.call().rise
	_check(rise >= 0.6 and rise <= WallLayout.RISE.y and data.call().points == before.points and data.call().height == before.height, "both hands rising raise it %.1f m, as large and as tall" % rise)
	await _laid(house)
	_check(is_equal_approx(house.layout.samples[0].y, foot + rise), "it is laid that much higher: %.2f to %.2f" % [foot, house.layout.samples[0].y])
	both.call(0.0)
	await _frames(2)
	await grip.call(&"right_hand", true)
	await grip.call(&"left_hand", true)
	for i in 20:
		both.call(-0.1 * (i + 1))
		await _frames(1)
	await grip.call(&"left_hand", false)
	await grip.call(&"right_hand", false)
	await _frames(4)
	_check(data.call().rise == 0.0, "both hands lowering set it back on its ground, no lower: %.1f" % data.call().rise)
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(is_equal_approx(data.call().rise, rise), "undo raises it again: %.1f" % data.call().rise)
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(data.call().rise == 0.0, "and once more puts it down")


func _points(d: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.assign(Array(d.points))
	return out


func _laid(w: Wall) -> void:
	for i in 300:
		w.lay_now()
		if w.layout.laid_points == w.layout.points:
			return
		await _frames(1)


## Directive (verbatim): "Sometimes I want to draw a circular wall. Um, In that case, I don't think it makes sense to turn it into a building, when I- didn't want that"
func _a_loop_stays_a_wall(walls: Array[Wall]) -> void:
	var tool: WallTool = main.tool
	main.rig.right.tool = Hand.Tool.WALLS
	var m := tool.mason(main.rig.right)
	var before := walls.size()
	var ring: Array[Vector3] = []
	for i in 25:
		var a := TAU * i / 24.0
		ring.append(Terrain.ground(-14.0 + cos(a) * 2.5, -12.0 + sin(a) * 2.5))
	tool.begin_stroke(m, ring[0])
	for p in ring:
		await _frames(1)
		tool.extend_stroke(m, p)
	for i in 90:
		await _frames(1)
		tool.extend_stroke(m, ring[-1])
	tool.end_stroke(m)
	await _frames(4)
	_check(walls.size() == before + 1, "a loop drawn and held closed builds one wall: %d" % (walls.size() - before))
	if walls.size() == before + 1:
		_check(walls[-1].roof == null and not walls[-1].layout.closed, "and it stays a freestanding wall, roofless")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _painted(flora: Flora, at: Vector3) -> Array:
	return flora.plants_near(at, 1.5).filter(func(p: Flora.Plant) -> bool: return p.group != 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
