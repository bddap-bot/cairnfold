extends SceneTree

## Headless checks of builds standing on builds and builds joining: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_build_on.gd

var failures := 0


func _init() -> void:
	_a_wall_top_holds_what_stands_on_it()
	_an_upper_storey_stands_on_the_house_and_takes_its_roof()
	_a_tower_on_a_wall_stands_on_its_top_and_takes_its_merlons()
	_two_houses_joined_are_one_room_under_one_roof()
	_a_wall_into_a_tower_stops_inside_it()
	_builds_meeting_nothing_lay_as_before()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _house(a: Vector3, b: Vector3, depth: float, on: Array[Massing] = []) -> Dictionary:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(a, b, depth)
	w.closed = true
	w.top = WallLayout.Top.CAP
	w.cover = WallLayout.Cover.ROOF
	w.height = 2.4
	w.supports = on
	w.resample(_flat)
	var r := RoofLayout.new()
	r.corners = w.points
	r.pitch = depth * 0.42
	return {"wall": w, "roof": r, "massing": Massing.of(w, r)}


func _lay(h: Dictionary) -> void:
	var w: WallLayout = h.wall
	w.build(_flat)
	h.roof.base = w.samples[0].y + w.height + WallLayout.CAP
	h.roof.build()
	w.hide_roof(h.roof)


func _tower(center: Vector3, radius: float, on: Array[Massing] = []) -> Dictionary:
	var w := WallLayout.new()
	w.points = WallLayout.circle(center, radius)
	w.closed = true
	w.top = WallLayout.Top.CAP
	w.cover = WallLayout.Cover.ROOF
	w.height = 4.5
	w.supports = on
	w.resample(_flat)
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE
	r.center = center
	r.radius = radius
	r.pitch = 2.4
	return {"wall": w, "roof": r, "massing": Massing.of(w, r)}


func _wall(from: Vector3, to: Vector3) -> WallLayout:
	var w := WallLayout.new()
	var pts: Array[Vector3] = []
	for i in 9:
		pts.append(from.lerp(to, i / 8.0))
	w.points = pts
	w.height = 2.7
	w.top = WallLayout.Top.CRENEL
	w.resample(_flat)
	return w


func _a_wall_top_holds_what_stands_on_it() -> void:
	var w := _wall(Vector3(-5, 0, 0), Vector3(5, 0, 0))
	var s := Massing.of(w, null)
	var top := -WallLayout.SINK + w.height + WallLayout.CAP
	_check(is_equal_approx(s.rest(1.0, 0.2), top), "a wall's top holds at %f, not %f" % [s.rest(1.0, 0.2), top])
	_check(is_nan(s.rest(1.0, 1.2)), "a metre off its face is not on it")
	var h := _house(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	_check(is_equal_approx(h.massing.rest(3.0, 0.5), -WallLayout.SINK + 2.4 + WallLayout.CAP), "a house's top holds anywhere over it")
	_check(is_nan(h.massing.rest(3.0, 3.0)), "and nowhere beside it")


func _an_upper_storey_stands_on_the_house_and_takes_its_roof() -> void:
	var lower := _house(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	var upper := _house(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0, [lower.massing])
	var top: float = lower.massing.feet[0] + lower.massing.rise
	_check(absf(upper.wall.samples[0].y - (top - WallLayout.SINK)) < 0.001, "the storey stands on the house's top (%f, top %f)" % [upper.wall.samples[0].y, top])
	lower.wall.resting.assign([upper.massing])
	_lay(lower)
	_lay(upper)
	var above: Array = lower.wall.stones.filter(func(s: Dictionary) -> bool: return s.xform.origin.y > top)
	_check(above.is_empty(), "nothing of the house's own stones pokes up into the storey: %d" % above.size())
	var covered: Array = lower.roof.tiles.filter(func(t: Dictionary) -> bool: return Massing.encloses(Vector2(t.xform.origin.x, t.xform.origin.z), upper.massing.inner))
	_check(covered.is_empty(), "the house's roof is gone under the storey: %d tiles" % covered.size())
	_check(lower.roof.gable_faces.is_empty(), "and its gable ends with it")
	var torching := 0
	for i in range(0, lower.roof.torching_faces.size(), 3):
		if (lower.roof.torching_faces[i] + lower.roof.torching_faces[i + 1] + lower.roof.torching_faces[i + 2]).y / 3.0 > top:
			torching += 1
	_check(torching == 0, "and its torching, but for the eaves' underside: %d faces" % torching)
	_check(upper.roof.tiles.size() > 200, "the storey keeps its roof: %d tiles" % upper.roof.tiles.size())
	_check(upper.wall.stones.size() > 300 and lower.wall.stones.size() > 300, "both storeys keep their walls")


func _a_tower_on_a_wall_stands_on_its_top_and_takes_its_merlons() -> void:
	var w := _wall(Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var ws := Massing.of(w, null)
	var t := _tower(Vector3(0, 0, 0), 1.6, [ws])
	var top: float = ws.feet[0] + ws.rise
	_check(absf(t.wall.samples[0].y - (top - WallLayout.SINK)) < 0.01, "the tower stands on the wall's top")
	var bare := _wall(Vector3(-6, 0, 0), Vector3(6, 0, 0))
	bare.build(_flat)
	w.resting.assign([t.massing])
	w.build(_flat)
	var merlons := func(l: WallLayout, near: bool) -> int:
		return l.stones.filter(func(s: Dictionary) -> bool: return s.kind == "merlon" and (absf(s.xform.origin.x) < 1.2 if near else absf(s.xform.origin.x) > 2.3)).size()
	_check(merlons.call(bare, true) > 0 and merlons.call(w, true) == 0, "no merlons under the tower (%d of %d)" % [merlons.call(w, true), merlons.call(bare, true)])
	_check(merlons.call(w, false) == merlons.call(bare, false), "the rest of the wall keeps them")
	_check(w.stones.filter(func(s: Dictionary) -> bool: return s.kind != "merlon").size() == bare.stones.filter(func(s: Dictionary) -> bool: return s.kind != "merlon").size(), "and every stone below its top")


## A build's stones but its floors', which tests/test_floors.gd checks where joined rooms meet.
func _walls(w: WallLayout) -> Array:
	return w.stones.filter(func(s: Dictionary) -> bool: return not s.kind in WallLayout.FLOOR_KINDS)


func _two_houses_joined_are_one_room_under_one_roof() -> void:
	var a := _house(Vector3(0, 0, 0), Vector3(7, 0, 0), 4.0)
	var b := _house(Vector3(4, 0, -1), Vector3(4, 0, 6), 3.6)
	var lone := _house(Vector3(0, 0, 0), Vector3(7, 0, 0), 4.0)
	_lay(lone)
	a.wall.joined.assign([b.massing])
	b.wall.joined.assign([a.massing])
	_lay(a)
	_lay(b)
	for pair in [[a, b], [b, a]]:
		var inside: Array = _walls(pair[0].wall).filter(func(s: Dictionary) -> bool: return pair[1].massing.holds(s.xform.origin))
		_check(inside.is_empty(), "no wall stands inside the other house: %d stones" % inside.size())
		var tiles: Array = pair[0].roof.tiles.filter(func(t: Dictionary) -> bool: return pair[1].massing.holds(t.xform.origin))
		_check(tiles.is_empty(), "no roof tile lies under the other roof: %d" % tiles.size())
	_check(_walls(a.wall).size() < _walls(lone.wall).size() * 0.9, "the shared stretch of wall is gone (%d of %d)" % [_walls(a.wall).size(), _walls(lone.wall).size()])
	_check(a.wall.stones.size() > lone.wall.stones.size() * 0.5, "the rest stands")
	_check(a.roof.tiles.size() < lone.roof.tiles.size() and a.roof.tiles.size() > lone.roof.tiles.size() * 0.5, "the roofs meet: %d of %d tiles" % [a.roof.tiles.size(), lone.roof.tiles.size()])
	for corner in [Vector2(2.2, 2.0), Vector2(5.8, 2.0)]:
		var low: Array = (a.wall.stones + b.wall.stones).filter(func(s: Dictionary) -> bool: return s.xform.origin.y < 1.5 and Vector2(s.xform.origin.x, s.xform.origin.z).distance_to(corner) < 0.35)
		_check(not low.is_empty(), "where the wing meets the house the walls join with no hole at %s" % corner)


func _a_wall_into_a_tower_stops_inside_it() -> void:
	var t := _tower(Vector3(0, 0, 0), 2.0)
	var w := _wall(Vector3(-8, 0, 0), Vector3(0, 0, 0))
	w.joined.assign([t.massing])
	w.build(_flat)
	var past: Array = w.stones.filter(func(s: Dictionary) -> bool: return s.xform.origin.x > -2.0 + Massing.SLACK + 0.3)
	_check(past.is_empty(), "the wall ends at the tower's centre line: %d stones inside" % past.size())
	var reach: Array = w.stones.filter(func(s: Dictionary) -> bool: return s.xform.origin.x > -2.4)
	_check(not reach.is_empty(), "and runs into its wall, leaving no gap")


func _builds_meeting_nothing_lay_as_before() -> void:
	var a := _house(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	var b := _house(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	b.wall.joined.assign([_house(Vector3(20, 0, 0), Vector3(26, 0, 0), 4.0).massing])
	_lay(a)
	_lay(b)
	_check(a.wall.stones.size() == b.wall.stones.size() and a.roof.tiles.size() == b.roof.tiles.size(), "a far build takes nothing away")
