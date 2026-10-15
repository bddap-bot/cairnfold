extends SceneTree

## Headless checks of fireflies: godot4 --headless --path game --script ../tests/test_fireflies.gd

const STEP := 1.0 / 30.0

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	_no_tool_places_fireflies()
	await _they_come_out_at_dusk_over_what_is_made()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run(wildlife: Wildlife, seconds: float) -> void:
	for i in int(seconds / STEP):
		wildlife.tick(STEP)


func _no_tool_places_fireflies() -> void:
	for key: String in Hand.Tool.keys():
		_check(not key.begins_with("FIREFL"), "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			_check(not FileAccess.get_file_as_string("res://src/" + f).contains("irefl"), "%s reaches no firefly" % f)
	_check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Fireflies.new(") == 1, "Wildlife alone makes fireflies")


func _dig(tool: WaterTool, x: float, z: float) -> void:
	tool.begin(tool.rig.right, Terrain.ground(x, z))
	for i in 90:
		tool.deepen(1.0 / 60.0)
	tool.end()
	await process_frame
	await process_frame


func _they_come_out_at_dusk_over_what_is_made() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var terrain := TerrainTool.new(rig, world)
	root.add_child(terrain)
	var water := Water.new([])
	terrain.reshaped.connect(water.reground)
	root.add_child(water)
	var tool := WaterTool.new(rig, terrain, water)
	root.add_child(tool)
	var flora := Flora.new()
	root.add_child(flora)
	var paths := Paths.new()
	root.add_child(paths)
	world.attach(null, flora, paths, terrain, water)
	var painter := FloraTool.new(rig, flora, paths, world)
	painter.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(painter)
	var look := Look.build(root)
	var palette := Palette.new()
	var no_hands: Array[Node3D] = []
	await process_frame
	var wildlife := Wildlife.new(water, flora, null, palette, rig.head, no_hands, 3, look)
	wildlife.set_process(false)
	root.add_child(wildlife)
	var ff := wildlife.fireflies

	look.set_time(0.98)
	_run(wildlife, 5.0)
	_check(ff.count() == 0, "a dusk without a pond or flowers has no fireflies")

	await _dig(tool, 3, -4)
	water.ponds[0]._process(PondWater.FILL)
	look.set_time(Daylight.DEFAULT)
	_run(wildlife, 5.0)
	_check(ff.count() == 0 and ff.mm.visible_instance_count == 0, "none by day")

	look.set_time(0.98)
	_run(wildlife, 3.0)
	var n := ff.count()
	_check(n >= Fireflies.PER_HABITAT.x and n <= Fireflies.PER_HABITAT.y, "a pond at dusk has its fireflies, %d" % n)
	_check(ff.mm.visible_instance_count == n, "each is drawn")
	var pond := water.ponds[0]
	var near := true
	for k in ff.spots:
		for s: Vector4 in ff.spots[k]:
			var shore := INF
			for g in pond.pond.shore:
				shore = minf(shore, Terrain.grid_xz(g).distance_to(Vector2(s.x, s.z)))
			var ground := maxf(Terrain.height_at(s.x, s.z), pond.surface_y())
			near = near and shore <= Fireflies.SHORE_SPREAD + 0.01 and s.y - ground >= Fireflies.HEIGHT.x - 0.01 and s.y - ground <= Fireflies.HEIGHT.y + 0.01
	_check(near, "they hover low by the pond's shore")
	_check(ff.dusk() > 0.9, "it is dark at the end of the day, %.2f" % ff.dusk())
	look.set_time(0.02)
	_check(ff.dusk() > 0.9, "and before dawn")

	palette.picks[Palette.Element.MEADOW] = 4
	_run(wildlife, 1.5)
	_check(ff.count() == n and ff.spots.values().all(func(l: Array) -> bool: return l.all(func(s: Vector4) -> bool: return s.w < 0.0)), "in winter they fade out")
	_run(wildlife, Fireflies.FADE + 1.5)
	_check(ff.count() == 0 and ff.mm.visible_instance_count == 0, "and are gone once faded")
	palette.picks[Palette.Element.MEADOW] = Palette.SUMMER
	_run(wildlife, 1.5)
	_check(ff.count() >= Fireflies.PER_HABITAT.x, "summer brings them back")

	await _dig(tool, 4.2, -4)
	_run(wildlife, Fireflies.REFRESH + 0.5)
	var reshaped := ff.spots.keys().filter(func(k: Variant) -> bool: return ff.spots[k].any(func(s: Vector4) -> bool: return s.w > 0.0))
	_check(ff.spots.size() == 2 and reshaped.size() == 1 and reshaped[0] == water.ponds[0].pond.shore.hash(), "a pond dug wider moves its fireflies to its new shore")
	_run(wildlife, Fireflies.FADE + 1.5)
	_check(ff.spots.size() == 1, "and the old ones fade away")

	var b := painter.brushes[0]
	b.hand.tool = Hand.Tool.FLOWERS
	for i in 90:
		painter.paint(b, Terrain.ground(-6, 3), 1.0, STEP)
	painter.end_stroke(b)
	_run(wildlife, 3.0)
	var patches := wildlife.butterflies.patches
	_check(not patches.is_empty(), "the painted flowers make a patch")
	var bloomed := patches.keys().all(func(k: Vector2i) -> bool: return ff.spots.has(k))
	_check(bloomed, "each flower patch has fireflies too")
	var by_blooms := true
	for k in patches:
		for s: Vector4 in ff.spots.get(k, []):
			var best := INF
			for p: Vector3 in patches[k]:
				best = minf(best, Vector2(p.x, p.z).distance_to(Vector2(s.x, s.z)))
			by_blooms = by_blooms and best <= Fireflies.BLOOM_SPREAD + 0.01
	_check(by_blooms, "they hover over the blooms")
	_check(ff.count() <= Fireflies.CAP, "never more than the cap")

	water.remove_seed(water._seeds[0])
	water.remove_seed(water._seeds[0])
	water.refill()
	_run(wildlife, Fireflies.FADE + 2.5)
	_check(water.ponds.is_empty() and not ff.spots.keys().any(func(k: Variant) -> bool: return k is int), "filling the pond in takes its fireflies away")
