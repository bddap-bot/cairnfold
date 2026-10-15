extends SceneTree

## Headless checks of ruins: the layout of a wall with stretches broken away, the eraser's arithmetic, the
## schema, and the delete tool's sweep through the garden: godot4 --headless --path game --script ../tests/test_ruins.gd

var failures := 0
var main: Node


func _initialize() -> void:
	_a_ruin_leaves_its_gap_clear_to_the_ground()
	_a_ruins_ends_step_down()
	_a_ruin_drops_what_stood_in_it()
	_ivy_keeps_to_the_standing_stones()
	_ruins_are_deterministic_and_keep_their_own_steps()
	_erase_widens_merges_and_trims()
	_erase_round_a_loop()
	_the_schema_checks_ruins()
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _the_eraser_sweeps_a_ruin_and_undo_mends_it()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _wall(length: float, height: float, ruins: Array[Vector2], closed := false) -> WallLayout:
	var w := WallLayout.new()
	if closed:
		w.points.assign(WallLayout.circle(Vector3.ZERO, length / TAU))
	else:
		w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.closed = closed
	w.height = height
	w.ruins = ruins
	w.build(_flat)
	return w


## Stones of the wall itself (not fallen) whose footprint reaches into [lo, hi] at height `y`.
func _standing_in(w: WallLayout, lo: float, hi: float, y: float) -> Array:
	return w.stones.filter(func(s): return s.kind != "mortar" and s.kind != "rubble" and absf(s.y - y) < s.size.y * 0.5 and s.s + s.size.x * 0.5 > lo + 0.02 and s.s - s.size.x * 0.5 < hi - 0.02)


func _a_ruin_leaves_its_gap_clear_to_the_ground() -> void:
	var w := _wall(12.0, 2.7, [Vector2(5.0, 7.0)])
	for k in w.courses():
		var y := (k + 0.5) * w.course_height()
		_check(_standing_in(w, 5.0, 7.0, y).is_empty(), "course %d stands clear of the gap" % k)
	_check(_standing_in(w, 0.0, 4.0, 0.5 * w.course_height()).size() > 0, "the foot stands either side")
	var fallen := w.stones.filter(func(s): return s.kind == "rubble")
	_check(fallen.size() >= 3 and fallen.all(func(s): return s.s >= 5.0 and s.s <= 7.0), "fallen stones lie in the gap: %d" % fallen.size())
	_check(w.stones.filter(func(s): return s.kind == "pier").size() >= 4, "both whole ends keep their piers")


func _a_ruins_ends_step_down() -> void:
	var w := _wall(16.0, 4.2, [Vector2(7.0, 9.0)])
	var prev := Vector2(7.0, 9.0)
	var narrower := false
	for k in w.breaks.size():
		var b: Vector2 = w.breaks[k][0]
		narrower = narrower or b.x > prev.x + 1e-4 or b.y < prev.y - 1e-4
		prev = b
	_check(not narrower, "every course up breaks away at least as much as the one under it, so no stone overhangs")
	_check(prev.x < 6.0 and prev.y > 10.0, "the top breaks back from the foot's gap: %s" % prev)
	_check(prev.x > 7.0 - WallLayout.RUIN_LEAN - WallLayout.RUIN_JAG - 0.01, "and leans back at most RUIN_LEAN")
	_check(w.standing(8.0) == 0.0 and w.standing(1.0) == 4.2 and w.standing(prev.x - 0.3) == 4.2, "standing is nothing in the gap and the full height away from it")
	var mid := w.standing((prev.x + 7.0) * 0.5)
	_check(mid > 0.0 and mid < 4.2, "and between on the broken step: %f" % mid)
	var caps := w.stones.filter(func(s): return s.kind == "cap" or s.kind == "merlon")
	_check(caps.size() > 0 and caps.all(func(s): return s.s + s.size.x * 0.5 <= prev.x + 0.02 or s.s - s.size.x * 0.5 >= prev.y - 0.02), "no capping over the broken top")


func _a_ruin_drops_what_stood_in_it() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(14, 0, 0)]
	w.height = 3.0
	w.arches = [4.0, 10.0]
	w.windows = [Vector2(7.0, 1.6)]
	w.lanterns = [Vector3(12.0, 1.5, 1.0)]
	w.flags = [12.0]
	w.build(_flat)
	_check(w.live_arches.size() == 2 and w.openings.size() == 1 and w.flames.size() == 1 and w.cloths.size() == 1, "whole, it has two arches, a window, a lantern and a flag")
	w.ruins = [Vector2(9.5, 13.0)]
	w.build(_flat)
	_check(w.live_arches == [4.0], "an arch in the ruin closes: %s" % [w.live_arches])
	_check(w.openings.size() == 1, "the window clear of it stays")
	_check(w.flames.is_empty() and w.cloths.is_empty(), "the lantern and flag in it go")
	var piers := w.stones.filter(func(s): return s.kind == "pier")
	_check(piers.all(func(s): return s.s < 1.0), "the ruined end loses its pier")
	w.ruins = [Vector2(6.5, 7.5)]
	w.build(_flat)
	_check(w.openings.is_empty(), "a window in a ruin closes")
	_check(not w.lantern_fits(7.0, 1.5) and w.lantern_fits(12.0, 1.5), "no lantern hangs in a ruin")


func _ivy_keeps_to_the_standing_stones() -> void:
	var w := _wall(16.0, 3.0, [Vector2(6.0, 9.0)])
	var leaves := IvyLayout.grow(w)
	_check(leaves.size() > 50, "ivy grows on what stands: %d leaves" % leaves.size())
	_check(leaves.all(func(l): return l.y <= w.standing(l.s)), "and never above the broken stones")


func _ruins_are_deterministic_and_keep_their_own_steps() -> void:
	var a := _wall(20.0, 3.0, [Vector2(4.0, 6.0)])
	var b := _wall(20.0, 3.0, [Vector2(4.0, 6.0)])
	_check(var_to_str(a.stones) == var_to_str(b.stones), "the same ruin lays the same stones")
	var c := _wall(20.0, 3.0, [Vector2(4.0, 6.0), Vector2(13.0, 15.0)])
	var steps := func(w: WallLayout) -> Array: return w.breaks.map(func(row: PackedVector2Array) -> Vector2: return row[0])
	_check(steps.call(a) == steps.call(c), "breaking a second stretch leaves the first one's steps as they were")


func _erase_widens_merges_and_trims() -> void:
	var w := _wall(12.0, 2.4, [])
	var tap := _after(w, 6.0, 6.0)
	_check(tap.size() == 1 and is_equal_approx(tap[0].y - tap[0].x, WallLayout.MIN_GAP), "a tap breaks MIN_GAP: %s" % [tap])
	_check(_after(w, 3.0, 5.0) == [Vector2(3.0, 5.0)], "a sweep breaks what it swept")
	_check(_after(w, 0.5, 3.0) == [Vector2(0.0, 3.0)], "no stub shorter than MIN_STUB stands at an end")
	_check(_after(w, -2.0, 3.0) == [Vector2(0.0, 3.0)], "a sweep past the end stops there")
	w.ruins = [Vector2(2.0, 4.0)]
	_check(_after(w, 3.5, 6.0) == [Vector2(2.0, 6.0)], "an overlapping sweep joins the ruin")
	_check(_after(w, 4.5, 6.0) == [Vector2(2.0, 6.0)], "a sweep leaving a stub between joins it too")
	_check(_after(w, 8.0, 9.0) == [Vector2(2.0, 4.0), Vector2(8.0, 9.0)], "a separate sweep makes a second ruin")
	_check(_after(w, 0.5, 11.5) == [Vector2(0.0, 12.0)], "nothing worth standing is all of it")


func _erase_round_a_loop() -> void:
	var w := _wall(20.0, 3.0, [], true)
	var total := w.length()
	var seam := _after(w, total - 1.0, total + 2.0)
	_check(seam.size() == 2 and is_equal_approx(seam[0].x, 0.0) and is_equal_approx(seam[0].y, 2.0) and is_equal_approx(seam[1].y, total), "a sweep across a loop's seam breaks both sides: %s" % [seam])
	_check(_after(w, 0.0, total) == [Vector2(0.0, total)], "sweeping all the way round takes it all")
	w.ruins.assign(seam)
	w.build(_flat)
	_check(_standing_in(w, 0.0, 1.9, 1.0).is_empty() and _standing_in(w, total - 0.9, total, 1.0).is_empty(), "the loop stands broken either side of its seam")


func _after(w: WallLayout, lo: float, hi: float) -> Array[Vector2]:
	return WallLayout.ruins_after(w.ruins, w.length(), w.closed, lo, hi)


func _the_schema_checks_ruins() -> void:
	var good := {"points": PackedVector3Array([Terrain.ground(0, 0), Terrain.ground(6, 0)]), "height": 2.6, "arches": PackedFloat32Array(), "seed": 3, "closed": false, "top": 0, "fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array([Vector2(2, 3)]), "on": PackedInt32Array()}
	_check(Commands._wall(good) != null, "a wall with a ruin is a wall")
	var bad := {
		"backwards": PackedVector2Array([Vector2(3, 2)]),
		"not finite": PackedVector2Array([Vector2(NAN, 2)]),
		"too many": PackedVector2Array(range(Commands.MAX_RUINS + 1).map(func(i: int) -> Vector2: return Vector2(i * 0.1, i * 0.1 + 0.05))),
		"wrong type": [Vector2(2, 3)],
	}
	for what in bad:
		var d := good.duplicate()
		d.ruins = bad[what]
		_check(Commands._wall(d) == null, "a ruin refused: %s" % what)
	var fence := good.duplicate()
	fence.fence = true
	_check(Commands._wall(fence) == null, "a fence takes no ruin")
	var missing := good.duplicate()
	missing.erase("ruins")
	_check(Commands._wall(missing) == null, "a wall states its ruins")


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _the_eraser_sweeps_a_ruin_and_undo_mends_it() -> void:
	var world: World = main.world
	var walls: Array[Wall] = main.tool.walls
	await _play([{"op": "wall", "points": [[-10, -10], [10, -10]], "seconds": 0.5}])
	_check(walls.size() == 1, "a long wall stands")
	var w := walls[0]
	var stones := w.layout.stones.size()
	await _play([{"op": "erase", "points": [[-2, -10], [2, -10]], "seconds": 0.3}])
	var ruins: PackedVector2Array = world.state.walls[w.id].ruins
	_check(ruins.size() == 1 and ruins[0].y - ruins[0].x > 3.5 and ruins[0].y - ruins[0].x < 4.5, "a sweep along it breaks that stretch away: %s" % ruins)
	_check(Array(w.layout.ruins) == Array(ruins) and w.layout.stones.size() < stones, "the wall shows the ruin it holds")
	await _play([{"op": "erase", "points": [[7.5, -10], [5, -10]], "seconds": 0.3}])
	ruins = world.state.walls[w.id].ruins
	_check(ruins.size() == 2 and ruins[1].y - ruins[1].x > 2.0, "a second sweep, leftward, breaks all of its stretch: %s" % ruins)
	var steps: int = world.stacks[world.me()].undo.size()
	await _play([{"op": "delete", "x": 0, "z": -10}])
	_check(world.stacks[world.me()].undo.size() == steps and world.state.walls[w.id].ruins == ruins, "a tap inside a ruin changes nothing and takes no step")
	var arches: PackedFloat32Array = world.state.walls[w.id].arches
	main.tool.toggle_arch(w, w.layout.closest_s(Terrain.ground(6.2, -10)))
	await process_frame
	_check(world.state.walls[w.id].arches == arches and world.stacks[world.me()].undo.size() == steps, "no arch opens in a ruin")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(world.state.walls[w.id].ruins.size() == 1, "undo mends the last one")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(world.state.walls[w.id].ruins.is_empty() and w.layout.ruins.is_empty(), "and the next the first")
	await _play([{"op": "erase", "points": [[-6, -10], [-4, -10], [-8, -10]], "seconds": 0.4}])
	ruins = world.state.walls[w.id].ruins
	_check(ruins.size() == 1 and ruins[0].y - ruins[0].x > 3.5 and ruins[0].y - ruins[0].x < 4.5, "a sweep that turns back breaks everything it passed over: %s" % ruins)
	await _play([{"op": "press", "button": "dpad_down"}])
	# The turn must survive even when the entire gesture fits between two frames.
	for seconds in [0.4, 0.000001]:
		await _play([{"op": "erase", "points": [[-9.8, -10], [11, -10], [-11, -10]], "seconds": seconds}])
		_check(walls.is_empty(), "sweeping the whole wall takes it")
		await _play([{"op": "press", "button": "dpad_down"}])
		_check(walls.size() == 1, "undo stands it again")
	await _play([{"op": "house", "at": [0.0, 8.0], "size": [8.0, 5.0], "seconds": 0.3}])
	var house := walls[-1]
	await _play([{"op": "delete", "x": house.layout.samples[0].x, "z": house.layout.samples[0].z}])
	_check(walls.size() == 1, "the eraser takes a house whole")
