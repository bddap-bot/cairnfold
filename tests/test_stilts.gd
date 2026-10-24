extends "res://../tests/support/suite.gd"

## Headless checks of round and long houses raised on stilts: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_stilts.gd


func _init() -> void:
	for kind in [WallLayout.Stilts.PILLARS, WallLayout.Stilts.POSTS]:
		for round in [false, true]:
			_stilts_line_up_under_the_walls(kind, round)
		_stilts_line_up_under_the_walls(kind, false, true)
	_the_grip_sets_the_foundation_under_the_stilts()
	_a_low_raise_stands_on_its_plinth()
	_stilts_stand_on_the_ground_where_it_rises()
	_pillars_carry_a_course_and_posts_beams()
	_the_budget_counts_stilts_as_laid()
	_the_garden_keeps_stilts()
	_stilts_are_deterministic()
	finish()


func _slope(x: float, z: float) -> float:
	return x * 0.1 + z * 0.05


func _raised(kind: WallLayout.Stilts, round: bool, rise: float, ground := Callable(self, "_slope"), timbered := false) -> WallLayout:
	var w := WallLayout.new()
	w.plaster = timbered
	w.points = WallLayout.circle(Vector3(1, 0, 1), 2.0) if round else WallLayout.rectangle(Vector3(0, 0, 0), Vector3(7, 0, 0), 4.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	w.rise = rise
	w.stilts = kind
	w.seed = 3
	w.build(ground)
	return w


func _supports(w: WallLayout) -> Array:
	return w.stones.filter(func(st: Dictionary) -> bool: return st.kind in ["pillar", "post"] or (st.kind == "pier" and st.y < 0.0))


func _name(kind: WallLayout.Stilts, round: bool) -> String:
	return "%s %s" % ["round" if round else "long", WallLayout.Stilts.keys()[kind].to_lower()]


## Every station round the walls has a stilt standing under the wall's centre line, from the foundation or the ground
## up under the foot, and between them nothing of the walls is laid: the house stands on them.
func _stilts_line_up_under_the_walls(kind: WallLayout.Stilts, round: bool, timbered := false) -> void:
	var w := _raised(kind, round, 1.5, _slope, timbered)
	var name := _name(kind, round) + (" timber-framed" if timbered else "")
	check(TimberFrame.applies(w) == timbered, "%s: framed as asked" % name)
	var span := WallLayout.stilt_span(kind, 1.5)
	check(is_equal_approx(span, 1.2), "%s: a 1.5 m raise stands 1.2 m of stilts on a course of foundation: %.2f" % [name, span])
	var at := w.stations()
	var total := w.length()
	if round:
		check(w.corners().is_empty() and at.size() == ceili(total / WallLayout.STILT_SPACING), "%s: stilts stand evenly round it, %d for %.1f m" % [name, at.size(), total])
	else:
		for c in w.corners():
			check(at.any(func(s: float) -> bool: return absf(w.offset(s, c)) < 1e-3), "%s: a stilt stands under the corner at %.2f" % [name, c])
	for i in at.size():
		var gap := w.offset(at[(i + 1) % at.size()], at[i])
		check(gap > 0.0 and gap <= WallLayout.STILT_SPACING + 1e-3, "%s: stilts %d and %d stand %.2f m apart along the walls" % [name, i, (i + 1) % at.size(), gap])
	var supports := _supports(w)
	var top := -WallLayout.COURSE if kind == WallLayout.Stilts.PILLARS else -WallLayout.BEAM.y
	for s in at:
		var under := supports.filter(func(st: Dictionary) -> bool: return absf(w.offset(st.s, s)) < 0.05)
		if under.is_empty():
			check(false, "%s: nothing stands under the walls at %.2f" % [name, s])
			continue
		var foot: Vector3 = w.frame_at(s).point
		var lo := INF
		var hi := -INF
		for st: Dictionary in under:
			var p: Vector3 = st.xform.origin
			if Vector2(p.x - foot.x, p.z - foot.z).length() > 0.05:
				check(false, "%s: a stilt at %.2f stands %.2f m off the wall's centre line" % [name, s, Vector2(p.x - foot.x, p.z - foot.z).length()])
			lo = minf(lo, st.y - st.size.y * 0.5)
			hi = maxf(hi, st.y + st.size.y * 0.5)
		var ground := -w.depth_at(s)
		check(lo <= maxf(ground, -span) + 0.01 and lo >= ground - 0.1, "%s: the stilt at %.2f stands on the foundation or the ground (%.2f, ground %.2f, foundation %.2f)" % [name, s, lo, ground, -span])
		check(hi >= top - 0.05, "%s: the stilt at %.2f reaches up under the walls: its top %.2f, wanted %.2f" % [name, s, hi, top])
	var open := w.stones.filter(func(st: Dictionary) -> bool: return st.kind in ["block", "mortar", "plaster"] and st.y < top and st.y > -span)
	check(open.is_empty(), "%s: no course is laid between the stilts: %d" % [name, open.size()])
	check(w.stones.any(func(st: Dictionary) -> bool: return st.kind == "block" and st.y < -span), "%s: a stone foundation lies under the stilts" % name)
	check(not w.stones.any(func(st: Dictionary) -> bool: return st.kind == "pier" and st.y < -WallLayout.COURSE and st.y > -span) or kind == WallLayout.Stilts.PILLARS, "%s: corner piers stop at the foundation over posts" % name)
	for i in w.samples.size():
		if w.plinths[i] != 0.0:
			check(false, "%s: ivy roots at the foot, not down a plinth that is not there" % name)
			break


## Raised past the stilts' span, the foundation rises with the house, as high as the grip sets.
func _the_grip_sets_the_foundation_under_the_stilts() -> void:
	for kind in [WallLayout.Stilts.PILLARS, WallLayout.Stilts.POSTS]:
		var tops := []
		for rise in [1.5, 2.4, 3.6]:
			var w := _raised(kind, false, rise, Terrain.flat)
			var span := WallLayout.stilt_span(kind, rise)
			var top := -INF
			for st in w.stones:
				if st.kind == "block" and st.y < -span:
					top = maxf(top, st.y + st.size.y * 0.5)
			tops.append(top + w.depth_at(0.0) + WallLayout.SINK)
		check(absf(tops[0] - 0.3) < 0.05 and absf(tops[1] - 0.6) < 0.05 and absf(tops[2] - 1.8) < 0.05, "%s: raised 1.5, 2.4 and 3.6 m, the foundation stands %.2f, %.2f and %.2f m out of the ground" % [WallLayout.Stilts.keys()[kind], tops[0], tops[1], tops[2]])


## A raise too low for stilts to stand in lays the plinth whole, as a house raised on none.
func _a_low_raise_stands_on_its_plinth() -> void:
	check(WallLayout.stilt_span(WallLayout.Stilts.POSTS, 0.6) == 0.0 and WallLayout.stilt_span(WallLayout.Stilts.PILLARS, 0.9) > 0.0, "a 0.6 m raise is too low for stilts; 0.9 m holds them")
	var low := _raised(WallLayout.Stilts.POSTS, false, 0.6)
	var plinth := _raised(WallLayout.Stilts.NONE, false, 0.6)
	check(low.stones.size() == plinth.stones.size() and not low.stones.any(func(st: Dictionary) -> bool: return st.kind in ["post", "beam"]), "raised 0.6 m on posts, it stands on its plinth")
	var none := _raised(WallLayout.Stilts.NONE, false, 1.5)
	check(not none.stones.any(func(st: Dictionary) -> bool: return st.kind in ["post", "beam"] or (st.kind == "pillar")), "a plinth has no stilts")


## On a steep slope the uphill stilts are short, standing on the ground over the foundation's level.
func _stilts_stand_on_the_ground_where_it_rises() -> void:
	var steep := func(x: float, z: float) -> float: return x * 0.25
	var w := _raised(WallLayout.Stilts.POSTS, false, 1.5, steep)
	var posts := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == "post")
	var heights := posts.map(func(st: Dictionary) -> float: return st.size.y)
	check(heights.max() - heights.min() > 0.5, "posts shorten uphill: %.2f to %.2f m" % [heights.min(), heights.max()])
	for st: Dictionary in posts:
		var p: Vector3 = st.xform.origin - Vector3.UP * st.size.y * 0.5
		if p.y < steep.call(p.x, p.z) - 0.1:
			check(false, "a post sinks %.2f m into the ground" % (steep.call(p.x, p.z) - p.y))


## Pillars carry a course of stone running whole round under the foot; posts carry timber beams from each post to the next.
func _pillars_carry_a_course_and_posts_beams() -> void:
	var pillared := _raised(WallLayout.Stilts.PILLARS, false, 1.5)
	var course := 0.0
	for st in pillared.stones:
		if st.kind == "block" and absf(st.y + WallLayout.COURSE * 0.5) < 0.05:
			course += st.size.x
	check(absf(course - pillared.length()) < 0.3, "a course of stone runs round over the pillars: %.1f of %.1f m" % [course, pillared.length()])
	for round in [false, true]:
		var posted := _raised(WallLayout.Stilts.POSTS, round, 1.5)
		var at := posted.stations()
		var beams := posted.stones.filter(func(st: Dictionary) -> bool: return st.kind == "beam")
		check(beams.size() == at.size(), "%s: one beam from each post to the next: %d for %d posts" % [_name(WallLayout.Stilts.POSTS, round), beams.size(), at.size()])
		for i in at.size():
			var a: Vector3 = posted.frame_at(at[i]).point
			var b: Vector3 = posted.frame_at(at[(i + 1) % at.size()]).point
			var mid := (a + b) * 0.5
			var found := beams.any(func(st: Dictionary) -> bool: return Vector2(st.xform.origin.x - mid.x, st.xform.origin.z - mid.z).length() < 0.02 and absf(st.size.x - (Vector2(b.x - a.x, b.z - a.z).length() + WallLayout.POST)) < 0.02)
			check(found, "%s: a beam spans posts %d and %d" % [_name(WallLayout.Stilts.POSTS, round), i, (i + 1) % at.size()])


func _wall_data(kind: WallLayout.Stilts, rise: float, round := false) -> Dictionary:
	var points := WallLayout.circle(Vector3(1, 0, 1), 2.0) if round else WallLayout.rectangle(Vector3.ZERO, Vector3(7, 0, 0), 4.0)
	return {"points": PackedVector3Array(points), "height": 2.4, "rise": rise, "closed": true, "fence": false, "plaster": false, "plinth_plaster": false, "stilts": kind, "planks": false, "lanterns": PackedVector3Array(), "flags": PackedFloat32Array()}


## Stilts are charged as they are laid: pillars and their course as stone wall, posts and beams as timbers, and only the
## foundation under them as plinth.
func _the_budget_counts_stilts_as_laid() -> void:
	for round in [false, true]:
		var plinth := Budget.wall(_wall_data(WallLayout.Stilts.NONE, 1.5, round))
		var pillars := Budget.wall(_wall_data(WallLayout.Stilts.PILLARS, 1.5, round))
		var posts := Budget.wall(_wall_data(WallLayout.Stilts.POSTS, 1.5, round))
		var w := _raised(WallLayout.Stilts.POSTS, round, 1.5, Terrain.flat)
		var n := w.stations().size()
		var length := w.length()
		check(absf(posts.wall_m2 - (plinth.wall_m2 - length * 1.2)) < 0.1, "posts: the plinth's charge falls to its foundation's: %.1f against %.1f" % [posts.wall_m2, plinth.wall_m2])
		check(posts.get("timber", 0) == n * 2 and w.stones.filter(func(st: Dictionary) -> bool: return st.kind in ["post", "beam"]).size() == n * 2, "posts: each post and beam is a timber: %d" % posts.get("timber", 0))
		check(absf(pillars.wall_m2 - (plinth.wall_m2 - length * 1.2 + length * WallLayout.COURSE + n * WallLayout.PILLAR * 0.9)) < 0.1, "pillars: charged as their faces and the course over them: %.1f" % pillars.wall_m2)
		check(Budget.cost_ms(pillars) < Budget.cost_ms(plinth) and Budget.cost_ms(posts) < Budget.cost_ms(plinth), "stilts cost less than the plinth they replace")


## A house's stilts come through the garden's command, which turns them down on an open wall or a fence.
func _the_garden_keeps_stilts() -> void:
	var d := _wall_data(WallLayout.Stilts.POSTS, 1.5)
	d.merge({"seed": 1, "top": WallLayout.Top.CAP, "gable_end": 0, "timber_style": -1, "openings": PackedVector4Array(), "ruins": PackedVector2Array(), "on": PackedInt32Array(), "paint": Palette.plain()})
	var kept: Variant = Commands._wall(d)
	check(kept != null and kept.stilts == WallLayout.Stilts.POSTS, "a house's stilts pass the garden's check")
	var open := d.duplicate()
	open.closed = false
	open.rise = 0.0
	check(Commands._wall(open) == null, "an open wall stands on no stilts")
	var bad := d.duplicate()
	bad.stilts = WallLayout.Stilts.size()
	check(Commands._wall(bad) == null, "an unknown kind of stilts is turned down")
	check("stilts" in Commands.RESHAPES.walls, "a reshape may change a house's stilts")


func _stilts_are_deterministic() -> void:
	for kind in [WallLayout.Stilts.PILLARS, WallLayout.Stilts.POSTS]:
		var a := _raised(kind, true, 2.1)
		var b := _raised(kind, true, 2.1)
		var same := a.stones.size() == b.stones.size()
		for i in mini(a.stones.size(), b.stones.size()):
			same = same and a.stones[i].xform.is_equal_approx(b.stones[i].xform)
		check(same, "%s: the same house lays the same stilts" % WallLayout.Stilts.keys()[kind])
