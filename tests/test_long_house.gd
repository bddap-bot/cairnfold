extends "res://../tests/support/booted.gd"


func _run() -> void:
	main.world.limit = INF
	await _a_chimney_far_down_a_long_ridge_stands()
	await _two_hands_stretch_a_house_only_as_long_as_a_wall_may_be()
	_every_stretch_stops_at_the_longest_wall()
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


func _two_hands_stretch_a_house_only_as_long_as_a_wall_may_be() -> void:
	await play([{"op": "house", "at": [0.0, 40.0], "size": [20.0, 5.0], "seconds": 0.2}])
	await laid()
	var house: Wall = main.tool.walls[-1]
	var rig: Rig = main.rig
	var trackers := track_hands(rig)
	var wall_z: float = house.layout.points[0].z
	var y: float = main.world.terrain.height_at(0.0, wall_z) + 1.2
	var put := func(spread: float) -> void:
		for hand in rig.hands:
			var at := Vector3(spread * (-1.0 if hand == rig.left else 1.0), y, wall_z - 2.0)
			hand.global_transform = Transform3D(Basis.looking_at(Vector3.BACK), at)
	put.call(0.2)
	await frames(3)
	for hand in rig.hands:
		Buttons.injected[Controls.key("grab", hand.tracker)] = true
		await frames(3)
	check(main.tool.held == house and main.tool._holders.size() == 2, "both hands hold the house by its front wall")
	put.call(1.6)
	await frames(3)
	var shown := Commands.length(house.layout.points)
	for hand in rig.hands:
		Buttons.injected.erase(Controls.key("grab", hand.tracker))
	await frames(3)
	await laid()
	var kept := Commands.length(main.world.state.walls[house.id].points)
	check(shown <= Commands.MAX_LENGTH and is_equal_approx(kept, shown), "a house stretched by two hands stands as long as it was shown, and no longer than a wall may be: shown %.1f, stands %.1f" % [shown, kept])
	for tracker in trackers:
		XRServer.remove_tracker(tracker)


func _every_stretch_stops_at_the_longest_wall() -> void:
	var over := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var round := i % 4 == 0
		var side := rng.randf_range(WallTool.HOUSE_SIDE, 30.0)
		var start := {"center": Vector3(rng.randf_range(-40.0, 40.0), 0.0, rng.randf_range(-40.0, 40.0)), "yaw": rng.randf_range(-PI, PI), "size": Vector2(side, side if round else rng.randf_range(WallTool.HOUSE_SIDE, 30.0)), "round": round, "rise": 0.0, "height": 2.4, "pitch": 1.9, "curve": 0.0, "overhang": 0.3}
		var way := Vector3.RIGHT.rotated(Vector3.UP, start.yaw + (PI * 0.5 if i % 2 else 0.0))
		var from: Array[Transform3D] = [Transform3D(Basis(), start.center - way * 0.2), Transform3D(Basis(), start.center + way * 0.2)]
		var spread := rng.randf_range(0.5, 40.0)
		var to: Array[Transform3D] = [Transform3D(Basis(), start.center - way * spread * rng.randf()), Transform3D(Basis(), start.center + way * spread)]
		var c := WallTool.resize(start, from, to)
		var run := Commands.length(WallTool.outline(c))
		if run > Commands.MAX_LENGTH:
			over.append([start.size, round, c.size, run])
	check(over.is_empty(), "no stretch by two hands outgrows the longest wall: %s" % [over.slice(0, 4)])
