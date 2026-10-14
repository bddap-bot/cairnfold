extends SceneTree

## Headless checks of towers, houses, roofs and wall tops: godot4 --headless --path game --script ../tests/test_house.gd

var failures := 0


func _init() -> void:
	_a_closed_loop_snaps_and_an_open_stroke_does_not()
	_a_tower_is_a_level_ring_without_end_piers()
	_a_house_has_corner_piers_and_a_door()
	_the_footprint_follows_the_hands()
	_gable_tiles_cover_the_footprint_under_the_ridge()
	_pitch_and_curvature_shape_the_slopes()
	_cone_tiles_ring_the_tower_up_to_the_finial()
	_pointing_at_a_roof_hits_it()
	_top_styles()
	_roofs_are_deterministic()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _slope(x: float, z: float) -> float:
	return x * 0.1 + z * 0.05


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _stroke(center: Vector3, radius: float, turns: float) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := int(24 * turns)
	for i in n + 1:
		var a := TAU * turns * i / n
		out.append(center + Vector3(cos(a), 0, sin(a)) * radius * (1.0 + 0.08 * sin(a * 3.0)))
	return out


func _blocks(w: WallLayout) -> Array:
	return w.stones.filter(func(s): return s.kind == "block")


func _a_closed_loop_snaps_and_an_open_stroke_does_not() -> void:
	var loop := WallLayout.fit_loop(_stroke(Vector3(3, 0, -2), 2.5, 1.0))
	_check(not loop.is_empty(), "a closed loop is a tower")
	if not loop.is_empty():
		_check(loop.center.distance_to(Vector3(3, 0, -2)) < 0.3, "tower centre %s" % loop.center)
		_check(absf(loop.radius - 2.5) < 0.3, "tower radius %f" % loop.radius)
	_check(WallLayout.fit_loop(_stroke(Vector3.ZERO, 2.5, 0.7)).is_empty(), "three quarters of a loop is still a wall")
	var line: Array[Vector3] = []
	for i in 12:
		line.append(Vector3(i * 0.5, 0, 0))
	_check(WallLayout.fit_loop(line).is_empty(), "a straight stroke is a wall")
	_check(absf(WallLayout.fit_loop(_stroke(Vector3.ZERO, 4.6, 1.0)).radius - WallLayout.TOWER_RADIUS.y) < 0.01, "a loop a little wider than the largest tower is clamped to it")
	_check(WallLayout.fit_loop(_stroke(Vector3.ZERO, 9.0, 1.0)).is_empty(), "closing a courtyard keeps it a wall")
	var there_and_back: Array[Vector3] = []
	for i in 13:
		there_and_back.append(Vector3(3.0 - absf(i - 6) * 0.5, 0, 0.3 * signf(i - 6)))
	_check(WallLayout.fit_loop(there_and_back).is_empty(), "out and back along itself is a wall")


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
	w.roofed = true
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
