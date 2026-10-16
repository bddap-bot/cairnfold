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
	_curved_walls_are_kept_off_where_they_curve()
	await _settled_sheep_follow_their_ground()
	await _leaving_sheep_keep_out_of_walls_and_water()
	await _a_sheep_off_its_grass_goes_back()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


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
	var terrain: GroundGrab
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
	g.terrain = GroundGrab.new(g.rig, g.world)
	g.terrain.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(g.terrain)
	g.water = Water.new([])
	g.terrain.reshaped.connect(g.water.reground)
	g.terrain.reshaped.connect(g.walls.reground)
	root.add_child(g.water)
	g.digger = WaterTool.new(g.rig, g.terrain, g.water)
	root.add_child(g.digger)
	g.world.attach(g.walls, g.flora, paths, g.terrain, g.water)
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
	for n: Node in [g.digger, g.terrain, g.water, g.walls, g.flora, g.world, g.rig]:
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


## As `_run`, a frame at a time, so walls lay their stones again as they would in play.
func _play(g: Glade, seconds: float, each := Callable()) -> void:
	for i in int(seconds / STEP):
		await process_frame
		g.wildlife.tick(STEP)
		if each.is_valid():
			each.call()


## Counts, over the frames it is called on, steps through a wall, frames in water, frames resting on ground
## kept off, and frames off the ground.
class Watch:
	var crossed := 0
	var wet := 0
	var kept := 0
	var floating := 0
	var last := {}

	func see(t: SceneTree, g: Glade) -> void:
		for s in g.sheep():
			if last.has(s) and t._crosses_a_wall(g, last[s], s.position):
				crossed += 1
			last[s] = s.position
			var pond := g.water.pond_at(s.position.x, s.position.z)
			if pond != null and pond.pond.level - Terrain.height_at(s.position.x, s.position.z) > 0.01:
				wet += 1
			if t._resting(s) and not g.wildlife.herds.allowed(s.position):
				kept += 1
			if absf(s.position.y - Terrain.height_at(s.position.x, s.position.z)) > 0.01:
				floating += 1


## A sheep of the flock resting on its spot, preferring the one furthest from the others; null if none rests.
func _a_resting(g: Glade, but: Array = []) -> Sheep:
	var best: Sheep = null
	var room := -1.0
	for s in g.sheep():
		if not _resting(s) or s in but:
			continue
		var near := INF
		for o in g.sheep():
			if o != s:
				near = minf(near, Vector2(o.position.x - s.position.x, o.position.z - s.position.z).length())
		if near > room:
			room = near
			best = s
	return best


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
	return s.state in [Herds.State.STAND, Herds.State.LIE] or (s.state == Herds.State.GRAZE and Vector2(s.goal.x - s.position.x, s.goal.z - s.position.z).length() < 0.005)


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
	_check(herds.flocks.size() == 1 and herds.flocks[0].sheep.all(func(s: Sheep) -> bool: return s.state == Herds.State.LEAVE), "the flock sets off")
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
	var g := await _glade(9)
	var seeds := [g.wildlife.rng.seed, g.wildlife.butterflies.rng.seed, g.wildlife.fireflies.rng.seed, g.wildlife.birds.rng.seed, g.wildlife.herds.rng.seed]
	_check(seeds.all(func(n: int) -> bool: return seeds.count(n) == 1), "each kind of animal draws its own numbers, seeds %s" % [seeds])
	await _teardown(g)


## A curved wall is kept clear of along its curve, not along the chords between the points it was drawn through.
func _curved_walls_are_kept_off_where_they_curve() -> void:
	var w := WallLayout.new()
	w.points.assign([Vector3(0, 0, 0), Vector3(3, 0, 3), Vector3(6, 0, 0), Vector3(9, 0, 3)])
	w.build(func(_x: float, _z: float) -> float: return 0.0)
	var chords := PackedVector2Array()
	for p in w.points:
		chords.append(Vector2(p.x, p.z))
	var worst := 0.0
	var at := Vector2.ZERO
	for p in w.samples:
		var q := Vector2(p.x, p.z)
		if _off_line(chords, q) > worst:
			worst = _off_line(chords, q)
			at = q
	_check(worst > 0.25, "the curve strays %.2f m from its chords" % worst)
	_check(_off_line(Herds._line(w), at) < 0.01, "the line sheep keep off runs along the curve, %.2f m off it" % _off_line(Herds._line(w), at))


func _off_line(line: PackedVector2Array, q: Vector2) -> float:
	var out := INF
	for i in line.size() - 1:
		out = minf(out, Geometry2D.get_closest_point_to_segment(q, line[i], line[i + 1]).distance_to(q))
	return out


## Ground dug out, built on or pulled up under a settled flock: the sheep move off water and walls within a few
## seconds, never through the new wall, stand on the ground as it now is, and go on grazing.
func _settled_sheep_follow_their_ground() -> void:
	var g := await _glade(4)
	_draw(g, Hand.Tool.FENCE, Vector3(-6, 0, -4), Vector3(6, 0, -4))
	_run(g, Wildlife.SHEEP_AFTER.y + 90.0)
	var herds := g.wildlife.herds
	_check(herds.flocks.size() == 1 and g.sheep().size() >= Herds.FLOCK.x, "a flock grazes by the fence")
	var watch := Watch.new()
	var see := func() -> void: watch.see(self, g)
	var some := _a_resting(g)
	_check(some != null, "a sheep rests")
	if some == null:
		await _teardown(g)
		return

	await _dig(g, some.position.x, some.position.z, 90)
	for p in g.water.ponds:
		p._process(PondWater.FILL)
	var pond := g.water.pond_at(some.position.x, some.position.z)
	_check(pond != null and pond.pond.level - Terrain.height_at(some.position.x, some.position.z) > 0.05, "a pond is dug under a resting sheep")
	_run(g, 10.0, func() -> void:
		watch.see(self, g)
		watch.wet = 0
		watch.kept = 0)
	_run(g, 20.0, see)
	_check(watch.wet == 0 and watch.kept == 0, "it walks out of the new pond and stays out, %d frames in water" % watch.wet)

	var other := _a_resting(g)
	_check(other != null, "another sheep rests")
	if other != null:
		var fence_z := -4.0
		var out := signf(other.position.z - fence_z)
		var x := other.position.x + 0.25
		_draw(g, Hand.Tool.WALLS, Vector3(x, 0, fence_z + out * 1.0), Vector3(x, 0, fence_z + out * 8.0))
		await process_frame
		_check(not herds.allowed(other.position), "a wall is drawn under a resting sheep")
		watch.kept = 0
		_run(g, 10.0, func() -> void:
			watch.see(self, g)
			watch.kept = 0)
		_run(g, 20.0, see)
		_check(watch.kept == 0, "it moves off the wall's ground and keeps off, %d frames on it" % watch.kept)
	_check(watch.crossed == 0, "never through a wall, %d steps" % watch.crossed)

	var middle := Vector3.ZERO
	for s in g.sheep():
		middle += s.position / g.sheep().size()
	var before := {}
	for s in g.sheep():
		before[s] = s.state
	g.terrain.begin(Terrain.ground(middle.x, middle.z), 6.0)
	for i in 30:
		g.terrain.pull(i * 0.04)
		await process_frame
		g.wildlife.tick(STEP)
		watch.see(self, g)
	g.terrain.end_stroke()
	var changed := {}
	await _play(g, 60.0, func() -> void:
		watch.see(self, g)
		for s in g.sheep():
			if before.has(s) and s.state != before[s]:
				changed[s] = true)
	_check(watch.floating == 0, "they stand on the ground as it moves, %d frames off it" % watch.floating)
	_check(changed.size() == before.size(), "and go on from what they were doing, %d of %d" % [changed.size(), before.size()])
	_check(watch.crossed == 0 and watch.wet == 0, "still never in water or through a wall")
	await _teardown(g)


## A flock whose fence is erased inside a ring of walls, with a pond by it, watched from outside the ring, never
## walks through a wall or into the water: hemmed in, it stands until nobody looks, and is let go then.
func _leaving_sheep_keep_out_of_walls_and_water() -> void:
	var g := await _glade(4)
	var fence := _draw(g, Hand.Tool.FENCE, Vector3(-6, 0, -4), Vector3(6, 0, -4))
	_run(g, Wildlife.SHEEP_AFTER.y + 60.0)
	_check(g.sheep().size() >= Herds.FLOCK.x, "a flock grazes by the fence")
	for side in [[Vector3(-14, 0, 6), Vector3(-14, 0, -14)], [Vector3(-13, 0, -15), Vector3(13, 0, -15)], [Vector3(14, 0, -14), Vector3(14, 0, 6)], [Vector3(13, 0, 7), Vector3(-13, 0, 7)]]:
		_draw(g, Hand.Tool.WALLS, side[0], side[1])
	await _dig(g, 0.0, -12.0, 90)
	for p in g.water.ponds:
		p._process(PondWater.FILL)
	_run(g, 10.0)
	var watch := Watch.new()
	var see := func() -> void: watch.see(self, g)
	var outside := Node3D.new()
	root.add_child(outside)
	outside.global_transform = Transform3D(Basis(), Vector3(0, 6, 30)).looking_at(Vector3(0, 0, -4))
	g.wildlife.viewer = outside
	_run(g, 1.0, see)
	g.world.submit({"op": "unwall", "ids": PackedInt32Array([fence.id])})
	await process_frame
	await process_frame
	_check(not is_instance_valid(fence), "the fence is erased")
	_run(g, 1.0, see)
	var herds := g.wildlife.herds
	_check(herds.flocks.size() == 1 and herds.flocks[0].sheep.all(func(s: Sheep) -> bool: return s.state == Herds.State.LEAVE), "the flock sets off")
	_run(g, 90.0, see)
	_check(watch.crossed == 0, "leaving, no sheep walks through a wall, %d steps" % watch.crossed)
	_check(watch.wet == 0, "or into the water, %d frames" % watch.wet)
	outside.global_transform = Transform3D(Basis(), Vector3(0, 6, 30)).looking_at(Vector3(0, 6, 60))
	_run(g, 30.0, see)
	_check(g.sheep().is_empty(), "once nobody looks they are let go, %d left" % g.sheep().size())
	g.wildlife.viewer = g.rig.head
	outside.free()
	await _teardown(g)


## A sheep that finds itself out beyond its flock's grass walks back to it.
func _a_sheep_off_its_grass_goes_back() -> void:
	var g := await _glade(4)
	var fence := _draw(g, Hand.Tool.FENCE, Vector3(-6, 0, -4), Vector3(6, 0, -4))
	_run(g, Wildlife.SHEEP_AFTER.y + 30.0)
	var flock: Herds.Flock = g.wildlife.herds.flocks[0] if not g.wildlife.herds.flocks.is_empty() else null
	_check(flock != null, "a flock grazes by the fence")
	if flock == null:
		await _teardown(g)
		return
	var s: Sheep = flock.sheep[0]
	var stray := Vector3.ZERO
	for i in 20:
		stray = Terrain.ground(-4.0 + i * 0.4, -4.0 + flock.side * 13.0)
		if g.wildlife.herds.allowed(stray):
			break
	s.position = stray
	s.goal = stray
	s.state = Herds.State.STAND
	s.timer = 0.0
	_check(_off_fence(fence, s.position).x > Herds.BAND.y + 4.0, "a sheep stands %.1f m out from its fence" % _off_fence(fence, s.position).x)
	_run(g, 60.0)
	var off := _off_fence(fence, s.position)
	_check(s.state != Herds.State.LEAVE and off.x <= Herds.BAND.y + 0.6 and off.y == flock.side, "with nothing in its way it walks back to its grass, %.1f m out" % off.x)
	await _teardown(g)




