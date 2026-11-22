extends "res://../tests/support/booted.gd"

var world: World
var dir := ""


func _run() -> void:
	await process_frame
	main.world.limit = INF
	await process_frame
	world = main.world
	dir = OS.get_user_data_dir().path_join("cairnfold-keep-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	check(world.save_path == "", "a test or scripted run keeps no garden unless told to")
	await _every_edit_is_kept_and_loads_whole()
	await _a_burst_of_edits_is_kept_together()
	await _a_flat_roof_is_kept()
	await _a_placed_bush_counts_and_is_kept()
	await _a_visited_garden_is_not_kept()
	_an_unreadable_file_starts_the_meadow()
	_a_garden_of_another_format_is_moved_aside()
	_a_format_keeps_what_its_numbers_mean()
	_a_file_that_cannot_be_moved_aside_is_never_written_over()
	await _a_garden_read_in_part_is_moved_aside()
	_a_garden_saved_with_this_meadow_loads()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	finish()


func _picture() -> String:
	return var_to_str(world.digest())


func _every_edit_is_kept_and_loads_whole() -> void:
	var path := dir.path_join("garden.save")
	world.load_from(path)
	check(not FileAccess.file_exists(path), "with nothing kept yet, the meadow starts empty and nothing is written")
	await play([{"op": "wall", "points": [[-6, -4], [6, -4]], "seconds": 0.3}])
	await flushed()
	check(FileAccess.file_exists(path), "the first edit is kept")
	var after_wall := FileAccess.get_file_as_bytes(path)
	await play([
		{"op": "tree", "x": 4, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[-4, 4], [-3, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "pave", "points": [[0, 2], [0, -8]], "radius": 1.5, "seconds": 0.3},
		{"op": "erase", "points": [[3, -4], [5, -4]], "seconds": 0.2},
		{"op": "sculpt", "x": 10, "z": 10, "lift": 1.5, "seconds": 0.3},
	])
	await flushed()
	check(FileAccess.get_file_as_bytes(path) != after_wall, "each later edit rewrites it")
	check(not FileAccess.file_exists(path + ".new"), "and leaves no half-written file")
	var picture := _picture()
	var walls: Dictionary = world.state.walls
	check(walls.size() == 1 and not walls.values()[0].ruins.is_empty() and world.state.paths.size() == 1 and world.sculpted, "the garden holds a ruined wall, a path and shaped ground")
	world.restore({"seq": 0, "cmds": []})
	await flushed()
	check(_picture() != picture, "an empty garden looks different")
	world.load_from(path)
	check(_picture() == picture, "loading rebuilds every wall, ruin, plant, path and height")
	var seq := world.seq
	await play([{"op": "tree", "x": -8, "z": 8}])
	world.settle()
	check(world.seq == seq + 1 and world.state.groups.has(world.seq), "commands go on numbering from the loaded garden")


## A keep copies the whole garden in its frame, so edits within World.KEEP_EVERY of the last keep are kept together.
func _a_burst_of_edits_is_kept_together() -> void:
	var path := dir.path_join("garden.save")
	await flushed()
	var before := FileAccess.get_file_as_bytes(path)
	var burst := []
	for i in 6:
		burst.append_array([{"op": "tree", "x": -6 + 2 * i, "z": 12}, {"op": "wait", "seconds": 0.1}])
	await play(burst)
	_landed()
	check(FileAccess.get_file_as_bytes(path) == before, "edits in a burst are not kept one by one")
	await frames(ceili(World.KEEP_EVERY * 60))
	_landed()
	check(FileAccess.get_file_as_bytes(path) == var_to_bytes(world.snapshot()), "but together, once the burst has waited its turn")


## Waits on a save in flight; never writes one still due.
func _landed() -> void:
	if world._keep_task >= 0:
		WorkerThreadPool.wait_for_task_completion(world._keep_task)
		world._keep_task = -1


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
	await flushed()
	var picture := _picture()
	world.restore({"seq": 0, "cmds": []})
	await flushed()
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
	await flushed()
	var flora: Flora = main.flora_tool.flora
	var before := world.units.duplicate()
	await play([{"op": "bush", "x": 3, "z": -6}, {"op": "bush", "x": 5, "z": -6}])
	await flushed()
	check(flora.placed("bush").size() == 2, "two placed bushes stand: %d" % flora.placed("bush").size())
	check(world.units.get("bush", 0) == before.get("bush", 0) + 2, "each counts one bush: %s" % world.units)
	check(Budget.cost_ms(world.units) - Budget.cost_ms(before) > 0.0, "and costs the frame")
	var picture := _picture()
	world.restore({"seq": 0, "cmds": []})
	await flushed()
	check(flora.placed("bush").is_empty(), "an empty garden has no placed bushes")
	world.load_from(path)
	await flushed()
	check(flora.placed("bush").size() == 2 and _picture() == picture, "loading grows the kept bushes where they stood")
	await play([{"op": "delete", "x": 3, "z": -6, "height": 2.0}])
	await flushed()
	check(flora.placed("bush").size() == 1 and world.units.get("bush", 0) == before.get("bush", 0) + 1, "deleting a bush frees what it counted: %s" % world.units)


func _a_visited_garden_is_not_kept() -> void:
	var path := dir.path_join("garden.save")
	await flushed()
	var home := FileAccess.get_file_as_bytes(path)
	var real := main.multiplayer.multiplayer_peer
	var client := ENetMultiplayerPeer.new()
	client.create_client("127.0.0.1", 9)
	main.multiplayer.multiplayer_peer = client
	world.restore({"seq": 0, "cmds": [{"op": "plant", "kind": "tree", "seed": 1, "at": main.world.terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}]})
	await flushed()
	check(FileAccess.get_file_as_bytes(path) == home, "a garden we visit is not written over our own")
	var token := world._next_token + 1
	world.undo()
	check(world._sent.has(token), "a visitor's undo is proposed to the host")
	world._sent.erase(token)
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
	var tree := {"op": "plant", "kind": "tree", "seed": 1, "at": main.world.terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}
	var bytes := var_to_bytes({"format": World.FORMAT - 1, "seq": 9, "cmds": [tree]})
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
	world.restore({"seq": 0, "cmds": []})
	world.load_from(path)
	check(world.state.groups.keys() == [0], "a garden saved in another format grows nothing")
	check(FileAccess.get_file_as_bytes(path + ".bad") == bytes and not FileAccess.file_exists(path), "and is moved aside whole")
	world.save_path = ""
	var unordered := var_to_bytes({"format": world.format(), "cmds": [tree]})
	FileAccess.open(path, FileAccess.WRITE).store_buffer(unordered)
	world.load_from(path)
	check(world.state.groups.keys() == [0] and FileAccess.get_file_as_bytes(path + ".bad") == unordered and not FileAccess.file_exists(path), "a garden with no sequence number grows nothing and is moved aside")
	world.save_path = ""


func _a_format_keeps_what_its_numbers_mean() -> void:
	var name := func(entry: Dictionary) -> String: return entry.name
	var format := 12
	var held := {
		"WallLayout.Top": [WallLayout.Top, ["CRENEL", "CAP", "COPE", "RAIL"]],
		"WallLayout.Finish": [WallLayout.Finish, ["BARE", "PLASTER", "TIMBER", "BOARDS_ACROSS", "BOARDS_UPRIGHT"]],
		"WallLayout.Foundation": [WallLayout.Foundation, ["STONE", "PLASTER", "PILLARS", "POSTS"]],
		"WallLayout.GableEnd": [WallLayout.GableEnd, ["WALL", "BOARDS", "STEPS"]],
		"WallLayout.Family": [WallLayout.Family, ["COTTAGE", "ARCHWAY", "ARCHED", "SLIT", "ROUND", "CORNER"]],
		"RoofLayout.Kind": [RoofLayout.Kind, ["GABLE", "CONE"]],
		"RoofLayout.Deck": [RoofLayout.Deck, ["STONE", "WOOD"]],
		"PathLayout.Surface": [PathLayout.Surface, ["DIRT", "SAND", "COBBLES", "FLAGS", "BED"]],
		"FloraLayout.Species": [FloraLayout.Species, ["OAK", "FIR", "POPLAR", "BIRCH", "BEECH"]],
		"Ground.Kind": [Ground.Kind, ["MEADOW", "EARTH", "STONE", "SAND"]],
		"Palette.Element": [Palette.Element, ["MEADOW", "STONE", "ROOF", "WOOD", "PLASTER", "TIMBER", "THATCH", "GLOW", "LANTERN"]],
		"Brushwork.Medium": [Brushwork.Medium, ["WATER", "OIL", "CHARCOAL", "SMEAR"]],
		"Brushwork.Brush": [Brushwork.Brush, ["SMALL", "BIG", "FLAT", "STICK", "THIN_STICK", "THICK_STICK"]],
		"DecorationLayout.STYLES": [DecorationLayout.STYLES.map(name), ["Present", "Planter", "Bench", "Rain barrel", "Woodpile", "Steps", "Gatepost lantern", "Standing torch", "Campfire", "Chair", "Table", "Settle", "Bed", "Shelf", "Rug", "Stool", "Chest", "Potted plant", "Candle stand", "Table and chairs", "Garden bench", "Trough planter", "Parasol", "String lights", "Lantern", "Lamp post", "Crates", "Market stall", "Anvil", "Flower box", "Carved pumpkin", "Bird nest", "Lantern string", "Flag string"]],
		"StoneStyles.STYLES": [StoneStyles.STYLES.map(name), ["mossy", "river cobble"]],
		"Palette.SEASONS": [Palette.SEASONS.map(name), ["spring", "summer", "late summer", "autumn", "winter"]],
		"Palette.SWATCHES": [Palette.Element.values().map(Palette.count), [5, 7, 8, 7, 6, 6, 6, 8, 24]],
	}
	check(World.FORMAT == format, "the lists a garden's numbers index are frozen here as format %d's: freeze them again as they stand and name the new format here" % format)
	check(Commands.MAX_PIECES == 8, "a format %d garden's wall ids are its commands' numbers times eight, so another stride takes a new World.FORMAT" % format)
	for table: String in held:
		var now: Variant = held[table][0]
		check(not now is Dictionary or now.values() == range(now.size()), "%s numbers its members from zero in the order written" % table)
		var names: Array = now.keys() if now is Dictionary else now
		check(names == held[table][1], "a format %d garden holds %s by number: a moved or dropped entry takes a new World.FORMAT, and any change this list: %s" % [format, table, names])
	var bounded := RegEx.create_from_string("\\b((?:[A-Z][A-Za-z]*\\.)?[A-Z][A-Za-z_]*)\\.size\\(\\)")
	for source: String in ["Commands", "Brushwork"]:
		for found in bounded.search_all(FileAccess.get_file_as_string("res://src/%s.gd" % source.to_lower())):
			var table := found.get_string(1) if "." in found.get_string(1) else "%s.%s" % [source, found.get_string(1)]
			check(held.has(table), "%s bounds a number a garden holds by %s, which no list here freezes" % [source, table])


func _a_file_that_cannot_be_moved_aside_is_never_written_over() -> void:
	var path := dir.path_join("stuck.save")
	FileAccess.open(path, FileAccess.WRITE).store_string("not a garden")
	DirAccess.make_dir_recursive_absolute(path + ".bad/taken")
	world.load_from(path)
	check(world.save_path == "", "a garden file that cannot be moved aside is never saved over")
	DirAccess.remove_absolute(path + ".bad/taken")
	DirAccess.remove_absolute(path + ".bad")


func _a_garden_read_in_part_is_moved_aside() -> void:
	var path := dir.path_join("part.save")
	var tree := {"op": "plant", "kind": "tree", "seed": 1, "at": main.world.terrain.ground(2, 2), "id": 5, "seq": 0, "by": 1}
	var odd := {"op": "wall", "ids": PackedInt32Array([8]), "walls": [{"points": "not points"}], "seq": 0, "by": 1}
	var bytes := var_to_bytes({"format": world.format(), "seq": 9, "cmds": [tree, odd]})
	FileAccess.open(path, FileAccess.WRITE).store_buffer(bytes)
	world.load_from(path)
	await flushed()
	check(world.state.groups.has(5) and world.state.walls.is_empty(), "what can be read of a garden loads")
	check(FileAccess.get_file_as_bytes(path + ".bad") == bytes, "and the file as it was is moved aside before the garden is saved again")
	check(FileAccess.file_exists(path), "the part that loaded is saved in its place")
	world.save_path = ""


func _a_garden_saved_with_this_meadow_loads() -> void:
	var kept: Dictionary = str_to_var(FileAccess.get_file_as_string("res://../tests/support/meadow.garden"))
	check(world.restore_whole(kept), "tests/support/meadow.garden, format %s, loads whole in this build's format %s" % [kept.format, world.format()])
	check(world.state.groups[0].hidden.keys() == [3, 40], "and hides the meadow's plants it names")
	world.restore({"seq": 0, "cmds": []})
