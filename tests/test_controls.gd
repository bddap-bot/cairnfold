extends "res://../tests/support/suite.gd"

## Headless checks of the Steam Frame's controls, the tool wheel and the shared undo history, all pressed
## through the driver: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_controls.gd


func _initialize() -> void:
	# These grips point at what they take: the reach they check is the pointing grab, until a playtest keeps one.
	Reach.mode = Reach.Mode.AIM
	boot_main()
	_run.call_deferred()


func _run() -> void:
	main.world.bounded = false
	var rig: Rig = main.rig
	var walls: Array[Wall] = main.tool.walls
	await play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "wall", "points": [[-6, -1], [-3, -3.5], [1, -4.5], [5, -3]], "seconds": 0.5},
		{"op": "wall", "points": [[-7, 3], [-6.5, 0]], "seconds": 0.3},
	])
	for b in ["B", "X", "Y", "dpad_up", "dpad_left", "dpad_right", "view", "menu", "left_bumper", "right_bumper", "right_stick_click", "left_stick_down", "left_stick_left", "left_stick_right", "right_stick_up", "right_stick_down", "right_stick_left", "right_stick_right"]:
		await play([{"op": "press", "button": b}])
	check(walls.size() == 2, "a tap of every button but undo and redo, and a flick of a stick that neither moves nor turns, leaves %d of 2 walls" % walls.size())
	check(rig.left.tool == Hand.Tool.NONE and rig.right.tool == Hand.Tool.NONE, "a tap of a wheel button without a sweep empties both hands, holding %s and %s" % [Hand.Tool.keys()[rig.left.tool], Hand.Tool.keys()[rig.right.tool]])
	rig.left.tool = Hand.Tool.BOOK
	rig.right.tool = Hand.Tool.WALLS

	await play([{"op": "press", "button": "dpad_down"}])
	check(walls.size() == 1, "a tap of D-pad down (Quest: left X) undoes one wall, leaving %d" % walls.size())
	await play([{"op": "press", "button": "A"}])
	check(walls.size() == 2, "a tap of A redoes it, %d walls" % walls.size())

	var stood := rig.global_position
	var at := rig.head.global_position + rig.global_basis * Vector3(-0.2, -0.4, -0.3)
	rig.left.global_transform = Transform3D(Basis.looking_at(rig.global_basis * Vector3(0, -0.4, -1), Vector3.UP), at)
	for t in ToolWheel.paths(Hand.TREE):
		if t is String:
			continue
		await play([{"op": "pick", "hand": "left", "tool": Hand.Tool.keys()[t].to_lower()}])
		check(rig.left.tool == t, "the left wheel picks %s, holding %s" % [Hand.Tool.keys()[t], Hand.Tool.keys()[rig.left.tool]])
	check(rig.right.tool == Hand.Tool.WALLS, "the left wheel leaves the right hand's tool alone")
	await play([{"op": "wait", "seconds": 0.3}])
	check(rig.global_position.is_equal_approx(stood), "picking from the left wheel never teleports")
	await play([{"op": "pick", "hand": "right", "tool": "trees"}])
	check(rig.right.tool == Hand.Tool.TREES, "the right wheel picks trees")
	await _sweep_by_hand(rig.left, at)

	rig.left.tool = Hand.Tool.FLOWERS
	rig.right.tool = Hand.Tool.WALLS

	var flora: Flora = main.flora_tool.flora
	var patch := Vector3(9, 0, 9)
	await play([
		{"op": "paint", "tool": "flowers", "points": [[9, 9], [9.5, 9]], "radius": 1.0, "seconds": 0.5},
		{"op": "tree", "x": -9, "z": 9, "seed": 1},
		{"op": "delete", "x": 0, "z": -4.4},
	])
	var tree: Array = flora.placed("tree")[0] if flora.placed("tree").size() == 1 else []
	check(not _painted(flora, patch).is_empty(), "painting adds flowers")
	check(not tree.is_empty(), "a tree stands where it was planted")
	var ruined := func() -> int: return walls.filter(func(w: Wall) -> bool: return not w.layout.ruins.is_empty()).size()
	check(walls.size() == 2 and ruined.call() == 1, "a tap of delete breaks a gap in the one wall it points at: %d walls, %d ruined" % [walls.size(), ruined.call()])

	await play([{"op": "press", "button": "dpad_down"}])
	check(walls.size() == 2 and ruined.call() == 0, "undo closes the gap")
	await play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	check(not tree[0].shown(), "the next undo takes the tree away")
	check(_painted(flora, patch).is_empty(), "and the next the painted flowers")
	await play([{"op": "press", "button": "A"}])
	check(not _painted(flora, patch).is_empty(), "redo paints them back")
	# Seeded: some random crowns reach across the ray from the hand to the house _resize_a_built_house grips.
	await play([{"op": "tree", "x": 9, "z": -9, "seed": 1}, {"op": "press", "button": "A"}])
	check(not tree[0].shown() and walls.size() == 2, "a new edit after an undo drops the redo steps")

	await play([
		{"op": "delete", "x": 9.2, "z": 9, "height": 14},
		{"op": "delete", "x": -9, "z": 9},
	])
	check(_painted(flora, patch).is_empty(), "delete clears the painted patch it points at")
	await play([{"op": "press", "button": "dpad_down"}])
	check(not _painted(flora, patch).is_empty(), "undo brings a deleted patch back")

	await _carry_a_house(rig, walls)
	await _round_a_tower(rig, walls)
	await _resize_a_built_house(rig, walls)
	await _a_loop_stays_a_wall(walls)

	finish()


## Moves the hand itself through the tool paths in a wheel standing upright and facing the head.
func _sweep_by_hand(hand: Hand, at: Vector3) -> void:
	var key := "%s/%s" % [hand.tracker, Controls.input("wheel", hand.tracker)]
	var toward: Vector3 = main.rig.head.global_position - at
	toward.y = 0.0
	var right := Vector3.UP.cross(toward.normalized())
	var paths := ToolWheel.paths(Hand.TREE)
	for tool in [Hand.Tool.DELETE, Hand.Tool.GRASS, Hand.Tool.MOSS]:
		hand.global_position = at
		Buttons.injected[key] = true
		await process_frame
		await process_frame
		var from := at
		for point: Vector2 in ToolWheel.sweep(Hand.TREE, paths[tool]):
			var to := at + right * point.x + Vector3.UP * point.y
			for f in 6:
				hand.global_position = from.lerp(to, (f + 1) / 6.0)
				await process_frame
			from = to
		Buttons.injected.erase(key)
		await process_frame
		await process_frame
		check(hand.tool == tool, "sweeping the hand itself picks %s, holding %s" % [Hand.Tool.keys()[tool], Hand.Tool.keys()[hand.tool]])
	hand.global_position = at
## Directive (verbatim): "If I grab a house or a building with two hands, I would like to be able to lift it up, raise it a little higher"
## Report (relay): placing a house with the trigger only places it; moving it is the grip's job, never the trigger's.
## The house tool in tracked hands: the trigger puts up a square house where it points and holding it moves nothing; a
## grip on the house carries it, its stones as laid, and raises it onto its plinth; the other hand's grip on it stretches
## it across and makes it taller upright; letting go sets it, one undo step.
func _carry_a_house(rig: Rig, walls: Array[Wall]) -> void:
	await play([{"op": "place", "x": 14, "z": 12}, {"op": "pick", "hand": "right", "tool": "house"}])
	check(rig.right.tool == Hand.Tool.HOUSE, "the right ring picks the house")
	var trackers := _track_hands()
	var hold := _holder(rig, trackers)
	var spot := main.world.terrain.ground(14, 5)
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), spot)
	hold.call(&"left_hand", Vector3(-0.2, -0.4, -0.3), spot)
	await frames(2)
	var before := walls.size()
	trackers[&"right_hand"].set_input(&"trigger_click", true)
	await frames(4)
	var tool: WallTool = main.tool
	check(walls.size() == before + 1 and tool.held == null, "the trigger puts up a house: %d walls" % walls.size())
	if walls.size() != before + 1:
		return
	var w := walls[-1]
	var data := func() -> Dictionary: return main.world.state.walls[w.id]
	var placed := WallTool.house_of(data.call())
	var placed_points: PackedVector3Array = data.call().points
	check(Vector2(placed.center.x - spot.x, placed.center.z - spot.z).length() < 0.5, "where the hand points: %s" % placed.center)
	check(placed.size == WallTool.HOUSE_SIZE and w.roof != null and w.layout.closed and w.layout.openings.is_empty(), "a square roofed house with no door until one is added")
	for i in 10:
		hold.call(&"right_hand", Vector3(0.2 + 0.03 * (i + 1), -0.4, -0.3), spot)
		await frames(1)
	trackers[&"right_hand"].set_input(&"trigger_click", false)
	await frames(2)
	check(WallTool.house_of(data.call()).center == placed.center and walls.size() == before + 1, "holding the trigger and moving the hand moves nothing")
	await _laid(w)
	var front: Vector3 = placed.center + Vector3.UP * 1.2 + Vector3.RIGHT.rotated(Vector3.UP, placed.yaw).cross(Vector3.UP) * placed.size.y * 0.5
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), front)
	await frames(2)
	trackers[&"right_hand"].set_input(&"grip_click", true)
	await frames(2)
	check(tool.held == w, "a grip on its wall takes the house")
	var laid: int = w.layout.laid
	var start: Vector3 = tool.held_at.center
	for i in 10:
		hold.call(&"right_hand", Vector3(0.2 + 0.03 * (i + 1), -0.4, -0.3), front)
		await frames(1)
		var stands: Vector3 = w.transform * Vector3(start.x, 0.0, start.z)
		if Vector2(stands.x - tool.held_at.center.x, stands.z - tool.held_at.center.z).length() > 0.01:
			check(false, "frame %d: the laid house stands at %s, carried to %s" % [i, stands, tool.held_at.center])
			break
	check(Vector2(tool.held_at.center.x - start.x, tool.held_at.center.z - start.z).length() > 1.0, "moving the hand carries it: %s" % tool.held_at.center)
	check(w.layout.laid == laid, "carried, not laid again: walls, roof and all move as one")
	check(w._drawn != null and w.masonry.counts() != null and not w._settled, "its stones are drawn with it, not left in the glade's")
	check(data.call().points == PackedVector3Array(WallTool.outline(placed)) or WallTool.house_of(data.call()).center == placed.center, "nothing is sent while it is held")
	# Directive (verbatim): "When placing a building, you should be able to raise it higher up by raising your controller up"
	var stale := 0
	for i in 70:
		hold.call(&"right_hand", Vector3(0.5, -0.4 + 0.04 * mini(i + 1, 10), -0.3), front)
		await frames(1)
		var shown: Dictionary = tool._laid_at[0]
		if shown.points != w.layout.laid_points or shown.laid_rise != w.layout.laid_rise:
			stale += 1
	check(stale == 0, "each frame the stones laid are the ones carried, never a new lay under the old carry: %d stale frames" % stale)
	var rise: float = tool.held_at.rise
	check(rise >= 0.3 and w.layout.rise == rise, "raising the hand raises it onto its plinth: %.1f m" % rise)
	await _laid(w)
	await frames(1)
	var foot: float = (w.transform * w.layout.samples[0]).y
	var ground := WallTool._lowest(WallTool.outline(tool.held_at), main.world.terrain.height_at)
	check(is_equal_approx(foot, ground + rise - WallLayout.SINK), "and shows it standing that high, never floating: foot %.2f over ground %.2f" % [foot, ground])
	var left_at := Vector3(-0.2, -0.4, -0.3)
	hold.call(&"left_hand", left_at, tool.held_at.center + Vector3.UP * (rise + 1.2) + (front - placed.center).normalized() * placed.size.y * 0.5 - Vector3.UP * 1.2)
	await frames(1)
	trackers[&"left_hand"].set_input(&"grip_click", true)
	await frames(2)
	check(tool._holders.size() == 2 and tool._pair == WallTool.Pair.WALLS, "the left grip on its wall joins to size it")
	Cues.pulsed.clear()
	var square: Vector2 = tool.held_at.size
	var held_at: Dictionary = tool.held_at.duplicate()
	var askew := 0
	for i in 20:
		hold.call(&"right_hand", Vector3(0.5 + 0.015 * (i + 1), 0.0, -0.3), front)
		await frames(1)
		if w.roof.corners != w.layout.laid_points:
			askew += 1
	check(askew == 0, "while it stretches the roof stays on the walls as laid, askew on %d frames" % askew)
	check(tool.held_at.size.x > square.x * 1.2 or tool.held_at.size.y > square.y * 1.2, "spreading the hands stretches it: %s" % tool.held_at.size)
	check(tool.held_at.rise == held_at.rise and tool.held_at.yaw == held_at.yaw, "two hands neither raise its plinth nor turn it")
	check(_pulsed_both(Cues.Act.HOUSE_STRETCH, rig), "the stretch pulses in both hands: %s" % Cues.pulsed)
	check(rig.left._holding and rig.right._holding and not rig.right.aiming() and not rig.left.aiming(), "both hands holding it show no pointer")
	# Report (relay): two hands stretching a house vertically make the house itself taller.
	var height: float = tool.held_at.height
	for i in 10:
		hold.call(&"right_hand", Vector3(0.8, 0.0 + 0.06 * (i + 1), -0.3), front)
		await frames(1)
	check(tool.held_at.height > height + 0.5 and w.layout.height == tool.held_at.height, "drawing the hands apart upright makes its walls taller: %.1f to %.1f m" % [height, tool.held_at.height])
	var sized: Dictionary = tool.held_at.duplicate()
	await frames(4)
	check(walls.size() == before + 1, "nothing new stands while it is held")
	trackers[&"right_hand"].set_input(&"grip_click", false)
	await frames(2)
	check(tool.held == w, "the left hand alone still holds it")
	trackers[&"left_hand"].set_input(&"grip_click", false)
	var back_home := 0
	for i in 60:
		await frames(1)
		if PackedVector3Array(w.layout.laid_points) == placed_points:
			back_home += 1
	check(back_home == 0, "once let go it never shows where it stood before: %d frames" % back_home)
	var set_at := WallTool.house_of(data.call())
	check(tool.held == null and walls.size() == before + 1, "letting go leaves the one house, %d walls" % walls.size())
	check(set_at.center.is_equal_approx(sized.center) and set_at.size.is_equal_approx(sized.size) and set_at.rise == rise and is_equal_approx(set_at.height, sized.height), "set where and as it was let go: %s" % set_at)
	await _laid(w)
	await frames(2)
	check(w.transform.is_equal_approx(Transform3D.IDENTITY), "laid again where it stands, carried no more")
	await play([{"op": "press", "button": "dpad_down"}])
	var back := WallTool.house_of(data.call())
	check(back.center.is_equal_approx(placed.center) and back.size == placed.size and back.rise == 0.0 and back.height == placed.height, "one undo puts it back where and as it was put up: %s" % back)
	await play([{"op": "press", "button": "A"}])
	check(WallTool.house_of(data.call()).center.is_equal_approx(sized.center), "redo carries it again")
	await play([{"op": "press", "button": "dpad_down"}, {"op": "press", "button": "dpad_down"}])
	check(walls.size() == before, "and the undo before takes the house away")
	await play([{"op": "press", "button": "A"}])
	check(walls.size() == before + 1, "redo puts it back")
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
## switches tile and thatch without changing its pitch or round footprint, each one undo step.
func _round_a_tower(rig: Rig, walls: Array[Wall]) -> void:
	await play([{"op": "place", "x": -14, "z": 12}, {"op": "pick", "hand": "right", "tool": "tower"}])
	check(rig.right.tool == Hand.Tool.TOWER, "the right ring picks the tower")
	var trackers := _track_hands()
	var hold := _holder(rig, trackers)
	var spot := main.world.terrain.ground(-14, 5)
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), spot)
	await frames(2)
	var before := walls.size()
	trackers[&"right_hand"].set_input(&"trigger_click", true)
	await frames(2)
	var tool: WallTool = main.tool
	trackers[&"right_hand"].set_input(&"trigger_click", false)
	await frames(4)
	check(walls.size() == before + 1 and tool.held == null, "the trigger puts up a tower")
	if walls.size() != before + 1:
		return
	var w := walls[-1]
	var round := func() -> bool:
		return w.roof.kind == RoofLayout.Kind.CONE and w.layout.points.size() >= 12 and w.layout.points.all(func(p: Vector3) -> bool: return absf(Vector2(p.x - w.roof.center.x, p.z - w.roof.center.z).length() - w.roof.radius) < 0.05)
	check(round.call(), "its wall runs round under its cone, %.1f m across" % (w.roof.radius * 2.0))
	check(is_equal_approx(w.roof.radius * 2.0, WallTool.TOWER_SIZE.x) and Vector2(w.roof.center.x - spot.x, w.roof.center.z - spot.z).length() < 0.5, "where the hand pointed, %.1f m across" % (w.roof.radius * 2.0))
	check(is_equal_approx(w.layout.height, WallTool.TOWER_HEIGHT), "and stands a tower's height: %.1f m" % w.layout.height)
	await play([{"op": "pick", "hand": "right", "tool": "style"}])
	var picker: PaletteTool = main.palette_tool
	var restyle := func(steps: int) -> void:
		var roof := _centre(w) + Vector3.UP * w.layout.height
		var at := roof + Vector3(0, 8, 6)
		var aim := Basis.looking_at(roof - at, Vector3.UP)
		var pose := func(b: Basis) -> void:
			trackers[&"right_hand"].set_pose(&"aim", rig.global_transform.affine_inverse() * Transform3D(b, at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		pose.call(aim)
		await frames(2)
		trackers[&"right_hand"].set_input(&"trigger_click", true)
		await frames(2)
		check(picker.wheels.has(rig.right) and picker.wheels[rig.right].target.get("restyle") == PaletteTool.Restyle.ROOF, "the style tool's trigger on the roof opens its roof styles")
		pose.call(aim * Basis(Vector3.FORWARD, deg_to_rad(Palette.TWIST_STEP * steps)))
		await frames(2)
		trackers[&"right_hand"].set_input(&"trigger_click", false)
		await frames(6)
	var coat := func() -> bool:
		w.lay_now()
		return not w.roof.coat.is_empty() and w.roof.tiles.all(func(t: Dictionary) -> bool: return t.kind != "tile")
	var pitch := w.roof.pitch
	await restyle.call(1)
	check(w.roof.thatch and not w.roof.flat() and round.call() and coat.call(), "Directive (verbatim): \"Thatched roofs I want them as an option.\" A twist on to thatch thatches the cone, still round")
	check(main.tool.thatch, "and builds laid after are thatched")
	await restyle.call(-1)
	check(not w.roof.thatch and is_equal_approx(w.roof.pitch, pitch) and round.call(), "a twist back tiles it, keeping pitch and round footprint")
	await play([{"op": "press", "button": "dpad_down"}])
	check(w.roof.thatch and not w.roof.flat() and round.call(), "undo stands the thatched cone again")
	await play([{"op": "press", "button": "dpad_down"}])
	check(not w.roof.thatch and not coat.call() and round.call(), "and the next tiles it again")
	for t in trackers.values():
		XRServer.remove_tracker(t)


static func _centre(w: Wall) -> Vector3:
	var sum := Vector3.ZERO
	for p in w.layout.points:
		sum += p
	return sum / w.layout.points.size()


## Directive (verbatim): "Eventually I'd like to be able to resize a house" / "in each dimension"
## A built house in tracked hands: one grip raises it onto its plinth and sets it back down, the other hand's grip
## joining stretches the side nearest the line between the hands, and a round tower's diameter; its fittings, roof and a
## wall it meets follow.
func _resize_a_built_house(rig: Rig, walls: Array[Wall]) -> void:
	await play([
		{"op": "place", "x": 12, "z": -7},
		{"op": "wall", "points": [[22, -14], [17.5, -14]], "seconds": 0.3},
		{"op": "house", "at": [12, -14], "size": [6, 4], "seconds": 0.3},
		{"op": "uncluttered"},
		{"op": "fit", "what": "opening", "index": -1, "s": 3.0, "y": 1.0},
		{"op": "fit", "what": "lantern", "index": -1, "s": 15.0, "y": 1.6, "side": -1.0},
		{"op": "fit", "what": "chimney", "index": -1, "at": [1.5, 0.6]},
		{"op": "wait", "seconds": 0.3},
	])
	var tool: WallTool = main.tool
	var world: World = main.world
	var house := walls[-1]
	var side := walls[-2]
	var data := func() -> Dictionary: return world.state.walls[house.id]
	var at := func() -> Dictionary: return WallTool.house_of(data.call())
	check(at.call().size.is_equal_approx(Vector2(6, 4)) and data.call().openings.size() == 1 and data.call().lanterns.size() == 1 and data.call().roof.chimneys.size() == 1, "a 6 by 4 house with a window, a lantern and a chimney: %s" % at.call())
	side.lay_now()
	var side_stones := side.layout.stones.size()
	rig.right.tool = Hand.Tool.TREES
	rig.left.tool = Hand.Tool.FLOWERS
	var trackers := _track_hands()
	var hold := _holder(rig, trackers)
	var front := main.world.terrain.ground(12, -12) + Vector3.UP * 1.2
	var grip := func(s: StringName, on: bool) -> void:
		trackers[s].set_input(&"grip_click", on)
		await frames(3)
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), front)
	hold.call(&"left_hand", Vector3(-0.2, -0.4, -0.3), front)
	await frames(2)
	var height: float = house.layout.height
	await _laid(house)
	var foot := house.layout.samples[0].y
	await grip.call(&"right_hand", true)
	for i in 10:
		hold.call(&"right_hand", Vector3(0.2, -0.4 + 0.03 * (i + 1), -0.3), front)
		await frames(1)
	await grip.call(&"right_hand", false)
	await frames(4)
	var rise: float = data.call().rise
	check(rise >= 0.6 and data.call().height == height and at.call().size.is_equal_approx(Vector2(6, 4)), "one grip rising raises it %.1f m onto its plinth, as large and as tall" % rise)
	await _laid(house)
	await frames(2)
	check(is_equal_approx(house.layout.samples[0].y, foot + rise) and house.transform.is_equal_approx(Transform3D.IDENTITY), "it is laid that much higher, carried no more: %.2f to %.2f" % [foot, house.layout.samples[0].y])
	hold.call(&"right_hand", Vector3(0.2, -0.1, -0.3), front)
	await frames(1)
	await grip.call(&"right_hand", true)
	for i in 10:
		hold.call(&"right_hand", Vector3(0.2, -0.1 - 0.1 * (i + 1), -0.3), front)
		await frames(1)
	await grip.call(&"right_hand", false)
	await frames(4)
	check(data.call().rise == 0.0, "lowered, it comes back down to its ground, no lower: %.1f" % data.call().rise)
	await play([{"op": "press", "button": "dpad_down"}])
	check(is_equal_approx(data.call().rise, rise), "undo raises it again: %.1f" % data.call().rise)
	await play([{"op": "press", "button": "dpad_down"}])
	check(data.call().rise == 0.0, "and once more puts it down")
	await _laid(house)
	var before: Dictionary = data.call().duplicate(true)

	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), front)
	await frames(1)
	await grip.call(&"right_hand", true)
	hold.call(&"right_hand", Vector3(0.2, -0.25, -0.3), front)
	await frames(2)
	await grip.call(&"left_hand", true)
	check(tool.held == house and tool._holders.size() == 2 and is_equal_approx(house.layout.height, height), "the other hand's grip on it joins: %.1f m" % house.layout.height)
	Cues.pulsed.clear()
	for i in 20:
		hold.call(&"right_hand", Vector3(0.2 + 0.015 * (i + 1), -0.25, -0.3), front)
		await frames(1)
	check(_pulsed_both(Cues.Act.HOUSE_STRETCH, rig), "resizing it pulses in both hands, the still one too: %s" % Cues.pulsed)
	check(rig.left._holding and rig.right._holding, "both hands hold it")
	check(walls[-1] == house and world.state.walls[house.id].points == before.points, "nothing is sent while it is held")
	await grip.call(&"left_hand", false)
	await grip.call(&"right_hand", false)
	await frames(4)
	var wide: Dictionary = at.call()
	check(tool.held == null and is_equal_approx(wide.size.x, 10.5) and is_equal_approx(wide.size.y, 4.0) and is_equal_approx(data.call().height, height), "spreading the hands across its front stretches only its width: %s, %.1f m high" % [wide.size, data.call().height])
	check(absf(wide.center.x - wide.size.x * 0.5 - (12 - 3)) < 0.05, "the still hand's wall stays put; the house grows toward the moving hand: %s" % wide.center)
	await _laid(house)
	check(house.layout.laid_points.size() == 4 and house.roof.corners == house.layout.laid_points, "its roof covers the new walls")
	var window_at := func(d: Dictionary) -> float:
		var h := WallTool.house_of(d)
		var p := WallTool._loop_point(_points(d), d.openings[0].x)
		return (p - h.center).dot(Vector3.RIGHT.rotated(Vector3.UP, h.yaw)) / h.size.x
	var lantern_at := func(d: Dictionary) -> float:
		var h := WallTool.house_of(d)
		var p := WallTool._loop_point(_points(d), d.lanterns[0].x)
		return (p - h.center).dot(Vector3.RIGHT.rotated(Vector3.UP, h.yaw)) / h.size.x
	check(is_equal_approx(window_at.call(before), window_at.call(data.call())) and is_equal_approx(lantern_at.call(before), lantern_at.call(data.call())), "its window and inside lantern keep their places in proportion")
	check(data.call().lanterns[0].z == before.lanterns[0].z and is_equal_approx(data.call().lanterns[0].y, before.lanterns[0].y), "the lantern on its same face, as high")
	check(absf(data.call().roof.chimneys[0].x / before.roof.chimneys[0].x - 1.75) < 0.01, "its chimney moves out along the longer ridge: %s" % data.call().roof.chimneys[0])
	side.lay_now()
	check(side.layout.stones.size() < side_stones, "the wall it now meets lays nothing inside it: %d of %d stones" % [side.layout.stones.size(), side_stones])

	await play([{"op": "press", "button": "dpad_down"}])
	check(at.call().size.is_equal_approx(Vector2(6, 4)) and data.call().openings == before.openings and data.call().roof.chimneys == before.roof.chimneys, "undo puts its width, window and chimney back: %s" % at.call().size)
	side.lay_now()
	check(side.layout.stones.size() == side_stones, "and the wall it met whole again")
	await play([{"op": "press", "button": "A"}])
	check(is_equal_approx(at.call().size.x, 10.5), "redo stretches it again: %s" % at.call().size)

	var flank := main.world.terrain.ground(13, -12) + Vector3.UP * 1.2
	hold.call(&"right_hand", Vector3(0.1, -0.4, -0.25), flank)
	hold.call(&"left_hand", Vector3(0.12, -0.38, -0.55), flank)
	await frames(2)
	await grip.call(&"right_hand", true)
	await grip.call(&"left_hand", true)
	check(tool.held == house and tool._holders.size() == 2, "two grips take it again, the hands one behind the other")
	for i in 20:
		hold.call(&"left_hand", Vector3(0.12, -0.38, -0.55 - 0.02 * (i + 1)), flank)
		await frames(1)
	await grip.call(&"right_hand", false)
	await grip.call(&"left_hand", false)
	await frames(4)
	var deep: Dictionary = at.call()
	check(is_equal_approx(deep.size.x, 10.5) and deep.size.y > 7.0 and is_equal_approx(data.call().height, height), "hands along its flank stretch only its depth, past the 7 m it once stopped at: %s" % deep.size)

	await play([{"op": "press", "button": "dpad_down"}])
	await frames(4)
	check(is_equal_approx(at.call().size.y, 4.0), "undo takes the depth back: %s" % at.call().size)

	await play([
		{"op": "house", "round": true, "at": [4, -15], "size": [3.4, 3.4], "seconds": 0.3},
		{"op": "uncluttered"},
		{"op": "wait", "seconds": 0.3},
	])
	var tower := walls[-1]
	var face := main.world.terrain.ground(4, -13.3) + Vector3.UP * 1.5
	hold.call(&"right_hand", Vector3(0.2, -0.4, -0.3), face)
	hold.call(&"left_hand", Vector3(-0.2, -0.4, -0.3), face)
	await frames(2)
	var left: Transform3D = main.rig.left.global_transform
	var tree: Dictionary = main.flora_tool.flora.solid_hit(left.origin, -left.basis.z, left.origin.distance_to(face) + 2.0)
	if not tree.is_empty():
		var trunk: Flora.Plant = tree.plants[0]
		world._order({"op": "show", "plants": {trunk.group: PackedInt32Array(tree.plants.map(func(p: Flora.Plant) -> int: return p.index))}, "on": false}, world.me())
	var tall := tower.layout.height
	await grip.call(&"right_hand", true)
	await grip.call(&"left_hand", true)
	for i in 20:
		hold.call(&"left_hand", Vector3(-0.2 - 0.01 * (i + 1), -0.4, -0.3), face)
		await frames(1)
	await grip.call(&"right_hand", false)
	await grip.call(&"left_hand", false)
	await frames(4)
	var d: Dictionary = world.state.walls[tower.id]
	var round := WallTool.house_of(d)
	var off := Array(d.points).filter(func(p: Vector3) -> bool: return absf(Vector2(p.x - round.center.x, p.z - round.center.z).length() - round.size.x * 0.5) > 0.01)
	check(round.round and round.size.x > 5.0 and off.is_empty() and is_equal_approx(d.height, tall), "two hands spread a round tower's diameter, round and as tall: %s" % round.size)
	await play([{"op": "press", "button": "dpad_down"}])
	check(is_equal_approx(WallTool.house_of(world.state.walls[tower.id]).size.x, 3.4), "undo narrows it back")
	for t in trackers.values():
		XRServer.remove_tracker(t)


## Whether `act` has pulsed in both of the rig's hands since `Cues.pulsed` was cleared.
func _pulsed_both(act: Cues.Act, rig: Rig) -> bool:
	var by: Dictionary = Cues.pulsed.get(act, {})
	return by.get(rig.left.get_instance_id(), 0) > 0 and by.get(rig.right.get_instance_id(), 0) > 0


func _points(d: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.assign(Array(d.points))
	return out


func _laid(w: Wall) -> void:
	for i in 300:
		w.lay_now()
		if w.layout.laid_points == w.layout.points and w.layout.laid_rise == w.layout.rise:
			return
		await frames(1)


## Directive (verbatim): "Sometimes I want to draw a circular wall. Um, In that case, I don't think it makes sense to turn it into a building, when I- didn't want that"
func _a_loop_stays_a_wall(walls: Array[Wall]) -> void:
	var tool: WallTool = main.tool
	main.rig.right.tool = Hand.Tool.WALLS
	var m := tool.mason(main.rig.right)
	var before := walls.size()
	var ring: Array[Vector3] = []
	for i in 25:
		var a := TAU * i / 24.0
		ring.append(main.world.terrain.ground(-14.0 + cos(a) * 2.5, -12.0 + sin(a) * 2.5))
	tool.begin_stroke(m, ring[0])
	for p in ring:
		await frames(1)
		tool.extend_stroke(m, p)
	for i in 90:
		await frames(1)
		tool.extend_stroke(m, ring[-1])
	tool.end_stroke(m)
	await frames(4)
	check(walls.size() == before + 1, "a loop drawn and held closed builds one wall: %d" % (walls.size() - before))
	if walls.size() == before + 1:
		check(walls[-1].roof == null and not walls[-1].layout.closed, "and it stays a freestanding wall, roofless")


func _painted(flora: Flora, at: Vector3) -> Array:
	return flora.plants_near(at, 1.5).filter(func(p: Flora.Plant) -> bool: return p.group != 0)
