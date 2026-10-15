extends SceneTree

## Headless checks of wildlife: godot4 --headless --path game --script ../tests/test_wildlife.gd

const STEP := 1.0 / 30.0

var failures := 0


func _initialize() -> void:
	_no_tool_places_an_animal()
	await _ducks_come_only_to_ponds()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run(wildlife: Wildlife, seconds: float, each := Callable()) -> void:
	var t := 0.0
	while t < seconds:
		wildlife.tick(STEP)
		if each.is_valid():
			each.call()
		t += STEP


## No hand tool, no scripted step and nothing but the game's root reaches an animal; Wildlife offers no way
## to add one.
func _no_tool_places_an_animal() -> void:
	for key in Hand.Tool.keys():
		_check(not key in ["DUCK", "DUCKS", "ANIMAL", "ANIMALS", "WILDLIFE"], "no hand tool %s" % key)
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			var code := FileAccess.get_file_as_string("res://src/" + f)
			_check(not code.contains("Duck") and not code.contains("ildlife"), "%s reaches no animal" % f)
	_check(FileAccess.get_file_as_string("res://src/main.gd").count("Wildlife.new(") == 1, "main makes one Wildlife")
	for m in (load("res://src/wildlife.gd") as Script).get_script_method_list():
		_check(m.name.begins_with("_") or m.name in ["tick", "ducks"], "Wildlife exposes no way to add an animal, found %s" % m.name)


func _dig(tool: WaterTool, x: float, z: float, frames: int) -> void:
	tool.begin(tool.rig.right, Terrain.ground(x, z))
	for i in frames:
		tool.deepen(1.0 / 60.0)
	tool.end()
	await process_frame
	await process_frame


func _from_shore(p: PondWater, at: Vector3) -> float:
	var best := INF
	for g in p.pond.shore:
		best = minf(best, Terrain.grid_xz(g).distance_to(Vector2(at.x, at.z)))
	return best


## Every duck that disappears was out of the viewer's sight in its last frame.
func _watch_vanishing(wildlife: Wildlife, seen: Dictionary) -> Callable:
	return func() -> void:
		var now := {}
		for d in wildlife.ducks():
			now[d] = wildlife._in_sight(d.position)
		for d in seen:
			if not now.has(d) and seen[d]:
				_check(false, "a duck vanished in sight")
		seen.clear()
		seen.merge(now)


func _ducks_come_only_to_ponds() -> void:
	Terrain.install()
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
	world.attach(null, null, null, terrain, water)
	var flora := Flora.new()
	root.add_child(flora)
	var no_hands: Array[Node3D] = []
	await process_frame
	var wildlife := Wildlife.new(water, flora, null, Palette.new(), rig.head, no_hands, 1)
	wildlife.set_process(false)
	root.add_child(wildlife)

	_run(wildlife, 600.0)
	_check(wildlife.ducks().is_empty(), "a meadow without a pond draws no ducks")

	await _dig(tool, 3, -4, 90)
	await _dig(tool, 4.5, -4, 90)
	_check(water.ponds.size() == 1 and water.ponds[0].pond.cells.size() >= Wildlife.MIN_POND, "a dug pond, %d wet points" % (water.ponds[0].pond.cells.size() if water.ponds.size() else 0))
	var pond := water.ponds[0]
	pond._process(PondWater.FILL)
	_check(rig.head.global_position.direction_to(Vector3(3.75, pond.surface_y(), -4)).dot(-rig.head.global_basis.z) > Wildlife.SIGHT, "the viewer looks at the pond")
	var seen := {}
	var vanishing := _watch_vanishing(wildlife, seen)
	var arrived := [false]
	var first_sight := func() -> void:
		vanishing.call()
		for d in wildlife.ducks():
			if not arrived[0]:
				_check(not wildlife._in_sight(d.position), "a duck first appears out of sight")
		arrived[0] = arrived[0] or not wildlife.ducks().is_empty()
	_run(wildlife, Wildlife.ARRIVE_AFTER.x - 1.0, first_sight)
	_check(wildlife.ducks().is_empty(), "no duck before its time")
	_run(wildlife, Wildlife.ARRIVE_AFTER.y - Wildlife.ARRIVE_AFTER.x + 2.0, first_sight)
	_check(wildlife.families.size() == 1, "a duck comes to the pond some time after it appears")

	var states := {}
	var worst := [0.0, 0.0, 0]
	var watch := func() -> void:
		vanishing.call()
		for f in wildlife.families:
			states[f.state] = true
			if f.state == Wildlife.State.REST:
				var at := f.leader().position
				worst[0] = maxf(worst[0], _from_shore(pond, at))
				worst[2] += int(water.pond_at(at.x, at.z) != null)
		for d in wildlife.ducks():
			if d.afloat:
				worst[1] = maxf(worst[1], absf(d.position.y - (pond.surface_y() - Wildlife.SINK * d.size)))
	_run(wildlife, 240.0, watch)
	_check(wildlife.families.size() == 1 and states.has(Wildlife.State.SWIM) and states.has(Wildlife.State.REST), "it swims, then rests on the bank, states %s" % [states.keys()])
	_check(worst[2] == 0 and worst[0] <= Wildlife.BANK.y + 0.75, "it rests on dry grass near the water, at most %.2f m from the shore" % worst[0])
	_check(worst[1] < 0.02, "afloat, each duck sits at the waterline, off by %.3f" % worst[1])

	var flier := Wildlife.new(water, flora, null, Palette.new(), rig.head, no_hands, 0)
	root.add_child(flier)
	flier.set_process(false)
	var lone: Duck = null
	var lone_seed := 0
	for seed in 40:
		flier.rng.seed = seed
		lone_seed = seed
		flier._arrive(pond)
		if flier.families[-1].ducks.size() == 1:
			lone = flier.families[-1].leader()
			break
		for d in flier.families[-1].ducks:
			d.free()
		flier.families.pop_back()
	_check(lone != null, "a lone duck flies in")
	var high := lone.position.y - pond.surface_y()
	_run(flier, 10.0)
	_check(high > 5.0 and flier.families[-1].state == Wildlife.State.SWIM and lone.afloat, "it comes down from %.1f m and settles on the water" % high)
	flier.families.clear()
	lone.free()
	flier.rng.seed = lone_seed
	flier._arrive(pond)
	var midair := flier.families[-1]
	_check(midair.state == Wildlife.State.FLY_IN, "the same seed flies in again")
	_run(flier, 1.0)
	var low := [midair.leader().position.y, 0.0]
	var walker := Wildlife.new(water, flora, null, Palette.new(), rig.head, no_hands, 0)
	root.add_child(walker)
	walker.set_process(false)
	for seed in 40:
		walker.rng.seed = seed
		walker._arrive(pond)
		if walker.families[-1].ducks.size() > 1:
			break
		walker.families[-1].leader().free()
		walker.families.pop_back()
	_check(walker.families.size() == 1 and walker.families[0].ducks.size() > 2, "a mother walks in with ducklings")
	_run(walker, 90.0)
	_check(walker.families[0].state in [Wildlife.State.SWIM, Wildlife.State.ASHORE, Wildlife.State.REST], "and they reach the water")

	world.undo()
	world.undo()
	await process_frame
	await process_frame
	_check(water.ponds.is_empty(), "the pond drains")
	var flying := _watch_vanishing(flier, {})
	flying.call()
	var climbing := func() -> void:
		flying.call()
		if not flier.families.is_empty():
			low[1] = minf(low[1], flier.families[0].leader().position.y - low[0])
			low[0] = flier.families[0].leader().position.y
	_run(flier, 30.0, climbing)
	_check(flier.families.is_empty() and low[1] >= 0.0, "a duck flying in to a drained pond turns back up and away")
	flier.queue_free()
	var walking := _watch_vanishing(walker, {})
	walking.call()
	_run(walker, 400.0, walking)
	_check(walker.families.is_empty(), "a family walks away from a drained pond")
	walker.queue_free()

	_run(wildlife, 400.0, vanishing)
	_check(wildlife.families.is_empty(), "the ducks leave a drained pond")
	_run(wildlife, 300.0)
	_check(wildlife.ducks().is_empty(), "and none come back without water")
