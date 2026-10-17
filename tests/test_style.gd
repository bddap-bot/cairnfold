extends SceneTree

## Headless checks of the style tool's plaster faces and tree species, through the host as a player's turn of the
## wheel goes: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_style.gd

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
	_species_differ()
	_old_save_loads_as_plaster()
	_faces_turn_to_plaster()
	_timber_faces()
	_trees_take_a_species()
	_meadow_trees_take_a_species()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## A cleaned command as the host would send it on, checked again as a peer checks it.
func _relayed(cmd: Dictionary, by: int) -> Dictionary:
	var hosted := Commands.clean(cmd, world.state, false)
	hosted.seq = world.seq + 1
	hosted.by = by
	return Commands.clean(hosted, world.state, true)


func _turn(target: Dictionary, steps: int) -> void:
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, target)
	picker.twist(main.rig.right, Palette.TWIST_STEP * steps)
	picker.close(main.rig.right)


## Each species stands apart from the others in the shape of its crown and in its leaves.
func _species_differ() -> void:
	var looks := []
	for species in FloraLayout.Species.values():
		var t := FloraLayout.tree(Vector3.ZERO, 5, species)
		_check(t.blobs.size() == FloraLayout.BLOBS, "every species grows BLOBS blobs")
		var box := AABB(t.blobs[0][0].origin, Vector3.ZERO)
		var green := Color(0, 0, 0)
		for b in t.blobs:
			box = box.merge(b[0] * AABB(-Vector3.ONE * 0.5, Vector3.ONE))
			green += b[1] / t.blobs.size()
		_check(box.position.y > 0.5, "%s: its foliage stands off the ground" % FloraLayout.Species.keys()[species])
		looks.append([box.size.y / box.size.x, green, box.size.y])
	for a in looks.size():
		for b in range(a + 1, looks.size()):
			var shape: float = absf(looks[a][0] - looks[b][0]) + absf(looks[a][2] - looks[b][2]) * 0.2
			var hue := Vector3(looks[a][1].r - looks[b][1].r, looks[a][1].g - looks[b][1].g, looks[a][1].b - looks[b][1].b).length()
			_check(shape > 0.25 and hue > 0.05, "%s and %s differ in silhouette (%.2f) and leaf colour (%.2f)" % [FloraLayout.Species.keys()[a], FloraLayout.Species.keys()[b], shape, hue])


## A garden saved by the build that laid plaster with its own wall and house tools loads with them plaster, and the
## style tool reads their faces as plaster.
func _old_save_loads_as_plaster() -> void:
	var path := "user://plaster-before-style.save"
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://").path_join("../tests/saves/plaster-before-style.save"), ProjectSettings.globalize_path(path))
	world.load_from(path)
	world.save_path = ""
	var plastered := 0
	var stone := 0
	for w: Wall in main.tool.walls:
		if w.layout.plaster:
			plastered += 1
			var picker: PaletteTool = main.palette_tool
			picker.open(main.rig.right, picker.style_target(PaletteTool.Restyle.FACE, w, Vector3.ZERO, 0.5))
			_check(picker.wheels[main.rig.right].start == (PaletteTool.Face.ALSACE if TimberFrame.applies(w.layout) else PaletteTool.Face.PLASTER), "the style tool reads an old plaster house as Alsace and an open wall as plaster")
			picker.close(main.rig.right)
		else:
			stone += 1
	_check(plastered == 2 and stone == 1, "the old save's plaster wall and plaster house load as plaster, its stone wall as stone: %d, %d" % [plastered, stone])
	world.restore({"seq": 0, "cmds": []})


## The style tool turns a stone face to plaster through the host, which a peer takes, an undo puts back, a redo
## brings again and a save carries; the walls laid after are plaster too.
func _faces_turn_to_plaster() -> void:
	world._order({"op": "wall", "walls": [_wall_data(PackedVector3Array([Terrain.ground(-30, 20), Terrain.ground(-24, 20)]))]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var target: Dictionary = main.palette_tool.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO, 3.0)
	_check(target.count == 4, "a face offers stone and plaster, each plain or arched")
	var relayed := _relayed({"op": "reshape", "id": id, "data": {"plaster": true}}, 2)
	_check(relayed.get("data", {}).get("plaster") == true, "a peer takes the host's turn of a face to plaster: %s" % relayed)
	_turn(target, PaletteTool.Face.PLASTER)
	_check(world.state.walls[id].plaster and main.tool.find(id).layout.plaster, "two twists of the style tool turn the face to plaster")
	main.tool.find(id).lay_now()
	_check(main.tool.find(id).layout.stones.any(func(s): return s.kind == "plaster"), "and it is laid in plaster panels")
	_check(main.tool.plaster, "walls laid after are plaster")
	world._order({"op": "undo"}, world.me())
	_check(not world.state.walls[id].plaster and not main.tool.find(id).layout.plaster, "an undo puts the stone back")
	world._order({"op": "redo"}, world.me())
	_check(world.state.walls[id].plaster, "a redo brings the plaster again")
	world.restore(world.snapshot())
	_check(main.tool.find(id).layout.plaster, "a save carries it")
	_turn(main.palette_tool.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO, 3.0), -2)
	_check(not world.state.walls[id].plaster and not main.tool.plaster, "two twists back turn it, and the walls after, to stone")
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, picker.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO, 3.0))
	picker.twist(main.rig.right, Palette.TWIST_STEP * PaletteTool.Face.STONE_ARCHED)
	picker.wheels[main.rig.right].target.wall.lay_now()
	picker.twist(main.rig.right, Palette.TWIST_STEP * PaletteTool.Face.PLASTER_ARCHED)
	picker.close(main.rig.right)
	_check(world.state.walls[id].plaster and world.state.walls[id].arches.size() == 1, "an arch shown on the way stands in the way of none: the face turns plaster, arched: %s" % world.state.walls[id].arches)
	world.restore({"seq": 0, "cmds": []})


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return {"points": points, "height": 2.6, "arches": PackedFloat32Array(), "seed": 3, "closed": false, "top": 0, "fence": false, "windows": PackedVector2Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "on": PackedInt32Array(), "paint": Palette.plain()}


## A planted tree grows an oak; the style tool aimed at it offers each species and turns it to one through the host,
## which a peer takes; an undo, a redo and a save follow it, and its slots are laid as that species.
func _trees_take_a_species() -> void:
	var flora: Flora = main.flora_tool.flora
	var at := Terrain.ground(-6, 18)
	world._order({"op": "plant", "kind": "tree", "seed": 7, "at": at}, world.me())
	var g := world.seq
	var trunk: Flora.Plant = flora.groups[g][0]
	_check(flora.species_of(trunk) == FloraLayout.Species.OAK, "a planted tree is an oak")
	var crown: Vector3 = flora.groups[g][1].xform.origin + Vector3.UP * Terrain.base_at(at.x, at.z)
	var target: Dictionary = main.palette_tool.aim_style(crown + Vector3(0, 1, 8), (crown - (crown + Vector3(0, 1, 8))).normalized())
	_check(target.get("restyle") == PaletteTool.Restyle.TREE and target.get("tree") == trunk and target.count == FloraLayout.Species.size(), "the style tool aimed at a tree offers its species: %s" % [target.get("restyle")])
	var models := ToolModels.style(PaletteTool.Restyle.TREE, FloraLayout.Species.FIR, false)
	_check(models.get_child_count() == 2, "each species has its miniature")
	models.free()
	var relayed := _relayed({"op": "species", "group": g, "index": 0, "species": FloraLayout.Species.BIRCH}, 2)
	_check(relayed.get("species") == FloraLayout.Species.BIRCH and relayed.get("group") == g, "a peer takes the host's species: %s" % relayed)
	_check(Commands.clean({"op": "species", "group": g, "index": 1, "species": 1}, world.state, false).is_empty(), "only a tree's trunk names it")
	_check(Commands.clean({"op": "species", "group": g, "index": 0, "species": FloraLayout.Species.size()}, world.state, false).is_empty(), "no species past the last")
	var oak_top: float = flora.groups[g][1].xform.origin.y
	_turn(target, FloraLayout.Species.POPLAR)
	_check(world.state.groups[g].species.get(0) == FloraLayout.Species.POPLAR and flora.species_of(trunk) == FloraLayout.Species.POPLAR, "a twist of the wheel turns the tree a poplar")
	_check(flora.groups[g][-1].xform.origin.y > oak_top + 1.0, "and it grows tall as one")
	_check(flora.trunks.size() == flora.trunks.kept + 1, "in the slots it held")
	world._order({"op": "undo"}, world.me())
	_check(flora.species_of(trunk) == FloraLayout.Species.OAK and world.state.groups[g].species.is_empty(), "an undo makes it an oak again")
	_check(is_equal_approx(flora.groups[g][1].xform.origin.y, oak_top), "the same oak")
	world._order({"op": "redo"}, world.me())
	_check(flora.species_of(trunk) == FloraLayout.Species.POPLAR, "a redo makes it a poplar again")
	var picture := var_to_str(world.digest())
	world.restore(world.snapshot())
	_check(var_to_str(world.digest()) == picture and flora.species_of(flora.groups[g][0]) == FloraLayout.Species.POPLAR, "a save carries it")
	world.restore({"seq": 0, "cmds": []})


## The meadow's own trees take a species as planted ones do, and go back to oaks with a swapped garden.
func _meadow_trees_take_a_species() -> void:
	var flora: Flora = main.flora_tool.flora
	var i: int = flora.meadow_trees()[3]
	var trunk: Flora.Plant = flora.groups[0][i]
	world._order({"op": "species", "group": 0, "index": i, "species": FloraLayout.Species.BEECH}, 2)
	_check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "a meadow tree turns a copper beech")
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	_check(flora.species_of(trunk) == FloraLayout.Species.OAK, "an empty garden has it an oak again")
	world.restore(snap)
	_check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "and its save a beech")
	world._order({"op": "species", "group": 0, "index": i, "species": FloraLayout.Species.FIR}, 2)
	world._order({"op": "undo"}, 2)
	_check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "an undo goes back one species")
	world.restore({"seq": 0, "cmds": []})


func _timber_faces() -> void:
	var data := _wall_data(PackedVector3Array(WallLayout.rectangle(Vector3(-20, 0, 10), Vector3(-13, 0, 10), 5)))
	data.closed = true
	world._order({"op": "wall", "walls": [data]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var wall: Wall = main.tool.find(id)
	wall.lay_now()
	var picker: PaletteTool = main.palette_tool
	for style in TimberFrame.PATTERNS.size():
		var target := picker.style_target(PaletteTool.Restyle.FACE, wall, Vector3.ZERO, 2.0)
		_check(target.count == 9, "house face wheel includes the five timber patterns")
		picker.open(main.rig.right, target)
		var start: int = picker.wheels[main.rig.right].start
		picker.twist(main.rig.right, (PaletteTool.Face.ALSACE + style - start) * Palette.TWIST_STEP)
		picker.close(main.rig.right)
		_check(world.state.walls[id].plaster and world.state.walls[id].timber_style == style, "face wheel commits timber pattern %d" % style)
		wall.lay_now()
		_check(wall.layout.stones.any(func(p): return p.kind == "timber"), "selected timber face is rendered")
	world._order({"op": "undo"}, world.me())
	_check(world.state.walls[id].timber_style == 3, "undo restores the preceding timber face")
	world._order({"op": "redo"}, world.me())
	_check(world.state.walls[id].timber_style == 4, "redo restores the selected timber face")
	world.restore(world.snapshot())
	_check(world.state.walls[id].timber_style == 4, "save retains the pattern")
	world.restore({"seq": 0, "cmds": []})
