extends SceneTree

## Headless checks of shaping the ground: godot4 --headless --path game --script ../tests/test_terrain.gd

var failures := 0
var main: Node
var tool: TerrainTool


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	tool = main.terrain_tool
	_pull_raises_a_smooth_hill()
	_baking_a_live_hump_moves_nothing()
	_texture_matches_the_heights()
	_height_between_grid_points_is_continuous()
	await _raising_ground_under_a_wall_keeps_it_on_the_ground()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _all() -> PackedFloat32Array:
	return Terrain.read(Rect2i(0, 0, Terrain.VERTS, Terrain.VERTS))


func _pull_raises_a_smooth_hill() -> void:
	var original := _all()
	var c := Terrain.ground(10, 10)
	var far := Terrain.ground(10, 30)
	tool.begin(c, 4.0)
	tool.pull(3.0)
	_check(absf(Terrain.height_at(10, 10) - c.y - 3.0) < 0.01, "a live pull lifts the grabbed point by the pull")
	_check(absf(Terrain.height_at(10, 30) - far.y) < 1e-4, "ground beyond the hill stays put")
	tool.end_stroke()
	_check(absf(Terrain.height_at(10, 10) - c.y - 3.0) < 0.01, "the baked hill keeps its height, %f" % (Terrain.height_at(10, 10) - c.y))
	var steepest := 0.0
	for i in 60:
		var x := 10.0 + i * 0.25
		steepest = maxf(steepest, absf(Terrain.height_at(x + 0.05, 10) - Terrain.height_at(x - 0.05, 10)) / 0.1)
	_check(steepest < 0.8, "the hill's flank stays walkable, slope %f" % steepest)
	var raised := _all()
	main.world.undo()
	_check(_all() == original, "undo takes the hill away exactly")
	main.world.redo()
	_check(_all() == raised, "redo puts it back exactly")
	main.world.undo()
	var d := Terrain.ground(-5, 3)
	tool.begin(d, 3.0)
	tool.pull(-2.0)
	tool.end_stroke()
	_check(absf(Terrain.height_at(-5, 3) - d.y + 2.0) < 0.01, "a downward pull digs")
	main.world.undo()
	_check(_all() == original, "undo fills the dig")


func _baking_a_live_hump_moves_nothing() -> void:
	tool.begin(Terrain.ground(-12.5, 7.5), 2.0)
	tool.pull(0.6)
	var live := PackedFloat32Array()
	for i in 50:
		live.append(Terrain.height_at(-14.0 + i * 0.06, 7.5 + i * 0.013))
	tool.end_stroke()
	var worst := 0.0
	for i in 50:
		worst = maxf(worst, absf(live[i] - Terrain.height_at(-14.0 + i * 0.06, 7.5 + i * 0.013)))
	_check(worst < 1e-4, "ground under a hump grabbed between grid points stays put when it bakes, worst %f" % worst)
	main.world.undo()


func _texture_matches_the_heights() -> void:
	tool.begin(Terrain.ground(20, -20), 3.0)
	tool.pull(2.0)
	tool.end_stroke()
	var worst := 0.0
	var cells := Terrain.cells_around(20, -20, 3.0)
	for j in range(cells.position.y, cells.end.y):
		for i in range(cells.position.x, cells.end.x):
			var h := Terrain.height_at(-Terrain.SIZE * 0.5 + i * Terrain.STEP, -Terrain.SIZE * 0.5 + j * Terrain.STEP)
			worst = maxf(worst, absf(Terrain._image.get_pixel(i, j).r - h))
	_check(worst < 0.02, "the GPU's heights match the CPU's after an edit, worst %f" % worst)
	main.world.undo()


func _height_between_grid_points_is_continuous() -> void:
	var worst := 0.0
	for i in 400:
		var x := -20.0 + i * 0.1
		worst = maxf(worst, absf(Terrain.height_at(x + 0.001, 1.3) - Terrain.height_at(x, 1.3)))
	_check(worst < 0.01, "the ground has no steps between grid points, worst %f" % worst)


func _on_ground(w: Wall) -> float:
	var worst := 0.0
	for p in w.layout.samples:
		worst = maxf(worst, absf(p.y + 0.12 - Terrain.height_at(p.x, p.z)))
	return worst


func _settles(w: Wall, what: String) -> void:
	var frames := 0
	while (w.laying() or not w._settled) and frames < 300:
		await process_frame
		frames += 1
	_check(not w.laying() and w._settled, what)


func _raising_ground_under_a_wall_keeps_it_on_the_ground() -> void:
	await _play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-4, -2], [0, -3], [4, -2]], "seconds": 0.4},
	])
	var w: Wall = main.tool.walls[-1]
	var mid := w.layout.samples[w.layout.samples.size() / 2]
	await _play([{"op": "sculpt", "x": mid.x, "z": mid.z, "lift": 2.5, "radius": 5.0, "seconds": 0.5}])
	await _settles(w, "a wall the ground rose under settles")
	_check(_on_ground(w) < 0.01, "after the ground rose under it every wall sample sits on the ground, worst gap %f" % _on_ground(w))
	_check(w.layout.samples[w.layout.samples.size() / 2].y > mid.y + 2.0, "the wall rose with the hill")
	var buried := 0
	for s in w.layout.stones:
		var o: Vector3 = s.xform.origin
		if o.y < Terrain.height_at(o.x, o.z) - 0.6:
			buried += 1
	_check(buried == 0, "no stone is left buried under the raised ground, %d are" % buried)
	await _play([{"op": "press", "button": "dpad_down"}])
	await _settles(w, "a wall the ground sank back under settles")
	_check(_on_ground(w) < 0.01 and absf(w.layout.samples[w.layout.samples.size() / 2].y - mid.y) < 0.01, "undoing the hill sets the wall back down on the ground")


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
