extends "res://../tests/support/suite.gd"

## Headless checks of the window families (arched, arrow slit, round, corner), roof trapdoors, the night glow and its
## colour, and the curtains, flower boxes and washing of lived-in houses, as layouts and through the tools:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_windows.gd

const RINGED: Array[WallLayout.Family] = [WallLayout.Family.ARCHED, WallLayout.Family.ROUND]


func _initialize() -> void:
	for family in [WallLayout.Family.ARCHED, WallLayout.Family.SLIT, WallLayout.Family.ROUND]:
		_a_family_cuts_its_shape(family)
		_a_family_fuses(family)
	_families_never_fuse_with_each_other()
	_low_on_the_wall()
	_a_course_below_a_ringed_sill_stays_whole()
	_a_corner_window_wraps_its_corner()
	_corner_windows_keep_to_corners()
	_room_glass_glows_in_its_colour()
	_lived_in_houses_dress_their_windows()
	_a_trapdoor_lies_in_a_flat_roof()
	_commands_carry_families_and_trapdoors()
	_the_budget_counts_rings_dressing_and_trapdoors()
	_windows_glow_after_sunset()
	_the_demos_show_them()
	boot_main()
	_in_the_glade.call_deferred()


static func _wall(family: int, at: Array[float], height := 2.7, y := -1.0) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(8, 0, 0)]
	w.height = height
	w.seed = 3
	w.openings.assign(at.map(func(s: float) -> Vector4: return Vector4(s, WallLayout.lowest(family) + 0.15 if y < 0.0 else y, family, 1.0)))
	w.build(Terrain.flat)
	return w


static func _house(openings: Array[Vector4], finish := WallLayout.Finish.BARE) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.top = WallLayout.Top.CAP
	w.height = 2.4
	w.seed = 5
	w.finish = finish
	w.openings.assign(openings)
	w.build(Terrain.flat)
	return w


static func _kind(w: WallLayout, kind: String) -> Array:
	return w.stones.filter(func(s): return s.kind == kind)


## Coursed stones whose face covers some of a light of `o` at their own height.
static func _intruders(w: WallLayout, o: Dictionary) -> Array:
	return w.stones.filter(func(s):
		# A ringed light's infill wedges turn round it; their boxes' level extents say nothing of where they lie.
		if s.kind != "block" and s.kind != "mortar" or s.has("ends"):
			return false
		for c in WallLayout.light_centres(o):
			for dy in [-0.4, 0.0, 0.4]:
				var y: float = s.y + s.size.y * dy
				var half := WallLayout.light_half(o, y)
				if half > 0.12 and absf(w.offset(s.s, c)) < half + s.size.x * 0.5 - 0.03:
					return true
		return false)


func _a_family_cuts_its_shape(family: WallLayout.Family) -> void:
	var name: String = WallLayout.Family.find_key(family)
	var w := _wall(family, [4.0])
	check(w.apertures.size() == 1 and w.apertures[0].style == family and not w.apertures[0].door, "%s: one window opens: %s" % [name, w.apertures])
	if w.apertures.is_empty():
		return
	var o := w.apertures[0]
	check(_intruders(w, o).is_empty(), "%s: no coursed stone stands in the light: %s" % [name, _intruders(w, o).map(func(s): return [s.kind, s.s, s.y, s.size])])
	check(not _kind(w, "glass").is_empty(), "%s: the light is glazed" % name)
	var glass: Array = _kind(w, "glass")
	check(glass.all(func(g) -> bool: return absf(g.s - 4.0) < o.half and g.y > o.sill and g.y < o.head), "%s: its glass stands inside the opening" % name)
	match family:
		WallLayout.Family.ARCHED, WallLayout.Family.ROUND:
			var wedges := _kind(w, "voussoir")
			check(wedges.size() == (10 if family == WallLayout.Family.ROUND else 6), "%s: a ring of wedges, %d" % [name, wedges.size()])
			var middle: float = (o.sill + o.head) * 0.5 if family == WallLayout.Family.ROUND else o.head - o.pane
			var round := wedges.all(func(v) -> bool: return absf(Vector2(v.s - 4.0, v.y - middle).length() - (o.pane + o.ring * 0.5)) < 0.03)
			check(round, "%s: every wedge stands round the light's head, %.2f out" % [name, o.pane + o.ring * 0.5])
			check(wedges.all(func(v) -> bool: return v.size.y > WallLayout.THICKNESS), "%s: the ring stands proud of both faces" % name)
			check(_kind(w, "lintel").is_empty(), "%s: a ring, not a lintel, heads it" % name)
			check(_kind(w, "sill").size() == (0 if family == WallLayout.Family.ROUND else 1), "%s: an arched window sits on a sill, a round one on none" % name)
			var infill := w.stones.filter(func(s) -> bool: return s.kind == "mortar" and s.has("ends") and Vector2(s.s - 4.0, s.y - middle).length() < o.pane + o.ring + w.course_height() + 0.05)
			check(not infill.is_empty(), "%s: infill closes the courses' level cut behind the ring" % name)
		WallLayout.Family.SLIT:
			check(o.half < 0.1 and o.head - o.sill > 1.19, "a slit is tall and narrow: %s" % o)
			check(_kind(w, "lintel").size() > 4 and _kind(w, "sill").size() == 1, "a slit stands between dressed jambs under a lintel, on a sill")
			check(glass.size() == 1 and absf(glass[0].xform.origin.z) > WallLayout.THICKNESS * 0.25 or w.inner_side() == 0.0, "a slit's glass lies deep in it")


func _a_family_fuses(family: WallLayout.Family) -> void:
	var name: String = WallLayout.Family.find_key(family)
	var w := _wall(family, [3.6, 4.4])
	check(w.apertures.size() == 1 and w.apertures[0].lights == 2 and w.apertures[0].style == family, "%s: two side by side fuse into one opening of two lights: %s" % [name, w.apertures])
	if w.apertures.size() != 1:
		return
	var o := w.apertures[0]
	var c := WallLayout.light_centres(o)
	check(absf(o.s - 4.0) < 0.01 and is_equal_approx(c[1] - c[0], o.pane * 2.0 + o.mullion), "%s: the lights stand a light and a mullion apart about the middle" % name)
	check(_intruders(w, o).is_empty(), "%s: neither fused light is filled" % name)
	if family in RINGED:
		check(_kind(w, "voussoir").size() == 2 * (10 if family == WallLayout.Family.ROUND else 6), "%s: each fused light wears its own ring" % name)
		check(c[1] - c[0] - o.pane * 2.0 > o.ring * 2.0, "%s: neighbouring rings stay apart" % name)
	var apart := _wall(family, [2.0, 6.0])
	check(apart.apertures.size() == 2, "%s: far apart they stay two" % name)


func _families_never_fuse_with_each_other() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(10, 0, 0)]
	w.height = 2.7
	w.openings.assign([Vector4(4.0, 1.35, WallLayout.Family.COTTAGE, 1.0), Vector4(5.0, 1.35, WallLayout.Family.ARCHED, 1.0)])
	w.build(Terrain.flat)
	check(w.apertures.all(func(o) -> bool: return o.lights == 1), "a cottage and an arched window side by side never fuse: %s" % [w.apertures])


func _low_on_the_wall() -> void:
	var arched := _wall(WallLayout.Family.ARCHED, [4.0], 2.7, 0.3)
	check(arched.apertures.size() == 1 and arched.apertures[0].door, "an arched window low on a wall opens as a round-headed door")
	if not arched.apertures.is_empty():
		var o := arched.apertures[0]
		var middle: float = o.head - o.pane
		var planks := _kind(arched, "door")
		check(planks.size() >= 3 and planks.all(func(p) -> bool: return p.y + p.size.y * 0.5 <= middle + sqrt(maxf(o.pane * o.pane - pow(maxf(absf(p.s - o.s) - p.size.x * 0.5 - 0.01, 0.0), 2.0), 0.0)) + 0.01), "its planks reach up into the round head and stop at it")
		check(planks.any(func(p) -> bool: return p.y + p.size.y * 0.5 > middle + o.pane * 0.8), "the middle planks reach the crown")
	for family in [WallLayout.Family.SLIT, WallLayout.Family.ROUND]:
		var w := _wall(family, [4.0], 2.7, 0.3)
		check(w.apertures.size() == 1 and not w.apertures[0].door and w.apertures[0].sill >= WallLayout.DOOR_SILL - 0.01, "%s low on a wall stays a window, its sill at a door's" % WallLayout.Family.find_key(family))
	check(not WallLayout.opens_door(Vector4(4.0, 0.3, WallLayout.Family.SLIT, 1.0)) and WallLayout.opens_door(Vector4(4.0, 0.3, WallLayout.Family.ARCHED, 1.0)), "opens_door names the families that open doors")


func _a_course_below_a_ringed_sill_stays_whole() -> void:
	for family in RINGED:
		var w := _wall(family, [4.0])
		var o := w.apertures[0]
		var c := w.course_height()
		check(WallLayout.light_cuts(o, o.sill - c, c).is_empty(), "%s: the course under its sill is not cut" % WallLayout.Family.find_key(family))
		check(not WallLayout.light_cuts(o, o.sill, c).is_empty(), "%s: the course above its sill is" % WallLayout.Family.find_key(family))


func _a_corner_window_wraps_its_corner() -> void:
	var w := _house([Vector4(6.2, 1.2, WallLayout.Family.CORNER, 1.0)])
	check(w.apertures.size() == 1 and w.apertures[0].style == WallLayout.Family.CORNER, "a corner window opens at a house's corner: %s" % [w.apertures])
	if w.apertures.is_empty():
		return
	var o := w.apertures[0]
	check(is_equal_approx(o.s, 6.0), "it snaps onto the corner: %.3f" % o.s)
	var filled := w.stones.filter(func(s) -> bool: return s.kind in ["block", "mortar", "pier"] and absf(w.offset(s.s, 6.0)) < o.half - 0.05 and s.y > o.sill + 0.05 and s.y < o.head - 0.05)
	check(filled.is_empty(), "no stone, pier or course, fills it on either face: %s" % [filled.map(func(s): return [s.kind, s.s, s.y])])
	var glass := _kind(w, "glass")
	check(glass.any(func(g) -> bool: return g.s < 6.0) and glass.any(func(g) -> bool: return g.s > 6.0), "a light on each face")
	var piers := _kind(w, "pier").filter(func(s) -> bool: return absf(s.s - 6.0) < 0.01)
	check(piers.any(func(s) -> bool: return s.y < o.sill) and piers.any(func(s) -> bool: return s.y > o.head), "the corner's pier stands under and over it")
	check(_kind(w, "lintel").size() == 2 and _kind(w, "sill").size() == 2 and _kind(w, "mullion").size() == 1, "a lintel and a sill on each face and a post at the corner")
	var beside := _house([Vector4(6.0, 1.2, WallLayout.Family.CORNER, 1.0), Vector4(7.6, 1.35, WallLayout.Family.CORNER, 1.0), Vector4(4.3, 1.2, WallLayout.Family.COTTAGE, 1.0)])
	check(beside.apertures.size() == 2 and beside.apertures.all(func(a) -> bool: return a.lights == 1), "a window beside a corner window keeps apart, and a second at the same corner does not open: %s" % [beside.apertures])


func _corner_windows_keep_to_corners() -> void:
	check(_house([Vector4(3.0, 1.2, WallLayout.Family.CORNER, 1.0)]).apertures.is_empty(), "a corner window away from a corner does not open")
	check(_house([Vector4(6.0, 1.2, WallLayout.Family.CORNER, 1.0)], WallLayout.Finish.TIMBER).apertures.is_empty(), "nor where a timber frame's corner post stands")
	var straight := _wall(WallLayout.Family.CORNER, [4.0])
	check(straight.apertures.is_empty(), "nor in a straight wall")
	var end := _wall(WallLayout.Family.CORNER, [0.1])
	check(end.apertures.is_empty(), "nor at an open wall's end")
	var w := _house([])
	check(is_equal_approx(w.corner_near(6.3), 6.0) and is_nan(w.corner_near(3.0)), "a point on a corner's pier is near that corner, one mid-face none")


func _room_glass_glows_in_its_colour() -> void:
	var house := _house([Vector4(3.0, 1.35, WallLayout.Family.COTTAGE, 1.0)])
	var warm: Color = Palette.SWATCHES[Palette.Element.GLOW][0]
	check(_kind(house, "glass").all(func(g) -> bool: return absf(g.color.r / warm.r - g.color.g / warm.g) < 0.01 and g.color.r > warm.r * 0.85), "a room's glass carries the glow's first swatch")
	var wall := _wall(WallLayout.Family.COTTAGE, [4.0])
	check(_kind(wall, "glass").all(func(g) -> bool: return g.color.r == 0.0 and g.color.g == 0.0), "a wall standing open glows nothing")
	check(Palette.code("glass") == Palette.Element.GLOW and Palette.count(Palette.Element.GLOW) >= 6, "glass is painted by the glow's swatches")
	check(Stones.glazed({"kind": "glass"}, Color.WHITE).a == 0.0 and Stones.glazed({"kind": "block"}, Color.WHITE).a == 1.0, "only glass is glazed")
	var paint := Palette.plain()
	paint[Palette.Element.GLOW] = 6
	var t := Palette.tint(Palette.Element.GLOW, 6)
	var blue: Color = Palette.SWATCHES[Palette.Element.GLOW][6]
	check(absf(warm.b * t.b - blue.b) < 0.001 and Palette.valid(paint), "a pick tints the glass onto its swatch")


func _lived_in_houses_dress_their_windows() -> void:
	var dressed := _house([Vector4(3.0, 0.0, WallLayout.Family.COTTAGE, 1.0), Vector4(1.2, 1.35, WallLayout.Family.COTTAGE, 1.0), Vector4(4.8, 1.35, WallLayout.Family.ARCHED, 1.0), Vector4(9.0, 1.35, WallLayout.Family.COTTAGE, 1.0), Vector4(12.8, 1.35, WallLayout.Family.COTTAGE, 1.0), Vector4(15.0, 1.35, WallLayout.Family.ROUND, 1.0)])
	check(dressed.lived_in(), "a roofed house with a door is lived in")
	var windows := dressed.apertures.filter(func(o) -> bool: return not o.door and o.style in [WallLayout.Family.COTTAGE, WallLayout.Family.ARCHED])
	check(windows.size() == 4, "four of its windows take dressing: %d" % windows.size())
	check(_kind(dressed, "curtain").size() == windows.size() * 3, "curtains drawn either side of every cottage and arched light, under a pelmet: %d" % _kind(dressed, "curtain").size())
	var out := -dressed.inner_side()
	var faces_out := _kind(dressed, "planter").all(func(p) -> bool: return (p.xform.origin - dressed.frame_at(p.s).point).dot(dressed.frame_at(p.s).tangent.cross(Vector3.UP) * out) > WallLayout.THICKNESS * 0.5)
	check(not _kind(dressed, "planter").is_empty() and faces_out, "flower boxes hang on the face looking out")
	check(not _kind(dressed, "bloom").is_empty() and not _kind(dressed, "leaf").is_empty(), "the boxes are full of flowers")
	check(dressed.cloths.size() >= 2 and _kind(dressed, "rope").size() == 2, "washing hangs on one line: %d pieces" % dressed.cloths.size())
	check(dressed.cloths.all(func(c) -> bool: return c.xform.origin.y > 1.5), "the washing hangs well clear of the ground")
	var empty := _house([Vector4(1.2, 1.35, WallLayout.Family.COTTAGE, 1.0)])
	check(not empty.lived_in() and _kind(empty, "curtain").is_empty() and empty.cloths.is_empty(), "a house with no door stands empty")
	var upper := _house([Vector4(1.2, 1.35, WallLayout.Family.COTTAGE, 1.0)])
	upper.supports.assign([Massing.of(_house([]), null)])
	upper.build(Terrain.flat)
	check(upper.lived_in() and not _kind(upper, "curtain").is_empty(), "a room standing on another is lived in, reached from below")
	var open := _wall(WallLayout.Family.COTTAGE, [2.0, 6.0], 2.7)
	open.openings.append(Vector4(4.0, 0.0, WallLayout.Family.COTTAGE, 1.0))
	open.build(Terrain.flat)
	check(not open.lived_in() and _kind(open, "curtain").is_empty(), "a wall with a door is no home")
	var again := _house(dressed.openings)
	check(again.stones.size() == dressed.stones.size() and again.cloths.size() == dressed.cloths.size(), "the dressing is laid alike every time")


func _a_trapdoor_lies_in_a_flat_roof() -> void:
	var r := RoofLayout.new()
	r.corners = [Vector3(-3, 0, -2), Vector3(3, 0, -2), Vector3(3, 0, 2), Vector3(-3, 0, 2)]
	r.pitch = 0.0
	r.hatches = [Vector2(0.5, 0.2)]
	r.build()
	var lid := r.tiles.filter(func(t) -> bool: return t.kind == "hatch")
	check(lid.size() == 8 and r.tiles.any(func(t) -> bool: return t.kind == "iron"), "a trapdoor: a curb, a lid of boards, hinges and a ring: %d" % lid.size())
	var top: float = r.frame().mid.y - RoofLayout.DECK_DROP
	check(lid.all(func(t) -> bool: return t.xform.origin.y > top - 0.01 and t.xform.origin.y < top + 0.12), "it lies on the deck")
	var spot := r.hatch_spot(Vector2(9, 9))
	check(not is_nan(spot.x) and absf(spot.x) < 3.0 - RoofLayout.HATCH * 0.5 and absf(spot.y) < 2.0 - RoofLayout.HATCH * 0.5, "pointed past the walls, it keeps inside them: %s" % [spot])
	check(r.hatch_fits(Vector2(-1.5, 0.0), r.hatches) and not r.hatch_fits(Vector2(0.9, 0.3), r.hatches), "two trapdoors keep apart")
	r.chimneys = [Vector2(-1.5, 0.0)]
	check(not r.hatch_fits(Vector2(-1.5, 0.0), []), "and clear of a chimney")
	r.chimneys = []
	r.pitch = 2.0
	r.build()
	check(r.tiles.all(func(t) -> bool: return t.kind != "hatch") and is_nan(r.hatch_spot(Vector2.ZERO).x), "a pitched roof keeps no trapdoor")
	var tower := RoofLayout.new()
	tower.kind = RoofLayout.Kind.CONE
	tower.radius = 2.0
	tower.pitch = 0.0
	tower.hatches = [Vector2(5, 0)]
	tower.build()
	tower.flag = true
	check(not tower.hatch_fits(Vector2.ZERO, []) and tower.hatch_fits(Vector2(1.0, 0.0), []), "a flagged tower keeps its trapdoor off the pole")
	tower.flag = false
	check(tower.tiles.any(func(t) -> bool: return t.kind == "hatch") and tower.hatch_spot(Vector2(5, 0)).length() < 2.0 - WallLayout.THICKNESS * 0.5, "a tower's flat roof takes one inside its ring")


func _commands_carry_families_and_trapdoors() -> void:
	var d := wall_data({"points": PackedVector3Array(WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)), "closed": true, "seed": 2})
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 0.0, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array([Vector2(0.5, 0.0)]), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	d.openings = PackedVector4Array([Vector4(6.0, 1.2, WallLayout.Family.CORNER, 1.0), Vector4(2.0, 1.35, WallLayout.Family.ROUND, 1.0)])
	var ok: Variant = Commands._wall(d)
	check(ok != null and ok.roof.hatches.size() == 1, "a house with a corner window, a round one and a trapdoor is a build")
	for bad in [Vector4(2.0, 1.35, WallLayout.Family.size(), 1.0), Vector4(2.0, 1.35, 2.5, 1.0), Vector4(2.0, 1.35, -1.0, 1.0)]:
		var b := d.duplicate(true)
		b.openings = PackedVector4Array([bad])
		check(Commands._wall(b) == null, "an opening of no family is refused: %s" % [bad])
	var many := d.duplicate(true)
	many.roof.hatches = PackedVector2Array()
	for i in Commands.MAX_HATCHES + 1:
		many.roof.hatches.append(Vector2(i, 0))
	check(Commands._wall(many) == null, "no more than MAX_HATCHES trapdoors")
	var none := d.duplicate(true)
	none.roof.erase("hatches")
	check(Commands._wall(none) == null, "a roof states its trapdoors")
	var change: Variant = Commands._reshape("walls", {"roof": {"hatches": PackedVector2Array()}}, ok)
	check(change != null, "a reshape takes the trapdoors away")


func _the_budget_counts_rings_dressing_and_trapdoors() -> void:
	var d := wall_data({"points": PackedVector3Array(WallLayout.rectangle(Vector3.ZERO, Vector3(6, 0, 0), 4.0)), "closed": true, "seed": 2})
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": 0.0, "curve": 0.0, "seed": 1, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	d.openings = PackedVector4Array([Vector4(2.0, 1.35, WallLayout.Family.COTTAGE, 1.0)])
	var bare: int = Budget.wall(d).get("fitting", 0)
	d.openings = PackedVector4Array([Vector4(2.0, 1.35, WallLayout.Family.ROUND, 1.0)])
	check(Budget.wall(d).get("fitting", 0) == bare + 1, "a round window's ring counts as a fitting")
	d.openings = PackedVector4Array([Vector4(2.0, 1.35, WallLayout.Family.COTTAGE, 1.0), Vector4(3.0, 0.0, WallLayout.Family.COTTAGE, 1.0)])
	check(Budget.wall(d).get("fitting", 0) == bare + 2, "a lived-in house's window counts its dressing, and the house its washing")
	d.roof.hatches = PackedVector2Array([Vector2.ZERO])
	check(Budget.wall(d).get("fitting", 0) == bare + 3, "a trapdoor counts as a fitting")


func _windows_glow_after_sunset() -> void:
	check(Daylight.lit(0.5) == 0.0 and Daylight.lit(Daylight.DEFAULT) == 0.0, "no glow by day")
	check(Daylight.lit(0.0) == 1.0 and Daylight.lit(0.86) == 1.0, "full glow at night")
	var dusk := Daylight.lit(0.76)
	check(dusk > 0.0 and dusk < 1.0 or Daylight.elevation(0.76) < Daylight.LIT.y or Daylight.elevation(0.76) > Daylight.LIT.x, "windows come on through the sunset")


## demo/windows.json shows every family by day and by night, and the stress scene's windows/* phases look over a
## village whose every house opens windows of a family, lit by night.
func _the_demos_show_them() -> void:
	var demo: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../demo/windows.json"))
	var families := demo.filter(func(s: Dictionary) -> bool: return s.op == "house" and s.has("windows")).map(func(s: Dictionary) -> int: return int(s.windows))
	check(range(WallLayout.WINDOW_FAMILIES.size()).all(func(k: int) -> bool: return k in families), "demo/windows.json puts up a house of each family")
	var night := demo.find_custom(func(s: Dictionary) -> bool: return s.op == "sun" and Daylight.lit(s.time) == 1.0)
	check(night > 0 and demo.slice(0, night).any(func(s: Dictionary) -> bool: return s.op == "capture") and demo.slice(night).any(func(s: Dictionary) -> bool: return s.op == "capture"), "it captures them by day and by night")
	var stress: Array = JSON.parse_string(FileAccess.get_file_as_string("res://../demo/stress.json"))
	var at := stress.find_custom(func(s: Dictionary) -> bool: return s.get("name", "") == "windows/aerial")
	check(at > 0 and stress.any(func(s: Dictionary) -> bool: return s.get("name", "") == "windows/ground"), "the stress scene has windows/aerial and windows/ground phases")
	var before := stress.slice(0, at)
	var village: int = before.rfind_custom(func(s: Dictionary) -> bool: return s.op == "village")
	var dark: int = before.rfind_custom(func(s: Dictionary) -> bool: return s.op == "sun")
	check(village >= 0 and before[village].get("windows", false) and dark > village and Daylight.lit(before[dark].time) == 1.0, "they look over a village opening windows in every house, by night")


func _in_the_glade() -> void:
	await process_frame
	main.world.bounded = false
	var tool: WallTool = main.tool
	var fit: FittingTool = main.fitting_tool
	var palette: PaletteTool = main.palette_tool
	var world: World = main.world
	await play([
		{"op": "place", "x": 0, "z": 12},
		{"op": "house", "at": [0.0, 0.0], "size": [6.0, 4.0], "seconds": 0.2},
		{"op": "house", "at": [10.0, 0.0], "size": [6.0, 4.0], "seconds": 0.2},
		{"op": "roof", "index": 1, "pitch": 0},
		{"op": "wait", "seconds": 0.5},
	])
	var house := tool.walls[0]
	var flat := tool.walls[1]
	for w in tool.walls:
		w.lay_now()
	var l := house.layout
	var corner := l.corners()[1]
	var at := l.frame_at(corner - 0.25)
	var n: Vector3 = at.tangent.cross(Vector3.UP) * -l.inner_side()
	var eye: Vector3 = at.point + Vector3.UP * 1.4 + n * 3.0
	var aimed := fit.aim(Hand.Tool.WINDOWS, eye, (at.point + Vector3.UP * 1.4 - eye).normalized())
	check(aimed.get("style") == WallLayout.Family.CORNER and is_equal_approx(aimed.get("s", -1.0), corner), "the windows tool on a corner's pier opens a corner window: %s" % aimed.get("style"))
	check(fit.fit(aimed), "and it opens")
	house.lay_now()
	check(l.apertures.any(func(o) -> bool: return o.style == WallLayout.Family.CORNER), "the house shows it")
	var mid := l.frame_at(corner * 0.5)
	tool.window_family = WallLayout.Family.ROUND
	var low_eye: Vector3 = mid.point + Vector3.UP * 0.5 + n * 3.0
	aimed = fit.aim(Hand.Tool.WINDOWS, low_eye, -n)
	check(aimed.get("style") == WallLayout.Family.ROUND and aimed.get("y", 0.0) >= WallLayout.lowest(WallLayout.Family.ROUND) - 0.001, "mid-face, low, the family last picked opens at a window's height: %s" % [aimed.get("y")])
	aimed = fit.aim(Hand.Tool.WINDOWS, low_eye + Vector3.UP * 0.85, -n)
	check(fit.fit(aimed), "a round window opens")
	house.lay_now()
	var round_at: Vector4 = Array(world.state.walls[house.id].openings).filter(func(o: Vector4) -> bool: return o.z == WallLayout.Family.ROUND)[0]
	var o := l.opening_for(round_at)
	var pane_point: Vector3 = l.frame_at(o.s).point + Vector3.UP * (o.sill + o.head) * 0.5
	var styled := palette.aim_style(pane_point + n * 2.5, -n)
	check(styled.get("restyle") == PaletteTool.Restyle.WINDOW and styled.count == WallLayout.WINDOW_FAMILIES.size(), "the style tool on a window opens a wheel of its families: %s" % styled.get("restyle"))
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.STYLE
	palette.open(hand, styled)
	palette.twist(hand, (styled.options.find(WallLayout.WINDOW_FAMILIES.find(WallLayout.Family.ARCHED)) - palette.wheels[hand].dial.start) * Dial.step(styled.count))
	palette.close(hand)
	hand.tool = Hand.Tool.WALLS
	await until(func() -> bool: return Array(world.state.walls[house.id].openings).any(func(e: Vector4) -> bool: return e.z == WallLayout.Family.ARCHED and e.x == round_at.x), "the window turned arched")
	check(tool.window_family == WallLayout.Family.ARCHED, "windows opened after take the family let go on")
	house.lay_now()
	var glass_at: Vector3 = l.frame_at(o.s).point + Vector3.UP * (o.sill + 0.3)
	var coloured := palette.aim(glass_at + n * 2.5, -n)
	check(coloured.get("element") == Palette.Element.GLOW, "the colour tool on a room's window picks its glow: %s" % coloured.get("element"))
	var door_eye: Vector3 = l.frame_at(corner * 0.25).point + Vector3.UP * 0.9 + n * 3.0
	tool.window_family = WallLayout.Family.COTTAGE
	check(fit.fit(fit.aim(Hand.Tool.WINDOWS, door_eye, -n)), "a door opens low on the wall")
	house.lay_now()
	check(l.lived_in() and not _kind(l, "curtain").is_empty(), "with a door the house is lived in, its windows curtained")

	var f := flat.roof.frame()
	var above: Vector3 = flat.transform * f.mid + Vector3.UP * 4.0
	var hatch := fit.aim(Hand.Tool.WINDOWS, above, Vector3.DOWN)
	check(hatch.get("what") == "hatch", "the windows tool on a flat roof opens a trapdoor: %s" % hatch.get("what"))
	var steps: int = world.stacks.get(world.me(), {"undo": []}).undo.size()
	check(fit.fit(hatch), "and a press lays it")
	await until(func() -> bool: return world.state.walls[flat.id].roof.hatches.size() == 1, "the trapdoor reaches the garden")
	flat.lay_now()
	check(flat.roof.tiles.any(func(t) -> bool: return t.kind == "hatch"), "the roof lays it")
	var on_it := fit.aim(Hand.Tool.WINDOWS, above, Vector3.DOWN)
	check(on_it.get("what") == "hatch" and on_it.has("fitting"), "pointed at again, the trapdoor is the target")
	check(fit.fit(on_it), "a press takes it away")
	await until(func() -> bool: return world.state.walls[flat.id].roof.hatches.is_empty(), "the trapdoor goes")
	world.undo()
	await until(func() -> bool: return world.state.walls[flat.id].roof.hatches.size() == 1, "undo brings the trapdoor back")
	check(world.stacks.get(world.me(), {"undo": []}).undo.size() == steps + 1, "laying it was one undo step")
	finish()
