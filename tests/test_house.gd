extends SceneTree

## Headless checks of towers, houses, roofs and wall tops: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_house.gd

var failures := 0


func _init() -> void:
	_a_tower_is_a_level_ring_without_end_piers()
	_a_house_has_corner_piers_and_a_door()
	_the_footprint_follows_the_hands()
	_one_hand_carries_and_turns_a_house()
	_two_hands_resize_a_built_house_one_side_at_a_time()
	_two_hands_drawn_apart_upright_raise_its_walls()
	_a_wall_is_carried_and_sized_as_a_house_is()
	_a_raised_house_stands_on_a_plinth()
	_a_resized_house_keeps_its_fittings_and_roof()
	_the_ridge_keeps_its_axis()
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
	_no_wall_rises_through_a_steep_roof()
	_gable_ends_keep_to_their_wall_under_the_roof()
	_every_tile_joint_has_a_tile_under_it()
	_a_gable_continues_the_wall_under_the_slopes()
	_gable_faces_face_out_of_the_wall()
	_the_budget_counts_gable_ends()
	_every_gable_end_stays_on_its_footprint()
	_every_gable_end_closes_its_wall()
	_crow_steps_stand_over_the_roof()
	_the_budget_counts_each_gable_end_as_laid()
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
	w.openings.assign([length * 0.5].map(WallLayout.archway))
	w.build(_flat)
	return w


func _a_house_has_corner_piers_and_a_door() -> void:
	var w := _house(6.0, 4.0)
	_check(absf(w.length() - 20.0) < 0.05, "a 6×4 house's walls run %f" % w.length())
	var c := w.corners()
	_check(c.size() == 4, "four corners, got %d" % c.size())
	if c.size() == 4:
		_check(absf(c[1] - 6.0) < 0.01 and absf(c[2] - 10.0) < 0.01 and absf(c[3] - 16.0) < 0.01, "corners at %s" % [c])
	_check(w.archways() == [3.0], "a door in the middle of the front wall, got %s" % [w.archways()])
	w.openings.assign([6.2, 8.0].map(WallLayout.archway))
	w.build(_flat)
	_check(w.archways() == [8.0], "no arch through a corner pier, got %s" % [w.archways()])
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


## Report (relay): placing a house with the trigger only places it; moving it is the grip's job.
func _one_hand_carries_and_turns_a_house() -> void:
	var start := {"center": Vector3(10, 0, 0), "yaw": 0.0, "size": Vector2(4.5, 4.5), "round": false, "rise": 0.0, "height": 2.4, "pitch": 1.9, "curve": 0.0, "overhang": 0.3, "grounded": true}
	var c := WallTool.carry(start, _hand(Vector3(0, 1, 0)), _hand(Vector3(0.5, 1.3, -0.2), 0.4), 4.0)
	_check(c.center.is_equal_approx(Vector3(12, 0, -0.8)), "one hand carries it along the ground, scaled by the gain: %s" % c.center)
	_check(is_equal_approx(c.yaw, 0.4) and c.size == start.size and c.height == start.height, "and turns it with its own turn, keeping its size and height")
	# Directive (verbatim): "When placing a building, you should be able to raise it higher up by raising your controller up"
	_check(is_equal_approx(c.rise, 1.2), "and raises it onto its plinth as the hand rises, scaled by the gain: %.2f" % c.rise)
	c = WallTool.carry(start, _hand(Vector3(0, 1, 0)), _hand(Vector3(0, 0.2, 0)), 4.0)
	_check(c.rise == 0.0, "lowered, it stays on its ground: %.2f" % c.rise)
	c = WallTool.carry(start, _hand(Vector3(0, 1, 0)), _hand(Vector3(0, 1000, 0)), 1.0)
	_check(c.rise > 900.0, "nothing caps the rise; the budget is what stops it: %.2f" % c.rise)
	var raised := start.duplicate()
	raised.rise = 0.9
	c = WallTool.carry(raised, _hand(Vector3(0, 1, 0)), _hand(Vector3(0, 0.7, 0)), 1.0)
	_check(is_equal_approx(c.rise, 0.6), "lowering the hand sets it back down: %.2f" % c.rise)
	var on_build := start.duplicate()
	on_build.grounded = false
	c = WallTool.carry(on_build, _hand(Vector3(0, 1, 0)), _hand(Vector3(0.5, 1.3, -0.2), 0.4), 4.0)
	_check(c.rise == 0.0, "one carried on a build stays on its top")
	var ring := WallTool.outline({"center": Vector3(1, 0, 1), "yaw": 0.3, "size": Vector2(5, 5), "round": true})
	_check(ring.all(func(p: Vector3) -> bool: return absf(Vector2(p.x - 1, p.z - 1).length() - 2.5) < 1e-4), "a round footprint is a circle as wide as its size")
	_check(WallTool.outline(start).size() == 4, "a square one has four corners")


## Directive (verbatim): "Eventually I'd like to be able to resize a house" / "in each dimension"
func _two_hands_resize_a_built_house_one_side_at_a_time() -> void:
	var start := {"center": Vector3(10, 0, 0), "yaw": 0.0, "size": Vector2(4.5, 4.5), "round": false, "rise": 0.0, "height": 2.4, "pitch": 1.9, "curve": 0.0, "overhang": 0.3}
	var front: Array[Transform3D] = [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1, 0))]
	var c := WallTool.resize(start, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.6, 1.1, 0))])
	_check(c.size.is_equal_approx(Vector2(9, 4.5)), "hands across its front stretch its width only: %s" % c.size)
	_check(c.center.is_equal_approx(Vector3(12.25, 0, 0)) and c.yaw == 0.0, "toward the moving hand, the still hand's wall staying: %s" % c.center)
	_check(c.height == start.height and c.rise == start.rise and c.pitch == start.pitch, "a hand a little higher neither raises its walls nor its plinth, and its roof keeps its slope over the same depth: %s" % c)
	c = WallTool.resize(start, front, [_hand(Vector3(-0.4, 1, 0)), _hand(Vector3(0.4, 1, 0))])
	_check(c.center.is_equal_approx(start.center), "both hands spreading grow it about its middle: %s" % c.center)
	var flank: Array[Transform3D] = [_hand(Vector3(0.05, 1, -0.2)), _hand(Vector3(-0.05, 1, 0.2))]
	c = WallTool.resize(start, flank, [_hand(Vector3(0.05, 1, -0.2)), _hand(Vector3(-0.025, 1, 0.1))])
	_check(c.size.is_equal_approx(Vector2(4.5, 3.375)) and is_equal_approx(c.center.z, -0.5625), "hands along its flank, a little askew, close its depth only: %s at %s" % [c.size, c.center])
	_check(is_equal_approx(c.pitch, 1.9 * 0.75), "and its roof keeps its slope, its rise scaling with the depth under its ridge: %.3f" % c.pitch)
	c = WallTool.resize(start, flank, [_hand(Vector3(0, 1, -5)), _hand(Vector3(0, 1, 5))])
	_check(c.size.x == 4.5 and c.size.y >= 14.0, "a narrow house deepens under its ridge past twice the old 7 m: %s" % c.size)
	var turned := start.duplicate()
	turned.yaw = 0.6
	var along := Vector3.RIGHT.rotated(Vector3.UP, 0.6) * 0.2
	c = WallTool.resize(turned, [_hand(-along + Vector3.UP), _hand(along + Vector3.UP)], [_hand(-along + Vector3.UP), _hand(along * 3.0 + Vector3.UP)])
	_check(c.size.is_equal_approx(Vector2(9, 4.5)) and c.yaw == 0.6, "a house turned on the ground stretches along its own sides: %s" % c.size)
	var tower := start.duplicate()
	tower.round = true
	c = WallTool.resize(tower, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.4, 1, 0))])
	_check(c.size.is_equal_approx(Vector2(6.75, 6.75)) and c.center.is_equal_approx(Vector3(11.125, 0, 0)), "a round tower's diameter spreads, staying round: %s at %s" % [c.size, c.center])
	_check(is_equal_approx(c.pitch, 1.9 * 1.5), "its cone keeps its slope: %.3f" % c.pitch)
	c = WallTool.resize(tower, front, [_hand(Vector3(-2, 1, 0)), _hand(Vector3(2, 1, 0))])
	_check(c.size.x >= 14.0 and c.size.x == c.size.y, "a tower spreads past twice the 7 m it once stopped at: %s" % c.size)
	c = WallTool.resize(tower, front, [_hand(Vector3(0, 1, 0)), _hand(Vector3(0.01, 1, 0))])
	_check(c.size.is_equal_approx(Vector2.ONE * WallTool.HOUSE_SIDE), "no narrower than the narrowest: %s" % c.size)


## Report (relay): two hands stretching a house vertically make the house itself taller; a tower's height likewise.
func _two_hands_drawn_apart_upright_raise_its_walls() -> void:
	var start := {"center": Vector3(10, 0, 0), "yaw": 0.0, "size": Vector2(4.5, 4.5), "round": false, "rise": 0.0, "height": 2.4, "pitch": 1.9, "curve": 0.0, "overhang": 0.3}
	var front: Array[Transform3D] = [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1, 0))]
	var c := WallTool.resize(start, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1.6, 0))], 1.0)
	_check(is_equal_approx(c.height, 3.0) and c.size.is_equal_approx(start.size) and c.rise == 0.0, "one hand rising 0.6 m over the other makes its walls 0.6 m taller, as wide, on the ground: %s" % c)
	c = WallTool.resize(start, front, [_hand(Vector3(-0.2, 1.6, 0)), _hand(Vector3(0.2, 1.6, 0))], 1.0)
	_check(c.height == start.height and c.rise == 0.0, "both rising together leave it as it was: %s" % c)
	c = WallTool.resize(start, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1.4, 0))], 3.0)
	_check(is_equal_approx(c.height, 3.6), "a far house grows by the reach gain, a course at a time: %.2f" % c.height)
	var apart: Array[Transform3D] = [_hand(Vector3(0, 0.6, 0)), _hand(Vector3(0, 2.6, 0))]
	c = WallTool.resize(start, apart, [_hand(Vector3(0, 0.6, 0)), _hand(Vector3(0, 0.7, 0))], 1.0)
	_check(is_equal_approx(c.height, WallLayout.MIN_HEIGHT), "brought together upright they shorten it, down to the lowest a wall stands: %.2f" % c.height)
	c = WallTool.resize(start, front, [_hand(Vector3(-0.6, 1, 0)), _hand(Vector3(0.6, 1.9, 0))], 1.0)
	_check(is_equal_approx(c.height, 3.3) and c.size.x > 9.0, "spread and drawn apart at once, it grows wider and taller: %s" % c)
	var tower := start.duplicate()
	tower.round = true
	tower.height = 4.5
	c = WallTool.resize(tower, front, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1.9, 0))], 1.0)
	_check(is_equal_approx(c.height, 5.4) and c.size.is_equal_approx(tower.size), "a tower's height grows the same way: %s" % c)


## Everything built or placed is moved by one hand and sized by two: a wall or fence is carried and turned about its
## middle, drawn out along its line by the hands' spread, and made taller upright, a fence keeping its height.
func _a_wall_is_carried_and_sized_as_a_house_is() -> void:
	var d := {"points": PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(6, 0, 2)]), "height": 2.0, "rise": 0.0, "fence": false,
		"openings": PackedVector4Array([Vector4(2.0, 0.0, WallLayout.DoorStyle.ARCHWAY, 1.0)]), "lanterns": PackedVector3Array([Vector3(5.0, 1.2, 1.0)]),
		"flags": PackedFloat32Array([1.0]), "ruins": PackedVector2Array([Vector2(3.0, 3.5)])}
	var at := WallTool.line_of(d)
	_check(at.center.is_equal_approx(Vector3(10.0 / 3.0, 0, 2.0 / 3.0)) and is_equal_approx(at.run, 4.0 + sqrt(8.0)) and at.length == 1.0, "a wall's middle and length read back: %s" % at)
	var c := WallTool.carry(at, _hand(Vector3(0, 1, 0)), _hand(Vector3(0.5, 1.3, 0), PI * 0.5), 2.0)
	_check(c.center.is_equal_approx(at.center + Vector3(1, 0, 0)) and is_equal_approx(c.yaw, PI * 0.5) and c.rise == 0.0, "one hand carries and turns it, raising nothing: %s" % c)
	var r := WallTool.reshape_line(d, c)
	var turned: Vector3 = c.center + Basis(Vector3.UP, PI * 0.5) * (Vector3(4, 0, 0) - at.center)
	_check(Vector2(r.points[1].x - turned.x, r.points[1].z - turned.z).length() < 1e-4 and r.openings == d.openings and r.lanterns == d.lanterns, "its line is carried and turned about its middle, its fittings where they were along it: %s" % r.points)
	var pair: Array[Transform3D] = [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 1, 0))]
	c = WallTool.stretch_line(at, pair, [_hand(Vector3(-0.4, 1, 0)), _hand(Vector3(0.4, 1.3, 0))], 1.0)
	_check(is_equal_approx(c.length, 2.0) and is_equal_approx(c.height, 2.3) and c.center == at.center, "two hands spread twice as far draw it twice as long about its middle, and one rising makes it taller: %s" % c)
	r = WallTool.reshape_line(d, c)
	_check(is_equal_approx(Commands.length(r.points), 2.0 * at.run) and is_equal_approx(r.openings[0].x, 4.0) and is_equal_approx(r.lanterns[0].x, 10.0) and is_equal_approx(r.flags[0], 2.0) and r.ruins[0].is_equal_approx(Vector2(6.0, 7.0)), "every opening, lantern, flag and ruin keeps its share of the line: %s" % r)
	c = WallTool.stretch_line(at, pair, [_hand(Vector3(0, 1, 0)), _hand(Vector3(0.001, 1, 0))], 1.0)
	_check(is_equal_approx(c.length * at.run, 1.0), "closed up, it stops a metre long: %.2f" % (c.length * at.run))
	var fence := at.duplicate()
	fence.fence = true
	c = WallTool.stretch_line(fence, pair, [_hand(Vector3(-0.2, 1, 0)), _hand(Vector3(0.2, 2, 0))], 1.0)
	_check(c.height == fence.height, "a fence keeps its height")


func _a_raised_house_stands_on_a_plinth() -> void:
	var low := _house(6.0, 4.0)
	var w := _house(6.0, 4.0)
	w.rise = 1.2
	w.build(_slope)
	low.build(_slope)
	_check(is_equal_approx(w.samples[0].y, low.samples[0].y + 1.2), "its foot stands 1.2 m above its lowest ground: %.2f" % (w.samples[0].y - low.samples[0].y))
	var gap := _plinth_gap(w)
	_check(gap <= 1e-4, "its courses reach the ground all round, nowhere floating: %.2f m at most above it" % gap)
	var tall := _house(6.0, 4.0)
	tall.rise = 8.0
	tall.build(_slope)
	_check(is_equal_approx(tall.samples[0].y, low.samples[0].y + 8.0), "raised 8 m, past where a plinth once stopped at 3 m: %.2f" % (tall.samples[0].y - low.samples[0].y))
	gap = _plinth_gap(tall)
	_check(gap <= 1e-4, "an 8 m plinth reaches the ground all round: %.2f m at most above it" % gap)
	_check(w.stones.any(func(st: Dictionary) -> bool: return st.kind == "block" and absf(st.s - w.archways()[0]) < WallLayout.ARCH_HALF - 0.05 and st.y < 0.0), "its doorway opens on its floor, the plinth whole under it")
	_check(w.stones.size() > low.stones.size(), "the plinth is laid in stones: %d against %d" % [w.stones.size(), low.stones.size()])
	var plaster := _house(6.0, 4.0)
	plaster.plaster = true
	plaster.rise = 1.2
	plaster.build(_flat)
	_check(plaster.stones.any(func(st: Dictionary) -> bool: return st.kind == "block" and st.y < 0.0), "a plaster house stands on a stone plinth")
	var supported := _house(6.0, 4.0)
	supported.rise = 1.2
	var under := Massing.of(low, null)
	supported.supports = [under]
	supported.build(_slope)
	_check(is_equal_approx(supported.samples[0].y, under.rest(supported.points[0].x, supported.points[0].z) - WallLayout.SINK), "a house standing on a build stays on its top")
	var d := {"points": PackedVector3Array(w.points), "height": 2.4, "rise": 1.2, "closed": true, "fence": false, "plaster": false, "plinth_plaster": false, "lanterns": PackedVector3Array(), "flags": PackedFloat32Array()}
	var flat := d.duplicate()
	flat.rise = 0.0
	_check(is_equal_approx(Budget.wall(d).wall_m2 - Budget.wall(flat).wall_m2, 20.0 * 1.2), "the budget counts the plinth as stone wall")


func _plinth_gap(w: WallLayout) -> float:
	var gap := 0.0
	for i in w.samples.size():
		var q := w.samples[i]
		if absf(w.lengths[i] - w.archways()[0]) < WallLayout.ARCH_HALF + 0.3:
			continue
		var under := w.stones.filter(func(st: Dictionary) -> bool: return st.kind in ["block", "pier"] and absf(st.s - w.lengths[i]) < 0.4)
		var lowest := INF
		for st: Dictionary in under:
			lowest = minf(lowest, st.xform.origin.y - st.size.y * 0.5)
		gap = maxf(gap, lowest - _slope(q.x, q.z))
	return gap


func _a_resized_house_keeps_its_fittings_and_roof() -> void:
	var at := {"center": Vector3(0, 0, 0), "yaw": 0.0, "size": Vector2(6, 4), "round": false}
	var d := {"points": PackedVector3Array(WallTool.outline(at)), "closed": true, "rise": 0.0, "openings": PackedVector4Array([Vector4(3.0, 1.2, 0, 1), Vector4(8.0, 0.0, 0, 1), WallLayout.archway(1.0)]),
		"lanterns": PackedVector3Array([Vector3(13.0, 2.0, -1.0)]), "flags": PackedFloat32Array([18.0]),
		"roof": {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array([Vector2(1.5, 0.8)]), "dormers": PackedVector2Array([Vector2(-1.0, -1.6)]), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}}
	d.height = 2.4
	var from := WallTool.house_of(d)
	_check(from.center.is_equal_approx(at.center) and from.size.is_equal_approx(at.size) and WallTool.outline(from) == WallTool.outline(at), "a built house's footprint reads back from its corners: %s" % from)
	_check(from.height == 2.4 and from.pitch == 1.6 and from.overhang == RoofLayout.OVERHANG, "and its height and roof: %s" % from)
	var moved := from.duplicate()
	moved.center = Vector3(5, 0, 2)
	moved.yaw = PI * 0.5
	var r := WallTool.reshape_house(d, moved)
	var same := func(a: Array, b: Array) -> bool: return a.size() == b.size() and range(a.size()).all(func(i: int) -> bool: return a[i].is_equal_approx(b[i]) if not a[i] is float else is_equal_approx(a[i], b[i]))
	_check(same.call(Array(r.openings), Array(d.openings)) and same.call(Array(r.lanterns), Array(d.lanterns)) and same.call(Array(r.flags), Array(d.flags)) and same.call(Array(r.roof.chimneys), Array(d.roof.chimneys)) and same.call(Array(r.roof.dormers), Array(d.roof.dormers)), "carried and turned, every fitting keeps its place on its wall and roof: %s" % r)
	var stands := WallTool.house_of(World.reshaped(d, r))
	_check(stands.center.is_equal_approx(moved.center) and stands.size.is_equal_approx(from.size) and is_equal_approx(angle_difference(stands.yaw, moved.yaw), 0.0), "its walls stand where it was carried, as large: %s" % stands)
	var wide := from.duplicate()
	wide.size = Vector2(12, 4)
	r = WallTool.reshape_house(d, wide)
	_check(r.points.size() == 4 and is_equal_approx(r.points[0].distance_to(r.points[1]), 12.0), "the wall line takes the new width")
	_check(is_equal_approx(r.openings[0].x, 6.0) and is_equal_approx(r.openings[0].y, 1.2), "a window halfway along the front stays halfway along it, as high: %s" % r.openings[0])
	_check(is_equal_approx(r.openings[1].x, 14.0) and is_equal_approx(r.openings[2].x, 2.0), "a door on the end wall stays on it, an arch on the front in proportion: %s, %s" % [r.openings[1], r.openings])
	_check(is_equal_approx(r.lanterns[0].x, 22.0) and r.lanterns[0].z == -1.0 and is_equal_approx(r.flags[0], 30.0), "a lantern inside keeps its face; it and a flag keep their places: %s, %s" % [r.lanterns, r.flags])
	_check(is_equal_approx(r.roof.pitch, 1.6) and r.roof.chimneys[0].is_equal_approx(Vector2(3.0, 0.8)), "the roof keeps its slope over the same depth; a chimney moves out along the ridge: %s" % r.roof)
	_check(r.roof.dormers.size() == 1 and r.roof.dormers[0].is_equal_approx(Vector2(-2.0, -1.6)), "a dormer moves along the ridge as a chimney does: %s" % r.roof.dormers)
	var deep := from.duplicate()
	deep.size = Vector2(6, 8)
	deep.pitch = 3.2
	r = WallTool.reshape_house(d, deep)
	var ridge: Vector3 = r.points[1] - r.points[0]
	_check(is_equal_approx(ridge.length(), 6.0) and absf(ridge.z) < 1e-4, "stretched deeper than long, its ridge keeps its axis")
	_check(is_equal_approx(r.roof.pitch, 3.2), "and the roof takes the pitch it is given: %f" % r.roof.pitch)
	_check(r.roof.chimneys[0].is_equal_approx(Vector2(1.5, 1.6)), "a chimney keeps its spot on the house as the depth grows: %s" % r.roof.chimneys[0])
	_check(r.roof.dormers[0].is_equal_approx(Vector2(-1.0, -3.2)), "and a dormer its slope: %s" % r.roof.dormers[0])
	_check(is_equal_approx(r.openings[0].x, 3.0), "the front window stays in the middle of the front as it moves out: %s" % r.openings[0])
	var tower := {"points": PackedVector3Array(WallLayout.circle(Vector3(2, 0, 2), 2.0)), "closed": true, "rise": 0.0, "height": 4.5, "openings": PackedVector4Array([Vector4(TAU * 0.5, 0.0, 0, 1)]),
		"lanterns": PackedVector3Array(), "flags": PackedFloat32Array([TAU]),
		"roof": {"kind": RoofLayout.Kind.CONE, "center": Vector3(2, 0, 2), "radius": 2.0, "pitch": 3.2, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": true, "thatch": false}}
	var wider := WallTool.house_of(tower)
	_check(wider.round and wider.size == Vector2(4, 4), "a tower reads back round, 4 m across")
	wider.size = Vector2(6, 6)
	wider.pitch = 4.8
	r = WallTool.reshape_house(tower, wider)
	_check(is_equal_approx(r.roof.radius, 3.0) and is_equal_approx(r.roof.pitch, 4.8) and r.roof.center == Vector3(2, 0, 2), "its cone covers the wider wall at the same slope: %s" % r.roof)
	_check(absf(r.openings[0].x - TAU * 0.75) < 0.05 and absf(r.flags[0] - TAU * 1.5) < 0.05, "its door and flag keep their bearing: %s, %s" % [r.openings, r.flags])


func _the_ridge_keeps_its_axis() -> void:
	var f := WallTool.footprint(Vector3(1, 0, 1), 0.0, Vector2(5, 5))
	_check(is_equal_approx(f.length, 5.0) and is_equal_approx(f.depth, 5.0), "a square footprint is a square house: %s" % f)
	f = WallTool.footprint(Vector3.ZERO, 0.0, Vector2(3, 8))
	_check(is_equal_approx(f.length, 3.0) and is_equal_approx(f.depth, 8.0) and absf(f.a.z - f.b.z) < 1e-4, "a footprint deeper than wide keeps its ridge: %s" % f)
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
	var here := Wall.pack_roof(w, r, Wall.kinds(), Palette.plain())
	var there := Wall.pack_roof(w, copy, Wall.kinds(), Palette.plain())
	_check(not here.tiles.is_empty() and here.tiles == there.tiles and here.shadows == there.shadows, "with the same tiles")
	copy.pitch = 2.0
	_check(not copy.same_inputs(r), "a pulled pitch is another roof")


func _pushed_down_a_roof_goes_flat() -> void:
	_check(RoofLayout.snap_pitch(-2.0, 0.1) == 0.0, "pushing past the bottom lands flat")
	_check(RoofLayout.snap_pitch(RoofLayout.FLAT_SNAP - 0.05, 0.1) == 0.0, "just above flat snaps to flat")
	_check(is_equal_approx(RoofLayout.snap_pitch(RoofLayout.FLAT_SNAP + 0.03, 0.1), RoofLayout.FLAT_SNAP), "the lowest pitch above the snap stays pitched")
	_check(is_equal_approx(RoofLayout.snap_pitch(2.04, 0.1), 2.0), "pitches step by 0.1")
	_check(is_equal_approx(RoofLayout.snap_pitch(12.04, 0.1), 12.0), "pulled up it rises past the 6 m it once stopped at")


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
		if absf(x.origin.x - 3.0) > inner.x + RoofLayout.DECK_TUCK or absf(x.origin.z) > inner.y + RoofLayout.DECK_TUCK or top > r.height_at(x.origin.x, x.origin.z) + 0.01 or top < r.height_at(x.origin.x, x.origin.z) - 0.1:
			_check(false, "a deck slab out of place at %s" % x.origin)
			return
		area += x.basis.x.length() * x.basis.z.length()
	_check(area > inner.x * inner.y * 4.0 * 0.85, "the deck covers the floor: %.1f m² of %.1f" % [area, inner.x * inner.y * 4.0])
	var t := r.ray_hit(Vector3(3, 10, 1), Vector3.DOWN)
	_check(absf(t - (10.0 - r.height_at(3, 1))) < 0.01, "pointing down at the deck hits its curved surface: %f" % t)
	_check(r.ray_hit(Vector3(3, 10, 3.0), Vector3.DOWN) == INF, "a flat roof has no eave beyond the walls")
	var open := 0
	for i in 60:
		for j in 40:
			var p := Vector2(3.0 + (i / 59.0 - 0.5) * 2.0 * inner.x, (j / 39.0 - 0.5) * 2.0 * inner.y)
			if not r.mortar.any(func(m): return _covers(m.xform, p)):
				open += 1
	_check(open == 0 and r.mortar.all(func(m): return m.xform.origin.y + m.xform.basis.y.length() * 0.5 < r.height_at(m.xform.origin.x, m.xform.origin.z) - RoofLayout.DECK_DROP), "a mortar bed under the flags leaves no joint open to the floor: %d of 2400 points open" % open)
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
		_check(_degenerate(r.torching_faces) == 0, "pitch %.1f %s: torching has no degenerate triangles" % [r.pitch, RoofLayout.Kind.keys()[r.kind]])
		_check(r.flat() == r.torching_faces.is_empty(), "pitch %.1f %s: torching under a pitched roof only" % [r.pitch, RoofLayout.Kind.keys()[r.kind]])
		for i in range(0, r.torching_faces.size(), 3):
			var t := r.torching_faces.slice(i, i + 3)
			# Godot's front faces turn clockwise, so one facing down winds counter-clockwise seen from below.
			if (t[1] - t[0]).cross(t[2] - t[0]).y < 0.0:
				_check(false, "pitch %.1f %s: torching faces down, under the tiles" % [r.pitch, RoofLayout.Kind.keys()[r.kind]])
				break
		_check(r.tiles.all(func(t): return absf(t.xform.basis.determinant()) > 1e-6), "pitch %.1f: no flattened tiles" % r.pitch)


func _covers(x: Transform3D, p: Vector2) -> bool:
	var inverse := x.affine_inverse()
	return AABB(Vector3.ONE * -0.5, Vector3.ONE).intersects_ray(inverse * Vector3(p.x, x.origin.y + 10.0, p.y), inverse.basis * Vector3.DOWN) != null


func _gabled(plaster: bool, curve := 0.0, style := WallLayout.GableEnd.WALL, points := WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0), pitch := 2.0) -> Array:
	var w := WallLayout.new()
	w.points.assign(points)
	w.closed = true
	w.height = 2.4
	w.plaster = plaster
	w.gable_end = style
	w.cover = WallLayout.Cover.ROOF
	var r := RoofLayout.new()
	r.corners = w.points
	r.pitch = pitch
	r.curve = curve
	w.gable = r
	w.build(_flat)
	r.base = w.samples[0].y + w.height + WallLayout.CAP
	r.stepped = style == WallLayout.GableEnd.STEPS
	r.build()
	return [w, r]


## Every style on a stone and a plaster house, at each curvature, as built, steepest and narrowest, and stretched by a
## resize either way.
func _gable_cases() -> Array:
	var d := {"points": PackedVector3Array(WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)), "closed": true, "rise": 0.0, "height": 2.4, "openings": PackedVector4Array(),
		"lanterns": PackedVector3Array(), "flags": PackedFloat32Array(),
		"roof": {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 2.0, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}}
	var shapes := [[d.points, 2.0], [WallLayout.rectangle(Vector3(0, 0, 0), Vector3(4, 0, 0), 2.4), 9.0]]
	for size in [Vector2(12, 4), Vector2(6, 8), Vector2(3, 2.4)]:
		var at := WallTool.house_of(d)
		at.size = size
		at.pitch = d.roof.pitch * size.y / 4.0
		var r := WallTool.reshape_house(d, at)
		shapes.append([r.points, r.roof.pitch])
	var out := []
	for style in WallLayout.GableEnd.values():
		for plaster in [false, true]:
			for curve in [0.0, 0.8, -0.8]:
				for shape in shapes:
					out.append({"style": WallLayout.GableEnd.keys()[style], "plaster": plaster, "curve": curve, "built": _gabled(plaster, curve, style, shape[0], shape[1])})
	return out


## A point in the house's frame: x along its first side from the middle, y up, z across.
func _local(w: WallLayout, p: Vector3) -> Vector3:
	var along := (w.points[1] - w.points[0]).normalized()
	var across := (w.points[3] - w.points[0]).normalized()
	var mid := (w.points[0] + w.points[2]) * 0.5
	return Vector3((p - mid).dot(along), p.y, (p - mid).dot(across))


func _gable_pieces(w: WallLayout) -> Array:
	return w.stones.filter(func(s): return s.y > w.height + WallLayout.CAP)


func _every_gable_end_stays_on_its_footprint() -> void:
	for c in _gable_cases():
		var w: WallLayout = c.built[0]
		var half := Vector2(w.points[0].distance_to(w.points[1]), w.points[0].distance_to(w.points[3])) * 0.5 + Vector2.ONE * (WallLayout.THICKNESS * 0.5 + 0.1)
		for s in _gable_pieces(w):
			var x: Transform3D = s.xform
			for corner in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
				var p := _local(w, x * corner)
				if absf(p.x) > half.x or absf(p.z) > half.y:
					_check(false, "%s %s curve %.1f, %.1f by %.1f: a %s stands off the footprint at %s" % [c.style, "plaster" if c.plaster else "stone", c.curve, half.x * 2.0, half.y * 2.0, s.kind, p])
					return


## No style leaves a gable end open from either side: each piece across its face runs through the wall's thickness,
## centred on its line, so its outer side faces out of the house and its inner side in.
func _every_gable_end_closes_its_wall() -> void:
	for c in _gable_cases():
		var w: WallLayout = c.built[0]
		var faced := 0
		var span := Vector2(w.points[0].distance_to(w.points[1]), w.points[0].distance_to(w.points[3])) * 0.5
		for s in _gable_pieces(w):
			if not s.kind in ["block", "mortar", "plaster", "board"]:
				continue
			var x: Transform3D = s.xform
			var p := _local(w, x.origin)
			var through := x.basis.z.length()
			var off := minf(absf(absf(p.x) - span.x), absf(absf(p.z) - span.y))
			if off > 0.05 or through < WallLayout.THICKNESS - WallLayout.PLASTER_INSET * 2.0 - 0.15:
				_check(false, "%s %s curve %.1f: a %s %.2f off its wall's line, %.2f thick" % [c.style, "plaster" if c.plaster else "stone", c.curve, s.kind, off, through])
				return
			faced += 1
		var mesh: bool = c.plaster and c.style == "WALL"
		_check(mesh or faced > 10, "%s %s curve %.1f: the gable ends are laid, %d pieces" % [c.style, "plaster" if c.plaster else "stone", c.curve, faced])


## Stepped, the gable ends stand over the slopes all the way up and the tiles stop inside them; a boarded gable's
## planks stay under the slopes as courses do.
func _crow_steps_stand_over_the_roof() -> void:
	for c in _gable_cases():
		var w: WallLayout = c.built[0]
		var r: RoofLayout = c.built[1]
		var span := w.points[0].distance_to(w.points[1]) * 0.5
		var pieces := _gable_pieces(w)
		if c.style == "BOARDS":
			for s in pieces.filter(func(s): return s.kind == "board" and s.xform.basis.x.y == 0.0):
				var x: Transform3D = s.xform
				var top := x.origin + x.basis.y * 0.5
				for end in [top - x.basis.x * 0.5, top + x.basis.x * 0.5]:
					if end.y > r.height_at(end.x, end.z) + 0.03:
						_check(false, "curve %.1f: a board's top at %s stands above the slope" % [c.curve, end])
						return
		if c.style != "STEPS":
			continue
		for t in r.tiles:
			if absf(_local(w, t.xform.origin).x) > span:
				_check(false, "%s curve %.1f: a tile at %s reaches past a stepped end wall's line" % ["plaster" if c.plaster else "stone", c.curve, _local(w, t.xform.origin)])
				return
		var hs := w.points[0].distance_to(w.points[3]) * 0.5 + WallLayout.THICKNESS * 0.5
		for i in 41:
			var z := (-hs + 2.0 * hs * i / 40.0) * 0.98
			var rise := r.base + r.rise(1.0 - absf(z) / hs)
			var top := -INF
			for s in pieces:
				var x: Transform3D = s.xform
				var p := _local(w, x.origin)
				if p.x > 0.0 and absf(p.z - z) <= x.basis.x.length() * 0.5:
					top = maxf(top, x.origin.y + x.basis.y.length() * 0.5)
			if top < rise:
				_check(false, "%s curve %.1f: at %.2f across the steps top out at %.2f, under the roof at %.2f" % ["plaster" if c.plaster else "stone", c.curve, z, top, rise])
				return


func _the_budget_counts_each_gable_end_as_laid() -> void:
	for plaster in [false, true]:
		var face := "plaster_m2" if plaster else "wall_m2"
		for curve in [0.0, 0.8, -0.8]:
			for pitch in [0.8, 2.0, 5.0]:
				var d := {"points": WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0), "closed": true, "height": 2.4, "rise": 0.0, "fence": false, "gable_end": 0,
					"plaster": plaster, "plinth_plaster": false, "timber_style": 0, "openings": [], "lanterns": [], "flags": [], "roof": {"kind": RoofLayout.Kind.GABLE, "radius": 2.0, "pitch": pitch, "curve": curve, "chimneys": [], "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}}
				var walls := 20.0 * 2.4
				var wall := Budget.wall(d)
				d.gable_end = WallLayout.GableEnd.BOARDS
				var boards := Budget.wall(d)
				_check(is_equal_approx(boards.get("wall_m2", 0.0) + boards.get("plaster_m2", 0.0), wall[face]) and is_equal_approx(boards.get("wall_m2", 0.0) - (0.0 if plaster else walls), wall[face] - walls), "boards count as stone wall over the same face")
				d.gable_end = WallLayout.GableEnd.STEPS
				var w: WallLayout = _gabled(plaster, curve, WallLayout.GableEnd.STEPS, d.points, pitch)[0]
				var h := w.course_height()
				var spans := {}
				for s in _gable_pieces(w):
					if s.kind in ["block", "mortar", "plaster"]:
						var p := _local(w, s.xform.origin)
						var row := Vector2i(signi(p.x), floori((s.y - w.height - WallLayout.CAP) / h))
						var run: float = s.xform.basis.x.length() * 0.5
						var was: Vector2 = spans.get(row, Vector2(INF, -INF))
						spans[row] = Vector2(minf(was.x, p.z - run), maxf(was.y, p.z + run))
				var laid := 0.0
				for row in spans:
					laid += (spans[row].y - spans[row].x) * h
				var counted: float = Budget.wall(d)[face] - walls
				_check(absf(counted - laid) < laid * 0.08 and counted > wall[face] - walls, "%s pitch %.1f curve %.1f: the steps count their face as laid, %.2f m² for %.2f, more than under the slopes" % [face, pitch, curve, counted, laid])


func _a_gable_continues_the_wall_under_the_slopes() -> void:
	for curve in [0.0, 0.8, -0.8]:
		var built := _gabled(false, curve)
		var w: WallLayout = built[0]
		var r: RoofLayout = built[1]
		var above := w.stones.filter(func(s): return s.y > w.height + WallLayout.CAP)
		var courses := above.filter(func(s): return s.kind == "block")
		var verge := above.filter(func(s): return s.kind == "cope")
		_check(courses.size() > 20, "curve %.1f: a stone house's gable ends are laid in courses: %d" % [curve, courses.size()])
		_check(verge.size() >= 8, "curve %.1f: a verge runs up each rake: %d" % [curve, verge.size()])
		for s in courses:
			var x: Transform3D = s.xform
			var run: Vector3 = x.basis.x * 0.5
			var top: Vector3 = x.origin + x.basis.y * 0.5
			for end in [top - run, top + run]:
				if end.y > r.height_at(end.x, end.z) + 0.03:
					_check(false, "curve %.1f: a gable stone's top at %s stands above the slope at %.2f" % [curve, end, r.height_at(end.x, end.z)])
					return
	var plastered: WallLayout = _gabled(true)[0]
	var up := plastered.stones.filter(func(s): return s.y > plastered.height + WallLayout.CAP)
	_check(not up.is_empty() and up.all(func(s): return s.kind == "timber"), "a plaster house's gable ends carry timber framing")
	var low := WallLayout.new()
	low.points = plastered.points
	low.closed = true
	low.height = 2.4
	low.cover = WallLayout.Cover.ROOF
	low.build(_flat)
	_check(low.stones.all(func(s): return s.y <= low.height + WallLayout.CAP), "with no gable over it a house's walls stop at the cap")


## Each face of a gable end is lit by the air before it, so its normal (Godot's: against the cross product of a
## triangle's edges) must point out of the wall: outward on the outer face, into the house on the inner.
func _gable_faces_face_out_of_the_wall() -> void:
	var r: RoofLayout = _gabled(true)[1]
	var f := r.frame()
	var tris := r.gables()
	_check(not tris.is_empty(), "gable ends have faces")
	for i in range(0, tris.size(), 3):
		var n := -(tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i])
		var d: float = ((tris[i] + tris[i + 1] + tris[i + 2]) / 3.0 - f.mid).dot(f.along)
		var away := signf(d) * signf(absf(d) - r.ridge_length() * 0.5)
		if n.dot(f.along) * away <= 0.0:
			_check(false, "a gable triangle at %.2f along faces into its wall" % d)
			return


func _the_budget_counts_gable_ends() -> void:
	var d := {"points": WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0), "closed": true, "height": 2.4, "rise": 0.0, "fence": false, "gable_end": 0,
		"plaster": false, "plinth_plaster": false, "lanterns": [], "flags": [], "roof": {"kind": RoofLayout.Kind.GABLE, "radius": 2.0, "pitch": 2.0, "curve": 0.0, "chimneys": [], "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}}
	var hs := (4.0 + WallLayout.THICKNESS) * 0.5
	_check(is_equal_approx(Budget.wall(d).wall_m2, 20.0 * 2.4 + 2.0 * hs * 2.0), "a house counts its two gable ends as wall: %s" % Budget.wall(d))
	d.roof.pitch = 0.0
	_check(is_equal_approx(Budget.wall(d).wall_m2, 20.0 * 2.4), "a flat-roofed house has none")


const PITCHES: Array[float] = [0.4, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 9.0]
const CURVES: Array[float] = [-RoofLayout.CURVE, 0.0, RoofLayout.CURVE]


## Every house and tower shape, gable end and pitch the roof tool offers, sagged, straight and bowed: no stone of
## the wall up to its top rises through the tiles' bed. A gable end stands above the top, carried up to its verge.
func _no_wall_rises_through_a_steep_roof() -> void:
	var shapes: Array[Dictionary] = []
	for size in [Vector2(3.0, 2.0), Vector2(5.0, 3.1), Vector2(6.0, 5.0)]:
		for end in WallLayout.GableEnd.values():
			shapes.append({"points": WallLayout.rectangle(Vector3.ZERO, Vector3(size.x, 0, 0), size.y), "end": end, "kind": RoofLayout.Kind.GABLE, "radius": 0.0})
	for radius in [1.2, 2.5]:
		shapes.append({"points": WallLayout.circle(Vector3(1, 0, 1), radius), "end": WallLayout.GableEnd.WALL, "kind": RoofLayout.Kind.CONE, "radius": radius})
	for shape in shapes:
		for pitch in PITCHES:
			for curve in CURVES:
				var r := RoofLayout.new()
				r.kind = shape.kind
				r.center = Vector3(1, 0, 1)
				r.radius = shape.radius
				r.pitch = pitch
				r.curve = curve
				var w := WallLayout.new()
				w.points.assign(shape.points)
				w.closed = true
				w.cover = WallLayout.Cover.ROOF
				w.height = 2.4
				w.gable_end = shape.end
				w.gable = r
				w.build(_flat)
				Wall.pack_roof(w, r, Wall.kinds(), Palette.plain())
				var worst := -INF
				var what := ""
				for st in w.stones:
					if st.y + st.size.y * 0.5 > w.height + WallLayout.CAP + WallLayout.FIT_CLEAR:
						continue
					for c in WallLayout.BOX:
						var p: Vector3 = st.xform * c
						var over := p.y - r.height_at(p.x, p.z)
						if over > worst:
							worst = over
							what = st.kind
				_check(worst <= 0.0, "%s %s pitch %.1f curve %+.0f: a %s stone rises %.3f m through the roof" % [RoofLayout.Kind.keys()[r.kind], WallLayout.GableEnd.keys()[shape.end], pitch, curve, what, worst])


## Every piece of a gable end, the lowest copes, bargeboards, planks and blocks beside its corners too, lies in its end
## wall's plane rather than turning onto the side wall; at every pitch and curve no cope, board, timber or course
## stone shows through the tiles. Crow steps stand over the roof.
func _gable_ends_keep_to_their_wall_under_the_roof() -> void:
	for size in [Vector2(3.0, 2.0), Vector2(5.0, 4.0), Vector2(6.0, 8.0)]:
		for end in WallLayout.GableEnd.values():
			for finish in [[false, -1], [true, -1], [true, 0]]:
				for pitch in PITCHES:
					for curve in CURVES:
						var w := WallLayout.new()
						w.points.assign(WallLayout.rectangle(Vector3.ZERO, Vector3(size.x, 0, 0), size.y))
						w.closed = true
						w.cover = WallLayout.Cover.ROOF
						w.height = 2.4
						w.plaster = finish[0]
						w.timber_style = finish[1]
						w.gable_end = end
						var r := RoofLayout.new()
						r.pitch = pitch
						r.curve = curve
						w.gable = r
						w.build(_flat)
						Wall.pack_roof(w, r, Wall.kinds(), Palette.plain())
						var f := r.frame()
						var turned := 0
						var worst := -INF
						var what := ""
						for st in w.stones:
							var gable: bool = st.xform.origin.y >= r.base + 0.02
							if gable and absf(st.xform.basis.z.normalized().dot(f.across)) > 0.2:
								turned += 1
							if not gable and st.kind != "timber":
								continue
							if end == WallLayout.GableEnd.STEPS and st.kind != "timber":
								continue
							for c in WallLayout.BOX:
								var through := _through_tiles(r, st.xform * c)
								if through > worst:
									worst = through
									what = st.kind
						var house := "%s %s %s pitch %.1f curve %+.1f" % [size, WallLayout.GableEnd.keys()[end], "timbered" if finish[1] >= 0 else "plaster" if finish[0] else "stone", pitch, curve]
						_check(turned == 0, "%s: %d gable pieces turn off their end wall" % [house, turned])
						_check(worst <= 0.0, "%s: a %s stands %.3f m out through the tiles" % [house, what, worst])


## How far `p` stands out past the outer face of the tiles over it, square to the slope: they lie on the roof's bed
## with their middles TILE.y/2 straight above it, so on a steep slope their face is nearer the bed.
static func _through_tiles(r: RoofLayout, p: Vector3) -> float:
	var f := r.frame()
	var steep := cos(r.slope_at(absf((p - f.mid).dot(f.across))))
	return (p.y - r.height_at(p.x, p.z)) * steep - RoofLayout.TILE.y * 0.5 * (1.0 + steep)


## Houses and towers to roof, each with its roof's footprint set: a narrow and a wide house and two towers.
func _roofed() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for size in [Vector2(3.0, 2.0), Vector2(5.0, 3.1), Vector2(6.0, 5.0)]:
		var r := RoofLayout.new()
		out.append({"wall": _house(size.x, size.y), "roof": r})
	for radius in [1.2, 2.5]:
		var w := WallLayout.new()
		w.points = WallLayout.circle(Vector3(1, 0, 1), radius)
		w.closed = true
		w.cover = WallLayout.Cover.ROOF
		w.height = 3.0
		w.build(_flat)
		var r := RoofLayout.new()
		r.kind = RoofLayout.Kind.CONE
		r.center = Vector3(1, 0, 1)
		r.radius = radius
		out.append({"wall": w, "roof": r})
	return out


## A tile hides what lies under the square inside its rounded, lumpy edges.
const SOLID := 0.41


func _every_tile_joint_has_a_tile_under_it() -> void:
	for h in _roofed():
		var r: RoofLayout = (h.roof as RoofLayout)
		if r.kind == RoofLayout.Kind.GABLE:
			r.corners = (h.wall as WallLayout).laid_points
		r.base = 2.54
		for pitch in PITCHES:
			for curve in CURVES:
				r.pitch = pitch
				r.curve = curve
				r.build()
				var open := _uncovered(r)
				_check(open.is_empty(), "%s pitch %.1f curve %+.0f: nothing covers the roof at %d points, first %s" % [RoofLayout.Kind.keys()[r.kind], pitch, curve, open.size(), open[0] if open.size() > 0 else null])


## Points on the slopes, from the eaves up to the ridge cap or finial, that no tile covers.
func _uncovered(r: RoofLayout) -> PackedVector3Array:
	var cells := {}
	for t in r.tiles:
		if t.kind == "tile":
			var o: Vector3 = t.xform.origin
			cells.get_or_add(Vector2i(floori(o.x * 2.0), floori(o.z * 2.0)), []).append(t.xform.affine_inverse())
	var f := r.frame()
	var points := PackedVector3Array()
	var top := 0.2
	if r.kind == RoofLayout.Kind.CONE:
		for k in 72:
			var out := Vector3(cos(TAU * k / 72.0), 0.0, sin(TAU * k / 72.0))
			for i in 60:
				var x := lerpf(top, r.eave() - 0.05, i / 59.0)
				points.append(f.mid + out * x + Vector3.UP * r.rise(1.0 - x / r.half_span()))
	else:
		var half := r.ridge_length() * 0.5 + WallLayout.THICKNESS * 0.5
		for side in [-1.0, 1.0]:
			for k in 60:
				var along: Vector3 = f.along * lerpf(-half, half, k / 59.0)
				for i in 60:
					var x := lerpf(top, r.eave() - 0.05, i / 59.0)
					points.append(f.mid + along + f.across * side * x + Vector3.UP * r.rise(1.0 - x / r.half_span()))
	var open := PackedVector3Array()
	for p in points:
		var c := Vector2i(floori(p.x * 2.0), floori(p.z * 2.0))
		var covered := false
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for inv: Transform3D in cells.get(c + Vector2i(dx, dz), []):
					var l := inv * p
					if absf(l.x) <= SOLID and absf(l.z) <= SOLID and absf(l.y) <= 6.0:
						covered = true
						break
				if covered:
					break
			if covered:
				break
		if not covered:
			open.append(p)
	return open
