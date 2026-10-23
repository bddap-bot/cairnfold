extends "res://../tests/support/suite.gd"

## Headless checks of flat roofs and platforms, railings, stacked decks, eaves, tents and dormers, as layouts and
## through the tools: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_roofs.gd

const SETTLE_FRAMES := 3600


func _initialize() -> void:
	_a_wooden_deck_is_boards_on_joists()
	_a_tower_takes_a_wooden_deck_inside_its_ring()
	_a_curved_wooden_deck_follows_its_surface()
	_a_railing_rims_a_deck_and_tops_a_wall()
	_flat_roofs_stack_into_terraces()
	_the_eaves_reach_as_far_as_pulled()
	_a_low_roof_comes_down_to_the_ground()
	_a_dormer_stands_out_of_the_slope()
	_a_dormer_needs_room()
	_the_budget_counts_eaves_and_dormers()
	_the_command_carries_decks_eaves_and_dormers()
	_the_style_tool_offers_both_decks()
	boot_main()
	_in_the_glade.call_deferred()


func _gable(length: float, depth: float, pitch: float, curve := 0.0) -> RoofLayout:
	var r := RoofLayout.new()
	r.corners = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(length, 0, 0), depth)
	r.base = 2.54
	r.foot = 0.0
	r.pitch = pitch
	r.curve = curve
	return r


func _of(r: RoofLayout, kind: String) -> Array:
	return r.tiles.filter(func(t): return t.kind == kind)


## Whether the box `x` lays over the ground point `p`, seen from above.
func _covers(x: Transform3D, p: Vector2) -> bool:
	var inverse := x.affine_inverse()
	return AABB(Vector3.ONE * -0.5, Vector3.ONE).intersects_ray(inverse * Vector3(p.x, x.origin.y + 10.0, p.y), inverse.basis * Vector3.DOWN) != null


func _top_of(x: Transform3D) -> float:
	return x.origin.y + absf(x.basis.y.y) * 0.5


func _a_wooden_deck_is_boards_on_joists() -> void:
	var r := _gable(6.0, 4.0, 0.0)
	r.deck = RoofLayout.Deck.WOOD
	r.build()
	var boards := _of(r, "plank")
	var joists := _of(r, "board")
	check(boards.size() > 40 and _of(r, "deck").is_empty() and r.mortar.is_empty(), "a wooden deck lays boards, no flags or mortar: %d boards" % boards.size())
	check(boards.size() + joists.size() == r.tiles.size(), "a flat wooden roof is all boards and joists")
	var inner := Vector2(3.0 - WallLayout.THICKNESS * 0.5 + RoofLayout.DECK_TUCK, 2.0 - WallLayout.THICKNESS * 0.5 + RoofLayout.DECK_TUCK)
	var deck_top := r.base - RoofLayout.DECK_DROP
	var astray := boards.filter(func(t): return absf(t.xform.origin.x - 3.0) > inner.x or absf(t.xform.origin.z) > inner.y or absf(_top_of(t.xform) - deck_top) > 0.012)
	check(astray.is_empty(), "every board lies inside the walls at the deck's height: %d astray" % astray.size())
	check(boards.all(func(t): return t.xform.basis.x.normalized().dot(Vector3.RIGHT) > 0.99), "the boards run along the ridge")
	var lengths := {}
	for t in boards:
		lengths[snappedf(t.xform.basis.x.length(), 0.01)] = true
	check(lengths.size() > 8, "boards come in many lengths, staggered: %d" % lengths.size())
	check(joists.size() >= 8 and joists.all(func(t): return _top_of(t.xform) <= deck_top - RoofLayout.PLANK.y + 0.001), "joists run under the boards: %d" % joists.size())
	var open := 0
	for i in 60:
		for j in 40:
			var p := Vector2(3.0 + (i / 59.0 - 0.5) * 2.0 * (inner.x - 0.05), (j / 39.0 - 0.5) * 2.0 * (inner.y - 0.05))
			if not boards.any(func(t): return _covers(t.xform, p)):
				open += 1
	check(open < 2400 * 0.06, "boards cover the deck but for their joints: %d of 2400 points open" % open)
	var t := r.ray_hit(Vector3(3, 10, 1), Vector3.DOWN)
	check(absf(t - (10.0 - r.base)) < 0.01, "pointing at a wooden deck hits it")
	var stone := _gable(6.0, 4.0, 0.0)
	stone.build()
	check(not _of(stone, "deck").is_empty() and _of(stone, "plank").is_empty(), "a stone deck stays flagged")


func _a_tower_takes_a_wooden_deck_inside_its_ring() -> void:
	var r := RoofLayout.new()
	r.kind = RoofLayout.Kind.CONE
	r.center = Vector3(1, 0, 1)
	r.radius = 2.0
	r.base = 4.6
	r.pitch = 0.0
	r.deck = RoofLayout.Deck.WOOD
	r.build()
	var boards := _of(r, "plank")
	var reach := 2.0 - WallLayout.THICKNESS * 0.5 + RoofLayout.DECK_TUCK
	check(boards.size() > 20, "a tower's wooden deck lays %d boards" % boards.size())
	var out := boards.filter(func(t):
		var x: Transform3D = t.xform
		for e in [-0.5, 0.5]:
			var end: Vector3 = x.origin + x.basis.x * e
			if Vector2(end.x - 1.0, end.z - 1.0).length() > reach + 0.02:
				return true
		return false)
	check(out.is_empty(), "no board runs out through the tower's wall: %d" % out.size())
	var open := 0
	for i in 24:
		for j in 10:
			var a := TAU * i / 24.0
			var rho := (reach - 0.12) * j / 10.0
			if not boards.any(func(t): return _covers(t.xform, Vector2(1 + cos(a) * rho, 1 + sin(a) * rho))):
				open += 1
	check(open < 240 * 0.06, "the boards floor the tower's top: %d of 240 points open" % open)


func _a_curved_wooden_deck_follows_its_surface() -> void:
	var r := _gable(6.0, 4.0, 0.0, 0.8)
	r.deck = RoofLayout.Deck.WOOD
	r.build()
	var off := _of(r, "plank").filter(func(t):
		var p: Vector3 = t.xform.origin
		return absf(p.y + absf(t.xform.basis.y.length()) * 0.5 - (r.height_at(p.x, p.z) - RoofLayout.DECK_DROP)) > 0.03)
	check(off.is_empty(), "a bowed wooden deck's boards ride its surface: %d off it" % off.size())


func _house(length: float, depth: float, top: WallLayout.Top, cover: WallLayout.Cover) -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(length, 0, 0), depth)
	w.closed = true
	w.cover = cover
	w.top = top
	w.height = 2.4
	w.build(Terrain.flat)
	return w


func _a_railing_rims_a_deck_and_tops_a_wall() -> void:
	var w := _house(6.0, 4.0, WallLayout.Top.RAIL, WallLayout.Cover.DECK)
	var top := w.height + WallLayout.CAP - WallLayout.SINK
	var posts := w.stones.filter(func(s): return s.kind == "post")
	var rails := w.stones.filter(func(s): return s.kind == "rail")
	check(posts.size() >= 12 and rails.size() >= 16, "a railed deck stands on posts and rails: %d posts, %d rails" % [posts.size(), rails.size()])
	check(posts.all(func(s): return absf(s.xform.origin.y - (top + WallLayout.RAILING * 0.5)) < 0.03), "the posts stand on the cap")
	check(not w.stones.any(func(s): return s.kind == "block" and s.xform.origin.y > top), "a railing, not a parapet")
	var run: float = rails.reduce(func(m, s): return m + s.xform.basis.x.length(), 0.0) * 0.5
	var spans := w.length() - 4.0 * (WallLayout.PIER + 0.06)
	check(run > spans - 0.2, "the rails run all the way round between the corner piers: %.1f of %.1f m" % [run, spans])
	var high := rails.filter(func(s): return s.xform.origin.y > top + WallLayout.RAILS.y - 0.01)
	check(high.size() * 2 == rails.size(), "two rails, a top one and a middle one")
	var open := WallLayout.new()
	open.points = [Vector3(0, 0, 0), Vector3(8, 0, 0)]
	open.height = 2.7
	open.top = WallLayout.Top.RAIL
	open.build(Terrain.flat)
	check(open.stones.any(func(s): return s.kind == "post") and not open.stones.any(func(s): return s.kind == "merlon"), "an open wall takes a railing as its top too")
	var roofed := _house(6.0, 4.0, WallLayout.Top.RAIL, WallLayout.Cover.ROOF)
	check(not roofed.stones.any(func(s): return s.kind in ["post", "rail"]), "under a pitched roof the railing goes")
	check(WallLayout.Top.size() == 4 and Commands._wall(_wall_data(WallLayout.Top.RAIL)) != null, "the railing is a top the command takes")


func _wall_data(top: int) -> Dictionary:
	return {
		"points": PackedVector3Array([Vector3.ZERO, Vector3(6, 0, 0)]), "height": 2.4, "rise": 0.0, "seed": 1, "closed": false, "top": top,
		"fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(),
		"plaster": false, "plinth_plaster": false, "planks": false, "gable_end": 0, "timber_style": 0, "on": PackedInt32Array(), "paint": Palette.plain(),
	}


func _storey(a: Vector3, b: Vector3, depth: float, on: Array[Massing], top := WallLayout.Top.CAP) -> Dictionary:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(a, b, depth)
	w.closed = true
	w.top = top
	w.cover = WallLayout.Cover.DECK
	w.height = 2.4
	w.supports = on
	w.resample(Terrain.flat)
	var r := RoofLayout.new()
	r.corners = w.points
	r.pitch = 0.0
	return {"wall": w, "roof": r, "massing": Massing.of(w, r)}


func _lay(h: Dictionary) -> void:
	var w: WallLayout = h.wall
	w.build(Terrain.flat)
	h.roof.base = w.samples[0].y + w.height + WallLayout.CAP
	h.roof.foot = w.stands_at()
	h.roof.build()
	w.hide_roof(h.roof)


func _flat_roofs_stack_into_terraces() -> void:
	var ground := _storey(Vector3(0, 0, 0), Vector3(8, 0, 0), 6.0, [])
	var middle := _storey(Vector3(1.5, 0, 0), Vector3(6.5, 0, 0), 3.6, [ground.massing], WallLayout.Top.RAIL)
	var upper := _storey(Vector3(2.5, 0, 0), Vector3(5.5, 0, 0), 2.4, [middle.massing])
	var first: float = ground.massing.feet[0] + ground.massing.rise
	var second: float = middle.massing.feet[0] + middle.massing.rise
	check(absf(middle.wall.samples[0].y - (first - WallLayout.SINK)) < 0.001, "a platform stands on the deck below")
	check(absf(upper.wall.samples[0].y - (second - WallLayout.SINK)) < 0.001 and second > first + 2.0, "and another on it, a storey up")
	ground.wall.resting.assign([middle.massing])
	middle.wall.resting.assign([upper.massing])
	for h in [ground, middle, upper]:
		_lay(h)
	var parapet := func(h: Dictionary, inside: Massing) -> Array:
		var top: float = h.massing.feet[0] + h.massing.rise
		return h.wall.stones.filter(func(s): return s.kind == "block" and s.xform.origin.y > top and (inside == null or Massing.encloses(Vector2(s.xform.origin.x, s.xform.origin.z), inside.outer)))
	check(not parapet.call(ground, null).is_empty(), "the lowest deck keeps its parapet round the terrace")
	check(middle.wall.stones.any(func(s): return s.kind == "rail") and upper.wall.stones.any(func(s): return s.kind == "block" and s.xform.origin.y > second + WallLayout.CAP), "each platform keeps its own rim")
	var under: Array = ground.roof.tiles.filter(func(t): return Massing.encloses(Vector2(t.xform.origin.x, t.xform.origin.z), middle.massing.inner))
	check(not under.is_empty() and under.all(func(t): return _top_of(t.xform) <= first + 0.001), "the deck under a platform stays, under its floor")
	var terrace: Array = ground.roof.tiles.filter(func(t): return not Massing.encloses(Vector2(t.xform.origin.x, t.xform.origin.z), middle.massing.outer))
	check(terrace.size() > 40, "the deck round it is a terrace: %d flags" % terrace.size())
	check(upper.roof.tiles.size() > 10 and middle.roof.tiles.size() > 10, "each platform is decked")
	var r: RoofLayout = middle.roof
	check(absf(r.deck_under(Vector3(4.0, second + 0.2, 1.0)) - r.height_at(4.0, 1.0)) < 0.001, "a stacked platform is stood on at its deck")


func _the_eaves_reach_as_far_as_pulled() -> void:
	var furthest := func(r: RoofLayout) -> float:
		return _of(r, "tile").reduce(func(m, t): return maxf(m, absf(t.xform.origin.z)), 0.0)
	var short := _gable(6.0, 4.0, 2.0)
	short.overhang = 0.0
	short.build()
	var long := _gable(6.0, 4.0, 2.0)
	long.overhang = 1.2
	long.build()
	var hs := short.half_span()
	check(absf(short.eave() - hs) < 0.001 and absf(long.eave() - hs - 1.2) < 0.001, "the eave reaches its overhang past the walls")
	check(furthest.call(short) < hs + 0.15 and furthest.call(long) > hs + 1.05 and furthest.call(long) < hs + 1.35, "tiles run out to the eave: %.2f and %.2f past %.2f" % [furthest.call(short), furthest.call(long), hs])
	check(_of(long, "tile").size() > _of(short, "tile").size(), "a longer eave lays more tiles")
	check(long.ray_hit(Vector3(3, 10, hs + 1.0), Vector3.DOWN) < INF and short.ray_hit(Vector3(3, 10, hs + 1.0), Vector3.DOWN) == INF, "pointing at the long eave hits it")
	check(long.eave_way(Vector3(3, 4, -(hs + 0.5))).is_equal_approx(Vector3(0, 0, -1)) and long.eave_way(Vector3(3, 4, 0.5)) == Vector3.ZERO, "a grip past the walls pulls its own eave; over them, the ridge")
	var cone := RoofLayout.new()
	cone.kind = RoofLayout.Kind.CONE
	cone.radius = 2.0
	cone.pitch = 3.0
	cone.base = 4.0
	cone.overhang = 0.9
	cone.build()
	var ring: float = _of(cone, "tile").reduce(func(m, t): return maxf(m, Vector2(t.xform.origin.x, t.xform.origin.z).length()), 0.0)
	check(ring > cone.half_span() + 0.8, "a cone's eave reaches its overhang too: %.2f" % ring)
	check(_holds_eave(1.2) and not _holds_eave(0.3), "a build under the long eave stands under it")


## Whether a house's eaves `overhang` past its walls cover a point 1 m out from its long side.
func _holds_eave(overhang: float) -> bool:
	var w := _house(6.0, 4.0, WallLayout.Top.CAP, WallLayout.Cover.ROOF)
	var r := RoofLayout.new()
	r.corners = w.points
	r.pitch = 2.0
	r.overhang = overhang
	var m := Massing.of(w, r)
	return m.covers(Vector3(3.0, 1.0, -(2.0 + WallLayout.THICKNESS * 0.5 + 1.0)))


func _a_low_roof_comes_down_to_the_ground() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(0, 0, 0), Vector3(6, 0, 0), 4.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.height = WallLayout.MIN_HEIGHT
	w.build(Terrain.flat)
	var r := RoofLayout.new()
	r.corners = w.points
	r.pitch = 2.6
	r.overhang = RoofLayout.MAX_OVERHANG
	r.base = w.samples[0].y + w.height + WallLayout.CAP
	r.foot = w.stands_at()
	r.build()
	check(r.eave() < r.half_span() + r.overhang - 0.1 and absf(r.eave() - r.half_span() - r.reach()) < 0.001, "a long overhang on low walls comes down to the ground")
	check(absf(r.base + r.rise(1.0 - r.eave() / r.half_span()) - r.foot) < 0.01, "its eave meets the ground the walls stand on: %.2f at %.2f" % [r.base + r.rise(1.0 - r.eave() / r.half_span()), r.foot])
	var tiles := _of(r, "tile")
	var lowest: float = tiles.reduce(func(m, t): return minf(m, t.xform.origin.y), INF)
	check(lowest > r.foot - 0.15 and lowest < r.foot + 0.25, "its lowest tiles lie on the ground, none under it: %.2f" % lowest)
	check(r.eave() > r.half_span() + 0.8, "the slopes run on well past the walls, a tent: %.2f past" % (r.eave() - r.half_span()))
	var tall := _gable(6.0, 4.0, 2.6)
	tall.overhang = 1.5
	tall.build()
	check(absf(tall.eave() - tall.half_span() - 1.5) < 0.001 and tall.reach() > 1.5, "high walls keep the eave off the ground")
	var raised := WallLayout.new()
	raised.points = w.points
	raised.closed = true
	raised.height = WallLayout.MIN_HEIGHT
	raised.rise = 1.2
	raised.build(Terrain.flat)
	check(absf(raised.stands_at()) < 0.001, "a raised house's eaves may come down past its plinth to the ground")


func _steep(pitch := 3.2) -> RoofLayout:
	var r := _gable(7.0, 5.0, pitch)
	return r


func _a_dormer_stands_out_of_the_slope() -> void:
	var r := _steep()
	r.dormers.assign([Vector2(-1.5, -10.0), Vector2(1.5, 2.0)])
	r.build()
	var bare := _steep()
	bare.build()
	var f := r.frame()
	var hs := r.half_span()
	check(_of(r, "glass").size() == 2 and _of(r, "frame").size() == 12, "each dormer has a cottage window: %d panes" % _of(r, "glass").size())
	check(_of(r, "board").size() > 30, "dormers are boarded: %d boards" % _of(r, "board").size())
	check(_of(r, "tile").size() > _of(bare, "tile").size() + 40, "and tiled over: %d tiles more" % (_of(r, "tile").size() - _of(bare, "tile").size()))
	for i in r.dormers.size():
		var spot := r.dormer_spot(r.dormers[i])
		var room := r.dormer_bounds(r.dormers[i])
		var inverse: Transform3D = room[0].affine_inverse()
		var box: AABB = room[1].grow(0.12)
		var mine := r.tiles.filter(func(t): return box.has_point(inverse * t.xform.origin) and t.kind in ["board", "glass", "frame", "sill"])
		check(mine.size() > 15, "dormer %d lays its pieces in its room: %d" % [i, mine.size()])
		var pane: Array = mine.filter(func(t): return t.kind == "glass")
		var out: Vector3 = f.across * signf(spot.y)
		check(pane.size() == 1 and absf(pane[0].xform.basis.z.normalized().dot(out)) > 0.99, "dormer %d's pane faces out of the slope" % i)
		var pane_at: Vector3 = pane[0].xform.origin if pane.size() == 1 else Vector3.ZERO
		check(pane_at.y > r.base + r.rise(1.0 - absf(spot.y) / hs) + 0.15, "dormer %d's window stands clear of the slope" % i)
		var top: float = r.tiles.filter(func(t): return box.has_point(inverse * t.xform.origin)).reduce(func(m, t): return maxf(m, t.xform.origin.y), -INF)
		check(top < r.base + r.pitch, "dormer %d's own ridge stays under the roof's: %.2f under %.2f" % [i, top, r.base + r.pitch])
	check(r.dormer_spot(Vector2(-1.5, -10.0)).y < 0.0 and absf(r.dormer_spot(Vector2(-1.5, -10.0)).y) <= hs - WallLayout.THICKNESS * 0.5 + 0.001, "a dormer placed past the eave stands over the wall")
	var thatched := _steep()
	thatched.thatch = true
	thatched.dormers.assign([Vector2(0.0, 2.0)])
	thatched.build()
	var pane: Array = _of(thatched, "glass")
	check(pane.size() == 1 and thatched.ray_hit(pane[0].xform.origin + f.across * 3.0, -f.across) > 2.5, "a dormer's window looks out over thatch, not into it")
	var copy := r.inputs()
	copy.dormers.clear()
	check(not copy.same_inputs(r), "a dormer is part of what the roof is laid from")


func _a_dormer_needs_room() -> void:
	var low := _gable(6.0, 4.0, 1.4)
	check(is_nan(low.dormer_spot(Vector2(0, 1)).x) and not low.dormer_fits(Vector2(0, 1), []), "a low roof has no room for a dormer")
	var steep := _steep()
	check(steep.dormer_fits(Vector2(0, 2), []), "a steep one has")
	check(not steep.dormer_fits(Vector2(0.8, 2), [Vector2(0, 2)]) and steep.dormer_fits(Vector2(0.8, -2), [Vector2(0, 2)]), "two dormers on a slope keep apart; on the other slope they may stand opposite")
	var spot := steep.dormer_spot(Vector2(40, 0.1))
	var along := steep.ridge_length() * 0.5 - WallLayout.THICKNESS * 0.5 - RoofLayout.DORMER_HALF - RoofLayout.DORMER_EAVE - RoofLayout.DORMER_CLEAR
	check(absf(spot.x - along) < 0.001, "a dormer keeps clear of the gable end: %s" % spot)
	check(steep.base + steep.rise(1.0 - spot.y / steep.half_span()) + RoofLayout.DORMER_TALL + RoofLayout.DORMER_PITCH <= steep.base + steep.pitch - RoofLayout.DORMER_UNDER + 0.01, "a dormer pointed at the ridge stands down the slope enough to keep under it")
	var flat := _gable(6.0, 4.0, 0.0)
	check(is_nan(flat.dormer_spot(Vector2(0, 1)).x), "a flat roof takes no dormer")
	var cone := RoofLayout.new()
	cone.kind = RoofLayout.Kind.CONE
	cone.radius = 2.0
	cone.pitch = 4.0
	check(is_nan(cone.dormer_spot(Vector2(0, 1)).x), "nor a cone")
	steep.chimneys.assign([Vector2(0.4, 1.0)])
	check(not steep.dormer_fits(Vector2(0, 2), []) and steep.dormer_fits(Vector2(0, -2), []) and steep.dormer_fits(Vector2(-2.0, 2), []), "a dormer keeps clear of a chimney on its slope")
	steep.chimneys.clear()
	steep.dormers.assign([Vector2(0, 2)])
	check(not steep.clear_of_dormers(Vector2(0.4, 1.0)) and steep.clear_of_dormers(Vector2(0.4, -1.0)), "and a chimney of a dormer")


func _house_data(pitch: float) -> Dictionary:
	var points := PackedVector3Array(WallLayout.rectangle(Vector3.ZERO, Vector3(7, 0, 0), 5.0))
	return {
		"points": points, "height": 2.4, "rise": 0.0, "seed": 3, "closed": true, "top": WallLayout.Top.CAP,
		"fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(),
		"plaster": false, "plinth_plaster": false, "planks": false, "gable_end": 0, "timber_style": 0, "on": PackedInt32Array(), "paint": Palette.plain(),
		"roof": {"kind": RoofLayout.Kind.GABLE, "center": Vector3(3.5, 0, 0), "radius": 2.0, "pitch": pitch, "curve": 0.0, "seed": 3, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false},
	}


func _the_budget_counts_eaves_and_dormers() -> void:
	var d := _house_data(3.2)
	var plain := Budget.wall(d)
	d.roof.overhang = 1.0
	var eaves := Budget.wall(d)
	check(eaves.roof_m2 > plain.roof_m2 + 2.0 * 7.6 * 0.6, "a longer eave counts its tiles: %.1f against %.1f m²" % [eaves.roof_m2, plain.roof_m2])
	d.roof.overhang = RoofLayout.OVERHANG
	d.roof.dormers = PackedVector2Array([Vector2(-1.4, 2.0), Vector2(1.4, -2.0)])
	var dormered := Budget.wall(d)
	check(dormered.get("fitting", 0) == plain.get("fitting", 0) + 2, "each dormer counts as a fitting")
	check(dormered.wall_m2 > plain.wall_m2 + 2.0 and dormered.roof_m2 > plain.roof_m2 + 2.0, "and its boarded faces as wall and its slopes as roof: %.1f, %.1f m² more" % [dormered.wall_m2 - plain.wall_m2, dormered.roof_m2 - plain.roof_m2])
	d.roof.pitch = 0.0
	var flat := Budget.wall(d)
	d.roof.dormers = PackedVector2Array()
	check(flat.get("fitting", 0) == Budget.wall(d).get("fitting", 0) and flat.roof_m2 == Budget.wall(d).roof_m2, "dormers kept by a roof pushed flat stand nowhere and count nothing")
	var tent := _house_data(2.6)
	tent.height = WallLayout.MIN_HEIGHT
	tent.roof.overhang = RoofLayout.MAX_OVERHANG
	var held := tent.duplicate(true)
	held.height = 4.0
	check(Budget.wall(tent).roof_m2 < Budget.wall(held).roof_m2 - 4.0, "a tent counts its slopes only down to the ground: %.1f against %.1f m²" % [Budget.wall(tent).roof_m2, Budget.wall(held).roof_m2])


func _the_command_carries_decks_eaves_and_dormers() -> void:
	var d := _house_data(3.2)
	d.roof.deck = RoofLayout.Deck.WOOD
	d.roof.overhang = 1.5
	d.roof.dormers = PackedVector2Array([Vector2(1, 2)])
	var cleaned: Variant = Commands._wall(d)
	check(cleaned != null and cleaned.roof.deck == RoofLayout.Deck.WOOD and cleaned.roof.overhang == 1.5 and cleaned.roof.dormers == PackedVector2Array([Vector2(1, 2)]), "a house keeps its deck, eaves and dormers")
	var round := d.duplicate(true)
	round.roof.kind = RoofLayout.Kind.CONE
	check(Commands._wall(round) == null, "a tower's cone takes no dormer")
	for bad in [{"deck": 2}, {"deck": -1}, {"overhang": RoofLayout.MAX_OVERHANG + 0.1}, {"overhang": -0.1}, {"dormers": [Vector2(1, 2)]}, {"dormers": PackedVector2Array([Vector2(INF, 2)])}]:
		var broken := d.duplicate(true)
		broken.roof.merge(bad, true)
		check(Commands._wall(broken) == null, "the command refuses a roof with %s" % bad)
	var many := d.duplicate(true)
	many.roof.dormers.resize(Commands.MAX_DORMERS + 1)
	check(Commands._wall(many) == null, "and more than %d dormers" % Commands.MAX_DORMERS)
	var change: Variant = Commands._reshape("walls", {"roof": {"overhang": 0.8, "deck": RoofLayout.Deck.STONE, "dormers": PackedVector2Array()}}, cleaned)
	check(change != null and change.roof.overhang == 0.8, "a reshape changes them")


func _the_style_tool_offers_both_decks() -> void:
	var d := _house_data(0.0)
	check(WallTool.roof_options(0.0) == [WallTool.RoofStyle.FLAT, WallTool.RoofStyle.BOARDED], "a flat roof offers a stone deck and a wooden one")
	check(WallTool.restyle_roof(d, WallTool.RoofStyle.BOARDED) == {"roof": {"deck": RoofLayout.Deck.WOOD}}, "picking boards decks it in wood")
	d.roof.deck = RoofLayout.Deck.WOOD
	check(WallTool.roof_style(d) == WallTool.RoofStyle.BOARDED, "a wooden deck reads back as boarded")
	check(WallTool.restyle_roof(d, WallTool.RoofStyle.THATCHED).is_empty(), "a flat roof takes no thatch")
	var pitched := _house_data(2.0)
	check(WallTool.restyle_roof(pitched, WallTool.RoofStyle.BOARDED).is_empty(), "a pitched roof takes no deck")


func _lay_walls() -> void:
	for w: Wall in main.tool.walls:
		w.lay_now()


func _play(script: Array) -> void:
	await play(script)
	await frames(10)
	_lay_walls()


func _in_the_glade() -> void:
	var walls: Array[Wall] = main.tool.walls
	var world: World = main.world
	var fit: FittingTool = main.fitting_tool
	await _play([
		{"op": "budget", "bounded": false},
		{"op": "place", "x": 0, "z": 14},
		{"op": "house", "at": [6.0, 0.0], "size": [7.0, 3.6], "seconds": 0.2},
		{"op": "house", "at": [-6.0, 0.0], "size": [6.0, 5.0], "seconds": 0.2},
	])
	check(walls.size() == 2, "two houses stand: %d" % walls.size())
	if walls.size() != 2:
		_done()
		return
	var house := walls[0]
	var deck := walls[1]
	var r := house.roof
	var ridge: Vector3 = r.frame().mid + Vector3.UP * r.pitch
	var slope: Vector3 = ridge + r.frame().across * 1.6
	var aim := fit.aim(Hand.Tool.WINDOWS, slope + Vector3.UP * 6.0, Vector3.DOWN)
	check(aim.get("what") == "dormer", "the windows tool pointed at a gable's slope opens a dormer: %s" % aim.get("what"))
	world.submit({"op": "reshape", "of": "walls", "id": house.id, "data": {"roof": {"chimneys": PackedVector2Array([Vector2(1.5, 0.0)])}}})
	_lay_walls()
	var stack: Vector3 = r.frame().mid + r.frame().along * 1.5 + Vector3.UP * (r.pitch + 1.2)
	check(fit.aim(Hand.Tool.WINDOWS, stack + r.frame().across * 4.0, -r.frame().across).is_empty(), "the windows tool pointed at a chimney does nothing")
	world.submit({"op": "reshape", "of": "walls", "id": house.id, "data": {"roof": {"chimneys": PackedVector2Array()}}})
	_lay_walls()
	check(not fit.fit(aim), "a roof too low for one refuses it")
	await _play([{"op": "roof", "index": 0, "pitch": 3.4}])
	ridge = r.frame().mid + Vector3.UP * r.pitch
	slope = ridge + r.frame().across * 1.6 + Vector3.DOWN * 1.0
	aim = fit.aim(Hand.Tool.WINDOWS, slope + Vector3.UP * 6.0, Vector3.DOWN)
	var steps := func() -> int: return world.stacks.get(world.me(), {"undo": []}).undo.size()
	var before: int = steps.call()
	check(fit.fit(aim), "on a steep roof a press opens a dormer")
	_lay_walls()
	var placed: PackedVector2Array = world.state.walls[house.id].roof.dormers
	check(placed.size() == 1 and steps.call() == before + 1, "one dormer, one undo step: %d" % placed.size())
	check(house.roof.tiles.any(func(t): return t.kind == "glass"), "the house lays it")
	var room := house.roof.dormer_bounds(placed[0]) if placed.size() == 1 else []
	if not room.is_empty():
		var front: Vector3 = room[0].origin + room[0].basis.z * 3.0 + Vector3.UP * (room[1].position.y + room[1].size.y * 0.4)
		var at_it := fit.aim(Hand.Tool.WINDOWS, front, -room[0].basis.z)
		check(at_it.get("what") == "dormer" and at_it.has("fitting"), "the windows tool pointed at a dormer picks it: %s" % at_it.get("what"))
		check(fit.fit(at_it) and world.state.walls[house.id].roof.dormers.is_empty(), "a press on it takes it away")
		_lay_walls()
		check(fit.aim(Hand.Tool.DECORATIONS, front, -room[0].basis.z).get("what") != "dormer", "decorations never take a dormer")
		world.undo()
		_lay_walls()
		check(world.state.walls[house.id].roof.dormers.size() == 1, "undo puts it back")
	var tool: WallTool = main.tool
	var hs := r.half_span()
	var across: Vector3 = r.frame().across
	var eave: Vector3 = r.frame().mid + across * (hs + 0.15) + Vector3.UP * r.rise(1.0 - (hs + 0.15) / hs)
	check(r.eave_way(eave).is_equal_approx(across) and r.eave_way(eave - across * (hs + 0.15) * 2.0).is_equal_approx(-across), "a grip on either eave, past the walls, holds that eave")
	check(r.eave_way(ridge) == Vector3.ZERO, "a grip on the slope over the walls holds the roof itself")
	tool.take_build(house)
	var from: Array[Transform3D] = [Transform3D(Basis(), eave - across * 2.0 * (hs + 0.15)), Transform3D(Basis(), eave)]
	var to: Array[Transform3D] = [Transform3D(Basis(), from[0].origin - across * 0.8), Transform3D(Basis(), from[1].origin + across * 0.8)]
	var out: Array[Vector3] = [-across, across]
	tool.stand_build(WallTool.pull_eaves(tool.held_at, from, to, out, 1.0, house.roof.reach()))
	tool.end_build()
	for f in 4:
		await process_frame
	var pulled: float = world.state.walls[house.id].roof.overhang
	check(absf(pulled - (RoofLayout.OVERHANG + 0.8)) < 0.06 and world.state.walls[house.id].roof.pitch == r.pitch, "both eaves pulled out, they reach further and the pitch stays: %.2f" % pulled)
	await _play([{"op": "roof", "index": 1, "pitch": 0.0, "deck": "wood"}, {"op": "top", "index": 1, "style": "rail"}])
	var d: Dictionary = world.state.walls[deck.id]
	check(d.roof.pitch == 0.0 and d.roof.deck == RoofLayout.Deck.WOOD and d.top == WallLayout.Top.RAIL, "a house pushed flat takes a wooden deck and a railing")
	check(deck.roof.tiles.any(func(t): return t.kind == "plank") and deck.layout.stones.any(func(s): return s.kind == "rail"), "and lays them")
	await _play([{"op": "house", "at": [-6.0, 0.0], "size": [3.4, 3.0], "seconds": 0.2, "on": true}])
	check(walls.size() == 3 and walls[2].on == PackedInt32Array([deck.id]), "a house set down on the deck stands on it")
	if walls.size() == 3:
		var upper := walls[2]
		await _play([{"op": "roof", "index": 2, "pitch": 0.0}])
		var top: float = deck.layout.samples[0].y + deck.layout.height + WallLayout.CAP
		check(absf(upper.layout.samples[0].y + WallLayout.SINK - top) < 0.01, "a platform on a platform: %.2f on %.2f" % [upper.layout.samples[0].y + WallLayout.SINK, top])
		check(deck.roof.tiles.filter(func(t): return t.kind == "plank").size() > 20 and deck.layout.stones.any(func(s): return s.kind == "rail"), "the deck below stays a railed terrace round it")
	_done()


func _done() -> void:
	finish()
