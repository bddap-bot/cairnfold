extends "res://../tests/support/suite.gd"

## Headless checks of keeping the garden: autosaved after every edit, loaded whole, and unreadable files
## reported: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_keep.gd

var world: World
var dir := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	await process_frame
	world = main.world
	dir = OS.get_user_data_dir().path_join("nestcombe-keep-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	check(world.save_path == "", "a test or scripted run keeps no garden unless told to")
	await _every_edit_is_kept_and_loads_whole()
	await _a_flat_roof_is_kept()
	await _a_placed_bush_counts_and_is_kept()
	await _a_visited_garden_is_not_kept()
	_an_unreadable_file_starts_the_meadow()
	_a_garden_of_another_format_is_moved_aside()
	await _a_garden_read_in_part_is_moved_aside()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	finish()


## Saves are written on a worker thread; this waits for the last one to land.
func _settled() -> void:
	await process_frame
	world.flush()


func _picture() -> String:
	return var_to_str(world.digest())


func _every_edit_is_kept_and_loads_whole() -> void:
	var path := dir.path_join("garden.save")
	world.load_from(path)
	check(not FileAccess.file_exists(path), "with nothing kept yet, the meadow starts empty and nothing is written")
	await play([{"op": "wall", "points": [[-6, -4], [6, -4]], "seconds": 0.3}])
	await _settled()
	check(FileAccess.file_exists(path), "the first edit is kept")
	var after_wall := FileAccess.get_file_as_bytes(path)
	await play([
		{"op": "tree", "x": 4, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[-4, 4], [-3, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "pave", "points": [[0, 2], [0, -8]], "radius": 1.5, "seconds": 0.3},
		{"op": "erase", "points": [[3, -4], [5, -4]], "seconds": 0.2},
		{"op": "sculpt", "x": 10, "z": 10, "lift": 1.5, "seconds": 0.3},
	])
	await _settled()
	check(FileAccess.get_file_as_bytes(path) != after_wall, "each later edit rewrites it")
	check(not FileAccess.file_exists(path + ".new"), "and leaves no half-written file")
	var picture := _picture()
	var walls: Dictionary = world.state.walls
	check(walls.size() == 1 and not walls.values()[0].ruins.is_empty() and world.state.paths.size() == 1 and world.sculpted, "the garden holds a ruined wall, a path and shaped ground")
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	check(_picture() != picture, "an empty garden looks different")
	world.load_from(path)
	check(_picture() == picture, "loading rebuilds every wall, ruin, plant, path and height")
	var seq := world.seq
	await play([{"op": "tree", "x": -8, "z": 8}, {"op": "wait", "seconds": 0.1}])
	check(world.seq == seq + 1 and world.state.groups.has(world.seq), "commands go on numbering from the loaded garden")


func _a_flat_roof_is_kept() -> void:
	var path := dir.path_join("garden.save")
	world.restore({"seq": 0, "cmds": []})
	await play([
		{"op": "house", "at": [5, 1], "size": [4, 2.5], "seconds": 0.3},
		{"op": "house", "at": [-4, -4], "size": [4, 2.5], "seconds": 0.3},
		{"op": "roof", "index": 0, "pitch": 0.2},
		{"op": "roof", "index": 1, "pitch": 0.0},
		{"op": "resize", "index": 0, "size": [4, 2.5], "rise": 0.9, "seconds": 0.2},
	])
	await _settled()
	var picture := _picture()
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	world.load_from(path)
	check(_picture() == picture, "a garden with flat roofs loads as it was kept")
	var flat: Array = world.state.walls.values().filter(func(w): return w.has("roof") and w.roof.pitch == 0.0)
	check(flat.size() == 2, "both roofs come back flat: %d" % flat.size())
	check(main.tool.walls.all(func(w): return w.roof == null or w.layout.cover == WallLayout.Cover.DECK), "and are laid as decks")
	var raised: Array = world.state.walls.values().filter(func(w): return is_equal_approx(w.get("rise", 0.0), 0.9))
	check(raised.size() == 1, "a house raised onto a plinth comes back raised: %d" % raised.size())


func _a_placed_bush_counts_and_is_kept() -> void:
	var path := dir.path_join("garden.save")
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	var flora: Flora = main.flora_tool.flora
	var before := world.units.duplicate()
	await play([{"op": "bush", "x": 3, "z": -6}, {"op": "bush", "x": 5, "z": -6}, {"op": "wait", "seconds": 0.1}])
	await _settled()
	check(flora.placed("bush").size() == 2, "two placed bushes stand: %d" % flora.placed("bush").size())
	check(world.units.get("bush", 0) == before.get("bush", 0) + 2, "each counts one bush: %s" % world.units)
	check(Budget.cost_ms(world.units) - Budget.cost_ms(before) > 0.0, "and costs the frame")
	var picture := _picture()
	world.restore({"seq": 0, "cmds": []})
	await _settled()
	check(flora.placed("bush").is_empty(), "an empty garden has no placed bushes")
	world.load_from(path)
	await _settled()
	check(flora.placed("bush").size() == 2 and _picture() == picture, "loading grows the kept bushes where they stood")
	await play([{"op": "delete", "x": 3, "z": -6, "height": 2.0}])
	await _settled()
	check(flora.placed("bush").size() == 1 and world.units.get("bush", 0) == before.get("bush", 0) + 1, "deleting a bush frees what it counted: %s" % world.units)


func _a_visited_garden_is_not_kept() -> void:
	var path := dir.path_join("garden.save")
	await _settled()
	var home := FileAccess.get_file_as_bytes(path)
	var real := main.multiplayer.multiplayer_peer
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", 9)
	main.multiplayer.multiplayer_peer = client
	world.restore({"seq": 0, "cmds": [{"op": "plant", "kind": "tree", "seed": 1, "at": Terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}]})
	await _settled()
	check(FileAccess.get_file_as_bytes(path) == home, "a garden we visit is not written over our own")
	client.close()
	main.multiplayer.multiplayer_peer = real


func _an_unreadable_file_starts_the_meadow() -> void:
	var path := dir.path_join("broken.save")
	FileAccess.open(path, FileAccess.WRITE).store_string("not a garden")
	world.restore({"seq": 0, "cmds": []})
	var empty := _picture()
	world.load_from(path)
	check(_picture() == empty, "a file holding no garden leaves the empty meadow")
	check(FileAccess.get_file_as_string(path + ".bad") == "not a garden" and not FileAccess.file_exists(path), "and is moved aside, not written over")
	world.save_path = ""


func _a_garden_of_another_format_is_moved_aside() -> void:
	var path := dir.path_join("old.save")
	var tree := {"op": "plant", "kind": "tree", "seed": 1, "at": Terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}
	var bytes := var_to_bytes({"format": World.FORMAT - 1, "seq": 9, "cmds": [tree]})
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
	world.restore({"seq": 0, "cmds": []})
	world.load_from(path)
	check(world.state.groups.keys() == [0], "a garden saved in another format grows nothing")
	check(FileAccess.get_file_as_bytes(path + ".bad") == bytes and not FileAccess.file_exists(path), "and is moved aside whole")
	world.save_path = ""


func _a_garden_read_in_part_is_moved_aside() -> void:
	var path := dir.path_join("part.save")
	var tree := {"op": "plant", "kind": "tree", "seed": 1, "at": Terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}
	var odd := {"op": "wall", "ids": PackedInt32Array([8]), "walls": [{"points": "not points"}], "seq": 0, "by": 1}
	var bytes := var_to_bytes({"format": World.FORMAT, "seq": 9, "cmds": [tree, odd]})
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
	world.load_from(path)
	await _settled()
	check(world.state.groups.has(5) and world.state.walls.is_empty(), "what can be read of a garden loads")
	check(FileAccess.get_file_as_bytes(path + ".bad") == bytes, "and the file as it was is moved aside before the garden is saved again")
	check(FileAccess.file_exists(path), "the part that loaded is saved in its place")
	world.save_path = ""
