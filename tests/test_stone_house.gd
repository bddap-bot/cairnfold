extends "res://../tests/support/suite.gd"

## Headless checks that a stone house is one masonry from its foundation through its walls to its gables:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_stone_house.gd


func _init() -> void:
	_the_foundation_is_the_walls_own_courses()
	_stones_shade_by_their_height_over_the_ground()
	_gables_carry_the_walls_courses_and_mortar()
	finish()


func _house(rise: float, gabled := false) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.height = 2.4
	w.rise = rise
	w.finish = WallLayout.Finish.BARE
	if gabled:
		var r := RoofLayout.new()
		r.corners = w.points
		r.pitch = 2.0
		w.gable = r
	w.build(Terrain.flat)
	return w


func _blocks(w: WallLayout, lo: float, hi: float) -> Array:
	return w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "block" and st.y >= lo and st.y < hi)


func _luma(stones: Array) -> float:
	var sum := 0.0
	for st in stones:
		sum += st.color.get_luminance()
	return sum / maxi(stones.size(), 1)


func _depth(stones: Array) -> Vector2:
	var out := Vector2(INF, -INF)
	for st in stones:
		out = Vector2(minf(out.x, st.size.z), maxf(out.y, st.size.z))
	return out


func _the_foundation_is_the_walls_own_courses() -> void:
	var w := _house(1.2)
	var foundation := _blocks(w, -INF, 0.0)
	var wall := _blocks(w, 0.0, w.height)
	check(foundation.size() > 20 and wall.size() > 20, "a raised house lays courses under its foot and over it: %d, %d" % [foundation.size(), wall.size()])
	var under := _depth(foundation)
	var over := _depth(wall)
	check(under.x >= over.x - 1e-3 and under.y <= over.y + 1e-3, "the foundation's stones are as deep as the wall's: %s against %s" % [under, over])
	check(absf(_luma(foundation) / _luma(wall) - 1.0) < 0.04, "the foundation's stone is the wall's colour: %.3f against %.3f" % [_luma(foundation), _luma(wall)])


## Stones darken toward the ground they stand on, so a raised house's foundation, standing in the open, is shaded as
## the wall over it would be at that height, not as stone under the floor.
func _stones_shade_by_their_height_over_the_ground() -> void:
	var low := _house(0.0)
	var raised := _house(1.2)
	for w in [low, raised]:
		for st in w.stones.filter(func(s: Dictionary) -> bool: return s.kind == "block"):
			var over: float = st.y + w.depth_at(st.s)
			var want := clampf(0.6 + over * 0.25, 0.6, 1.0)
			if not is_equal_approx(st.ao, want):
				check(false, "a stone %.2f over the ground is shaded %.2f, not %.2f" % [over, st.ao, want])
				return
	check(_blocks(raised, 0.0, 0.5).all(func(st: Dictionary) -> bool: return st.ao > 0.85), "a raised house's lowest wall courses stand in the light")


func _gables_carry_the_walls_courses_and_mortar() -> void:
	var w := _house(0.0, true)
	var base := w.height + WallLayout.CAP
	var gable := _blocks(w, base, INF)
	check(gable.size() > 10, "a stone gable end is laid in courses: %d stones" % gable.size())
	var mortar := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "mortar" and st.y > base)
	var wall_mortar := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "mortar" and st.y < w.height)
	check(not mortar.is_empty(), "the gable's courses are set in mortar")
	check(mortar.all(func(st: Dictionary) -> bool: return st.color == WallLayout.MORTAR and is_equal_approx(st.size.z, wall_mortar[0].size.z)), "the gable's mortar is the wall's, as deep behind the faces")
	# A course's last stone can be cut to a sliver narrower than a joint, which no panel needs to back.
	var unset := gable.filter(func(st: Dictionary) -> bool:
		return st.size.x > WallLayout.JOINT and not mortar.any(func(m: Dictionary) -> bool: return absf(m.y - st.y) < m.size.y * 0.5 and absf(w.offset(m.s, st.s)) < m.size.x * 0.5 + WallLayout.JOINT + 0.01))
	check(unset.is_empty(), "every gable stone has mortar behind it: %s" % [unset.map(func(st: Dictionary) -> String: return "s %.2f y %.2f size %s" % [st.s, st.y, st.size])])
	check(absf(_luma(gable) / _luma(_blocks(w, 0.0, w.height)) - 1.0) < 0.06, "the gable's stone is the wall's colour")
