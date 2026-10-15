extends SceneTree

## Headless checks of conures: godot4 --headless --path game --script ../tests/test_birds.gd

const STEP := 1.0 / 30.0
const AWAY := Vector3(0, -50, 0)

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	_no_tool_places_a_bird()
	_wall_tops_are_perches()
	await _they_come_after_the_ducks_and_leave_with_the_perches()
	await _a_perch_taken_away_sends_them_elsewhere()
	await _with_no_room_they_leave()
	await _a_reshape_carries_them_with_their_perch()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _no_tool_places_a_bird() -> void:
	for key: String in Hand.Tool.keys():
		_check(not key in ["BIRD", "BIRDS", "CONURE", "CONURES"], "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			var code := FileAccess.get_file_as_string("res://src/" + f)
			_check(not code.contains("Birds") and not code.contains("onure"), "%s reaches no bird" % f)
	_check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Birds.new(") == 1, "Wildlife alone makes the birds")
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with(".gd") and f != "birds.gd" and f != "conure.gd":
			_check(not FileAccess.get_file_as_string("res://src/" + f).contains("Conure.new("), "%s makes no conure" % f)


## A wall's perches stand on its top: on the cap, on merlons, on piers, on a fence's top rail and posts; none
## beside a flag, none on a roofed wall.
func _wall_tops_are_perches() -> void:
	for top in WallLayout.Top.values():
		var w := WallLayout.new()
		w.points.assign([Vector3(0, 0, 0), Vector3(6, 0, 0)])
		w.top = top
		w.flags.assign([3.0])
		w.build(func(_x: float, _z: float) -> float: return 0.0)
		var perches := w.perches()
		var low := INF
		var high := -INF
		var by_flag := 0
		for p in perches:
			var up: float = p.y - w.frame_at(p.x).point.y
			low = minf(low, up)
			high = maxf(high, up)
			by_flag += int(absf(p.x - 3.0) < 0.25)
		_check(perches.size() > 20, "a 6 m wall has perches along its top, %d" % perches.size())
		_check(low >= w.height + 0.05 and high <= w.height + 1.2, "they stand on its top: %.2f to %.2f up a wall %.2f tall" % [low, high, w.height])
		_check(by_flag == 0, "none beside the flag")
	var f := WallLayout.new()
	f.points.assign([Vector3(0, 0, 0), Vector3(6, 0, 0)])
	f.fence = true
	f.build(func(_x: float, _z: float) -> float: return 0.0)
	var rails := f.perches()
	_check(rails.size() > 20 and Array(rails).all(func(p: Vector3) -> bool: return p.y - f.frame_at(p.x).point.y > 0.85 and p.y - f.frame_at(p.x).point.y < WallLayout.FENCE_HEIGHT + 0.2), "a fence's perches are on its top rail and posts")
	var roofed := WallLayout.new()
	roofed.points.assign([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 3), Vector3(0, 0, 3)])
	roofed.closed = true
	roofed.cover = WallLayout.Cover.ROOF
	roofed.build(func(_x: float, _z: float) -> float: return 0.0)
	_check(roofed.perches().is_empty(), "a roofed house has no perches")


class Glade:
	var rig: Rig
	var world: World
	var flora: Flora
	var tool: WallTool
	var terrain: TerrainTool
	var wildlife: Wildlife

	func birds() -> Array[Birds.Bird]:
		return wildlife.birds.birds


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
	g.tool = WallTool.new(g.rig, g.world, g.flora, paths)
	g.tool.set_process(false)
	root.add_child(g.tool)
	g.terrain = TerrainTool.new(g.rig, g.world)
	g.terrain.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(g.terrain)
	var water := Water.new([])
	g.terrain.reshaped.connect(water.reground)
	g.terrain.reshaped.connect(g.tool.reground)
	root.add_child(water)
	g.world.attach(g.tool, g.flora, paths, g.terrain, water)
	var hands: Array[Node3D] = []
	hands.assign(g.rig.hands)
	await process_frame
	g.wildlife = Wildlife.new(water, g.flora, g.tool, Palette.new(), g.rig.head, hands, seed)
	g.wildlife.set_process(false)
	root.add_child(g.wildlife)
	for h in g.rig.hands:
		h.global_position = AWAY
	return g


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


func _teardown(g: Glade) -> void:
	g.wildlife.free()
	for w in g.tool.walls:
		w.free()
	for n: Node in [g.terrain, g.tool, g.flora, g.world, g.rig]:
		n.queue_free()
	await process_frame


## Runs until a flock has come and every bird of it perches, or `seconds` have passed.
func _until_perched(g: Glade, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	for w in g.tool.walls:
		while (w.laying() or w.perches().is_empty()) and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(not w.laying() and not w.perches().is_empty(), "wall perches are ready before advancing bird time")
	for i in int(seconds / STEP):
		g.wildlife.tick(STEP)
		if g.birds().size() >= Birds.FLOCK.x and g.birds().all(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH):
			return


func _draw_wall(tool: WallTool, a: Vector3, b: Vector3) -> Wall:
	var m: WallTool.Mason = tool.masons[0]
	tool.begin_stroke(m, Terrain.ground(a.x, a.z))
	for i in 31:
		var p := a.lerp(b, i / 30.0)
		tool.extend_stroke(m, Terrain.ground(p.x, p.z))
	tool.end_stroke(m)
	return tool.walls[-1]


## Every bird that disappears was out of the viewer's sight in its last frame.
func _watch_vanishing(g: Glade, seen: Dictionary) -> Callable:
	return func() -> void:
		var now := {}
		for b in g.birds():
			now[b] = g.wildlife._in_sight(b.node.position)

		for b in seen:
			if not now.has(b) and seen[b]:
				_check(false, "a bird vanished in sight")
		seen.clear()
		seen.merge(now)


## Whether `at` is on top of a standing wall, or on the surface of a planted tree's crown and inside none of its blobs.
func _on_perch(g: Glade, at: Vector3) -> bool:
	for w in g.tool.walls:
		var s := w.layout.closest_s(at)
		var foot: Vector3 = w.layout.frame_at(s).point
		if Vector2(at.x - foot.x, at.z - foot.z).length() < WallLayout.THICKNESS and at.y > foot.y + w.layout.height and at.y < foot.y + w.layout.height + 1.0:
			return true
	for parts: Array in g.flora.planted_trees():
		var trunk: Flora.Plant = parts[0]
		var ground := Terrain.height_at(trunk.anchor.x, trunk.anchor.z)
		if Vector2(at.x - trunk.anchor.x, at.z - trunk.anchor.z).length() > 4.0 or at.y < ground + 2.0:
			continue
		var nearest := INF
		for blob: Flora.Plant in parts.slice(1):
			var x := blob.xform
			x.origin.y += ground
			nearest = minf(nearest, (x.affine_inverse() * at).length())
		if nearest >= 0.6 and nearest < 1.4:
			return true
	return false


func _they_come_after_the_ducks_and_leave_with_the_perches() -> void:
	var g := await _glade(3)
	_run(g, 300.0)
	_check(g.birds().is_empty(), "a garden without perches draws no conures")

	g.world.submit({"op": "plant", "kind": "tree", "seed": 7, "at": Terrain.ground(-2.5, -9)})
	var wall := _draw_wall(g.tool, Vector3(0, 0, -7), Vector3(5, 0, -8))
	await process_frame
	_check(g.flora.planted_trees().size() == 1 and g.tool.walls.size() == 1 and wall.finished, "a planted tree and a finished wall")
	_check(g.rig.head.global_position.direction_to(Terrain.ground(1, -8)).dot(-g.rig.head.global_basis.z) > Wildlife.SIGHT, "the viewer looks at them")
	_run(g, 200.0)
	_check(g.birds().is_empty(), "no conure comes before the ducks")

	var duck := Duck.new(false, 0.0)
	g.wildlife.families.append(Wildlife.Family.new(duck))
	g.wildlife.tick(STEP)
	g.wildlife.families.clear()
	duck.free()
	_check(g.wildlife.ducks_came, "a duck coming counts")

	var seen := {}
	var vanishing := _watch_vanishing(g, seen)
	var appeared := [false]
	var first := func() -> void:
		vanishing.call()
		if not appeared[0] and not g.birds().is_empty():
			appeared[0] = true
			for b in g.birds():
				_check(not g.wildlife._in_sight(b.node.position), "a conure first appears out of sight")
	_run(g, Wildlife.ARRIVE_AFTER.x - 1.0, first)
	_check(g.birds().is_empty(), "no conure before its time")
	_run(g, Wildlife.ARRIVE_AFTER.y - Wildlife.ARRIVE_AFTER.x + 2.0, first)
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().size() <= Birds.FLOCK.y, "a pair or a trio flies in, %d" % g.birds().size())

	var states := {}
	var off_perch := [0.0]
	var watch := func() -> void:
		vanishing.call()
		for b in g.birds():
			states[b.state] = true
			if b.state == Birds.State.PERCH and not _on_perch(g, b.node.position):
				off_perch[0] = maxf(off_perch[0], 1.0)
			if b.preening > 0.0:
				states["preen"] = true
	_run(g, 240.0, watch)
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().size() <= Birds.CAP, "they stay while there are perches")
	_check(off_perch[0] == 0.0, "every perched conure stands on a wall top or a crown")
	for s in [Birds.State.PERCH, Birds.State.HOP, Birds.State.FLY, Birds.State.PECK, "preen"]:
		_check(states.has(s), "they %s" % (s if s is String else Birds.State.keys()[s].to_lower()))

	var perched: Birds.Bird = null
	for i in 600:
		for b in g.birds():
			if b.state == Birds.State.PERCH:
				perched = b
		if perched != null:
			break
		_run(g, STEP)
	_check(perched != null, "a conure sits on its perch")
	var hand: Node3D = g.rig.hands[0]
	hand.global_position = perched.node.position + Vector3(0.3, 0.1, 0)
	_run(g, STEP * 2, vanishing)
	_check(perched.state == Birds.State.FLY, "a hand near it flushes it up")
	var from := hand.global_position
	_run(g, 6.0, vanishing)
	_check(perched.node.position.distance_to(from) > Birds.FLUSH, "to a perch out of reach, %.2f m off" % perched.node.position.distance_to(from))
	hand.global_position = AWAY

	g.world.undo()
	g.world.undo()
	await process_frame
	_check(g.flora.planted_trees().is_empty() and g.tool.walls.is_empty(), "the tree and the wall are gone")
	_run(g, 120.0, vanishing)
	_check(g.birds().is_empty(), "the conures leave once no perch stands")
	_run(g, 200.0)
	_check(g.birds().is_empty(), "and none come back without one")
	await _teardown(g)


## A wall taken away under perched conures, with another perch standing: from the next frame none counts on
## the wall, none perches in the air, and they settle on what stands.
func _a_perch_taken_away_sends_them_elsewhere() -> void:
	var g := await _glade(5)
	g.wildlife.ducks_came = true
	var first := _draw_wall(g.tool, Vector3(0, 0, -7), Vector3(5, 0, -8))
	# Keep perch work pending until the test yields, independent of machine speed.
	var ready := Semaphore.new()
	var out := {"laid": first.layout.laid}
	first._perch_out = out
	first._perch_task = WorkerThreadPool.add_task(func():
		ready.wait()
		out.points = first.layout.perches())
	ready.post.call_deferred()
	await _until_perched(g, Wildlife.ARRIVE_AFTER.y + 30.0)
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().all(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH), "conures perch on the only wall")
	var second := _draw_wall(g.tool, Vector3(-9, 0, -6), Vector3(-4, 0, -8))
	await process_frame
	await _play(g, 1.5)
	_check(g.wildlife.birds.sites.size() == 2, "a second wall to perch on, %d sites" % g.wildlife.birds.sites.size())
	g.world.submit({"op": "unwall", "ids": PackedInt32Array([first.id])})
	await process_frame
	await process_frame
	_check(not is_instance_valid(first), "the first wall is gone")
	g.wildlife.tick(STEP)
	_check(g.birds().all(func(b: Birds.Bird) -> bool: return b.site == null or b.site.standing()), "from the next frame no conure counts on the wall taken away")
	var off := [0]
	await _play(g, 12.0, func() -> void:
		for b in g.birds():
			if b.state == Birds.State.PERCH and not _on_perch(g, b.node.position):
				off[0] += 1)
	_check(off[0] == 0, "no conure perches where the wall stood, %d frames" % off[0])
	_check(g.birds().size() >= Birds.FLOCK.x and g.birds().all(func(b: Birds.Bird) -> bool: return b.state != Birds.State.LEAVE), "they stay, with a wall still standing")
	_check(g.birds().any(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH and _on_perch(g, b.node.position)), "and settle on it")
	await _teardown(g)


## A site with the one point to stand on.
class OnePoint extends Birds.Site:
	var at := Vector3.ZERO

	func standing() -> bool:
		return true

	func points() -> PackedVector3Array:
		return PackedVector3Array([at])


## Arrivals never share a point, and a bird whose perch is gone, with no room left elsewhere, flies off rather
## than staying in the air.
func _with_no_room_they_leave() -> void:
	var g := await _glade(6)
	var birds := g.wildlife.birds
	var one := OnePoint.new()
	one.at = Terrain.ground(0, -6) + Vector3.UP * 2.0
	birds.sites.assign([one])
	birds.arrive()
	_check(g.birds().size() == 1, "a flock coming to one free point brings one bird, %d" % g.birds().size())
	for i in int(10.0 / STEP):
		birds.tick(STEP)
	var b: Birds.Bird = g.birds()[0] if not g.birds().is_empty() else null
	_check(b != null and b.state == Birds.State.PERCH, "it perches")
	if b != null:
		var lost := Birds.Bird.new()
		lost.node = Conure.new(0.0)
		birds.add_child(lost.node)
		lost.node.position = one.at + Vector3(1, 0, 0)
		lost.state = Birds.State.PERCH
		lost.site = Birds.WallSite.new(null)
		lost.spot = lost.node.position
		birds.birds.append(lost)
		birds.sites.assign([one])
		birds._flutter(lost)
		_check(lost.state == Birds.State.LEAVE, "a bird whose perch is gone and finds no room leaves, state %d" % lost.state)
	await _teardown(g)


## Ground pulled up under a perched flock: once the wall is laid on it again they stand on its top as it now
## is, and on the crown over the ground now under the tree.
func _a_reshape_carries_them_with_their_perch() -> void:
	var g := await _glade(3)
	g.wildlife.ducks_came = true
	g.world.submit({"op": "plant", "kind": "tree", "seed": 7, "at": Terrain.ground(-2.5, -9)})
	_draw_wall(g.tool, Vector3(0, 0, -7), Vector3(5, 0, -8))
	await process_frame
	await _until_perched(g, Wildlife.ARRIVE_AFTER.y + 30.0)
	_check(g.birds().any(func(b: Birds.Bird) -> bool: return b.state == Birds.State.PERCH), "conures perch")
	g.terrain.begin(Terrain.ground(1, -8), 8.0)
	g.terrain.pull(1.5)
	g.terrain.end_stroke()
	_run(g, 1.0)
	var settled := false
	for i in 300:
		await process_frame
		if g.tool.walls.all(func(w: Wall) -> bool: return not w.laying()):
			settled = true
			break
	_check(settled, "the wall is laid on the new ground")
	await _play(g, 4.0)
	var off := [0, 0]
	await _play(g, 6.0, func() -> void:
		for b in g.birds():
			if b.state == Birds.State.PERCH:
				off[1] += 1
				if not _on_perch(g, b.node.position):
					off[0] += 1)
	_check(off[1] > 0 and off[0] == 0, "perched conures stand on the wall top or crown as they are after the reshape, %d of %d frames off" % off)
	await _teardown(g)
