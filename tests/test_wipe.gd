extends SceneTree

## Headless checks of wiping the garden: the delete tool held at the sky empties every layer in one step, undo
## brings back the garden as it was kept, and only the host may wipe: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_wipe.gd

var failures := 0
var main: Node
var world: World
var dir := ""


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	dir = OS.get_temp_dir().path_join("nestcombe-wipe-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dir)
	world.load_from(dir.path_join("garden.save"))
	await _build()
	await _letting_go_early_wipes_nothing()
	await _a_wipe_empties_every_layer_and_undo_brings_it_all_back()
	_a_visitor_cannot_wipe()
	_a_wipe_someone_built_on_stays()
	await _settled()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
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
	await process_frame
	await process_frame
	world.flush()


## What the garden shows, whatever its sequence number.
func _picture() -> String:
	var d := world.digest()
	d.erase("seq")
	return var_to_str(d)


## The kept garden without its sequence numbers, which go on counting through a wipe and its undo.
func _kept() -> PackedByteArray:
	var snap: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(world.save_path))
	for c: Dictionary in snap.cmds:
		c.erase("seq")
	snap.erase("seq")
	return var_to_bytes(snap)


func _build() -> void:
	await _play([
		{"op": "place", "x": 0, "z": 8},
		{"op": "wall", "points": [[-6, -2], [-1, -3]], "seconds": 0.3},
		{"op": "tree", "x": -6, "z": 4},
		{"op": "paint", "tool": "flowers", "points": [[6, 4], [7, 4]], "radius": 1.0, "seconds": 0.3},
		{"op": "pave", "points": [[3.5, -6], [3.5, 1]], "radius": 0.8, "seconds": 0.3},
		{"op": "paint", "tool": "stone", "points": [[-9, 6], [-6, 6]], "radius": 1.5, "seconds": 0.3},
		{"op": "sculpt", "x": -12, "z": 2, "lift": 1.5, "radius": 3, "seconds": 0.3},
		{"op": "dig", "x": 12, "z": 10, "seconds": 1.0},
		{"op": "colour", "hand": "left", "element": "roof", "swatch": 3, "seconds": 0.3},
		{"op": "delete", "x": 30, "z": 0},
	])
	await _settled()
	var s := world.state
	_check(s.walls.size() == 1 and s.paths.size() == 1 and s.grounds.size() == 1 and s.groups.size() == 3 and s.ponds.size() == 1 and world.sculpted, "the garden holds a wall, a path, stone, a tree, flowers, shaped ground and a pond: %s" % [s.keys().map(func(k: String) -> int: return s[k].size())])


func _letting_go_early_wipes_nothing() -> void:
	var seq := world.seq
	var picture := _picture()
	await _play([{"op": "wipe", "seconds": 1.5}])
	_check(world.seq == seq and _picture() == picture, "letting go before the charge is full wipes nothing")
	await _play([{"op": "wipe", "seconds": 3.0, "dir": [0, -1, -1]}])
	_check(world.seq == seq and _picture() == picture, "nor does holding the trigger at the ground")
	_check(not main.delete_tool.busy(), "and no charge is left behind")


func _a_wipe_empties_every_layer_and_undo_brings_it_all_back() -> void:
	var before := _kept()
	var picture := _picture()
	var season := world.palette.season
	var seq := world.seq
	await _play([{"op": "wipe", "seconds": 2.5}])
	await _settled()
	_check(world.seq == seq + 1, "a full charge wipes in one command")
	var s := world.state
	_check(s.walls.is_empty() and main.tool.walls.is_empty(), "no walls stand")
	_check(s.paths.is_empty() and s.grounds.is_empty(), "no paths or stone are laid")
	_check(Ground.laid.get_data().count(0) == Ground.laid.get_data().size(), "and the ground shows no wear from them")
	_check(s.groups.keys() == [0], "no planted groups are left")
	_check(s.ponds.is_empty() and main.water.ponds.is_empty(), "no ponds hold water")
	_check(not world.sculpted and Terrain.read(Terrain.ALL) == Terrain.base_heights(), "the ground lies as it first did")
	var flora: Flora = main.flora_tool.flora
	var meadow: Array = flora.groups[0]
	_check(meadow.all(func(p: Flora.Plant) -> bool: return p.shown() == (p.pool == flora.grass)), "of the meadow's own plants only its grass stands")
	_check(flora.grass.size() == flora.grass.kept and flora.flowers.size() == flora.flowers.kept and flora.trunks.size() == flora.trunks.kept, "and nothing painted or planted")
	_check(world.palette.season == season, "the garden keeps its season")
	var wiped := _picture()
	await _play([{"op": "press", "button": "dpad_down"}])
	await _settled()
	_check(world.seq == seq + 2 and _picture() == picture, "one undo brings the whole garden back")
	_check(_kept() == before, "and keeps it exactly as it was kept before the wipe")
	await _play([{"op": "press", "button": "A"}])
	await _settled()
	_check(_picture() == wiped, "redo wipes it again")
	world.restore({"seq": 0, "cmds": []})
	world.load_from(world.save_path)
	_check(_picture() == wiped, "the wiped garden is kept and loads back bare")


func _a_visitor_cannot_wipe() -> void:
	world._order({"op": "plant", "kind": "tree", "seed": 4, "at": Terrain.ground(-8, 6)}, 1)
	var seq := world.seq
	var picture := _picture()
	world._order({"op": "wipe"}, 2)
	_check(world.seq == seq and _picture() == picture, "the host turns down a visitor's wipe")


func _a_wipe_someone_built_on_stays() -> void:
	world._order({"op": "wipe"}, 1)
	var wall := _wall(2)
	var seq := world.seq
	world._order({"op": "undo"}, 1)
	_check(world.seq == seq and world.state.walls.keys() == [wall], "the host's undo leaves a wipe a visitor has since built on, and every step of theirs before it")
	world._order({"op": "undo"}, 2)
	_check(world.state.walls.is_empty(), "while the visitor still takes back their own wall")


func _wall(by: int) -> int:
	world._order({"op": "wall", "walls": [{"points": PackedVector3Array([Terrain.ground(0, -5), Terrain.ground(4, -5)]), "height": 2.6, "arches": PackedFloat32Array(), "seed": 3, "closed": false, "top": 0, "fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "rise": 0.0, "plaster": false, "gable_end": 0, "timber_style": 0, "storey_floors": false, "on": PackedInt32Array(), "paint": Palette.plain()}]}, by)
	return world.seq * Commands.MAX_PIECES
