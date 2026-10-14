extends SceneTree

## Headless checks of sheep: godot4 --headless --path game --script ../tests/test_sheep.gd

const STEP := 1.0 / 30.0
const AWAY := Vector3(0, -50, 0)

var failures := 0


func _initialize() -> void:
	Terrain.install()
	Ground.install()
	await process_frame
	_no_tool_places_a_sheep()
	_the_sheep_is_one_small_mesh()
	await _fences_draw_a_flock()
	await _the_same_seed_brings_the_same_flock()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


class Glade:
	var rig: Rig
	var world: World
	var walls: WallTool
	var water: Water
	var digger: WaterTool
	var flora: Flora
	var wildlife: Wildlife

	func sheep() -> Array[Sheep]:
		return wildlife.herds.all()


func _glade(seed: int) -> Glade:
	var g := Glade.new()
	g.rig = Rig.new()
	root.add_child(g.rig)
	g.world = World.new()
	root.add_child(g.world)
	var paths := Paths.new()
	root.add_child(paths)
	g.flora = Flora.new()
	root.add_child(g.flora)
	g.flora.keep()
	g.walls = WallTool.new(g.rig, g.world, g.flora, paths)
	g.walls.set_process(false)
	root.add_child(g.walls)
	var terrain := TerrainTool.new(g.rig, g.world)
	terrain.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(terrain)
	g.water = Water.new([])
	terrain.reshaped.connect(g.water.reground)
	root.add_child(g.water)
	g.digger = WaterTool.new(g.rig, terrain, g.water)
	root.add_child(g.digger)
	g.world.attach(g.walls, g.flora, paths, terrain, g.water)
	var hands: Array[Node3D] = []
	hands.assign(g.rig.hands)
	await process_frame
	g.wildlife = Wildlife.new(g.water, g.flora, g.walls, Palette.new(), g.rig.head, hands, seed)
	g.wildlife.set_process(false)
	root.add_child(g.wildlife)
	for h in g.rig.hands:
		h.global_position = AWAY
	return g


func _teardown(g: Glade) -> void:
	g.wildlife.free()
	for w in g.walls.walls:
		w.free()
	for n: Node in [g.digger, g.water, g.walls, g.flora, g.world, g.rig]:
		n.queue_free()
	await process_frame


func _draw(g: Glade, tool: Hand.Tool, a: Vector3, b: Vector3) -> Wall:
	var m: WallTool.Mason = g.walls.masons[0]
	m.hand.tool = tool
	g.walls.begin_stroke(m, Terrain.ground(a.x, a.z))
	for i in 41:
		var p := a.lerp(b, i / 40.0)
		g.walls.extend_stroke(m, Terrain.ground(p.x, p.z))
	g.walls.end_stroke(m)
	return g.walls.walls[-1]


func _dig(g: Glade, x: float, z: float, frames: int) -> void:
	g.digger.begin(g.digger.rig.right, Terrain.ground(x, z))
	for i in frames:
		g.digger.deepen(1.0 / 60.0)
	g.digger.end()
	await process_frame
	await process_frame


func _run(g: Glade, seconds: float, each := Callable()) -> void:
	for i in int(seconds / STEP):
		g.wildlife.tick(STEP)
		if each.is_valid():
			each.call()


## Every sheep that disappears was out of the viewer's sight in its last frame.
func _watch_vanishing(g: Glade, seen: Dictionary) -> Callable:
	return func() -> void:
		var now := {}
		for s in g.sheep():
			now[s] = g.wildlife._in_sight(s.position)
		for s in seen:
			if not now.has(s) and seen[s]:
				_check(false, "a sheep vanished in sight")
		seen.clear()
		seen.merge(now)


func _no_tool_places_a_sheep() -> void:
	for key: String in Hand.Tool.keys():
		_check(not key.begins_with("SHEEP") and not key.begins_with("HERD"), "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			var code := FileAccess.get_file_as_string("res://src/" + f)
			_check(not code.contains("Sheep") and not code.contains("Herds"), "%s reaches no sheep" % f)
	_check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Herds.new(") == 1, "Wildlife alone makes the herds")


func _the_sheep_is_one_small_mesh() -> void:
	var tris := Sheep.build().get_faces().size() / 3
	_check(tris >= 500 and tris <= 900, "a sheep is a few hundred triangles, %d" % tris)
	var a := Sheep.new(0.0, 1.0, Color.WHITE)
	var b := Sheep.new(1.0, 0.9, Color.WHITE)
	_check(a.mesh == b.mesh and a.material_override == b.material_override, "every sheep shares one mesh and one material")
	_check(a.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a sheep casts no shadow")
	a.free()
	b.free()


## The distance from the fence's centre line and the side of it, of a ground point.
func _off_fence(fence: Wall, p: Vector3) -> Vector2:
	var at := fence.layout.frame_at(fence.layout.closest_s(p))
	var off := Vector3(p.x - at.point.x, 0, p.z - at.point.z)
	return Vector2(off.length(), signf(off.dot((at.tangent as Vector3).cross(Vector3.UP))))


## A sheep standing, lying, or grazing on its spot rather than stepping on.
func _resting(s: Sheep) -> bool:
	return s.state in [Herds.State.STAND, Herds.State.LIE] or (s.state == Herds.State.GRAZE and s.position.distance_to(s.goal) < 0.005)


func _crosses_a_wall(g: Glade, a: Vector3, b: Vector3) -> bool:
	for w in g.walls.walls:
		var pts := Herds._line(w.layout)
		for i in pts.size() - 1:
			if Geometry2D.segment_intersects_segment(Vector2(a.x, a.z), Vector2(b.x, b.z), pts[i], pts[i + 1]) != null:
				return true
	return false


func _fences_draw_a_flock() -> void:
	var g := await _glade(4)
	_run(g, 300.0)
	_check(g.sheep().is_empty(), "a meadow without a fence draws no sheep")
	var wall := _draw(g, Hand.Tool.WALLS, Vector3(-6, 0, -8), Vector3(6, 0, -8))
	_run(g, 120.0)
	_check(g.sheep().is_empty(), "a stone wall draws no sheep")
	var short := _draw(g, Hand.Tool.FENCE, Vector3(-14, 0, -2), Vector3(-14, 0, 2))
	_check(short.layout.fence and short.layout.length() < Herds.MIN_FENCE, "a short fence, %.1f m" % short.layout.length())
	_run(g, 120.0)
	_check(g.sheep().is_empty(), "a short fence draws no sheep")

	var fence := _draw(g, Hand.Tool.FENCE, Vector3(-6, 0, -4), Vector3(6, 0, -4))
	_check(fence.layout.fence and fence.finished and Herds.standing_length(fence.layout) >= Herds.MIN_FENCE, "a fence of %.1f m" % fence.layout.length())
	_draw(g, Hand.Tool.WALLS, Vector3(-2, 0, -0.5), Vector3(-2, 0, 4))
	await _dig(g, 3.5, -0.5, 90)
	await _dig(g, 3.5, -7.5, 90)
	for p in g.water.ponds:
		p._process(PondWater.FILL)
	_check(g.water.ponds.size() == 2, "a pond on each side of the fence, %d" % g.water.ponds.size())
	_check(g.rig.head.global_position.direction_to(Vector3(0, 0.5, -4)).dot(-g.rig.head.global_basis.z) > Wildlife.SIGHT, "the viewer looks at the fence")

	var seen := {}
	var vanishing := _watch_vanishing(g, seen)
	var arrived := [false]
	var first_sight := func() -> void:
		vanishing.call()
		if not arrived[0]:
			for s in g.sheep():
				_check(not g.wildlife._in_sight(s.position), "a sheep first appears out of sight")
		arrived[0] = arrived[0] or not g.sheep().is_empty()
	_run(g, Wildlife.SHEEP_AFTER.x - 1.0, first_sight)
	_check(g.sheep().is_empty(), "no sheep before its time")
	_run(g, Wildlife.SHEEP_AFTER.y - Wildlife.SHEEP_AFTER.x + 2.0, first_sight)
	var herds := g.wildlife.herds
	_check(herds.flocks.size() == 1 and herds.flocks[0].fence == fence, "a flock comes to the fence some time after it stands")
	var n := g.sheep().size()
	_check(n >= Herds.FLOCK.x and n <= Herds.FLOCK.y, "two to four sheep, %d" % n)

	var states := {}
	var worst := {"band": Vector2(INF, 0.0), "sides": {}, "wet": 0, "crossed": 0, "near": 0, "kept": 0}
	var last := {}
	var watch := func() -> void:
		vanishing.call()
		var flock := g.sheep()
		for s in flock:
			states[s.state] = true
			if last.has(s) and _crosses_a_wall(g, last[s], s.position):
				worst.crossed += 1
			last[s] = s.position
			var pond := g.water.pond_at(s.position.x, s.position.z)
			if pond != null and pond.pond.level - Terrain.height_at(s.position.x, s.position.z) > 0.01:
				worst.wet += 1
			if _resting(s):
				var off := _off_fence(fence, s.position)
				worst.band = Vector2(minf(worst.band.x, off.x), maxf(worst.band.y, off.x))
				worst.sides[off.y] = true
				if not herds.allowed(s.position):
					worst.kept += 1
			for t in flock:
				if t != s and _resting(s) and _resting(t) and Vector2(s.position.x - t.position.x, s.position.z - t.position.z).length() < Sheep.RADIUS * Sheep.SIZE.x * 1.5:
					worst.near += 1
	_run(g, 400.0, watch)
	_check(states.has(Herds.State.GRAZE) and states.has(Herds.State.STAND) and states.has(Herds.State.WALK) and states.has(Herds.State.LIE), "they graze, look about, walk on and lie down, states %s" % [states.keys()])
	_check(worst.band.x >= Herds.BAND.x - 0.4 and worst.band.y <= Herds.BAND.y + 0.6, "they graze beside the fence, %.2f to %.2f m from it" % [worst.band.x, worst.band.y])
	_check(worst.sides.size() == 1, "on one side of it")
	_check(worst.wet == 0, "never in water, %d frames" % worst.wet)
	_check(worst.crossed == 0, "never through a wall, %d steps" % worst.crossed)
	_check(worst.kept == 0, "never on ground they keep off, %d frames" % worst.kept)
	_check(worst.near <= 30, "standing, they keep a little apart, crowded for %d frames" % worst.near)

	var calm := g.sheep().filter(func(s: Sheep) -> bool: return s.state != Herds.State.ENTER)
	_check(not calm.is_empty(), "a sheep to approach")
	if not calm.is_empty():
		var target: Sheep = calm[0]
		var hand: Hand = g.rig.right
		hand.global_position = target.position + Vector3(0.3, 0.6, 0.3)
		_run(g, 0.2)
		_check(target.state == Herds.State.FLEE, "a hand at its back sends a sheep off, state %d" % target.state)
		var from := hand.global_position
		_run(g, 5.0, watch)
		var off := Vector2(target.position.x - from.x, target.position.z - from.z).length()
		_check(off > 2.0 and target.state != Herds.State.FLEE, "it trots %.1f m away and settles" % off)
		hand.global_position = AWAY
		_run(g, 30.0, watch)
		_check(worst.crossed == 0 and worst.wet == 0, "fleeing, it keeps out of water and walls")

	g.world.undo()
	g.world.undo()
	g.world.undo()
	g.world.undo()
	await process_frame
	await process_frame
	_check(not is_instance_valid(fence), "the fence is erased")
	_run(g, 1.0, vanishing)
	_check(herds.flocks.size() == 1 and herds.flocks[0].leaving, "the flock sets off")
	_run(g, 400.0, vanishing)
	_check(g.sheep().is_empty(), "the sheep leave an erased fence")
	_run(g, 120.0)
	_check(g.sheep().is_empty(), "and none come back without it")
	await _teardown(g)


func _the_same_seed_brings_the_same_flock() -> void:
	var places := []
	for run in 2:
		var g := await _glade(9)
		_draw(g, Hand.Tool.FENCE, Vector3(-6, 0, -5), Vector3(6, 0, -5))
		_run(g, Wildlife.SHEEP_AFTER.y + 40.0)
		var at := []
		for s in g.sheep():
			at.append(s.position.snapped(Vector3.ONE * 0.001))
		places.append(at)
		await _teardown(g)
	_check(not places[0].is_empty() and places[0] == places[1], "the same seed brings the same flock to the same grass: %s vs %s" % places)
