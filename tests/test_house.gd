extends SceneTree

## Headless checks of towers, houses, roofs and wall tops: godot4 --headless --path game --script ../tests/test_house.gd

var failures := 0


func _init() -> void:
	_a_tower_is_a_level_ring_without_end_piers()
	_a_house_has_corner_piers_and_a_door()
	_the_footprint_follows_the_hands()
	_hands_carry_turn_and_stretch_a_house()
	_two_hands_resize_a_built_house_one_side_at_a_time()
	_a_resized_house_keeps_its_fittings_and_roof()
	_the_ridge_runs_the_longer_way()
	_gable_tiles_cover_the_footprint_under_the_ridge()
	_pitch_and_curvature_shape_the_slopes()
	_cone_tiles_ring_the_tower_up_to_the_finial()
	_pointing_at_a_roof_hits_it()
	_top_styles()
	_roofs_are_deterministic()
	_a_roof_laid_from_its_inputs_is_the_same_roof()
	_pushed_down_a_roof_goes_flat()
	_a_flat_roof_is_a_deck_inside_the_walls()
	_a_deck_is_rimmed_by_the_top_style()
	_roof_surfaces_have_no_degenerate_triangles()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _slope(x: float, z: float) -> float:
	return x * 0.1 + z * 0.05


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _blocks(w: WallLayout) -> Array:
	return w.stones.filter(func(s): return s.kind == "block")


func _tower(radius: float) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.circle(Vector3(1, 0, 1), radius)
	w.closed = true
	w.height = 4.5
	w.build(_slope)
	return w


func _a_tower_is_a_level_ring_without_end_piers() -> void:
	var w := _tower(2.0)
	_check(absf(w.length() - TAU * 2.0) < 0.1, "a 2 m tower's wall runs %f around" % w.length())
	_check(w.samples[0].distance_to(w.samples[-1]) < 0.01, "the ring closes")
	var foot := w.samples[0].y
	_check(w.samples.all(func(p): return absf(p.y - foot) < 1e-4), "the tower stands level")
	var lowest := INF
	for p in w.samples:
		lowest = minf(lowest, _slope(p.x, p.z))
	_check(absf(foot - (lowest - 0.12)) < 1e-4, "the tower's foot is on its lowest ground")
	_check(w.corners().is_empty(), "a round tower has no piers")
	_check(w.stones.all(func(s): return s.kind != "pier"), "no pier stones on a tower")
	for s in _blocks(w):
		var p: Vector3 = s.xform.origin
		var r := Vector2(p.x - 1, p.z - 1).length()
		if absf(r - 2.0) > WallLayout.THICKNESS:
			_check(false, "a stone %f m from the axis of a 2 m tower" % r)
			break
	var courses := int(round(4.5 / WallLayout.COURSE))
	var bottom := 0.0
	for s in _blocks(w):
		if absf(s.y - 4.5 / courses * 0.5) < 0.01:
			bottom += s.size.x
	_check(absf(bottom - w.length()) < 0.05, "the bottom course covers %f of %f" % [bottom, w.length()])


func _house(length: float, depth: float) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(length, 0, 0), depth)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	w.arches = [length * 0.5]
	w.build(_flat)
	return w


func _a_house_has_corner_piers_and_a_door() -> void:
	var w := _house(6.0, 4.0)
	_check(absf(w.length() - 20.0) < 0.05, "a 6×4 house's walls run %f" % w.length())
	var c := w.corners()
	_check(c.size() == 4, "four corners, got %d" % c.size())
	if c.size() == 4:
		_check(absf(c[1] - 6.0) < 0.01 and absf(c[2] - 10.0) < 0.01 and absf(c[3] - 16.0) < 0.01, "corners at %s" % [c])
	_check(w.live_arches == [3.0], "a door in the middle of the front wall, got %s" % [w.live_arches])
	w.arches = [6.2, 8.0]
	w.build(_flat)
	_check(w.live_arches == [8.0], "no arch through a corner pier, got %s" % [w.live_arches])
	var top := w.height + WallLayout.CAP
	_check(w.stones.all(func(s): return s.y + s.size.y * 0.5 <= top + 0.05), "nothing stands above the cap under a roof")
	_check(w.stones.all(func(s): return s.kind != "merlon"), "a roofed house has no merlons")


func _the_footprint_follows_the_hands() -> void:
	var corners := WallLayout.rectangle(Vector3(0, 0, 0), Vector3(0, 0, 5), 3.0)
	_check(corners[0].distance_to(corners[1]) > 4.99 and corners[0].distance_to(corners[3]) > 2.99, "5 by 3")
	var twisted := WallLayout.rectangle(Vector3(-2.5 * cos(0.5), 0, -2.5 * sin(0.5)), Vector3(2.5 * cos(0.5), 0, 2.5 * sin(0.5)), 3.0)
	var along := twisted[1] - twisted[0]
	_check(absf(atan2(along.z, along.x) - 0.5) < 1e-4, "twisting the hands turns the ridge")


func _hand(at: Vector3, turn := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, turn), at)


func _hands_carry_turn_and_stretch_a_house() -> void:
	var start := {"center": Vector3(10, 0, 0), "yaw": 0.0, "size": Vector2(4.5, 4.5), "round": false}
	var one: Array[Transform3D] = [_hand(Vector3(0, 1, 0))]
	var moved: Array[Transform3D] = [_hand(Vector3(0.5, 1.3, -0.2), 0.4)]
	var c := WallTool.carry(start, one, moved, 4.0)
	_check(c.center.is_equal_approx(Vector3(12, 0, -0.8)), "one hand carries it along the ground, scaled by the gain: %s" % c.center)
	_check(is_equal_approx(c.yaw, 0.4) and c.size == start.size, "and turns it with its own turn, keeping its size")
	var pair: Array[Transform3D] = [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1, 0))]
	var spread: Array[Transform3D] = [_hand(Vector3(-0.4, 1, 0)), _hand(Vector3(0.4, 1, 0))]
	c = WallTool.carry(start, pair, spread, 4.0)
	_check(c.center.is_equal_approx(start.center) and is_zero_approx(c.yaw), "spreading the hands in place neither moves nor turns it")
	_check(c.size.is_equal_approx(Vector2(9, 4.5)), "it stretches twice as long along the hands' line, not across: %s" % c.size)
	var circled: Array[Transform3D] = [_hand(Vector3(0, 1, 0.2)), _hand(Vector3(0, 1, -0.2))]
	c = WallTool.carry(start, pair, circled, 4.0)
	_check(is_equal_approx(c.yaw, PI * 0.5) and c.size.is_equal_approx(start.size), "moving the hands round a quarter circle turns it a quarter: %f" % c.yaw)
	var askew: Array[Transform3D] = [_hand(Vector3(-0.2, 1, 0.07)), _hand(Vector3(0.2, 1, -0.07))]
	var wide: Array[Transform3D] = [_hand(Vector3(-0.4, 1, 0.14)), _hand(Vector3(0.4, 1, -0.14))]
	c = WallTool.carry(start, askew, wide, 4.0)
	_check(is_equal_approx(c.size.x, 9.0) and c.size.y == start.size.y, "spread a little askew, only the nearer side stretches: %s" % c.size)
	var far: Array[Transform3D] = [_hand(Vector3(-5, 1, 0)), _hand(Vector3(5, 1, 0))]
	c = WallTool.carry(start, pair, far, 4.0)
	_check(c.size.x == WallTool.HOUSE_SIDES.y, "no longer than the longest house: %s" % c.size)
	var long := start.duplicate()
	long.size = Vector2(10, 4.5)
	c = WallTool.carry(long, circled, [_hand(Vector3(0, 1, 5)), _hand(Vector3(0, 1, -5))], 4.0)
	_check(c.size == Vector2(10, WallTool.HOUSE_DEPTH), "nor deeper under the ridge than the deepest, the length kept: %s" % c.size)
	var close: Array[Transform3D] = [_hand(Vector3(0, 1, 0)), _hand(Vector3(0.01, 1, 0))]
	c = WallTool.carry(start, pair, close, 4.0)
	_check(c.size.x == WallTool.HOUSE_SIDES.x, "nor shorter than the smallest: %s" % c.size)
	var tower := start.duplicate()
	tower.round = true
	c = WallTool.carry(tower, pair, spread, 4.0)
	_check(c.size.is_equal_approx(Vector2(7, 7)), "a round one spreads every way at once, no wider than the deepest house: %s" % c.size)
	c = WallTool.carry(tower, pair, circled, 4.0)
	_check(c.size.is_equal_approx(start.size), "and turning the pair keeps it as wide: %s" % c.size)
	var ring := WallTool.outline({"center": Vector3(1, 0, 1), "yaw": 0.3, "size": Vector2(5, 5), "round": true})
	_check(ring.all(func(p: Vector3) -> bool: return absf(Vector2(p.x - 1, p.z - 1).length() - 2.5) < 1e-4), "a round footprint is a circle as wide as its size")
	_check(WallTool.outline(start).size() == 4, "a square one has four corners")


## Directive (verbatim): "Eventually I'd like to be able to resize a house" / "in each dimension"
func _two_hands_resize_a_built_house_one_side_at_a_time() -> void:
	var start := {"center": Vector3(10, 0, 0), "yaw": 0.0, "size": Vector2(4.5, 4.5), "round": false}
	var front: Array[Transform3D] = [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1, 0))]
	var c := WallTool.resize(start, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.6, 1.1, 0))])
	_check(c.size.is_equal_approx(Vector2(9, 4.5)), "hands across its front stretch its width only: %s" % c.size)
	_check(c.center.is_equal_approx(Vector3(12.25, 0, 0)) and c.yaw == 0.0, "toward the moving hand, the still hand's wall staying: %s" % c.center)
	c = WallTool.resize(start, front, [_hand(Vector3(-0.4, 1, 0)), _hand(Vector3(0.4, 1, 0))])
	_check(c.center.is_equal_approx(start.center), "both hands spreading grow it about its middle: %s" % c.center)
	var flank: Array[Transform3D] = [_hand(Vector3(0.05, 1, -0.2)), _hand(Vector3(-0.05, 1, 0.2))]
	c = WallTool.resize(start, flank, [_hand(Vector3(0.05, 1, -0.2)), _hand(Vector3(-0.025, 1, 0.1))])
	_check(c.size.is_equal_approx(Vector2(4.5, 3.375)) and is_equal_approx(c.center.z, -0.5625), "hands along its flank, a little askew, close its depth only: %s at %s" % [c.size, c.center])
	c = WallTool.resize(start, flank, [_hand(Vector3(0, 1, -5)), _hand(Vector3(0, 1, 5))])
	_check(c.size == Vector2(4.5, WallTool.HOUSE_SIDES.y), "a narrow house's depth runs to the longest side: %s" % c.size)
	var turned := start.duplicate()
	turned.yaw = 0.6
	var along := Vector3.RIGHT.rotated(Vector3.UP, 0.6) * 0.2
	c = WallTool.resize(turned, [_hand(-along + Vector3.UP), _hand(along + Vector3.UP)], [_hand(-along + Vector3.UP), _hand(along * 3.0 + Vector3.UP)])
	_check(c.size.is_equal_approx(Vector2(9, 4.5)) and c.yaw == 0.6, "a house turned on the ground stretches along its own sides: %s" % c.size)
	var tower := start.duplicate()
	tower.round = true
	c = WallTool.resize(tower, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.4, 1, 0))])
	_check(c.size.is_equal_approx(Vector2(6.75, 6.75)) and c.center.is_equal_approx(Vector3(11.125, 0, 0)), "a round tower's diameter spreads, staying round: %s at %s" % [c.size, c.center])
	c = WallTool.resize(tower, front, [_hand(Vector3(-2, 1, 0)), _hand(Vector3(2, 1, 0))])
	_check(c.size == Vector2.ONE * WallTool.HOUSE_DEPTH, "no wider than the widest tower: %s" % c.size)
	c = WallTool.resize(tower, front, [_hand(Vector3(0, 1, 0)), _hand(Vector3(0.01, 1, 0))])
	_check(c.size == Vector2.ONE * WallTool.HOUSE_SIDES.x, "nor narrower than the narrowest: %s" % c.size)


func _a_resized_house_keeps_its_fittings_and_roof() -> void:
	var at := {"center": Vector3(0, 0, 0), "yaw": 0.0, "size": Vector2(6, 4), "round": false}
	var d := {"points": PackedVector3Array(WallTool.outline(at)), "closed": true, "arches": PackedFloat32Array([1.0]), "windows": PackedVector2Array([Vector2(3.0, 1.2), Vector2(8.0, 0.0)]),
		"lanterns": PackedVector3Array([Vector3(13.0, 2.0, -1.0)]), "flags": PackedFloat32Array([18.0]),
		"roof": {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array([Vector2(1.5, 0.8)]), "flag": false}}
	var from := WallTool.house_of(d)
	_check(from.center.is_equal_approx(at.center) and from.size.is_equal_approx(at.size) and WallTool.outline(from) == WallTool.outline(at), "a built house's footprint reads back from its corners: %s" % from)
	var wide := from.duplicate()
	wide.size = Vector2(12, 4)
	var r := WallTool.reshape_house(d, wide)
	_check(r.points.size() == 4 and is_equal_approx(r.points[0].distance_to(r.points[1]), 12.0), "the wall line takes the new width")
	_check(is_equal_approx(r.windows[0].x, 6.0) and is_equal_approx(r.windows[0].y, 1.2), "a window halfway along the front stays halfway along it, as high: %s" % r.windows[0])
	_check(is_equal_approx(r.windows[1].x, 14.0) and is_equal_approx(r.arches[0], 2.0), "a door on the end wall stays on it, an arch on the front in proportion: %s, %s" % [r.windows[1], r.arches])
	_check(is_equal_approx(r.lanterns[0].x, 22.0) and r.lanterns[0].z == -1.0 and is_equal_approx(r.flags[0], 30.0), "a lantern inside keeps its face; it and a flag keep their places: %s, %s" % [r.lanterns, r.flags])
	_check(is_equal_approx(r.roof.pitch, 1.6) and r.roof.chimneys[0].is_equal_approx(Vector2(3.0, 0.8)), "the roof keeps its slope over the same depth; a chimney moves out along the ridge: %s" % r.roof)
	var deep := from.duplicate()
	deep.size = Vector2(6, 8)
	r = WallTool.reshape_house(d, deep)
	var ridge: Vector3 = r.points[1] - r.points[0]
	_check(is_equal_approx(ridge.length(), 8.0) and absf(ridge.x) < 1e-4, "stretched deeper than long, its ridge turns the longer way")
	_check(is_equal_approx(r.roof.pitch, 2.4), "and the rise scales with the depth under the ridge: %f" % r.roof.pitch)
	_check(r.roof.chimneys[0].is_equal_approx(Vector2(1.6, -1.5)), "a chimney keeps its spot on the house as the ridge turns: %s" % r.roof.chimneys[0])
	_check(is_equal_approx(r.windows[0].x, 25.0), "the front window stays in the middle of the front as it moves out: %s" % r.windows[0])
	var tower := {"points": PackedVector3Array(WallLayout.circle(Vector3(2, 0, 2), 2.0)), "closed": true, "arches": PackedFloat32Array(), "windows": PackedVector2Array([Vector2(TAU * 0.5, 0.0)]),
		"lanterns": PackedVector3Array(), "flags": PackedFloat32Array([TAU]),
		"roof": {"kind": RoofLayout.Kind.CONE, "center": Vector3(2, 0, 2), "radius": 2.0, "pitch": 3.2, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "flag": true}}
	var wider := WallTool.house_of(tower)
	_check(wider.round and wider.size == Vector2(4, 4), "a tower reads back round, 4 m across")
	wider.size = Vector2(6, 6)
	r = WallTool.reshape_house(tower, wider)
	_check(is_equal_approx(r.roof.radius, 3.0) and is_equal_approx(r.roof.pitch, 4.8) and r.roof.center == Vector3(2, 0, 2), "its cone covers the wider wall at the same slope: %s" % r.roof)
	_check(absf(r.windows[0].x - TAU * 0.75) < 0.05 and absf(r.flags[0] - TAU * 1.5) < 0.05, "its door and flag keep their bearing: %s, %s" % [r.windows, r.flags])


func _the_ridge_runs_the_longer_way() -> void:
	var f := WallTool.footprint(Vector3(1, 0, 1), 0.0, Vector2(5, 5))
	_check(is_equal_approx(f.length, 5.0) and is_equal_approx(f.depth, 5.0), "a square footprint is a square house: %s" % f)
	f = WallTool.footprint(Vector3.ZERO, 0.0, Vector2(3, 8))
	_check(is_equal_approx(f.length, 8.0) and is_equal_approx(f.depth, 3.0) and absf(f.a.x - f.b.x) < 1e-4, "a footprint deeper than wide turns its ridge across: %s" % f)
	f = WallTool.footprint(Vector3.ZERO, PI * 0.5, Vector2(6, 3))
	_check(absf(f.a.x - f.b.x) < 1e-4 and absf(absf(f.a.z - f.b.z) - 6.0) < 1e-4, "turned a quarter, the ridge runs along z: %s" % f)


func _gable(length: float, depth: float, pitch: float, curve: float) -> RoofLayout:
	var r := RoofLayout.new()
	r.corners = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(length, 0, 0), depth)
	r.base = 2.54
	r.pitch = pitch
	r.curve = curve
	r.build()
	return r


func _of(r: RoofLayout, kind: String) -> Array:
	return r.tiles.filter(func(t): return t.kind == kind)


func _gable_tiles_cover_the_footprint_under_the_ridge() -> void:
	var r := _gable(6.0, 4.0, 1.8, 0.0)
	var tiles := _of(r, "tile")
	_check(tiles.size() > 200, "a 6×4 roof has %d tiles" % tiles.size())
	var reach := 2.0 + WallLayout.THICKNESS * 0.5 + RoofLayout.OVERHANG + 0.2
	var ends := 3.0 + WallLayout.THICKNESS * 0.5 + RoofLayout.GABLE_OVERHANG + 0.2
	for t in tiles:
		var p: Vector3 = t.xform.origin
		if absf(p.z) > reach or absf(p.x - 3.0) > ends or p.y > 2.54 + 1.8 + 0.1:
			_check(false, "a tile outside the roof at %s" % p)
			return
		var up: Vector3 = t.xform.basis.y.normalized()
		if up.y < 0.4 or up.z * p.z < 0.0:
			_check(false, "a tile at %s faces %s, not up and out" % [p, up])
			return
	for side in [-1.0, 1.0]:
		var near := tiles.filter(func(t): return t.xform.origin.z * side > 0.0 and absf(t.xform.origin.z) < 0.4)
		_check(not near.is_empty(), "the slope on side %d reaches the ridge" % side)
		var eave := tiles.filter(func(t): return t.xform.origin.z * side > 2.3)
		_check(not eave.is_empty(), "the slope on side %d overhangs the wall" % side)
	_check(_of(r, "ridge").size() >= 18, "ridge tiles along 6 m")
	_check(not r.gables().is_empty(), "gable ends close the roof")


func _height_at(r: RoofLayout, z: float) -> float:
	var best := INF
	var y := 0.0
	for t in _of(r, "tile"):
		var d := absf(absf(t.xform.origin.z) - z)
		if d < best:
			best = d
			y = t.xform.origin.y
	return y


func _pitch_and_curvature_shape_the_slopes() -> void:
	var low := _gable(6.0, 4.0, 1.0, 0.0)
	var high := _gable(6.0, 4.0, 3.0, 0.0)
	_check(_height_at(high, 0.2) > _height_at(low, 0.2) + 1.5, "pulling the ridge up raises it")
	var straight := _gable(6.0, 4.0, 2.0, 0.0)
	var bowed := _gable(6.0, 4.0, 2.0, 0.8)
	var swept := _gable(6.0, 4.0, 2.0, -0.8)
	_check(_height_at(bowed, 1.0) > _height_at(straight, 1.0) + 0.3, "positive curvature bows the slope out")
	_check(_height_at(swept, 1.0) < _height_at(straight, 1.0) - 0.3, "negative curvature sags it")
	_check(absf(_height_at(bowed, 0.1) - _height_at(straight, 0.1)) < 0.25, "curvature keeps the ridge height")
	for c in [-1.0, 1.0]:
		var r := _gable(6.0, 4.0, 2.0, c)
		var prof := r.profile(32)
		for i in prof.size() - 1:
			if prof[i + 1].y >= prof[i].y:
				_check(false, "curvature %f makes the slope climb outward" % c)
				break


func _cone_tiles_ring_the_tower_up_to_the_finial() -> void:
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE
	r.center = Vector3(1, 0, 1)
	r.radius = 2.0
	r.base = 4.6
	r.pitch = 3.2
	r.build()
	var tiles := _of(r, "tile")
	_check(tiles.size() > 150, "a 2 m cone has %d tiles" % tiles.size())
	var eave := 2.0 + WallLayout.THICKNESS * 0.5 + RoofLayout.OVERHANG
	for t in tiles:
		var p: Vector3 = t.xform.origin
		var rho := Vector2(p.x - 1, p.z - 1).length()
		if rho > eave + 0.05:
			_check(false, "a cone tile %f out" % rho)
			break
		var out := Vector3(p.x - 1, 0, p.z - 1).normalized()
		var up: Vector3 = t.xform.basis.y.normalized()
		if up.y < 0.3 or up.dot(out) < 0.0:
			_check(false, "a cone tile faces %s" % up)
			break
	_check(_of(r, "finial").size() == 1, "one finial")
	_check(r.gables().is_empty(), "a cone has no gables")


func _pointing_at_a_roof_hits_it() -> void:
	var r := _gable(6.0, 4.0, 1.8, 0.0)
	var t := r.ray_hit(Vector3(3, 10, 1), Vector3.DOWN)
	_check(t < 10.0 and t > 10.0 - 2.54 - 1.8, "a ray down onto the slope hits it at %f" % t)
	_check(r.ray_hit(Vector3(3, 10, 6), Vector3.DOWN) == INF, "a ray beside the house misses")


func _top_styles() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(6, 0, 0)]
	var count := func(kind: String) -> int: return w.stones.filter(func(s): return s.kind == kind).size()
	w.build(_flat)
	_check(count.call("merlon") > 0 and count.call("cap") > 0, "crenellated by default")
	w.top = WallLayout.Top.CAP
	w.build(_flat)
	_check(count.call("merlon") == 0 and count.call("cap") > 0, "a capped top has no merlons")
	w.top = WallLayout.Top.COPE
	w.build(_flat)
	_check(count.call("cope") > 20 and count.call("cap") == 0 and count.call("merlon") == 0, "coping stones on edge")
	var covered := 0.0
	for s in w.stones.filter(func(s): return s.kind == "cope"):
		covered += s.size.x
	_check(covered > 6.0 * 0.85, "coping runs the wall: %f of 6 m" % covered)


func _roofs_are_deterministic() -> void:
	var a := _gable(5.0, 3.5, 1.6, 0.3)
	var b := _gable(5.0, 3.5, 1.6, 0.3)
	_check(a.tiles.size() == b.tiles.size(), "same tile count")
	for i in a.tiles.size():
		if not a.tiles[i].xform.is_equal_approx(b.tiles[i].xform):
			_check(false, "tile %d differs" % i)
			break


func _a_roof_laid_from_its_inputs_is_the_same_roof() -> void:
	var w := _house(5.0, 3.5)
	var r := RoofLayout.new()
	r.seed = 9
	r.pitch = 1.6
	r.curve = 0.3
	r.chimneys = [Vector2(0.8, 0.6)]
	var copy := r.inputs()
	_check(copy.same_inputs(r), "a roof's inputs lay the same roof")
	var here := Wall.pack_roof(w, r, Wall.kinds())
	var there := Wall.pack_roof(w, copy, Wall.kinds())
	_check(not here.tiles.is_empty() and here.tiles == there.tiles and here.shadows == there.shadows, "with the same tiles")
	copy.pitch = 2.0
	_check(not copy.same_inputs(r), "a pulled pitch is another roof")


func _pushed_down_a_roof_goes_flat() -> void:
	_check(RoofLayout.snap_pitch(-2.0, 0.1) == 0.0, "pushing past the bottom lands flat")
	_check(RoofLayout.snap_pitch(RoofLayout.FLAT_SNAP - 0.05, 0.1) == 0.0, "just above flat snaps to flat")
	_check(is_equal_approx(RoofLayout.snap_pitch(RoofLayout.FLAT_SNAP + 0.03, 0.1), RoofLayout.FLAT_SNAP), "the lowest pitch above the snap stays pitched")
	_check(is_equal_approx(RoofLayout.snap_pitch(2.04, 0.1), 2.0), "pitches step by 0.1")


func _flat_cone() -> RoofLayout:
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE
	r.center = Vector3(1, 0, 1)
	r.radius = 2.0
	r.base = 4.6
	r.pitch = 0.0
	r.build()
	return r


func _a_flat_roof_is_a_deck_inside_the_walls() -> void:
	var r := _gable(6.0, 4.0, 0.0, 0.6)
	var deck := _of(r, "deck")
	_check(not deck.is_empty() and deck.size() == r.tiles.size(), "a flat gable is all deck: %d of %d" % [deck.size(), r.tiles.size()])
	_check(r.gables().is_empty(), "a flat roof has no gable ends")
	var inner := Vector2(3.0 - WallLayout.THICKNESS * 0.5, 2.0 - WallLayout.THICKNESS * 0.5)
	var area := 0.0
	for t in deck:
		var x: Transform3D = t.xform
		var top := x.origin.y + x.basis.y.length() * 0.5
		if absf(x.origin.x - 3.0) > inner.x + RoofLayout.DECK_TUCK or absf(x.origin.z) > inner.y + RoofLayout.DECK_TUCK or top > r.base + 0.01 or top < r.base - 0.1:
			_check(false, "a deck slab out of place at %s" % x.origin)
			return
		area += x.basis.x.length() * x.basis.z.length()
	_check(area > inner.x * inner.y * 4.0 * 0.85, "the deck covers the floor: %.1f m² of %.1f" % [area, inner.x * inner.y * 4.0])
	var t := r.ray_hit(Vector3(3, 10, 1), Vector3.DOWN)
	_check(absf(t - (10.0 - r.base)) < 0.01, "pointing down at the deck hits it at the cap's height: %f" % t)
	_check(r.ray_hit(Vector3(3, 10, 3.0), Vector3.DOWN) == INF, "a flat roof has no eave beyond the walls")
	var open := 0
	for i in 60:
		for j in 40:
			var p := Vector2(3.0 + (i / 59.0 - 0.5) * 2.0 * inner.x, (j / 39.0 - 0.5) * 2.0 * inner.y)
			if not r.mortar.any(func(m): return _covers(m.xform, p)):
				open += 1
	_check(open == 0 and r.mortar.all(func(m): return m.xform.origin.y + m.xform.basis.y.length() * 0.5 < r.base - RoofLayout.DECK_DROP), "a mortar bed under the flags leaves no joint open to the floor: %d of 2400 points open" % open)
	_check(_gable(6.0, 4.0, 2.0, 0.0).mortar.is_empty(), "a pitched roof lays no bed")
	var round := _flat_cone()
	var ring_open := 0
	for i in 24:
		for j in 12:
			var a := TAU * i / 24.0
			var rho := (2.0 - WallLayout.THICKNESS * 0.5) * j / 12.0
			if not round.mortar.any(func(m): return _covers(m.xform, Vector2(1 + cos(a) * rho, 1 + sin(a) * rho))):
				ring_open += 1
	_check(ring_open == 0, "a tower's deck bed leaves no joint open: %d of 288 points open" % ring_open)
	r.chimneys.assign([Vector2(1.0, 1.0)])
	r.build()
	_check(not _of(r, "chimney").is_empty(), "a chimney still stands on a flat roof")
	var cone := _flat_cone()
	var ring := _of(cone, "deck")
	_check(ring.size() > 10 and ring.size() == cone.tiles.size(), "a flat tower roof is all deck, no finial: %d" % ring.size())
	var reach := 2.0 - WallLayout.THICKNESS * 0.5 + RoofLayout.DECK_TUCK
	_check(ring.all(func(s): return Vector2(s.xform.origin.x - 1, s.xform.origin.z - 1).length() < reach), "the tower's deck stays inside its wall")
	cone.flag = true
	cone.build()
	_check(cone.cloths.size() == 1 and cone.cloths[0].xform.origin.y > cone.base + 1.0, "a flag flies from a flat tower")


func _a_deck_is_rimmed_by_the_top_style() -> void:
	var w := _house(6.0, 4.0)
	w.cover = WallLayout.Cover.DECK
	w.build(_flat)
	var top := w.height + WallLayout.CAP
	var rim := w.stones.filter(func(s): return s.y > top)
	_check(rim.any(func(s): return s.kind == "cap" and s.y > top + WallLayout.PARAPET), "a cap top on a deck rises into a coped parapet")
	_check(rim.any(func(s): return s.kind == "mortar"), "the parapet's joints are mortared")
	_check(rim.filter(func(s): return s.kind == "block").reduce(func(m, s): return m + s.size.x, 0.0) > w.length() - 0.1, "the parapet runs all the way round")
	var piers := w.stones.filter(func(s): return s.kind == "pier")
	_check(piers.reduce(func(m, s): return maxf(m, s.y), 0.0) > top + WallLayout.PARAPET, "corner piers rise past the parapet")
	w.top = WallLayout.Top.CRENEL
	w.build(_flat)
	_check(w.stones.any(func(s): return s.kind == "merlon") and not w.stones.any(func(s): return s.kind == "block" and s.y > top), "a crenellated top rims a deck with merlons, no parapet")
	w.cover = WallLayout.Cover.ROOF
	w.build(_flat)
	_check(not w.stones.any(func(s): return s.kind == "merlon"), "under a pitched roof the merlons go")


func _degenerate(tris: PackedVector3Array) -> int:
	var bad := 0
	for i in range(0, tris.size(), 3):
		if (tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i]).length() < 1e-6:
			bad += 1
	return bad


func _roof_surfaces_have_no_degenerate_triangles() -> void:
	var cone := _flat_cone()
	var roofs: Array[RoofLayout] = [_gable(6.0, 4.0, 0.0, 0.0), _gable(6.0, 4.0, 0.0, -1.0), _gable(6.0, 4.0, 2.0, 0.4), cone]
	var pitched := _flat_cone()
	pitched.pitch = 3.0
	pitched.build()
	roofs.append(pitched)
	for r in roofs:
		_check(not r.faces.is_empty() and _degenerate(r.faces) == 0, "pitch %.1f %s: %d of %d surface triangles degenerate" % [r.pitch, RoofLayout.Kind.keys()[r.kind], _degenerate(r.faces), r.faces.size() / 3])
		_check(_degenerate(r.gable_faces) == 0, "pitch %.1f: gable ends have no degenerate triangles" % r.pitch)
		_check(r.tiles.all(func(t): return absf(t.xform.basis.determinant()) > 1e-6), "pitch %.1f: no flattened tiles" % r.pitch)


func _covers(x: Transform3D, p: Vector2) -> bool:
	var local := x.affine_inverse() * Vector3(p.x, x.origin.y, p.y)
	return absf(local.x) <= 0.5 and absf(local.z) <= 0.5
