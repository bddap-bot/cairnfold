extends SceneTree

## Headless checks that the delete tool takes every kind of thing a garden holds, pointed at as a player points,
## and that what it took stays gone in the saved garden: godot4 --headless --path game --script ../tests/test_delete.gd

var failures := 0
var main: Node
var tool: DeleteTool
var flora: Flora
var world: World
var save := ""


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	tool = main.delete_tool
	flora = main.flora_tool.flora
	world = main.world
	save = OS.get_temp_dir().path_join("cairnfold-delete-%d.garden" % OS.get_process_id())
	world.load_from(save)
	_every_spawned_solid_is_struck()
	var tree := _spawned(flora.trunks)
	var bush := _spawned(flora.foliage)
	await _takes_solid(tree, "a spawned tree")
	await _takes_solid(bush, "a spawned bush")
	await _play([{"op": "tree", "x": 6, "z": 6}, {"op": "wait", "seconds": 0.1}])
	await _takes_solid(flora.planted_trees()[0], "a planted tree")
	await _no_strike_through_hills()
	await _takes_marks()
	await _mows()
	await process_frame
	world.flush()
	world.restore(bytes_to_var(FileAccess.get_file_as_bytes(save)))
	_check(not _standing(tree) and not _standing(bush), "the spawned tree and bush stay gone in the saved garden")
	_check(flora.planted_trees().is_empty(), "the planted tree stays gone in the saved garden")
	_check(world.state.paths.is_empty() and world.state.grounds.is_empty(), "the path and stone stay gone in the saved garden")
	_check(flora.plants_near(Terrain.ground(4, 3), 0.5).is_empty(), "the mown meadow stays mown in the saved garden")
	DirAccess.remove_absolute(save)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


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
	_check(solids.size() == Meadow.TREES + Meadow.BUSHES, "the meadow's %d trees and bushes are all solids: %d" % [Meadow.TREES + Meadow.BUSHES, solids.size()])
	_check(missed == 0, "a beam aimed at each spawned tree or bush strikes it or one in front: %d of %d missed" % [missed, solids.size()])


func _struck(parts: Array) -> bool:
	return tool.aim(_eye(parts), _toward(parts)).get("plants") == parts


func _toward(parts: Array) -> Vector3:
	return (_centre(parts) - _eye(parts)).normalized()


func _takes_solid(parts: Array, what: String) -> void:
	tool.press(self, _eye(parts), _toward(parts))
	tool.let_go(self)
	await process_frame
	_check(not _standing(parts), "delete takes %s it points at" % what)
	var group: int = parts[0].group
	_check(parts.all(func(p: Flora.Plant) -> bool: return world.state.groups[group].hidden.has(p.index)), "%s's taking is in the garden's state" % what)


## A tree behind a hill is out of reach: the beam stops at the ground it meets first.
func _no_strike_through_hills() -> void:
	var parts := _spawned(flora.trunks)
	var eye := _eye(parts)
	var dir := _toward(parts)
	var mid := eye + dir * eye.distance_to(_centre(parts)) * 0.5
	await _play([{"op": "sculpt", "x": mid.x, "z": mid.z, "lift": 4.0, "radius": 1.5, "seconds": 0.5}])
	_check(Terrain.height_at(mid.x, mid.z) > mid.y, "a hill rises between the eye and a tree")
	_check(not tool.aim(eye, dir).has("plants"), "the beam does not strike the tree behind the hill")
	await _play([{"op": "press", "button": "dpad_down"}])


func _takes_marks() -> void:
	await _play([
		{"op": "pave", "points": [[-6, -12], [0, -12]], "radius": 0.8, "seconds": 0.4},
		{"op": "paint", "tool": "stone", "points": [[8, -12], [11, -12]], "radius": 1.5, "seconds": 0.4},
	])
	_check(world.state.paths.size() == 1 and world.state.grounds.size() == 1, "a path and a stone stroke are laid")
	_check(Ground.laid_bare(-3, -12) > 0.9 and Ground.stone(9.5, -12) > 0.5, "they show in the ground")
	await _play([{"op": "delete", "x": -3, "z": -12}])
	_check(world.state.paths.is_empty(), "delete takes the path it points at")
	_check(Ground.laid_bare(-3, -12) < 0.1, "the ground under the path is meadow again")
	_check(world.state.grounds.size() == 1, "and leaves the stone")
	await _play([{"op": "delete", "x": 9.5, "z": -12}])
	_check(world.state.grounds.is_empty() and Ground.stone(9.5, -12) < 0.1, "delete takes the stone stroke it points at")


func _mows() -> void:
	var meadow := Terrain.ground(4, 3)
	_check(not flora.plants_near(meadow, 0.5).is_empty(), "the meadow's own grass grows at the mown spot")
	await _play([
		{"op": "paint", "tool": "flowers", "points": [[-4, 3], [-3.5, 3]], "radius": 1.0, "seconds": 0.5},
		{"op": "erase", "points": [[-4, 3], [4, 3]], "height": 6, "seconds": 0.6},
	])
	var left := flora.plants_near(Terrain.ground(-3.75, 3), 0.5)
	_check(left.is_empty(), "a held sweep mows the painted flowers: %d left" % left.size())
	left = flora.plants_near(meadow, 0.5)
	_check(left.is_empty(), "and the meadow's own grass and flowers: %d left" % left.size())
	_check(not flora.plants_near(Terrain.ground(4, 6), 0.5).is_empty(), "beyond the ring the meadow stands")
	await _play([{"op": "press", "button": "dpad_down"}])
	_check(not flora.plants_near(meadow, 0.5).is_empty(), "undo stands the mown meadow back up")
	await _play([{"op": "press", "button": "dpad_up"}])
	_check(flora.plants_near(meadow, 0.5).is_empty(), "redo mows it again")


func _spawned(pool: Flora.Pool) -> Array:
	for parts in flora.solids():
		if parts[0].pool == pool and parts[0].slot < pool.kept and _struck(parts):
			return parts
	return []


func _standing(parts: Array) -> bool:
	return parts.any(func(p: Flora.Plant) -> bool: return p.shown())


func _centre(parts: Array) -> Vector3:
	var top: Flora.Plant = parts[-1]
	return top.xform.origin + Vector3.UP * Terrain.base_at(top.anchor.x, top.anchor.z)


## A player's hand at head height, a few metres from the solid towards the glade's centre.
func _eye(parts: Array) -> Vector3:
	var a: Vector3 = parts[0].anchor
	var toward := Vector3(-a.x, 0, -a.z).normalized()
	return Terrain.ground(a.x + toward.x * 3.0, a.z + toward.z * 3.0) + Vector3.UP * 1.6


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _play(steps: Array) -> void:
	var d := Driver.new(main, steps)
	main.add_child(d)
	await d.finished
	d.queue_free()
