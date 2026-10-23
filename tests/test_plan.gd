extends "res://../tests/support/suite.gd"

## Headless checks of how a stroke meets standing walls: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_plan.gd


func _init() -> void:
	_a_stroke_alongside_a_wall_merges_into_it()
	_a_stroke_a_walkway_away_stands_free()
	_a_stroke_from_a_wall_starts_on_it()
	_a_crossing_stroke_meets_the_wall_from_both_sides()
	_a_short_wall_can_meet_another()
	_a_stroke_drifting_near_a_wall_grows_no_spur()
	_a_stroke_passing_a_walls_end_meets_it_there()
	_a_junction_keeps_out_of_an_arch()
	_a_junction_keeps_out_of_neighbouring_arches()
	_a_merged_stroke_wavering_past_reach_stays_merged()
	_a_junction_among_crowded_arches_takes_the_widest_pier()
	_a_wall_arches_over_a_plant()
	_a_wall_over_open_ground_stays_solid()
	finish()


func _line(a: Vector2, b: Vector2) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var n := maxi(1, int(ceil(a.distance_to(b) / 0.45)))
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		out.append(Vector3(p.x, 0, p.y))
	return out


func _standing(arches: Array[float] = []) -> Array[WallLayout]:
	var w := WallLayout.new()
	w.points = _line(Vector2(-6, 0), Vector2(6, 0))
	w.openings.append_array(arches.map(WallLayout.archway))
	w.build(Terrain.flat)
	return [w]


func _plan(a: Vector2, b: Vector2, obstacles := PackedVector3Array(), standing := _standing()) -> Array[WallLayout]:
	return _plan_stroke(_line(a, b), obstacles, standing)


func _plan_stroke(stroke: Array[Vector3], obstacles := PackedVector3Array(), standing := _standing()) -> Array[WallLayout]:
	return WallPlan.new(standing, obstacles, 1).pieces(stroke, Terrain.flat)


## Smallest centre-line distance from any sample of `w` to the standing wall at z = 0, x in [-6, 6].
func _gap(w: WallLayout) -> float:
	var m := INF
	for p in w.samples:
		m = minf(m, Vector2(p.x - clampf(p.x, -6, 6), p.z).length())
	return m


func _a_stroke_alongside_a_wall_merges_into_it() -> void:
	for gap in [0.0, 0.5, 1.2]:
		var got := _plan(Vector2(-5, gap), Vector2(5, gap))
		check(got.is_empty(), "a stroke %.1f m from a wall builds %d walls, not none" % [gap, got.size()])


func _a_stroke_a_walkway_away_stands_free() -> void:
	var got := _plan(Vector2(-5, 2.5), Vector2(5, 2.5))
	check(got.size() == 1, "a stroke 2.5 m away builds %d walls, not one" % got.size())
	if got.size() == 1:
		check(_gap(got[0]) >= WallPlan.REACH - 0.01, "it keeps %.2f m from the wall" % _gap(got[0]))


func _a_stroke_from_a_wall_starts_on_it() -> void:
	var got := _plan(Vector2(1, 0.4), Vector2(1, 6))
	check(got.size() == 1, "a stroke away from a wall builds %d walls, not one" % got.size())
	if got.size() == 1:
		check(absf(got[0].samples[0].z) < 0.01, "it starts on the wall's centre line, at z=%.2f" % got[0].samples[0].z)
		check(got[0].samples.all(func(p): return p.z > -0.01), "it does not poke through")


func _a_crossing_stroke_meets_the_wall_from_both_sides() -> void:
	var got := _plan(Vector2(2, -5), Vector2(2, 5))
	check(got.size() == 2, "a crossing stroke builds %d walls, not two" % got.size())
	for w in got:
		var on := [w.samples[0], w.samples[-1]].filter(func(p): return absf(p.z) < 0.01)
		check(on.size() == 1, "each half has one end on the wall")


func _a_wall_arches_over_a_plant() -> void:
	var got := _plan(Vector2(-3, 6), Vector2(3, 6), PackedVector3Array([Vector3(-1.2, 0, 6.2)]))
	for w in got:
		w.build(Terrain.flat)
	check(got.size() == 1 and got[0].openings.size() == 1, "a wall over a bush has one arch")
	if got.size() == 1 and got[0].openings.size() == 1:
		check(absf(got[0].point_at(got[0].openings[0].x).x + 1.2) < 0.25, "the arch stands over the bush")
		check(got[0].archways() == got[0].openings.map(func(o): return o.x), "and the layout opens it")


func _a_wall_over_open_ground_stays_solid() -> void:
	for length in [3.0, 5.0, 8.0, 27.0, 120.0]:
		var got := _plan(Vector2(-length * 0.5, 6), Vector2(length * 0.5, 6))
		check(got.size() == 1 and got[0].openings.is_empty(), "a %s m wall over open ground stays solid" % length)


func _a_short_wall_can_meet_another() -> void:
	var got := _plan(Vector2(2, 0.3), Vector2(2, 2.6))
	check(got.size() == 1, "a 2.6 m stroke from a wall builds %d walls, not one" % got.size())


func _a_stroke_drifting_near_a_wall_grows_no_spur() -> void:
	var stroke: Array[Vector3] = []
	for i in 30:
		var x := -6.0 + i * 0.4
		stroke.append(Vector3(x, 0, 2.0 - 0.4 * exp(-pow(x, 2))))
	for w in _plan_stroke(stroke):
		check(_gap(w) >= WallPlan.REACH - 0.05, "a stroke dipping toward a wall keeps %.2f m from it" % _gap(w))


func _a_stroke_passing_a_walls_end_meets_it_there() -> void:
	var got := _plan(Vector2(7, -5), Vector2(7, 5))
	check(got.size() == 2, "a stroke passing 1 m from a wall's end builds %d walls, not two" % got.size())
	for w in got:
		var tip := [w.samples[0], w.samples[-1]].filter(func(p): return Vector2(p.x - 6.0, p.z).length() < 0.05)
		check(tip.size() == 1, "each meets the wall at its end")


func _a_junction_keeps_out_of_an_arch() -> void:
	var standing := _standing([0.0 + 6.0])
	var got := _plan(Vector2(0, 0.5), Vector2(0, 6), PackedVector3Array(), standing)
	check(got.size() == 1, "a stroke from an arch builds %d walls, not one" % got.size())
	if got.size() == 1:
		var x := got[0].samples[0].x
		check(absf(x) >= WallLayout.ARCH_HALF + WallLayout.RING, "its junction stands clear of the arch, at x=%.2f" % x)


func _a_junction_keeps_out_of_neighbouring_arches() -> void:
	var standing := _standing([4.73, 7.27])
	var got := _plan(Vector2(0.1 + 0.27, 0.5), Vector2(0.37, 6), PackedVector3Array(), standing)
	if got.size() == 1:
		var x := got[0].samples[0].x
		for a in [-1.27, 1.27]:
			check(absf(x - a) >= WallLayout.ARCH_HALF + WallLayout.RING, "a junction between two arches stands clear of both, at x=%.2f" % x)
	else:
		check(false, "a stroke between two arches builds %d walls, not one" % got.size())


func _a_merged_stroke_wavering_past_reach_stays_merged() -> void:
	var stroke: Array[Vector3] = []
	for i in 30:
		var x := -5.0 + i * 0.35
		stroke.append(Vector3(x, 0, 1.0 if i < 5 else 1.9 + 0.2 * sin(i * 1.7)))
	var got := _plan_stroke(stroke)
	check(got.is_empty(), "a stroke wavering between 1.7 and 2.1 m from a wall after merging builds %d walls" % got.size())


func _a_junction_among_crowded_arches_takes_the_widest_pier() -> void:
	var w := WallLayout.new()
	w.points = _line(Vector2(0, 0), Vector2(5.4, 0))
	w.openings.assign([1.4, 3.94].map(WallLayout.archway))
	w.build(Terrain.flat)
	check(w.archways().size() == 2, "a 5.4 m wall opens both arches")
	var s := WallPlan._clear_of_arches(w, 1.5)
	check(absf(s - 1.4) > 0.9 and absf(s - 3.94) > 0.9, "with no clear spot the junction stands off both arches, at s=%.2f" % s)
