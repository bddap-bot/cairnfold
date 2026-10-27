extends "res://../tests/support/suite.gd"

## Headless checks of stone in ponds: stone ground painted on a pond's bed, and walls crossing water on arches
## whose pillars stand on the bed: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_pond_stone.gd

var world: World
var terrain: Terrain:
	get:
		return main.world.terrain
var marks: Ground:
	get:
		return main.world.marks


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	await _stone_lines_a_pond()
	await _a_wall_drawn_across_a_pond_arches_over_it()
	await _a_pond_dug_under_a_wall_opens_its_arches()
	await _a_snapshot_rebuilds_the_wall_in_its_pond()
	finish()


## Lets the fills, refills and walls' rebuilds on worker threads finish, and the commands waiting on them apply.
func _settle() -> void:
	main.water_tool.settle()
	await process_frame
	for w in main.tool.walls:
		while w.laying():
			await process_frame
	await process_frame


func _dig(x: float, z: float) -> void:
	await play([{"op": "dig", "x": x, "z": z, "seconds": 1.8}, {"op": "dig", "x": x + 2.5, "z": z, "seconds": 1.8}])
	await _settle()


func _wall_at(x: float, z: float) -> Wall:
	for w in main.tool.walls:
		if w.footprint().grow(0.5).has_point(Vector2(x, z)):
			return w
	return null


func _stone_lines_a_pond() -> void:
	await _dig(-30, 30)
	var water: Water = main.water
	var pond := water.pond_at(-29, 30)
	check(pond != null, "a pond to paint")
	if pond == null:
		return
	var level := pond.pond.level
	var cells := pond.pond.cells.size()
	var hit: Variant = terrain.raycast(Vector3(-29, level + 3, 33), Vector3(0, -3, -3).normalized())
	check(hit != null and hit.y < level - 0.2, "the stone tool's ray reaches the bed through the water")
	await play([{"op": "paint", "tool": "stone", "hand": "right", "points": [[-32, 30], [-26, 30]], "radius": 2.5, "seconds": 1.5}])
	await _settle()
	check(marks.stone(-29, 30) > 0.99 and marks.stone(-31.5, 30) > 0.99, "stone lies on the bed (%.2f)" % marks.stone(-29, 30))
	check(water.pond_at(-29, 30) == pond and pond.pond.level == level and pond.pond.cells.size() == cells, "and the pond is as it was dug")
	world.undo()
	await process_frame
	marks.settle()
	check(marks.stone(-29, 30) == 0.0, "undo lifts it off the bed")
	world.redo()
	await process_frame
	marks.settle()
	check(marks.stone(-29, 30) > 0.99, "redo lays it again")


func _a_wall_drawn_across_a_pond_arches_over_it() -> void:
	await _dig(30, 30)
	var pond: PondWater = main.water.pond_at(31, 30)
	check(pond != null, "a pond to cross")
	if pond == null:
		return
	await play([{"op": "wall", "points": [[25, 30], [37, 30]], "seconds": 0.5}])
	await _settle()
	var w := _wall_at(31, 30)
	check(w != null, "a wall across it")
	if w == null:
		return
	var l := w.layout
	var mid := l.closest_s(Vector3(31.2, 0, 30))
	check(absf(l.point_at(mid).y - (pond.pond.level - 0.12)) < 0.02, "over the water it stands at the surface")
	check(l.depth_at(mid) > 0.3, "with the bed %.2f m below its foot" % l.depth_at(mid))
	check(not l.archways().is_empty() and l.archways().all(func(a): return main.water.pond_at(l.point_at(a).x, l.point_at(a).z) != null), "arches open over the water: %s" % [l.archways()])
	check(l.stones.any(func(st): return st.y < -0.3), "stones reach down into the pond")
	world.undo()
	await _settle()
	check(_wall_at(31, 30) == null, "undo takes the wall out of the pond")
	check(main.water.pond_at(31, 30) == pond, "and leaves the water")


func _a_pond_dug_under_a_wall_opens_its_arches() -> void:
	await play([{"op": "wall", "points": [[-36, -30], [-24, -30]], "seconds": 0.5}])
	await _settle()
	var w := _wall_at(-30, -30)
	var dry := var_to_str(w.layout.stones)
	check(not w.layout.stones.any(func(st): return st.y < 0.0), "on dry ground nothing lies under its foot")
	await _dig(-31.5, -30)
	check(main.water.pond_at(-30.5, -30) != null, "a pond under the wall")
	check(w.layout.archways().any(func(a): return absf(a - w.layout.closest_s(Vector3(-30.5, 0, -30))) < 2.0), "the water under it opens an arch: %s" % [w.layout.archways()])
	check(w.layout.stones.any(func(st): return st.y < -0.3), "and its stones reach the bed")
	for step in 4:
		world.undo()
	await _settle()
	check(main.water.pond_at(-30.5, -30) == null, "undoing the digs drains it")
	check(var_to_str(w.layout.stones) == dry, "and the wall stands as it was on dry ground")
	for step in 4:
		world.redo()
	await _settle()
	check(w.layout.stones.any(func(st): return st.y < -0.3), "redo puts it back in the water")


func _a_snapshot_rebuilds_the_wall_in_its_pond() -> void:
	var w := _wall_at(-30, -30)
	var stones := var_to_str(w.layout.stones)
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	await _settle()
	check(main.water.ponds.is_empty() and main.tool.walls.is_empty(), "an empty garden")
	world.restore(snap)
	await _settle()
	var again := _wall_at(-30, -30)
	check(again != null and var_to_str(again.layout.stones) == stones, "a saved garden stands its wall in its pond again")
	check(marks.stone(-29, 30) > 0.99, "with the stone on the other pond's bed")
