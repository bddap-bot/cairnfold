extends "res://../tests/support/suite.gd"

## Headless checks that demo/paths.json runs paths into houses that open doors, and that the stress scene's doors/*
## village opens one in every house a path runs into: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_doors_demo.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await process_frame
	await _demo()
	await _stress_village()
	finish()


## The doors a path opened in `w`: its plank doors that none of its stored openings make.
func _path_doors(w: Wall) -> Array:
	var stored: Array[Vector4] = []
	stored.assign(Array(main.world.state.walls[w.id].openings))
	var own := w.layout.openings_for(stored)
	return w.layout.apertures.filter(func(o: Dictionary) -> bool: return o.door and o.style == WallLayout.Family.COTTAGE and not own.any(func(e: Dictionary) -> bool: return absf(w.layout.offset(e.s, o.s)) < 0.05))


## `demo/paths.json` runs a narrow path into one house, a single door its width, and puts another up over a wide path,
## a double door.
func _demo() -> void:
	for step: Dictionary in Driver.read("res://../demo/paths.json"):
		if step.op in ["quit", "capture"]:
			continue
		await play([step])
	var houses: Array[Wall] = []
	houses.assign(main.tool.walls.filter(func(w: Wall) -> bool: return w.layout.floored()))
	for w in houses:
		w.lay_now()
	check(houses.size() == 2, "the demo puts up two houses: %d" % houses.size())
	if houses.size() == 2:
		var lights := houses.map(func(w: Wall) -> Array: return _path_doors(w).map(func(o: Dictionary) -> int: return o.lights))
		check(lights == [[1], [2]], "the narrow path opens a single door and the wide one a double door: %s" % [lights])
	await play([{"op": "bare"}])


## The stress scene's doors/* phases look over a village where every house a path runs into opens a door there.
func _stress_village() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var first := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "doors/aerial")
	check(first >= 0 and steps.any(func(s: Dictionary) -> bool: return s.get("name", "") == "doors/ground"), "the stress scene has doors/aerial and doors/ground phases")
	if first < 0:
		return
	var village := village_before(steps, first)
	check(steps.slice(village, first).all(func(s: Dictionary) -> bool: return s.op != "clear"), "the doors phases look over that village")
	await play([steps[0], steps[village]])
	var fronts := 0
	var opened := 0
	for w: Wall in main.tool.walls:
		w.lay_now()
		if not w.layout.floored() or not w.on.is_empty():
			continue
		for p in main.tool.paths.layouts:
			if not p.meetings(w.layout).is_empty():
				fronts += 1
				opened += 1 if not _path_doors(w).is_empty() else 0
				break
	check(fronts >= 15 and opened == fronts, "every house a path runs into opens a door: %d of %d" % [opened, fronts])
	var bare := steps.slice(first).find_custom(func(s: Dictionary) -> bool: return s.op in ["bare", "clear"])
	check(bare >= 0 and steps[first + bare].op == "bare", "the scene wipes the village's paths with it before going on")
