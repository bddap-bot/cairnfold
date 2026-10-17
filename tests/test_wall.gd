extends SceneTree

## Headless checks of the wall layout: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wall.gd

var failures := 0


func _init() -> void:
	_straight_wall_fills_its_length()
	_arch_leaves_its_opening_clear()
	_arch_ring_closes_over_the_opening()
	_short_or_low_walls_take_no_arch()
	_layout_is_deterministic()
	_a_copy_built_elsewhere_lays_the_same_stones()
	_raising_the_wall_adds_courses()
	_point_at_follows_the_curve()
	_a_long_wall_splits_by_the_ground_under_each_stone()
	_stone_faces_share_their_borders()
	_settled_chunks_draw_far_stones_and_stop_ivy_at_its_reach()
	_full_stones_stand_only_near_the_eye()
	_a_changing_wall_draws_far_stones_by_its_own_chunks()
	_a_wall_over_water_stands_on_its_bed()
	_a_narrow_crossing_takes_one_arch()
	_a_low_wall_crosses_as_a_causeway()
	_ducks_pass_only_under_arches()
	_a_path_arch_beside_a_pond_stays_open()
	_water_leaves_the_dry_stones_as_they_were()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _wall(length: float, height: float, arches: Array[float]) -> WallLayout:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(length, 0, 0)]
	w.height = height
	w.arches = arches
	w.build(_flat)
	return w


func _blocks(w: WallLayout) -> Array:
	return w.stones.filter(func(s): return s.kind == "block")


func _straight_wall_fills_its_length() -> void:
	var w := _wall(6.0, 2.4, [])
	_check(absf(w.length() - 6.0) < 0.01, "length %f" % w.length())
	var courses := int(round(2.4 / WallLayout.COURSE))
	for k in courses:
		var covered := 0.0
		for s in _blocks(w):
			if absf(s.y - (k + 0.5) * 2.4 / courses) < 0.01:
				covered += s.size.x
		_check(absf(covered - 6.0) < 0.02, "course %d covers %f of 6 m" % [k, covered])
	_check(w.stones.any(func(s): return s.kind == "merlon"), "a crenellated top")
	_check(w.stones.filter(func(s): return s.kind == "pier").size() >= 4, "piers at both ends")


func _arch_leaves_its_opening_clear() -> void:
	var w := _wall(8.0, 2.7, [4.0])
	for s in w.stones:
		if s.kind == "voussoir" or s.kind == "keystone":
			continue
		var y: float = s.y
		var half := w.opening(y, false)
		var lo: float = s.s - s.size.x * 0.5
		var hi: float = s.s + s.size.x * 0.5
		if half > 0.0:
			_check(hi <= 4.0 - half + 0.01 or lo >= 4.0 + half - 0.01, "%s at s=%f y=%f intrudes into the arch" % [s.kind, s.s, y])


func _arch_ring_closes_over_the_opening() -> void:
	var w := _wall(8.0, 2.7, [4.0])
	var ring := w.stones.filter(func(s): return s.kind == "voussoir")
	_check(ring.size() == 11, "11 voussoirs, got %d" % ring.size())
	_check(w.stones.filter(func(s): return s.kind == "keystone").size() == 1, "one keystone")
	for s in ring:
		var r := Vector2(s.s - 4.0, s.y - w.spring()).length()
		_check(absf(r - (WallLayout.ARCH_HALF + WallLayout.RING * 0.5)) < 0.05, "voussoir off the ring: r=%f" % r)


func _short_or_low_walls_take_no_arch() -> void:
	_check(_wall(1.5, 2.7, [0.75]).stones.all(func(s): return s.kind != "voussoir"), "a 1.5 m wall has no room for an arch")
	_check(_wall(8.0, 1.2, [4.0]).stones.all(func(s): return s.kind != "voussoir"), "a 1.2 m wall is too low for an arch")


func _layout_is_deterministic() -> void:
	var a := _wall(7.0, 2.4, [3.5])
	var b := _wall(7.0, 2.4, [3.5])
	_check(a.stones.size() == b.stones.size() and a.stones.all(func(s): return true), "same stone count")
	for i in a.stones.size():
		if not a.stones[i].xform.is_equal_approx(b.stones[i].xform):
			_check(false, "stone %d differs between identical builds" % i)
			break


func _a_copy_built_elsewhere_lays_the_same_stones() -> void:
	var loop := WallLayout.new()
	loop.points = [Vector3(0, 0, 0), Vector3(4, 0, 2), Vector3(8, 0, 0), Vector3(5, 0, -3)]
	loop.closed = true
	loop.height = 3.3
	loop.top = WallLayout.Top.CAP
	loop.cover = WallLayout.Cover.ROOF
	loop.seed = 9
	loop.arches.assign([16.1])
	loop.windows.assign([Vector2(2.2, 1.4)])
	loop.lanterns.assign([Vector3(7.0, 1.8, 1.0)])
	var flagged := WallLayout.new()
	flagged.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	flagged.flags.assign([6.0])
	var fence := WallLayout.new()
	fence.points = [Vector3(0, 0, 0), Vector3(6, 0, 1)]
	fence.fence = true
	for a: WallLayout in [loop, flagged, fence]:
		a.build(_flat)
		var copy := a.inputs()
		copy.build(_flat)
		var b := WallLayout.new()
		b.adopt(copy)
		_check(b.stones.size() == a.stones.size() and b.live_arches == a.live_arches and b.samples == a.samples and b.openings.size() == a.openings.size() and b.flames == a.flames and b.cloths.size() == a.cloths.size(), "a copy's build matches: %d vs %d stones" % [b.stones.size(), a.stones.size()])
		for i in mini(a.stones.size(), b.stones.size()):
			if not a.stones[i].xform.is_equal_approx(b.stones[i].xform) or a.stones[i].kind != b.stones[i].kind:
				_check(false, "stone %d differs in the copy's build" % i)
				break
	_check(loop.live_arches.size() == 1 and not loop.openings.is_empty() and not loop.flames.is_empty(), "the loop opens its arch and window and hangs its lantern")
	_check(not flagged.cloths.is_empty(), "the flag flies")


func _raising_the_wall_adds_courses() -> void:
	var low := _wall(5.0, 1.8, [])
	var high := _wall(5.0, 3.6, [])
	var top := func(w: WallLayout) -> float:
		var m := 0.0
		for s in w.stones:
			m = maxf(m, s.y + s.size.y * 0.5)
		return m
	_check(top.call(high) > top.call(low) + 1.5, "raising 1.8 m adds height")
	_check(_blocks(high).size() > _blocks(low).size() * 1.6, "raising adds courses of stone")


func _point_at_follows_the_curve() -> void:
	var w := _wall(6.0, 2.4, [])
	_check(w.point_at(3.0).distance_to(Vector3(3, -0.12, 0)) < WallLayout.SAMPLE * 2.0, "point_at(3) is %s" % w.point_at(3.0))
	_check(w.point_at(99.0) == w.samples[-1], "point_at past the end is the end")


func _a_long_wall_splits_by_the_ground_under_each_stone() -> void:
	var stone := Wall.kinds()[Wall.Part.STONE]
	var w := _wall(40.0, 1.5, [])
	var packed := Wall.pack(w, Wall.kinds(), Palette.plain())
	var chunks: Dictionary = packed.chunks[Wall.Part.STONE]
	_check(chunks.size() >= 3, "a 40 m wall spans at least three chunks, got %d" % chunks.size())
	var total := 0
	for key in chunks:
		var buf: PackedFloat32Array = chunks[key]
		total += buf.size()
		for i in range(0, buf.size(), stone.stride()):
			var at := Vector2i(floori(buf[i + 3] / Masonry.CHUNK_METRES), floori(buf[i + 11] / Masonry.CHUNK_METRES))
			if at != key:
				_check(false, "a stone at %s sits in chunk %s" % [at, key])
				return
	_check(total == packed.stone.size(), "every stone in exactly one chunk")


func _stone_faces_share_their_borders() -> void:
	for segments in [1, 2, 3]:
		var a := Meshes.rounded_box(0.14, segments, 100).surface_get_arrays(0)
		var row: int = segments + 1
		_check(a[Mesh.ARRAY_VERTEX].size() == 6 * row * row - 12 * row + 8, "%d segments: one vertex per lattice point, got %d" % [segments, a[Mesh.ARRAY_VERTEX].size()])
		_check(a[Mesh.ARRAY_INDEX].size() == 36 * segments * segments, "%d segments: every face's triangles" % segments)


func _settled_chunks_draw_far_stones_and_stop_ivy_at_its_reach() -> void:
	var ks := Wall.kinds()
	var m := Masonry.new(ks)
	var parts: Array[Dictionary] = []
	for k in ks.size():
		var buf := PackedFloat32Array()
		buf.resize(ks[k].stride() * 2)
		buf[3] = 1.0
		buf[ks[k].stride() + 3] = 40.0
		parts.append(Masonry.split(buf, ks[k].stride()))
	m.place(1, parts)
	_check(m._chunks.size() == 2, "pieces 39 m apart stand in two chunks")
	for c in m._chunks.values():
		var near: MultiMeshInstance3D = c.instances[Wall.Part.STONE]
		var far: MultiMeshInstance3D = c.fars[Wall.Part.STONE]
		_check(far != null and far.multimesh.mesh == Stones.far_mesh(), "a chunk draws far stones with the far mesh")
		_check(far.multimesh.instance_count == 0 and near.multimesh.instance_count == 0, "nothing drawn before the chunk is processed")
		_check(is_equal_approx(near.visibility_range_end, ks[Wall.Part.STONE].near + Masonry.CHUNK_RADIUS) and is_equal_approx(far.visibility_range_begin, near.visibility_range_end), "near and far stones meet at the near distance")
		_check(is_equal_approx(c.instances[Wall.Part.IVY].visibility_range_end, ks[Wall.Part.IVY].reach + Masonry.CHUNK_RADIUS), "ivy stops at its reach")
		_check(c.fars[Wall.Part.MORTAR] == null and c.instances[Wall.Part.MORTAR].visibility_range_end == 0.0, "mortar has no far mesh and no limit")
	m._process(0.0)
	for c in m._chunks.values():
		_check(c.instances[Wall.Part.STONE].multimesh.instance_count == 1 and c.fars[Wall.Part.STONE].multimesh.instance_count == 1, "near and far hold the chunk's one stone")
	m.place(1, parts)
	m.remove(1)
	m._process(0.0)
	for c in m._chunks.values():
		_check(c.instances[Wall.Part.STONE].multimesh.instance_count == 0 and c.fars[Wall.Part.STONE].multimesh.instance_count == 0, "a removed owner leaves every chunk it stood in")
	m.free()


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
	_check(w._drawn != null and w._drawn._owners.has(id) and not glade._owners.has(id), "a changing wall draws its own pieces")
	if w._drawn != null:
		_check(w._drawn._chunks.size() >= 4, "by the ground chunk under each, got %d chunks" % w._drawn._chunks.size())
		for c in w._drawn._chunks.values():
			var far: MultiMeshInstance3D = c.fars[Wall.Part.STONE]
			_check(far != null and far.multimesh.mesh == Stones.far_mesh() and is_equal_approx(far.visibility_range_begin, Wall.kinds()[Wall.Part.STONE].near + Masonry.CHUNK_RADIUS), "beyond the near distance in coarse stones")
	w.finished = true
	w.rebuild(true)
	w.lay_now()
	_check(glade._owners.has(id) and w._drawn == null, "once settled the glade draws them, and the wall's own Masonry goes")
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
		parts.append(Masonry.split(buf, stone.stride()) if k == Wall.Part.STONE else {})
	Wall.approach(Quality.ladder[-1], INF, m)
	m.place(1, parts)
	var full := 0.0
	var eye := Vector3(0.5, 1.65, 0.5)
	for key in m._chunks:
		var centre := Vector3(key.x + 0.5, 0.0, key.y + 0.5) * Masonry.CHUNK_METRES + Vector3.UP * WallLayout.HEIGHTS.y * 0.5
		if eye.distance_to(centre) < m._chunks[key].instances[Wall.Part.STONE].visibility_range_end:
			full += Masonry.CHUNK_METRES * Masonry.CHUNK_METRES
	_check(full <= 256.0, "stones drawn in full over at most 256 m² around the eye at the bottom step, got %.0f" % full)
	Wall.approach(Quality.ladder[0], INF, m)
	m.free()


func _a_wall_over_water_stands_on_its_bed() -> void:
	var w := _wet(6.0, 2.6)
	_check(absf(w.point_at(6.0).y - (0.0 - 0.12)) < 1e-3, "over water the foot is at the surface, %f" % w.point_at(6.0).y)
	_check(absf(w.depth_at(6.0) - 0.88) < 1e-3 and w.depth_at(1.0) == 0.0, "the bed lies 0.88 m under the foot there, none on the bank")
	_check(w.live_arches.size() >= 2 and w.live_arches.all(func(a): return a > 3.0 and a < 9.0), "the crossing opens an arcade over the water: %s" % [w.live_arches])
	var bays := w.pillars()
	_check(bays.size() == w.live_arches.size() - 1, "pillars between its arches")
	for b in bays:
		var lowest := INF
		for st in w.stones:
			if st.kind == "pillar" and absf(st.s - b.s) < 0.01:
				lowest = minf(lowest, st.y - st.size.y * 0.5)
		_check(absf(lowest + 0.88) < 0.02, "a pillar stands on the bed, its foot %f" % lowest)
	for a in w.live_arches:
		_check(not w.stones.any(func(st): return st.kind in ["block", "pillar", "mortar"] and absf(st.s - a) < WallLayout.ARCH_HALF - 0.1 and st.y < w.spring()), "water flows under the arch at %f" % a)
	var footing := w.stones.filter(func(st): return st.y < 0.0)
	_check(not footing.is_empty() and footing.all(func(st): return st.s > 2.5 and st.s < 9.5), "stones under the foot only over the water")
	_check(w.live_arches.size() == 3 and w.live_arches[-1] - w.live_arches[0] + WallLayout.ARCH_HALF * 2.0 > 5.5, "the arcade spans the water: %s" % [w.live_arches])
	var dry := _wall(12.0, 2.6, [])
	_check(dry.depths.size() == dry.samples.size() and not dry.stones.any(func(st): return st.y < 0.0), "a wall on dry ground lays nothing under its foot")
	var again := WallLayout.new()
	again.points = w.points
	again.build(func(x: float, _z: float) -> float: return -1.0 if x > 3.0 and x < 9.0 else 0.08, _surface)
	_check(var_to_str(again.stones) == var_to_str(w.stones), "the same ground and water lay the same stones")


func _a_narrow_crossing_takes_one_arch() -> void:
	var w := _wet(1.8, 2.6)
	_check(w.live_arches.size() == 1 and absf(w.live_arches[0] - 6.0) < 0.3, "a narrow pond takes one arch at its middle: %s" % [w.live_arches])
	_check(w.pillars().is_empty(), "and no pillars")


func _a_low_wall_crosses_as_a_causeway() -> void:
	var w := _wet(6.0, 1.2)
	_check(w.live_arches.is_empty(), "a wall too low to arch opens none")
	var under := w.stones.filter(func(st): return st.kind == "block" and st.y < 0.0)
	var covered := 0.0
	for st in under:
		if absf(st.y - under.map(func(u): return u.y).min()) < 0.01:
			covered += st.size.x
	_check(covered > 5.5, "its lowest course runs along the bed, %f m" % covered)


func _ducks_pass_only_under_arches() -> void:
	var w := _wet(6.0, 2.6)
	var a: float = w.live_arches[0]
	var x := w.point_at(a).x
	_check(not w.blocks_swim(Vector2(x, -2), Vector2(x, 2)), "a duck swims under an arch")
	var pillar: float = w.pillars()[0].s
	_check(w.blocks_swim(Vector2(pillar, -2), Vector2(pillar, 2)), "but not through a pillar")
	_check(not w.blocks_swim(Vector2(x, 1), Vector2(x + 1, 2)), "nor is it stopped by a wall it never reaches")
	_check(w.blocks_swim(Vector2(x + 1.15, -2), Vector2(x + 1.15, 0.1)), "nor stop beside a pillar")
	var ruin := WallLayout.new()
	ruin.points = w.points
	ruin.ruins = [Vector2(4.0, 8.0)]
	ruin.height = 1.2
	ruin.build(_bowl, _surface)
	_check(not ruin.blocks_swim(Vector2(6, -2), Vector2(6, 2)), "a duck swims through a ruin's gap")
	var f := WallLayout.new()
	f.points = w.points
	f.fence = true
	f.height = WallLayout.FENCE_HEIGHT
	f.build(_bowl, _surface)
	_check(not f.blocks_swim(Vector2(pillar, -2), Vector2(pillar, 2)), "a fence's rails stand over the water")
	var post := f.stones.filter(func(st): return st.kind == "post" and absf(st.s - 6.0) < 1.0)
	_check(not post.is_empty() and post.all(func(st): return absf(st.y - st.size.y * 0.5 + 0.88) < 0.1), "its posts stand on the bed")


func _a_path_arch_beside_a_pond_stays_open() -> void:
	var w := WallLayout.new()
	w.points = [Vector3(0, 0, 0), Vector3(12, 0, 0)]
	w.arches = [2.6]
	w.build(_bowl, _surface)
	_check(w.live_arches.has(2.6), "a path's arch beside the water stays open: %s" % [w.live_arches])
	_check(w.live_arches.size() >= 3, "and arches still cross the water")


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
	_check(not before.is_empty() and before == after, "water under a causeway leaves its dry end's stones as they were")
