extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var d := {"a": Vector3.ZERO, "b": Vector3(0, 2, -4), "width": 1.2, "rail": "stone", "seed": 8, "paint": Palette.plain(), "on": PackedInt32Array()}
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
		check(is_zero_approx(piece.xform.origin.y - piece.xform.basis.y.length() * 0.5), "blocks reach down to the foot, a solid flight with no air under its steps")
	_posts_on_treads(d)
	_walkable(d)
	_walkable({"a": Vector3(1, 0.5, 2), "b": Vector3(-3, 0.5, -1), "width": 2.0, "rail": "none", "seed": 3, "paint": Palette.plain()})
	_walkable({"a": Vector3(2, 3.1, 0), "b": Vector3(-1, 0.2, 2.5), "width": 0.8, "rail": "wood", "seed": 4, "paint": Palette.plain()})
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
	var bare := d.duplicate()
	bare.rail = "none"
	check(is_equal_approx(Budget.stairs(bare).wall_m2, 3.0 * d.width), "a flight without railings is charged for its treads alone")
	check(is_equal_approx(Budget.stairs(d).wall_m2, 3.0 * (d.width + 2.0 * StairLayout.RAIL_HEIGHT)), "railings are charged on a railed flight")
	var climb := d.duplicate()
	climb.b = Vector3(0, 3, -0.5)
	check(is_equal_approx(Budget.stairs(climb).wall_m2, d.a.distance_to(climb.b) * d.width), "a ladder, which has no railings, is charged for none")
	for bad in [Vector3(NAN, 0, 0), Vector3(0, 0, -Commands.MAX_LENGTH - 1.0), d.a]:
		var invalid := d.duplicate()
		invalid.b = bad
		check(Commands._stairs(invalid) == null, "reject invalid endpoint")
	var long := {"a": Vector3(0, 2, 0), "b": Vector3(0, 2, -60), "width": 1.2, "rail": "stone", "seed": 5, "paint": Palette.plain(), "on": PackedInt32Array()}
	check(Commands._stairs(long) != null, "a sixty-metre bridge is a valid command")
	stairs.build(long)
	check(stairs.kind == StairLayout.Kind.LANDING and is_equal_approx(stairs.surface(Vector3(0, 3, -59.5)), 2.0), "a sixty-metre bridge is walkable to its far end")
	long.b.y = 2.15
	stairs.build(long)
	check(stairs.kind == StairLayout.Kind.FLIGHT and stairs.treads.size() == ceili(60.0 / StairLayout.TREAD), "a gently sloped long bridge climbs in shallow treads, not a few long ones: %d" % stairs.treads.size())
	boot_main()
	await process_frame
	var world: World = main.world
	_path_steps_follow_terrain(main)
	main.stair_tool.begin(main.rig.left, long.a)
	main.stair_tool.extend(main.rig.left, long.b)
	check(is_equal_approx(main.stair_tool._strokes[main.rig.left].data.b.z, -60.0), "the tool draws a bridge past twenty-four metres")
	main.stair_tool._cancel(main.rig.left)
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
	_painted_and_styled(main)
	_gripped(main)
	finish()


func _posts_on_treads(d: Dictionary) -> void:
	var railed := d.duplicate()
	railed.rail = "wood"
	var stairs := StairLayout.new()
	stairs.build(railed)
	var tops := stairs.treads.map(func(t: Vector3) -> float: return t.y)
	var posts := stairs.stones.filter(func(p: Dictionary) -> bool: return p.kind == "rail" and is_equal_approx(p.xform.basis.y.normalized().y, 1.0))
	check(posts.size() >= 4, "a railed flight has posts on both sides")
	for post: Dictionary in posts:
		var foot: float = post.xform.origin.y - post.xform.basis.y.length() * 0.5
		check(tops.any(func(y: float) -> bool: return is_equal_approx(y, foot)), "a railing post stands on a tread, not in the air: %.3f" % foot)


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


## The colour and style tools reach stairs as they reach walls: a tread recoloured, the railings restyled, each one
## undo step, kept through a snapshot, and taken by stairs laid after.
func _painted_and_styled(main: Node) -> void:
	var world: World = main.world
	var picker: PaletteTool = main.palette_tool
	var hand: Hand = main.rig.right
	var stone := Palette.Element.STONE
	world.submit({"op": "wipe"})
	var a := Terrain.ground(10, 0)
	world.submit({"op": "stairs", "stairs": {"a": a, "b": a + Vector3(0, 2, -4), "width": 1.2, "rail": "stone", "seed": 5, "paint": Palette.plain(), "on": PackedInt32Array()}})
	world.stairs._process(10.0)
	var id: int = world.state.stairs.keys()[0]
	var over := a + Vector3(0, 6, -2)
	var laid: Color = world.stairs.layouts[id].stones[0].color
	hand.tool = Hand.Tool.COLOUR
	var target := picker.aim(over, Vector3.DOWN)
	check(target.get("of") == "stairs" and target.get("id") == id and target.get("element") == stone, "the colour tool on a tread picks the stairs' stone: %s" % [target])
	picker.open(hand, target)
	picker.twist(hand, 3 * Palette.TWIST_STEP)
	var shown: Color = world.stairs.layouts[id].stones[0].color
	check(world.state.stairs[id].paint[stone] == 0 and shown.is_equal_approx(laid * Palette.tint(stone, 3)), "the turned swatch shows on the stairs before it is sent")
	picker.close(hand)
	check(world.state.stairs[id].paint[stone] == 3, "letting go recolours the stairs")
	check(world.stairs.layouts[id].stones[0].color.is_equal_approx(laid * Palette.tint(stone, 3)), "the stairs are laid in the swatch")
	check(main.tool.paint[stone] == 3, "builds laid after take the swatch")
	var blocks: Array = world.stairs.layouts[id].stones.filter(func(p: Dictionary) -> bool: return p.kind == "block")
	hand.tool = Hand.Tool.STYLE
	target = picker.aim_style(over, Vector3.DOWN)
	check(target.get("restyle") == PaletteTool.Restyle.RAIL and target.get("id") == id and target.count == StairLayout.RAILS.size(), "the style tool on stairs offers their railings: %s" % [target])
	picker.open(hand, target)
	check(picker.wheels[hand].choices.size() == StairLayout.RAILS.size(), "a miniature for each railing")
	picker.twist(hand, StairLayout.RAILS.find("wood") * Palette.TWIST_STEP)
	check(world.stairs.layouts[id].stones.any(func(p: Dictionary) -> bool: return p.kind == "rail"), "the turned railing shows on the stairs before it is sent")
	picker.close(hand)
	var wooden: Array = world.stairs.layouts[id].stones
	check(world.state.stairs[id].rail == "wood" and wooden.any(func(p: Dictionary) -> bool: return p.kind == "rail"), "letting go gives the stairs wooden railings")
	check(wooden.filter(func(p: Dictionary) -> bool: return p.kind == "block").size() < blocks.size(), "the stone railings are gone")
	check(world.stairs.rail == "wood", "stairs laid after take the railings")
	check(Commands.clean({"op": "reshape", "of": "stairs", "id": id, "data": {"rail": "gold"}}, world.state, false).is_empty(), "a railing off the wheel is refused")
	check(not Commands.clean({"op": "reshape", "of": "stairs", "id": id, "data": {"a": a + Vector3(1, 0, 0)}}, world.state, false).is_empty(), "a reshape may move stairs, as a grip does")
	check(Commands.clean({"op": "reshape", "of": "stairs", "id": id, "data": {"width": StairLayout.WIDTH.y + 1.0}}, world.state, false).is_empty(), "but never wider than stairs are drawn")
	check(Commands.clean({"op": "reshape", "of": "stairs", "id": id, "data": {"paint": {stone: Palette.count(stone)}}}, world.state, false).is_empty(), "a swatch off the wheel is refused")
	world.undo()
	check(world.state.stairs[id].rail == "stone" and not world.stairs.layouts[id].stones.any(func(p: Dictionary) -> bool: return p.kind == "rail"), "undo puts the stone railings back")
	world.redo()
	check(world.state.stairs[id].rail == "wood", "redo restyles again")
	var snap := world.snapshot()
	world.submit({"op": "wipe"})
	world.restore(snap)
	world.stairs._process(10.0)
	var kept: Dictionary = world.state.stairs.get(id, {})
	check(kept.get("rail") == "wood" and kept.get("paint", Palette.plain())[stone] == 3, "a garden rebuilt from its snapshot keeps the stairs' colour and railings")
	check(world.stairs.layouts[id].stones[0].color.is_equal_approx(laid * Palette.tint(stone, 3)) and world.stairs.layouts[id].stones.any(func(p: Dictionary) -> bool: return p.kind == "rail"), "and lays them so")
	hand.tool = Hand.Tool.STAIRS
	var b := Terrain.ground(-10, 0)
	main.stair_tool.begin(hand, b)
	main.stair_tool.extend(hand, b + Vector3(0, 2, -4))
	main.stair_tool.end(hand)
	var fresh: Dictionary = world.state.stairs[world.state.stairs.keys().max()]
	check(fresh.rail == "wood" and fresh.paint[stone] == 3, "new stairs take the last swatch and railings")
	var ladder := Terrain.ground(0, 10)
	world.submit({"op": "stairs", "stairs": {"a": ladder, "b": ladder + Vector3(0, 3, -0.5), "width": 1.2, "rail": "stone", "seed": 6, "paint": Palette.plain(), "on": PackedInt32Array()}})
	world.stairs._process(10.0)
	var facing := ladder + Vector3(0.6, 1.5, 3)
	check(not world.stairs.pick(facing, Vector3.FORWARD, 10.0).is_empty() and picker.aim_style(facing, Vector3.FORWARD).is_empty(), "a ladder has no style")
	hand.tool = Hand.Tool.WALLS


func _path_steps_follow_terrain(main: Node3D) -> void:
	var world: World = main.world
	var before := world.units.duplicate()
	var cells := Terrain.cells_around(-25, -20, 6)
	var original := Terrain.read(cells)
	var flat := original.duplicate()
	flat.fill(0.0)
	world.submit({"op": "heights", "cells": cells, "values": flat})
	world.submit({"op": "path", "path": {"points": PackedVector3Array([Vector3(-28, 0, -20), Vector3(-22, 0, -20)]), "half_widths": PackedFloat32Array([0.8, 0.8]), "seed": 42}})
	var id: int = world.state.paths.keys().max()
	var owner := -2000000 - id
	check(world.units != before, "paths reserve steps through World")
	check(not main.tool.masonry._owners.has(owner), "flat path has no masonry")
	var slope := flat.duplicate()
	for j in cells.size.y:
		for i in cells.size.x:
			slope[j * cells.size.x + i] = Terrain.grid_xz(cells.position + Vector2i(i, j)).x * 0.8
	world.submit({"op": "heights", "cells": cells, "values": slope})
	check(main.tool.masonry._owners.has(owner), "terrain command builds steps on an existing path")
	world.submit({"op": "heights", "cells": cells, "values": flat})
	check(not main.tool.masonry._owners.has(owner), "flattening removes the old treads")
	world.submit({"op": "heights", "cells": cells, "values": slope})
	world.submit({"op": "take", "of": "paths", "ids": PackedInt32Array([id])})
	check(not main.tool.masonry._owners.has(owner), "deleting steep path removes its masonry")
	check(world.units == before, "deleting path refunds its steps")
	world.submit({"op": "heights", "cells": cells, "values": original})


## Report (relay): stairs join the grab rule: a one-hand grip moves and turns a flight, two hands pulled apart widen it.
func _gripped(main: Node) -> void:
	var world: World = main.world
	var tool: WallTool = main.tool
	var g := Terrain.ground(6, -6)
	world.submit({"op": "stairs", "stairs": {"a": g, "b": g + Vector3(0, 2, -4), "width": 1.2, "rail": "stone", "seed": 9, "paint": Palette.plain(), "on": PackedInt32Array()}})
	world.stairs._process(10.0)
	var id: int = world.state.stairs.keys().filter(func(k: int) -> bool: return world.state.stairs[k].seed == 9)[0]
	var was: Dictionary = world.state.stairs[id].duplicate()
	var mid: Vector3 = (was.a + was.b) * 0.5
	var right: Hand = main.rig.right
	var left: Hand = main.rig.left
	var from := Transform3D(Basis(), mid + Vector3(0, 1.5, 3))
	var hit: Dictionary = world.stairs.pick(from.origin, (mid - from.origin).normalized(), 50.0)
	check(hit.get("stair", -1) == id, "a ray from the hand meets the flight")
	if hit.is_empty():
		return
	right.global_transform = from
	var m := tool.mason(right)
	tool.begin_grow(m, tool._stair_grip(id), from, hit.point)
	check(m.growing is WallTool.StairGrip and tool.busy(right), "a grip on stairs takes them")
	var to := Transform3D(Basis(Vector3.UP, 0.5), from.origin + Vector3(1, -0.2, 0.5))
	m.sizing.follow.call(m, to)
	var expect := WallTool.carry_stairs(was, from, to, Hand.reach_gain(from.origin.distance_to(hit.point)))
	check(expect.a.distance_to(was.a) > 1.0 and not is_equal_approx((expect.b - expect.a).normalized().dot((was.b - was.a).normalized()), 1.0), "the hand's move and turn carry and turn them")
	check(world.state.stairs[id].a == was.a, "nothing is sent while they are held")
	tool.end_grow(m)
	var now: Dictionary = world.state.stairs[id]
	check(now.a.is_equal_approx(expect.a) and now.b.is_equal_approx(expect.b) and now.width == was.width, "let go, they are set where the hand carried and turned them: %s" % [now])
	var low: Vector3 = now.a if now.a.y < now.b.y else now.b
	check(low.y >= Terrain.height_at(low.x, low.z) - 0.001, "their lower end is never under the ground")
	var deep := WallTool.carry_stairs(was, from, Transform3D(Basis(), from.origin + Vector3.DOWN * 3.0), 1.0)
	var foot: Vector3 = deep.a if deep.a.y < deep.b.y else deep.b
	check(is_equal_approx(foot.y, Terrain.height_at(foot.x, foot.z)), "pushed down, they stop with their lower end on the ground")
	var mid2: Vector3 = (now.a + now.b) * 0.5
	var r := Transform3D(Basis(), mid2 + Vector3(0.3, 1.5, 3))
	var l := Transform3D(Basis(), mid2 + Vector3(-0.3, 1.5, 3))
	right.global_transform = r
	left.global_transform = l
	var on: Dictionary = world.stairs.pick(r.origin, (mid2 - r.origin).normalized(), 50.0)
	tool.begin_grow(m, tool._stair_grip(id), r, on.get("point", mid2))
	var lm := tool.mason(left)
	tool.begin_grow(lm, tool._stair_grip(id), l, on.get("point", mid2))
	check(lm.growing == m.growing and lm.partner == m, "the other hand's grip on them joins the first")
	tool.drag_pair(lm, r.origin, l.origin - Vector3(0.6, 0, 0))
	tool.end_grow(lm)
	tool.end_grow(m)
	var wide: float = world.state.stairs[id].width
	check(is_equal_approx(wide, snappedf(1.2 * 1.2 / 0.6, 0.01)) and world.state.stairs[id].a.is_equal_approx(now.a), "two hands pulled apart widen them where they stand: %.2f" % wide)
	world.undo()
	check(world.state.stairs[id].width == was.width, "undo narrows them back")
	world.undo()
	check(world.state.stairs[id].a == was.a and world.state.stairs[id].b == was.b, "and the undo before puts them back where they stood")
