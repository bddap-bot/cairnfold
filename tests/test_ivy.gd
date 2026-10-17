extends SceneTree

## Headless checks of ivy growth: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_ivy.gd

var failures := 0


func _init() -> void:
	_ivy_climbs_both_faces()
	_ivy_stays_on_the_wall()
	_ivy_keeps_out_of_arches()
	_ivy_grows_over_time()
	_ivy_is_deterministic()
	_short_walls_take_no_ivy()
	_tall_walls_stay_bounded()
	_raising_a_wall_keeps_its_ivy()
	_bake_packs_each_leaf()
	_a_house_grows_ivy_outside_only()
	_a_tower_keeps_ivy_on_both_faces()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _wall(length: float, height: float, arches: Array[float], seed := 1) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.height = height
	w.arches = arches
	w.seed = seed
	w.build(_flat)
	return w


func _ivy_climbs_both_faces() -> void:
	var leaves := IvyLayout.grow(_wall(12.0, 2.7, []))
	_check(leaves.size() > 100, "a 12 m wall grows a good spread of ivy, got %d leaves" % leaves.size())
	_check(leaves.any(func(l): return l.side < 0.0) and leaves.any(func(l): return l.side > 0.0), "ivy on both faces")
	_check(leaves.any(func(l): return l.y > 1.5), "ivy climbs well up the wall")


func _ivy_stays_on_the_wall() -> void:
	var w := _wall(10.0, 2.4, [])
	for l in IvyLayout.grow(w):
		var p: Vector3 = l.xform.origin
		if p.x < IvyLayout.END - 0.01 or p.x > w.length() - IvyLayout.END + 0.01 or l.y < 0.0 or l.y > w.height:
			_check(false, "leaf at s %.2f y %.2f is off the wall face" % [l.s, l.y])
			return
		var off := absf(p.z)
		if off < WallLayout.THICKNESS * 0.5 or off > WallLayout.THICKNESS * 0.5 + 0.12:
			_check(false, "leaf %.2f m from the wall's centre line, not on its face" % off)
			return


func _ivy_keeps_out_of_arches() -> void:
	var w := _wall(10.0, 3.3, [5.0])
	_check(w.live_arches == [5.0], "the test wall has its arch")
	var leaves := IvyLayout.grow(w)
	var near := 0
	for l in leaves:
		var open := w.opening(l.y, true)
		if open > 0.0 and absf(l.s - 5.0) < open:
			_check(false, "leaf at s %.2f y %.2f sits in the arch" % [l.s, l.y])
			return
		if absf(l.s - 5.0) < WallLayout.ARCH_HALF + WallLayout.RING + 0.5:
			near += 1
	_check(near > 0, "ivy grows up beside the arch")


func _ivy_grows_over_time() -> void:
	var leaves := IvyLayout.grow(_wall(10.0, 2.7, []))
	var sorted := true
	for i in range(1, leaves.size()):
		sorted = sorted and leaves[i].t >= leaves[i - 1].t
	_check(sorted, "leaves come in growth order")
	_check(leaves[0].t < 4.0, "the first leaves show within seconds")
	_check(leaves[-1].t > 10.0 and leaves[-1].t < 60.0, "growth takes a while but finishes, last leaf at %.1f s" % leaves[-1].t)
	_check(leaves[0].y < 0.4, "growth starts at the foot")


func _ivy_is_deterministic() -> void:
	var a := IvyLayout.grow(_wall(9.0, 2.4, [], 4))
	var b := IvyLayout.grow(_wall(9.0, 2.4, [], 4))
	var c := IvyLayout.grow(_wall(9.0, 2.4, [], 5))
	_check(a.size() == b.size() and a[7].xform == b[7].xform, "the same wall grows the same ivy")
	_check(a.size() != c.size() or a[7].xform != c[7].xform, "another wall grows its own ivy")


func _short_walls_take_no_ivy() -> void:
	_check(IvyLayout.grow(_wall(1.2, 2.4, [])).is_empty(), "a stub between two piers takes no ivy")


func _tall_walls_stay_bounded() -> void:
	var low := IvyLayout.grow(_wall(15.0, 2.7, [])).size()
	var tall := IvyLayout.grow(_wall(15.0, 9.0, [])).size()
	_check(tall < low * 2.5, "ivy on a 9 m wall stays within a small multiple of a 2.7 m one, %d against %d leaves" % [tall, low])


func _raising_a_wall_keeps_its_ivy() -> void:
	var before := {}
	for l in IvyLayout.grow(_wall(10.0, 2.7, [], 3)):
		if l.y < 1.0:
			before[l.xform.origin] = true
	var kept := 0
	for l in IvyLayout.grow(_wall(10.0, 3.3, [], 3)):
		if before.has(l.xform.origin):
			kept += 1
	_check(kept == before.size(), "raising a wall leaves the ivy below where it was, %d of %d leaves" % [kept, before.size()])


func _bake_packs_each_leaf() -> void:
	var w := _wall(8.0, 2.4, [])
	var leaves := IvyLayout.grow(w)
	var baked := IvyLayout.bake(w.snapshot())
	_check(baked.buffer.size() == leaves.size() * 16 and baked.times.size() == leaves.size(), "a transform and a colour per leaf")
	var i := leaves.size() / 2
	var b: PackedFloat32Array = baked.buffer
	var x: Transform3D = leaves[i].xform
	_check(is_equal_approx(b[i * 16 + 3], x.origin.x) and is_equal_approx(b[i * 16 + 1], x.basis.y.x) and is_equal_approx(b[i * 16 + 14], leaves[i].color.b), "rows laid out as the MultiMesh reads them")
	_check(baked.bounds.has_point(x.origin), "the bounds hold the leaves")


func _loop(cover: WallLayout.Cover, reverse: bool) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(8, 0, 0), 6.0)
	if reverse:
		w.points.reverse()
	w.closed = true
	w.cover = cover
	w.height = 2.7
	w.seed = 6
	w.build(_flat)
	return w


func _inside(w: WallLayout, p: Vector3) -> bool:
	var poly := PackedVector2Array()
	for q in w.samples:
		poly.append(Vector2(q.x, q.z))
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly)


func _a_house_grows_ivy_outside_only() -> void:
	for reverse in [false, true]:
		for cover in [WallLayout.Cover.ROOF, WallLayout.Cover.DECK]:
			var w := _loop(cover, reverse)
			var leaves := IvyLayout.grow(w.snapshot())
			_check(leaves.size() > 100, "a house grows ivy outside, got %d leaves" % leaves.size())
			_check(not leaves.any(func(l): return _inside(w, l.xform.origin)), "no ivy on a roofed house's inner faces (reversed %s)" % reverse)
	var open := IvyLayout.grow(_loop(WallLayout.Cover.OPEN, false)).filter(func(l): return not _inside(_loop(WallLayout.Cover.OPEN, false), l.xform.origin))
	var roofed := IvyLayout.grow(_loop(WallLayout.Cover.ROOF, false))
	_check(roofed.size() == open.size() and roofed.all(func(l): return open.any(func(o): return o.xform == l.xform)), "roofing a loop leaves its outer ivy where it was")


func _a_tower_keeps_ivy_on_both_faces() -> void:
	var w := _loop(WallLayout.Cover.OPEN, false)
	var leaves := IvyLayout.grow(w)
	_check(leaves.any(func(l): return _inside(w, l.xform.origin)) and leaves.any(func(l): return not _inside(w, l.xform.origin)), "an open loop keeps ivy inside and out")
