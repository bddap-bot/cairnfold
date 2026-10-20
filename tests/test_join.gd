extends SceneTree

## Walls drawn among standing walls and plants, through the driver: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_join.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _a_wall_drawn_tight_alongside_another_never_doubles_it()
	await _the_preview_over_a_bush_is_the_wall_left_on_release()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _a_wall_drawn_tight_alongside_another_never_doubles_it() -> void:
	var walls: Array[Wall] = main.tool.walls
	await _play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "wall", "points": [[-6, -20], [6, -20]], "seconds": 0.5},
		{"op": "wall", "points": [[-5, -19.4], [5, -19.4]], "seconds": 0.5},
	])
	var first := walls[0].layout
	for w in walls.slice(1):
		for p in w.layout.samples:
			var d := Vector2(p.x - clampf(p.x, first.samples[0].x, first.samples[-1].x), p.z - first.samples[0].z).length()
			_check(d < 0.01 or d >= WallPlan.REACH - 0.01, "a wall drawn 0.6 m alongside another stands %.2f m from it" % d)
	_check(walls.size() == 1, "the stroke merges into the wall it hugs, leaving %d walls" % walls.size())

	await _play([{"op": "wall", "points": [[0, -19.6], [0, -14]], "seconds": 0.5}])
	_check(walls.size() == 2, "a stroke leaving the wall builds one more, %d walls" % walls.size())
	if walls.size() == 2:
		_check(absf(walls[1].layout.samples[0].z + 20.0) < 0.05, "and starts on the wall's centre line, z=%.2f" % walls[1].layout.samples[0].z)


func _the_preview_over_a_bush_is_the_wall_left_on_release() -> void:
	var tool: WallTool = main.tool
	var bush := Terrain.ground(-1.0, 20.0)
	tool.flora.add_bush(bush, RandomNumberGenerator.new())
	var m := tool.mason(main.rig.right)
	var path: Array[Vector3] = [Terrain.ground(-4.0, 20.0), Terrain.ground(2.5, 20.0)]
	tool.begin_stroke(m, path[0])
	for f in 40:
		await process_frame
		tool.extend_stroke(m, Driver._along(path, (f + 1) / 40.0))
	tool._flush()
	while m.stroke.walls.any(func(w: Wall) -> bool: return w.laying()):
		await process_frame
	_check(m.stroke.walls.size() == 1 and m.stroke.walls[0].layout.archways().size() == 1, "the preview arches over the bush while drawing")
	var shown := _stones(m.stroke.walls)
	var preview := m.stroke.walls.size()
	var before := tool.walls.size()
	tool.end_stroke(m)
	var kept := tool.walls.slice(before)
	_check(kept.size() == preview, "release leaves the preview's walls")
	_check(_alike(shown, _stones(kept)), "and their stones stand where the preview showed them")
	if kept.size() == 1 and kept[0].layout.archways().size() == 1:
		var at: Vector3 = kept[0].layout.point_at(kept[0].layout.archways()[0])
		_check(Vector2(at.x - bush.x, at.z - bush.z).length() < 0.3, "the arch stands over the bush")


## Stone buffers equal but for the rounding of the wall's points to the 32-bit floats a build command carries.
func _alike(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x: PackedFloat32Array = a[i]
		var y: PackedFloat32Array = b[i]
		if x.size() != y.size():
			return false
		for k in x.size():
			if absf(x[k] - y[k]) > 1e-3:
				return false
	return true


func _stones(ws: Array) -> Array:
	var out := []
	for w: Wall in ws:
		out.append(w._parts[Wall.Part.STONE])
	return out
