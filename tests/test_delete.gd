extends "res://../tests/support/suite.gd"

## Headless checks that the delete tool takes every kind of thing a garden holds, pointed at as a player points,
## and that what it took stays gone in the saved garden: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_delete.gd

var tool: DeleteTool
var flora: Flora
var world: World
var save := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	tool = main.delete_tool
	flora = main.flora_tool.flora
	world = main.world
	save = OS.get_user_data_dir().path_join("nestcombe-delete-%d.garden" % OS.get_process_id())
	world.load_from(save)
	_every_spawned_solid_is_struck()
	var tree := _spawned(flora.trunks)
	var bush := _spawned(flora.bushes)
	await _takes_solid(tree, "a spawned tree")
	await _takes_solid(bush, "a spawned bush")
	await play([{"op": "tree", "x": 6, "z": 6}, {"op": "wait", "seconds": 0.1}])
	await _takes_solid(flora.placed("tree")[0], "a planted tree")
	await _no_strike_through_hills()
	await _takes_marks()
	await _mows()
	_a_wide_swipe_mows_its_band_in_few_rays()
	await _one_stroke()
	await process_frame
	world.flush()
	world.restore(bytes_to_var(FileAccess.get_file_as_bytes(save)))
	check(not _standing(tree) and not _standing(bush), "the spawned tree and bush stay gone in the saved garden")
	check(flora.placed("tree").is_empty(), "the planted tree stays gone in the saved garden")
	check(world.state.paths.is_empty() and world.state.grounds.is_empty(), "the path and stone stay gone in the saved garden")
	check(flora.plants_near(world.terrain.ground(4, 3), 0.5).is_empty(), "the mown meadow stays mown in the saved garden")
	DirAccess.remove_absolute(save)
	finish()


## Every tree and bush the meadow grows, aimed at from beside it at head height, is what the beam strikes, or one
## nearer that stands in the way.
func _every_spawned_solid_is_struck() -> void:
	var missed := 0
	var solids := flora.solids()
	for parts in solids:
		if not _struck(parts):
			var aim := tool.aim(_eye(parts), _toward(parts))
			if not aim.has("plants") or _eye(parts).distance_to(aim.point) > _eye(parts).distance_to(_centre(parts)):
				missed += 1
	check(solids.size() == Meadow.TREES + Meadow.BUSHES, "the meadow's %d trees and bushes are all solids: %d" % [Meadow.TREES + Meadow.BUSHES, solids.size()])
	check(missed == 0, "a beam aimed at each spawned tree or bush strikes it or one in front: %d of %d missed" % [missed, solids.size()])


func _struck(parts: Array) -> bool:
	return tool.aim(_eye(parts), _toward(parts)).get("plants") == parts


func _toward(parts: Array) -> Vector3:
	return (_centre(parts) - _eye(parts)).normalized()


func _takes_solid(parts: Array, what: String) -> void:
	tool.press(self, _eye(parts), _toward(parts))
	check(tool.hold(self, _eye(parts), _toward(parts)).get("plants") != parts, "a held beam passes through %s once it took it" % what)
	tool.let_go(self)
	await process_frame
	check(not _standing(parts), "delete takes %s it points at" % what)
	var group: int = parts[0].group
	check(parts.all(func(p: Flora.Plant) -> bool: return world.state.groups[group].hidden.has(p.index)), "%s's taking is in the garden's state" % what)


## A tree behind a hill is out of reach: the beam stops at the ground it meets first.
func _no_strike_through_hills() -> void:
	var parts := _spawned(flora.trunks)
	var eye := _eye(parts)
	var dir := _toward(parts)
	var mid := eye + dir * eye.distance_to(_centre(parts)) * 0.5
	await play([{"op": "sculpt", "x": mid.x, "z": mid.z, "lift": 4.0, "radius": 1.5, "seconds": 0.5}])
	check(world.terrain.height_at(mid.x, mid.z) > mid.y, "a hill rises between the eye and a tree")
	check(not tool.aim(eye, dir).has("plants"), "the beam does not strike the tree behind the hill")
	await play([{"op": "press", "button": "dpad_down"}])


func _takes_marks() -> void:
	await play([
		{"op": "pave", "points": [[-6, -12], [0, -12]], "radius": 0.8, "seconds": 0.4},
		{"op": "paint", "tool": "stone", "points": [[8, -12], [11, -12]], "radius": 1.5, "seconds": 0.4},
	])
	check(world.state.paths.size() == 1 and world.state.grounds.size() == 1, "a path and a stone stroke are laid")
	check(world.marks.laid_bare(-3, -12) > 0.9 and world.marks.stone(9.5, -12) > 0.5, "they show in the ground")
	await play([{"op": "delete", "x": -3, "z": -12}])
	check(world.state.paths.is_empty(), "delete takes the path it points at")
	check(world.marks.laid_bare(-3, -12) < 0.1, "the ground under the path is meadow again")
	check(world.state.grounds.size() == 1, "and leaves the stone")
	await play([{"op": "delete", "x": 9.5, "z": -12}])
	check(world.state.grounds.is_empty() and world.marks.stone(9.5, -12) < 0.1, "delete takes the stone stroke it points at")


func _mows() -> void:
	var meadow := world.terrain.ground(4, 3)
	check(not flora.plants_near(meadow, 0.5).is_empty(), "the meadow's own grass grows at the mown spot")
	await play([
		{"op": "paint", "tool": "flowers", "points": [[-4, 3], [-3.5, 3]], "radius": 1.0, "seconds": 0.5},
		{"op": "erase", "points": [[-4, 3], [4, 3]], "height": 6, "seconds": 0.6},
	])
	var left := flora.plants_near(world.terrain.ground(-3.75, 3), 0.5)
	check(left.is_empty(), "a held sweep mows the painted flowers: %d left" % left.size())
	left = flora.plants_near(meadow, 0.5)
	check(left.is_empty(), "and the meadow's own grass and flowers: %d left" % left.size())
	check(not flora.plants_near(world.terrain.ground(4, 6), 0.5).is_empty(), "beyond the ring the meadow stands")
	await play([{"op": "press", "button": "dpad_down"}])
	check(not flora.plants_near(meadow, 0.5).is_empty(), "undo stands the mown meadow back up")
	await play([{"op": "press", "button": "A"}])
	check(flora.plants_near(meadow, 0.5).is_empty(), "redo mows it again")


## One held sweep across two trees, a wall, a path and the meadow takes them all, and one undo puts them all back.
func _one_stroke() -> void:
	await play([
		{"op": "wall", "points": [[2, -26], [2, -18]], "seconds": 0.6},
		{"op": "tree", "x": -2, "z": -22},
		{"op": "tree", "x": 6, "z": -22},
		{"op": "pave", "points": [[9, -24], [9, -20]], "radius": 0.8, "seconds": 0.4},
	])
	var trees := flora.placed("tree")
	var wall: Wall = main.tool.walls[-1]
	var grass := world.terrain.ground(12, -22)
	check(trees.size() == 2 and world.state.paths.size() == 1, "two trees and a path stand in the stroke's way")
	check(not flora.plants_near(grass, 0.5).is_empty(), "and the meadow grows at its far end")
	var steps: int = world.stacks[world.me()].undo.size()
	await play([{"op": "erase", "points": [[-4, -22], [13, -22]], "height": 14, "seconds": 1.5}])
	check(not trees.any(_standing), "one held sweep takes both trees it passes over")
	check(not Array(world.state.walls[wall.id].ruins).is_empty(), "breaks the wall it crosses into a ruin")
	check(world.state.paths.is_empty(), "lifts the path")
	check(flora.plants_near(grass, 0.5).is_empty(), "and mows the meadow")
	check(world.stacks[world.me()].undo.size() == steps + 1, "as one undo step: %d" % (world.stacks[world.me()].undo.size() - steps))
	await play([{"op": "press", "button": "dpad_down"}])
	check(trees.all(_standing), "one undo stands both trees back up")
	check(Array(world.state.walls[wall.id].ruins).is_empty(), "makes the wall whole")
	check(world.state.paths.size() == 1, "lays the path again")
	check(not flora.plants_near(grass, 0.5).is_empty(), "and the meadow")
	await play([{"op": "press", "button": "A"}])
	check(not trees.any(_standing) and world.state.paths.is_empty(), "redo takes the whole stroke again")
	var show := {"op": "show", "plants": {}, "on": false}
	var gone := {"op": "take", "of": "paths", "ids": PackedInt32Array([999999])}
	check(Commands.clean({"op": "batch", "cmds": [gone, show]}, world.state, false, world.terrain).get("cmds", []).size() == 1, "a stroke whose path went meanwhile still takes the rest")
	check(Commands.clean({"op": "batch", "cmds": [gone]}, world.state, false, world.terrain).is_empty(), "one with nothing left to take is turned down")
	check(Commands.clean({"op": "batch", "cmds": [show, show]}, world.state, false, world.terrain).is_empty(), "a batch shows plants once")
	check(Commands.clean({"op": "batch", "cmds": [{"op": "wipe"}]}, world.state, false, world.terrain).is_empty(), "a batch carries only takings")


func _spawned(pool: Flora.Pool) -> Array:
	for parts in flora.solids():
		if parts[0].pool == pool and parts[0].slot < pool.kept and _struck(parts):
			return parts
	return []


func _standing(parts: Array) -> bool:
	return parts.any(func(p: Flora.Plant) -> bool: return p.shown())


func _centre(parts: Array) -> Vector3:
	var top: Flora.Plant = parts[-1]
	return top.xform.origin + Vector3.UP * world.terrain.height_at(top.anchor.x, top.anchor.z)


## A player's hand at head height, a few metres from the solid towards the glade's centre.
func _eye(parts: Array) -> Vector3:
	var a: Vector3 = parts[0].anchor
	var toward := Vector3(-a.x, 0, -a.z).normalized()
	return world.terrain.ground(a.x + toward.x * 3.0, a.z + toward.z * 3.0) + Vector3.UP * 1.6


## A swipe of a wide ring across the meadow in one frame mows the whole band it crossed, taking rays half a ring
## apart rather than one every STEP, so a wide sweep does not mow the same plants over and over.
func _a_wide_swipe_mows_its_band_in_few_rays() -> void:
	var a := world.terrain.ground(-10, -6)
	var b := world.terrain.ground(2, -6)
	var up := Vector3.UP * 14.0
	var radius := FloraTool.brush_radius(a + up, a)
	tool.press(self, a + up, Vector3.DOWN)
	tool.hold(self, b + up, Vector3.DOWN)
	var taken: Dictionary = tool._cuts[self].plants
	var standing := 0
	for i in 13:
		var p := a.lerp(b, i / 12.0)
		standing += flora.plants_near(p, 0.2 * radius).filter(func(q: Flora.Plant) -> bool: return not taken.has(q) and not flora.on_path(q.anchor)).size()
	tool.let_go(self)
	check(standing == 0, "a wide ring swiped in one frame mows its whole band: %d standing" % standing)
	check(DeleteTool.steps(a.distance_to(b), radius) == ceili(a.distance_to(b) / (radius * 0.5)), "a %.1f m ring's swipe takes rays half a ring apart" % radius)
