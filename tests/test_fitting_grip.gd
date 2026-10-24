extends "res://../tests/support/suite.gd"

## A grip carries a placed fitting along the surface it stands on and sets it where let go, one reshape and one undo step:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_fitting_grip.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _lay() -> void:
	for w: Wall in main.tool.walls:
		w.lay_now()
	main.world.decorations.sync()


func _target(w: Wall, what: String) -> Dictionary:
	for t in FittingTool.targets(w):
		if t.what == what:
			return t
	return {}


func _decoration(id: int) -> Dictionary:
	for t in main.world.decorations.targets():
		if t.decoration == id:
			return t
	return {}


func _steps() -> int:
	return main.world.stacks.get(main.world.me(), {"undo": []}).undo.size()


## One hand grips `target` from a metre off, moves `path` (each a move from where it gripped) turning `turn` at the end,
## and lets go; the build command it sent, as the garden took it.
func _carry(target: Dictionary, path: Array, turn := 0.0) -> void:
	var tool: WallTool = main.tool
	var m := tool.mason(main.rig.right)
	var at: Vector3 = target.bounds.get_center()
	var from := Transform3D(Basis(), at + Vector3(0, 0, 1.0))
	var grip := tool._fitting_grip(target)
	check(grip != null, "a grip takes the %s" % target.what)
	if grip == null:
		return
	tool.begin_grow(m, grip, from, at)
	check(m.growing is FittingGrip and tool.busy(main.rig.right) and tool.held == null, "a grip on the %s holds it, not its build" % target.what)
	for i in path.size():
		var b := Basis(Vector3.UP, turn) if i == path.size() - 1 else Basis()
		m.sizing.follow.call(m, Transform3D(b, from.origin + path[i]))
	tool.end_grow(m)
	_lay()


func _run() -> void:
	main.world.bounded = false
	await play([
		{"op": "wall", "points": [[-6, 0], [6, 0]], "seconds": 0.2},
		{"op": "house", "at": [0, 12], "size": [7, 5], "seconds": 0.2},
	])
	var world: World = main.world
	var tool: WallTool = main.tool
	var fit: FittingTool = main.fitting_tool
	var wall: Wall = tool.walls[0]
	var house: Wall = tool.walls[1]
	world.submit({"op": "reshape", "of": "walls", "id": wall.id, "data": {"height": 4.0}})
	_lay()
	var s0 := wall.layout.length() * 0.5
	var high := WallLayout.DOOR_SILL + WallLayout.WINDOW_TALL * 0.5 + 0.4
	for t in [
		{"what": "opening", "wall": wall, "s": s0 - 2.0, "y": high, "style": WallLayout.Family.COTTAGE},
		{"what": "opening", "wall": wall, "s": s0 - 4.2, "y": 0.0, "style": WallLayout.Family.COTTAGE},
		{"what": "opening", "wall": wall, "s": s0 + 3.8, "y": 0.0, "style": WallLayout.Family.ARCHWAY},
		{"what": "lantern", "wall": wall, "s": s0 + 0.5, "y": 1.5, "side": 1.0},
		{"what": "flag", "wall": wall, "s": s0},
		{"what": "chimney", "wall": house, "at": Vector2(1.5, 0.8)},
		{"what": "dormer", "wall": house, "at": Vector2(-1.2, 1.4)},
	]:
		check(fit.fit(t), "%s placed" % t.what)
		_lay()
	var openings := func() -> Array: return Array(world.state.walls[wall.id].openings)
	check(openings.call().size() == 3 and wall.layout.apertures.size() == 3, "a window, a door and an arch stand: %s" % [openings.call()])
	var tangent: Vector3 = wall.layout.frame_at(s0).tangent

	var window: Vector4 = openings.call()[0]
	var steps := _steps()
	var target := _target(wall, "opening")
	for t in FittingTool.targets(wall):
		if t.what == "opening" and t.value == window:
			target = t
	_carry(target, [tangent * 0.5, tangent * 1.0 + Vector3.UP * 0.6])
	var now: Vector4 = openings.call()[0]
	check(absf(now.x - (window.x + 1.0)) < 0.06 and absf(now.y - (window.y + 0.6)) < 0.06 and now.z == window.z and now.w == window.w, "one hand slides a window along its wall and up it: %s from %s" % [now, window])
	check(_steps() == steps + 1, "set as one undo step")
	check(wall.layout.apertures.size() == 3 and wall.layout.apertures.any(func(o: Dictionary) -> bool: return not o.door and absf(o.s - now.x) < 0.01), "the wall opens it where it was set")
	world.undo()
	_lay()
	check(openings.call()[0] == window, "undo puts the window back")

	var door: Vector4 = openings.call()[1]
	for t in FittingTool.targets(wall):
		if t.what == "opening" and t.value == door:
			target = t
	_carry(target, [tangent * 0.6 + Vector3.UP * 1.0])
	now = openings.call()[1]
	check(absf(now.x - (door.x + 0.6)) < 0.06 and now.y == door.y, "a door slides along its wall and stays at its floor: %s from %s" % [now, door])
	world.undo()
	_lay()

	for t in FittingTool.targets(wall):
		if t.what == "opening" and t.value == window:
			target = t
	var path := []
	for i in 12:
		path.append(tangent * 0.5 * (i + 1))
	_carry(target, path)
	now = openings.call()[0]
	var arch: Vector4 = openings.call()[2]
	check(now.x > window.x + 0.5 and now.x < arch.x - 0.5 and openings.call()[2] == arch and wall.layout.apertures.size() == 3, "a window carried into an arch stops at the last place it opens on its own: %s, the arch at %.2f" % [now, arch.x])
	check(wall.layout.opening_fits(now, wall.layout.openings.filter(func(o: Vector4) -> bool: return o != now)), "and fits where it stopped")
	world.undo()
	_lay()

	var tall: Vector4 = openings.call()[0]
	for t in FittingTool.targets(wall):
		if t.what == "opening" and t.value == tall:
			target = t
	_carry(target, [Vector3.UP * 6.0])
	check(openings.call()[0] == tall and _steps() == steps, "a window pushed past the wall's top stays where it last fit, and nothing is sent")

	var lantern: Vector3 = world.state.walls[wall.id].lanterns[0]
	_carry(_target(wall, "lantern"), [tangent * -0.7 + Vector3.UP * 0.5])
	var lit: Vector3 = world.state.walls[wall.id].lanterns[0]
	check(absf(lit.x - (lantern.x - 0.7)) < 0.06 and absf(lit.y - (lantern.y + 0.5)) < 0.06 and lit.z == lantern.z, "a lantern slides along and up its wall face: %s from %s" % [lit, lantern])
	world.undo()
	_lay()

	var flag: float = world.state.walls[wall.id].flags[0]
	_carry(_target(wall, "flag"), [tangent * 1.2 + Vector3.UP * 2.0])
	check(absf(world.state.walls[wall.id].flags[0] - (flag + 1.2)) < 0.06, "a flag slides along the wall top: %.2f from %.2f" % [world.state.walls[wall.id].flags[0], flag])
	world.undo()
	_lay()

	var r := house.roof.frame()
	var chimney: Vector2 = world.state.walls[house.id].roof.chimneys[0]
	_carry(_target(house, "chimney"), [r.along * 0.8])
	var moved: Vector2 = world.state.walls[house.id].roof.chimneys[0]
	check(absf(moved.x - (chimney.x + 0.8)) < 0.06 and is_equal_approx(moved.y, chimney.y), "a chimney moves over its roof: %s from %s" % [moved, chimney])
	world.undo()
	_lay()

	var dormer: Vector2 = world.state.walls[house.id].roof.dormers[0]
	_carry(_target(house, "dormer"), [-r.along * 0.6])
	moved = world.state.walls[house.id].roof.dormers[0]
	check(absf(moved.x - (dormer.x - 0.6)) < 0.06, "a dormer moves over its roof: %s from %s" % [moved, dormer])
	check(house.roof.dormers.has(moved), "and the roof opens it there")
	world.undo()
	_lay()
	_carry(_target(house, "dormer"), [r.along * 1.4, r.along * 2.7])
	check(world.state.walls[house.id].roof.chimneys[0] == chimney and house.roof.dormer_fits(world.state.walls[house.id].roof.dormers[0], []), "a dormer carried at the chimney stops clear of it")
	world.undo()
	_lay()

	var before: Array = world.state.decorations.keys()
	fit.fit(fit.aim(Hand.Tool.DECORATIONS, Vector3(0.5, 1.8, 13.0), (Vector3(1.0, 0.0, 11.8) - Vector3(0.5, 1.8, 13.0)).normalized()))
	fit.fit({"what": "decoration", "mount": "ground", "point": Terrain.ground(4.0, -4.0), "wall": null, "s": 0.0, "side": 1.0, "turn": 0.0})
	fit.fit({"what": "decoration", "mount": "foundation", "wall": house, "s": 3.0, "side": 1.0, "point": house.layout.point_at(3.0), "turn": 0.0})
	var added: Array = world.state.decorations.keys().filter(func(k: int) -> bool: return not k in before)
	_lay()
	check(added.size() == 3, "a chair, a ground piece and one at the house's foot placed: %s" % [added])
	if added.size() != 3:
		_done()
		return
	var chair: int = added[0]
	var was: Dictionary = world.state.decorations[chair].duplicate()
	var node: Node3D = world.decorations.nodes[chair]
	var p0 := node.position
	var tool_m := tool.mason(main.rig.right)
	var grip := tool._fitting_grip(_decoration(chair))
	var from := Transform3D(Basis(), p0 + Vector3(0, 0.5, 0.8))
	tool.begin_grow(tool_m, grip, from, p0)
	tool_m.sizing.follow.call(tool_m, Transform3D(Basis(Vector3.UP, 0.5), from.origin + Vector3(0.6, 0.4, -0.3)))
	check(world.decorations.nodes[chair] == node and node.position.distance_to(p0 + Vector3(0.6, 0, -0.3)) < 0.06, "a held chair's node moves across its floor, nothing laid again: %s from %s" % [node.position, p0])
	check(world.state.decorations[chair] == was, "nothing is sent while it is held")
	tool.end_grow(tool_m)
	_lay()
	var set_at: Dictionary = world.state.decorations[chair]
	node = world.decorations.nodes[chair]
	check(node.position.distance_to(p0 + Vector3(0.6, 0, -0.3)) < 0.06 and absf(node.position.y - house.layout.floor_y) < 0.01, "let go, the chair stands where it was carried, on its floor: %s" % node.position)
	check(absf(angle_difference(was.turn, set_at.turn) - snappedf(0.5, FittingGrip.TURN_STEP)) < 0.001 and set_at.style == was.style and set_at.seed == was.seed, "and turned with the hand: %.3f from %.3f" % [set_at.turn, was.turn])
	world.undo()
	_lay()
	check(world.state.decorations[chair] == was, "undo puts the chair back")

	var stone: int = added[1]
	var ground_was: Dictionary = world.state.decorations[stone].duplicate()
	_carry(_decoration(stone), [Vector3(-1.0, 0.3, 0.5)], 1.0)
	var on_ground: Dictionary = world.state.decorations[stone]
	check(Vector2(on_ground.at.x, on_ground.at.z).distance_to(Vector2(ground_was.at.x - 1.0, ground_was.at.z + 0.5)) < 0.06 and not is_equal_approx(on_ground.turn, ground_was.turn), "a ground piece moves across the ground and turns: %s" % [on_ground])
	world.undo()
	_lay()

	var foot: int = added[2]
	var foot_was: Dictionary = world.state.decorations[foot].duplicate()
	var along: Vector3 = house.layout.frame_at(foot_was.s).tangent
	_carry(_decoration(foot), [along * 0.8 + Vector3.UP * 0.5], 1.0)
	var at_foot: Dictionary = world.state.decorations[foot]
	check(absf(at_foot.s - (foot_was.s + 0.8)) < 0.06 and at_foot.side == foot_was.side and at_foot.turn == foot_was.turn, "a piece at the house's foot slides along the wall: %s" % [at_foot])
	world.undo()
	_lay()

	var outside := {"op": "reshape", "of": "decorations", "id": chair, "data": {"at": Vector3(0.2, 0.0, -0.3), "turn": 1.0}}
	check(not Commands.clean(outside, world.state, false).is_empty(), "a peer takes a carried decoration's place and turn")
	for bad in [{"wall": -1}, {"side": -1.0}, {"at": Vector3(INF, 0, 0)}, {"seed": 3}]:
		check(Commands.clean({"op": "reshape", "of": "decorations", "id": chair, "data": bad}, world.state, false).is_empty(), "a peer refuses a decoration reshape of %s" % [bad])
	var flags := PackedFloat32Array([flag + 1.0])
	check(not Commands.clean({"op": "reshape", "of": "walls", "id": wall.id, "data": {"flags": flags}}, world.state, false).is_empty(), "a peer takes a carried flag")

	await _real_grip(wall)
	_done()


## The grip button, pressed with the hand pointing at a lantern, takes the lantern rather than its wall; a second hand's
## grip on it does nothing, a lantern having no size.
func _real_grip(wall: Wall) -> void:
	var world: World = main.world
	var hand: Hand = main.rig.right
	var other: Hand = main.rig.left
	var lantern: Vector3 = world.state.walls[wall.id].lanterns[0]
	var at: Vector3 = _target(wall, "lantern").bounds.get_center()
	for h in [hand, other]:
		h.held_still = true
		h.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, -1)), at + Vector3(0.1 if h == hand else -0.1, 0, 1.0))
	for i in 3:
		await process_frame
	Buttons.injected["right_hand/grip_click"] = true
	for i in 3:
		await process_frame
	check(main.tool.mason(hand).growing is FittingGrip and main.tool.held == null, "the grip button takes the lantern, not its wall")
	Buttons.injected["left_hand/grip_click"] = true
	for i in 3:
		await process_frame
	check(main.tool.mason(other).growing == null and main.tool.mason(hand).partner == null, "the other hand's grip on a lantern does not size it")
	Buttons.injected.erase("left_hand/grip_click")
	hand.global_position += Vector3(-0.6, 0.3, 0)
	for i in 3:
		await process_frame
	Buttons.injected.erase("right_hand/grip_click")
	for i in 3:
		await process_frame
	var now: Vector3 = world.state.walls[wall.id].lanterns[0]
	check(absf(now.x - lantern.x) > 0.4 and absf(now.y - (lantern.y + 0.3)) < 0.06, "let go, the lantern hangs where the hand took it: %s from %s" % [now, lantern])
	for h in [hand, other]:
		h.held_still = false


func _done() -> void:
	finish()
