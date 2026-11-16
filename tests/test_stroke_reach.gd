extends "res://../tests/support/booted.gd"

const LEG := 140.0
const STEP := WallTool.POINT_SPACING * 0.7
const PAST := 8.0
const ARCHES := 13


func _run() -> void:
	main.world.limit = INF
	await _a_last_move_past_the_longest_wall_stops_there()
	await _a_join_along_an_arcade_stops_there()
	finish()


func _path_at(d: float) -> Vector3:
	if d < LEG:
		return Vector3(d - LEG * 0.5, 0.0, -LEG * 0.5)
	return Vector3(LEG * 0.5, 0.0, d - LEG * 1.5)


func _draw(to: float, last: Vector3) -> Array:
	var tool: WallTool = main.tool
	var terrain := main.world.terrain
	var m: WallTool.Mason = tool.masons[0]
	var start := _path_at(0.0)
	tool.begin_stroke(m, terrain.ground(start.x, start.z))
	var d := 0.0
	while d < to and Commands.length(m.stroke.points) < Commands.STROKE_LENGTH:
		d += STEP
		var p := _path_at(d)
		tool.extend_stroke(m, terrain.ground(p.x, p.z))
	var laid: int = Cues.asked.get(Cues.Act.WALL_LAY, 0)
	for k in 4:
		tool.extend_stroke(m, terrain.ground(last.x, last.z))
		await frames(1)
	var cued: int = Cues.asked.get(Cues.Act.WALL_LAY, 0) - laid
	var before: Array = main.world.state.walls.keys()
	tool.end_stroke(m)
	await frames(4)
	var stood: Array = main.world.state.walls.keys().filter(func(id: int) -> bool: return not id in before).map(func(id: int) -> float: return Commands.length(main.world.state.walls[id].points))
	return [stood, cued]


func _a_last_move_past_the_longest_wall_stops_there() -> void:
	var drawn := await _draw(Commands.STROKE_LENGTH - STEP, _path_at(Commands.MAX_LENGTH + PAST))
	check(drawn[0].size() == 1 and drawn[0][0] <= Commands.MAX_LENGTH and drawn[0][0] > Commands.MAX_LENGTH - STEP, "a stroke whose last move jumps %.0f m past the longest wall stands as the longest wall: %s" % [PAST, drawn[0]])
	check(drawn[1] <= 1, "the hand held there lays it once: %d cues" % drawn[1])
	main.world.submit({"op": "wipe"})
	await frames(4)


func _a_join_along_an_arcade_stops_there() -> void:
	var terrain := main.world.terrain
	var foot := _path_at(Commands.STROKE_LENGTH - WallPlan.LEAVE) + Vector3.RIGHT * WallPlan.REACH * 0.8
	var run := WallLayout.ARCH_END * 2.0 + ARCHES * WallLayout.ARCADE_GAP
	var arcade := PackedVector4Array(range(ARCHES).map(func(k: int) -> Vector4: return WallLayout.archway(WallLayout.ARCH_END + k * WallLayout.ARCADE_GAP)))
	main.world.submit({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([terrain.ground(foot.x, foot.z), terrain.ground(foot.x, foot.z + run)]), "seed": 6, "openings": arcade})]})
	await frames(4)
	await laid()
	var end := Commands.STROKE_LENGTH + WallPlan.LEAVE
	var drawn := await _draw(end, _path_at(end + STEP))
	check(not drawn[0].is_empty() and drawn[0].all(func(l: float) -> bool: return l <= Commands.MAX_LENGTH), "a stroke that meets a wall leading an arcade stands no longer than a wall may be: %s" % [drawn[0]])
	main.world.submit({"op": "wipe"})
	await frames(4)
