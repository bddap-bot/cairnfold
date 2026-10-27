extends "res://../tests/support/suite.gd"

## Headless checks that demo/paths.json lays every path surface, stepping stones across its pond and beds of
## vegetables, and that the stress scene's materials/* phases look over the meadow's paths in cobbles and full beds:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_materials_demo.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await process_frame
	main.world.bounded = false
	await _demo()
	await _stress()
	finish()


## What `path` lays on the ground and water as they stand now.
func _pieces(path: PathLayout, kind: String) -> Array:
	return path.pieces(main.world.terrain.height_at, main.world.terrain.water_at).filter(func(p: Dictionary) -> bool: return p.kind == kind)


## Whether every plant of every bed among `paths` stands: none of its spots dropped for water.
func _beds_full(paths: Array[PathLayout]) -> bool:
	var beds := paths.filter(func(p: PathLayout) -> bool: return p.surface == PathLayout.Surface.BED)
	return not beds.is_empty() and beds.all(func(p: PathLayout) -> bool: return not p.crop_spots().any(func(spot: Dictionary) -> bool: return main.world.terrain.water_at(spot.at.x, spot.at.z) > main.world.terrain.height_at(spot.at.x, spot.at.z) + PathLayout.WET))


func _demo() -> void:
	var steps := Driver.read("res://../demo/paths.json")
	var from := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "materials")
	var to := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "floating")
	check(from >= 0 and to > from, "demo/paths.json has a materials section")
	await play(steps.slice(from, to).filter(func(s: Dictionary) -> bool: return s.op != "capture"))
	await until(func() -> bool: return main.water.ponds.size() > 0, "the demo's pond fills")
	var paths: Array[PathLayout] = main.tool.paths.layouts
	var surfaces := {}
	for p in paths:
		surfaces[p.surface] = true
	check(surfaces.size() == PathLayout.Surface.size(), "the demo lays every surface: %s" % [surfaces.keys()])
	var across := paths.filter(func(p: PathLayout) -> bool: return not _pieces(p, "block").is_empty())
	check(across.size() == 1, "the path across the pond lays stepping stones: %d" % across.size())
	var beds := paths.filter(func(p: PathLayout) -> bool: return p.surface == PathLayout.Surface.BED)
	check(beds.size() == 3 and beds.all(func(p: PathLayout) -> bool: return _pieces(p, "crop").size() > 100), "three beds sprout their vegetables")
	main.world.marks.settle()
	for p in paths:
		var f := p.frame_at(p.length() * 0.2)
		check(kind_at(main.world.marks, f.point.x, f.point.z) == p.kind, "the %s path shows its own ground" % PathLayout.Surface.find_key(p.surface))
	var sand: PathLayout = paths.filter(func(p: PathLayout) -> bool: return p.surface == PathLayout.Surface.SAND)[0]
	var dirt: PathLayout = paths.filter(func(p: PathLayout) -> bool: return p.surface == PathLayout.Surface.DIRT and _pieces(p, "block").is_empty())[0]
	var meet: Vector2 = Geometry2D.segment_intersects_segment(Vector2(sand.points[0].x, sand.points[0].z), Vector2(sand.points[-1].x, sand.points[-1].z), Vector2(dirt.points[0].x, dirt.points[0].z), Vector2(dirt.points[-1].x, dirt.points[-1].z))
	var blended := false
	for i in 30:
		var c := main.world.marks._texel(meet.x - 1.5 + i * 0.1, meet.y, main.world.marks.laid)
		blended = blended or c.r > 0.1 and c.a > 0.1
	check(blended, "dirt and sand blend where they meet at %s" % meet)
	await play([{"op": "bare"}])


## The materials/* phases follow the last wipe, over a garden the build budget admits: the meadow's paths in cobbles,
## stepping stones and full beds.
func _stress() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var aerial := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "materials/aerial")
	check(aerial >= 0 and steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "materials/ground"), "the stress scene has materials/aerial and materials/ground phases")
	if aerial < 0:
		return
	var wiped := aerial
	while steps[wiped].op != "bare":
		wiped -= 1
	var paves := steps.slice(wiped, aerial).filter(func(s: Dictionary) -> bool: return s.op == "pave")
	await play([steps[0], {"op": "budget", "bounded": true}] + steps.slice(wiped, aerial).filter(func(s: Dictionary) -> bool: return s.op in ["bare", "dig", "pave"]))
	await until(func() -> bool: return main.water.ponds.size() > 0, "the stress pond fills")
	var paths: Array[PathLayout] = main.tool.paths.layouts
	check(paths.size() == paves.size(), "the build budget admits every path the phases look over: %d of %d" % [paths.size(), paves.size()])
	check(paths.any(func(p: PathLayout) -> bool: return p.surface == PathLayout.Surface.COBBLES), "the meadow's paths are cobbled")
	check(_beds_full(paths), "every bed is full")
	check(paths.any(func(p: PathLayout) -> bool: return not _pieces(p, "block").is_empty()), "a path crosses the pond on stepping stones")
