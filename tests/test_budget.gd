extends SceneTree

## Headless checks of the frame budget: what the garden counts follows every placement and deletion, an edit that
## would take it past the budget is turned down whole, and deleting makes room again:
## godot4 --headless --path game --script ../tests/test_budget.gd

var failures := 0
var main: Node
var world: World


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	await _counts_follow_placements_and_deletions()
	await _an_edit_past_the_budget_is_turned_down_and_deleting_makes_room()
	await _painting_stops_at_the_budget()
	await _the_bar_shows_the_share()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _settled() -> void:
	for i in 3:
		await process_frame
	main.flora_tool.flora.grow_now()


## What the garden holds, counted afresh from its state rather than kept command by command.
func _recount() -> Dictionary:
	var out := {}
	for d: Dictionary in world.state.walls.values():
		Budget.add(out, Budget.wall(d))
	for p: Dictionary in world.state.paths.values():
		Budget.add(out, Budget.path(p))
	for g in world.state.groups:
		for p: Flora.Plant in world.flora.groups[g]:
			if p != null and not world.state.groups[g].hidden.has(p.index):
				var u := world.flora.unit_of(p)
				if u != "" and not (g == 0 and u == "grass"):
					Budget.add(out, {u: 1})
	if not world.state.seeds.is_empty():
		out.pond = world.state.seeds.size()
	return out


func _same(a: Dictionary, b: Dictionary) -> bool:
	for k in Budget.UNITS:
		if not is_equal_approx(snappedf(a.get(k, 0.0), 0.001), snappedf(b.get(k, 0.0), 0.001)):
			return false
	return true


static func _wall(from: Vector2, to: Vector2, height: float) -> Dictionary:
	var points := PackedVector3Array()
	for i in 9:
		var p := from.lerp(to, i / 8.0)
		points.append(Terrain.ground(p.x, p.y))
	return {"points": points, "height": height, "arches": PackedFloat32Array(), "seed": 7, "closed": false, "top": 0,
		"fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(),
		"ruins": PackedVector2Array(), "plaster": false, "on": PackedInt32Array(), "paint": Palette.plain()}


## Submits a wall command and waits for it to settle; whether it went into the garden.
func _build(walls: Array) -> bool:
	var before: int = world.state.walls.size()
	var settled := [false]
	world.submit({"op": "wall", "walls": walls}, func() -> void: settled[0] = true, main.rig.right)
	_check(settled[0], "a wall command settles at once on the host")
	await _settled()
	return world.state.walls.size() > before


func _counts_follow_placements_and_deletions() -> void:
	var meadow := world.units.duplicate()
	_check(meadow.get("flower", 0) > 0 and meadow.get("tree", 0) > 0, "the meadow's own flowers and trees count: %s" % meadow)
	_check(_same(world.units, _recount()), "a fresh garden counts what it holds")
	await _play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-6, -2], [-1, -3]], "seconds": 0.3},
		{"op": "tree", "x": -6, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[6, 4], [7, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "pave", "points": [[3.5, -6], [3.5, 1]], "radius": 0.8, "seconds": 0.3},
		{"op": "dig", "x": 10, "z": -8, "seconds": 0.5},
	])
	await _settled()
	_check(world.units.get("wall_m2", 0.0) > 0.0 and world.units.get("path_m2", 0.0) > 0.0 and world.units.get("pond", 0) == 1, "walls, paths and ponds count: %s" % world.units)
	_check(world.units.get("tree", 0) == meadow.tree + 1 and world.units.get("flower", 0) > meadow.flower, "a planted tree and painted flowers count: %s" % world.units)
	_check(_same(world.units, _recount()), "what the garden counts matches what it holds: %s against %s" % [world.units, _recount()])
	var wall_id: int = world.state.walls.keys()[0]
	var wall_units := Budget.wall(world.state.walls[wall_id])
	var with_wall := world.units.duplicate()
	world.submit({"op": "unwall", "ids": PackedInt32Array([wall_id])})
	await _settled()
	_check(is_equal_approx(world.units.get("wall_m2", 0.0), with_wall.wall_m2 - wall_units.wall_m2), "deleting a wall frees what it counted")
	await _play([{"op": "delete", "x": -6, "z": 4, "height": 3.0}])
	await _settled()
	_check(world.units.get("tree", 0) == meadow.tree, "deleting the tree frees it: %s" % world.units)
	_check(_same(world.units, _recount()), "after deletions the count still matches the garden")
	for i in 8:
		world.undo()
		await _settled()
	_check(_same(world.units, _recount()), "undo and redo keep the count matching the garden")
	await _play([{"op": "bare"}])
	await _settled()
	_check(_same(world.units, _recount()) and not world.units.has("wall_m2") and not world.units.has("flower"), "a wipe leaves nothing counted but the bare meadow: %s" % world.units)
	world.undo()
	await _settled()
	_check(_same(world.units, _recount()), "undoing the wipe counts the garden it brings back")
	await _play([{"op": "bare"}])
	await _settled()


func _an_edit_past_the_budget_is_turned_down_and_deleting_makes_room() -> void:
	var on := world.devices()
	var piece := _wall(Vector2(-12, -20), Vector2(12, -20), 4.5)
	var share := Budget.fill(Budget.wall(piece), on)
	_check(share > 0.02 and share < 0.3, "one test wall takes a measurable share: %.3f" % share)
	var too_big := [_wall(Vector2(-40, 30), Vector2(40, 30), 9.0), _wall(Vector2(-40, 34), Vector2(40, 34), 9.0), _wall(Vector2(-40, 38), Vector2(40, 38), 9.0)]
	var before := world.units.duplicate()
	_check(not await _build(too_big), "a build past the whole budget is turned down")
	_check(_same(world.units, before), "a turned-down build counts nothing")
	var built := 0
	for i in 40:
		var at := -30.0 + i * 3.0
		if not await _build([_wall(Vector2(-12, at), Vector2(12, at), 4.5)]):
			break
		built += 1
	_check(built > 0 and built < 40, "walls go up until the budget is full: %d" % built)
	_check(world.fill() <= 1.0, "the garden never passes its budget: %.3f" % world.fill())
	_check(world.fill() + share > 1.0, "the wall turned down would have passed it: %.3f + %.3f" % [world.fill(), share])
	var full := world.units.duplicate()
	var last: int = world.state.walls.keys().max()
	world.submit({"op": "unwall", "ids": PackedInt32Array([last])})
	await _settled()
	_check(world.fill() < Budget.fill(full, on), "deleting a wall frees its share")
	_check(await _build([_wall(Vector2(-12, -50), Vector2(12, -50), 4.5)]), "the room it freed takes another wall")
	var tall_id: int = world.state.walls.keys().max()
	world.submit({"op": "reshape", "id": tall_id, "data": {"height": 9.0}})
	await _settled()
	_check(world.state.walls[tall_id].height == 4.5, "pulling a wall taller than the budget allows is turned down")
	await _play([{"op": "bare"}])
	await _settled()


func _painting_stops_at_the_budget() -> void:
	for i in 40:
		var at := -30.0 + i * 3.0
		if not await _build([_wall(Vector2(-12, at), Vector2(12, at), 4.5)]):
			break
	var walls: Array = world.state.walls.keys()
	world.submit({"op": "unwall", "ids": PackedInt32Array([walls.max()])})
	await _settled()
	await _play([{"op": "paint", "tool": "flowers", "points": [[-20, 20], [20, 20]], "radius": 3.0, "seconds": 6.0}])
	await _settled()
	_check(world.fill() <= 1.0, "a long paint stroke stops at the budget: %.3f" % world.fill())
	_check(world.units.get("flower", 0) > 0, "it painted up to it")


func _the_bar_shows_the_share() -> void:
	var bars := []
	for h in main.rig.hands:
		for c in h.get_children():
			if c is BudgetBar:
				bars.append(c)
	_check(bars.size() == 2, "each controller carries a bar")
	for i in 60:
		await process_frame
	for b: BudgetBar in bars:
		var shown: float = b.material_override.get_shader_parameter("fill")
		_check(absf(shown - world.fill()) < 0.01, "the bar shows the garden's share: %.3f against %.3f" % [shown, world.fill()])
