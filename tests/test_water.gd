extends SceneTree

## Headless checks of ponds: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_water.gd

const SIDE := 21
const WINDOW := Rect2i(0, 0, SIDE, SIDE)
const RADIUS := 2.8
## Just past the edge of a hollow pressed a metre deep, which widens to GroundGrab.SPREAD metres.
const RIM := GroundGrab.SPREAD + 0.2

var failures := 0


func _initialize() -> void:
	_bowl_fills_to_below_its_rim()
	_water_spills_at_the_lowest_rim_point()
	_seed_off_the_bottom_still_fills()
	_a_level_below_the_rim_fills_shallower()
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


func _a_level_below_the_rim_fills_shallower() -> void:
	var g := _grid(_bowl)
	var full := PondLayout.fill(g, WINDOW, Vector2i(10, 10))
	var side := Vector2i(13, 10)
	var p := PondLayout.fill(g, WINDOW, side, g[side.y * SIDE + side.x])
	_check(p != null and is_equal_approx(p.level, 0.9) and p.bottom == Vector2i(10, 10), "a point on the bowl's side fills it to that point's height, %s" % (p.level if p else "no pond"))
	_check(p != null and p.cells.size() < full.cells.size() and p.cells.all(func(c: Vector2i) -> bool: return g[c.y * SIDE + c.x] < 0.9), "covering less of it")
	var over := PondLayout.fill(g, WINDOW, side, 9.0)
	_check(over != null and is_equal_approx(over.level, full.level), "a level over the rim fills only to where it would spill")
	_check(PondLayout.fill(g, WINDOW, side, PondLayout.MIN_DEPTH * 0.5) == null, "a level just over the bottom holds nothing")


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


## Presses a hollow `depth` deep at x, z as a grip does; the rim it leaves is `rim` from x, z.
func _press(terrain: GroundGrab, x: float, z: float, depth: float) -> void:
	terrain.begin(terrain.rig.right, Terrain.ground(x, z), RADIUS)
	terrain.pull(terrain.rig.right, -depth)
	terrain.end_stroke(terrain.rig.right)
	await process_frame


## Points the tool's first hand at `at` until its preview has caught up.
func _preview(tool: WaterTool, at: Vector3) -> void:
	tool._show(0, at)
	while tool._tasks[0] >= 0:
		await process_frame
		tool._show(0, at)


## The ground back as it first lay around x, z, as one ground edit.
func _fill_in(world: World, x: float, z: float) -> void:
	var cells := Terrain.cells_around(x, z, RADIUS * 3.0)
	var base := Terrain.base_heights()
	var flat := PackedFloat32Array()
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			flat.append(base[j * Terrain.VERTS + i])
	world.submit({"op": "heights", "cells": cells, "values": flat})
	await process_frame


## Only a head under the surface turns the view and the mix underwater, and coming up undoes every part of it.
func _head_under(water: Water, rig: Rig, pond: PondWater) -> void:
	var holder := Node.new()
	root.add_child(holder)
	var look := Look.build(holder)
	var under := Underwater.new(water, look)
	holder.add_child(under)
	var effects := AudioServer.get_bus_effect_count(0)
	var fog_keys: Array = Look.WATER_FOG.keys() + ["fog_light_color", "adjustment_color_correction"]
	rig.head.global_position = Vector3(3, pond.surface_y() + 0.1, -4)
	await process_frame
	await process_frame
	var air := {}
	for k in fog_keys:
		air[k] = look.env.get(k)
	_check(not under.visible and not look.under and air.adjustment_color_correction == null, "a head just above the surface sees open air")
	_check(not AudioServer.is_bus_effect_enabled(0, effects - 1) and AudioServer.get_bus_volume_db(0) == 0.0, "and hears it unmuffled")

	rig.head.global_position.y = pond.surface_y() - 0.1
	await process_frame
	_check(under.visible and look.under, "a head just under it is underwater")
	_check(look.env.fog_depth_end == Look.WATER_FOG.fog_depth_end and look.env.adjustment_color_correction != null, "its view closes in and loses red")
	_check(AudioServer.is_bus_effect_enabled(0, effects - 1) and AudioServer.get_bus_volume_db(0) < 0.0, "its mix is muffled")

	rig.head.global_position.y = pond.surface_y() + 0.1
	await process_frame
	await process_frame
	_check(not under.visible and not look.under, "coming up leaves the water")
	for k in fog_keys:
		_check(look.env.get(k) == air[k], "coming up restores %s" % k)
	_check(not AudioServer.is_bus_effect_enabled(0, effects - 1) and AudioServer.get_bus_volume_db(0) == 0.0, "and the open mix")

	var low := Daylight.toward_sun(Daylight.DEFAULT)
	var bent := Underwater.into_water(-low)
	_check(bent.y < (-low.normalized()).y and is_equal_approx(sin(bent.angle_to(Vector3.DOWN)) * Underwater.WATER_IOR, sin((-low).angle_to(Vector3.DOWN))), "sunlight bends toward straight down entering the water, by Snell's law")
	holder.free()
	await process_frame
	_check(AudioServer.get_bus_effect_count(0) == effects - 1, "the muffle leaves the mix with the water's view")


func _ponds_in_the_glade() -> void:
	Terrain.install()
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var terrain := GroundGrab.new(rig, world)
	root.add_child(terrain)
	var water := Water.new([])
	root.add_child(water)
	var tool := WaterTool.new(rig, world)
	root.add_child(tool)
	world.attach(null, null, null, terrain, water)
	await process_frame
	var fills := [0]
	water.splashed.connect(func(kind: StringName, _at: Vector3) -> void: fills[0] += int(kind == &"fill"))
	var hand := rig.right

	var meadow := Terrain.height_at(3, -4)
	await _press(terrain, 3, -4, 1.0)
	_check(water.ponds.is_empty(), "a pressed hollow holds no water until the pond tool fills it")
	var rim := Terrain.ground(3 + RIM, -4)
	var steps: int = world.stacks[world.me()].undo.size()
	tool.fill(hand, rim)
	await process_frame
	_check(water.ponds.size() == 1 and fills[0] == 1 and world.state.ponds.size() == 1, "pointing at the rim fills the hollow once, %d ponds" % water.ponds.size())
	_check(world.stacks[world.me()].undo.size() == steps + 1, "a fill is one undo step")
	var pond := water.pond_at(3, -4)
	_check(pond != null, "its middle is under water")
	var brim := pond.pond.level if pond != null else 0.0
	_check(brim <= rim.y + 1e-4 and brim > meadow - 0.3, "it fills to the brim, %.2f against the rim at %.2f" % [brim, rim.y])
	_check(water.pond_at(3 + RADIUS * 3.0, -4) == null, "the meadow beyond stays dry")
	var shore := Terrain.grid_xz(pond.pond.shore[0])
	_check(water.pond_at(shore.x, shore.y) == null, "a shore point stands above the water")
	await _head_under(water, rig, pond)

	var lower := Terrain.ground(3 + RIM * 0.3, -4)
	_check(lower.y < brim - 0.2, "a point down the side stands below the brim, %.2f against %.2f, meadow %.2f, bottom %.2f" % [lower.y, brim, meadow, Terrain.height_at(3, -4)])
	tool.fill(hand, lower)
	await process_frame
	_check(water.ponds.size() == 1 and world.state.ponds.size() == 1 and water.ponds[0] == pond, "pointing lower keeps the one pond and its surface")
	_check(absf(pond.pond.level - lower.y) < 1e-4 and pond.pond.cells.size() > 0, "and fills it shallower, to %.2f" % pond.pond.level)
	var shallow := pond.pond.cells.size()
	tool.fill(hand, rim)
	await process_frame
	_check(water.ponds.size() == 1 and absf(pond.pond.level - brim) < 1e-4 and pond.pond.cells.size() > shallow, "pointing at the rim again fills it to the brim")

	tool.fill(hand, rim + Vector3.UP * 5.0)
	await process_frame
	_check(water.ponds.size() == 1 and pond.pond.level <= brim + PondLayout.FREEBOARD and pond.pond.level < meadow + 0.3, "a level over the rim fills only to where it would spill, %.2f" % pond.pond.level)
	tool.fill(hand, rim)
	await process_frame

	var again: int = world.stacks[world.me()].undo.size()
	tool.fill(hand, rim)
	await process_frame
	world.undo()
	await process_frame
	_check(world.stacks[world.me()].undo.size() == again and water.ponds.size() == 1 and absf(pond.pond.level - brim) < 1e-4, "undoing a fill to the level it already had leaves the pond be")
	tool.set_process(false)
	await _preview(tool, rim)
	_check(tool._ghosts[0].visible and absf(tool._ghosts[0].position.y - brim) < 0.05, "the tool shows the water pointing at the rim would hold")
	await _preview(tool, Terrain.ground(-30, 30))
	_check(not tool._ghosts[0].visible and tool._ponds[0] == null, "and nothing where no hollow holds any")
	tool.set_process(true)
	var seq := world.seq
	_check(Water.pointed(Terrain.ground(-30, 30)) == null, "open meadow holds no water")
	tool.fill(hand, Terrain.ground(-30, 30))
	await process_frame
	_check(world.seq == seq, "and the pond tool sends nothing there")
	_check(Water.pointed(Terrain.ground(3, -4) + Vector3.UP * 0.05) == null, "nor at a point just over the hollow's bottom")

	var depth := pond.pond.depth
	await _press(terrain, 3, -4, 0.6)
	_check(water.ponds.size() == 1 and absf(pond.pond.level - brim) < 0.01 and pond.pond.depth > depth + 0.2, "digging its bed deeper keeps its level and deepens it")
	world.undo()
	await process_frame

	await _press(terrain, 12, 8, 1.0)
	tool.fill(hand, Terrain.ground(12 + RIM, 8))
	await process_frame
	_check(water.ponds.size() == 2 and world.state.ponds.size() == 2, "a hollow elsewhere holds a second pond")
	var other := water.pond_at(12, 8)
	_check(other != null and other != pond and water.pond_at(3, -4) == pond, "each place finds its own pond")

	await _fill_in(world, 12, 8)
	_check(water.ponds.size() == 1 and world.state.ponds.size() == 1 and water.pond_at(12, 8) == null, "filling a pond's hollow in erases it")
	_check(not world.snapshot().cmds.any(func(c: Dictionary) -> bool: return c.op == "ponds" and c.put.size() != 1), "and the garden saves without it")
	world.undo()
	await process_frame
	_check(water.ponds.size() == 2 and world.state.ponds.size() == 2 and water.pond_at(12, 8) != null, "undoing the filling in brings the pond back")
	world.redo()
	await process_frame
	_check(water.ponds.size() == 1 and world.state.ponds.size() == 1, "redo fills it in again")
	world.undo()
	await process_frame

	world.undo()
	await process_frame
	_check(water.ponds.size() == 1 and water.pond_at(12, 8) == null and water.pond_at(3, -4) == pond, "undoing a fill drains only its pond")
	world.redo()
	await process_frame
	_check(water.ponds.size() == 2 and water.pond_at(12, 8) != null, "redo fills it again")

	var saved: Array = world.snapshot().cmds.filter(func(c: Dictionary) -> bool: return c.op == "ponds")
	_check(saved.size() == 1 and saved[0].put == world.state.ponds and world.state.ponds.values().has(rim.y), "the garden saves each pond's level: %s" % [saved])
