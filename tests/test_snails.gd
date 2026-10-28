extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	var terrain := Terrain.new()
	var marks := Ground.new()
	terrain.install()
	await process_frame
	var water := Water.new(terrain, [])
	root.add_child(water)
	var flora := Flora.new(terrain, marks)
	root.add_child(flora)
	var wildlife := Wildlife.new(terrain, marks, water, flora, null, Palette.new(), null, [], 3)
	root.add_child(wildlife)
	wildlife.set_process(false)
	var snails := wildlife.snails
	snails.tick(1.0)
	check(snails.crawling.is_empty(), "no pond means no snails")
	var ponds: Array[PondLayout.Pond] = []
	for spot in [Vector2(-15, -8), Vector2(-5, -8), Vector2(5, -8), Vector2(15, -8), Vector2(-15, 8), Vector2(-5, 8), Vector2(5, 8), Vector2(15, 8)]:
		var centre := Terrain.grid_point(spot.x, spot.y)
		var area := Rect2i(centre - Vector2i(4, 4), Vector2i(9, 9))
		var heights := PackedFloat32Array()
		for z in 9:
			for x in 9:
				heights.append(0.0 if x == 0 or z == 0 or x == 8 or z == 8 else -1.0)
		terrain.write(area, heights)
		ponds.append(Water.fill(terrain, centre, -0.1))
	water.show_ponds(ponds)
	for p in water.ponds:
		p._process(PondWater.FILL)
	snails.tick(0.01)
	check(snails.crawling.is_empty(), "arrival waits for the pond")
	for i in 2400:
		snails.tick(1.0 / 30.0)
	check(not snails.crawling.is_empty(), "snails arrive through wildlife")
	check(snails.crawling.size() == Snails.CAP, "global cap")
	print("snail_population: %d ponds; %d snails; cells %s" % [water.ponds.size(), snails.crawling.size(), water.ponds.map(func(p: PondWater) -> int: return p.pond.cells.size())])
	for p in water.ponds:
		check(snails.crawling.filter(func(s: Snails.One) -> bool: return s.pond == p).size() == Wildlife._pond_quota(p, water.ponds.size(), Snails.CAP, Snails.CELLS_EACH, Snails.PER_POND), "pond size determines population")
	var moved := 0.0
	var elapsed := 0
	for i in 3600:
		var before := snails.crawling[0].position
		var start := Time.get_ticks_usec()
		snails.tick(1.0 / 72.0)
		elapsed += Time.get_ticks_usec() - start
		moved += before.distance_to(snails.crawling[0].position)
		for s in snails.crawling:
			check(absf(s.position.y - terrain.height_at(s.position.x, s.position.z)) < 0.0001, "foot stays on bed")
			check(snails._wet(s.pond, s.position), "stays submerged")
	check(moved > 0.2 and moved < 1.0, "slow sustained crawl: %.3f m" % moved)
	print("snail_cost: %d animals; 3600 ticks simulation only: %.3f ms/tick; %d triangles/animal; one draw; travel %.3f m" % [snails.crawling.size(), elapsed / 3600000.0, snails.crowd.multimesh.mesh.get_surface_count() * snails.crowd.multimesh.mesh.surface_get_array_len(0) / 3, moved])
	water.clear()
	await process_frame
	snails.tick(0.1)
	check(snails.crawling.is_empty(), "pond removal removes snails")
	for n in [wildlife, water, flora]:
		n.queue_free()
	await process_frame
	finish()
