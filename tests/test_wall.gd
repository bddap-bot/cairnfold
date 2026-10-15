extends SceneTree

## Headless checks of the wall layout: godot4 --headless --path game --script ../tests/test_wall.gd

var failures := 0


func _init() -> void:
	_straight_wall_fills_its_length()
	_arch_leaves_its_opening_clear()
	_arch_ring_closes_over_the_opening()
	_short_or_low_walls_take_no_arch()
	_layout_is_deterministic()
	_a_copy_built_elsewhere_lays_the_same_stones()
	_raising_the_wall_adds_courses()
	_point_at_follows_the_curve()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _wall(length: float, height: float, arches: Array[float]) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.height = height
	w.arches = arches
	w.build(_flat)
	return w


func _blocks(w: WallLayout) -> Array:
	return w.stones.filter(func(s): return s.kind == "block")


func _straight_wall_fills_its_length() -> void:
	var w := _wall(6.0, 2.4, [])
	_check(absf(w.length() - 6.0) < 0.01, "length %f" % w.length())
	var courses := int(round(2.4 / WallLayout.COURSE))
	for k in courses:
		var covered := 0.0
		for s in _blocks(w):
			if absf(s.y - (k + 0.5) * 2.4 / courses) < 0.01:
				covered += s.size.x
		_check(absf(covered - 6.0) < 0.02, "course %d covers %f of 6 m" % [k, covered])
	_check(w.stones.any(func(s): return s.kind == "merlon"), "a crenellated top")
	_check(w.stones.filter(func(s): return s.kind == "pier").size() >= 4, "piers at both ends")


func _arch_leaves_its_opening_clear() -> void:
	var w := _wall(8.0, 2.7, [4.0])
	for s in w.stones:
		if s.kind == "voussoir" or s.kind == "keystone":
			continue
		var y: float = s.y
		var half := w.opening(y, false)
		var lo: float = s.s - s.size.x * 0.5
		var hi: float = s.s + s.size.x * 0.5
		if half > 0.0:
			_check(hi <= 4.0 - half + 0.01 or lo >= 4.0 + half - 0.01, "%s at s=%f y=%f intrudes into the arch" % [s.kind, s.s, y])


func _arch_ring_closes_over_the_opening() -> void:
	var w := _wall(8.0, 2.7, [4.0])
	var ring := w.stones.filter(func(s): return s.kind == "voussoir")
	_check(ring.size() == 11, "11 voussoirs, got %d" % ring.size())
	_check(w.stones.filter(func(s): return s.kind == "keystone").size() == 1, "one keystone")
	for s in ring:
		var r := Vector2(s.s - 4.0, s.y - w.spring()).length()
		_check(absf(r - (WallLayout.ARCH_HALF + WallLayout.RING * 0.5)) < 0.05, "voussoir off the ring: r=%f" % r)


func _short_or_low_walls_take_no_arch() -> void:
	_check(_wall(1.5, 2.7, [0.75]).stones.all(func(s): return s.kind != "voussoir"), "a 1.5 m wall has no room for an arch")
	_check(_wall(8.0, 1.2, [4.0]).stones.all(func(s): return s.kind != "voussoir"), "a 1.2 m wall is too low for an arch")


func _layout_is_deterministic() -> void:
	var a := _wall(7.0, 2.4, [3.5])
	var b := _wall(7.0, 2.4, [3.5])
	_check(a.stones.size() == b.stones.size() and a.stones.all(func(s): return true), "same stone count")
	for i in a.stones.size():
		if not a.stones[i].xform.is_equal_approx(b.stones[i].xform):
			_check(false, "stone %d differs between identical builds" % i)
			break


func _a_copy_built_elsewhere_lays_the_same_stones() -> void:
	var loop := WallLayout.new()
	loop.points = [Vector3(0, 0, 0), Vector3(4, 0, 2), Vector3(8, 0, 0), Vector3(5, 0, -3)]
	loop.closed = true
	loop.height = 3.3
	loop.top = WallLayout.Top.CAP
	loop.cover = WallLayout.Cover.ROOF
	loop.seed = 9
	loop.arches.assign([16.1])
	loop.windows.assign([Vector2(2.2, 1.4)])
	loop.lanterns.assign([Vector3(7.0, 1.8, 1.0)])
	var flagged := WallLayout.new()
	flagged.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	flagged.flags.assign([6.0])
	var fence := WallLayout.new()
	fence.points = [Vector3(0, 0, 0), Vector3(6, 0, 1)]
	fence.fence = true
	for a: WallLayout in [loop, flagged, fence]:
		a.build(_flat)
		var copy := a.inputs()
		copy.build(_flat)
		var b := WallLayout.new()
		b.adopt(copy)
		_check(b.stones.size() == a.stones.size() and b.live_arches == a.live_arches and b.samples == a.samples and b.openings.size() == a.openings.size() and b.flames == a.flames and b.cloths.size() == a.cloths.size(), "a copy's build matches: %d vs %d stones" % [b.stones.size(), a.stones.size()])
		for i in mini(a.stones.size(), b.stones.size()):
			if not a.stones[i].xform.is_equal_approx(b.stones[i].xform) or a.stones[i].kind != b.stones[i].kind:
				_check(false, "stone %d differs in the copy's build" % i)
				break
	_check(loop.live_arches.size() == 1 and not loop.openings.is_empty() and not loop.flames.is_empty(), "the loop opens its arch and window and hangs its lantern")
	_check(not flagged.cloths.is_empty(), "the flag flies")


func _raising_the_wall_adds_courses() -> void:
	var low := _wall(5.0, 1.8, [])
	var high := _wall(5.0, 3.6, [])
	var top := func(w: WallLayout) -> float:
		var m := 0.0
		for s in w.stones:
			m = maxf(m, s.y + s.size.y * 0.5)
		return m
	_check(top.call(high) > top.call(low) + 1.5, "raising 1.8 m adds height")
	_check(_blocks(high).size() > _blocks(low).size() * 1.6, "raising adds courses of stone")


func _point_at_follows_the_curve() -> void:
	var w := _wall(6.0, 2.4, [])
	_check(w.point_at(3.0).distance_to(Vector3(3, -0.12, 0)) < WallLayout.SAMPLE * 2.0, "point_at(3) is %s" % w.point_at(3.0))
	_check(w.point_at(99.0) == w.samples[-1], "point_at past the end is the end")
