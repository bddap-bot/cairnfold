extends "res://../tests/support/suite.gd"

## Headless checks of ivy growth: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_ivy.gd


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
	_every_lobe_faces_its_normal()
	_a_house_grows_ivy_outside_only()
	_a_tower_keeps_ivy_on_both_faces()
	_a_raised_house_roots_its_ivy_at_its_plinths_foot()
	finish()


func _slope(x: float, z: float) -> float:
	return x * 0.1 + z * 0.05


func _ivy_climbs_both_faces() -> void:
	var leaves := IvyLayout.grow(straight_wall(12.0, 2.7, []))
	check(leaves.size() > 100, "a 12 m wall grows a good spread of ivy, got %d leaves" % leaves.size())
	check(leaves.any(func(l): return l.side < 0.0) and leaves.any(func(l): return l.side > 0.0), "ivy on both faces")
	check(leaves.any(func(l): return l.y > 1.5), "ivy climbs well up the wall")


func _ivy_stays_on_the_wall() -> void:
	var w := straight_wall(10.0, 2.4, [])
	for l in IvyLayout.grow(w):
		var p: Vector3 = l.xform.origin
		if p.x < IvyLayout.END - 0.01 or p.x > w.length() - IvyLayout.END + 0.01 or l.y < 0.0 or l.y > w.height:
			check(false, "leaf at s %.2f y %.2f is off the wall face" % [l.s, l.y])
			return
		var off := absf(p.z)
		if off < WallLayout.THICKNESS * 0.5 or off > WallLayout.THICKNESS * 0.5 + 0.12:
			check(false, "leaf %.2f m from the wall's centre line, not on its face" % off)
			return


func _ivy_keeps_out_of_arches() -> void:
	var w := straight_wall(10.0, 3.3, [5.0])
	check(w.archways() == [5.0], "the test wall has its arch")
	var leaves := IvyLayout.grow(w)
	var near := 0
	for l in leaves:
		var open := w.opening(l.y, true)
		if open > 0.0 and absf(l.s - 5.0) < open:
			check(false, "leaf at s %.2f y %.2f sits in the arch" % [l.s, l.y])
			return
		if absf(l.s - 5.0) < WallLayout.ARCH_HALF + WallLayout.RING + 0.5:
			near += 1
	check(near > 0, "ivy grows up beside the arch")


func _ivy_grows_over_time() -> void:
	var leaves := IvyLayout.grow(straight_wall(10.0, 2.7, []))
	var sorted := true
	for i in range(1, leaves.size()):
		sorted = sorted and leaves[i].t >= leaves[i - 1].t
	check(sorted, "leaves come in growth order")
	check(leaves[0].t < 4.0, "the first leaves show within seconds")
	check(leaves[-1].t > 10.0 and leaves[-1].t < 60.0, "growth takes a while but finishes, last leaf at %.1f s" % leaves[-1].t)
	check(leaves[0].y < 0.4, "growth starts at the foot")


func _ivy_is_deterministic() -> void:
	var a := IvyLayout.grow(straight_wall(9.0, 2.4, [], 4))
	var b := IvyLayout.grow(straight_wall(9.0, 2.4, [], 4))
	var c := IvyLayout.grow(straight_wall(9.0, 2.4, [], 5))
	check(a.size() == b.size() and a[7].xform == b[7].xform, "the same wall grows the same ivy")
	check(a.size() != c.size() or a[7].xform != c[7].xform, "another wall grows its own ivy")


func _short_walls_take_no_ivy() -> void:
	check(IvyLayout.grow(straight_wall(1.2, 2.4, [])).is_empty(), "a stub between two piers takes no ivy")


func _tall_walls_stay_bounded() -> void:
	var low := IvyLayout.grow(straight_wall(15.0, 2.7, [])).size()
	var tall := IvyLayout.grow(straight_wall(15.0, 9.0, [])).size()
	check(tall < low * 2.5, "ivy on a 9 m wall stays within a small multiple of a 2.7 m one, %d against %d leaves" % [tall, low])


func _raising_a_wall_keeps_its_ivy() -> void:
	var before := {}
	for l in IvyLayout.grow(straight_wall(10.0, 2.7, [], 3)):
		if l.y < 1.0:
			before[l.xform.origin] = true
	var kept := 0
	for l in IvyLayout.grow(straight_wall(10.0, 3.3, [], 3)):
		if before.has(l.xform.origin):
			kept += 1
	check(kept == before.size(), "raising a wall leaves the ivy below where it was, %d of %d leaves" % [kept, before.size()])


func _bake_packs_each_leaf() -> void:
	var w := straight_wall(8.0, 2.4, [])
	var leaves := IvyLayout.grow(w)
	var baked := IvyLayout.bake(w.snapshot())
	check(baked.buffer.size() == leaves.size() * 16 and baked.times.size() == leaves.size(), "a transform and a colour per leaf")
	var i := leaves.size() / 2
	var b: PackedFloat32Array = baked.buffer
	var x: Transform3D = leaves[i].xform
	check(is_equal_approx(b[i * 16 + 3], x.origin.x) and is_equal_approx(b[i * 16 + 1], x.basis.y.x) and is_equal_approx(b[i * 16 + 14], leaves[i].color.b) and is_equal_approx(b[i * 16 + 15], w.ground_at(leaves[i].s)), "rows laid out as the MultiMesh reads them, the alpha the ground under the wall")
	check(baked.bounds.has_point(x.origin), "the bounds hold the leaves")


func _every_lobe_faces_its_normal() -> void:
	var a := Meshes.sprig().surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var against := 0
	for t in range(0, idx.size(), 3):
		var front := (v[idx[t + 2]] - v[idx[t]]).cross(v[idx[t + 1]] - v[idx[t]])
		for k in 3:
			if front.dot(n[idx[t + k]]) <= 0.0:
				against += 1
	check(idx.size() == 18 and against == 0, "every lobe winds as its normal faces, so none is drawn as its back face")


func _loop(cover: WallLayout.Cover, reverse: bool) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(8, 0, 0), 6.0)
	if reverse:
		w.points.reverse()
	w.closed = true
	w.cover = cover
	w.height = 2.7
	w.seed = 6
	w.build(Terrain.flat)
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
			check(leaves.size() > 100, "a house grows ivy outside, got %d leaves" % leaves.size())
			check(not leaves.any(func(l): return _inside(w, l.xform.origin)), "no ivy on a roofed house's inner faces (reversed %s)" % reverse)
	var open := IvyLayout.grow(_loop(WallLayout.Cover.OPEN, false)).filter(func(l): return not _inside(_loop(WallLayout.Cover.OPEN, false), l.xform.origin))
	var roofed := IvyLayout.grow(_loop(WallLayout.Cover.ROOF, false))
	check(roofed.size() == open.size() and roofed.all(func(l): return open.any(func(o): return o.xform == l.xform)), "roofing a loop leaves its outer ivy where it was")


func _a_tower_keeps_ivy_on_both_faces() -> void:
	var w := _loop(WallLayout.Cover.OPEN, false)
	var leaves := IvyLayout.grow(w)
	check(leaves.any(func(l): return _inside(w, l.xform.origin)) and leaves.any(func(l): return not _inside(w, l.xform.origin)), "an open loop keeps ivy inside and out")


## A house raised as it is placed grows its ivy from its base, not high up the building.
func _a_raised_house_roots_its_ivy_at_its_plinths_foot() -> void:
	var house := func(rise: float) -> WallLayout:
		var w := WallLayout.new()
		w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
		w.closed = true
		w.cover = WallLayout.Cover.ROOF
		w.height = 2.7
		w.seed = 6
		w.rise = rise
		w.build(_slope)
		return w
	for rise in [0.0, 1.2, 3.0]:
		var w: WallLayout = house.call(rise)
		var shape := w.snapshot()
		var leaves := IvyLayout.grow(shape)
		var baked := IvyLayout.bake(shape)
		var lowest := INF
		var light_off := 0.0
		for i in leaves.size():
			var p: Vector3 = leaves[i].xform.origin
			lowest = minf(lowest, p.y - _slope(p.x, p.z))
			var under: Vector3 = w.frame_at(leaves[i].s).point
			light_off = maxf(light_off, absf(baked.buffer[i * 16 + 15] - _slope(under.x, under.z)))
		check(leaves.size() > 100, "a house raised %.1f m grows ivy, got %d leaves" % [rise, leaves.size()])
		check(lowest < 0.15, "a house raised %.1f m roots its ivy where its plinth meets the ground: lowest leaf %.2f m above it" % [rise, lowest])
		check(light_off < 1e-3, "and its sprigs read the light over the ground under the wall: %.3f m off" % light_off)
	var tower: WallLayout = house.call(0.0)
	var on: WallLayout = house.call(1.2)
	on.supports = [Massing.of(tower, null)]
	on.build(_slope)
	var top := INF
	for l in IvyLayout.grow(on.snapshot()):
		top = minf(top, l.y)
	check(top > 0.0 and top < 0.15, "a house standing on a build roots its ivy at its foot on the build's top: %.2f" % top)
