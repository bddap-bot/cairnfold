extends "res://../tests/support/suite.gd"

## Headless checks of a house's and tower's floors: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_floors.gd


func _init() -> void:
	_a_house_is_floored_wall_to_wall_over_its_highest_ground()
	_a_raised_house_floors_its_foot()
	_doors_stand_their_height_over_the_floor()
	_doors_and_arches_stop_at_the_floor()
	_an_arch_is_placed_and_taken_over_a_raised_floor()
	_the_floor_is_flags_or_planks_apart_from_the_walls()
	_a_round_tower_is_floored_too()
	_a_house_has_one_floor_however_tall()
	_open_walls_lay_no_floor()
	_a_newer_house_yields_its_floor_to_an_older_one_it_joins()
	_floors_are_stood_on_and_hit()
	_the_meadow_is_worn_bare_inside_the_walls_only()
	finish()


func _slope(x: float, z: float) -> float:
	return x * 0.1 + z * 0.05


func _house(ground: Callable, rise := 0.0, plaster := false, height := 2.4, planks := false) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.top = WallLayout.Top.CAP
	w.height = height
	w.rise = rise
	w.finish = WallLayout.Finish.TIMBER if plaster else WallLayout.Finish.BARE
	w.planks = planks
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
	check(w.floor_y != -INF, "a house has one floor, got %s" % [w.floor_y])
	var highest := -INF
	for s in _pieces(w):
		for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
			var q: Vector3 = s.xform * c
			highest = maxf(highest, _slope(q.x, q.z))
	check(w.floor_y >= highest - 1e-4, "no ground under the floor, a doorway's included, rises through it: floor %.2f, ground up to %.2f" % [w.floor_y, highest])
	check(w.floor_y > w.samples[0].y + WallLayout.SINK, "on a slope the floor stands over the foot, at the uphill ground")
	check(_covered(w, w.floor_y) == 1.0, "the floor covers everything inside the walls: %.3f" % _covered(w, w.floor_y))
	var beds := w.stones.filter(func(s: Dictionary) -> bool: return s.kind == "bed")
	check(beds.size() == _pieces(w).size() and beds.all(func(s: Dictionary) -> bool: return s.xform.origin.y - s.xform.basis.y.length() * 0.5 <= w.samples[0].y + 1e-3), "the floor's bed reaches down to the walls' foot")
	var flat := _house(Terrain.flat)
	check(is_equal_approx(flat.floor_y, flat.samples[0].y + WallLayout.SINK), "on level ground the floor is the walls' foot")
	check(_pieces(flat).all(func(s: Dictionary) -> bool: return absf(_top(s) - flat.floor_y) < 0.01), "every piece's top lies on the floor")


func _a_raised_house_floors_its_foot() -> void:
	for rise in [0.9, 1.5, 3.0]:
		var w := _house(_slope, rise)
		var lowest := INF
		for p in w.points:
			lowest = minf(lowest, _slope(p.x, p.z))
		check(is_equal_approx(w.floor_y, w.samples[0].y + WallLayout.SINK) and absf(w.floor_y - (lowest + rise)) < 0.05, "raised %.1f, the floor rides the foot: %.2f over ground %.2f" % [rise, w.floor_y, lowest])
		check(_covered(w, w.floor_y) == 1.0, "raised %.1f, the floor still covers the room" % rise)


func _doors_stand_their_height_over_the_floor() -> void:
	for plaster in [false, true]:
		var w := _house(_slope, 0.0, plaster, 4.8)
		var lift := w.floor_y - w.samples[0].y - WallLayout.SINK
		check(lift > 0.3 and is_equal_approx(w.floor_lift(), lift), "up a slope the floor stands %.2f over the foot" % lift)
		check(is_equal_approx(w.spring() - lift, WallLayout.SPRING), "the doorway arch springs its full height over the floor: %.2f" % (w.spring() - lift))
		var door := w.opening_for(Vector4(1.5, 0.0, WallLayout.Family.COTTAGE, 1.0))
		check(door.head - lift >= WallLayout.DOOR_TALL - w.course_height() * 0.5, "a door's head stands its height over the floor: %.2f" % (door.head - lift))
		var pet := w.opening_for(Vector4(1.5, 0.0, WallLayout.Family.ARCHWAY, WallLayout.MIN_SIZE))
		check(w.can_arch(WallLayout.MIN_SIZE) and pet.head - lift < 1.2, "a pet door still opens small over the floor: %.2f" % (pet.head - lift))
		check(not w.stones.any(func(st: Dictionary) -> bool: return st.kind in ["block", "plaster"] and absf(st.s - 3.0) < WallLayout.ARCH_HALF - 0.1 and st.y > lift and st.y < w.spring()), "nothing of the wall stands in the doorway over the floor")


## A doorway, arched or planked, opens from the floor: under it the wall stands whole down to the foundation's foot, on a
## slope, raised on a plinth, in stone, plaster or timber framing, so nothing under the floor shows through it.
func _doors_and_arches_stop_at_the_floor() -> void:
	for ground in [Terrain.flat, _slope]:
		for rise in [0.0, 1.2]:
			for finish in ["stone", "plaster", "timber"]:
				for style in [WallLayout.Family.ARCHWAY, WallLayout.Family.COTTAGE]:
					var w := _house(Terrain.flat, rise, finish != "stone", 3.0)
					w.finish = {"stone": WallLayout.Finish.BARE, "plaster": WallLayout.Finish.PLASTER, "timber": WallLayout.Finish.TIMBER}[finish]
					w.openings.assign([Vector4(3.0, 0.0, style, 1.0)])
					w.build(ground)
					var name := "%s %s %s, raised %.1f" % ["arch" if style == WallLayout.Family.ARCHWAY else "door", finish, "up a slope" if ground == _slope else "on the flat", rise]
					var t := w.threshold()
					check(w.apertures.size() == 1 and is_equal_approx(w.apertures[0].sill, t), "%s: it opens from the floor at %.2f: %s" % [name, t, w.apertures])
					var low := w.stones.filter(func(st: Dictionary) -> bool: return (st.kind in ["door", "iron"] or st.kind == "timber" and absf(absf(st.s - 3.0) - WallLayout.ARCH_HALF - TimberFrame.WIDTH * 0.5) < 0.01) and st.y - st.size.y * 0.5 < t - 0.01)
					check(low.is_empty(), "%s: nothing of it reaches under the floor: %s" % [name, low.map(func(st: Dictionary) -> String: return "%s at %.2f" % [st.kind, st.y])])
					var walls := w.stones.filter(func(st: Dictionary) -> bool: return not st.kind in WallLayout.FLOOR_KINDS)
					var open := []
					var y := -w.plinth_at(3.0) + 0.05
					while y < t - w.course_height():
						for d in [-0.4, 0.0, 0.4]:
							var p: Vector3 = w.frame_at(3.0 + d).point + Vector3.UP * y
							if not walls.any(func(st: Dictionary) -> bool: return _holds(st, p)):
								open.append(Vector2(d, y))
						y += 0.1
					check(open.is_empty(), "%s: the wall stands whole under the floor, not at %s" % [name, open.slice(0, 6)])


## A press with the arch tool on a house whose floor stands over its foot cuts an arch, and a press on that arch finds it
## to fill it again.
func _an_arch_is_placed_and_taken_over_a_raised_floor() -> void:
	for plaster in [false, true]:
		var w := _house(_slope, 0.0, plaster, 4.8)
		var placed: Array[Vector4] = []
		placed.assign(w.openings)
		check(w.threshold() > 0.3 and w.opening_fits(WallLayout.archway(13.0), placed), "an arch fits over a floor %.2f up" % w.threshold())
		check(w.placed_at(WallLayout.archway(3.2), placed) == 0, "a press on the arch over a floor %.2f up finds it" % w.threshold())


## Whether `p` lies in laid piece `st` as it is drawn, its ends cut as WallLayout.drawn_corners cuts them.
func _holds(st: Dictionary, p: Vector3) -> bool:
	var x: Transform3D = st.xform
	var q := x.affine_inverse() * p
	var e: Vector2 = st.get("ends", Vector2.ZERO)
	var axis := x.basis.y.normalized()
	q.x -= q.z * x.basis.z.length() * tan(e.x if q.x < 0.0 else e.y) / (x.basis.x - axis * x.basis.x.dot(axis)).length()
	return absf(q.x) <= 0.5 and absf(q.y) <= 0.5 and absf(q.z) <= 0.5


## Either face takes either floor, and the floor changes nothing of the walls. Planks lay about as many pieces as flags,
## so the budget's wall rates, measured over both, price either.
func _the_floor_is_flags_or_planks_apart_from_the_walls() -> void:
	for plaster in [false, true]:
		var flagged := _house(Terrain.flat, 0.0, plaster)
		var boarded := _house(Terrain.flat, 0.0, plaster, 2.4, true)
		var flags := _pieces(flagged)
		var planks := _pieces(boarded)
		check(not flags.is_empty() and flags.all(func(s: Dictionary) -> bool: return s.kind == "flagstone"), "plaster %s: flags unless planked" % plaster)
		check(not planks.is_empty() and planks.all(func(s: Dictionary) -> bool: return s.kind == "plank"), "plaster %s: boarded when planked" % plaster)
		check(planks.all(func(s: Dictionary) -> bool: return s.xform.basis.z.length() <= WallLayout.PLANK.x + 1e-3 and s.xform.basis.x.length() <= WallLayout.PLANK.w), "planks are narrow boards")
		var walls := func(w: WallLayout) -> Array: return w.stones.filter(func(s: Dictionary) -> bool: return not s.kind in WallLayout.FLOOR_KINDS)
		check(walls.call(flagged) == walls.call(boarded), "plaster %s: the floor leaves the walls as they were" % plaster)
		check(absf(planks.size() - flags.size()) <= flags.size() * 0.25, "plaster %s: planks lay about as many pieces as flags (%d, %d)" % [plaster, planks.size(), flags.size()])
	check(Palette.code("plank") == Palette.Element.WOOD and Palette.code("flagstone") == Palette.Element.STONE, "planks take the woodwork's paint, flags the stone's")


func _a_round_tower_is_floored_too() -> void:
	for planks in [false, true]:
		var w := WallLayout.new()
		w.points = WallLayout.circle(Vector3(1, 0, 1), 1.7)
		w.closed = true
		w.cover = WallLayout.Cover.ROOF
		w.height = 4.5
		w.planks = planks
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
		check(inside > 100 and hit == inside, "a %s tower's floor covers its room: %d of %d" % ["planked" if planks else "flagged", hit, inside])
		var outer := Geometry2D.offset_polygon(PackedVector2Array(w.points.map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z))), WallLayout.THICKNESS * 0.5)[0]
		var out := on.filter(func(s: Dictionary) -> bool:
			var x: Transform3D = s.xform
			for c in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
				var q: Vector3 = x * c
				if not Geometry2D.is_point_in_polygon(Vector2(q.x, q.z), outer):
					return true
			return false)
		check(out.is_empty(), "no floor piece pokes out past a tower's outer face: %d" % out.size())


func _a_house_has_one_floor_however_tall() -> void:
	for h in [2.4, 7.2, 12.0]:
		check(_house(Terrain.flat, 0.0, false, h).floor_y != -INF, "a %.1f m house lays one floor, at its foot" % h)
	check(_house(Terrain.flat, 1.5, true, 7.2).floor_y != -INF, "a raised plastered house lays one floor")
	var d := wall_data({"points": PackedVector3Array(WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)), "height": 7.2, "seed": 3, "closed": true, "storey_floors": true})
	var kept: Variant = Commands._wall(d)
	check(kept != null and not kept.has("storey_floors"), "a house asking for a floor at every storey is taken with that dropped: %s" % [kept])
	var state := {"walls": {1: kept}}
	check(not Commands.clean({"op": "reshape", "of": "walls", "id": 1, "data": {"height": 3.0}}, state, false, Terrain.new()).is_empty(), "a reshape of the house's height stands")
	check(Commands.clean({"op": "reshape", "of": "walls", "id": 1, "data": {"storey_floors": true}}, state, false, Terrain.new()).is_empty(), "no reshape gives a floor a second storey")


func _open_walls_lay_no_floor() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.build(Terrain.flat)
	check(w.floor_y == -INF and _pieces(w).is_empty(), "a roofless loop of wall is a wall, not a room")
	var line := WallLayout.new()
	line.points = [Vector3.ZERO, Vector3(6, 0, 0)]
	line.build(Terrain.flat)
	check(line.floor_y == -INF and _pieces(line).is_empty(), "an open wall lays no floor")


## Joined across the side its rows start from, past its end, and corner to corner, on level and sloping ground.
func _a_newer_house_yields_its_floor_to_an_older_one_it_joins() -> void:
	for ground in [Terrain.flat, _slope]:
		for at in [Vector3(4, 0, -1), Vector3(0, 0, 3.7), Vector3(2, 0, 3.7), Vector3(4.3, 0, 2.6)]:
			var old := _house(ground)
			var new := WallLayout.new()
			new.points = WallLayout.rectangle(at, at + Vector3(6, 0, 0), 4.0)
			new.closed = true
			new.cover = WallLayout.Cover.ROOF
			new.height = 2.4
			new.build(ground)
			var room := Massing.of(old, null)
			new.joined.assign([room])
			new.older.assign([room])
			new.build(ground)
			old.joined.assign([Massing.of(new, null)])
			old.build(ground)
			check(_pieces(new).all(func(s: Dictionary) -> bool: return not room.holds(s.xform.origin)), "the newer floor lays nothing in the older room")
			check(_covered(old, old.floor_y) == 1.0, "the older floor stays whole")
			var pieces := _pieces(old) + _pieces(new)
			var gap := 0
			for j in range(-110, 311):
				for i in range(-10, 511):
					var p := Vector2(i * 0.02, j * 0.02)
					if (Geometry2D.is_point_in_polygon(p, old.floor_outline) or Geometry2D.is_point_in_polygon(p, new.floor_outline)) and not pieces.any(func(s: Dictionary) -> bool: return _over(s, p)):
						gap += 1
			check(gap == 0, "joined at %s, the rooms' floors leave no gap: %d bare points" % [at, gap])


func _floors_are_stood_on_and_hit() -> void:
	var w := _house(Terrain.flat, 1.5, false, 7.2)
	var mid := Vector3(3, 0, 0)
	check(is_equal_approx(w.floor_under(mid + Vector3.UP * (w.floor_y + 1.0)), w.floor_y), "standing over the ground floor stands on it")
	check(is_equal_approx(w.floor_under(mid + Vector3.UP * (w.floor_y + 4.0)), w.floor_y), "standing high in a tall house still stands on its one floor")
	check(w.floor_under(mid) == -INF, "under the raised floor stands on nothing of it")
	check(w.floor_under(Vector3(-2, w.floor_y + 1.0, 0)) == -INF, "beside the house stands on nothing of it")
	var from := mid + Vector3(0.5, w.floor_y + 1.6, 0)
	var dir := Vector3(-0.3, -1, 0).normalized()
	var t := w.floor_hit(from, dir)
	check(t < INF and absf((from + dir * t).y - w.floor_y) < 0.01, "a ray down from inside meets the floor under it: %.2f" % t)
	check(w.floor_hit(mid + Vector3.UP * (w.floor_y + 1.6), Vector3.UP) == INF, "a ray upward meets no floor's top")


func _the_meadow_is_worn_bare_inside_the_walls_only() -> void:
	var points := WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	var stamps := WallLayout.floor_stamps(points)
	var line := PackedVector2Array(points.map(func(p: Vector3) -> Vector2: return Vector2(p.x, p.z)))
	var outer := Geometry2D.offset_polygon(line, WallLayout.THICKNESS * 0.5)[0]
	var inner := Geometry2D.offset_polygon(line, -WallLayout.THICKNESS * 0.5)[0]
	var reach := func(s: Vector4) -> float: return s.z + s.w
	check(Array(stamps).all(func(s: Vector4) -> bool:
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
	check(inside > 0 and bare == inside, "the meadow is worn bare everywhere under the floor: %d of %d" % [bare, inside])
