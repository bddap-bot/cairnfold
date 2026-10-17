extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _run() -> void:
	var d := {"a": Vector3.ZERO, "b": Vector3(0, 2, -4), "width": 1.2, "rail": "stone", "seed": 8}
	var stairs := StairLayout.new()
	stairs.build(d)
	check(stairs.kind == StairLayout.Kind.FLIGHT and stairs.treads.size() == 10, "two metres rise makes ten steps")
	check(is_equal_approx(stairs.treads[-1].y, 2.0), "last tread reaches target")
	for i in range(1, stairs.treads.size()):
		check(is_equal_approx(stairs.treads[i].y - stairs.treads[i - 1].y, 0.2), "equal rises")
	check(stairs.stones.size() > 30, "flight includes blocks and stone rails")
	for i in 30:
		var piece: Dictionary = stairs.stones[i]
		check(is_equal_approx(piece.xform.origin.y + piece.xform.basis.y.length() * 0.5, stairs.treads[i / 3].y), "blocks meet the tread top")
	_walkable(d)
	_walkable({"a": Vector3(1, 0.5, 2), "b": Vector3(-3, 0.5, -1), "width": 2.0, "rail": "none", "seed": 3})
	_walkable({"a": Vector3(2, 3.1, 0), "b": Vector3(-1, 0.2, 2.5), "width": 0.8, "rail": "wood", "seed": 4})
	check(is_nan(stairs.surface(Vector3(2, 1, -2))), "nothing to stand on beside the flight")
	check(is_nan(stairs.surface(Vector3(0, 1, 1))), "nothing to stand on before its foot")
	var first := stairs.stones.duplicate(true)
	stairs.build(d)
	check(stairs.stones == first, "same command lays identical stones")
	var swap := d.duplicate()
	swap.a = d.b
	swap.b = d.a
	stairs.build(swap)
	check(stairs.stones == first, "drawing downhill lays the same flight")
	d.b = Vector3(0, 3, -0.5)
	stairs.build(d)
	check(stairs.stones.size() == stairs.treads.size() + 2 and stairs.treads.size() > 2, "ladder has rungs and two stiles")
	check(stairs.kind == StairLayout.Kind.LADDER and stairs.stones.all(func(p): return p.kind == "rail"), "steep runs become wooden ladders")
	d.b = Vector3(0, 0, -3)
	d.rail = "wood"
	stairs.build(d)
	check(stairs.kind == StairLayout.Kind.LANDING, "level run becomes a landing")
	check(stairs.treads.all(func(p): return is_zero_approx(p.y)), "landing stays level")
	check(stairs.stones.any(func(p): return p.kind == "rail"), "wooden railing")
	check(Commands._stairs(d) != null, "valid stair command")
	for bad in [Vector3(NAN, 0, 0), Vector3(0, 0, -100), d.a]:
		var invalid := d.duplicate()
		invalid.b = bad
		check(Commands._stairs(invalid) == null, "reject invalid endpoint")
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var world: World = main.world
	d.a.y = 2.0
	d.b.y = 2.0
	var units_before := world.units.duplicate(true)
	main.stair_tool.begin(main.rig.right, d.a)
	main.stair_tool.extend(main.rig.right, d.b)
	check(world.state.stairs.is_empty(), "preview does not edit garden")
	main.stair_tool.end(main.rig.right)
	check(world.state.stairs.size() == 1, "tool command builds stairs")
	check(world.units != units_before, "stairs consume build budget")
	check(world.stairs.laying(), "stair assembly starts growing")
	world.stairs._process(0.01)
	check(world.stairs.laying(), "assembly remains partial at first")
	world.stairs._process(10.0)
	check(not world.stairs.laying(), "assembly finishes")
	var id: int = world.state.stairs.keys()[0]
	var hit: Dictionary = main.stair_tool.aim(Vector3(0, 5, -1), Vector3.DOWN)
	check(hit.get("stair", -1) == id, "tool targets a landing for a connected flight")
	check(is_equal_approx(main.rig.floor_under.call(Vector3(0, 3, -1)), 2.0), "a point over the landing stands on it")
	check(is_equal_approx(main.rig.floor_under.call(Vector3(0, 1, -1)), Terrain.height_at(0, -1)), "a point under the landing stands on the ground")
	main.rig.aim(Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), Vector3(0, 5, -1)))
	check(main.rig.aim_ground != null and is_equal_approx(main.rig.aim_ground.y, 2.0), "the teleport ray lands on the landing")
	main.rig.aim(Transform3D(Basis.looking_at(Vector3(0, -1, -1).normalized(), Vector3.UP), Vector3(0, 5, 2)), 0.9)
	check(main.rig.aim_ground != null and is_equal_approx(main.rig.aim_ground.y, 2.0), "short of the landing, the target floats over it, not the ground")
	main.rig.hide_markers()
	var cut: Dictionary = main.delete_tool.aim(Vector3(0, 5, -1), Vector3.DOWN)
	check(cut.get("stair", -1) == id, "eraser targets stairs")
	var snap := world.snapshot()
	world.undo()
	check(world.units == units_before, "undo refunds stair budget")
	check(world.state.stairs.is_empty() and world.stairs.layouts.is_empty(), "undo removes stairs")
	world.redo()
	check(world.state.stairs.size() == 1, "redo restores stairs")
	world.submit({"op": "wipe"})
	check(world.state.stairs.is_empty(), "wipe removes stairs")
	world.restore(snap)
	check(world.state.stairs.size() == 1, "snapshot restores stairs")
	main.delete_tool.press(self, Vector3(0, 5, -1), Vector3.DOWN)
	main.delete_tool.let_go(self)
	check(world.state.stairs.is_empty(), "eraser takes the whole landing")
	world.undo()
	check(world.state.stairs.size() == 1, "erased stairs return on undo")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Walking the centre line from one end to the other meets a tread everywhere, no step higher than a stair's rise,
## starting a step from the lower end and finishing level with the upper one.
func _walkable(d: Dictionary) -> void:
	var stairs := StairLayout.new()
	stairs.build(d)
	var low: Vector3 = d.a if d.a.y <= d.b.y else d.b
	var high: Vector3 = d.b if d.a.y <= d.b.y else d.a
	var flat := Vector3(high.x - low.x, 0, high.z - low.z)
	var last := low.y
	var steps := 200
	for i in steps + 1:
		var p := low + flat * (float(i) / steps)
		var y := stairs.surface(p)
		check(not is_nan(y), "a tread under every point of %s" % [d])
		check(absf(y - last) <= StairLayout.RISE + 0.001, "no step higher than a rise on %s" % [d])
		var off: Vector3 = p + flat.normalized().cross(Vector3.UP) * (d.width as float) * 0.45
		check(absf(stairs.surface(off) - y) <= StairLayout.RISE + 0.001, "a tread spans the width of %s" % [d])
		last = y
	check(is_equal_approx(last, high.y), "the treads reach the upper end of %s" % [d])
