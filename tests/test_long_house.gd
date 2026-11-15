extends "res://../tests/support/booted.gd"


func _run() -> void:
	main.world.limit = INF
	await _a_chimney_far_down_a_long_ridge_stands()
	finish()


func _a_chimney_far_down_a_long_ridge_stands() -> void:
	await play([{"op": "house", "at": [0.0, 0.0], "size": [100.0, 5.0], "seconds": 0.2}])
	await laid()
	var house: Wall = main.tool.walls[-1]
	var fit: FittingTool = main.fitting_tool
	var r := house.roof
	var spot := Vector2(45.0, r.half_span() * 0.5)
	var above: Vector3 = house.transform * (r.spot_point(spot) + Vector3.UP * (r.spot_height(spot) + 0.5))
	var aimed := fit.aim(Hand.Tool.DECORATIONS, above, Vector3.DOWN)
	check(aimed.get("what") == "chimney", "aimed 45 m down a 100 m ridge, a chimney: %s" % aimed.get("what"))
	if aimed.get("what") != "chimney":
		return
	var ghost := fit.ghost_of(aimed, above, Vector3.DOWN, null)
	check(ghost.get("fits", false), "its ghost shows it fits")
	check(fit.fit(aimed), "a press there places it")
	await frames(3)
	await laid()
	var stacks: PackedVector2Array = main.world.state.walls[house.id].roof.chimneys
	check(stacks.size() == 1 and stacks[0] == ghost.get("spot"), "the chimney stands where its ghost showed: %s for %s" % [stacks, ghost.get("spot")])
