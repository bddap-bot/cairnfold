extends "res://../tests/support/suite.gd"

## Headless checks that the teleport ray lands on whatever solid it meets in the garden, a pitched roof, a tree, a
## wall's top, and that what the player stands on and hovers over is the top surface beneath: a wall walk, a flat
## roof, a platform, stairs and a bridge; and that a wall's face, struck low, lands at its foot and, struck high, floats there, while a ruin's stepped ledge, pointed at, is stood on: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_teleport_solids.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	await process_frame
	var rig: Rig = main.rig
	rig.set_process(false)
	var world: World = main.world
	world.load_from(OS.get_temp_dir().path_join("nestcombe-teleport-%d.garden" % OS.get_process_id()))
	_onto_a_pitched_roof(rig, world)
	_onto_a_tree(rig, world)
	_onto_a_wall_top(rig, world)
	_onto_a_wall_face(rig, world)
	_onto_a_ruin_ledge(rig, world)
	_onto_a_raised_floor(rig, world)
	_on_a_wall_walk(rig, world)
	_on_flat_roofs_and_platforms(rig, world)
	_on_stairs_and_a_bridge(rig, world)
	finish()


func _pose(origin: Vector3, dir: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(dir, Vector3.UP), origin)


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return wall_data({"points": points, "seed": 3})


## Aims at `at` from `from`, lands, and checks the player stands upright where the ray hit, on `surface`'s height.
func _lands(rig: Rig, from: Vector3, at: Vector3, surface: Callable, what: String) -> void:
	rig.aim(_pose(from, at - from))
	var g: Variant = rig.aim_ground
	check(g != null and rig.aim_lift == 0.0, "a ray %s has a landing where it hits: %s up %.2f" % [what, g, rig.aim_lift])
	if g == null:
		return
	rig.place(g, rig.aim_lift)
	var h := rig.head.global_position
	var stand := rig.global_position.y
	var want: float = surface.call(h)
	check(absf(stand - want) < 0.3, "aimed %s, the player stands on it: %.2f for %.2f, ground %.2f" % [what, stand, want, Terrain.height_at(h.x, h.z)])
	check(rig.global_basis.y.is_equal_approx(Vector3.UP), "aimed %s, the player stands upright" % what)


## Aims down at `at` with the stick eased back to `fraction`, and checks the hover there counts from `top`, the surface
## beneath it, and lets go on it.
func _hovers(rig: Rig, at: Vector3, top: float, what: String, fraction := 0.75) -> void:
	var from := at + Vector3(0, 6, 0.4)
	rig.aim(_pose(from, at - from), fraction)
	var g: Variant = rig.aim_ground
	check(g != null and absf(g.y - top) < 0.02, "hovering over %s, the target counts from its top %.2f: %s" % [what, top, g])
	if g == null:
		return
	var target: Vector3 = g + Vector3.UP * rig.aim_lift
	check(absf(target.y - from.lerp(at, fraction).y) < 0.3 and rig.aim_lift > Rig.LIFTED, "hovering over %s, the target floats on the ray, %.2f m over it" % [what, rig.aim_lift])
	rig.place(g, rig.aim_lift)
	check(absf(rig.global_position.y - target.y) < 0.01, "let go over %s, the player floats where it aimed: %.2f for %.2f" % [what, rig.global_position.y, target.y])
	rig.aim(_pose(from, at - from), 0.999)
	g = rig.aim_ground
	check(g != null and absf(g.y - top) < 0.02 and rig.aim_lift <= Rig.LIFTED + 0.3, "eased all but home over %s, the target settles on its top: %s up %.2f" % [what, g, rig.aim_lift])


## Checks a point `up` metres over `at` stands on `want`, and one under the surface there on the ground.
func _stands(at: Vector3, up: float, want: float, what: String) -> void:
	var y: float = main.rig.floor_under.call(at + Vector3.UP * up)
	check(absf(y - want) < 0.02, "%s stands on %.2f: %.2f" % [what, want, y])


func _onto_a_pitched_roof(rig: Rig, world: World) -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-40, 30), Terrain.ground(-34, 30), 4.0)))
	d.closed = true
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(-37, 30), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var r: RoofLayout = w.roof
	var f := r.frame()
	var slope: Vector3 = Vector3(f.mid.x, 0.0, f.mid.z) + f.across * r.half_span() * 0.5
	slope.y = r.height_at(slope.x, slope.z)
	var on_roof := func(p: Vector3) -> float: return r.height_at(p.x, p.z)
	_lands(rig, slope + Vector3(0, 9, 0) + f.across * 6.0, slope, on_roof, "from the air down onto a pitched roof")
	_lands(rig, Terrain.ground(slope.x, slope.z) + f.across * (r.half_span() + 3.0) + Vector3.UP * 1.2, slope, on_roof, "from the ground up onto a pitched roof")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)


func _onto_a_tree(rig: Rig, world: World) -> void:
	var flora: Flora = main.flora_tool.flora
	world._order({"op": "plant", "kind": "tree", "seed": 4, "at": Terrain.ground(-20, 40)}, 1)
	flora.grow_now()
	var parts: Array = flora.placed("tree")[-1]
	var crown: Flora.Plant = parts[-1]
	var top: Vector3 = crown.xform.translated(Vector3.UP * Terrain.base_at(crown.anchor.x, crown.anchor.z)) * crown.pool.mesh.get_aabb().get_center()
	var from := top + Vector3(0, 6, 8)
	var hit: Dictionary = flora.solid_hit(from, (top - from).normalized(), 50.0)
	check(not hit.is_empty(), "a ray down at a tree's crown strikes it")
	var high := func(_p: Vector3) -> float: return hit.get("point", Vector3.ZERO).y
	_lands(rig, from, top, high, "down onto a tree")
	check(rig.global_position.y - Terrain.height_at(top.x, top.z) > 1.0, "the landing on a tree is up in it, not on the ground under it")


func _onto_a_wall_top(rig: Rig, world: World) -> void:
	world._order({"op": "wall", "walls": [_wall_data(PackedVector3Array([Terrain.ground(10, -30), Terrain.ground(16, -30)]))]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var mid := Terrain.ground(13, -30)
	var top := mid + Vector3.UP * (w.layout.height + WallLayout.CAP)
	var on_top := func(_p: Vector3) -> float: return top.y
	_lands(rig, top + Vector3(0, 5, 6), top, on_top, "down onto a wall's top")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)


## A ruined wall's face is its stones', each leaning a little and some standing proud of the one above: aims at it
## behave as at a plain wall's, at every height and all along it.
func _onto_a_wall_face(rig: Rig, world: World) -> void:
	var d := _wall_data(PackedVector3Array([Terrain.ground(-6, -14), Terrain.ground(6, -14)]))
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	for s: float in [2.0, 6.0, 10.0]:
		for up: float in [0.5, 1.45, 1.55, 2.2]:
			_onto_a_face(rig, w.layout.point_at(s), up)
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)
	d.top = WallLayout.Top.CAP
	d.ruins = PackedVector2Array([Vector2(8.5, 9.5)])
	world._order({"op": "wall", "walls": [d]}, 1)
	w = main.tool.walls[-1]
	w.lay_now()
	check(not w.layout.ruins.is_empty(), "the wall is ruined")
	for k in 13:
		for up: float in [0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4]:
			_onto_a_face(rig, w.layout.point_at(0.5 + k * 0.5), up)
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)


## Where a ruin steps down, each course's broken top is a ledge: a ray pointed at one, from above in front or behind,
## or from the ground in front, lands the player standing on it where it struck. Ledges are found by looking straight
## down every 2 cm along the wall, wherever the stone struck is flat for 4 cm either way.
func _onto_a_ruin_ledge(rig: Rig, world: World) -> void:
	for seed: int in [3, 8]:
		_onto_ruin_ledges(rig, world, seed)


func _onto_ruin_ledges(rig: Rig, world: World, seed: int) -> void:
	var d := _wall_data(PackedVector3Array([Terrain.ground(-6, -14), Terrain.ground(6, -14)]))
	d.top = WallLayout.Top.CAP
	d.seed = seed
	d.ruins = PackedVector2Array([Vector2(5.0, 6.5)])
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var l := w.layout
	var top_at := func(s: float) -> float:
		var hit: Dictionary = rig.solid_hit.call(l.frame_at(s).point + Vector3.UP * 20.0, Vector3.DOWN, 40.0)
		return hit.point.y if not hit.is_empty() else -INF
	var heights := {}
	var aims := 0
	var s := 2.0
	while s < 9.5:
		s += 0.02
		var foot: Vector3 = l.frame_at(s).point
		var top: float = top_at.call(s)
		var up := top - foot.y
		if up < 0.15 or up > l.height - 0.05 or absf(top_at.call(s - 0.04) - top) > 0.02 or absf(top_at.call(s + 0.04) - top) > 0.02:
			continue
		heights[snappedf(up, 0.3)] = true
		var ledge := Vector3(foot.x, top, foot.z)
		var normal: Vector3 = l.frame_at(s).tangent.cross(Vector3.UP)
		var froms: Array[Vector3] = [ledge + Vector3.UP * 2.5 + normal * 1.5, ledge + Vector3.UP * 2.5 - normal * 1.5]
		if up < 1.2:
			froms.append(Terrain.ground(foot.x + normal.x * 3.0, foot.z + normal.z * 3.0) + Vector3.UP * 1.6)
		for from in froms:
			var dir := (ledge - from).normalized()
			var struck: Dictionary = rig.solid_hit.call(from, dir, 20.0)
			var what := "at the ruin's ledge %.2f up at %.2f from %s" % [up, s, from]
			if struck.is_empty() or struck.point.distance_to(ledge) > 0.03:
				continue
			aims += 1
			rig.aim(_pose(from, dir))
			var g: Variant = rig.aim_ground
			check(g != null and rig.aim_lift < 0.01, "aimed %s, it has a landing on it: %s up %.2f" % [what, g, rig.aim_lift])
			if g == null:
				continue
			check(g.distance_to(struck.point) < 0.05, "aimed %s, the target is where it struck: %s for %s" % [what, g, struck.point])
			rig.place(g, rig.aim_lift)
			check(absf(rig.global_position.y - struck.point.y) < 0.05, "aimed %s, the player stands on it: %.2f for %.2f" % [what, rig.global_position.y, struck.point.y])
	check(heights.size() >= 6 and aims >= 60, "seed %d's ruin steps down through several heights, each pointed at: %d aims, heights %s" % [seed, aims, heights.keys()])
	print("ruin ledges, seed %d: %d aims, heights %s" % [seed, aims, heights.keys()])
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)


func _onto_a_raised_floor(rig: Rig, world: World) -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(30, 30), Terrain.ground(36, 30), 4.0)))
	d.closed = true
	d.rise = 1.5
	d.openings = PackedVector4Array([3.0].map(WallLayout.archway))
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(33, 30), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var level := w.layout.floor_y
	var inside := Vector3(33.5, level, 30.0)
	var on_floor := func(_p: Vector3) -> float: return level
	check(level > Terrain.height_at(inside.x, inside.z) + 1.0, "the raised house's floor stands over the ground: %.2f" % level)
	_lands(rig, Vector3(32.5, level + 1.6, 30.3), inside, on_floor, "down onto a raised house's floor from inside")
	check(is_equal_approx(main.tool.floor_under(inside + Vector3.UP * 0.5), level), "standing inside, the player stands on the floor, not the ground under it")
	var middle := Terrain.ground(33.0, 30.0)
	Ground.settle()
	check(Ground.laid_bare(middle.x, middle.z) > 0.99, "the meadow under the floor is worn bare: %.2f" % Ground.laid_bare(middle.x, middle.z))
	check(Ground.laid_bare(33.0, 30.0 + 2.0 + 1.0) < 0.01, "the meadow outside the walls is not")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)
	Ground.settle()
	check(Ground.laid_bare(middle.x, middle.z) < 0.01, "taken away, the house gives the meadow back")


func _on_a_wall_walk(rig: Rig, world: World) -> void:
	var d := _wall_data(PackedVector3Array([Terrain.ground(-6, -14), Terrain.ground(6, -14)]))
	d.top = WallLayout.Top.CAP
	d.ruins = PackedVector2Array([Vector2(8.5, 9.5)])
	world._order({"op": "wall", "walls": [d]}, 1)
	var w: Wall = main.tool.walls[-1]
	w.lay_now()
	var l := w.layout
	var mid := l.point_at(3.0)
	var top: float = rig.solid_hit.call(mid + Vector3.UP * 20.0, Vector3.DOWN, 40.0).point.y
	check(absf(top - (mid.y + l.height + WallLayout.CAP)) < 0.1, "the wall walk is the wall's cap: %.2f over a foot at %.2f" % [top, mid.y])
	var on_top := func(_p: Vector3) -> float: return top
	_lands(rig, Vector3(mid.x - 4, top + 5, mid.z + 6), mid + Vector3.UP * (top - mid.y), on_top, "down onto a wall walk")
	_hovers(rig, Vector3(mid.x, top, mid.z), top, "a wall walk")
	_stands(Vector3(mid.x, top, mid.z), Flat.STEP_UP, top, "walking along a wall walk, the next step")
	_stands(Vector3(mid.x, top, mid.z + WallLayout.THICKNESS * 0.5 + 0.1), 0.5, Terrain.height_at(mid.x, mid.z + WallLayout.THICKNESS * 0.5 + 0.1), "a step off the wall walk's side")
	_stands(Vector3(mid.x, top - 1.0, mid.z), 0.0, Terrain.height_at(mid.x, mid.z), "a point inside the wall, under its walk,")
	var gap := l.point_at(9.0)
	check(l.standing(9.0) == 0.0, "the ruin breaks the wall to the ground at its middle")
	_stands(gap + Vector3.UP * top, 0.0, Terrain.height_at(gap.x, gap.z), "over a ruin's gap, a point")
	var at := 8.5
	while at > 6.0 and not (l.standing(at) > 0.0 and l.standing(at) < l.height):
		at -= 0.05
	var stepped := l.standing(at)
	check(stepped > 0.0 and stepped < l.height, "the ruin's end steps down: %.2f at %.2f" % [stepped, at])
	var step := l.point_at(at)
	_stands(step, stepped + 0.5, step.y + stepped, "a point over a ruin's stepped end")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)
	var coped := _wall_data(PackedVector3Array([Terrain.ground(-6, -18), Terrain.ground(6, -18)]))
	coped.top = WallLayout.Top.COPE
	world._order({"op": "wall", "walls": [coped]}, 1)
	w = main.tool.walls[-1]
	w.lay_now()
	var over := w.layout.point_at(3.0)
	var stones := w.layout.stones.filter(func(st: Dictionary) -> bool: return st.kind == "cope" and Vector2(st.xform.origin.x - over.x, st.xform.origin.z - over.z).length() < 0.3)
	var tallest: float = stones.map(func(st: Dictionary) -> float: return st.xform.origin.y + st.xform.basis.y.length() * 0.5).max()
	var coping: float = rig.solid_hit.call(over + Vector3.UP * 20.0, Vector3.DOWN, 40.0).point.y
	check(absf(coping - tallest) < 0.1, "a ray lands on a coping's tall stones: %.2f for %.2f" % [coping, tallest])
	_stands(over + Vector3.UP * (coping - over.y), 0.3, coping, "a point over a coped wall's walk")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)
	var house := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-4, -6), Terrain.ground(2, -6), 4.0)))
	house.closed = true
	house.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(-1, -6), "radius": 2.0, "pitch": 1.6, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [house]}, 1)
	w = main.tool.walls[-1]
	w.lay_now()
	var corner: Vector3 = w.layout.points[0]
	var side: Vector3 = w.layout.points[1]
	var along := corner.lerp(side, 0.5)
	check(w.layout.walk_under(along + Vector3.UP * (w.layout.height + 1.0)) == -INF, "a house's walls under its roof are no wall walk")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])}, 1)


## Aims from 6 m out at the wall's face `up` metres over the floor in front of `mid`: struck within 1.5 m of that floor,
## the player lands on that floor; higher, they float at the height struck. Either way clear of the face.
func _onto_a_face(rig: Rig, mid: Vector3, up: float) -> void:
	var face := mid + Vector3(0, 0, WallLayout.THICKNESS * 0.5)
	var front := Terrain.ground(face.x, face.z + Rig.STAND_OFF)
	var from := Vector3(face.x, front.y + 1.6, face.z + 6.0)
	var dir := (Vector3(face.x, front.y + up, face.z) - from).normalized()
	var struck: Variant = rig.solid_hit.call(from, dir, 20.0).get("point")
	rig.aim(_pose(from, dir))
	var g: Variant = rig.aim_ground
	check(struck != null and g != null, "a ray %.2f m up the wall's face strikes it and has a target" % up)
	if struck == null or g == null:
		return
	var floor_y := Terrain.height_at(g.x, g.z)
	var high: bool = struck.y - floor_y > Rig.CLIMB
	check(high == (up > Rig.CLIMB), "aimed %.2f m up the face, it is struck %.2f m over the floor in front" % [up, struck.y - floor_y])
	check(absf(g.y - floor_y) < 0.05, "aimed %.2f m up the face, the target stands over the floor in front: %s" % [up, g])
	var at: float = g.y + rig.aim_lift
	if high:
		check(absf(at - struck.y) < 0.05, "aimed %.2f m up the face, the player floats where it struck: %.2f for %.2f" % [up, at, struck.y])
	else:
		check(rig.aim_lift < 0.01, "aimed %.2f m up the face, the player lands at its foot, not on the face: up %.2f" % [up, rig.aim_lift])
	check(g.z - struck.z > Rig.STAND_OFF * 0.99 and struck.z - mid.z > WallLayout.THICKNESS * 0.3, "aimed %.2f m up the face, the target stands clear of it: %s, struck at %s" % [up, g, struck])
	rig.place(g, rig.aim_lift)
	check(absf(rig.global_position.y - at) < 0.01, "let go aimed %.2f m up the face, the player is where the halo showed: %.2f for %.2f" % [up, rig.global_position.y, at])


func _on_flat_roofs_and_platforms(rig: Rig, world: World) -> void:
	var tool: WallTool = main.tool
	var at := Terrain.ground(-6, -26)
	var stance := WallTool.stance(at, 0.0)
	stance.size = Vector2(8, 6)
	stance.pitch = 0.0
	tool.build([tool.new_house(stance)])
	var below: Wall = tool.walls[-1]
	below.lay_now()
	stance.size = Vector2(4, 3)
	tool.build([tool.new_house(stance, PackedInt32Array([below.id]))])
	var above: Wall = tool.walls[-1]
	above.lay_now()
	var deck := below.roof.base
	var upper := above.roof.base
	check(below.roof.flat() and above.roof.flat() and upper > deck + 2.0, "a platform stands on a flat roof: decks at %.2f and %.2f" % [deck, upper])
	var terrace := Vector3(at.x + 3.2, deck, at.z)
	var on_deck := func(_p: Vector3) -> float: return deck
	var on_upper := func(_p: Vector3) -> float: return upper
	_lands(rig, terrace + Vector3(6, 5, 0), terrace, on_deck, "down onto a flat roof's terrace")
	_hovers(rig, terrace, deck, "a flat roof")
	_lands(rig, Vector3(at.x, upper, at.z) + Vector3(0, 6, 5), Vector3(at.x, upper, at.z), on_upper, "down onto a platform stacked on the flat roof")
	_hovers(rig, Vector3(at.x, upper, at.z), upper, "a platform")
	_stands(terrace, 0.5, deck, "a point over the terrace")
	check(above.layout.floor_y != -INF, "the platform has its floor")
	_stands(Vector3(at.x + 1.0, deck, at.z), 1.0, above.layout.floor_y, "a point inside the platform's room")
	world._order({"op": "take", "of": "walls", "ids": PackedInt32Array([above.id, below.id])}, 1)


func _on_stairs_and_a_bridge(rig: Rig, world: World) -> void:
	var left := _wall_data(PackedVector3Array([Terrain.ground(-4, -4), Terrain.ground(-4, 3)]))
	var right := _wall_data(PackedVector3Array([Terrain.ground(3, -4), Terrain.ground(3, 3)]))
	left.top = WallLayout.Top.CAP
	right.top = WallLayout.Top.CAP
	world._order({"op": "wall", "walls": [left, right]}, 1)
	var walls: Array = main.tool.walls.slice(-2)
	var ids := PackedInt32Array()
	var tops: Array[float] = []
	for w: Wall in walls:
		w.lay_now()
		ids.append(w.id)
		var on := w.layout.point_at(3.5)
		tops.append(rig.solid_hit.call(on + Vector3.UP * 20.0, Vector3.DOWN, 40.0).point.y)
	var deck := maxf(tops[0], tops[1])
	var bridge := {"a": Vector3(-4, deck, -0.5), "b": Vector3(3, deck, -0.5), "width": 1.2, "rail": "wood", "seed": 5, "paint": Palette.plain(), "on": ids}
	var foot := Terrain.ground(-9, 1.5)
	var flight := {"a": foot, "b": Vector3(-4, tops[0], 1.5), "width": 1.2, "rail": "stone", "seed": 6, "paint": Palette.plain(), "on": PackedInt32Array([ids[0]])}
	world._order({"op": "stairs", "stairs": bridge}, 1)
	world._order({"op": "stairs", "stairs": flight}, 1)
	var keys: Array = world.stairs.layouts.keys()
	var span: StairLayout = world.stairs.layouts[keys[-2]]
	var steps: StairLayout = world.stairs.layouts[keys[-1]]
	check(span.kind == StairLayout.Kind.LANDING and steps.kind == StairLayout.Kind.FLIGHT, "a level run between two wall tops is a bridge, a rising one a flight")
	var middle := Vector3(-0.5, deck, -0.5)
	var on_bridge := func(_p: Vector3) -> float: return deck
	_lands(rig, middle + Vector3(0, 5, 5), middle, on_bridge, "down onto a bridge between two wall walks")
	_hovers(rig, middle, deck, "a bridge")
	_stands(middle, -1.0, Terrain.height_at(middle.x, middle.z), "a point under the bridge")
	var tread := foot.lerp(flight.b, 0.5)
	var tread_y := steps.surface(tread + Vector3.UP)
	check(not is_nan(tread_y), "the flight has a tread halfway up")
	var on_tread := func(_p: Vector3) -> float: return tread_y
	_lands(rig, Vector3(tread.x + 5, tread_y + 4, tread.z), Vector3(tread.x, tread_y, tread.z), on_tread, "down onto a flight's tread")
	_hovers(rig, Vector3(tread.x, tread_y, tread.z), tread_y, "a flight of stairs")
	var walk := Terrain.ground(3, 2)
	var far_top: float = rig.solid_hit.call(walk + Vector3.UP * 20.0, Vector3.DOWN, 40.0).point.y
	_hovers(rig, Vector3(walk.x, far_top, walk.z), far_top, "the far wall walk the bridge reaches")
	world._order({"op": "take", "of": "walls", "ids": ids}, 1)
	check(world.stairs.layouts.size() == keys.size() - 2, "taking the walls away takes the stairs standing on them")
