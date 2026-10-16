extends SceneTree

## Headless checks of ponds: godot4 --headless --path game --script ../tests/test_water.gd

const SIDE := 21
const WINDOW := Rect2i(0, 0, SIDE, SIDE)

var failures := 0


func _initialize() -> void:
	_bowl_fills_to_below_its_rim()
	_water_spills_at_the_lowest_rim_point()
	_seed_off_the_bottom_still_fills()
	_neighbouring_hollows_fill_as_one()
	_spilling_into_a_draining_hollow_stops_at_the_rim()
	_shore_is_the_dry_ring_around_the_water()
	_open_ground_holds_no_pond()
	_shallow_basin_holds_no_pond()
	_check((load("res://src/water.gdshader") as Shader).code.contains("ripples[%d]" % PondWater.RIPPLES), "the shader takes every ripple slot")
	await _ponds_in_the_glade()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _grid(height: Callable) -> PackedFloat32Array:
	var g := PackedFloat32Array()
	for j in SIDE:
		for i in SIDE:
			g.append(height.call(i, j))
	return g


## Rises `slope` per point out to a rim `rim` high at radius `r` around (cx, cz), then falls gently away.
static func _bowl(i: int, j: int, cx := 10, cz := 10, slope := 0.3, r := 5.0) -> float:
	var d := Vector2(i - cx, j - cz).length()
	return d * slope if d < r else r * slope - (d - r) * 0.02


func _bowl_fills_to_below_its_rim() -> void:
	var g := _grid(_bowl)
	var p := PondLayout.fill(g, WINDOW, Vector2i(10, 10))
	_check(p != null, "a bowl holds a pond")
	if p == null:
		return
	_check(p.level <= 1.5 - PondLayout.FREEBOARD and p.level > 1.35, "the level sits just under the rim, %.3f" % p.level)
	_check(p.bottom == Vector2i(10, 10) and is_equal_approx(p.depth, p.level), "the bottom is the bowl's lowest point")
	var lo := Vector2i(SIDE, SIDE)
	var hi := Vector2i(-1, -1)
	for c in p.cells:
		_check(g[c.y * SIDE + c.x] < p.level, "every wet point is under the water")
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	_check(p.cells.size() > 50, "the pond covers the bowl, %d points" % p.cells.size())
	_check(p.box == Rect2i(lo, hi - lo + Vector2i.ONE), "the box is exactly the wet points' extent")


func _water_spills_at_the_lowest_rim_point() -> void:
	var notched := func(i: int, j: int) -> float:
		if j != 10 or i <= 10:
			return _bowl(i, j)
		return minf(_bowl(i, j), 0.9) if i < 16 else 0.5
	var p := PondLayout.fill(_grid(notched), WINDOW, Vector2i(10, 10))
	_check(p != null and absf(p.level - (0.9 - PondLayout.FREEBOARD)) < 1e-4, "a notch in the rim sets the level, %s" % (p.level if p else "no pond"))


func _seed_off_the_bottom_still_fills() -> void:
	var tilted := func(i: int, j: int) -> float: return _bowl(i, j) + i * 0.05
	var p := PondLayout.fill(_grid(tilted), WINDOW, Vector2i(11, 9))
	_check(p != null, "a seed beside the bottom of a tilted bowl still fills it")
	var q := PondLayout.fill(_grid(tilted), WINDOW, Vector2i(10, 10))
	_check(p != null and q != null and p.bottom == q.bottom, "seeds in one basin find the same bottom")
	var flat := func(i: int, j: int) -> float: return maxf(_bowl(i, j), 0.6)
	var a := PondLayout.fill(_grid(flat), WINDOW, Vector2i(9, 9))
	var b := PondLayout.fill(_grid(flat), WINDOW, Vector2i(11, 11))
	_check(a != null and b != null and a.bottom == b.bottom, "seeds on a flat floor name the same bottom")


func _neighbouring_hollows_fill_as_one() -> void:
	var two := func(i: int, j: int) -> float: return minf(_bowl(i, j, 7, 10), _bowl(i, j, 13, 10) - 0.2)
	var g := _grid(two)
	var a := PondLayout.fill(g, WINDOW, Vector2i(7, 10))
	var b := PondLayout.fill(g, WINDOW, Vector2i(13, 10))
	_check(a != null and b != null and a.bottom == b.bottom and a.bottom == Vector2i(13, 10), "seeds in either hollow find the deeper one's bottom")
	if a == null:
		return
	_check(a.level > 0.7 + PondLayout.FREEBOARD, "the water rises over the ridge between them, level %.2f" % a.level)
	_check(Vector2i(7, 10) in a.cells and Vector2i(13, 10) in a.cells, "and fills both hollows")


func _spilling_into_a_draining_hollow_stops_at_the_rim() -> void:
	var leaky := func(i: int, j: int) -> float:
		var b := minf(_bowl(i, j, 7, 10), _bowl(i, j, 13, 10) - 0.2)
		return minf(b, 0.4) if j == 10 and i >= 13 else b
	var p := PondLayout.fill(_grid(leaky), WINDOW, Vector2i(7, 10))
	_check(p != null and not Vector2i(13, 10) in p.cells and p.level < 0.7, "water overflowing into a hollow that drains stays in its own, %s" % (p.level if p else "no pond"))


func _shore_is_the_dry_ring_around_the_water() -> void:
	var g := _grid(_bowl)
	var p := PondLayout.fill(g, WINDOW, Vector2i(10, 10))
	var wet := {}
	for c in p.cells:
		wet[c] = true
	var ring := {}
	for s in p.shore:
		_check(not wet.has(s) and g[s.y * SIDE + s.x] >= p.level, "a shore point is dry")
		ring[s] = true
	for c in p.cells:
		for o in PondLayout.AROUND:
			if not wet.has(c + o) and not ring.has(c + o):
				_check(false, "dry point %s beside the water is not shore" % (c + o))
				return


func _open_ground_holds_no_pond() -> void:
	_check(PondLayout.fill(_grid(func(i: int, j: int) -> float: return i * 0.05), WINDOW, Vector2i(10, 10)) == null, "a slope holds nothing")
	_check(PondLayout.fill(_grid(func(i: int, j: int) -> float: return Vector2(i - 10, j - 10).length() * 0.3), WINDOW, Vector2i(10, 10)) == null, "a basin wider than the window holds nothing")
	for edge in [Vector2i(3, 10), Vector2i(17, 10), Vector2i(10, 17)]:
		var cut := func(i: int, j: int) -> float: return _bowl(i, j, edge.x, edge.y)
		_check(PondLayout.fill(_grid(cut), WINDOW, edge) == null, "a bowl cut by the window's edge near %s holds nothing" % edge)


func _shallow_basin_holds_no_pond() -> void:
	var rim := PondLayout.FREEBOARD + PondLayout.MIN_DEPTH * 0.6
	var shallow := func(i: int, j: int) -> float: return _bowl(i, j, 10, 10, rim / 4.0, 4.0)
	_check(PondLayout.fill(_grid(shallow), WINDOW, Vector2i(10, 10)) == null, "a basin %.2f deep holds nothing" % rim)
	var enough := func(i: int, j: int) -> float: return _bowl(i, j, 10, 10, (PondLayout.FREEBOARD + PondLayout.MIN_DEPTH * 1.5) / 4.0, 4.0)
	_check(PondLayout.fill(_grid(enough), WINDOW, Vector2i(10, 10)) != null, "a slightly deeper one does")


func _dig(tool: WaterTool, x: float, z: float, frames: int) -> void:
	tool.begin(tool.rig.right, Terrain.ground(x, z))
	for i in frames:
		tool.deepen(1.0 / 60.0)
	tool.end()
	await process_frame
	await process_frame


func _ponds_in_the_glade() -> void:
	Terrain.install()
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var terrain := GroundGrab.new(rig, world)
	root.add_child(terrain)
	var water := Water.new([])
	terrain.reshaped.connect(water.reground)
	root.add_child(water)
	var tool := WaterTool.new(rig, terrain, water)
	root.add_child(tool)
	world.attach(null, null, null, terrain, water)
	await process_frame
	var fills := [0]
	water.splashed.connect(func(kind: StringName, _at: Vector3) -> void: fills[0] += int(kind == &"fill"))

	var before := Terrain.height_at(3, -4)
	await _dig(tool, 3, -4, 120)
	_check(water.ponds.size() == 1 and fills[0] == 1, "a dug hollow fills once, %d ponds" % water.ponds.size())
	_check(world.stacks[world.me()].undo.size() == 1, "a dig is one undo step")
	var pond := water.pond_at(3, -4)
	_check(pond != null, "its middle is under water")
	_check(water.pond_at(3 + WaterTool.RADIUS * 3.0, -4) == null, "the meadow beyond stays dry")
	var shore := Terrain.grid_xz(pond.pond.shore[0])
	_check(water.pond_at(shore.x, shore.y) == null, "a shore point stands above the water")

	await _dig(tool, 4, -4, 1)
	_check(water.ponds.size() == 1 and water.ponds[0] == pond and fills[0] == 1, "a second dig in the same pond keeps its surface")

	await _dig(tool, 12, 8, 120)
	_check(water.ponds.size() == 2, "a dig elsewhere makes a second pond")
	var other := water.pond_at(12, 8)
	_check(other != null and other != pond and water.pond_at(3, -4) == pond, "each place finds its own pond")

	terrain.reshaped.emit(Rect2(), false)
	await process_frame
	_check(water.ponds.size() == 2, "nothing refills mid-stroke")
	world.undo()
	await process_frame
	await process_frame
	_check(water.ponds.size() == 1 and (not is_instance_valid(other) or other.is_queued_for_deletion()), "undoing a dig drains its pond")
	world.redo()
	await process_frame
	_check(water.ponds.size() == 2 and water.pond_at(12, 8) != null, "redo digs and fills it again")

	for step in 3:
		world.undo()
	await process_frame
	_check(water.ponds.is_empty() and water.pond_at(3, -4) == null, "undoing every dig drains them all")
	_check(absf(Terrain.height_at(3, -4) - before) < 1e-4, "and the ground is as it was")
	terrain.begin(Terrain.ground(3, -4), WaterTool.RADIUS)
	terrain.pull(-1.0)
	terrain.end_stroke()
	await process_frame
	_check(water.ponds.is_empty(), "a hollow pressed where an undone pond was stays dry")
	world.undo()
	await process_frame

	await _dig(tool, 3, -4, 1)
	_check(water.ponds.size() == 1, "even a tap scoops enough to hold water")
	world.undo()
