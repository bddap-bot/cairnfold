extends SceneTree

## Headless checks of fish: godot4 --headless --path game --script ../tests/test_fish.gd

const STEP := 1.0 / 30.0

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	_no_tool_places_fish()
	await _they_swim_in_the_ponds()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _no_tool_places_fish() -> void:
	for f in DirAccess.get_files_at("res://src"):
		if f.ends_with("_tool.gd") or f in ["hand.gd", "driver.gd", "buttons.gd"]:
			_check(not FileAccess.get_file_as_string("res://src/" + f).contains("Fish"), "%s reaches no fish" % f)
	_check(FileAccess.get_file_as_string("res://src/wildlife.gd").count("Fish.new(") == 1, "Wildlife alone makes fish")


func _dig(tool: WaterTool, x: float, z: float) -> void:
	tool.begin(tool.rig.right, Terrain.ground(x, z))
	for i in 90:
		tool.deepen(1.0 / 60.0)
	tool.end()
	await process_frame
	await process_frame


func _run(wildlife: Wildlife, seconds: float) -> void:
	for i in int(seconds / STEP):
		wildlife.tick(STEP)


func _in_water(fish: Fish, water: Water) -> bool:
	return fish.swimming.all(func(f: Fish.One) -> bool:
		var p := water.pond_at(f.at.x, f.at.z)
		return p != null and f.at.y < p.surface_y() and f.at.y > Terrain.height_at(f.at.x, f.at.z))


func _they_swim_in_the_ponds() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var terrain := GroundGrab.new(rig, world)
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
	var palette := Palette.new()
	var hand := Node3D.new()
	root.add_child(hand)
	hand.global_position = Vector3(0, 30, 0)
	var hands: Array[Node3D] = [hand]
	await process_frame
	var wildlife := Wildlife.new(water, flora, null, palette, rig.head, hands, 3)
	root.add_child(wildlife)
	wildlife.set_process(false)
	var fish := wildlife.fish

	wildlife.tick(STEP)
	_check(fish.swimming.size() == 0 and fish.mm.visible_instance_count == 0, "no pond, no fish")

	await _dig(tool, 3, -4)
	await _dig(tool, 4.5, -4)
	water.ponds[0]._process(PondWater.FILL)
	_run(wildlife, Fish.FADE + 0.5)
	var n := fish.swimming.size()
	_check(n >= 1 and n <= Fish.PER_POND, "a pond has a few fish, %d" % n)
	_check(fish.swimming.all(func(f: Fish.One) -> bool: return f.shown >= 1.0), "faded in")
	_check(fish.mm.visible_instance_count == n, "each is drawn")
	_check(_in_water(fish, water), "under the surface, over the ground")

	var start := fish.swimming.map(func(f: Fish.One) -> Vector3: return f.at)
	var kept := true
	for i in int(60.0 / STEP):
		wildlife.tick(STEP)
		kept = kept and _in_water(fish, water)
	_check(kept, "a minute on, every one has stayed in the water")
	var moved := 0.0
	var now := fish.swimming
	for i in now.size():
		moved += now[i].at.distance_to(start[i])
	_check(moved / now.size() > 0.3, "and they swim about, %.2f m on average" % (moved / now.size()))

	var one: Fish.One = now[0]
	hand.global_position = one.at + Vector3(0.1, 0.05, 0)
	wildlife.tick(STEP)
	wildlife.tick(STEP)
	_check(one.speed > Fish.CRUISE * 2.0, "a hand coming near makes a fish dart, %.2f m/s" % one.speed)
	var from := one.at
	for i in int(Fish.DART_FOR / STEP):
		wildlife.tick(STEP)
	_check(one.at.distance_to(hand.global_position) > from.distance_to(hand.global_position), "away from it")
	_check(_in_water(fish, water), "and still in the water")
	hand.global_position = one.at + Vector3(0.1, 0.05, 0)
	_run(wildlife, 0.5)
	_run(wildlife, 3.0)
	_check(one.speed < Fish.CRUISE * 1.5, "a hand held still beside one frightens it no more, %.2f m/s" % one.speed)
	hand.global_position = Vector3(0, 30, 0)

	await _dig(tool, 5.8, -4.2)
	water.ponds[0]._process(PondWater.FILL)
	var kept_on := true
	for i in int(5.0 / STEP):
		wildlife.tick(STEP)
		kept_on = kept_on and _in_water(fish, water)
	_check(kept_on and not fish.swimming.is_empty(), "a pond dug wider keeps its fish in its water")

	await _dig(tool, -6, 5)
	_check(fish.swimming.all(func(f: Fish.One) -> bool: return f.pond != water.ponds[-1]), "none in a pond still filling")
	water.ponds[-1]._process(PondWater.FILL)
	_run(wildlife, Fish.FADE)
	_check(fish.swimming.any(func(f: Fish.One) -> bool: return f.pond == water.ponds[-1]), "a second pond has its own fish")
	_check(_in_water(fish, water), "every fish in water")
	_check(fish.swimming.size() <= Fish.CAP, "never more than the cap, %d" % fish.swimming.size())
