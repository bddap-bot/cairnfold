extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var world: World = main.world
	var flora: Flora = main.flora_tool.flora
	world.limit = INF
	var stone := Ground.Stroke.new(Ground.Kind.STONE)
	stone.add(world.marks, 7, 0, 1, 2)
	world._order({"op": "ground", "kind": int(Ground.Kind.STONE), "stamps": stone.stamps}, 1)
	world._order({"op": "plant", "kind": "moss", "seed": 42, "dabs": [[main.world.terrain.ground(7, 0), 0.8, 100]]}, 1)
	var moss_id := world.seq
	flora.grow_now()
	check(flora.groups[moss_id].size() == 100 and world.state.groups[moss_id].skip.is_empty(), "moss paints stone instead of skipping it")
	check(world.units.get("moss", 0) == 100, "moss consumes its build budget")
	world._order({"op": "plant", "kind": "tree", "seed": 11, "at": main.world.terrain.ground(7, 0)}, 1)
	var tree_id := world.seq
	world._order({"op": "tree", "group": tree_id, "index": 0, "moss": true}, 1)
	world._order({"op": "tree", "group": tree_id, "index": 0, "scale": 1.5}, 1)
	var trunk: Flora.Plant = flora.groups[tree_id][0]
	check(world.state.groups[tree_id].moss.get(0, false) and is_equal_approx(flora.scale_of(trunk), 1.5), "tree scale preserves bark moss")
	world._order({"op": "undo"}, 1)
	world._order({"op": "undo"}, 1)
	check(not world.state.groups[tree_id].moss.get(0, false), "undo removes the trunk coat")
	world._order({"op": "redo"}, 1)
	var saved := world.snapshot()
	world.restore(saved)
	flora.grow_now()
	trunk = flora.groups[tree_id][0]
	check(world.state.groups[tree_id].moss.get(0, false), "snapshot restores moss on bark")
	check(flora.groups[moss_id].size() == 100, "snapshot restores ground moss")
	var start := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in Flora.PAINTED_MOSS:
		flora.add_moss(main.world.terrain.ground(rng.randf_range(-2, 2), rng.randf_range(-2, 2)), rng)
	print("moss cost: %d patches, %d triangles, %.3f ms to fill; Quest 2 reserved %.3f ms" % [Flora.PAINTED_MOSS, Flora.PAINTED_MOSS * 12, (Time.get_ticks_usec() - start) / 1000.0, Budget.cost_ms({"moss": Flora.PAINTED_MOSS})])
	finish()
