extends SceneTree

## Headless checks of trees and bushes a pond covers: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_drown.gd

const AT := Vector2(3, -4)

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	await _a_pond_takes_out_what_it_covers()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _a_pond_takes_out_what_it_covers() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var world := World.new()
	root.add_child(world)
	var terrain := GroundGrab.new(rig, world)
	root.add_child(terrain)
	var water := Water.new([])
	root.add_child(water)
	var tool := WaterTool.new(rig, world)
	root.add_child(tool)
	var flora := Flora.new()
	root.add_child(flora)
	flora.keep()
	var paths := Paths.new()
	root.add_child(paths)
	var walls := WallTool.new(rig, world, flora, paths)
	root.add_child(walls)
	walls.set_process(false)
	world.attach(walls, flora, paths, terrain, water)
	await process_frame
	var hand := rig.right

	terrain.begin(hand, Terrain.ground(AT.x, AT.y), 2.8)
	terrain.pull(hand, -1.0)
	terrain.end_stroke(hand)
	await process_frame
	var bare := world.units.duplicate()
	world.submit({"op": "plant", "kind": "tree", "seed": 4, "at": Terrain.ground(AT.x, AT.y)})
	world.submit({"op": "plant", "kind": "bush", "seed": 5, "at": Terrain.ground(AT.x + 0.8, AT.y)})
	await process_frame
	var tree: Array = flora.placed("tree")
	var bush: Array = flora.placed("bush")
	_check(tree.size() == 1 and bush.size() == 1, "a tree and a bush stand in the dry hollow")
	_check(world.units.get("tree", 0.0) == bare.get("tree", 0.0) + 1.0 and world.units.get("bush", 0.0) == bare.get("bush", 0.0) + 1.0, "and count in the budget")
	var tree_group: int = tree[0][0].group
	var bush_group: int = bush[0][0].group
	var standing := flora.solids().size()

	var rim := Vector3(AT.x, Water.brim(AT.x, AT.y, 2.8 * GroundGrab.SPREAD), AT.y)
	tool.fill(hand, rim)
	await process_frame
	await process_frame
	_check(water.pond_at(AT.x, AT.y) != null and Water.drowned(tree[0][0].anchor), "the pond covers the tree's root")
	_check(tree[0].all(func(p: Flora.Plant) -> bool: return not p.shown()) and not bush[0][0].shown(), "the pond takes out the tree, every blob, and the bush")
	_check(flora.placed("tree").is_empty() and flora.placed("bush").is_empty() and flora.solids().size() == standing - 2, "neither stands among the solids the beam, shade and animals find")
	_check(world.units.get("tree", 0.0) == bare.get("tree", 0.0) and world.units.get("bush", 0.0) == bare.get("bush", 0.0), "the budget gives back their share, tree %.1f bush %.1f" % [world.units.get("tree", 0.0), world.units.get("bush", 0.0)])
	_check(world.state.groups[tree_group].hidden.size() == tree[0].size() and world.state.groups[bush_group].hidden.size() == 1, "the garden holds them as taken out")
	var saved := world.snapshot()
	_check(saved.cmds.any(func(c: Dictionary) -> bool: return c.op == "show" and not c.on and c.plants.has(tree_group)), "so does its save and what a joining player is handed")
	_check(not flora.solids().any(func(parts: Array) -> bool: return Water.drowned(parts[0].anchor)), "nothing stands drowned, the meadow's own trees included")

	world.submit({"op": "show", "plants": {tree_group: PackedInt32Array(range(tree[0].size()))}, "on": true})
	await process_frame
	_check(not tree[0][0].shown() and world.units.get("tree", 0.0) == bare.get("tree", 0.0), "showing it again under the water leaves it out")
	world.submit({"op": "plant", "kind": "tree", "seed": 6, "at": Terrain.ground(AT.x, AT.y)})
	await process_frame
	_check(flora.placed("tree").is_empty() and world.units.get("tree", 0.0) == bare.get("tree", 0.0), "a tree planted in the water does not stand")
	for i in 3:
		world.undo()
		await process_frame
	_check(water.ponds.is_empty(), "undo takes the pond away")
	_check(tree[0].all(func(p: Flora.Plant) -> bool: return p.shown()) and bush[0][0].shown(), "and stands the tree and bush back up")
	_check(world.units.get("tree", 0.0) == bare.get("tree", 0.0) + 1.0 and world.units.get("bush", 0.0) == bare.get("bush", 0.0) + 1.0, "counting in the budget again")
	world.redo()
	await process_frame
	_check(not water.ponds.is_empty() and not tree[0][0].shown() and not bush[0][0].shown(), "redo fills it and takes them out again")

	world.restore(saved)
	await process_frame
	var again: Array = flora.groups[tree_group]
	_check(not water.ponds.is_empty() and not again[0].shown() and world.units.get("tree", 0.0) == bare.get("tree", 0.0), "a garden rebuilt from its save has the pond and not the tree")
	for n in [tool, walls, terrain, world, water, flora, paths, rig]:
		n.queue_free()
	await process_frame
