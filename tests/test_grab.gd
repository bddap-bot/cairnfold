extends SceneTree

var failures := 0
var main: Node
var trackers: Array[XRControllerTracker] = []


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames() -> void:
	for i in 3:
		await process_frame


func _capture(name: String) -> void:
	if main.args.has("capture-dir"):
		await main.capture(name)


## What the garden holds and what any tool has under way, so a grip that made or started something shows.
## The garden and what each tool is in the middle of, but for the parts of the garden named in `apart`.
func _made(apart: Array = []) -> String:
	var busy := [main.tool.busy(), main.flora_tool.busy(), main.palette_tool.busy(), main.delete_tool.busy(), main.tool.house != null]
	var state: Dictionary = main.world.state.duplicate()
	for k in apart:
		state.erase(k)
	return var_to_str([state, main.world.palette.season, busy])


func _grip_lifts_the_wall_whatever_the_hand_holds(hand: Hand) -> void:
	var at := hand.global_transform
	for t in Hand.Tool.values():
		hand.tool = t
		hand.global_transform = at
		await _frames()
		var wall: Wall = main.tool.walls[0]
		var height := wall.layout.height
		Buttons.injected["right_hand/grip_click"] = true
		await _frames()
		_check(main.tool.mason(hand).lifting == wall and not main.ground_grab.busy(), "grip on the wall takes the wall, holding %s" % Hand.Tool.keys()[t])
		hand.position.y += 0.3
		await _frames()
		_check(wall.layout.height > height, "and lifts it, holding %s" % Hand.Tool.keys()[t])
		Buttons.injected.erase("right_hand/grip_click")
		await _frames()
		_check(main.tool.mason(hand).lifting == null, "release drops it, holding %s" % Hand.Tool.keys()[t])
		main.world.undo()
		await _frames()
	hand.tool = Hand.Tool.WALLS
	hand.global_transform = at


## Grip on a tree, whatever the hand holds, takes the tree, not the ground behind it: raised, it grows the tree; let
## go, the garden has it.
func _grip_grows_a_tree_whatever_the_hand_holds(hand: Hand) -> void:
	var at := hand.global_transform
	var flora: Flora = main.flora_tool.flora
	var spot := Terrain.ground(9, 8)
	main.world.submit({"op": "plant", "kind": "tree", "seed": 4, "at": spot})
	var g: int = main.world.seq
	var trunk: Flora.Plant = flora.groups[g][0]
	var crown := spot + Vector3.UP * flora.top_of(trunk) * 0.7
	for t in [Hand.Tool.TREES, Hand.Tool.WALLS, Hand.Tool.DELETE]:
		hand.tool = t
		hand.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD), crown + Vector3.BACK * 3.0)
		await _frames()
		Buttons.injected["right_hand/grip_click"] = true
		await _frames()
		_check(main.tool.mason(hand).growing == trunk and not main.ground_grab.busy(), "grip on a tree takes the tree, holding %s" % Hand.Tool.keys()[t])
		hand.position.y += 2.0
		await _frames()
		Buttons.injected.erase("right_hand/grip_click")
		await _frames()
		_check(main.tool.mason(hand).growing == null and main.world.state.groups[g].scale.get(0, 1.0) > 1.1, "raised and let go, it grows, holding %s" % Hand.Tool.keys()[t])
		main.world.undo()
		await _frames()
		_check(flora.scale_of(trunk) == 1.0, "an undo shrinks it back, holding %s" % Hand.Tool.keys()[t])
	main.world.undo()
	await _frames()
	hand.tool = Hand.Tool.WALLS
	hand.global_transform = at


## Grip on open ground, whatever the hand holds, takes the ground: up pulls a hill, down presses a hollow, and
## nothing the held tool makes is made or started.
func _grip_shapes_the_ground_and_makes_nothing(hand: Hand) -> void:
	var at := hand.global_transform
	for t in Hand.Tool.values():
		var name: String = Hand.Tool.keys()[t]
		for lift in [0.3, -0.3]:
			hand.tool = t
			hand.global_transform = at
			hand.global_basis = Basis.looking_at(Vector3(0, -0.6, -1))
			await _frames()
			var before := _made()
			var ground: Variant = Terrain.raycast(hand.global_position, -hand.global_basis.z)
			var g: Vector3 = ground
			Buttons.injected["right_hand/grip_click"] = true
			await _frames()
			_check(main.ground_grab.busy(), "grip takes the ground, holding %s" % name)
			_check(not hand._beam.visible and not hand._dot.visible, "the ground in hand hides the pointer, holding %s" % name)
			hand.position.y += lift
			await _frames()
			var moved := Terrain.height_at(g.x, g.z) - g.y
			_check(moved * lift > 0.0 and absf(moved) > absf(lift) * 0.5, "moving the hand %+.1f moves the ground %+.2f, holding %s" % [lift, moved, name])
			Buttons.injected.erase("right_hand/grip_click")
			await _frames()
			_check(not main.ground_grab.busy(), "release lets the ground go, holding %s" % name)
			_check(absf(Terrain.height_at(g.x, g.z) - g.y - moved) < 0.05, "the ground stays where it was left, holding %s" % name)
			_check(_made() == before, "grip makes nothing else, holding %s" % name)
			main.world.undo()
			await _frames()
			_check(absf(Terrain.height_at(g.x, g.z) - g.y) < 1e-3, "undo puts the ground back, holding %s" % name)
	hand.tool = Hand.Tool.WALLS
	hand.global_transform = at


## A pond is ground under water: a grip pointed at it takes its bed, and the water fills what the bed leaves.
func _grip_on_a_pond_moves_its_bed(hand: Hand) -> void:
	var at := hand.global_transform
	var water: Water = main.water
	hand.global_basis = Basis.looking_at(Vector3(1, -0.6, 0.5))
	var spot: Vector3 = Terrain.raycast(hand.global_position, -hand.global_basis.z)
	var d := Driver.new(main, [{"op": "dig", "x": spot.x, "z": spot.z, "seconds": 1.5}])
	main.add_child(d)
	await d.finished
	d.queue_free()
	hand.tool = Hand.Tool.FLOWERS
	await _frames()
	var pond := water.pond_at(spot.x, spot.z)
	_check(pond != null, "the dig holds a pond")
	for lift in [-0.2, 0.2]:
		var bed: Vector3 = Terrain.raycast(hand.global_position, -hand.global_basis.z)
		_check(bed.y < spot.y - 0.3, "the grip's ray reaches the pond's bed under the water, %.2f below the meadow" % (spot.y - bed.y))
		Buttons.injected["right_hand/grip_click"] = true
		await _frames()
		_check(main.ground_grab.busy(), "grip on the pond takes its bed")
		hand.position.y += lift
		await _frames()
		Buttons.injected.erase("right_hand/grip_click")
		await _frames()
		var moved := Terrain.height_at(bed.x, bed.z) - bed.y
		_check(moved * lift > 0.0, "moving the hand %+.1f moves the pond's bed %+.2f" % [lift, moved])
		await _frames()
		_check(water.pond_at(spot.x, spot.z) != null, "the pond still holds water after its bed moved %+.2f" % moved)
		main.world.undo()
		hand.position.y -= lift
		await _frames()
	main.world.undo()
	await _frames()
	hand.tool = Hand.Tool.WALLS
	hand.global_transform = at


func _grip(hand: Hand, down: bool) -> void:
	if down:
		Buttons.injected[hand.tracker + "/grip_click"] = true
	else:
		Buttons.injected.erase(hand.tracker + "/grip_click")


func _ground_ahead(hand: Hand, side: float) -> Vector3:
	hand.global_basis = Basis.looking_at(Vector3(side, -0.6, -1))
	return Terrain.raycast(hand.global_position, -hand.global_basis.z)


## Each hand's grip grabs on its own: two hands pull two pieces of ground at once, one up and one down, and each
## grab is its own undo step.
func _two_hands_grab_the_ground_at_once(rig: Rig) -> void:
	var left_at := rig.left.global_transform
	var right_at := rig.right.global_transform
	var a := _ground_ahead(rig.left, -1.0)
	var b := _ground_ahead(rig.right, 1.0)
	await _frames()
	_grip(rig.left, true)
	await _frames()
	_grip(rig.right, true)
	await _frames()
	_check(main.ground_grab.busy(rig.left) and main.ground_grab.busy(rig.right), "both grips hold the ground")
	rig.left.position.y += 0.3
	rig.right.position.y -= 0.3
	await _frames()
	var up := Terrain.height_at(a.x, a.z) - a.y
	var down := Terrain.height_at(b.x, b.z) - b.y
	_check(up > 0.15 and down < -0.15, "both pieces follow their own hands at once, %+.2f and %+.2f" % [up, down])
	_grip(rig.left, false)
	await _frames()
	_check(not main.ground_grab.busy(rig.left) and main.ground_grab.busy(rig.right), "letting go of one keeps the other")
	_check(absf(Terrain.height_at(a.x, a.z) - a.y - up) < 0.05 and absf(Terrain.height_at(b.x, b.z) - b.y - down) < 0.05, "and leaves both where they were")
	_grip(rig.right, false)
	await _frames()
	main.world.undo()
	await _frames()
	_check(absf(Terrain.height_at(b.x, b.z) - b.y) < 1e-3 and absf(Terrain.height_at(a.x, a.z) - a.y - up) < 0.05, "undo puts back the last grab alone")
	main.world.undo()
	await _frames()
	_check(absf(Terrain.height_at(a.x, a.z) - a.y) < 1e-3, "and undo again the first")
	rig.left.global_transform = left_at
	rig.right.global_transform = right_at
	await _frames()


## Holding the ground in one hand while the other pulls a wall up: both move, each its own step.
func _one_hand_holds_the_ground_while_the_other_lifts_a_wall(rig: Rig) -> void:
	var left_at := rig.left.global_transform
	var right_at := rig.right.global_transform
	var g := _ground_ahead(rig.left, -1.0)
	await _frames()
	_grip(rig.left, true)
	await _frames()
	var wall: Wall = main.tool.walls[0]
	var height := wall.layout.height
	_grip(rig.right, true)
	await _frames()
	_check(main.ground_grab.busy(rig.left) and main.tool.mason(rig.right).lifting == wall, "the left grip holds the ground and the right the wall")
	rig.left.position.y += 0.3
	rig.right.position.y += 0.3
	await _frames()
	var raised := Terrain.height_at(g.x, g.z) - g.y
	_check(raised > 0.15 and wall.layout.height > height, "both follow their hands, ground %+.2f, wall %.2f to %.2f" % [raised, height, wall.layout.height])
	_grip(rig.right, false)
	_grip(rig.left, false)
	await _frames()
	main.world.undo()
	main.world.undo()
	await _frames()
	_check(absf(Terrain.height_at(g.x, g.z) - g.y) < 1e-3 and is_equal_approx(main.tool.walls[0].layout.height, height), "two undos put both back")
	rig.left.global_transform = left_at
	rig.right.global_transform = right_at
	await _frames()


## A grip on the wall the other hand holds takes nothing, not the wall and not the ground behind it.
func _a_wall_held_by_one_hand_is_not_taken_by_the_other(rig: Rig) -> void:
	var wall: Wall = main.tool.walls[0]
	_grip(rig.right, true)
	await _frames()
	_check(main.tool.mason(rig.right).lifting == wall, "the right grip takes the wall")
	_grip(rig.left, true)
	await _frames()
	_check(main.tool.mason(rig.left).lifting == null and not main.ground_grab.busy(rig.left) and main.sky_tool.holder == null, "the left grip on the same wall takes nothing")
	_check(main.tool.mason(rig.right).lifting == wall, "and the right keeps it")
	_grip(rig.left, false)
	_grip(rig.right, false)
	await _frames()


## One hand's grab leaves the other free to use its tool: the left holds the ground while the right draws a wall.
func _a_grab_leaves_the_other_hand_its_tool(rig: Rig) -> void:
	var left_at := rig.left.global_transform
	var right_at := rig.right.global_transform
	var g := _ground_ahead(rig.left, -1.0)
	_ground_ahead(rig.right, 1.0)
	rig.right.tool = Hand.Tool.WALLS
	await _frames()
	_grip(rig.left, true)
	await _frames()
	rig.left.position.y += 0.3
	Buttons.injected["right_hand/trigger_click"] = true
	await _frames()
	_check(main.ground_grab.busy(rig.left) and main.tool.mason(rig.right).stroke != null, "the right draws a wall while the left holds the ground")
	Buttons.injected.erase("right_hand/trigger_click")
	_grip(rig.left, false)
	await _frames()
	main.world.undo()
	await _frames()
	_check(absf(Terrain.height_at(g.x, g.z) - g.y) < 1e-3, "undo puts the ground back")
	rig.left.global_transform = left_at
	rig.right.global_transform = right_at
	await _frames()


## A grip into an arch takes the arch, not the wall; the other hand's grip on it joins, and the pair pulled apart
## widen it, its head rising with it, as one build command and one undo step.
func _two_hands_stretch_an_opening(rig: Rig) -> void:
	var at_right := rig.right.global_transform
	var at_left := rig.left.global_transform
	var wall: Wall = main.tool.walls[0]
	var world: World = main.world
	world.submit({"op": "reshape", "of": "walls", "id": wall.id, "data": {"height": 6.0}})
	main.fitting_tool.fit({"what": "opening", "wall": wall, "s": 3.0, "y": 0.0, "style": WallLayout.DoorStyle.ARCHWAY})
	for i in 30:
		await process_frame
	_check(world.state.walls[wall.id].openings.size() == 1 and wall.layout.archways().size() == 1, "the tall wall opens a doorway arch")
	var f := wall.layout.frame_at(3.0)
	var into: Vector3 = f.point + Vector3.UP * 1.0
	var out: Vector3 = f.tangent.cross(Vector3.UP) * 2.0
	var head: float = wall.layout.apertures[0].head
	rig.right.global_transform = Transform3D(Basis.looking_at(-out), into + out + f.tangent * 0.2)
	rig.left.global_transform = Transform3D(Basis.looking_at(-out), into + out - f.tangent * 0.2)
	await _frames()
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(main.tool.mason(rig.right).growing is WallTool.OpeningGrip and main.tool.mason(rig.right).lifting == null, "a grip into the arch takes the arch, not the wall")
	Buttons.injected["left_hand/grip_click"] = true
	await _frames()
	_check(main.tool.mason(rig.left).partner == main.tool.mason(rig.right), "the other hand's grip on it joins the first")
	rig.left.global_position -= f.tangent * 0.4
	for i in 10:
		await process_frame
	var shown: Dictionary = wall.layout.apertures[0] if wall.layout.apertures.size() == 1 else {}
	_check(not shown.is_empty() and absf(shown.size - 2.0) < 0.05 and shown.head > head * 1.8, "the hands pulled twice as far apart show it twice as big, its head as high: %s" % shown)
	Buttons.injected.erase("left_hand/grip_click")
	await _frames()
	_check(main.tool.mason(rig.right).growing is WallTool.OpeningGrip and Array(world.state.walls[wall.id].openings)[0].w == 1.0, "one hand let go, the other still holds it and the garden waits")
	var steps: int = world.stacks[world.me()].undo.size()
	Buttons.injected.erase("right_hand/grip_click")
	for i in 30:
		await process_frame
	var kept: Vector4 = Array(world.state.walls[wall.id].openings)[0]
	_check(absf(kept.w - 2.0) < 0.05 and world.stacks[world.me()].undo.size() == steps + 1, "let go, the garden keeps the grand arch, one undo step: %s" % kept)
	world.undo()
	for i in 30:
		await process_frame
	_check(Array(world.state.walls[wall.id].openings)[0].w == 1.0 and is_equal_approx(wall.layout.apertures[0].head, head), "undo makes it a doorway again")
	world.undo()
	world.undo()
	rig.right.global_transform = at_right
	rig.left.global_transform = at_left
	await _frames()


func _run() -> void:
	var d := Driver.new(main, [{"op": "wall", "points": [[-3, 0], [3, 0]], "seconds": 0.2}])
	main.add_child(d)
	await d.finished
	d.queue_free()
	var rig: Rig = main.rig
	rig.left.tool = Hand.Tool.FLOWERS
	for hand in rig.hands:
		var tracker := XRControllerTracker.new()
		tracker.name = hand.tracker
		tracker.type = XRServer.TRACKER_CONTROLLER
		tracker.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		XRServer.add_tracker(tracker)
		trackers.append(tracker)
		var at := rig.head.global_position + Vector3(-0.35 if hand == rig.left else 0.35, -0.4, -0.5)
		var target := Vector3(at.x, Terrain.height_at(at.x, 0) + 1.0, 0)
		hand.global_transform = Transform3D(Basis.looking_at(target - at), at)
	await _frames()
	var hand := rig.right
	_check(hand._beam.visible and hand._dot.visible, "idle hand points at the wall")
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(main.tool.mason(hand).lifting != null, "grip takes the wall")
	_check(not hand._beam.visible and not hand._dot.visible, "wall grab hides beam and dot")
	hand.point(Vector3.ZERO, Color.WHITE)
	_check(not hand._beam.visible and not hand._dot.visible, "a later tool cannot redraw a held hand pointer")
	_check(rig.left._beam.visible, "other hand can still point")
	await _capture("grab")
	var height: float = main.tool.walls[0].layout.height
	hand.rotate_x(0.2)
	await _frames()
	_check(is_equal_approx(main.tool.walls[0].layout.height, height), "rotating a held wall does not lift it")
	hand.position.y += 0.2
	await _frames()
	_check(main.tool.walls[0].layout.height > height, "translating the hand lifts the wall")
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	_check(main.tool.mason(hand).lifting == null, "release drops the wall")
	_check(hand._beam.visible, "pointer returns on release")
	await _capture("released")
	await _grip_lifts_the_wall_whatever_the_hand_holds(hand)
	await _grip_grows_a_tree_whatever_the_hand_holds(hand)
	await _grip_shapes_the_ground_and_makes_nothing(hand)
	await _grip_on_a_pond_moves_its_bed(hand)
	await _two_hands_grab_the_ground_at_once(rig)
	await _one_hand_holds_the_ground_while_the_other_lifts_a_wall(rig)
	await _a_wall_held_by_one_hand_is_not_taken_by_the_other(rig)
	await _a_grab_leaves_the_other_hand_its_tool(rig)
	await _two_hands_stretch_an_opening(rig)
	hand.tool = Hand.Tool.POND
	hand.global_basis = Basis.looking_at(Vector3(0, -0.6, -1))
	var made := _made(["ponds"])
	var heights := Terrain.read(Terrain.ALL)
	Buttons.injected["right_hand/trigger_click"] = true
	await _frames()
	_check(_made(["ponds"]) == made and Terrain.read(Terrain.ALL) == heights, "the pond tool's trigger on the meadow never shapes the ground, only fills what its hollows hold")
	_check(hand._beam.visible and hand._dot.visible, "the pond tool keeps its pointer")
	Buttons.injected.erase("right_hand/trigger_click")
	hand.tool = Hand.Tool.WALLS
	await _frames()
	var sky: SkyTool = main.sky_tool
	var time: float = main.look.time
	var axis := Daylight.RISE.cross(Daylight.ARC_UP)
	var up := Daylight.toward_sun(time).rotated(axis, 0.2)
	hand.global_basis = Basis.looking_at(up)
	Buttons.injected["right_hand/grip_click"] = true
	await _frames()
	_check(sky.holder == hand, "grip on open sky takes the sky")
	_check(hand._beam.visible, "the pointer stays while it turns the sky")
	hand.position += -Daylight.RISE * 0.3
	await _frames()
	_check(is_equal_approx(main.look.time, time), "moving the hand without turning its aim leaves the sky")
	hand.global_basis = Basis.looking_at(up.rotated(axis, 0.2))
	await _frames()
	_check(absf(Daylight.angle(main.look.time) - Daylight.angle(time) - 0.2) < 1e-3, "turning the pointer turns the sky as far")
	var left := rig.left
	left.global_basis = Basis.looking_at(up)
	Buttons.injected["left_hand/grip_click"] = true
	await _frames()
	_check(sky.holder == hand, "the other hand's grip on the sky takes nothing")
	Buttons.injected.erase("left_hand/grip_click")
	Buttons.injected.erase("right_hand/grip_click")
	await _frames()
	_check(sky.holder == null, "release lets the sky go")
	Hand.injected_sticks.clear()
	Buttons.injected.clear()
	await _frames()
	for tracker in trackers:
		XRServer.remove_tracker(tracker)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
