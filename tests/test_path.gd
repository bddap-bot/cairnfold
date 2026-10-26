extends "res://../tests/support/suite.gd"

## Headless checks of paths and wall chemistry: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_path.gd


var terrain := Terrain.new()
var marks := Ground.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	marks.install()
	_steep_paths_lay_level_treads()
	_a_path_across_a_wall_opens_one_arch()
	_a_wide_or_slanted_crossing_opens_an_arcade()
	_a_path_beside_a_wall_opens_nothing()
	_crossings_test_every_segment_pair_that_meets()
	_a_growing_stroke_plans_and_meets_as_a_whole_one()
	_arcades_stand_on_pillars()
	_overlapping_arches_do_not_both_open()
	_the_mask_parts_the_path_only()
	_a_short_stroke_leaves_no_trace()
	_chemistry_works_in_either_order()
	_a_second_path_beside_an_arch_makes_an_arcade()
	_a_crossing_that_cannot_open_leaves_no_arch()
	_a_tower_opens_a_doorway_across_its_seam()
	_a_path_into_a_house_opens_a_door_as_wide_as_it()
	_a_path_and_a_house_make_a_door_in_either_order()
	_painting_skips_a_path()
	_a_scripted_stroke_outlasts_the_hand()
	_undo_lifts_a_path_and_its_arches()
	await _a_path_opens_its_arch_before_release()
	_a_stroke_over_many_walls_previews_as_one_cut_whole()
	_a_stroke_laid_keeps_the_arches_its_ghost_showed()
	await _a_laid_path_wears_the_garden_at_once_and_shows_by_the_next_frame()
	await _dirt_wears_without_stones()
	_each_surface_wears_its_own_ground()
	_surfaces_blend_where_they_meet()
	_earth_and_stone_keep_their_looks()
	_a_path_across_water_lays_stepping_stones()
	_a_bed_sprouts_rows_of_vegetables()
	finish()


func _path(points: Array, half: float) -> PathLayout:
	var p := PathLayout.new()
	for q in points:
		p.add(Vector3(q[0], 0, q[1]), half)
	p.plan()
	return p


func _wall(points: Array, height := 2.6) -> WallLayout:
	var w := WallLayout.new()
	for q in points:
		w.points.append(Vector3(q[0], 0, q[1]))
	w.height = height
	w.build(Terrain.flat)
	return w


func _a_path_across_a_wall_opens_one_arch() -> void:
	var w := _wall([[0, 0], [10, 0]])
	var cut := _path([[4, -4], [4, 4]], 0.6).crossings(w)
	check(cut.size() == 1, "a narrow square crossing opens one arch, got %s" % [cut])
	if cut.size() == 1:
		check(absf(cut[0] - 4.0) < 0.05, "the arch opens where the path crosses, at %.2f" % cut[0])


func _a_wide_or_slanted_crossing_opens_an_arcade() -> void:
	var w := _wall([[0, 0], [16, 0]])
	var cut := _path([[8, -6], [8, 6]], 2.5).crossings(w)
	check(cut.size() >= 2, "a 5 m wide crossing opens an arcade, got %s" % [cut])
	if not cut.is_empty():
		var lo: float = cut.min() - WallLayout.ARCH_HALF
		var hi: float = cut.max() + WallLayout.ARCH_HALF
		check(lo <= 8.0 - 2.5 and hi >= 8.0 + 2.5, "the arcade's openings span the whole path: %.2f to %.2f" % [lo, hi])
	cut.sort()
	for i in range(1, cut.size()):
		check(is_equal_approx(cut[i] - cut[i - 1], WallLayout.ARCADE_PITCH), "arcade arches stand a pitch apart: %s" % [cut])
	if not cut.is_empty():
		check(absf((cut[0] + cut[-1]) * 0.5 - 8.0) < 0.05, "the arcade centres on the crossing: %s" % [cut])
	var slant := _path([[2, -1.2], [14, 1.2]], 0.9).crossings(w)
	check(slant.size() >= 2, "a path meeting the wall at a shallow angle opens an arcade, got %s" % [slant])


func _a_path_beside_a_wall_opens_nothing() -> void:
	var w := _wall([[0, 0], [10, 0]])
	check(_path([[0, 2], [10, 2]], 1.2).crossings(w).is_empty(), "a path alongside a wall opens nothing")
	check(_path([[4, 1.5], [4, 6]], 1.2).crossings(w).is_empty(), "a path that stops short of a wall opens nothing")


## Crossings found through the grid match testing every path segment against every wall segment.
func _crossings_test_every_segment_pair_that_meets() -> void:
	var tower := WallLayout.new()
	for k in 7:
		tower.points.append(Vector3(cos(k * TAU / 7) * 4.0, 0, sin(k * TAU / 7) * 4.0))
	tower.closed = true
	tower.height = 3.0
	tower.build(Terrain.flat)
	var walls: Array[WallLayout] = [_wall([[0, 0], [16, 0]]), _wall([[-6, -5], [-1, 3], [6, 4], [9, -3]]), tower]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mismatched := 0
	for k in 30:
		var pts := []
		for i in 4:
			pts.append([rng.randf_range(-10, 16), rng.randf_range(-8, 8)])
		var p := _path(pts, rng.randf_range(PathLayout.HALF_WIDTH.x, PathLayout.HALF_WIDTH.y))
		for w in walls:
			var shared := p.segment_cells().keys().filter(func(c: Vector2i) -> bool: return w.segment_cells().has(c))
			if p.crossings(w) != _every_pair(p, w) or (not shared.is_empty() and p.crossings(w, shared) != _every_pair(p, w)):
				mismatched += 1
	check(mismatched == 0, "crossings match every segment pair tested: %d of 90 differ" % mismatched)


## A stroke being drawn re-plans only its moving end and keeps each wall's meetings along the rest; after every relay
## its samples, cells and meetings are those of the same points planned whole.
func _a_growing_stroke_plans_and_meets_as_a_whole_one() -> void:
	var walls: Array[WallLayout] = []
	for z in [-5.0, -1.0, 3.0]:
		walls.append(_wall([[-10, z], [10, z]]))
	walls.append(_wall([[-9, -8], [-9, 8]]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var drawn := PathLayout.new()
	drawn.growing = true
	var at := Vector3(-8, 0, -9)
	drawn.add(at, 0.6)
	var differ := 0
	for step in 120:
		at += Vector3(rng.randf_range(-0.3, 0.6), 0, rng.randf_range(0.0, 0.4))
		if drawn.points.size() >= 2 and drawn.points[-1].distance_to(drawn.points[-2]) < WallTool.POINT_SPACING:
			drawn.points[-1] = at
			drawn.half_widths[-1] = maxf(drawn.half_widths[-1], rng.randf_range(0.5, 1.5))
		else:
			drawn.add(at, rng.randf_range(0.5, 1.5))
		if step % 3 != 0:
			continue
		drawn.plan()
		var whole := PathLayout.new()
		whole.points = drawn.points.duplicate()
		whole.half_widths = drawn.half_widths.duplicate()
		whole.plan()
		if drawn.samples != whole.samples or drawn.lengths != whole.lengths or drawn.sample_half_widths != whole.sample_half_widths or drawn.point_lengths != whole.point_lengths or drawn.segment_cells() != whole.segment_cells():
			differ += 1
		for w in walls:
			if drawn.meetings(w) != whole.meetings(w):
				differ += 1
	check(differ == 0, "a growing stroke plans and meets walls as the same points planned whole: %d differ" % differ)


func _every_pair(path: PathLayout, wall: WallLayout) -> Array[float]:
	var out: Array[float] = []
	var found: Array[float] = []
	for i in path.samples.size() - 1:
		var a := Vector2(path.samples[i].x, path.samples[i].z)
		var b := Vector2(path.samples[i + 1].x, path.samples[i + 1].z)
		for j in wall.samples.size() - 1:
			var c := Vector2(wall.samples[j].x, wall.samples[j].z)
			var d := Vector2(wall.samples[j + 1].x, wall.samples[j + 1].z)
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit == null or (c - d).length() < 1e-5:
				continue
			var s: float = wall.lengths[j] + c.distance_to(hit)
			if found.any(func(f): return absf(f - s) < WallLayout.SAMPLE):
				continue
			found.append(s)
			var slant := absf((b - a).normalized().cross((d - c).normalized()))
			var span := 2.0 * lerpf(path.sample_half_widths[i], path.sample_half_widths[i + 1], a.distance_to(hit) / maxf(a.distance_to(b), 1e-5)) / maxf(slant, 0.4)
			var n := 1 if span < PathLayout.ARCADE_SPAN else ceili((span - WallLayout.ARCH_HALF * 2.0) / WallLayout.ARCADE_PITCH) + 1
			for m in n:
				out.append(s + (m - (n - 1) * 0.5) * WallLayout.ARCADE_PITCH)
	return out


func _arcades_stand_on_pillars() -> void:
	var w := _wall([[0, 0], [16, 0]], 3.2)
	w.openings.assign(_path([[8, -6], [8, 6]], 2.5).crossings(w).map(WallLayout.archway))
	w.build(Terrain.flat)
	check(w.archways().size() == w.openings.size(), "every arcade arch opens: %s of %s" % [w.archways(), w.openings])
	var pillars := w.pillars()
	check(pillars.size() == w.archways().size() - 1, "%d pillars between %d arches" % [pillars.size(), w.archways().size()])
	var pillar_stones := w.stones.filter(func(s): return s.kind == "pillar")
	check(pillar_stones.size() >= pillars.size() * 4, "each pillar is a stack of drums with plinth and capital (%d stones)" % pillar_stones.size())
	var lo: float = w.archways()[0] - WallLayout.ARCH_HALF
	var hi: float = w.archways()[-1] + WallLayout.ARCH_HALF
	for s in w.stones:
		if s.kind == "block" and s.y < w.spring() - 0.2 and absf(s.s - (lo + hi) * 0.5) < (hi - lo) * 0.5 - s.size.x * 0.5 + 0.01:
			check(false, "a coursed block at s=%.2f y=%.2f fills the arcade below its springing" % [s.s, s.y])
			return
	for p in pillars:
		var here := pillar_stones.filter(func(s): return absf(s.s - p.s) < 0.01)
		var top := 0.0
		for s in here:
			top = maxf(top, s.y + s.size.y * 0.5)
		check(top >= w.spring() - 0.05, "a pillar rises to the springing (%.2f of %.2f)" % [top, w.spring()])


func _overlapping_arches_do_not_both_open() -> void:
	var w := _wall([[0, 0], [12, 0]])
	w.openings.assign([5.0, 6.0].map(WallLayout.archway))
	w.build(Terrain.flat)
	check(w.archways().size() == 1, "two arches whose rings overlap open as one: %s" % [w.archways()])


func _the_mask_parts_the_path_only() -> void:
	var paths := _paths()
	paths.begin(Vector3(-10, 0, 20), 0.8)
	for i in 30:
		paths.extend(Vector3(-10 + i * 0.3, 0, 20), 0.8)
	var p := paths.end()
	check(not p.is_empty() and p.layout.length() > 8.0, "a 9 m stroke is a path")
	marks.settle()
	check(marks.bare(-5, 20) > 0.99, "the stroke centre is fully worn (%.2f)" % marks.bare(-5, 20))
	check(marks.bare(-5, 20.7) > 0.5, "the stroke edge is worn (%.2f)" % marks.bare(-5, 20.7))
	check(marks.bare(-5, 21.6) == 0.0, "the meadow a metre past the edge is untouched (%.2f)" % marks.bare(-5, 21.6))
	check(marks.bare(10, 20) == 0.0, "the meadow past the end is untouched")
	paths.queue_free()


func _a_short_stroke_leaves_no_trace() -> void:
	var paths := _paths()
	paths.begin(Vector3(30, 0, 30), 1.0)
	paths.extend(Vector3(30.4, 0, 30), 1.0)
	check(paths.end().is_empty() and paths.layouts.is_empty(), "a stroke under a metre is dropped")
	check(marks.bare(30, 30) == 0.0, "a dropped stroke unwears the ground (%.2f)" % marks.bare(30, 30))
	paths.queue_free()


func _chemistry_works_in_either_order() -> void:
	var nodes := _setup()
	var tool: WallTool = nodes[0]
	var paths: Paths = nodes[1]
	var first := _draw_wall(tool, Vector3(-8, 0, -12), Vector3(8, 0, -12))
	_reshape(nodes, first, {"openings": PackedVector4Array()})
	_lay(nodes, Vector3(2, 0, -18), Vector3(2, 0, -6), 0.6)
	check(first.layout.archways().size() == 1 and absf(first.layout.archways()[0] - 10.0) < 0.1, "a path laid through a wall cuts an arch at the crossing: %s" % [first.layout.archways()])
	_lay(nodes, Vector3(-30, 0, -2), Vector3(-30, 0, 10), 2.5)
	var second := _draw_wall(tool, Vector3(-38, 0, 4), Vector3(-22, 0, 4))
	check(second.layout.archways().size() >= 2 and second.layout.pillars().size() >= 1, "a wall drawn across a wide path opens an arcade: %s" % [second.layout.archways()])
	for a in second.layout.archways():
		check(absf(a - 8.0) < WallLayout.ARCADE_PITCH * 1.5, "arcade arches stand over the path, not the wall's middle: %s" % [second.layout.archways()])
	_teardown(nodes)


func _paths() -> Paths:
	var paths := Paths.new()
	paths.terrain = terrain
	paths.marks = marks
	root.add_child(paths)
	return paths


## A wall tool, the paths, the garden and the rig, idle so a test drives them.
func _setup() -> Array:
	var world := World.new()
	var rig := Rig.new(world.terrain)
	root.add_child(rig)
	# Crossing fixtures exceed capacity; test_budget covers the shared limit.
	world.bounded = false
	root.add_child(world)
	var paths := Paths.new()
	paths.terrain = world.terrain
	paths.marks = world.marks
	root.add_child(paths)
	var flora := Flora.new(world.terrain, world.marks)
	root.add_child(flora)
	flora.keep()
	var tool := WallTool.new(rig, world, flora, paths)
	root.add_child(tool)
	tool.set_process(false)
	var ground := GroundGrab.new(rig, world)
	ground.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(ground)
	world.attach(tool, flora, paths, ground)
	return [tool, paths, world, rig, flora, ground]


func _teardown(nodes: Array) -> void:
	for w in nodes[0].walls:
		w.queue_free()
	for n in nodes:
		n.queue_free()


func _a_second_path_beside_an_arch_makes_an_arcade() -> void:
	var nodes := _setup()
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 30), Vector3(8, 0, 30))
	_reshape(nodes, w, {"openings": PackedVector4Array([8.0].map(WallLayout.archway))})
	var before := w.layout.archways().duplicate()
	_lay(nodes, Vector3(1.5, 0, 24), Vector3(1.5, 0, 36), 0.5)
	check(before.all(func(a): return w.layout.archways().has(a)), "a path beside the middle arch closes nothing: %s then %s" % [before, w.layout.archways()])
	check(w.layout.archways().size() == before.size() + 1 and w.layout.pillars().size() == 1, "it opens a second arch on a shared pillar: %s" % [w.layout.archways()])
	_lay(nodes, Vector3(0.2, 0, 24), Vector3(0.2, 0, 36), 0.5)
	check(w.layout.archways().size() == before.size() + 1, "a path through an opening that is already there adds none: %s" % [w.layout.archways()])
	_teardown(nodes)


func _a_crossing_that_cannot_open_leaves_no_arch() -> void:
	var nodes := _setup()
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 40), Vector3(8, 0, 40))
	var before := w.layout.openings.duplicate()
	_lay(nodes, Vector3(-7.6, 0, 34), Vector3(-7.6, 0, 46), 0.5)
	check(w.layout.openings == before, "a crossing at a wall's end records no arch: %s" % [w.layout.openings])
	var low := _draw_wall(nodes[0], Vector3(-8, 0, 50), Vector3(8, 0, 50))
	_reshape(nodes, low, {"height": 1.2, "openings": PackedVector4Array()})
	_lay(nodes, Vector3(0, 0, 44), Vector3(0, 0, 56), 0.5)
	check(low.layout.openings.is_empty(), "a wall too low to arch records none: %s" % [low.layout.openings])
	_teardown(nodes)


func _a_tower_opens_a_doorway_across_its_seam() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.circle(Vector3.ZERO, 1.3)
	w.closed = true
	w.height = 4.5
	w.build(Terrain.flat)
	var cut := _path([[-1, 0.15], [4, 0.15]], 0.5).crossings(w)
	check(cut.size() == 1, "a path into a tower crosses its wall once there, got %s" % [cut])
	if cut.size() == 1:
		var a := w.wrap(cut[0])
		check(w.opening_fits(WallLayout.archway(a), []), "a doorway fits beside the tower's seam at %.2f of %.2f" % [a, w.length()])
		w.openings.assign([a].map(WallLayout.archway))
		w.build(Terrain.flat)
		check(w.archways().size() == 1, "the doorway opens")
		var t := WallLayout.new()
		t.points = w.points
		t.closed = true
		t.height = 4.5
		t.openings.assign([w.wrap(a - 1.0)].map(WallLayout.archway))
		t.build(Terrain.flat)
		var nodes := _setup()
		var tower := Wall.new(1, nodes[0].masonry, nodes[2].terrain)
		tower.layout = t
		nodes[0].walls.append(tower)
		var opened: Array[float] = nodes[0]._cut_crossings(tower, _path([[-1, 0.15], [4, 0.15]], 0.5))
		check(opened.size() == 1 and absf(t.offset(opened[0], w.wrap(a - 1.0))) > WallLayout.ARCH_SPACING - 0.01, "a crossing beside an arch across the seam stands a pitch from it: %s beside %.2f" % [opened, w.wrap(a - 1.0)])
		t.build(Terrain.flat)
		check(t.pillars().size() == 1, "the pair across the seam shares a pillar: %s" % [t.pillars()])
		nodes[0].walls.clear()
		tower.free()
		_teardown(nodes)
		var blocks := w.stones.filter(func(s): return s.kind == "block" and s.y < w.spring())
		check(not blocks.any(func(s): return Vector2(s.xform.origin.x - 1.3, s.xform.origin.z - 0.15).length() < WallLayout.ARCH_HALF - 0.2), "no block fills the doorway across the seam")


## A house 8 m by 5 m with a gable roof, its front wall from (4, 2.5) back to (-4, 2.5) at arc length 13 to 21.
func _house_layout() -> WallLayout:
	var w := WallLayout.new()
	w.points = WallLayout.rectangle(Vector3(-4, 0, 0), Vector3(4, 0, 0), 5.0)
	w.closed = true
	w.cover = WallLayout.Cover.ROOF
	w.build(Terrain.flat)
	return w


func _doors(w: WallLayout) -> Array:
	return w.apertures.filter(func(o: Dictionary) -> bool: return o.door and o.style != WallLayout.Family.ARCHWAY)


func _a_path_into_a_house_opens_a_door_as_wide_as_it() -> void:
	var w := _house_layout()
	var none: Array[Vector4] = []
	for t in [[0.45, 1], [0.55, 1], [1.0, 2], [1.6, 3]]:
		var half: float = t[0]
		var meets := _path([[0.5, 7], [0.5, 0]], half).meetings(w)
		check(meets.size() == 1 and absf(meets[0].s - 16.5) < 0.05, "a path into a house meets its front once, where it runs in: %s" % [meets])
		var doors := w.path_doors(meets[0].s, meets[0].span, none)
		check(not doors.is_empty() and doors.all(func(d: Vector4) -> bool: return d.z == WallLayout.Family.COTTAGE and WallLayout.opens_door(d)), "a %.2f m path opens plank doors: %s" % [half * 2.0, doors])
		w.openings.assign(doors)
		w.build(Terrain.flat)
		var made := _doors(w)
		check(made.size() == 1 and absf(made[0].s - 16.5) < 0.05 and made[0].lights == t[1] and absf(made[0].half * 2.0 - half * 2.0) < 0.04, "a %.2f m path opens one door of %d lights where it meets the wall, as wide as it: %s" % [half * 2.0, t[1], made])
		check(w.archways().is_empty(), "a path into a house opens no arch")
	var wall_high := w.path_doors(16.5, 1.4, none)
	w.openings.assign(wall_high)
	w.build(Terrain.flat)
	var made := _doors(w)
	check(made.size() == 1 and made[0].lights == 1 and made[0].half * 2.0 < 1.4 and made[0].head + w.course_height() <= w.height + 0.01, "a path a little wider than the tallest door the wall holds opens that door: %s" % [made])
	var wide := _path([[-4.5, 7], [2.5, 0]], 3.0).meetings(w)
	w.openings.assign(w.path_doors(wide[0].s, wide[0].span, none))
	w.build(Terrain.flat)
	made = _doors(w)
	check(made.size() == 1 and made[0].lights == w.openings.size() and made[0].half * 2.0 < wide[0].span and made[0].half * 2.0 > 4.0, "a path wider than the wall opens as many lights as it holds: %s for a %.2f m crossing" % [made, wide[0].span])
	var placed: Array[Vector4] = [Vector4(16.6, 0.3, WallLayout.Family.COTTAGE, 1.0)]
	var through := _path([[0.5, 7], [0.5, 0]], 0.45).meetings(w)
	check(w.path_doors(through[0].s, through[0].span, placed).is_empty(), "a path through a door already there opens none")
	var corner := _path([[3.9, 7], [3.9, 0]], 0.45).meetings(w)
	check(w.path_doors(corner[0].s, corner[0].span, none).is_empty(), "a path into a corner pier opens no door")
	var open := WallLayout.new()
	open.points = w.points
	open.closed = true
	open.build(Terrain.flat)
	check(_path([[0.5, 7], [0.5, 0]], 0.45).crossings(open).size() == 1 and not open.floored(), "a roofless loop is a wall, and a path through it opens an arch")


func _a_path_and_a_house_make_a_door_in_either_order() -> void:
	var nodes := _setup()
	var tool: WallTool = nodes[0]
	var world: World = nodes[2]
	var house := _put_house(nodes, Vector3(-30, 0, 0))
	_lay(nodes, Vector3(-29.5, 0, 7), Vector3(-29.5, 0, 0), 0.5)
	var made := _doors(house.layout)
	check(made.size() == 1 and made[0].lights == 1 and absf(made[0].half - 0.5) < 0.02, "a path laid into a house opens a door as wide as it: %s" % [made])
	check(world.state.walls[house.id].openings.is_empty(), "the door is the path's: the house stores none")
	world.undo()
	_lay_walls(tool)
	check(_doors(house.layout).is_empty() and world.state.paths.is_empty(), "undoing the path closes its door: %s" % [_doors(house.layout)])
	world.redo()
	_lay_walls(tool)
	check(_doors(house.layout).size() == 1, "redo opens it again: %s" % [_doors(house.layout)])
	_lay(nodes, Vector3(30.5, 0, 7), Vector3(30.5, 0, 0), 1.0)
	var second := _put_house(nodes, Vector3(30, 0, 0))
	made = _doors(second.layout)
	check(made.size() == 1 and made[0].lights == 2 and absf(made[0].half - 1.0) < 0.04, "a house put up over a wide path opens a double door as wide as the path: %s" % [made])
	world.undo()
	_lay_walls(tool)
	check(tool.find(second.id) == null, "undo takes the house")
	world.redo()
	_lay_walls(tool)
	second = tool.find(second.id)
	check(second != null and _doors(second.layout).size() == 1, "redo puts it back with its door: %s" % [_doors(second.layout) if second != null else []])
	var path_id: int = world.state.paths.keys().max()
	world.submit({"op": "take", "of": "paths", "ids": PackedInt32Array([path_id])})
	_lay_walls(tool)
	check(_doors(second.layout).is_empty(), "taking the path away closes the door: %s" % [_doors(second.layout)])
	world.undo()
	_lay_walls(tool)
	check(_doors(second.layout).size() == 1, "undoing that opens it again")
	_teardown(nodes)


## Puts up a house 8 m by 5 m with a gable roof centred on `at`, its front facing +z.
func _put_house(nodes: Array, at: Vector3) -> Wall:
	var world: World = nodes[2]
	var a := world.terrain.ground(at.x - 4, at.z)
	var b := world.terrain.ground(at.x + 4, at.z)
	var data := wall_data({"points": PackedVector3Array(WallLayout.rectangle(a, b, 5.0)), "seed": 3, "closed": true, "top": WallLayout.Top.CAP, "roof": {"kind": RoofLayout.Kind.GABLE, "center": world.terrain.ground(at.x, at.z), "radius": 2.5, "pitch": 1.4, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}})
	world.submit({"op": "wall", "walls": [data]})
	_lay_walls(nodes[0])
	return nodes[0].walls[-1]


func _painting_skips_a_path() -> void:
	var nodes := _setup()
	var world: World = nodes[2]
	var flora: Flora = nodes[4]
	var t := FloraTool.new(nodes[3], flora, nodes[1], nodes[2])
	t.set_process(false)
	_lay(nodes, Vector3(20, 0, -20), Vector3(30, 0, -20), 1.5)
	world.marks.settle()
	var before := flora.grass.size()
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.GRASS
	t.paint(b, world.terrain.ground(25, -20), 0.8, 1.0)
	check(flora.ghost_grass.size() == 0, "grass painted on a path shows no plants (%d)" % flora.ghost_grass.size())
	t.end_stroke(b)
	check(flora.grass.size() == before, "and grows none in the garden (%d added)" % (flora.grass.size() - before))
	t.free()
	_teardown(nodes)


func _a_scripted_stroke_outlasts_the_hand() -> void:
	var nodes := _setup()
	var world: World = nodes[2]
	var rig: Rig = nodes[3]
	var t := FloraTool.new(rig, nodes[4], nodes[1], nodes[2])
	t.set_process(false)
	var paths: Paths = nodes[1]
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.PATH
	t.begin_path(b, world.terrain.ground(-30, 20), 0.6)
	rig.aim_hand = b.hand
	t._handle(b, 1.0 / 60.0)
	rig.aim_hand = null
	check(paths.drawing != null, "a stroke no button holds outlasts the hand's own frame")
	t.end_path(b)
	t.free()
	_teardown(nodes)


func _undo_lifts_a_path_and_its_arches(kind := Hand.Tool.PATH) -> void:
	var nodes := _setup()
	var world: World = nodes[2]
	world.marks.install()
	var t := FloraTool.new(nodes[3], nodes[4], nodes[1], nodes[2])
	t.set_process(false)
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 60), Vector3(8, 0, 60))
	_reshape(nodes, w, {"openings": PackedVector4Array()})
	var b := t.brushes[1]
	b.hand.tool = kind
	t.begin_path(b, world.terrain.ground(2, 54), 0.6)
	for i in 41:
		t.extend_path(world.terrain.ground(2, 54 + i * 0.3), 0.6)
	t.end_path(b)
	_lay_walls(nodes[0])
	var paths: Paths = nodes[1]
	check(paths.layouts.size() == 1 and w.layout.archways().size() == 1, "the path is laid and opens its arch: %s" % [w.layout.archways()])
	world.undo()
	_lay_walls(nodes[0])
	check(paths.layouts.is_empty() and world.marks.bare(2, 57) == 0.0, "undo lifts the path and its wear (%.2f)" % world.marks.bare(2, 57))
	check(w.layout.archways().is_empty(), "undo closes the arch the path opened: %s" % [w.layout.archways()])
	world.redo()
	_lay_walls(nodes[0])
	world.marks.settle()
	check(paths.layouts.size() == 1 and world.marks.bare(2, 57) > 0.99 and w.layout.archways().size() == 1, "redo lays it again, arch and all: %s" % [w.layout.archways()])
	var deleter := DeleteTool.new(nodes[3], nodes[0], t, world)
	var target := deleter.aim(world.terrain.ground(2, 57) + Vector3.UP * 2, Vector3.DOWN)
	check(target.has("laid"), "Delete selects a path away from its wall crossing")
	deleter.press(deleter, world.terrain.ground(2, 57) + Vector3.UP * 2, Vector3.DOWN)
	deleter.let_go(deleter)
	_lay_walls(nodes[0])
	check(paths.layouts.is_empty() and w.layout.archways().is_empty(), "Delete lifts path and closes its arch")
	world.undo()
	_lay_walls(nodes[0])
	check(paths.layouts.size() == 1 and w.layout.archways().size() == 1, "undo restores deleted path and arch")
	deleter.free()
	t.free()
	_teardown(nodes)


func _draw_wall(tool: WallTool, a: Vector3, b: Vector3) -> Wall:
	var m: WallTool.Mason = tool.masons[0]
	tool.begin_stroke(m, tool.world.terrain.ground(a.x, a.z))
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		tool.extend_stroke(m, tool.world.terrain.ground(p.x, p.z))
	tool.end_stroke(m)
	_lay_walls(tool)
	return tool.walls[-1]


func _lay_walls(tool: WallTool) -> void:
	for w in tool.walls:
		w.lay_now()


## Draws a path and sends it to the garden, as the path tool does.
func _lay(nodes: Array, a: Vector3, b: Vector3, half: float) -> void:
	var world: World = nodes[2]
	var paths: Paths = nodes[1]
	paths.begin(world.terrain.ground(a.x, a.z), half)
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		paths.extend(world.terrain.ground(p.x, p.z), half)
	var ghost := paths.end()
	world.submit({"op": "path", "path": ghost.data}, paths.drop.bind(ghost))
	_lay_walls(nodes[0])


func _reshape(nodes: Array, w: Wall, data: Dictionary) -> void:
	(nodes[2] as World).submit({"op": "reshape", "of": "walls", "id": w.id, "data": data})
	_lay_walls(nodes[0])


## Relays look again only at the walls in the cells a stroke's moving end left or reached; what each wall shows is what
## cutting every wall from scratch shows.
func _a_stroke_over_many_walls_previews_as_one_cut_whole() -> void:
	var nodes := _setup()
	var tool: WallTool = nodes[0]
	var paths: Paths = nodes[1]
	var world: World = nodes[2]
	var walls: Array[Wall] = []
	for z in [20.0, 24.0, 28.0, 32.0]:
		walls.append(_draw_wall(tool, Vector3(-8, 0, z), Vector3(8, 0, z)))
	paths.begin(world.terrain.ground(1, 18), 0.6)
	var differ := 0
	for i in 40:
		var z := 18 + i * 0.4
		paths.extend(world.terrain.ground(1 + 0.15 * sin(i * 0.5), z), 0.6)
		paths._relay()
		# The tip reaches over the next wall and draws back from it, as a hand overshooting does.
		if i % 10 == 2:
			var pts := paths.drawing.points
			pts[-1] = pts[-1] + Vector3(0, 0, 1.6)
			paths._dirty = true
			paths._relay()
			pts[-1] = pts[-1] - Vector3(0, 0, 1.6)
			paths._relay()
		for w in walls:
			var shown := w.layout.openings.duplicate()
			w.layout.openings.assign(tool._path_openings[w.id])
			for p in paths.previews:
				tool._cut_crossings(w, p)
			if w.layout.openings != shown:
				differ += 1
			w.layout.openings = shown
	check(differ == 0, "a stroke's relays open the arches cutting every wall again would: %d relays differ" % differ)
	check(walls.all(func(w: Wall) -> bool: return w.layout.openings.size() == 1), "each wall the stroke crossed shows its arch: %s" % [walls.map(func(w: Wall) -> int: return w.layout.openings.size())])
	paths.forget()
	_teardown(nodes)


## Laid, a stroke's walls keep the arches its ghost showed, as cutting each again from the paths laid would leave them,
## without laying a wall again.
func _a_stroke_laid_keeps_the_arches_its_ghost_showed() -> void:
	var nodes := _setup()
	var tool: WallTool = nodes[0]
	var paths: Paths = nodes[1]
	var world: World = nodes[2]
	var walls: Array[Wall] = []
	for z in [40.0, 44.0, 48.0]:
		walls.append(_draw_wall(tool, Vector3(-8, 0, z), Vector3(8, 0, z)))
	_lay(nodes, Vector3(-5, 0, 37), Vector3(-5, 0, 51), 0.6)
	paths.begin(world.terrain.ground(2, 38), 0.6)
	for i in 30:
		paths.extend(world.terrain.ground(2, 38 + i * 0.4), 0.6)
		paths._relay()
	_lay_walls(tool)
	var laid := walls.map(func(w: Wall) -> int: return w.layout.laid)
	var ghost := paths.end()
	world.submit({"op": "path", "path": ghost.data}, paths.drop.bind(ghost))
	check(walls.all(func(w: Wall) -> bool: return not w.laying()) and walls.map(func(w: Wall) -> int: return w.layout.laid) == laid, "laying the stroke lays no wall again")
	var differ := 0
	for w in walls:
		var shown := w.layout.openings.duplicate()
		var kept: Array = tool._path_openings[w.id].duplicate()
		tool._open_paths(w)
		if w.layout.openings != shown or tool._path_openings[w.id] != kept:
			differ += 1
	check(differ == 0 and walls.all(func(w: Wall) -> bool: return w.layout.openings.size() == 2), "each wall keeps both paths' arches, as cut again: %d differ" % differ)
	_teardown(nodes)


func _a_path_opens_its_arch_before_release() -> void:
	var nodes := _setup()
	var paths: Paths = nodes[1]
	var world: World = nodes[2]
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 0), Vector3(8, 0, 0))
	paths.begin(world.terrain.ground(3, 4), 0.6)
	paths.extend(world.terrain.ground(3, 1), 0.6)
	paths._relay()
	check(w.layout.openings.is_empty(), "a path approaching a wall leaves it solid")
	paths.extend(world.terrain.ground(3, -1), 0.6)
	paths._relay()
	check(w.layout.openings.size() == 1 and paths.drawing != null, "crossing opens an arch while the stroke is held")
	check(world.state.paths.is_empty() and world.state.walls[w.id].openings.is_empty(), "the preview changes no saved garden data")
	while w.laying():
		await process_frame
	check(w.layout.archways().size() == 1, "the worker renders the arch before release")
	var laid := w.layout.laid
	paths.extend(world.terrain.ground(3, -2), 0.6)
	paths._relay()
	check(not w.laying() and w.layout.laid == laid, "an unchanged crossing does not rebuild the wall")
	var ghost := paths.end()
	check(w.layout.openings.size() == 1, "the sent ghost keeps its arch while awaiting acceptance")
	paths.drop(ghost)
	while w.laying():
		await process_frame
	check(w.layout.archways().is_empty(), "a rejected ghost closes its preview arch")
	paths.begin(world.terrain.ground(3, 4), 0.6)
	paths.extend(world.terrain.ground(3, -1), 0.6)
	paths._relay()
	paths.forget()
	while w.laying():
		await process_frame
	check(w.layout.archways().is_empty(), "forgetting the stroke closes its preview arch")
	paths.begin(world.terrain.ground(3, 0.1), 0.6)
	paths.extend(world.terrain.ground(3, -0.1), 0.6)
	paths._relay()
	check(w.layout.openings.size() == 1, "a short crossing previews its opening")
	paths.extend(world.terrain.ground(3, 0.3), 0.6)
	paths._relay()
	check(w.layout.openings.is_empty(), "moving the unsettled tip back closes the crossing")
	check(paths.end().is_empty() and paths.previews.is_empty(), "a discarded short stroke leaves no preview")
	_teardown(nodes)


## A path's command wears the garden's mask before anything reads it, and the shown mask over the frames after, a few
## rows a frame, not in the frame it lands.
func _a_laid_path_wears_the_garden_at_once_and_shows_by_the_next_frame() -> void:
	var nodes := _setup()
	var world: World = nodes[2]
	world.marks.install()
	_lay(nodes, Vector3(-40, 0, 70), Vector3(-30, 0, 70), 0.8)
	check(world.marks.bare(-35, 70) == 0.0, "the landing frame leaves the shown mask as it was (%.2f)" % world.marks.bare(-35, 70))
	var frames := 0
	while world.marks.bare(-35, 70) <= 0.99 and frames < 30:
		await process_frame
		frames += 1
	check(world.marks.bare(-35, 70) > 0.99, "the frames after show the path's wear (%.2f after %d)" % [world.marks.bare(-35, 70), frames])
	var worn := world.marks.laid.get_data()
	world.marks.rewear()
	check(world.marks.laid.get_data() == worn, "worn a few rows a frame, the mask is the one worn whole")
	_lay(nodes, Vector3(-40, 0, 75), Vector3(-10, 0, 85), 0.8)
	await process_frame
	await process_frame
	check(world.marks.laid_bare(-25, 80) > 0.99, "the garden's mask has it as soon as it is read (%.2f)" % world.marks.laid_bare(-25, 80))
	worn = world.marks.laid.get_data()
	world.marks.rewear()
	check(world.marks.laid.get_data() == worn, "read part way through its wear, the mask is the one worn whole")
	_teardown(nodes)


func _dirt_wears_without_stones() -> void:
	marks.install()
	var paths := _paths()
	paths.begin(Vector3(-20, 0, -20), 0.8)
	paths.extend(Vector3(-10, 0, -20), 0.8)
	var ghost := paths.end()
	check(paths.get_child_count() == 0, "dirt creates no stones or stone nodes")
	marks.settle()
	check(marks.bare(-15, -20) > 0.99, "dirt wears the stroke centre")
	var soft := false
	for i in 20:
		var edge := marks.bare(-15, -20 + i * 0.1)
		soft = soft or (edge > 0.0 and edge < 1.0)
	check(soft, "dirt has partially worn texels along its edge")
	check(marks.bare(-15, -18) == 0.0, "ground outside dirt stays meadow")
	var data: Dictionary = Commands._path(ghost.data)
	paths.drop(ghost)
	paths.put(123, data)
	check(marks.mark_at(-15, -20) == 123 and marks.mark_at(-15, -18) == -1, "path selection follows the stroke width")
	paths.take(123)
	await process_frame
	check(marks.bare(-15, -20) == 0.0, "taking dirt restores the meadow")
	data.style = "invalid"
	check(Commands._path(data) == null, "extra path fields are rejected")
	paths.free()


## Both edges carry a timber run from the ground at the foot to the ground at the head, its top standing proud of every
## tread it passes, with no break along it.
func _stringers_carry_the_flight(treads: Array, timbers: Array, ground: Callable) -> void:
	check(timbers.size() >= 4, "a flight has a stringer on either edge: %d timbers" % timbers.size())
	for edge in [-1.0, 1.0]:
		var run := timbers.filter(func(p: Dictionary) -> bool: return signf(p.xform.origin.x) == edge)
		check(run.size() * 2 == timbers.size(), "the stringers stand at either edge")
		run.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.xform.origin.z > b.xform.origin.z)
		var foot: Transform3D = run[0].xform
		var head: Transform3D = run[-1].xform
		var foot_end := foot.origin + foot.basis.z * 0.5 * signf(foot.basis.z.z)
		var head_end := head.origin - head.basis.z * 0.5 * signf(head.basis.z.z)
		check(foot_end.y - foot.basis.y.length() * 0.5 <= ground.call(foot_end.x, foot_end.z), "the stringer meets the ground at the flight's foot")
		check(head_end.y - head.basis.y.length() * 0.5 <= ground.call(head_end.x, head_end.z), "the stringer meets the ground at the flight's head")
		for i in run.size() - 1:
			var a: Transform3D = run[i].xform
			var b: Transform3D = run[i + 1].xform
			var a_end := a.origin + a.basis.z * 0.5 * -signf(a.basis.z.z)
			var b_start := b.origin + b.basis.z * 0.5 * signf(b.basis.z.z)
			check(signf(a_end.z - b_start.z) <= 0.0, "consecutive stringer timbers overlap")
	for tread in treads:
		var x: Transform3D = tread.xform
		var top := x.origin.y + x.basis.y.length() * 0.5
		var edge := absf(x.origin.x) + x.basis.x.length() * 0.5
		var beside := timbers.filter(func(p: Dictionary) -> bool: return absf(p.xform.origin.z - x.origin.z) < 0.3)
		check(beside.any(func(p: Dictionary) -> bool: return absf(p.xform.origin.x) >= edge - 0.05), "a stringer runs beside every tread")


## Neighbouring stones overlap across the width and along the flight, so nothing beneath shows between them.
func _no_gaps_between_treads(treads: Array) -> void:
	for a in treads:
		var xa: Transform3D = a.xform
		var near := treads.filter(func(b: Dictionary) -> bool: return b != a and absf(b.xform.origin.z - xa.origin.z) < 0.01 and absf(b.xform.origin.x - xa.origin.x) < xa.basis.x.length() * 1.5)
		for b in near:
			var xb: Transform3D = b.xform
			check(absf(xb.origin.x - xa.origin.x) < (xa.basis.x.length() + xb.basis.x.length()) * 0.5, "stones side by side in a tread overlap")
	var rows := {}
	for t in treads:
		rows[snappedf(t.xform.origin.z, 0.001)] = t.xform
	var zs := rows.keys()
	zs.sort()
	for i in zs.size() - 1:
		var a: Transform3D = rows[zs[i]]
		var b: Transform3D = rows[zs[i + 1]]
		check(zs[i + 1] - zs[i] < (a.basis.z.length() + b.basis.z.length()) * 0.5, "consecutive treads overlap along the flight")


func _steep_paths_lay_level_treads() -> void:
	var path := PathLayout.new()
	path.add(Vector3.ZERO, 0.8)
	path.add(Vector3(0, 0, -4), 0.8)
	path.plan()
	var flat := Terrain.flat
	var slope := func(_x: float, z: float) -> float: return -z * 0.8
	check(path.pieces(flat).is_empty(), "flat dirt has no treads")
	var pieces := path.pieces(slope)
	var treads := pieces.filter(func(p: Dictionary) -> bool: return p.kind == "block")
	var timbers := pieces.filter(func(p: Dictionary) -> bool: return p.kind == "timber")
	check(treads.size() > 30, "steep dirt lays a flight of stone treads")
	check(treads.size() + timbers.size() == pieces.size(), "a flight is stone treads and timber stringers")
	for tread in treads:
		var x: Transform3D = tread.xform
		check(x.basis.y.normalized().is_equal_approx(Vector3.UP), "tread top is horizontal")
		var back := x.origin + x.basis.z * 0.5
		var front := x.origin - x.basis.z * 0.5
		var top := x.origin.y + x.basis.y.length() * 0.5
		check(top >= maxf(slope.call(back.x, back.z), slope.call(front.x, front.z)) - 0.01, "tread is above its sloping ground")
	_stringers_carry_the_flight(treads, timbers, slope)
	_no_gaps_between_treads(treads)
	var extreme := path.pieces(func(_x: float, z: float) -> float: return -z * 100.0)
	check(extreme.size() == pieces.size(), "raising terrain cannot multiply reserved geometry")
	for piece in extreme.filter(func(p: Dictionary) -> bool: return p.kind == "block"):
		var x: Transform3D = piece.xform
		var uphill := x.origin - x.basis.z * 0.5
		check(x.origin.y + x.basis.y.length() * 0.5 >= -uphill.z * 100.0, "the full tread footprint clears very steep ground")
	check(path.pieces(slope) == pieces, "steps rebuild deterministically")
	check(path.pieces(flat).is_empty(), "flattening a path removes its steps")
	var reserved := Budget.path(path.data())
	check(reserved.wall_m2 >= treads.size() * 0.1 and reserved.timber >= timbers.size(), "flat paths reserve their possible treads and stringers before terrain is raised: %s" % reserved)


## A path of each surface laid by the garden.
func _laid(paths: Paths, id: int, surface: PathLayout.Surface, points: Array, half: float) -> PathLayout:
	var p := _path(points, half)
	p.surface = surface
	p.seed = id
	paths.put(id, Commands._path(p.data()))
	marks.settle()
	return paths.layouts[-1]


## Each surface wears its own ground into the mask, in full down the middle of the stroke: dirt and a bed earth, a bed's
## tilled and dirt's not, sand sand, cobbles and flagstones stone in their styles; and each is the mark found there.
func _each_surface_wears_its_own_ground() -> void:
	marks.install()
	var paths := _paths()
	var z := -60.0
	var expect := {
		PathLayout.Surface.DIRT: [Ground.Kind.EARTH, false],
		PathLayout.Surface.SAND: [Ground.Kind.SAND, false],
		PathLayout.Surface.COBBLES: [Ground.Kind.STONE, false],
		PathLayout.Surface.FLAGS: [Ground.Kind.STONE, false],
		PathLayout.Surface.BED: [Ground.Kind.EARTH, true],
	}
	for surface: PathLayout.Surface in expect:
		var id := 500 + surface
		_laid(paths, id, surface, [[-50, z], [-40, z]], 0.8)
		var name: String = PathLayout.Surface.find_key(surface)
		check(marks.bare(-45, z) > 0.99 and kind_at(marks, -45, z) == expect[surface][0], "%s wears the ground to its kind: %s" % [name, kind_at(marks, -45, z)])
		check(tilled(marks, -45, z) == expect[surface][1], "%s is %stilled" % [name, "" if expect[surface][1] else "not "])
		if expect[surface][0] == Ground.Kind.STONE:
			check(marks._texel(-45, z, marks.laid).b8 & ~Ground.TILLED == PathLayout.look(surface), "%s lays stone in its own style" % name)
		check(marks.mark_at(-45, z) == id, "the %s path is the mark found on it" % name)
		check(marks.bare(-45, z + 2.0) == 0.0, "the meadow beside the %s path is untouched" % name)
		z -= 4.0
	check(StoneStyles.STYLES[PathLayout.look(PathLayout.Surface.COBBLES)].name == "river cobble" and StoneStyles.STYLES[PathLayout.look(PathLayout.Surface.FLAGS)].name == "mossy", "cobbles and flagstones are the river cobble and mossy stone styles")
	var reserved := Budget.path(paths.layouts[PathLayout.Surface.COBBLES].data())
	check(reserved.get("stone_m2", 0.0) > 10.0 and not Budget.path(paths.layouts[PathLayout.Surface.SAND].data()).has("stone_m2"), "cobbles count their ground as painted stone, sand none: %s" % reserved)
	paths.free()


## Where two surfaces meet, the later one lies over the earlier down its middle and the two blend across its soft edge,
## each texel there part of each, with no meadow showing between them; lifting the later gives the earlier back.
func _surfaces_blend_where_they_meet() -> void:
	marks.install()
	var paths := _paths()
	_laid(paths, 601, PathLayout.Surface.SAND, [[-50, -70], [-40, -70]], 1.5)
	_laid(paths, 602, PathLayout.Surface.DIRT, [[-45, -65], [-45, -75]], 0.8)
	check(kind_at(marks, -45, -70) == Ground.Kind.EARTH and kind_at(marks, -48, -70) == Ground.Kind.SAND, "the later dirt lies over the sand down its middle")
	var blended := 0
	for i in 20:
		var c := marks._texel(-45 + 0.5 + i * 0.1, -70, marks.laid)
		blended += 1 if c.r > 0.1 and c.a > 0.1 else 0
		check(c.r + c.a > 0.95, "no meadow shows between dirt and sand (%.2f)" % (c.r + c.a))
	check(blended >= 2, "dirt and sand blend across the dirt's edge: %d texels" % blended)
	paths.take(602)
	marks.settle()
	check(kind_at(marks, -45, -70) == Ground.Kind.SAND and marks._texel(-45, -70, marks.laid).a > 0.99, "lifting the dirt gives the sand back")
	paths.free()


## Across water a path lays flat stepping stones a stride apart, their tops just out of the water and their feet on the
## bed, and no treads; on the dry ground either side it lays none.
func _a_path_across_water_lays_stepping_stones() -> void:
	var path := _path([[-6, 0], [6, 0]], 0.6)
	var height := func(x: float, _z: float) -> float: return -0.3 * clampf(3.5 - absf(x), 0.0, 1.0)
	var level := -0.1
	var water := func(x: float, z: float) -> float: return level if absf(x) < 3.0 else height.call(x, z)
	check(path.pieces(height).is_empty(), "with no water a flat path lays nothing")
	var stones := path.pieces(height, water)
	check(stones.size() >= 7 and stones.size() <= 9, "a stone a stride across 6 m of water: %d" % stones.size())
	var xs: Array[float] = []
	for st in stones:
		var x: Transform3D = st.xform
		xs.append(x.origin.x)
		check(st.kind == "block" and absf(x.origin.x) < 3.0, "every stepping stone stands in the water")
		check(x.basis.y.normalized().is_equal_approx(Vector3.UP), "a stepping stone lies flat")
		var top := x.origin.y + x.basis.y.length() * 0.5
		check(top > level and top < level + 0.1, "its top stands just out of the water (%.2f)" % top)
		check(x.origin.y - x.basis.y.length() * 0.5 <= height.call(x.origin.x, x.origin.z), "its foot is on the bed")
	xs.sort()
	for i in xs.size() - 1:
		check(absf(xs[i + 1] - xs[i] - PathLayout.STRIDE) < 0.05, "stepping stones lie a stride apart")
	var bed := _path([[-6, 0], [6, 0]], 0.6)
	bed.surface = PathLayout.Surface.BED
	check(bed.pieces(height, water).all(func(p: Dictionary) -> bool: return p.kind == "block" or absf(p.xform.origin.x) > 3.0 - 0.3), "a bed across water sprouts nothing in it")


## A bed sprouts rows along it as many as its width holds, each row one crop, a plant every CROP_EVERY, standing on
## the ground inside the bed; a steep bed lays no treads, and the budget reserves every plant.
func _a_bed_sprouts_rows_of_vegetables() -> void:
	var bed := _path([[0, 0], [0, -6]], 1.0)
	bed.surface = PathLayout.Surface.BED
	var spots := bed.crop_spots()
	var rows := {}
	for spot in spots:
		var across := snappedf(spot.at.x, 0.01)
		if not rows.has(across):
			rows[across] = []
		rows[across].append(spot)
	var offsets := rows.keys()
	offsets.sort()
	check(offsets.size() == 5, "a 2 m bed holds five rows: %s" % [offsets])
	for i in offsets.size() - 1:
		check(absf(offsets[i + 1] - offsets[i] - PathLayout.CROP_ROWS) < 0.01, "rows lie CROP_ROWS apart")
	var crops := {}
	for across in rows:
		var row: Array = rows[across]
		check(row.all(func(spot: Dictionary) -> bool: return spot.crop == row[0].crop), "one crop down each row")
		check(row.size() >= 17, "a plant every CROP_EVERY down 6 m: %d" % row.size())
		crops[row[0].crop] = true
	check(crops.size() >= 2, "the rows grow more than one crop: %s" % [crops.keys()])
	var slope := func(_x: float, z: float) -> float: return -z * 0.8
	var pieces := bed.pieces(slope)
	check(pieces.size() >= spots.size() * 3 and pieces.all(func(p: Dictionary) -> bool: return p.kind == "crop"), "every plant is a few coloured pieces and a steep bed lays no treads: %d" % pieces.size())
	for p in pieces:
		var at: Vector3 = p.xform.origin
		check(absf(at.x) < 1.0 and at.y >= slope.call(at.x, at.z) - 0.1, "a plant stands on the ground inside its bed")
	check(Budget.path(bed.data()).wall_m2 >= pieces.size() * 0.1, "the budget reserves every plant: %s" % Budget.path(bed.data()))
	for crop in PathLayout.Crop.values():
		check(PathLayout.crop(crop).size() >= 3, "a %s is a few pieces" % PathLayout.Crop.find_key(crop))


## Dirt or a bed crossing stone leaves the stone it does not cover in its own style, stone over a bed leaves the bed
## tilled under it, and stone painted back to meadow over cobbles leaves the cobbled path's way worn and found there.
func _earth_and_stone_keep_their_looks() -> void:
	marks.install()
	var paths := _paths()
	_laid(paths, 701, PathLayout.Surface.COBBLES, [[-50, -40], [-40, -40]], 1.5)
	_laid(paths, 702, PathLayout.Surface.BED, [[-45, -35], [-45, -45]], 0.8)
	var kept := true
	for i in 30:
		var c := marks._texel(-45 + i * 0.1, -40, marks.laid)
		kept = kept and (c.g < 0.05 or c.b8 & ~Ground.TILLED == StoneStyles.RIVER_COBBLE)
	check(kept, "the cobbles the bed leaves keep their style")
	var r := FloraTool.MAX_RADIUS * 0.4
	var over := Ground.Stroke.new(Ground.Kind.STONE, StoneStyles.MOSSY)
	over.stamps = PackedVector4Array([Vector4(-45, -43, r, r * 2.0)])
	marks.lay(over, 703)
	var back := Ground.Stroke.new(Ground.Kind.MEADOW)
	back.stamps = PackedVector4Array([Vector4(-45, -43, r, r * 2.0), Vector4(-48, -40, r, r * 2.0)])
	marks.lay(back, 704)
	marks.settle()
	check(tilled(marks, -45, -43) and kind_at(marks, -45, -43) == Ground.Kind.EARTH, "stone painted over the bed and back leaves it tilled")
	check(marks.stone(-48, -40) < 0.05 and marks.laid_bare(-48, -40) > 0.99, "painted back over cobbles, the path's way stays worn")
	check(marks.mark_at(-48, -40) == 701, "and the cobbled path is found there")
	marks.lift(back)
	marks.lift(over)
	paths.free()
