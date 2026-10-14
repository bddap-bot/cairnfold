extends SceneTree

## Headless checks of shaping the ground: godot4 --headless --path game --script ../tests/test_terrain.gd

var failures := 0
var main: Node


func _initialize() -> void:
	Terrain.install()
	_pull_raises_a_smooth_hill()
	_baking_a_live_hump_moves_nothing()
	_dig_lowers_and_restore_undoes()
	_height_between_grid_points_is_continuous()
	_texture_matches_the_heights()
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _raising_ground_under_a_wall_keeps_it_on_the_ground()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _all() -> PackedFloat32Array:
	return Terrain.read(Rect2i(0, 0, Terrain.VERTS, Terrain.VERTS))


func _pull_raises_a_smooth_hill() -> void:
	var original := _all()
	var tool := TerrainTool.new()
	var c := Terrain.ground(10, 10)
	var far := Terrain.ground(10, 30)
	tool.begin(c, 4.0)
	tool.pull(3.0)
	_check(absf(Terrain.height_at(10, 10) - c.y - 3.0) < 0.01, "a live pull lifts the grabbed point by the pull")
	_check(absf(Terrain.height_at(10, 30) - far.y) < 1e-4, "ground beyond the hill stays put")
	var edit := tool.end()
	_check(absf(Terrain.height_at(10, 10) - c.y - 3.0) < 0.01, "the baked hill keeps its height, %f" % (Terrain.height_at(10, 10) - c.y))
	_check(edit.cells.has_point(Vector2i(90, 90)), "the edit names the cells it changed")
	var steepest := 0.0
	for i in 60:
		var x := 10.0 + i * 0.25
		steepest = maxf(steepest, absf(Terrain.height_at(x + 0.05, 10) - Terrain.height_at(x - 0.05, 10)) / 0.1)
	_check(steepest < 0.8, "the hill's flank stays walkable, slope %f" % steepest)
	tool.restore(edit.cells, edit.before)
	_check(_all() == original, "restoring the before heights undoes the stroke exactly")
	tool.restore(edit.cells, edit.after)
	_check(_all() != original, "restoring the after heights redoes it")
	tool.restore(edit.cells, edit.before)
	tool.free()


func _baking_a_live_hump_moves_nothing() -> void:
	var tool := TerrainTool.new()
	tool.begin(Terrain.ground(-12.5, 7.5), 2.0)
	tool.pull(0.6)
	var live := PackedFloat32Array()
	for i in 50:
		live.append(Terrain.height_at(-14.0 + i * 0.06, 7.5 + i * 0.013))
	var edit := tool.end()
	var worst := 0.0
	for i in 50:
		worst = maxf(worst, absf(live[i] - Terrain.height_at(-14.0 + i * 0.06, 7.5 + i * 0.013)))
	_check(worst < 1e-4, "ground under a hump grabbed between grid points stays put when it bakes, worst %f" % worst)
	tool.restore(edit.cells, edit.before)
	tool.free()


func _dig_lowers_and_restore_undoes() -> void:
	var tool := TerrainTool.new()
	var c := Terrain.ground(-5, 3)
	tool.begin(c, 3.0)
	tool.pull(-2.0)
	var edit := tool.end()
	_check(Terrain.height_at(-5, 3) < c.y - 1.9, "a downward pull digs")
	tool.restore(edit.cells, edit.before)
	_check(absf(Terrain.height_at(-5, 3) - c.y) < 1e-6, "undoing the dig fills it")
	tool.free()


func _height_between_grid_points_is_continuous() -> void:
	var worst := 0.0
	for i in 400:
		var x := -20.0 + i * 0.1
		worst = maxf(worst, absf(Terrain.height_at(x + 0.001, 1.3) - Terrain.height_at(x, 1.3)))
	_check(worst < 0.01, "the ground has no steps between grid points, worst %f" % worst)


func _texture_matches_the_heights() -> void:
	var tool := TerrainTool.new()
	tool.begin(Terrain.ground(20, -20), 3.0)
	tool.pull(2.0)
	var edit := tool.end()
	var worst := 0.0
	for j in range(edit.cells.position.y, edit.cells.end.y):
		for i in range(edit.cells.position.x, edit.cells.end.x):
			var h := Terrain.height_at(-Terrain.SIZE * 0.5 + i * Terrain.STEP, -Terrain.SIZE * 0.5 + j * Terrain.STEP)
			worst = maxf(worst, absf(Terrain._image.get_pixel(i, j).r - h))
	_check(worst < 0.02, "the GPU's heights match the CPU's after an edit, worst %f" % worst)
	tool.restore(edit.cells, edit.before)
	tool.free()


func _raising_ground_under_a_wall_keeps_it_on_the_ground() -> void:
	await _play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-4, -2], [0, -3], [4, -2]], "seconds": 0.4},
	])
	var w: Wall = main.tool.walls[-1]
	var mid := w.layout.samples[w.layout.samples.size() / 2]
	await _play([{"op": "sculpt", "x": mid.x, "z": mid.z, "lift": 2.5, "radius": 5.0, "seconds": 0.5}])
	var worst := 0.0
	for p in w.layout.samples:
		worst = maxf(worst, absf(p.y + 0.12 - Terrain.height_at(p.x, p.z)))
	_check(worst < 0.01, "after the ground rose under it every wall sample sits on the ground, worst gap %f" % worst)
	_check(w.layout.samples[w.layout.samples.size() / 2].y > mid.y + 2.0, "the wall rose with the hill")
	var stones_ok := true
	for s in w.layout.stones:
		var o: Vector3 = s.xform.origin
		if o.y < Terrain.height_at(o.x, o.z) - 0.6:
			stones_ok = false
	_check(stones_ok, "no stone is left buried under the raised ground")


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
