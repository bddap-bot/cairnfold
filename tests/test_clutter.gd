extends "res://../tests/support/suite.gd"

## Clutter: where houses, walls and paths gather their small things, each laid with its build and charged as its
## stones; a hand moving, turning, copying and taking one away, each one reshape and one undo step; birds on nests,
## lanterns and flags; demo/clutter.json and the stress scene's clutter/* phases:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_clutter.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	check(main.tool.foundation == WallLayout.Foundation.PILLARS, "new houses default to pillar supports")
	_gathered()
	_valid()
	await _in_the_garden()
	await _nests_meet_roofs()
	await _demo()
	await _stress()
	finish()


static func _named(list: Variant, name: String) -> Array:
	return Array(list).filter(func(v: Vector4) -> bool: return int(v.w) == DecorationLayout.named(name))


static func _house(at: Vector3, size: Vector2, on := PackedInt32Array()) -> Dictionary:
	var stance := WallTool.stance(at, 0.0, false)
	stance.size = size
	var d := wall_data({"points": PackedVector3Array(WallTool.outline(stance)), "closed": true, "seed": 5, "on": on})
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": at, "radius": size.x * 0.5, "pitch": 1.5, "curve": 0.0, "seed": 5, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array(), "overhang": 0.3, "deck": 0, "flag": false, "thatch": false}
	return d


## What each kind of build gathers, worked out from its command alone.
func _gathered() -> void:
	var house := _house(Vector3.ZERO, Vector2(6, 4))
	var styles := {}
	for seed in 40:
		house.seed = seed
		var list := ClutterLayout.of_wall(house)
		check(list.size() >= 3 and list.size() <= ClutterLayout.GATHERED, "a house gathers a few things: %d" % list.size())
		check(_named(list, "Bench").size() == 1 and _named(list, "Bird nest").size() == 1, "a bench by its front and a nest under its eaves")
		check(_named(list, "Carved pumpkin").size() == 2 or _named(list, "Flower box").size() == 1, "pumpkins or flowers the other side of its door")
		var bench: Vector4 = _named(list, "Bench")[0]
		check(bench.x > 0.0 and bench.x < 6.0, "the bench stands along its front, %.2f" % bench.x)
		for v in list:
			styles[int(v.w)] = true
	for name in ["Bench", "Rain barrel", "Crates", "Market stall", "Anvil", "Flower box", "Carved pumpkin", "Bird nest"]:
		check(styles.has(DecorationLayout.named(name)), "houses gather a %s" % name.to_lower())
	house.openings = PackedVector4Array([Vector4(4.5, 0.0, WallLayout.Family.COTTAGE, 1.0)])
	check(absf(_named(ClutterLayout.of_wall(house), "Bench")[0].x - (4.5 - 1.35)) < 0.001, "with a door, the bench stands beside the door")
	var upper := ClutterLayout.of_wall(_house(Vector3.ZERO, Vector2(6, 4), PackedInt32Array([1])))
	check(upper.size() == 1 and _named(upper, "Bird nest").size() == 1, "an upper storey gathers its nest alone")
	var layout := WallLayout.new()
	layout.points.assign(Array(house.points))
	layout.closed = true
	layout.build(Terrain.flat)
	var out := ClutterLayout._outward(house.points, ClutterLayout._sides(house.points, true))
	var mid := layout.frame_at(3.0)
	var probe: Vector3 = mid.point + mid.tangent.cross(Vector3.UP) * out * 1.0
	check(not Geometry2D.is_point_in_polygon(Vector2(probe.x, probe.z), PackedVector2Array(Array(house.points).map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z)))), "a house's things stand outside it")
	var wall := wall_data({"points": PackedVector3Array([Vector3(0, 0, 0), Vector3(30, 0, 0)]), "seed": 2})
	var along := ClutterLayout.of_wall(wall)
	check(_named(along, "Bird nest").size() >= 2, "a long wall gathers nests on its top: %d" % _named(along, "Bird nest").size())
	check(along.size() > _named(along, "Bird nest").size(), "and things at its foot")
	check(Array(along).all(func(v: Vector4) -> bool: return v.x >= 0.0 and v.x <= 30.0), "all along its length")
	check(ClutterLayout.of_wall(wall.merged({"fence": true}, true)).is_empty(), "a fence gathers nothing")
	check(ClutterLayout.of_wall(wall.merged({"ruins": PackedVector2Array([Vector2(3, 5)])}, true)).is_empty(), "nor a ruin")
	var path := {"points": PackedVector3Array([Vector3(0, 0, 0), Vector3(20, 0, 0)]), "half_widths": PackedFloat32Array([1.0, 1.0]), "seed": 3, "surface": PathLayout.Surface.DIRT}
	var beside := ClutterLayout.of_path(path)
	check(beside.size() >= 2, "a 20 m path gathers things beside it: %d" % beside.size())
	check(Array(beside).all(func(v: Vector4) -> bool: return absf(v.y) > 1.0 and v.x <= 20.0 - ClutterLayout.PATH_CLEAR), "past its edge and clear of its end")
	check(is_equal_approx(beside[0].x, ClutterLayout.PATH_FIRST) and signf(beside[0].y) != signf(beside[1].y), "first near its start, then on either side in turn: %s" % beside)
	check(ClutterLayout.of_path(path.merged({"points": PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0)])}, true)).is_empty(), "a path too short gathers nothing")
	var with := ClutterLayout.of_wall(house)
	check(is_equal_approx(Budget.wall(house.merged({"clutter": with}, true)).wall_m2 - Budget.wall(house).wall_m2, ClutterLayout.count(with) * Budget.PIECE_M2), "a house's clutter is charged a part a piece, as wall stone")
	check(is_equal_approx(Budget.path(path.merged({"clutter": beside}, true)).wall_m2 - Budget.path(path).wall_m2, ClutterLayout.count(beside) * Budget.PIECE_M2), "a path's too")


## The command schema takes what a hand could leave and nothing else.
func _valid() -> void:
	var bench := DecorationLayout.named("Bench")
	var d := wall_data({"points": PackedVector3Array([Vector3(0, 0, 0), Vector3(6, 0, 0)]), "seed": 2})
	check(Commands._wall(d.merged({"clutter": PackedVector4Array([Vector4(2, 0.4, 0.3, bench)])}, true)) != null, "a wall keeps a bench at its foot")
	check(Commands._wall(d.merged({"clutter": PackedVector4Array([Vector4(2, 0.4, 0.3, DecorationLayout.named("Lantern string"))])}, true)) == null, "but no string")
	check(Commands._wall(d.merged({"clutter": PackedVector4Array([Vector4(2, 9.0, 0.3, bench)])}, true)) == null, "nor one out of reach")
	check(Commands._wall(d.merged({"clutter": PackedVector4Array([Vector4(2, 0.4, 0.3, 1.5)])}, true)) == null, "nor a style between styles")
	var many := PackedVector4Array()
	many.resize(ClutterLayout.MOST + 1)
	many.fill(Vector4(2, 0.4, 0, bench))
	check(Commands._wall(d.merged({"clutter": many}, true)) == null, "nor more than MOST")
	check(Commands._wall(d.merged({"fence": true, "finish": WallLayout.Finish.BARE, "clutter": PackedVector4Array([Vector4(2, 0.4, 0, bench)])}, true)) == null, "a fence keeps none")
	check(Commands._wall(d).clutter.is_empty(), "a wall without a list keeps none")


func _lay() -> void:
	for w: Wall in main.tool.walls:
		w.lay_now()
	main.tool.paths.lay_now()


## A held piece stands apart from its house: the house is laid once without it, each step of the hand moves only the
## piece, a second hand reaching for it pulls off a copy, and let go it stands until the house is laid with it.
func _held_apart(house: Wall) -> void:
	var tool: WallTool = main.tool
	var target: Dictionary = FittingTool.targets(house).filter(func(t: Dictionary) -> bool: return t.what == "clutter")[0]
	var at: Vector3 = target.bounds.get_center()
	target.point = at
	var from := Transform3D(Basis(), at + Vector3(0.0, 0.3, 0.3))
	var m := tool.mason(main.rig.right)
	var grip := tool._fitting_grip(target)
	tool.begin_grow(m, grip, from, at)
	_lay()
	await until(func() -> bool: return tool._held_clutter[grip].node.visible, "the piece in hand shows once its house is drawn without it")
	var laid := house.layout.laid
	check(house.layout.clutter.size() == _clutter(house.id).size() - 1, "the house is laid without the piece in hand")
	var held: Node3D = tool._held_clutter[grip].node
	var reach: Vector3 = held.global_transform * ClutterLayout.bounds(grip.shown).get_center()
	var out: Vector3 = held.global_transform.basis.z.normalized()
	var pick := FittingTool.pick_target(tool, reach + out, -out, true)
	var copy: Variant = tool._fitting_grip(pick) if pick.get("what") == "clutter" else null
	check(copy != null and copy.copy, "a second hand reaching for it pulls off a copy")
	for k in 8:
		m.sizing.follow.call(m, Transform3D(Basis(), from.origin + Vector3(0.1 * (k + 1), 0.0, 0.04 * (k + 1))))
		await frames(1)
		_lay()
	check(grip.shown != grip.start, "the hand carried it")
	check(house.layout.laid == laid, "steps of the hand lay the house no more: %d lays" % (house.layout.laid - laid))
	var piece: Node3D = tool._held_clutter[grip].node
	check(piece.global_transform.is_equal_approx(house.layout.clutter_frame(grip.shown, main.world.terrain.height_at)), "the piece stands where the hand carries it")
	tool.end_grow(m)
	await until(func() -> bool: return not tool._held_clutter.has(grip), "the piece let go stands apart until its house is laid")
	check(house.layout.clutter.size() == _clutter(house.id).size() and Array(house.layout.clutter).has(grip.shown), "and the house lays it where it was let go")
	main.world.undo()
	await frames(2)


func _clutter(id: int) -> PackedVector4Array:
	return main.world.state.walls[id].clutter


## A house, a wall and a path put up by the tools gather their things as the garden lays them; a hand moves, turns,
## copies and takes each away, one reshape and one undo step each.
func _in_the_garden() -> void:
	var world: World = main.world
	world.limit = INF
	await play([
		{"op": "house", "at": [0, -10], "size": [6, 4.2], "seconds": 0.3},
		{"op": "wall", "points": [[-12, 2], [12, 2]], "seconds": 0.3},
		{"op": "top", "index": 1, "style": "cap"},
		{"op": "pave", "points": [[-10, 8], [10, 8]], "radius": 0.8, "seconds": 0.5},
		{"op": "wait", "seconds": 1},
	])
	_lay()
	var house: Wall = main.tool.walls[0]
	var wall: Wall = main.tool.walls[1]
	var gathered := _clutter(house.id)
	check(gathered == ClutterLayout.of_wall(world.state.walls[house.id].merged({"clutter": PackedVector4Array()}, true)), "the host gathered the house's things from its command")
	check(gathered.size() >= 3 and _clutter(wall.id).size() >= 2, "a house and a wall gather things: %d, %d" % [gathered.size(), _clutter(wall.id).size()])
	var path_id: int = world.state.paths.keys()[0]
	check(world.state.paths[path_id].clutter.size() >= 2, "so does a path: %d" % world.state.paths[path_id].clutter.size())
	check(house.layout.stones.any(func(st: Dictionary) -> bool: return st.kind == "nest"), "the house lays its things with its stones")
	var targets := FittingTool.targets(house).filter(func(t: Dictionary) -> bool: return t.what == "clutter")
	check(targets.size() == gathered.size(), "each is a fitting a hand can take: %d of %d" % [targets.size(), gathered.size()])
	var beside := FittingTool.path_targets(main.tool.paths, world.terrain.height_at)
	check(beside.size() == world.state.paths[path_id].clutter.size(), "so is each beside the path")
	var nest: Vector4 = _named(gathered, "Bird nest")[0]
	var eave: Transform3D = house.layout.clutter_frame(nest, main.world.terrain.height_at)
	check(eave.origin.y > house.layout.frame_at(nest.x).point.y + house.layout.height - 0.5, "a house's nest hangs under its eaves")
	check(Array(house.perches(true)).any(func(p: Vector3) -> bool: return p.distance_to(eave.origin) < 0.3), "and birds perch in it")
	var on_top: Array = _named(_clutter(wall.id), "Bird nest")
	check(not on_top.is_empty() and Array(wall.perches(true)).any(func(p: Vector3) -> bool: return absf(p.y - (wall.layout.clutter_frame(on_top[0], main.world.terrain.height_at).origin.y + 0.05)) < 0.05 and Vector2(p.x, p.z).distance_to(Vector2(wall.layout.clutter_frame(on_top[0], main.world.terrain.height_at).origin.x, wall.layout.clutter_frame(on_top[0], main.world.terrain.height_at).origin.z)) < 0.05), "a wall's nest sits on its top, a perch")
	await play([{"op": "fit", "what": "lantern", "index": 1, "s": 20.0, "y": 1.6, "side": 1}, {"op": "fit", "what": "flag", "index": 1, "s": 22.0}])
	_lay()
	var perches := Array(wall.perches(true))
	var hood: Dictionary = wall.layout.stones.filter(func(st: Dictionary) -> bool: return st.kind == "hood")[0]
	var finial: Dictionary = wall.layout.stones.filter(func(st: Dictionary) -> bool: return st.kind == "finial")[0]
	check(perches.any(func(p: Vector3) -> bool: return p.distance_to(hood.xform.origin) < 0.1), "birds perch on a lantern's hood")
	check(perches.any(func(p: Vector3) -> bool: return p.distance_to(finial.xform.origin) < 0.1), "and on a flag's finial")

	var steps := func() -> int: return world.stacks.get(world.me(), {"undo": []}).undo.size()
	var before := _clutter(house.id)
	var undos: int = steps.call()
	await play([{"op": "clutter", "wall": 0, "piece": 0, "move": [0.6, 0, 0.5], "turn": 40, "seconds": 0.3}])
	_lay()
	var moved := _clutter(house.id)
	check(moved.size() == before.size() and moved[0] != before[0] and moved.slice(1) == before.slice(1), "a grip moves one piece, the rest stay")
	check(absf(angle_difference(before[0].z, moved[0].z) - deg_to_rad(40.0)) < FittingGrip.TURN_STEP, "and turns it with the hand: %.2f" % rad_to_deg(angle_difference(before[0].z, moved[0].z)))
	check(moved[0].x != before[0].x or absf(moved[0].y) != absf(before[0].y), "carrying it along or out from the wall")
	check(steps.call() == undos + 1, "one undo step")
	var x0: Transform3D = house.layout.clutter_frame(moved[0], main.world.terrain.height_at)
	check(FittingTool.targets(house).any(func(t: Dictionary) -> bool: return t.what == "clutter" and t.bounds.has_point(x0.origin + Vector3.UP * 0.3)), "the house lays it where it was let go")
	world.undo()
	await frames(2)
	check(_clutter(house.id) == before, "undo puts it back")
	world.redo()
	await frames(2)
	check(_clutter(house.id) == moved, "redo moves it again")

	await play([{"op": "clutter", "wall": 0, "piece": 1, "copy": true, "move": [0.0, 0, 1.2], "seconds": 0.3}])
	var copied := _clutter(house.id)
	check(copied.size() == moved.size() + 1 and copied.slice(0, moved.size()) == moved, "a second hand's grip pulls a copy off, the first left where it stood")
	check(int(copied[-1].w) == int(moved[1].w) and copied[-1] != moved[1], "the copy is the same thing, carried off")
	world.undo()
	await frames(2)
	check(_clutter(house.id) == moved, "undo takes the copy back")
	world.redo()
	await frames(2)
	await _held_apart(house)

	var kept := _clutter(house.id)
	await play([{"op": "clutter", "wall": 0, "piece": 0, "take": true}])
	check(_clutter(house.id).size() == kept.size() - 1 and not Array(_clutter(house.id)).has(kept[0]), "a press of the decorations tool takes one away")
	world.undo()
	await frames(2)
	check(_clutter(house.id) == kept, "undo puts it back")

	var lined: PackedVector4Array = world.state.paths[path_id].clutter
	await play([{"op": "clutter", "path": 0, "piece": 0, "move": [1.0, 0, 0.0], "turn": -30, "seconds": 0.3}])
	var slid: PackedVector4Array = world.state.paths[path_id].clutter
	check(slid.size() == lined.size() and slid[0] != lined[0] and slid[0].w == lined[0].w, "a path's piece moves and turns: %s to %s" % [lined[0], slid[0]])
	world.undo()
	await frames(2)
	check(world.state.paths[path_id].clutter == lined, "undo puts it back")
	await play([{"op": "clutter", "path": 0, "piece": 0, "take": true}])
	check(world.state.paths[path_id].clutter.size() == lined.size() - 1, "a path's piece is taken away")
	world.undo()
	await frames(2)
	check(world.state.paths[path_id].clutter == lined, "and put back")

	var id := house.id
	var keep := _clutter(id)
	world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([id])})
	await frames(2)
	world.undo()
	await frames(2)
	check(world.state.walls.has(id) and _clutter(id) == keep, "a house taken and put back keeps its things as they stood, gathering none afresh")
	var saved: Array = world.snapshot().cmds.filter(func(c: Dictionary) -> bool: return c.op == "wall" and id in c.ids)
	check(not saved.is_empty() and saved[0].walls[0].clutter == keep, "the garden keeps them")
	house = main.tool.find(id)

	await play([{"op": "pave", "points": [[0, -16], [0, -10]], "radius": 0.6, "seconds": 0.5}, {"op": "wait", "seconds": 0.5}])
	_lay()
	var door: Array = house.layout.apertures.filter(func(o: Dictionary) -> bool: return o.door)
	check(not door.is_empty(), "a path into the house opens a door")
	if not door.is_empty():
		var o: Dictionary = door[0]
		var by_door := Vector4(o.s, -0.32 * signf(keep[0].y if keep[0].y != 0.0 else 1.0), 0.0, DecorationLayout.named("Bench"))
		check(house.layout.clutter_frame(by_door, main.world.terrain.height_at) == null, "nothing stands in a doorway")
	await play([{"op": "bare"}])


## A house's nest sits with its top against its roof on every roof style demo/roof-nests.json puts up, raised on a
## plinth or on another house too, and stays there as the roofs are thatched, a house grown taller and steeper and
## another carried.
func _nests_meet_roofs() -> void:
	var steps := Driver.read("res://../demo/roof-nests.json")
	await play(steps.slice(0, steps.find_custom(func(s: Dictionary) -> bool: return s.op == "view")))
	_check_nests("laid")
	await play([
		{"op": "thatch"},
		{"op": "lift_wall", "index": 0, "height": 3.6},
		{"op": "roof", "index": 0, "pitch": 2.0},
		{"op": "house", "at": [45, 0], "from": [45, 6], "size": [6, 4.2], "seconds": 1},
		{"op": "wait", "seconds": 2},
	])
	_check_nests("thatched, regrown and carried")
	await play([{"op": "bare"}])


## Whether each house's nest, as its stones were laid, touches its roof's underside, neither short of it nor through it.
func _check_nests(when: String) -> void:
	_lay()
	var houses := main.tool.walls.filter(func(w: Wall) -> bool: return w.roof != null)
	check(houses.size() >= 8, "%s: the roof styles stand: %d" % [when, houses.size()])
	for w: Wall in houses:
		var nests := _named(w.layout.clutter, "Bird nest")
		check(nests.size() == 1, "%s: house %d has its nest" % [when, w.id])
		for v: Vector4 in nests:
			var at: Vector3 = (w.layout.clutter_frame(v, main.world.terrain.height_at) as Transform3D).origin
			var gap := INF
			for st in w.layout.stones:
				if st.s != w.layout.wrap(v.x) or st.xform.origin.distance_to(at) > 0.4:
					continue
				for c in WallLayout.BOX:
					var p: Vector3 = st.xform * c
					gap = minf(gap, w.roof.height_at(p.x, p.z) - p.y)
			check(absf(gap) < 0.02, "%s: house %d's nest meets its %s roof: %.3f m short of it" % [when, w.id, "flat" if w.roof.flat() else "cone" if w.roof.kind == RoofLayout.Kind.CONE else "gable", gap])


func _demo() -> void:
	var steps := Driver.read("res://../demo/clutter.json").filter(func(s: Dictionary) -> bool: return s.op != "capture")
	main.world.limit = 1.0
	await play(steps.slice(0, steps.find_custom(func(s: Dictionary) -> bool: return s.op == "view")))
	_lay()
	var world: World = main.world
	var houses := main.tool.walls.filter(func(w: Wall) -> bool: return w.roof != null)
	check(houses.size() == 2 and houses.all(func(w: Wall) -> bool: return not world.state.walls[w.id].clutter.is_empty()), "the demo's two houses gather things")
	var styles := {}
	for w: Wall in main.tool.walls:
		for v in world.state.walls[w.id].clutter:
			styles[int(v.w)] = true
	for p: Dictionary in world.state.paths.values():
		for v in p.clutter:
			styles[int(v.w)] = true
	check(styles.size() >= 5, "the demo shows several kinds: %d" % styles.size())
	var before: PackedVector4Array = world.state.walls[houses[0].id].clutter.duplicate()
	var path_before: int = world.state.paths.values()[0].clutter.size()
	var edits := steps.slice(steps.find_custom(func(s: Dictionary) -> bool: return s.op == "clutter")).filter(func(s: Dictionary) -> bool: return s.op in ["view", "clutter", "wait"])
	await play(edits.map(_uncaptured))
	var after: PackedVector4Array = world.state.walls[houses[0].id].clutter
	check(after.size() == before.size() + 1 and after[0] != before[0], "it moves one, copies another")
	check(world.state.paths.values()[0].clutter.size() == path_before - 1, "and takes one away")
	await play([{"op": "bare"}])


static func _uncaptured(s: Dictionary) -> Dictionary:
	var out := s.duplicate()
	out.erase("capture")
	return out


## The clutter/* phases: two houses, a wall and a path, with what they gathered and things copied round their walls
## until the budget is full or their feet are.
func _stress() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var aerial := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "clutter/aerial")
	check(aerial >= 0 and ["clutter/ground", "clutter/carry", "clutter/copy"].all(func(name: String) -> bool: return steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == name)), "the stress scene has clutter/aerial, clutter/ground, clutter/carry and clutter/copy phases")
	if aerial < 0:
		return
	var wiped := aerial
	while steps[wiped].op != "bare":
		wiped -= 1
	var built := steps.slice(wiped, aerial).filter(func(s: Dictionary) -> bool: return s.op in ["bare", "house", "wall", "pave", "cluttered"])
	check(built.any(func(s: Dictionary) -> bool: return s.op == "cluttered"), "the village is cluttered")
	main.world.limit = 1.0
	await play([steps[0]] + built)
	_lay()
	var world: World = main.world
	var styles := {}
	var pieces := 0
	for d: Dictionary in world.state.walls.values():
		pieces += d.clutter.size()
		for v in d.clutter:
			styles[int(v.w)] = true
	for name in ["Bench", "Rain barrel", "Crates", "Market stall", "Anvil", "Flower box", "Carved pumpkin", "Bird nest"]:
		check(styles.has(DecorationLayout.named(name)), "the village holds a %s" % name.to_lower())
	check(pieces > world.state.walls.size() * 4, "a cluttered village: %d pieces on %d builds" % [pieces, world.state.walls.size()])
	check(world.fill() <= 1.0, "within the budget: %.3f" % world.fill())
	await play([{"op": "bare"}])
