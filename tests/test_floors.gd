extends SceneTree

## Headless checks of a house's and tower's floors: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_floors.gd

var failures := 0


func _init() -> void:
	_a_house_is_floored_wall_to_wall_over_its_highest_ground()
	_a_raised_house_floors_its_foot()
	_stone_lays_flags_and_plaster_planks()
	_a_round_tower_is_floored_too()
	_storey_floors_rise_a_storey_apart_under_headroom()
	_open_walls_lay_no_floor()
	_a_newer_house_yields_its_floor_to_an_older_one_it_joins()
	_floors_are_stood_on_and_hit()
	_the_meadow_is_worn_bare_inside_the_walls_only()
	_the_budget_counts_storey_floors()
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


func _house(ground: Callable, rise := 0.0, plaster := false, height := 2.4, storeys := false) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.top = WallLayout.Top.CAP
	w.height = height
	w.rise = rise
	w.plaster = plaster
	w.storey_floors = storeys
	w.openings.assign([3.0].map(WallLayout.archway))
	w.build(ground)
	return w


func _pieces(w: WallLayout) -> Array:
	return w.stones.filter(func(s: Dictionary) -> bool: return s.kind in ["flagstone", "plank"])


func _top(s: Dictionary) -> float:
	return s.xform.origin.y + s.xform.basis.y.length() * 0.5


## Whether a piece, grown by its joint, lies over the ground point `p`.
func _over(s: Dictionary, p: Vector2) -> bool:
	var x: Transform3D = s.xform
	var local := x.affine_inverse() * Vector3(p.x, x.origin.y, p.y)
	var grow := Vector3(WallLayout.FLOOR_JOINT, 0.0, WallLayout.FLOOR_JOINT) / x.basis.get_scale()
	return absf(local.x) <= 0.5 + grow.x and absf(local.z) <= 0.5 + grow.z


## The share of grid points inside `w`'s inner faces some piece with its top at `level` lies over.
func _covered(w: WallLayout, level: float) -> float:
	var on := _pieces(w).filter(func(s: Dictionary) -> bool: return absf(_top(s) - level) < 0.02)
	var inside := 0
	var hit := 0
	for j in range(-30, 31):
		for i in range(-10, 71):
			var p := Vector2(i * 0.1, j * 0.1)
			if not Geometry2D.is_point_in_polygon(p, w.floor_outline):
				continue
			inside += 1
			if on.any(func(s: Dictionary) -> bool: return _over(s, p)):
				hit += 1
	return float(hit) / maxi(inside, 1)


func _a_house_is_floored_wall_to_wall_over_its_highest_ground() -> void:
	var w := _house(_slope)
	_check(w.floors.size() == 1, "a house has one floor, got %s" % [w.floors])
	var highest := -INF
	for s in _pieces(w):
		for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
			var q: Vector3 = s.xform * c
			highest = maxf(highest, _slope(q.x, q.z))
	_check(w.floors[0] >= highest - 1e-4, "no ground under the floor, a doorway's included, rises through it: floor %.2f, ground up to %.2f" % [w.floors[0], highest])
	_check(w.floors[0] > w.samples[0].y + WallLayout.SINK, "on a slope the floor stands over the foot, at the uphill ground")
	_check(_covered(w, w.floors[0]) == 1.0, "the floor covers everything inside the walls: %.3f" % _covered(w, w.floors[0]))
	var beds := w.stones.filter(func(s: Dictionary) -> bool: return s.kind == "bed")
	_check(beds.size() == _pieces(w).size() and beds.all(func(s: Dictionary) -> bool: return s.xform.origin.y - s.xform.basis.y.length() * 0.5 <= w.samples[0].y + 1e-3), "the floor's bed reaches down to the walls' foot")
	var flat := _house(_flat)
	_check(is_equal_approx(flat.floors[0], flat.samples[0].y + WallLayout.SINK), "on level ground the floor is the walls' foot")
	_check(_pieces(flat).all(func(s: Dictionary) -> bool: return absf(_top(s) - flat.floors[0]) < 0.01), "every piece's top lies on the floor")


func _a_raised_house_floors_its_foot() -> void:
	for rise in [0.9, 1.5, 3.0]:
		var w := _house(_slope, rise)
		var lowest := INF
		for p in w.points:
			lowest = minf(lowest, _slope(p.x, p.z))
		_check(is_equal_approx(w.floors[0], w.samples[0].y + WallLayout.SINK) and absf(w.floors[0] - (lowest + rise)) < 0.05, "raised %.1f, the floor rides the foot: %.2f over ground %.2f" % [rise, w.floors[0], lowest])
		_check(_covered(w, w.floors[0]) == 1.0, "raised %.1f, the floor still covers the room" % rise)


func _stone_lays_flags_and_plaster_planks() -> void:
	var stone := _pieces(_house(_flat))
	var plaster := _pieces(_house(_flat, 0.0, true))
	_check(not stone.is_empty() and stone.all(func(s: Dictionary) -> bool: return s.kind == "flagstone"), "a stone house is flagged")
	_check(not plaster.is_empty() and plaster.all(func(s: Dictionary) -> bool: return s.kind == "plank"), "a plaster house is boarded")
	_check(plaster.all(func(s: Dictionary) -> bool: return s.xform.basis.z.length() <= WallLayout.PLANK.x + 1e-3 and s.xform.basis.x.length() <= WallLayout.PLANK.w), "planks are narrow boards")
	_check(Palette.code("plank") == Palette.Element.WOOD and Palette.code("flagstone") == Palette.Element.STONE, "planks take the woodwork's paint, flags the stone's")


func _a_round_tower_is_floored_too() -> void:
	for plaster in [false, true]:
		var w := WallLayout.new()
		w.points = WallLayout.circle(Vector3(1, 0, 1), 1.7)
		w.closed = true
		w.cover = WallLayout.Cover.ROOF
		w.height = 4.5
		w.plaster = plaster
		w.build(_slope)
		var on := _pieces(w)
		var inside := 0
		var hit := 0
		for j in range(-20, 21):
			for i in range(-20, 21):
				var p := Vector2(1 + i * 0.1, 1 + j * 0.1)
				if Geometry2D.is_point_in_polygon(p, w.floor_outline):
					inside += 1
					if on.any(func(s: Dictionary) -> bool: return _over(s, p)):
						hit += 1
		_check(inside > 100 and hit == inside, "a %s tower's floor covers its room: %d of %d" % ["plaster" if plaster else "stone", hit, inside])
		var outer := Geometry2D.offset_polygon(PackedVector2Array(w.points.map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z))), WallLayout.THICKNESS * 0.5)[0]
		var out := on.filter(func(s: Dictionary) -> bool:
			var x: Transform3D = s.xform
			for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
				var q: Vector3 = x * c
				if not Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), outer):
					return true
			return false)
		_check(out.is_empty(), "no floor piece pokes out past a tower's outer face: %d" % out.size())


func _storey_floors_rise_a_storey_apart_under_headroom() -> void:
	_check(WallLayout.upper_floors(2.4) == 0 and WallLayout.upper_floors(3.6) == 1 and WallLayout.upper_floors(4.5) == 1 and WallLayout.upper_floors(9.0) == 3, "storeys fit under the top with headroom: %d %d %d %d" % [WallLayout.upper_floors(2.4), WallLayout.upper_floors(3.6), WallLayout.upper_floors(4.5), WallLayout.upper_floors(9.0)])
	var tall := _house(_flat, 0.0, false, 7.2, true)
	_check(tall.floors.size() == 3, "a 7.2 m house floored every storey has three floors: %s" % [tall.floors])
	for i in range(1, tall.floors.size()):
		_check(is_equal_approx(tall.floors[i] - tall.floors[i - 1], WallLayout.STOREY), "floors a storey apart")
		_check(_covered(tall, tall.floors[i]) == 1.0, "an upper floor covers the room")
	_check(_house(_flat, 0.0, false, 7.2, false).floors.size() == 1, "without storey floors, one floor at the foot")
	var sloped := _house(_slope, 0.0, false, 7.8, true)
	_check(sloped.floors.size() == 3 and sloped.floors[0] > sloped.samples[0].y + WallLayout.SINK and is_equal_approx(sloped.floors[1] - sloped.floors[0], WallLayout.STOREY), "up a slope the storeys rise from the raised ground floor: %s" % [sloped.floors])
	var raised := _house(_flat, 1.5, true, 7.2, true)
	_check(raised.floors.size() == 3 and is_equal_approx(raised.floors[1], raised.floors[0] + WallLayout.STOREY), "a raised house's storeys ride its foot")


func _open_walls_lay_no_floor() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.build(_flat)
	_check(w.floors.is_empty() and _pieces(w).is_empty(), "a roofless loop of wall is a wall, not a room")
	var line := WallLayout.new()
	line.points = [Vector3.ZERO, Vector3(6, 0, 0)]
	line.build(_flat)
	_check(line.floors.is_empty() and _pieces(line).is_empty(), "an open wall lays no floor")


func _a_newer_house_yields_its_floor_to_an_older_one_it_joins() -> void:
	var old := _house(_flat)
	var new := WallLayout.new()
	new.points = WallLayout.rectangle(Vector3(4, 0, -1), Vector3(10, 0, -1), 4.0)
	new.closed = true
	new.cover = WallLayout.Cover.ROOF
	new.height = 2.4
	new.build(_flat)
	var room := Massing.of(old, null)
	new.joined.assign([room])
	new.older.assign([room])
	new.build(_flat)
	old.joined.assign([Massing.of(new, null)])
	old.build(_flat)
	_check(_pieces(new).all(func(s: Dictionary) -> bool: return not room.holds(s.xform.origin)), "the newer floor lays nothing in the older room")
	_check(_covered(old, old.floors[0]) == 1.0, "the older floor stays whole")
	var both := 0
	var gap := 0
	for j in range(-25, 16):
		for i in range(40, 61):
			var p := Vector2(i * 0.1, j * 0.1)
			var in_old := Geometry2D.is_point_in_polygon(p, old.floor_outline)
			var in_new := Geometry2D.is_point_in_polygon(p, new.floor_outline)
			if not (in_old or in_new):
				continue
			var hits := _pieces(old).filter(func(s: Dictionary) -> bool: return _over(s, p)).size() + _pieces(new).filter(func(s: Dictionary) -> bool: return _over(s, p)).size()
			if hits == 0:
				gap += 1
	_check(gap == 0, "the joined rooms' floors leave no gap: %d bare points" % gap)


func _floors_are_stood_on_and_hit() -> void:
	var w := _house(_flat, 1.5, false, 7.2, true)
	var mid := Vector3(3, 0, 0)
	_check(is_equal_approx(w.floor_under(mid + Vector3.UP * (w.floors[0] + 1.0)), w.floors[0]), "standing over the ground floor stands on it")
	_check(is_equal_approx(w.floor_under(mid + Vector3.UP * (w.floors[1] + 0.5)), w.floors[1]), "standing over an upper floor stands on that one")
	_check(w.floor_under(mid) == -INF, "under the raised floor stands on nothing of it")
	_check(w.floor_under(Vector3(-2, w.floors[0] + 1.0, 0)) == -INF, "beside the house stands on nothing of it")
	var from := mid + Vector3(0.5, w.floors[0] + 1.6, 0)
	var dir := Vector3(-0.3, -1, 0).normalized()
	var t := w.floor_hit(from, dir)
	_check(t < INF and absf((from + dir * t).y - w.floors[0]) < 0.01, "a ray down from inside meets the floor under it: %.2f" % t)
	_check(w.floor_hit(mid + Vector3.UP * (w.floors[0] + 1.6), Vector3.UP) == INF, "a ray upward meets no floor's top")


func _the_meadow_is_worn_bare_inside_the_walls_only() -> void:
	var points := WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	var stamps := WallLayout.floor_stamps(points)
	var line := PackedVector2Array(points.map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z)))
	var outer := Geometry2D.offset_polygon(line, WallLayout.THICKNESS * 0.5)[0]
	var inner := Geometry2D.offset_polygon(line, -WallLayout.THICKNESS * 0.5)[0]
	var reach := func(s: Vector4) -> float: return s.z + s.w
	_check(Array(stamps).all(func(s: Vector4) -> bool:
		for k in 16:
			var q: Vector2 = Vector2(s.x, s.y) + Vector2.from_angle(TAU * k / 16) * reach.call(s)
			if not Geometry2D.is_point_in_polygon(q, outer):
				return false
		return true), "no stamp wears the meadow outside the walls")
	var bare := 0
	var inside := 0
	for j in range(-15, 16):
		for i in range(0, 61):
			var p := Vector2(i * 0.1, j * 0.1)
			if Geometry2D.is_point_in_polygon(p, inner):
				inside += 1
				if Array(stamps).any(func(s: Vector4) -> bool: return Vector2(s.x, s.y).distance_to(p) <= s.z):
					bare += 1
	_check(inside > 0 and bare == inside, "the meadow is worn bare everywhere under the floor: %d of %d" % [bare, inside])


func _the_budget_counts_storey_floors() -> void:
	var d := {"points": WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0), "closed": true, "height": 7.2, "rise": 0.0, "fence": false, "gable_end": 0,
		"plaster": false, "plinth_plaster": false, "timber_style": 0, "storey_floors": false, "openings": [], "lanterns": [], "flags": [], "roof": {"kind": RoofLayout.Kind.GABLE, "radius": 2.0, "pitch": 2.0, "curve": 0.0, "chimneys": [], "flag": false, "thatch": false}}
	_check(not Budget.wall(d).has("floor_m2"), "a house floored at its foot alone is charged as before")
	d.storey_floors = true
	_check(is_equal_approx(Budget.wall(d).get("floor_m2", 0.0), 2.0 * 24.0), "two storey floors of 24 m² are charged: %s" % [Budget.wall(d)])
