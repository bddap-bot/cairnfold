extends SceneTree

## Headless checks of paths and wall chemistry: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_path.gd

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Ground.install()
	_a_path_across_a_wall_opens_one_arch()
	_a_wide_or_slanted_crossing_opens_an_arcade()
	_a_path_beside_a_wall_opens_nothing()
	_crossings_test_every_segment_pair_that_meets()
	_arcades_stand_on_pillars()
	_overlapping_arches_do_not_both_open()
	_the_mask_parts_the_path_only()
	_a_short_stroke_leaves_no_trace()
	_chemistry_works_in_either_order()
	_a_second_path_beside_an_arch_makes_an_arcade()
	_a_crossing_that_cannot_open_leaves_no_arch()
	_a_tower_opens_a_doorway_across_its_seam()
	_painting_skips_a_path()
	_a_scripted_stroke_outlasts_the_hand()
	_undo_lifts_a_path_and_its_arches()
	await _a_path_opens_its_arch_before_release()
	await _a_laid_path_wears_the_garden_at_once_and_shows_by_the_next_frame()
	await _dirt_wears_without_stones()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _flat(_x: float, _z: float) -> float:
	return 0.0


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
	w.build(_flat)
	return w


func _a_path_across_a_wall_opens_one_arch() -> void:
	var w := _wall([[0, 0], [10, 0]])
	var cut := _path([[4, -4], [4, 4]], 0.6).crossings(w)
	_check(cut.size() == 1, "a narrow square crossing opens one arch, got %s" % [cut])
	if cut.size() == 1:
		_check(absf(cut[0] - 4.0) < 0.05, "the arch opens where the path crosses, at %.2f" % cut[0])


func _a_wide_or_slanted_crossing_opens_an_arcade() -> void:
	var w := _wall([[0, 0], [16, 0]])
	var cut := _path([[8, -6], [8, 6]], 2.5).crossings(w)
	_check(cut.size() >= 2, "a 5 m wide crossing opens an arcade, got %s" % [cut])
	if not cut.is_empty():
		var lo: float = cut.min() - WallLayout.ARCH_HALF
		var hi: float = cut.max() + WallLayout.ARCH_HALF
		_check(lo <= 8.0 - 2.5 and hi >= 8.0 + 2.5, "the arcade's openings span the whole path: %.2f to %.2f" % [lo, hi])
	cut.sort()
	for i in range(1, cut.size()):
		_check(is_equal_approx(cut[i] - cut[i - 1], WallLayout.ARCADE_PITCH), "arcade arches stand a pitch apart: %s" % [cut])
	if not cut.is_empty():
		_check(absf((cut[0] + cut[-1]) * 0.5 - 8.0) < 0.05, "the arcade centres on the crossing: %s" % [cut])
	var slant := _path([[2, -1.2], [14, 1.2]], 0.9).crossings(w)
	_check(slant.size() >= 2, "a path meeting the wall at a shallow angle opens an arcade, got %s" % [slant])


func _a_path_beside_a_wall_opens_nothing() -> void:
	var w := _wall([[0, 0], [10, 0]])
	_check(_path([[0, 2], [10, 2]], 1.2).crossings(w).is_empty(), "a path alongside a wall opens nothing")
	_check(_path([[4, 1.5], [4, 6]], 1.2).crossings(w).is_empty(), "a path that stops short of a wall opens nothing")


## Crossings found through the grid match testing every path segment against every wall segment.
func _crossings_test_every_segment_pair_that_meets() -> void:
	var tower := WallLayout.new()
	for k in 7:
		tower.points.append(Vector3(cos(k * TAU / 7) * 4.0, 0, sin(k * TAU / 7) * 4.0))
	tower.closed = true
	tower.height = 3.0
	tower.build(_flat)
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
	_check(mismatched == 0, "crossings match every segment pair tested: %d of 90 differ" % mismatched)


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
	w.build(_flat)
	_check(w.archways().size() == w.openings.size(), "every arcade arch opens: %s of %s" % [w.archways(), w.openings])
	var pillars := w.pillars()
	_check(pillars.size() == w.archways().size() - 1, "%d pillars between %d arches" % [pillars.size(), w.archways().size()])
	var pillar_stones := w.stones.filter(func(s): return s.kind == "pillar")
	_check(pillar_stones.size() >= pillars.size() * 4, "each pillar is a stack of drums with plinth and capital (%d stones)" % pillar_stones.size())
	var lo: float = w.archways()[0] - WallLayout.ARCH_HALF
	var hi: float = w.archways()[-1] + WallLayout.ARCH_HALF
	for s in w.stones:
		if s.kind == "block" and s.y < w.spring() - 0.2 and absf(s.s - (lo + hi) * 0.5) < (hi - lo) * 0.5 - s.size.x * 0.5 + 0.01:
			_check(false, "a coursed block at s=%.2f y=%.2f fills the arcade below its springing" % [s.s, s.y])
			return
	for p in pillars:
		var here := pillar_stones.filter(func(s): return absf(s.s - p.s) < 0.01)
		var top := 0.0
		for s in here:
			top = maxf(top, s.y + s.size.y * 0.5)
		_check(top >= w.spring() - 0.05, "a pillar rises to the springing (%.2f of %.2f)" % [top, w.spring()])


func _overlapping_arches_do_not_both_open() -> void:
	var w := _wall([[0, 0], [12, 0]])
	w.openings.assign([5.0, 6.0].map(WallLayout.archway))
	w.build(_flat)
	_check(w.archways().size() == 1, "two arches whose rings overlap open as one: %s" % [w.archways()])


func _the_mask_parts_the_path_only() -> void:
	var paths := Paths.new()
	root.add_child(paths)
	paths.begin(Vector3(-10, 0, 20), 0.8)
	for i in 30:
		paths.extend(Vector3(-10 + i * 0.3, 0, 20), 0.8)
	var p := paths.end()
	_check(not p.is_empty() and p.layout.length() > 8.0, "a 9 m stroke is a path")
	Ground.settle()
	_check(Ground.bare(-5, 20) > 0.99, "the stroke centre is fully worn (%.2f)" % Ground.bare(-5, 20))
	_check(Ground.bare(-5, 20.7) > 0.5, "the stroke edge is worn (%.2f)" % Ground.bare(-5, 20.7))
	_check(Ground.bare(-5, 21.6) == 0.0, "the meadow a metre past the edge is untouched (%.2f)" % Ground.bare(-5, 21.6))
	_check(Ground.bare(10, 20) == 0.0, "the meadow past the end is untouched")
	paths.queue_free()


func _a_short_stroke_leaves_no_trace() -> void:
	var paths := Paths.new()
	root.add_child(paths)
	paths.begin(Vector3(30, 0, 30), 1.0)
	paths.extend(Vector3(30.4, 0, 30), 1.0)
	_check(paths.end().is_empty() and paths.layouts.is_empty(), "a stroke under a metre is dropped")
	_check(Ground.bare(30, 30) == 0.0, "a dropped stroke unwears the ground (%.2f)" % Ground.bare(30, 30))
	paths.queue_free()


func _chemistry_works_in_either_order() -> void:
	var nodes := _setup()
	var tool: WallTool = nodes[0]
	var paths: Paths = nodes[1]
	var first := _draw_wall(tool, Vector3(-8, 0, -12), Vector3(8, 0, -12))
	_reshape(nodes, first, {"openings": PackedVector4Array()})
	_lay(nodes, Vector3(2, 0, -18), Vector3(2, 0, -6), 0.6)
	_check(first.layout.archways().size() == 1 and absf(first.layout.archways()[0] - 10.0) < 0.1, "a path laid through a wall cuts an arch at the crossing: %s" % [first.layout.archways()])
	_lay(nodes, Vector3(-30, 0, -2), Vector3(-30, 0, 10), 2.5)
	var second := _draw_wall(tool, Vector3(-38, 0, 4), Vector3(-22, 0, 4))
	_check(second.layout.archways().size() >= 2 and second.layout.pillars().size() >= 1, "a wall drawn across a wide path opens an arcade: %s" % [second.layout.archways()])
	for a in second.layout.archways():
		_check(absf(a - 8.0) < WallLayout.ARCADE_PITCH * 1.5, "arcade arches stand over the path, not the wall's middle: %s" % [second.layout.archways()])
	_teardown(nodes)


## A wall tool, the paths, the garden and the rig, idle so a test drives them.
func _setup() -> Array:
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var paths := Paths.new()
	root.add_child(paths)
	var flora := Flora.new()
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
	_check(before.all(func(a): return w.layout.archways().has(a)), "a path beside the middle arch closes nothing: %s then %s" % [before, w.layout.archways()])
	_check(w.layout.archways().size() == before.size() + 1 and w.layout.pillars().size() == 1, "it opens a second arch on a shared pillar: %s" % [w.layout.archways()])
	_lay(nodes, Vector3(0.2, 0, 24), Vector3(0.2, 0, 36), 0.5)
	_check(w.layout.archways().size() == before.size() + 1, "a path through an opening that is already there adds none: %s" % [w.layout.archways()])
	_teardown(nodes)


func _a_crossing_that_cannot_open_leaves_no_arch() -> void:
	var nodes := _setup()
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 40), Vector3(8, 0, 40))
	var before := w.layout.openings.duplicate()
	_lay(nodes, Vector3(-7.6, 0, 34), Vector3(-7.6, 0, 46), 0.5)
	_check(w.layout.openings == before, "a crossing at a wall's end records no arch: %s" % [w.layout.openings])
	var low := _draw_wall(nodes[0], Vector3(-8, 0, 50), Vector3(8, 0, 50))
	_reshape(nodes, low, {"height": 1.2, "openings": PackedVector4Array()})
	_lay(nodes, Vector3(0, 0, 44), Vector3(0, 0, 56), 0.5)
	_check(low.layout.openings.is_empty(), "a wall too low to arch records none: %s" % [low.layout.openings])
	_teardown(nodes)


func _a_tower_opens_a_doorway_across_its_seam() -> void:
	var w := WallLayout.new()
	w.points = WallLayout.circle(Vector3.ZERO, 1.3)
	w.closed = true
	w.height = 4.5
	w.build(_flat)
	var cut := _path([[-1, 0.15], [4, 0.15]], 0.5).crossings(w)
	_check(cut.size() == 1, "a path into a tower crosses its wall once there, got %s" % [cut])
	if cut.size() == 1:
		var a := w.wrap(cut[0])
		_check(w.opening_fits(WallLayout.archway(a), []), "a doorway fits beside the tower's seam at %.2f of %.2f" % [a, w.length()])
		w.openings.assign([a].map(WallLayout.archway))
		w.build(_flat)
		_check(w.archways().size() == 1, "the doorway opens")
		var t := WallLayout.new()
		t.points = w.points
		t.closed = true
		t.height = 4.5
		t.openings.assign([w.wrap(a - 1.0)].map(WallLayout.archway))
		t.build(_flat)
		var nodes := _setup()
		var tower := Wall.new(1, nodes[0].masonry)
		tower.layout = t
		nodes[0].walls.append(tower)
		var opened: Array[float] = nodes[0]._cut_crossings(tower, _path([[-1, 0.15], [4, 0.15]], 0.5))
		_check(opened.size() == 1 and absf(t.offset(opened[0], w.wrap(a - 1.0))) > WallLayout.ARCH_SPACING - 0.01, "a crossing beside an arch across the seam stands a pitch from it: %s beside %.2f" % [opened, w.wrap(a - 1.0)])
		t.build(_flat)
		_check(t.pillars().size() == 1, "the pair across the seam shares a pillar: %s" % [t.pillars()])
		nodes[0].walls.clear()
		tower.free()
		_teardown(nodes)
		var blocks := w.stones.filter(func(s): return s.kind == "block" and s.y < w.spring())
		_check(not blocks.any(func(s): return Vector2(s.xform.origin.x - 1.3, s.xform.origin.z - 0.15).length() < WallLayout.ARCH_HALF - 0.2), "no block fills the doorway across the seam")


func _painting_skips_a_path() -> void:
	var nodes := _setup()
	var flora: Flora = nodes[4]
	var t := FloraTool.new(nodes[3], flora, nodes[1], nodes[2])
	t.set_process(false)
	_lay(nodes, Vector3(20, 0, -20), Vector3(30, 0, -20), 1.5)
	var before := flora.grass.size()
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.GRASS
	t.paint(b, Terrain.ground(25, -20), 0.8, 1.0)
	_check(flora.ghost_grass.size() == 0, "grass painted on a path shows no plants (%d)" % flora.ghost_grass.size())
	t.end_stroke(b)
	_check(flora.grass.size() == before, "and grows none in the garden (%d added)" % (flora.grass.size() - before))
	t.free()
	_teardown(nodes)


func _a_scripted_stroke_outlasts_the_hand() -> void:
	var nodes := _setup()
	var rig: Rig = nodes[3]
	var t := FloraTool.new(rig, nodes[4], nodes[1], nodes[2])
	t.set_process(false)
	var paths: Paths = nodes[1]
	var b := t.brushes[0]
	b.hand.tool = Hand.Tool.DIRT_PATH
	t.begin_path(b, Terrain.ground(-30, 20), 0.6)
	rig.aim_hand = b.hand
	t._handle(b, 1.0 / 60.0)
	rig.aim_hand = null
	_check(paths.drawing != null, "a stroke no button holds outlasts the hand's own frame")
	t.end_path(b)
	t.free()
	_teardown(nodes)


func _undo_lifts_a_path_and_its_arches(kind := Hand.Tool.DIRT_PATH) -> void:
	Ground.install()
	var nodes := _setup()
	var t := FloraTool.new(nodes[3], nodes[4], nodes[1], nodes[2])
	t.set_process(false)
	var world: World = nodes[2]
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 60), Vector3(8, 0, 60))
	_reshape(nodes, w, {"openings": PackedVector4Array()})
	var b := t.brushes[1]
	b.hand.tool = kind
	t.begin_path(b, Terrain.ground(2, 54), 0.6)
	for i in 41:
		t.extend_path(Terrain.ground(2, 54 + i * 0.3), 0.6)
	t.end_path(b)
	_lay_walls(nodes[0])
	var paths: Paths = nodes[1]
	_check(paths.layouts.size() == 1 and w.layout.archways().size() == 1, "the path is laid and opens its arch: %s" % [w.layout.archways()])
	world.undo()
	_lay_walls(nodes[0])
	_check(paths.layouts.is_empty() and Ground.bare(2, 57) == 0.0, "undo lifts the path and its wear (%.2f)" % Ground.bare(2, 57))
	_check(w.layout.archways().is_empty(), "undo closes the arch the path opened: %s" % [w.layout.archways()])
	world.redo()
	_lay_walls(nodes[0])
	Ground.settle()
	_check(paths.layouts.size() == 1 and Ground.bare(2, 57) > 0.99 and w.layout.archways().size() == 1, "redo lays it again, arch and all: %s" % [w.layout.archways()])
	var deleter := DeleteTool.new(nodes[3], nodes[0], t, world)
	var target := deleter.aim(Terrain.ground(2, 57) + Vector3.UP * 2, Vector3.DOWN)
	_check(target.has("laid"), "Delete selects a path away from its wall crossing")
	deleter.press(deleter, Terrain.ground(2, 57) + Vector3.UP * 2, Vector3.DOWN)
	deleter.let_go(deleter)
	_lay_walls(nodes[0])
	_check(paths.layouts.is_empty() and w.layout.archways().is_empty(), "Delete lifts path and closes its arch")
	world.undo()
	_lay_walls(nodes[0])
	_check(paths.layouts.size() == 1 and w.layout.archways().size() == 1, "undo restores deleted path and arch")
	deleter.free()
	t.free()
	_teardown(nodes)


func _draw_wall(tool: WallTool, a: Vector3, b: Vector3) -> Wall:
	var m: WallTool.Mason = tool.masons[0]
	tool.begin_stroke(m, Terrain.ground(a.x, a.z))
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		tool.extend_stroke(m, Terrain.ground(p.x, p.z))
	tool.end_stroke(m)
	_lay_walls(tool)
	return tool.walls[-1]


func _lay_walls(tool: WallTool) -> void:
	for w in tool.walls:
		w.lay_now()


## Draws a path and sends it to the garden, as the path tool does.
func _lay(nodes: Array, a: Vector3, b: Vector3, half: float) -> void:
	var paths: Paths = nodes[1]
	paths.begin(Terrain.ground(a.x, a.z), half)
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		paths.extend(Terrain.ground(p.x, p.z), half)
	var ghost := paths.end()
	(nodes[2] as World).submit({"op": "path", "path": ghost.data}, paths.drop.bind(ghost))
	_lay_walls(nodes[0])


func _reshape(nodes: Array, w: Wall, data: Dictionary) -> void:
	(nodes[2] as World).submit({"op": "reshape", "of": "walls", "id": w.id, "data": data})
	_lay_walls(nodes[0])


func _a_path_opens_its_arch_before_release() -> void:
	var nodes := _setup()
	var paths: Paths = nodes[1]
	var world: World = nodes[2]
	var w := _draw_wall(nodes[0], Vector3(-8, 0, 0), Vector3(8, 0, 0))
	paths.begin(Terrain.ground(3, 4), 0.6)
	paths.extend(Terrain.ground(3, 1), 0.6)
	paths._relay()
	_check(w.layout.openings.is_empty(), "a path approaching a wall leaves it solid")
	paths.extend(Terrain.ground(3, -1), 0.6)
	paths._relay()
	_check(w.layout.openings.size() == 1 and paths.drawing != null, "crossing opens an arch while the stroke is held")
	_check(world.state.paths.is_empty() and world.state.walls[w.id].openings.is_empty(), "the preview changes no saved garden data")
	while w.laying():
		await process_frame
	_check(w.layout.archways().size() == 1, "the worker renders the arch before release")
	var laid := w.layout.laid
	paths.extend(Terrain.ground(3, -2), 0.6)
	paths._relay()
	_check(not w.laying() and w.layout.laid == laid, "an unchanged crossing does not rebuild the wall")
	var ghost := paths.end()
	_check(w.layout.openings.size() == 1, "the sent ghost keeps its arch while awaiting acceptance")
	paths.drop(ghost)
	while w.laying():
		await process_frame
	_check(w.layout.archways().is_empty(), "a rejected ghost closes its preview arch")
	paths.begin(Terrain.ground(3, 4), 0.6)
	paths.extend(Terrain.ground(3, -1), 0.6)
	paths._relay()
	paths.forget()
	while w.laying():
		await process_frame
	_check(w.layout.archways().is_empty(), "forgetting the stroke closes its preview arch")
	paths.begin(Terrain.ground(3, 0.1), 0.6)
	paths.extend(Terrain.ground(3, -0.1), 0.6)
	paths._relay()
	_check(w.layout.openings.size() == 1, "a short crossing previews its opening")
	paths.extend(Terrain.ground(3, 0.3), 0.6)
	paths._relay()
	_check(w.layout.openings.is_empty(), "moving the unsettled tip back closes the crossing")
	_check(paths.end().is_empty() and paths.previews.is_empty(), "a discarded short stroke leaves no preview")
	_teardown(nodes)


## A path's command wears the garden's mask before anything reads it, and the shown mask a frame later, not in the
## frame it lands.
func _a_laid_path_wears_the_garden_at_once_and_shows_by_the_next_frame() -> void:
	Ground.install()
	var nodes := _setup()
	_lay(nodes, Vector3(-40, 0, 70), Vector3(-30, 0, 70), 0.8)
	_check(Ground.bare(-35, 70) == 0.0, "the landing frame leaves the shown mask as it was (%.2f)" % Ground.bare(-35, 70))
	for i in 2:
		await process_frame
	_check(Ground.bare(-35, 70) > 0.99, "the next frame shows the path's wear (%.2f)" % Ground.bare(-35, 70))
	_lay(nodes, Vector3(-40, 0, 75), Vector3(-30, 0, 75), 0.8)
	_check(Ground.laid_bare(-35, 75) > 0.99, "the garden's mask has it as soon as it is read (%.2f)" % Ground.laid_bare(-35, 75))
	_teardown(nodes)


func _dirt_wears_without_stones() -> void:
	Ground.install()
	var paths := Paths.new()
	root.add_child(paths)
	paths.begin(Vector3(-20, 0, -20), 0.8)
	paths.extend(Vector3(-10, 0, -20), 0.8)
	var ghost := paths.end()
	_check(paths.get_child_count() == 0, "dirt creates no stones or stone nodes")
	Ground.settle()
	_check(Ground.bare(-15, -20) > 0.99, "dirt wears the stroke centre")
	var soft := false
	for i in 20:
		var edge := Ground.bare(-15, -20 + i * 0.1)
		soft = soft or (edge > 0.0 and edge < 1.0)
	_check(soft, "dirt has partially worn texels along its edge")
	_check(Ground.bare(-15, -18) == 0.0, "ground outside dirt stays meadow")
	var data: Dictionary = Commands._path(ghost.data)
	paths.drop(ghost)
	paths.put(123, data)
	_check(Ground.mark_at(-15, -20) == 123 and Ground.mark_at(-15, -18) == -1, "path selection follows the stroke width")
	paths.take(123)
	await process_frame
	_check(Ground.bare(-15, -20) == 0.0, "taking dirt restores the meadow")
	data.style = "invalid"
	_check(Commands._path(data) == null, "extra path fields are rejected")
	paths.free()
