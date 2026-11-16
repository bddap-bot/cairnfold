extends "res://../tests/support/suite.gd"


func _meadow() -> Meadow:
	for n in main.get_children():
		if n is Meadow:
			return n
	return null


func _draw_all(meadow: Meadow, full: int) -> void:
	var tiles := PackedByteArray()
	tiles.resize(Terrain.CHUNK_TILES * Terrain.CHUNK_TILES)
	tiles.fill(full)
	for c: Meadow.Chunk in meadow._chunks:
		c.show(tiles)


static func _nearest_wet_row(terrain: Terrain) -> int:
	var levels := terrain.water_levels()
	for k in levels.size():
		if levels[k] != Terrain.NO_WATER:
			return k / Terrain.VERTS
	return -1


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.world.submit({"op": "sky", "time": 0.35})
	await until(func() -> bool: return main.look._sky_time == 0.35, "the sky is painted for the hour")
	main.look.bounce.finish()
	main.look.set_process(false)
	await play([{"op": "dig", "x": -30, "z": 31, "seconds": 1.8}, {"op": "dig", "x": -27.5, "z": 31, "seconds": 1.8}])
	await play([{"op": "paint", "tool": "stone", "hand": "right", "points": [[-34, 22.5], [-24, 23]], "radius": 1.0, "seconds": 1.0}])
	main.water_tool.settle()
	await process_frame
	await play([{"op": "layer", "name": "all", "mode": "off"}, {"op": "layer", "name": "terrain"}, {"op": "layer", "name": "sun"}])
	var terrain: Terrain = main.world.terrain
	var ground := terrain.height_at(-28.7, 29)
	await play([{"op": "view", "eye": [-28.7, ground + 11.0, 29.2], "at": [-28.7, ground, 29]}])
	Engine.time_scale = 0.0
	var meadow := _meadow()
	var marked := await drawn()
	_draw_all(meadow, 1)
	var full := await drawn()
	_draw_all(meadow, 0)
	var plain := await drawn()
	Engine.time_scale = 1.0
	check(main.world.marks.stone_tiles.count(1) > 0, "a stone path marks tiles")
	var near := _nearest_wet_row(terrain)
	check(near % Terrain.TILE == 0, "the pond's near shore runs along a tile's edge: row %d" % near)
	check(pixels_apart(marked, plain) > 300, "the pond's bank and the stone draw only in the full shader: %d pixels" % pixels_apart(marked, plain))
	check(pixels_apart(marked, full, 1.5 / 255.0) == 0, "every tile drawn in the full shader changes no pixel of the tiles the meadow marks: %d apart" % pixels_apart(marked, full, 1.5 / 255.0))
	finish()
