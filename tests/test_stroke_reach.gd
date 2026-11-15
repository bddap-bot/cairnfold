extends "res://../tests/support/booted.gd"


func _run() -> void:
	main.world.limit = INF
	await _a_last_move_past_the_longest_wall_stops_there()
	await _a_join_along_an_arcade_stops_there()
	finish()


func _path_at(d: float) -> Vector3:
	if d < 140.0:
		return Vector3(-70.0 + d, 0.0, -70.0)
	return Vector3(70.0, 0.0, -70.0 + (d - 140.0))


func _draw(to: float, last: Vector3) -> Array:
	var tool: WallTool = main.tool
	var terrain := main.world.terrain
	var m: WallTool.Mason = tool.masons[0]
	var start := _path_at(0.0)
	tool.begin_stroke(m, terrain.ground(start.x, start.z))
	var d := 0.0
	while d < to and Commands.length(m.stroke.points) < Commands.STROKE_LENGTH:
		d += 0.3
		var p := _path_at(d)
		tool.extend_stroke(m, terrain.ground(p.x, p.z))
	tool.extend_stroke(m, terrain.ground(last.x, last.z))
	tool._plan(m.stroke, true)
	var shown: Array = m.stroke.walls.map(func(w: Wall) -> float: return Commands.length(w.layout.points))
	var before: int = main.world.state.walls.size()
	tool.end_stroke(m)
	await frames(4)
	var stood: int = main.world.state.walls.size() - before
	return [shown, stood]


func _a_last_move_past_the_longest_wall_stops_there() -> void:
	var drawn := await _draw(Commands.STROKE_LENGTH - 0.3, _path_at(Commands.STROKE_LENGTH + 24.0))
	check(drawn[0].max() <= Commands.MAX_LENGTH and drawn[1] == drawn[0].size(), "a stroke whose last move jumps 24 m on stands no longer than a wall may be: shown %s, %d stood" % drawn)
	main.world.submit({"op": "wipe"})
	await frames(4)


func _a_join_along_an_arcade_stops_there() -> void:
	var terrain := main.world.terrain
	var arcade := PackedVector4Array(range(12).map(func(k: int) -> Vector4: return WallLayout.archway(WallLayout.ARCH_END + k * WallLayout.ARCADE_GAP)))
	main.world.submit({"op": "wall", "walls": [wall_data({"points": PackedVector3Array([terrain.ground(71.5, 12.0), terrain.ground(71.5, 60.0)]), "seed": 6, "openings": arcade})]})
	await frames(4)
	await laid()
	var drawn := await _draw(225.6, _path_at(225.9))
	check(drawn[0].max() <= Commands.MAX_LENGTH and drawn[1] == drawn[0].size(), "a stroke that meets a wall leading an arcade stands no longer than a wall may be: shown %s, %d stood" % drawn)
	main.world.submit({"op": "wipe"})
	await frames(4)
