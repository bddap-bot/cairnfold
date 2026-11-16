extends "res://../tests/support/booted.gd"

const DEPTH := WallTool.HOUSE_SIZE.y
const LONG := (Commands.MAX_LENGTH - DEPTH) * 0.5 * 0.85
const SHORT := Commands.MAX_LENGTH / 12.0
const GRIP := 0.2


func _run() -> void:
	main.world.limit = INF
	await _a_chimney_far_down_a_long_ridge_stands()
	await _two_hands_stretch_a_house_only_as_long_as_a_wall_may_be()
	_every_stretch_stops_at_the_longest_wall()
	finish()


func _a_chimney_far_down_a_long_ridge_stands() -> void:
	await play([{"op": "house", "at": [0.0, 0.0], "size": [LONG, DEPTH], "seconds": 0.2}])
	await laid()
	var house: Wall = main.tool.walls[-1]
	var fit: FittingTool = main.fitting_tool
	var r := house.roof
	var spot := Vector2(LONG * 0.45, r.half_span() * 0.5)
	var above: Vector3 = house.transform * (r.spot_point(spot) + Vector3.UP * (r.spot_height(spot) + 0.5))
	var aimed := fit.aim(Hand.Tool.DECORATIONS, above, Vector3.DOWN)
	check(aimed.get("what") == "chimney", "aimed %.0f m down a %.0f m ridge, a chimney: %s" % [spot.x, LONG, aimed.get("what")])
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
	await play([{"op": "house", "at": [0.0, Terrain.SIZE * 0.25], "size": [SHORT, DEPTH], "seconds": 0.2}])
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
	put.call(GRIP)
	await frames(3)
	for hand in rig.hands:
		Buttons.injected[Controls.key("grab", hand.tracker)] = true
		await frames(3)
	check(main.tool.held == house and main.tool._holders.size() == 2, "both hands hold the house by its front wall")
	put.call(GRIP * Commands.MAX_LENGTH / SHORT)
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
	var short := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var room := Terrain.SIZE * 0.25
	var widest := Commands.MAX_LENGTH / 8.0
	for i in 400:
		var tower := i % 4 == 0
		var start := WallTool.stance(Vector3(rng.randf_range(-room, room), 0.0, rng.randf_range(-room, room)), rng.randf_range(-PI, PI), tower)
		var side := rng.randf_range(WallTool.HOUSE_SIDE, widest)
		start.size = Vector2(side, side if tower else rng.randf_range(WallTool.HOUSE_SIDE, widest))
		var way := Vector3.RIGHT.rotated(Vector3.UP, start.yaw + (PI * 0.5 if i % 2 else 0.0))
		var from: Array[Transform3D] = [Transform3D(Basis(), start.center - way * GRIP), Transform3D(Basis(), start.center + way * GRIP)]
		var spread := GRIP * rng.randf_range(1.0, Commands.MAX_LENGTH / WallTool.HOUSE_SIDE)
		var to: Array[Transform3D] = [Transform3D(Basis(), start.center - way * spread * rng.randf()), Transform3D(Basis(), start.center + way * spread)]
		var c := WallTool.resize(start, from, to)
		var run := Commands.length(WallTool.outline(c))
		var farther: Array[Transform3D] = [to[0], Transform3D(Basis(), to[1].origin + way * spread)]
		var capped: bool = WallTool.resize(start, from, farther).size == c.size
		if run > Commands.MAX_LENGTH:
			over.append([start.size, tower, c.size, run])
		elif capped and run < Commands.GROWN_LENGTH - (Commands.MAX_LENGTH - Commands.GROWN_LENGTH):
			short.append([start.size, tower, c.size, run])
	check(over.is_empty(), "no stretch by two hands outgrows the longest wall: %s" % [over.slice(0, 4)])
	check(short.is_empty(), "a stretch past it stops at it: %s" % [short.slice(0, 4)])
