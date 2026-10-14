extends SceneTree

## Headless checks of butterflies: godot4 --headless --path game --script ../tests/test_butterflies.gd

const STEP := 1.0 / 30.0
const AWAY := Vector3(0, -50, 0)

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	_no_tool_places_butterflies()
	await _only_painted_flowers_draw_them()
	await _they_settle_on_blooms_and_scatter_from_a_hand()
	await _they_leave_when_the_flowers_go()
	await _a_path_over_flowers_takes_them_away()
	_seasons_take_flowers_by_rank()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


class Glade:
	var rig: Rig
	var flora: Flora
	var tool: FloraTool
	var palette := Palette.new()
	var wildlife: Wildlife

	func all() -> Array[Butterflies.Butterfly]:
		return wildlife.butterflies.butterflies

	func in_state(s: Butterflies.State) -> Array[Butterflies.Butterfly]:
		return all().filter(func(b: Butterflies.Butterfly) -> bool: return b.state == s)

	func painted() -> PackedVector3Array:
		var out := PackedVector3Array()
		for i in range(flora.flowers.kept, flora.flowers.size()):
			if flora.flowers.anchors[i] != Flora.Pool.GONE:
				out.append(flora.flowers.anchors[i])
		return out


func _glade(seed: int) -> Glade:
	var g := Glade.new()
	g.rig = Rig.new()
	root.add_child(g.rig)
	var world := World.new()
	root.add_child(world)
	g.flora = Flora.new()
	root.add_child(g.flora)
	var paths := Paths.new()
	root.add_child(paths)
	g.tool = FloraTool.new(g.rig, g.flora, paths, world)
	g.tool.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(g.tool)
	var water := Water.new([])
	root.add_child(water)
	world.attach(null, g.flora, paths, null, water)
	var hands: Array[Node3D] = []
	hands.assign(g.rig.hands)
	await process_frame
	g.wildlife = Wildlife.new(water, g.flora, g.palette, g.rig.head, hands, seed)
	g.wildlife.set_process(false)
	root.add_child(g.wildlife)
	for h in g.rig.hands:
		h.global_position = AWAY
	return g


func _paint(g: Glade, at: Vector3, seconds: float) -> void:
	var b := g.tool.brushes[0]
	b.hand.tool = Hand.Tool.FLOWERS
	for i in int(seconds / STEP):
		g.tool.paint(b, Terrain.ground(at.x, at.z), 1.0, STEP)
	g.tool.end_stroke(b)


func _run(g: Glade, seconds: float, each := Callable()) -> void:
	for i in int(seconds / STEP):
		g.wildlife.tick(STEP)
		if each.is_valid():
			each.call()


func _arrived(g: Glade) -> void:
	_run(g, Wildlife.BUTTERFLIES_AFTER.y + 3.0)
	_check(not g.all().is_empty(), "butterflies came")


func _no_tool_places_butterflies() -> void:
	for key: String in Hand.Tool.keys():
		_check(not key.begins_with("BUTTERFL"), "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			_check(not FileAccess.get_file_as_string("res://src/" + f).contains("utterfl"), "%s reaches no butterfly" % f)
	_check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Butterflies.new(") == 1, "Wildlife alone makes butterflies")


func _only_painted_flowers_draw_them() -> void:
	var g := await _glade(2)
	var rng := RandomNumberGenerator.new()
	for i in 600:
		g.flora.add_flower(Terrain.ground(rng.randf_range(-3, 3), rng.randf_range(-7, -1)), rng)
	g.flora.keep()
	_run(g, 120.0)
	_check(g.all().is_empty(), "the meadow's own flowers draw no butterflies")
	_paint(g, Vector3(0.5, 0, -4.5), 0.15)
	_run(g, 60.0)
	_check(g.all().is_empty(), "a few painted flowers are not yet a patch")
	_paint(g, Vector3(0.5, 0, -4.5), 3.0)
	_check(g.all().is_empty(), "painting flowers puts no butterfly down")
	_run(g, Wildlife.BUTTERFLIES_AFTER.x - 1.0)
	_check(g.all().is_empty(), "none before their time")
	var first := {}
	var watch := func() -> void:
		for b in g.all():
			if not first.has(b):
				first[b] = g.wildlife._in_sight(b.at)
	_run(g, Wildlife.BUTTERFLIES_AFTER.y - Wildlife.BUTTERFLIES_AFTER.x + 3.0, watch)
	var n := g.all().size()
	_check(n >= Butterflies.PER_PATCH.x, "butterflies come to a painted patch some time after it appears, %d" % n)
	_check(not first.values().has(true), "each first appears out of sight")
	var painted := g.painted()
	for b in g.all():
		var near := false
		for p in painted:
			near = near or Vector2(p.x - b.goal.x, p.z - b.goal.z).length() < 1e-3
		_check(near, "each makes for a painted bloom")


func _they_settle_on_blooms_and_scatter_from_a_hand() -> void:
	var g := await _glade(3)
	_paint(g, Vector3(-1, 0, -3), 4.0)
	_arrived(g)
	var n := g.all().size()
	var perched := [0]
	_run(g, 40.0, func() -> void: perched[0] = maxi(perched[0], g.in_state(Butterflies.State.PERCH).size()))
	_check(n > 0 and perched[0] == n, "every one settles on a bloom, %d of %d" % [perched[0], n])
	var sitting := g.in_state(Butterflies.State.PERCH)
	if sitting.is_empty():
		_check(false, "one is sitting to be scattered")
		return
	var b: Butterflies.Butterfly = sitting[0]
	var at := b.at
	g.rig.right.global_position = at + Vector3(0.2, 0.05, 0)
	_run(g, 1.0)
	_check(b.state == Butterflies.State.FLEE and b.at.distance_to(at) > 0.8 and b.at.y > at.y, "a hand near sends it up and away, %.2f m" % b.at.distance_to(at))
	g.rig.right.global_position = AWAY
	var back := [false]
	_run(g, 40.0, func() -> void: back[0] = back[0] or (b.state == Butterflies.State.PERCH and g.wildlife.butterflies.patches.has(b.patch)))
	_check(back[0], "a scattered one comes back and settles in its patch")


func _they_leave_when_the_flowers_go() -> void:
	var g := await _glade(4)
	_paint(g, Vector3(3, 0, -4), 4.0)
	_arrived(g)
	g.palette.picks[Palette.Element.MEADOW] = Palette.SEASONS.size() - 1
	_run(g, 2.0)
	_check(g.wildlife.butterflies.patches.is_empty(), "flowers out of season are no patch")
	_check(g.in_state(Butterflies.State.LEAVE).size() == g.all().size(), "so they leave")
	g.palette.picks[Palette.Element.MEADOW] = Palette.SUMMER
	_run(g, 60.0)
	_check(not g.in_state(Butterflies.State.PERCH).is_empty(), "in bloom again, they come back")
	for p in g.flora.painted_near(Terrain.ground(3, -4), 4.0):
		p.set_shown(false)
	_run(g, 2.0)
	_check(g.wildlife.butterflies.patches.is_empty(), "a cleared patch is no longer a patch")
	_check(not g.all().is_empty() and g.in_state(Butterflies.State.LEAVE).size() == g.all().size(), "they leave when its flowers are gone")
	var popped := [false]
	var last := {}
	_run(g, 60.0, func() -> void:
		for b in last:
			if not g.all().has(b) and g.wildlife._in_sight(last[b]):
				popped[0] = true
		last.clear()
		for b in g.all():
			last[b] = b.at)
	_check(g.all().is_empty(), "and are gone")
	_check(not popped[0], "none vanishes in sight")


func _a_path_over_flowers_takes_them_away() -> void:
	var g := await _glade(5)
	_paint(g, Vector3(-3, 0, -5), 4.0)
	_arrived(g)
	var b := g.tool.brushes[0]
	b.hand.tool = Hand.Tool.PATH
	g.tool.begin_path(b, Terrain.ground(-6, -5), 2.5)
	for x in range(-6, 1):
		g.tool.extend_path(Terrain.ground(x, -5), 2.5)
	g.tool.end_path(b)
	await process_frame
	_run(g, 2.0)
	_check(g.wildlife.butterflies.patches.is_empty(), "flowers a path parts are no patch, %d left" % g.wildlife.butterflies.patches.size())


func _seasons_take_flowers_by_rank() -> void:
	_check(FileAccess.get_file_as_string("res://src/plant.gdshaderinc").contains("INSTANCE_CUSTOM.r >= season_bloom"), "the flower shader folds flowers by their rank")
	var share := 0
	for i in 2000:
		share += int(FloraLayout.bloom_rank(Vector3(i * 0.37 - 50.0, 0, i * 0.61 - 80.0)) < 0.55)
	_check(absi(share - 1100) < 100, "ranks spread evenly, %d of 2000 under 0.55" % share)
