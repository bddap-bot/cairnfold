extends SceneTree

## Headless checks of which thing a ray takes when two meet it at once, a hand inside both: a grip takes a fitting over
## a plant and joins the build it holds over that build's own fitting, and the ground in front stops it; a delete
## takes a fitting over an easel and passes the plants, easels and boulders it already took; the style tool takes a
## boulder standing on painted stone over the stone: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_pick_ties.gd

var failures := 0
var main: Node
var world: World
var tool: WallTool
var flora: Flora


func _initialize() -> void:
	Reach.mode = Reach.Mode.AIM
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _lay() -> void:
	for w: Wall in tool.walls:
		w.lay_now()
	world.decorations.sync()


func _lantern(w: Wall) -> Dictionary:
	for t in FittingTool.targets(w):
		if t.what == "lantern":
			return t
	return {}


func _run() -> void:
	await process_frame
	world = main.world
	world.bounded = false
	tool = main.tool
	flora = main.flora_tool.flora
	var d := Driver.new(main, [
		{"op": "wall", "points": [[-6, 0], [6, 0]], "seconds": 0.2},
		{"op": "wall", "points": [[-6, 20], [6, 20]], "seconds": 0.2},
	])
	main.add_child(d)
	await d.finished
	d.queue_free()
	var a: Wall = tool.walls[0]
	var b: Wall = tool.walls[1]
	for w in [a, b]:
		_check(main.fitting_tool.fit({"what": "lantern", "wall": w, "s": w.layout.length() * 0.5, "y": 1.5, "side": 1.0}), "a lantern hangs on the wall")
	_lay()
	await _grip_takes_a_fitting_over_a_plant(a)
	await _grip_joins_the_held_build_over_its_fitting(b)
	await _ground_in_front_stops_a_grip(b)
	await _delete_takes_a_fitting_over_an_easel(b)
	await _delete_passes_what_it_took()
	await _style_takes_a_boulder_over_painted_stone()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


## Presses the right hand's grip with it at `at` pointing along `dir`, and returns its mason once the press is handled.
func _press_grip(at: Vector3, dir: Vector3) -> WallTool.Mason:
	var hand: Hand = main.rig.right
	hand.held_still = true
	hand.global_transform = Transform3D(Basis.looking_at(dir), at)
	await _frames(3)
	Buttons.injected["right_hand/grip_click"] = true
	await _frames(3)
	return tool.mason(hand)


func _let_go() -> void:
	Buttons.injected.erase("right_hand/grip_click")
	await _frames(3)
	if tool.held != null:
		tool.end_build()
	await _frames(3)
	main.rig.right.held_still = false


## A hand inside both a tree's trunk and a lantern meets each at once: the grip takes the lantern.
func _grip_takes_a_fitting_over_a_plant(w: Wall) -> void:
	var at: Vector3 = _lantern(w).bounds.get_center()
	main.flora_tool.place("tree", Terrain.ground(at.x, at.z), null, 7)
	await _frames(3)
	var dir := Vector3.FORWARD
	var plant := flora.solid_hit(at, dir, 1.0)
	var pick := FittingTool.pick_target(tool, at, dir, true)
	_check(plant.get("along", INF) == 0.0 and pick.get("along", INF) == 0.0 and pick.get("what") == "lantern", "a hand in the lantern is in the tree's trunk too: %s, %s" % [plant.get("along"), pick.get("what")])
	var m := await _press_grip(at, dir)
	_check(m.growing is FittingGrip, "a grip meeting a lantern and a tree at once takes the lantern: %s" % [m.growing])
	await _let_go()
	m = await _press_grip(at + Vector3.UP * 1.5, dir)
	_check(m.growing is Flora.Plant, "a grip in the tree's trunk alone takes the tree: %s" % [m.growing])
	await _let_go()
	world.undo()
	await _frames(3)


## With a build in hand, the other hand's grip inside that build's own lantern joins the hold rather than taking the
## lantern: the build pick that finds its lantern is the held build, which is not weighed against itself.
func _grip_joins_the_held_build_over_its_fitting(w: Wall) -> void:
	var at: Vector3 = _lantern(w).bounds.get_center()
	tool.take_build(w)
	await _frames(2)
	_check(tool.held == w, "the wall is in hand")
	var pick := FittingTool.pick_target(tool, at, Vector3.FORWARD, true)
	_check(pick.get("what") == "lantern" and pick.get("wall") == w, "a held pick into its lantern finds the held build's lantern")
	var m := await _press_grip(at, Vector3.FORWARD)
	_check(m.growing == null and tool._holders.has(m), "a grip in the held build's lantern joins the hold: %s" % [m.growing])
	await _let_go()


## A grip from under the ground toward a lantern meets the ground first and takes nothing.
func _ground_in_front_stops_a_grip(w: Wall) -> void:
	var lantern: Vector3 = _lantern(w).bounds.get_center()
	var at := Terrain.ground(lantern.x, lantern.z + 1.5) + Vector3.DOWN * 0.2
	var m := await _press_grip(at, (lantern - at).normalized())
	_check(m.growing == null and tool.held == null and not tool._holders.has(m), "a grip from under the ground takes nothing: %s, %s" % [m.growing, tool.held])
	await _let_go()


## A delete from inside an easel standing in a lantern meets both at once and takes the lantern.
func _delete_takes_a_fitting_over_an_easel(w: Wall) -> void:
	var at: Vector3 = _lantern(w).bounds.get_center()
	world.submit({"op": "easel", "at": Terrain.ground(at.x, at.z), "yaw": 0.0})
	await _frames(3)
	var dir := Vector3.FORWARD
	var easel: Dictionary = main.easels.pick(at, dir)
	_check(easel.get("along", INF) == 0.0, "a hand in the lantern is inside the easel too: %s" % [easel.get("along")])
	var aim: Dictionary = main.delete_tool.aim(at, dir)
	_check(aim.get("what") == "lantern", "a delete meeting a lantern and an easel at once takes the lantern: %s" % [aim.keys()])
	var out := Vector3(0, 0, signf(at.z - w.layout.point_at(0.0).z))
	_check(main.delete_tool.aim(at + out * 2.0, -out).has("easel"), "a delete from in front of the easel takes it")
	world.undo()
	await _frames(3)


## The delete beam passes through what its stroke already took: the plants in `taken`, and easels and boulders in
## `gone`.
func _delete_passes_what_it_took() -> void:
	var spots := _clear_spots(3)
	world.submit({"op": "easel", "at": spots[0], "yaw": 0.0})
	main.flora_tool.place_boulder(spots[1], null, 3)
	main.flora_tool.place("tree", spots[2], null, 7)
	await _frames(3)
	var tool_d: DeleteTool = main.delete_tool
	var from: Vector3 = spots[0] + Vector3(0, 1.2, 3.0)
	var aim := tool_d.aim(from, (spots[0] + Vector3.UP * 1.2 - from).normalized())
	_check(aim.has("easel"), "the beam meets the easel: %s" % [aim.keys()])
	if aim.has("easel"):
		_check(not tool_d.aim(from, (spots[0] + Vector3.UP * 1.2 - from).normalized(), {}, {aim.easel.id: true}).has("easel"), "and passes the easel it took")
	from = spots[1] + Vector3(0, 3.0, 2.0)
	var dir: Vector3 = (spots[1] + Vector3.UP * 0.3 - from).normalized()
	aim = tool_d.aim(from, dir)
	_check(aim.has("boulder"), "the beam meets the boulder: %s" % [aim.keys()])
	if aim.has("boulder"):
		_check(not tool_d.aim(from, dir, {}, {aim.boulder.id: true}).has("boulder"), "and passes the boulder it took")
	from = spots[2] + Vector3(0, 1.0, 3.0)
	dir = (spots[2] + Vector3.UP * 1.0 - from).normalized()
	aim = tool_d.aim(from, dir)
	_check(aim.has("plants"), "the beam meets the tree: %s" % [aim.keys()])
	if aim.has("plants"):
		_check(tool_d.aim(from, dir, {aim.plants[0]: true}).get("plants") != aim.plants, "and passes the tree it took")
	for i in 3:
		world.undo()
	await _frames(3)


## `n` ground spots 20 m apart with no tree or bush within 8 m of any.
func _clear_spots(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for k in 200:
		var p := Terrain.ground(-60.0 + (k % 10) * 20.0, -60.0 + (k / 10) * 20.0)
		if flora.solids_in(Rect2(p.x - 8.0, p.z - 8.0, 16.0, 16.0)).is_empty() and absf(p.z) > 30.0:
			out.append(p)
			if out.size() == n:
				break
	_check(out.size() == n, "%d clear spots" % n)
	return out


## A boulder standing on painted stone takes the style tool's aim, the stone beside it its own.
func _style_takes_a_boulder_over_painted_stone() -> void:
	var spot: Vector3 = _clear_spots(1)[0]
	var d := Driver.new(main, [
		{"op": "paint", "tool": "stone", "points": [[spot.x - 3.0, spot.z], [spot.x + 3.0, spot.z]], "radius": 2.0, "seconds": 0.4},
		{"op": "boulder", "x": spot.x, "z": spot.z, "seed": 3},
	])
	main.add_child(d)
	await d.finished
	d.queue_free()
	await _frames(3)
	var palette: PaletteTool = main.palette_tool
	var top := Terrain.ground(spot.x, spot.z) + Vector3.UP * 6.0
	var target := palette.aim_style(top, Vector3.DOWN)
	_check(target.get("of") == "boulders", "the style tool aimed at a boulder on painted stone takes the boulder: %s" % [target.get("of")])
	target = palette.aim_style(Terrain.ground(spot.x + 2.5, spot.z) + Vector3.UP * 6.0, Vector3.DOWN)
	_check(target.get("restyle") == PaletteTool.Restyle.STONE and target.has("stroke"), "and the painted stone beside it its stroke: %s" % [target])
