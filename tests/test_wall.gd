extends "res://../tests/support/suite.gd"

## Headless checks of the wall layout: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wall.gd


func _init() -> void:
	_straight_wall_fills_its_length()
	_arch_ring_closes_over_the_opening()
	_arch_meets_its_wall_with_no_gap()
	_a_grand_arch_is_a_doorway_arch_scaled()
	_an_arch_grows_up_to_the_wall_top()
	_doors_and_windows_scale_from_where_they_stand()
	_short_or_low_walls_take_no_arch()
	_layout_is_deterministic()
	_a_copy_built_elsewhere_lays_the_same_stones()
	_raising_the_wall_adds_courses()
	_point_at_follows_the_curve()
	_a_long_wall_splits_by_the_ground_under_each_stone()
	_stone_faces_share_their_borders()
	_settled_chunks_draw_far_stones_and_stop_ivy_at_its_reach()
	_far_stones_draw_by_coarse_chunks()
	_far_pieces_reach_the_near_pieces_faces()
	_full_stones_stand_only_near_the_eye()
	_a_changing_wall_draws_far_stones_by_its_own_chunks()
	_grown_ivy_moves_to_the_glade_in_one_frame()
	_a_chunk_draws_again_only_the_pieces_that_changed()
	_a_wall_over_water_stands_on_its_bed()
	_a_narrow_crossing_takes_one_arch()
	_a_low_wall_crosses_as_a_causeway()
	_ducks_pass_only_under_arches()
	_a_path_arch_beside_a_pond_stays_open()
	_water_leaves_the_dry_stones_as_they_were()
	_mortar_stops_short_of_a_doorway_and_the_ends()
	_a_drawn_bend_is_a_corner()
	finish()


func _blocks(w: WallLayout) -> Array:
	return w.stones.filter(func(s): return s.kind == "block")


func _straight_wall_fills_its_length() -> void:
	var w := straight_wall(6.0, 2.4, [])
	check(absf(w.length() - 6.0) < 0.01, "length %f" % w.length())
	var courses := int(round(2.4 / WallLayout.COURSE))
	for k in courses:
		var covered := 0.0
		for s in _blocks(w):
			if absf(s.y - (k + 0.5) * 2.4 / courses) < 0.01:
				covered += s.size.x
		check(absf(covered - 6.0) < 0.02, "course %d covers %f of 6 m" % [k, covered])
	check(w.stones.any(func(s): return s.kind == "merlon"), "a crenellated top")
	check(w.stones.filter(func(s): return s.kind == "pier").size() >= 4, "piers at both ends")


func _arch_ring_closes_over_the_opening() -> void:
	var w := straight_wall(8.0, 2.7, [4.0])
	var ring := w.stones.filter(func(s): return s.kind == "voussoir")
	check(ring.size() == 10, "10 voussoirs, got %d" % ring.size())
	check(w.stones.filter(func(s): return s.kind == "keystone").size() == 1, "one keystone")
	for s in ring:
		var r := Vector2(s.s - 4.0, s.y - w.spring()).length()
		check(absf(r - (WallLayout.ARCH_HALF + WallLayout.RING * 0.5)) < 0.05, "voussoir off the ring: r=%f" % r)


## Across every style, height and stretch, every point of the wall's middle plane round an arch is either in its
## opening and clear, or covered by a piece of the wall or the arch; points within 3 cm of the opening's edge are
## its soffit's facets. Under the springing of a style with no posts the jamb is the wall's own reveal, where the
## mortar stands JOINT back between courses as at every open end.
func _arch_meets_its_wall_with_no_gap() -> void:
	var walls: Array[WallLayout] = []
	for style in ["stone", "plaster", "timber"]:
		for height in [2.3, 2.6, 3.1, 4.5]:
			for stretch in [5.0, 9.0]:
				var w := WallLayout.new()
				if style == "timber":
					w.points = WallLayout.rectangle(Vector3.ZERO, Vector3(stretch, 0, 0), 5.0)
					w.closed = true
				else:
					w.points = [Vector3(0, 0, 0), Vector3(stretch, 0, 0)]
				w.openings.assign([stretch * 0.5].map(WallLayout.archway))
				w.finish = {"stone": WallLayout.Finish.BARE, "plaster": WallLayout.Finish.PLASTER, "timber": WallLayout.Finish.TIMBER}[style]
				w.height = height
				walls.append(w)
	var arc := WallLayout.new()
	for i in 9:
		arc.points.append(Vector3(cos(i / 8.0 * PI) * 5.0, 0.0, sin(i / 8.0 * PI) * 5.0))
	arc.height = 3.0
	arc.finish = WallLayout.Finish.PLASTER
	arc.build(Terrain.flat)
	arc.openings.assign([arc.length() * 0.5].map(WallLayout.archway))
	walls.append(arc)
	for style in ["stone", "plaster", "timber"]:
		var grand := WallLayout.new()
		if style == "timber":
			grand.points = WallLayout.rectangle(Vector3.ZERO, Vector3(12, 0, 0), 5.0)
			grand.closed = true
		else:
			grand.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
		grand.openings.assign([WallLayout.archway(6.0, 2.5)])
		grand.finish = {"stone": WallLayout.Finish.BARE, "plaster": WallLayout.Finish.PLASTER, "timber": WallLayout.Finish.TIMBER}[style]
		grand.height = 6.3
		walls.append(grand)
	for w in walls:
		w.build(Terrain.flat)
		check(w.archways().size() == 1, "%s wall %.1f m high opens its arch" % [w.arch_style().name, w.height])
		if w.archways().is_empty():
			continue
		var a: float = w.archways()[0]
		var k: float = w.apertures.filter(func(o): return o.style == WallLayout.DoorStyle.ARCHWAY)[0].size
		var near := w.stones.filter(func(st: Dictionary) -> bool: return absf(w.offset(st.s, a)) < 1.6 * k + 1.5)
		var gaps := []
		var blocked := []
		var y := 0.05
		while y < w.height - 0.05:
			var d := -1.6 * k
			while d <= 1.6 * k:
				var inner := w.opening(y + 0.03, false, k)
				var edge := maxf(w.opening(y - 0.03, false, k), w.opening(y + 0.03, false, k)) + 0.03
				# A timber arch's jambs stand on the foot course, whose joints show at the reveal under them as a stone arch's do.
				var jamb: float = w.arch_style().jamb * k if y < w.course_height() else 0.0
				var reveal: bool = y < w.spring(k) and (w.arch_style().jamb == 0.0 or jamb > 0.0) and absf(d) < WallLayout.ARCH_HALF * k + jamb + WallLayout.JOINT + 0.02
				var p: Vector3 = w.frame_at(a + d).point + Vector3.UP * y
				var hit := near.any(func(st: Dictionary) -> bool:
					return _holds(st, p))
				if absf(d) < inner - 0.03 and hit:
					blocked.append(Vector2(d, y))
				elif absf(d) > edge and not reveal and not hit:
					gaps.append(Vector2(d, y))
				d += 0.04
			y += 0.04
		var name := "%s wall %.1f m high, %.1f m long, arch %.1f" % [w.arch_style().name, w.height, w.length(), k]
		check(gaps.is_empty(), "%s: gaps between arch and wall at %s" % [name, gaps.slice(0, 8)])
		check(blocked.is_empty(), "%s: pieces in the opening at %s" % [name, blocked.slice(0, 8)])
		var styled := w.stones.filter(func(st: Dictionary) -> bool: return st.kind == w.arch_style().kind and absf(w.offset(st.s, a)) < 1.2 * k and st.y < w.spring(k) + 1.2 * k)
		check(not styled.is_empty(), "%s: the arch is laid in %s" % [name, w.arch_style().kind])
		if w.arch_style().name == "timber":
			check(not w.stones.any(func(st: Dictionary) -> bool: return st.kind in ["voussoir", "keystone"]), "%s: no stone in a timber frame's arch" % name)

		if w.height < WallLayout.DOOR_TALL + w.course_height() * 1.4 or k != 1.0:
			continue
		var door := w.inputs()
		door.openings = [Vector4(a, 0.0, WallLayout.DoorStyle.PLAIN, 1)]
		door.build(Terrain.flat)
		check(door.apertures.size() == 1 and door.apertures[0].door, "%s: the same opening list takes a door" % name)
		if door.apertures.is_empty():
			continue
		var o := door.apertures[0]
		gaps.clear()
		y = 0.05
		while y < door.height - 0.05:
			var d := -1.6
			while d <= 1.6:
				# The jamb exposes course joints; above the lintel the wall must cover the whole band.
				if absf(d) > o.half + WallLayout.JOINT + 0.03 or y > o.head + door.course_height() + 0.03:
					var p: Vector3 = door.frame_at(a + d).point + Vector3.UP * y
					if not door.stones.any(func(st: Dictionary) -> bool:
						return _holds(st, p)):
						gaps.append(Vector2(d, y))
				d += 0.04
			y += 0.04
		check(gaps.is_empty(), "%s: gaps between door and wall at %s" % [name, gaps.slice(0, 8)])


## An arch of any size is the doorway's, scaled: its opening, its ring of voussoirs and its keystone, under the top,
## every one a wedge whose joints run through the arch's centre.
func _a_grand_arch_is_a_doorway_arch_scaled() -> void:
	for k in [WallLayout.MIN_SIZE, 1.0, 2.0, 3.5]:
		var w := WallLayout.new()
		w.points = [Vector3(0, 0, 0), Vector3(16, 0, 0)]
		w.height = 6.0
		w.openings.assign([WallLayout.archway(8.0, k)])
		w.build(Terrain.flat)
		check(w.apertures.size() == 1 and is_equal_approx(w.apertures[0].half, WallLayout.ARCH_HALF * k), "an arch of size %.1f opens %.2f m wide: %s" % [k, WallLayout.ARCH_HALF * k * 2.0, w.apertures])
		if w.apertures.size() != 1:
			continue
		var ring := w.stones.filter(func(st): return st.kind == "voussoir")
		check(ring.size() == 10, "size %.1f: 10 voussoirs, got %d" % [k, ring.size()])
		for st in ring:
			var r := Vector2(st.s - 8.0, st.y - w.spring(k)).length()
			check(absf(r - (WallLayout.ARCH_HALF + WallLayout.RING * 0.5) * k) < 0.05 * k, "size %.1f: voussoir off its ring: r=%f" % [k, r])
		var key := w.stones.filter(func(st): return st.kind == "keystone")
		check(key.size() == 1 and key[0].y > w.apertures[0].head - WallLayout.RING * k, "size %.1f: its keystone closes the head" % k)
		for st in ring + key:
			var miss := _joint_miss(st, Vector2(8.0, w.spring(k) + st.xform.origin.y - st.y))
			check(miss < 0.01, "size %.1f: a %s's joints run %.3f m wide of the arch's centre" % [k, st.kind, miss])
		check(w.apertures[0].head <= w.height - 0.3 + 0.01, "size %.1f: its ring stays under the top" % k)


## Whether `p` lies in laid piece `st` as it is drawn, its ends cut as WallLayout.drawn_corners cuts them.
func _holds(st: Dictionary, p: Vector3) -> bool:
	var x: Transform3D = st.xform
	var q := x.affine_inverse() * p
	var e: Vector2 = st.get("ends", Vector2.ZERO)
	var axis := x.basis.y.normalized()
	q.x -= q.z * x.basis.z.length() * tan(e.x if q.x < 0.0 else e.y) / (x.basis.x - axis * x.basis.x.dot(axis)).length()
	return absf(q.x) <= 0.5 and absf(q.y) <= 0.5 and absf(q.z) <= 0.5


## How far wide of `centre`, in the plane of a wall along x, the farther of a wedge's two joint lines runs, as the stone
## shader cuts its ends (`ends`, turning about its local y), where its faces stop standing full and the next wedge's meet.
func _joint_miss(st: Dictionary, centre: Vector2) -> float:
	var x: Transform3D = st.xform
	var e: Vector2 = st.get("ends", Vector2.ZERO)
	var miss := 0.0
	for side in [-1.0, 1.0]:
		var p: Vector3 = x.origin + x.basis.x * 0.5 * WallLayout.MEET * side
		var d: Vector3 = x.basis.z + x.basis.x.normalized() * x.basis.z.length() * tan(e.x if side < 0.0 else e.y)
		var along := Vector2(d.x, d.y).normalized()
		var to := centre - Vector2(p.x, p.y)
		miss = maxf(miss, absf(to.x * along.y - to.y * along.x))
	return miss


## The largest arch that opens reaches up to the wall's top, ring and all, however tall the wall: a grand arch is
## only a matter of a wall tall enough.
func _an_arch_grows_up_to_the_wall_top() -> void:
	for height in [3.0, 6.0, 9.0]:
		var w := WallLayout.new()
		w.points = [Vector3(0, 0, 0), Vector3(40, 0, 0)]
		w.height = height
		w.build(Terrain.flat)
		var placed: Array[Vector4] = []
		var k := 1.0
		while w.opening_fits(WallLayout.archway(20.0, k + 0.05), placed):
			k += 0.05
		var head: float = w.opening_for(WallLayout.archway(20.0, k)).head
		check(k > 1.0 and head > height - 0.3 - 0.1, "on a wall %.1f m high an arch grows to size %.2f, its ring %.2f m up" % [height, k, head])


## A door or window of any size stands where it was placed, grown up from its sill: still a window, still a door.
func _doors_and_windows_scale_from_where_they_stand() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(14, 0, 0)]
	w.height = 6.0
	w.openings.assign([Vector4(3.0, 0.5, WallLayout.DoorStyle.PLAIN, 1.5), Vector4(9.0, 2.0, WallLayout.DoorStyle.PLAIN, 2.0)])
	w.build(Terrain.flat)
	var c := w.course_height()
	var unit := w.opening_for(Vector4(9.0, 2.0, WallLayout.DoorStyle.PLAIN, 1.0))
	check(w.apertures.size() == 2, "a big door and a big window both open: %s" % [w.apertures])
	if w.apertures.size() != 2:
		return
	var door := w.apertures[0]
	var window := w.apertures[1]
	check(door.door and is_equal_approx(door.half, WallLayout.DOOR_HALF * 1.5) and is_equal_approx(door.head, roundf(WallLayout.DOOR_TALL * 1.5 / c) * c), "the door is half again as wide and tall: %s" % door)
	check(not window.door and is_equal_approx(window.sill, unit.sill) and is_equal_approx(window.half, WallLayout.WINDOW_HALF * 2.0) and window.head - window.sill > (unit.head - unit.sill) * 1.8, "the window keeps its sill and doubles: %s" % window)
	check(w.stones.any(func(st): return st.kind == "lintel" and absf(st.s - 9.0) < 0.1 and st.size.x > WallLayout.WINDOW_HALF * 4.0), "its lintel spans it")


func _short_or_low_walls_take_no_arch() -> void:
	check(straight_wall(1.5, 2.7, [0.75]).stones.all(func(s): return s.kind != "voussoir"), "a 1.5 m wall has no room for an arch")
	check(straight_wall(8.0, 1.2, [4.0]).stones.all(func(s): return s.kind != "voussoir"), "a 1.2 m wall is too low for an arch")


func _layout_is_deterministic() -> void:
	var a := straight_wall(7.0, 2.4, [3.5])
	var b := straight_wall(7.0, 2.4, [3.5])
	check(a.stones == b.stones, "identical builds lay identical stones")


func _a_copy_built_elsewhere_lays_the_same_stones() -> void:
	var loop := WallLayout.new()
	loop.points = [Vector3(0, 0, 0), Vector3(4, 0, 2), Vector3(8, 0, 0), Vector3(5, 0, -3)]
	loop.closed = true
	loop.height = 3.3
	loop.top = WallLayout.Top.CAP
	loop.cover = WallLayout.Cover.ROOF
	loop.seed = 9
	loop.openings.assign([16.1].map(WallLayout.archway))
	loop.openings.append_array([Vector4(2.2, 1.4, 0, 1)])
	loop.lanterns.assign([Vector3(7.0, 1.8, 1.0)])
	var flagged := WallLayout.new()
	flagged.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	flagged.flags.assign([6.0])
	var fence := WallLayout.new()
	fence.points = [Vector3(0, 0, 0), Vector3(6, 0, 1)]
	fence.fence = true
	for a: WallLayout in [loop, flagged, fence]:
		a.build(Terrain.flat)
		var copy := a.inputs()
		copy.build(Terrain.flat)
		var b := WallLayout.new()
		b.adopt(copy)
		check(b.stones.size() == a.stones.size() and b.archways() == a.archways() and b.samples == a.samples and b.apertures.size() == a.apertures.size() and b.flames == a.flames and b.cloths.size() == a.cloths.size(), "a copy's build matches: %d vs %d stones" % [b.stones.size(), a.stones.size()])
		for i in mini(a.stones.size(), b.stones.size()):
			if not a.stones[i].xform.is_equal_approx(b.stones[i].xform) or a.stones[i].kind != b.stones[i].kind:
				check(false, "stone %d differs in the copy's build" % i)
				break
	check(loop.archways().size() == 1 and not loop.apertures.is_empty() and not loop.flames.is_empty(), "the loop opens its arch and window and hangs its lantern")
	check(not flagged.cloths.is_empty(), "the flag flies")


func _raising_the_wall_adds_courses() -> void:
	var low := straight_wall(5.0, 1.8, [])
	var high := straight_wall(5.0, 3.6, [])
	var top := func(w: WallLayout) -> float:
		var m := 0.0
		for s in w.stones:
			m = maxf(m, s.y + s.size.y * 0.5)
		return m
	check(top.call(high) > top.call(low) + 1.5, "raising 1.8 m adds height")
	check(_blocks(high).size() > _blocks(low).size() * 1.6, "raising adds courses of stone")


func _point_at_follows_the_curve() -> void:
	var w := straight_wall(6.0, 2.4, [])
	check(w.point_at(3.0).distance_to(Vector3(3, -0.12, 0)) < WallLayout.SAMPLE * 2.0, "point_at(3) is %s" % w.point_at(3.0))
	check(w.point_at(99.0) == w.samples[-1], "point_at past the end is the end")


func _a_long_wall_splits_by_the_ground_under_each_stone() -> void:
	var stone := Wall.kinds()[Wall.Part.STONE]
	var w := straight_wall(40.0, 1.5, [])
	var packed := Wall.pack(w, Wall.kinds(), Palette.plain())
	var chunks: Dictionary = packed.chunks[Wall.Part.STONE]
	check(chunks.size() >= 3, "a 40 m wall spans at least three chunks, got %d" % chunks.size())
	var total := 0
	for key in chunks:
		var buf: PackedFloat32Array = chunks[key]
		total += buf.size()
		for i in range(0, buf.size(), stone.stride()):
			var at := Vector2i(floori(buf[i + 3] / stone.cell()), floori(buf[i + 11] / stone.cell()))
			if at != key:
				check(false, "a stone at %s sits in chunk %s" % [at, key])
				return
	check(total == packed.stone.size(), "every stone in exactly one chunk")


func _stone_faces_share_their_borders() -> void:
	for segments in [1, 2, 3]:
		var mesh := Meshes.rounded_box(0.14, segments, 100)
		var a := mesh.surface_get_arrays(0)
		var points := func(n: int) -> int: return 6 * (n + 1) * (n + 1) - 12 * (n + 1) + 8
		var lod: bool = segments > Meshes.LOD_SEGMENTS
		var expected: int = points.call(segments) + (points.call(Meshes.LOD_SEGMENTS) if lod else 0)
		check(a[Mesh.ARRAY_VERTEX].size() == expected, "%d segments: one vertex per lattice point, got %d" % [segments, a[Mesh.ARRAY_VERTEX].size()])
		check(a[Mesh.ARRAY_INDEX].size() == 36 * segments * segments, "%d segments: every face's triangles" % segments)
		var lods: Array = RenderingServer.mesh_get_surface(mesh.get_rid(), 0).get("lods", [])
		check(lods.size() == (1 if lod else 0), "%d segments: %d levels of detail" % [segments, lods.size()])
		if lod:
			var error: float = lods[0].edge_length
			check(error > 0.0 and error < 0.05, "%d segments: the coarse lattice strays %.4f, under a twentieth of the stone" % [segments, error])


func _settled_chunks_draw_far_stones_and_stop_ivy_at_its_reach() -> void:
	var ks := Wall.kinds()
	var m := Masonry.new(ks)
	var parts: Array[Dictionary] = []
	for k in ks.size():
		var buf := PackedFloat32Array()
		buf.resize(ks[k].stride() * 2)
		buf[3] = 1.0
		buf[ks[k].stride() + 3] = 40.0
		parts.append(Masonry.split(buf, ks[k]))
	m.place(1, parts)
	var stones := m._chunks.keys().filter(func(key: Vector3i) -> bool: return key.z == Wall.Part.STONE)
	check(stones.size() == 2, "stones 39 m apart stand in two chunks")
	for key: Vector3i in m._chunks:
		var c: Masonry.Chunk = m._chunks[key]
		match key.z:
			Wall.Part.STONE:
				check(c.far != null and c.far.multimesh.mesh == Stones.far_mesh(), "a chunk draws far stones with the far mesh")
				check(c.far.multimesh.instance_count == 0 and c.instance.multimesh.instance_count == 0, "nothing drawn before the chunk is processed")
				check(is_equal_approx(c.instance.visibility_range_end, ks[Wall.Part.STONE].near + ks[Wall.Part.STONE].radius()) and is_equal_approx(c.far.visibility_range_begin, c.instance.visibility_range_end), "near and far stones meet at the near distance")
			Wall.Part.IVY:
				check(is_equal_approx(c.instance.visibility_range_end, ks[Wall.Part.IVY].reach + ks[Wall.Part.IVY].radius()), "ivy stops at its reach")
			Wall.Part.MORTAR:
				check(c.far == null and c.instance.visibility_range_end == 0.0, "mortar has no far mesh and no limit")
	check(ks[Wall.Part.STONE].cell() < ks[Wall.Part.MORTAR].cell(), "what is cut by distance stands in finer chunks than what is drawn at every distance")
	m._process(0.0)
	for key in stones:
		var c: Masonry.Chunk = m._chunks[key]
		check(c.instance.multimesh.instance_count == 1 and c.far.multimesh.instance_count == 1, "near and far hold the chunk's one stone")
	m.place(1, parts)
	m.remove(1)
	m._process(0.0)
	for c: Masonry.Chunk in m._chunks.values():
		check(c.instance.multimesh.instance_count == 0, "a removed owner leaves every chunk it stood in")
	m.free()


## From afar the far stones of every 8 m chunk in a 16 m one draw as one; nearer, each chunk's own near or far stones
## draw instead, never both.
func _far_stones_draw_by_coarse_chunks() -> void:
	var ks := Wall.kinds()
	var stone := ks[Wall.Part.STONE]
	var m := Masonry.new(ks)
	root.add_child(m)
	var buf := PackedFloat32Array()
	buf.resize(stone.stride() * 3)
	for i in 3:
		buf[i * stone.stride() + 3] = [1.0, 9.0, 17.0][i]
	var parts: Array[Dictionary] = []
	for k in ks.size():
		parts.append(Masonry.split(buf, stone) if k == Wall.Part.STONE else {})
	m.place(1, parts)
	m._process(0.0)
	check(m._chunks.size() == 3 and m._coarse.size() == 2, "three 8 m chunks under two 16 m ones, got %d and %d" % [m._chunks.size(), m._coarse.size()])
	var coarse: MultiMeshInstance3D = m._coarse.get(Vector3i(0, 0, Wall.Part.STONE))
	check(coarse != null and coarse.multimesh.instance_count == 2 and coarse.multimesh.mesh == Stones.far_mesh(), "the 16 m chunk draws both its 8 m chunks' stones far")
	check(is_equal_approx(coarse.visibility_range_begin, stone.near + Masonry.radius(Masonry.COARSE)), "once the whole 16 m chunk is past the near distance")
	for x in [0, 1]:
		var c: Masonry.Chunk = m._chunks[Vector3i(x, 0, Wall.Part.STONE)]
		check(c.far.get_node(c.far.visibility_parent) == coarse and c.instance.get_node(c.instance.visibility_parent) == coarse, "chunk %d draws only while its 16 m chunk does not" % x)
	m.free()


## Neighbouring pieces meet face to face, so a far mesh whose faces stand inside its near mesh's opens gaps between
## them past the near distance: boards and tiles show what is behind them.
func _far_pieces_reach_the_near_pieces_faces() -> void:
	for k in Wall.kinds():
		if k.far == null:
			continue
		var near: PackedVector3Array = k.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = k.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		var far: PackedVector3Array = k.far.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
			var face := 0.0
			var n := 0
			for i in near.size():
				if normals[i].dot(axis) > 0.999:
					face += near[i].dot(axis)
					n += 1
			var reach := -INF
			for v in far:
				reach = maxf(reach, v.dot(axis))
			check(n > 0 and reach >= face / n - 0.01, "the far mesh reaches the near face toward %s: %.3f, near %.3f" % [axis, reach, face / maxi(n, 1)])


## A wall still changing, as one over a hill being pulled, draws its own chunks, far ones in coarse stones, and
## hands them to the glade once it settles. A fence, so no ivy grows: a wall freed with its ivy laid crashes the engine
## at exit.
func _a_changing_wall_draws_far_stones_by_its_own_chunks() -> void:
	var glade := Masonry.new(Wall.kinds())
	root.add_child(glade)
	var w := Wall.new(1, glade)
	root.add_child(w)
	w.layout.points = [Vector3(0, 0, 0), Vector3(30, 0, 0)]
	w.layout.height = 2.0
	w.layout.fence = true
	w.rebuild(false)
	w.lay_now()
	var id := w.get_instance_id()
	check(w._drawn != null and w._drawn._owners.has(id) and not glade._owners.has(id), "a changing wall draws its own pieces")
	if w._drawn != null:
		var stones := w._drawn._chunks.keys().filter(func(key: Vector3i) -> bool: return key.z == Wall.Part.STONE)
		check(stones.size() >= 4, "by the ground chunk under each, got %d chunks" % stones.size())
		for key in stones:
			var far: MultiMeshInstance3D = w._drawn._chunks[key].far
			check(far != null and far.multimesh.mesh == Stones.far_mesh() and is_equal_approx(far.visibility_range_begin, Wall.kinds()[Wall.Part.STONE].near + Wall.kinds()[Wall.Part.STONE].radius()), "beyond the near distance in coarse stones")
	w.finished = true
	w.rebuild(true)
	w.lay_now()
	check(glade._owners.has(id) and w._drawn == null, "once settled the glade draws them, and the wall's own Masonry goes")
	w.free()
	glade.free()


## Ivy that finishes growing leaves the wall's own instance for the glade's chunks in the frame it stops, so it never
## blinks out for the frame before the glade next processes.
func _grown_ivy_moves_to_the_glade_in_one_frame() -> void:
	var glade := Masonry.new(Wall.kinds())
	root.add_child(glade)
	var w := Wall.new(1, glade)
	root.add_child(w)
	w.layout.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	w.layout.height = 2.4
	w.finished = true
	w.rebuild(true)
	w.lay_now()
	while not WorkerThreadPool.is_task_completed(w._ivy_task):
		OS.delay_msec(1)
	w._process(0.0)
	check(w._ivy != null and w._ivy.multimesh.instance_count > 0, "growing ivy is drawn by its wall")
	w.ivy_age = INF
	w._process(0.0)
	var leaves := 0
	for key: Vector3i in glade._chunks:
		if key.z == Wall.Part.IVY:
			leaves += glade._chunks[key].instance.multimesh.instance_count
	check(w._ivy.multimesh.instance_count == 0 and leaves > 0, "grown ivy is drawn by the glade the frame its wall lets it go, got %d leaves" % leaves)
	w.free()
	glade.free()


## A pond 1 m deep from x = 3 to 9 under a 12 m wall, its surface at 0.
func _bowl(x: float, _z: float) -> float:
	return -1.0 if x > 3.0 and x < 9.0 else 0.08


func _surface(_x: float, _z: float) -> float:
	return 0.0


func _wet(width: float, height: float) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	w.height = height
	var lo := 6.0 - width * 0.5
	var hi := 6.0 + width * 0.5
	w.build(func(x: float, _z: float) -> float: return -1.0 if x > lo and x < hi else 0.08, _surface)
	return w


## Walls fill the ground around the eye; at the ladder's bottom step only the chunks around the eye's own may draw
## their stones in full, the rest the far mesh.
func _full_stones_stand_only_near_the_eye() -> void:
	var ks := Wall.kinds()
	var stone := ks[Wall.Part.STONE]
	var m := Masonry.new(ks)
	var buf := PackedFloat32Array()
	buf.resize(64 * 64 * stone.stride())
	var n := 0
	for x in range(-32, 32):
		for z in range(-32, 32):
			buf[n * stone.stride() + 3] = x + 0.5
			buf[n * stone.stride() + 11] = z + 0.5
			n += 1
	var parts: Array[Dictionary] = []
	for k in ks.size():
		parts.append(Masonry.split(buf, stone) if k == Wall.Part.STONE else {})
	Wall.approach(Quality.ladder[-1], INF, m)
	m.place(1, parts)
	var full := 0.0
	var eye := Vector3(0.5, 1.65, 0.5)
	for key: Vector3i in m._chunks:
		var centre := Vector3(key.x + 0.5, 0.0, key.y + 0.5) * stone.cell() + Vector3.UP * Masonry.TALL * 0.5
		if eye.distance_to(centre) < m._chunks[key].instance.visibility_range_end:
			full += stone.cell() * stone.cell()
	check(full <= 256.0, "stones drawn in full over at most 256 m² around the eye at the bottom step, got %.0f" % full)
	Wall.approach(Quality.ladder[0], INF, m)
	m.free()


func _a_wall_over_water_stands_on_its_bed() -> void:
	var w := _wet(6.0, 2.6)
	check(absf(w.point_at(6.0).y - (0.0 - 0.12)) < 1e-3, "over water the foot is at the surface, %f" % w.point_at(6.0).y)
	check(absf(w.depth_at(6.0) - 0.88) < 1e-3 and w.depth_at(1.0) == 0.0, "the bed lies 0.88 m under the foot there, none on the bank")
	check(w.archways().size() >= 2 and w.archways().all(func(a): return a > 3.0 and a < 9.0), "the crossing opens an arcade over the water: %s" % [w.archways()])
	var bays := w.pillars()
	check(bays.size() == w.archways().size() - 1, "pillars between its arches")
	for b in bays:
		var lowest := INF
		for st in w.stones:
			if st.kind == "pillar" and absf(st.s - b.s) < 0.01:
				lowest = minf(lowest, st.y - st.size.y * 0.5)
		check(absf(lowest + 0.88) < 0.02, "a pillar stands on the bed, its foot %f" % lowest)
	for a in w.archways():
		check(not w.stones.any(func(st): return st.kind in ["block", "pillar", "mortar"] and absf(st.s - a) < WallLayout.ARCH_HALF - 0.1 and st.y < w.spring()), "water flows under the arch at %f" % a)
	var footing := w.stones.filter(func(st): return st.y < 0.0)
	check(not footing.is_empty() and footing.all(func(st): return st.s > 2.5 and st.s < 9.5), "stones under the foot only over the water")
	check(w.archways().size() == 3 and w.archways()[-1] - w.archways()[0] + WallLayout.ARCH_HALF * 2.0 > 5.5, "the arcade spans the water: %s" % [w.archways()])
	var dry := straight_wall(12.0, 2.6, [])
	check(dry.depths.size() == dry.samples.size() and not dry.stones.any(func(st): return st.y < 0.0), "a wall on dry ground lays nothing under its foot")
	var again := WallLayout.new()
	again.points = w.points
	again.build(func(x: float, _z: float) -> float: return -1.0 if x > 3.0 and x < 9.0 else 0.08, _surface)
	check(var_to_str(again.stones) == var_to_str(w.stones), "the same ground and water lay the same stones")


func _a_narrow_crossing_takes_one_arch() -> void:
	var w := _wet(1.8, 2.6)
	check(w.archways().size() == 1 and absf(w.archways()[0] - 6.0) < 0.3, "a narrow pond takes one arch at its middle: %s" % [w.archways()])
	check(w.pillars().is_empty(), "and no pillars")


func _a_low_wall_crosses_as_a_causeway() -> void:
	var w := _wet(6.0, 1.2)
	check(w.archways().is_empty(), "a wall too low to arch opens none")
	var under := w.stones.filter(func(st): return st.kind == "block" and st.y < 0.0)
	var covered := 0.0
	for st in under:
		if absf(st.y - under.map(func(u): return u.y).min()) < 0.01:
			covered += st.size.x
	check(covered > 5.5, "its lowest course runs along the bed, %f m" % covered)


func _ducks_pass_only_under_arches() -> void:
	var w := _wet(6.0, 2.6)
	var a: float = w.archways()[0]
	check(not w.opening_fits(Vector4(a, 1.5, WallLayout.DoorStyle.PLAIN, 1), w.openings), "placement respects the water opening it previews")
	var x := w.point_at(a).x
	check(not w.blocks_swim(Vector2(x, -2), Vector2(x, 2)), "a duck swims under an arch")
	var pillar: float = w.pillars()[0].s
	check(w.blocks_swim(Vector2(pillar, -2), Vector2(pillar, 2)), "but not through a pillar")
	check(not w.blocks_swim(Vector2(x, 1), Vector2(x + 1, 2)), "nor is it stopped by a wall it never reaches")
	check(w.blocks_swim(Vector2(x + 1.15, -2), Vector2(x + 1.15, 0.1)), "nor stop beside a pillar")
	var ruin := WallLayout.new()
	ruin.points = w.points
	ruin.ruins = [Vector2(4.0, 8.0)]
	ruin.height = 1.2
	ruin.build(_bowl, _surface)
	check(not ruin.blocks_swim(Vector2(6, -2), Vector2(6, 2)), "a duck swims through a ruin's gap")
	var f := WallLayout.new()
	f.points = w.points
	f.fence = true
	f.height = WallLayout.FENCE_HEIGHT
	f.build(_bowl, _surface)
	check(not f.blocks_swim(Vector2(pillar, -2), Vector2(pillar, 2)), "a fence's rails stand over the water")
	var post := f.stones.filter(func(st): return st.kind == "post" and absf(st.s - 6.0) < 1.0)
	check(not post.is_empty() and post.all(func(st): return absf(st.y - st.size.y * 0.5 + 0.88) < 0.1), "its posts stand on the bed")


func _a_path_arch_beside_a_pond_stays_open() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	w.openings.assign([2.6].map(WallLayout.archway))
	w.build(_bowl, _surface)
	check(w.archways().any(func(a): return is_equal_approx(a, 2.6)), "a path's arch beside the water stays open: %s" % [w.archways()])
	check(w.archways().size() >= 3, "and arches still cross the water")


func _water_leaves_the_dry_stones_as_they_were() -> void:
	var dry := WallLayout.new()
	dry.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	dry.height = 1.2
	dry.build(_bowl)
	var wet := WallLayout.new()
	wet.points = dry.points
	wet.height = 1.2
	wet.build(_bowl, func(x: float, _z: float) -> float: return 0.0 if x > 3.0 and x < 9.0 else Terrain.NO_WATER)
	var key := func(st: Dictionary) -> String: return var_to_str([st.xform, st.color])
	var before := dry.stones.filter(func(st): return st.kind == "block" and st.s < 2.0).map(key)
	var after := wet.stones.filter(func(st): return st.kind == "block" and st.s < 2.0).map(key)
	check(not before.is_empty() and before == after, "water under a causeway leaves its dry end's stones as they were")


## A wall's ivy settling after its stones draws its chunk's ivy again and nothing else, and does not stir the light;
## placing what is already placed draws nothing.
func _a_chunk_draws_again_only_the_pieces_that_changed() -> void:
	var ks := Wall.kinds()
	var m := Masonry.new(ks)
	var told := [0]
	m.placed.connect(func(_o: int, _b: Array[PackedFloat32Array], _s: PackedInt32Array) -> void: told[0] += 1)
	var parts: Array[Dictionary] = []
	for k in ks.size():
		var buf := PackedFloat32Array()
		buf.resize(ks[k].stride())
		buf[3] = 1.0
		parts.append(Masonry.split(buf, ks[k]))
	var bare := parts.duplicate()
	bare[Wall.Part.IVY] = {}
	m.place(2, parts)
	m.place(1, bare)
	m._process(0.0)
	told[0] = 0
	m.place(1, parts)
	var redrawn: Array = m._dirty.keys()
	check(redrawn == [Vector3i(0, 0, Wall.Part.IVY)], "ivy settling draws the chunk's ivy again, nothing else: %s" % [redrawn])
	check(told[0] == 0, "ivy settling does not stir the light")
	m._process(0.0)
	m.place(1, parts)
	check(m._dirty.is_empty(), "placing the same pieces again draws nothing")
	m.free()


func _mortar_stops_short_of_a_doorway_and_the_ends() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(9, 0, 0)]
	w.height = 3.0
	w.openings = [Vector4(3.0, 0.3, 0, 1)]
	w.build(Terrain.flat)
	var o: Dictionary = w.apertures[0]
	var reach := WallLayout.JOINT - 0.001
	var bad := []
	for m in w.stones.filter(func(s): return s.kind == "mortar"):
		var lo: float = m.s - m.size.x * 0.5
		var hi: float = m.s + m.size.x * 0.5
		var through: bool = m.y - m.size.y * 0.5 < o.head - 0.05 and hi > o.s - o.half - reach and lo < o.s + o.half + reach
		if through or lo < reach or hi > w.length() - reach:
			bad.append([lo, hi, m.y])
	check(bad.is_empty(), "mortar stops JOINT behind a doorway's jambs and the wall's ends: %s" % [bad])


## A hand draws a corner as a tight bend in an open wall: it stands a pier there, and no mortar runs on straight
## past it and out of the other wall's face.
func _a_drawn_bend_is_a_corner() -> void:
	var loop: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4.3, 0, 0), Vector3(4.3, 0, 3.7), Vector3(0, 0, 3.7)]
	var w := WallLayout.new()
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var n := ceili(a.distance_to(b) / 0.45)
		for j in n:
			w.points.append(a.lerp(b, float(j) / n))
	w.points.append(loop[0])
	w.height = 3.6
	w.build(Terrain.flat)
	check(w.corners().size() == 5, "a pier at each end and each of the 3 bends: %s" % [w.corners()])
	var off := 0.0
	for m in w.stones.filter(func(s): return s.kind == "mortar"):
		var x: Transform3D = m.xform
		for p in [x.origin - x.basis.x * 0.5, x.origin, x.origin + x.basis.x * 0.5]:
			off = maxf(off, _off_line(w, p))
	check(off < 0.05, "mortar keeps to the wall's line round its bends: %.3f off" % off)


func _off_line(w: WallLayout, p: Vector3) -> float:
	var best := INF
	for i in w.samples.size() - 1:
		var a := Vector2(w.samples[i].x, w.samples[i].z)
		var b := Vector2(w.samples[i + 1].x, w.samples[i + 1].z)
		var q := Vector2(p.x, p.z)
		var t := clampf((q - a).dot(b - a) / maxf((b - a).length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, q.distance_to(a.lerp(b, t)))
	return best
