extends "res://../tests/support/suite.gd"

## Headless checks of shaping the ground: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_terrain.gd

var tool: GroundGrab
var terrain: Terrain:
	get:
		return main.world.terrain


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	tool = main.ground_grab
	_pull_raises_a_smooth_hill()
	_baking_a_live_hump_moves_nothing()
	_texture_matches_the_heights()
	_height_between_grid_points_is_continuous()
	_pulls_go_as_far_as_the_hand()
	_a_guest_may_reshape_the_whole_ground()
	_a_ray_reaches_ground_across_the_garden()
	await _raising_ground_under_a_wall_keeps_it_on_the_ground()
	_a_lay_reads_the_ground_it_started_on()
	_raycast_skips_only_open_air()
	_chunks_meet_at_every_step()
	finish()


## The ray passes over blocks it stays above without sampling them, and finds the same ground as one that samples
## the whole way: on the ground as shaped, after a write raises a spike, and under a live hump.
func _raycast_skips_only_open_air() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var spike := Rect2i(Terrain.grid_point(30, -30), Vector2i(2, 2))
	var before := terrain.read(spike)
	var raised := before.duplicate()
	for n in raised.size():
		raised[n] += 25.0
	for phase in ["as shaped", "after a raise", "under a hump"]:
		if phase == "after a raise":
			terrain.write(spike, raised)
		if phase == "under a hump":
			terrain.set_hump(0, -20, 20, 12, 15)
		var wrong := 0
		for k in 200:
			var h := Terrain.SIZE * 0.5
			var o := Vector3(rng.randf_range(-h, h), 0, rng.randf_range(-h, h))
			o.y = terrain.height_at(o.x, o.z) + rng.randf_range(0.5, 40.0)
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.05), rng.randf_range(-1, 1)).normalized()
			var reach := terrain.exit_along(o, dir)
			var got: Variant = terrain.raycast(o, dir, reach)
			var want: Variant = _sampled_raycast(o, dir, reach)
			if (got == null) != (want == null) or (got != null and got.distance_to(want) > 0.05):
				wrong += 1
		check(wrong == 0, "%s, %d of 200 rays find other ground than a ray sampling all the way" % [phase, wrong])
	terrain.clear_hump(0)
	terrain.write(spike, before)


func _sampled_raycast(origin: Vector3, dir: Vector3, reach: float) -> Variant:
	var prev := 0.0
	var t := 0.0
	while t <= reach:
		var p := origin + dir * t
		if p.y <= terrain.height_at(p.x, p.z):
			var lo := prev
			var hi := t
			for i in 30:
				var mid := (lo + hi) * 0.5
				var q := origin + dir * mid
				if q.y <= terrain.height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev = t
		t += 0.05
	return null


func _all() -> PackedFloat32Array:
	return terrain.read(Rect2i(0, 0, Terrain.VERTS, Terrain.VERTS))


func _pull_raises_a_smooth_hill() -> void:
	var original := _all()
	var c := terrain.ground(10, 10)
	var far := terrain.ground(10, 30)
	tool.begin(tool.rig.right, c, 4.0)
	tool.pull(tool.rig.right, 3.0)
	check(absf(terrain.shown_at(10, 10) - c.y - 3.0) < 0.01, "a live pull lifts the grabbed point by the pull")
	check(absf(terrain.shown_at(10, 30) - far.y) < 1e-4, "ground beyond the hill stays put")
	tool.end_stroke(tool.rig.right)
	check(absf(terrain.height_at(10, 10) - c.y - 3.0) < 0.01, "the baked hill keeps its height, %f" % (terrain.height_at(10, 10) - c.y))
	var steepest := 0.0
	for i in 60:
		var x := 10.0 + i * 0.25
		steepest = maxf(steepest, absf(terrain.height_at(x + 0.05, 10) - terrain.height_at(x - 0.05, 10)) / 0.1)
	check(steepest < 0.8, "the hill's flank stays walkable, slope %f" % steepest)
	var raised := _all()
	main.world.undo()
	check(_all() == original, "undo takes the hill away exactly")
	main.world.redo()
	check(_all() == raised, "redo puts it back exactly")
	main.world.undo()
	var d := terrain.ground(-5, 3)
	tool.begin(tool.rig.right, d, 3.0)
	tool.pull(tool.rig.right, -2.0)
	tool.end_stroke(tool.rig.right)
	check(absf(terrain.height_at(-5, 3) - d.y + 2.0) < 0.01, "a downward pull digs")
	main.world.undo()
	check(_all() == original, "undo fills the dig")


func _baking_a_live_hump_moves_nothing() -> void:
	tool.begin(tool.rig.right, terrain.ground(-12.5, 7.5), 2.0)
	tool.pull(tool.rig.right, 0.6)
	var live := PackedFloat32Array()
	for i in 50:
		live.append(terrain.shown_at(-14.0 + i * 0.06, 7.5 + i * 0.013))
	tool.end_stroke(tool.rig.right)
	var worst := 0.0
	for i in 50:
		worst = maxf(worst, absf(live[i] - terrain.height_at(-14.0 + i * 0.06, 7.5 + i * 0.013)))
	check(worst < 1e-4, "ground under a hump grabbed between grid points stays put when it bakes, worst %f" % worst)
	main.world.undo()


func _texture_matches_the_heights() -> void:
	tool.begin(tool.rig.right, terrain.ground(20, -20), 3.0)
	tool.pull(tool.rig.right, 2.0)
	tool.end_stroke(tool.rig.right)
	var worst := 0.0
	var tilt := 0.0
	var cells := Terrain.cells_around(20, -20, 3.0).grow(1)
	var e := Terrain.STEP
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			var x := -Terrain.SIZE * 0.5 + i * e
			var z := -Terrain.SIZE * 0.5 + j * e
			var t := terrain._image.get_pixel(i, j)
			worst = maxf(worst, absf(t.r + t.b - terrain.height_at(x, z)))
			var n := Vector3(terrain.height_at(x - e, z) - terrain.height_at(x + e, z), 2.0 * e, terrain.height_at(x, z - e) - terrain.height_at(x, z + e)).normalized()
			tilt = maxf(tilt, Vector2(t.g - n.x, t.a - n.z).length())
	check(worst < 0.02, "the GPU's heights match the CPU's after an edit, worst %f" % worst)
	check(tilt < 0.002, "the GPU's normals match the CPU's heights after an edit, around it too, worst %f" % tilt)
	main.world.undo()


## The texture's height against the CPU's at every grid point.
func _texture_error() -> float:
	var worst := 0.0
	for j in Terrain.VERTS:
		for i in Terrain.VERTS:
			var t := terrain._image.get_pixel(i, j)
			worst = maxf(worst, absf(t.r + t.b - terrain._heights[j * Terrain.VERTS + i]))
	return worst


func _pulls_go_as_far_as_the_hand() -> void:
	var original := _all()
	var clean: Variant = bytes_to_var(var_to_bytes(main.world.snapshot()))
	var c := terrain.ground(-30, 25)
	var ground: Node = main.get_children().filter(func(n: Node) -> bool: return n is Meadow)[0]
	var meadow: MeshInstance3D = ground.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.mesh is ArrayMesh)[0]
	for lift in [600.0, -900.0]:
		tool.begin(tool.rig.right, c, 4.0)
		tool.pull(tool.rig.right, lift)
		check(absf(terrain.shown_at(c.x, c.z) - c.y - lift) < 0.01, "a live pull of %d m moves the grabbed point all the way, %f" % [lift, terrain.shown_at(c.x, c.z) - c.y])
		check(meadow.custom_aabb.has_point(Vector3(c.x, terrain.shown_at(c.x, c.z), c.z)), "the ground's box holds a live pull of %d m" % lift)
		tool.end_stroke(tool.rig.right)
		var h := terrain.height_at(c.x, c.z)
		check(absf(h - c.y - lift) < 0.01, "a stroke of %d m bakes all the way, %f" % [lift, h - c.y])
		check(_texture_error() < 0.001, "the GPU's heights match the CPU's to a millimetre %d m off, worst %f" % [lift, _texture_error()])
		check(terrain.bounds().has_point(terrain.ground(c.x, c.z)) and meadow.custom_aabb.has_point(terrain.ground(c.x, c.z)), "the ground's box holds a %d m stroke" % lift)
		check(main.rig.far() > terrain.bounds().size.length(), "the eyes see the whole ground %d m off" % lift)
		var kept: Variant = bytes_to_var(var_to_bytes(main.world.snapshot()))
		main.world.undo()
		check(_all() == original, "undo takes a %d m stroke away exactly" % lift)
		check(main.world.restore_whole(kept) and absf(terrain.height_at(c.x, c.z) - h) < 1e-4, "a saved garden keeps a %d m stroke" % lift)
		check(main.world.restore_whole(bytes_to_var(var_to_bytes(clean))) and _all() == original, "the garden as it was comes back after a %d m stroke" % lift)


func _a_guest_may_reshape_the_whole_ground() -> void:
	var values := _all()
	for n in values.size():
		values[n] += 2000.0 if n % 2 else -2000.0
	var cmd := {"op": "heights", "cells": Terrain.ALL, "values": values}
	check(not Commands.clean(cmd, main.world.state, false, main.world.terrain).is_empty(), "a guest's stroke may cover the whole ground and reach 2 km either way")
	values[7] = NAN
	check(Commands.clean(cmd, main.world.state, false, main.world.terrain).is_empty(), "a guest's stroke with no height is turned down")


func _a_ray_reaches_ground_across_the_garden() -> void:
	var from := terrain.ground(-70, 0) + Vector3.UP * 20.0
	var to := terrain.ground(70, 0)
	var hit: Variant = terrain.raycast(from, (to - from).normalized())
	check(hit != null and (hit as Vector3).distance_to(to) < 1.0, "a hand reaches ground across the whole garden, %s for %s" % [hit, to])
	check(terrain.raycast(from, Vector3(1, 0.2, 0).normalized()) == null, "a ray into the sky still meets nothing")


func _height_between_grid_points_is_continuous() -> void:
	var worst := 0.0
	for i in 400:
		var x := -20.0 + i * 0.1
		worst = maxf(worst, absf(terrain.height_at(x + 0.001, 1.3) - terrain.height_at(x, 1.3)))
	check(worst < 0.01, "the ground has no steps between grid points, worst %f" % worst)


func _on_ground(w: Wall) -> float:
	var worst := 0.0
	for p in w.layout.samples:
		worst = maxf(worst, absf(p.y + 0.12 - terrain.height_at(p.x, p.z)))
	return worst


func _settles(w: Wall, what: String) -> void:
	for i in 300:
		w.lay_now()
		if w._settled:
			break
		await process_frame
	check(w._settled, what)


func _raising_ground_under_a_wall_keeps_it_on_the_ground() -> void:
	await play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-4, -2], [0, -3], [4, -2]], "seconds": 0.4},
	])
	var w: Wall = main.tool.walls[-1]
	var mid := w.layout.samples[w.layout.samples.size() / 2]
	await play([{"op": "sculpt", "x": mid.x, "z": mid.z, "lift": 2.5, "radius": 5.0, "seconds": 0.5}])
	await _settles(w, "a wall the ground rose under settles")
	check(_on_ground(w) < 0.01, "after the ground rose under it every wall sample sits on the ground, worst gap %f" % _on_ground(w))
	check(w.layout.samples[w.layout.samples.size() / 2].y > mid.y + 2.0, "the wall rose with the hill")
	var buried := 0
	for s in w.layout.stones:
		var o: Vector3 = s.xform.origin
		if o.y < terrain.height_at(o.x, o.z) - 0.6:
			buried += 1
	check(buried == 0, "no stone is left buried under the raised ground, %d are" % buried)
	await play([{"op": "press", "button": "dpad_down"}])
	await _settles(w, "a wall the ground sank back under settles")
	check(_on_ground(w) < 0.01 and absf(w.layout.samples[w.layout.samples.size() / 2].y - mid.y) < 0.01, "undoing the hill sets the wall back down on the ground")


## A dig while a wall is being laid: the worker threads are held until the dig is done, and the lay must read
## the ground as it stood when the lay began, not the live heights the dig rewrote and reallocated (#13).
func _a_lay_reads_the_ground_it_started_on() -> void:
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var laid := w.layout.samples.duplicate()
	var gate := Semaphore.new()
	var started := Semaphore.new()
	var holds := []
	for t in OS.get_processor_count():
		holds.append(WorkerThreadPool.add_task(func() -> void:
			started.post()
			gate.wait(), true))
	for h in holds:
		started.wait()
	w.rebuild(false)
	var cells := Terrain.cells_around(0, -2.5, 6.0)
	var before := terrain.read(cells)
	var shared := terrain.read(Terrain.ALL)
	var dug := before.duplicate()
	for n in dug.size():
		dug[n] -= 1.0
	terrain.write(cells, dug)
	shared = PackedFloat32Array()
	for h in holds:
		gate.post()
	for h in holds:
		WorkerThreadPool.wait_for_task_completion(h)
	w.lay_now()
	var worst := 0.0
	for n in laid.size():
		worst = maxf(worst, absf(w.layout.samples[n].y - laid[n].y))
	check(w.layout.samples.size() == laid.size() and worst < 0.001, "a lay begun before a dig stands on the ground it began on, worst %f" % worst)
	terrain.write(cells, before)
	w.rebuild()
	w.lay_now()


## Every chunk at every grid step has a vertex every STEP along its edge and covers its square once over, so chunks
## drawn at different steps meet with no crack and no overlap.
func _chunks_meet_at_every_step() -> void:
	var size := Terrain.CHUNK * Terrain.STEP
	for k in Terrain.LODS:
		var arrays := Terrain.chunk_mesh(2, 3, k).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var corner := Terrain.grid_xz(Vector2i(2, 3) * Terrain.CHUNK)
		var edge := {}
		for p in verts:
			var at := Vector2(p.x, p.z) - corner
			if is_zero_approx(at.x) or is_zero_approx(at.y) or is_equal_approx(at.x, size) or is_equal_approx(at.y, size):
				edge[Vector2i(roundi(at.x), roundi(at.y))] = true
		check(edge.size() == 4 * Terrain.CHUNK, "a chunk at step %d has %d edge vertices, not one every metre" % [k, edge.size()])
		var area := 0.0
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var a := verts[idx[t]]
			var b := verts[idx[t + 1]]
			var c := verts[idx[t + 2]]
			var turn := (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
			check(turn > 0.0, "a chunk at step %d has a triangle wound the other way" % k)
			area += turn * 0.5
		check(is_equal_approx(area, size * size), "a chunk at step %d covers %.1f m², not its %.0f" % [k, area, size * size])
