extends SceneTree

## Headless checks of the style tool's plaster faces, tree species and painted stone's styles, through the host as a player's turn of the
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
	_roof_choices_keep_shape()
	_species_differ()
	_faces_turn_to_plaster()
	_floors_turn_to_every_storey()
	_faces_cut_no_opening()
	_timber_faces()
	_towers_keep_stone()
	_trees_take_a_species()
	_meadow_trees_take_a_species()
	_trees_grow_by_the_grip()
	_meadow_trees_grow()
	_stone_takes_a_style()
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


## The style tool turns a stone face to plaster through the host, which a peer takes, an undo puts back, a redo
## brings again and a save carries; the walls laid after are plaster too.
func _faces_turn_to_plaster() -> void:
	world._order({"op": "wall", "walls": [_wall_data(PackedVector3Array([Terrain.ground(-30, 20), Terrain.ground(-24, 20)]))]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var target: Dictionary = main.palette_tool.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO)
	_check(target.count == 2, "an open wall's face offers stone and plaster")
	var relayed := _relayed({"op": "reshape", "of": "walls", "id": id, "data": {"plaster": true}}, 2)
	_check(relayed.get("data", {}).get("plaster") == true, "a peer takes the host's turn of a face to plaster: %s" % relayed)
	_turn(target, PaletteTool.Face.PLASTER)
	_check(world.state.walls[id].plaster and main.tool.find(id).layout.plaster, "a twist of the style tool turns the face to plaster")
	main.tool.find(id).lay_now()
	_check(main.tool.find(id).layout.stones.any(func(s): return s.kind == "plaster"), "and it is laid in plaster panels")
	_check(main.tool.plaster, "walls laid after are plaster")
	world._order({"op": "undo"}, world.me())
	_check(not world.state.walls[id].plaster and not main.tool.find(id).layout.plaster, "an undo puts the stone back")
	world._order({"op": "redo"}, world.me())
	_check(world.state.walls[id].plaster, "a redo brings the plaster again")
	world.restore(world.snapshot())
	_check(main.tool.find(id).layout.plaster, "a save carries it")
	_turn(main.palette_tool.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO), -1)
	_check(not world.state.walls[id].plaster and not main.tool.plaster, "a twist back turns it, and the walls after, to stone")
	world.restore({"seq": 0, "cmds": []})


## The style tool aimed at a tall tower's floor floors it at every storey, on every machine, and towers laid after too.
func _floors_turn_to_every_storey() -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.circle(Terrain.ground(-12, 24), 1.7)))
	d.closed = true
	d.height = 4.5
	d.roof = {"kind": RoofLayout.Kind.CONE, "center": Terrain.ground(-12, 24), "radius": 1.7, "pitch": 2.7, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var w: Wall = main.tool.find(id)
	w.lay_now()
	_check(w.layout.floors.size() == 1, "a tower is floored at its foot: %s" % [w.layout.floors])
	var inside := Vector3(-12.3, w.layout.floors[0] + 1.6, 24.2)
	var target: Dictionary = main.palette_tool.aim_style(inside, Vector3(0.1, -1, -0.1).normalized())
	_check(target.get("restyle") == PaletteTool.Restyle.FLOOR and target.get("count") == 2, "the style tool aimed at the floor offers its floors: %s" % [target.get("restyle")])
	var relayed := _relayed({"op": "reshape", "of": "walls", "id": id, "data": {"storey_floors": true}}, 2)
	_check(relayed.get("data", {}).get("storey_floors") == true, "a peer takes the host's turn of a floor to every storey: %s" % relayed)
	_turn(target, 1)
	w.lay_now()
	_check(world.state.walls[id].storey_floors and w.layout.floors.size() == 2, "a twist floors it at every storey: %s" % [w.layout.floors])
	_check(main.tool.storey_floors, "towers laid after are floored at every storey")
	world._order({"op": "undo"}, world.me())
	w.lay_now()
	_check(not world.state.walls[id].storey_floors and w.layout.floors.size() == 1, "an undo takes the upper floor away")
	main.tool.storey_floors = false
	world.restore({"seq": 0, "cmds": []})


## The style tool only restyles: turned through every face of an open wall and of a house, shown and sent, it
## neither cuts an opening nor fills the arch standing.
func _faces_cut_no_opening() -> void:
	var open := _wall_data(PackedVector3Array([Terrain.ground(-30, 20), Terrain.ground(-22, 20)]))
	open.openings = PackedVector4Array([2.0].map(WallLayout.archway))
	var house := _wall_data(PackedVector3Array(WallLayout.rectangle(Vector3(-20, 0, 10), Vector3(-13, 0, 10), 5)))
	house.closed = true
	world._order({"op": "wall", "walls": [open, house]}, 1)
	var picker: PaletteTool = main.palette_tool
	_check(world.state.walls.size() == 2, "an open wall and a house stand")
	for id: int in world.state.walls:
		var before := PackedVector4Array(world.state.walls[id].openings)
		var wall: Wall = main.tool.find(id)
		for at in [0.5, 2.0, 5.0]:
			var target := picker.style_target(PaletteTool.Restyle.FACE, wall, wall.layout.point_at(at))
			for pick in target.count:
				picker.open(main.rig.right, target)
				picker.twist(main.rig.right, (pick - picker.wheels[main.rig.right].start) * Palette.TWIST_STEP)
				_check(PackedVector4Array(wall.layout.openings) == before, "face %d shown at %.1f m keeps the arches: %s" % [pick, at, wall.layout.openings])
				picker.close(main.rig.right)
				_check(PackedVector4Array(world.state.walls[id].openings) == before, "face %d sent at %.1f m keeps the arches: %s" % [pick, at, world.state.walls[id].openings])
	world.restore({"seq": 0, "cmds": []})


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return {"points": points, "height": 2.6, "seed": 3, "closed": false, "top": 0, "fence": false, "openings": PackedVector4Array(), "lanterns": PackedVector3Array(), "flags": PackedFloat32Array(), "ruins": PackedVector2Array(), "rise": 0.0, "plaster": false, "gable_end": 0, "timber_style": 0, "storey_floors": false, "on": PackedInt32Array(), "paint": Palette.plain()}


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
	var relayed := _relayed({"op": "tree", "group": g, "index": 0, "species": FloraLayout.Species.BIRCH}, 2)
	_check(relayed.get("species") == FloraLayout.Species.BIRCH and relayed.get("group") == g, "a peer takes the host's species: %s" % relayed)
	_check(Commands.clean({"op": "tree", "group": g, "index": 1, "species": 1}, world.state, false).is_empty(), "only a tree's trunk names it")
	_check(Commands.clean({"op": "tree", "group": g, "index": 0, "species": FloraLayout.Species.size()}, world.state, false).is_empty(), "no species past the last")
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
	world._order({"op": "tree", "group": 0, "index": i, "species": FloraLayout.Species.BEECH}, 2)
	_check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "a meadow tree turns a copper beech")
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	_check(flora.species_of(trunk) == FloraLayout.Species.OAK, "an empty garden has it an oak again")
	world.restore(snap)
	_check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "and its save a beech")
	world._order({"op": "tree", "group": 0, "index": i, "species": FloraLayout.Species.FIR}, 2)
	world._order({"op": "undo"}, 2)
	_check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "an undo goes back one species")
	world.restore({"seq": 0, "cmds": []})


## A grip on a planted tree raised grows it and lowered shrinks it, within FloraLayout.SCALES, through the host,
## which a peer takes; what it strikes, its shade and its share of the budget grow with it; an undo, a redo, a
## species and a snapshot keep it.
func _trees_grow_by_the_grip() -> void:
	var flora: Flora = main.flora_tool.flora
	var tool: WallTool = main.tool
	var at := Terrain.ground(-6, 18)
	world._order({"op": "plant", "kind": "tree", "seed": 7, "at": at}, world.me())
	var g := world.seq
	var trunk: Flora.Plant = flora.groups[g][0]
	var top := flora.top_of(trunk)
	var shade := flora.shade_of(flora.groups[g]).basis.get_scale()
	var trees: float = world.units.tree
	var m := tool.mason(main.rig.right)
	var grip := at + Vector3.UP * top * 0.8
	var hand := grip + Vector3.BACK * 2.0
	tool.begin_grow(m, trunk, Transform3D(Basis(), hand), grip)
	_check(tool.busy(main.rig.right), "a grip on a tree holds it")
	tool.drag_grow(m, hand.y + 1.5)
	var grown := flora.scale_of(trunk)
	_check(grown > 1.3 and absf(flora.top_of(trunk) - (top + 1.5 * Hand.reach_gain(2.0))) < 0.1, "its top follows the raised hand: %.2f, top %.2f from %.2f" % [grown, flora.top_of(trunk), top])
	_check(world.state.groups[g].scale.is_empty(), "shown here alone while held")
	tool.end_grow(m)
	_check(world.state.groups[g].scale.get(0) == grown and is_equal_approx(flora.scale_of(trunk), grown), "letting go sends it")
	_check(is_equal_approx(world.units.tree, trees - 1.0 + grown * grown), "it counts by its crown's ground: %.2f" % (world.units.tree - trees))
	_check(flora.shade_of(flora.groups[g]).basis.get_scale().is_equal_approx(shade * grown), "its shade grows with it")
	var high := at + Vector3(0, top * grown * 0.9, 6)
	_check(not flora.solid_hit(high, Vector3.FORWARD, 12.0).is_empty(), "and what strikes it, high on its new crown")
	var relayed := _relayed({"op": "tree", "group": g, "index": 0, "scale": 2.5}, 2)
	_check(relayed.get("scale") == 2.5 and not relayed.has("species"), "a peer takes the host's scale: %s" % relayed)
	for bad in [FloraLayout.SCALES.x - 0.01, FloraLayout.SCALES.y + 0.01, 2, NAN]:
		_check(Commands.clean({"op": "tree", "group": g, "index": 0, "scale": bad}, world.state, false).is_empty(), "no scale %s" % bad)
	_check(Commands.clean({"op": "tree", "group": g, "index": 0}, world.state, false).is_empty(), "a tree command changes something")
	tool.begin_grow(m, trunk, Transform3D(Basis(), hand), grip)
	tool.drag_grow(m, hand.y - 50.0)
	tool.end_grow(m)
	_check(is_equal_approx(flora.scale_of(trunk), FloraLayout.SCALES.x), "lowered all the way it shrinks to the least")
	world._order({"op": "undo"}, world.me())
	_check(is_equal_approx(flora.scale_of(trunk), grown), "an undo grows it back")
	world._order({"op": "undo"}, world.me())
	_check(flora.scale_of(trunk) == 1.0 and world.state.groups[g].scale.is_empty() and is_equal_approx(flora.top_of(trunk), top), "and another to the tree it was planted")
	_check(is_equal_approx(world.units.tree, trees), "costing what it did")
	world._order({"op": "redo"}, world.me())
	_check(is_equal_approx(flora.scale_of(trunk), grown), "a redo grows it again")
	var crown: Vector3 = flora.groups[g][1].xform.origin + Vector3.UP * Terrain.base_at(at.x, at.z)
	_turn(main.palette_tool.aim_style(crown + Vector3(0, 1, 12), (crown - (crown + Vector3(0, 1, 12))).normalized()), FloraLayout.Species.FIR)
	_check(flora.species_of(trunk) == FloraLayout.Species.FIR and is_equal_approx(flora.scale_of(trunk), grown), "a new species keeps its size")
	var picture := var_to_str(world.digest())
	world.restore(world.snapshot())
	trunk = flora.groups[g][0]
	_check(var_to_str(world.digest()) == picture and is_equal_approx(flora.scale_of(trunk), grown) and flora.species_of(trunk) == FloraLayout.Species.FIR, "a snapshot carries both")
	world.restore({"seq": 0, "cmds": []})


## The meadow's own trees grow as planted ones do, and go back to their size with a swapped garden.
func _meadow_trees_grow() -> void:
	var flora: Flora = main.flora_tool.flora
	var trunk: Flora.Plant = flora.groups[0][flora.meadow_trees()[2]]
	var top := flora.top_of(trunk)
	world._order({"op": "tree", "group": 0, "index": trunk.index, "scale": 2.0}, 2)
	_check(is_equal_approx(flora.top_of(trunk), top * 2.0), "a meadow tree grows twice as tall")
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	_check(flora.scale_of(trunk) == 1.0 and is_equal_approx(flora.top_of(trunk), top), "an empty garden has it as it grew")
	world.restore(snap)
	_check(flora.scale_of(trunk) == 2.0, "and its snapshot grown")
	world.restore({"seq": 0, "cmds": []})


func _timber_faces() -> void:
	var data := _wall_data(PackedVector3Array(WallLayout.rectangle(Vector3(-20, 0, 10), Vector3(-13, 0, 10), 5)))
	data.closed = true
	world._order({"op": "wall", "walls": [data]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var wall: Wall = main.tool.find(id)
	wall.lay_now()
	var picker: PaletteTool = main.palette_tool
	var target := picker.style_target(PaletteTool.Restyle.FACE, wall, Vector3.ZERO)
	_check(target.count == 3, "a house's face wheel offers stone, plaster and timber")
	picker.open(main.rig.right, target)
	var start: int = picker.wheels[main.rig.right].start
	picker.twist(main.rig.right, (PaletteTool.Face.TIMBER - start) * Palette.TWIST_STEP)
	picker.close(main.rig.right)
	_check(world.state.walls[id].plaster and world.state.walls[id].timber_style == 0, "face wheel commits timber")
	wall.lay_now()
	_check(wall.layout.stones.any(func(p): return p.kind == "timber"), "selected timber face is rendered")
	world._order({"op": "undo"}, world.me())
	_check(not world.state.walls[id].plaster, "undo restores stone")
	world._order({"op": "redo"}, world.me())
	_check(world.state.walls[id].timber_style == 0, "redo restores the selected timber face")
	world.restore(world.snapshot())
	_check(world.state.walls[id].timber_style == 0, "save retains the pattern")
	var saved := world.snapshot().duplicate(true)
	for previous in 5:
		for cmd in saved.cmds:
			if cmd.op == "wall":
				cmd.walls[0].timber_style = previous
		_check(world.restore(saved) == saved.cmds.size(), "existing timber house loads")
		_check(world.state.walls[id].timber_style == 0, "existing timber choice loads as Fachwerk")
	wall = main.tool.find(id)
	_turn(picker.style_target(PaletteTool.Restyle.FACE, wall, Vector3.ZERO), -1)
	wall.lay_now()
	_check(world.state.walls[id].plaster and world.state.walls[id].timber_style == -1, "plain plaster remains selectable on houses")
	_check(wall.layout.stones.all(func(p): return p.kind != "timber"), "plain plaster has no framing")
	world.restore({"seq": 0, "cmds": []})


func _towers_keep_stone() -> void:
	main.tool.plaster = true
	main.tool.begin_house(Terrain.ground(-20, 10), 0.0, PackedInt32Array(), true)
	_check(not main.tool.house.layout.plaster, "new towers use stone even after choosing plaster on a house")
	var data: Dictionary = main.tool.house.data()
	main.tool.end_house()
	world.restore({"seq": 0, "cmds": []})
	data.plaster = true
	var snap := {"seq": 2, "cmds": [
		{"op": "wall", "walls": [data], "ids": PackedInt32Array([Commands.MAX_PIECES]), "seq": 1, "by": 1},
		{"op": "reshape", "of": "walls", "id": Commands.MAX_PIECES, "data": {"plaster": true}, "seq": 2, "by": 1},
	]}
	_check(world.restore(snap) == 2, "a saved plaster tower and its style edit both load")
	var id := Commands.MAX_PIECES
	var wall: Wall = main.tool.find(id)
	_check(not world.state.walls[id].plaster and not wall.layout.plaster, "saved plaster towers take the default stone")
	var picker: PaletteTool = main.palette_tool
	for style in [WallTool.RoofStyle.PITCHED, WallTool.RoofStyle.THATCHED, WallTool.RoofStyle.FLAT]:
		if style == WallTool.RoofStyle.FLAT:
			wall.lay_now()
			var mason := WallTool.Mason.new()
			var start: Vector3 = wall.roof.frame().mid + Vector3.UP * wall.roof.pitch
			main.tool.begin_roof(mason, wall, start)
			main.tool.drag_roof(mason, start - Vector3.UP * wall.roof.pitch / mason.lift_gain)
			main.tool.end_roof(mason)
		else:
			world._order({"op": "reshape", "of": "walls", "id": id, "data": WallTool.restyle_roof(world.state.walls[id], style)}, 1)
		_check(WallTool.roof_style(world.state.walls[id]) == style, "tower takes the tested roof style")
		wall.lay_now()
		_check(not wall.layout.stones.any(func(s): return s.kind == "plaster"), "tower geometry has no plaster panels")
		var target := picker.style_target(PaletteTool.Restyle.FACE, wall, Vector3.ZERO)
		_check(target.count == 1, "every tower roof style offers only stone walls")
		_turn(target, 1)
		_check(not world.state.walls[id].plaster, "turning the tower face wheel keeps stone")
	world.restore({"seq": 0, "cmds": []})


## Painted stone aimed at offers every style in StoneStyles' table and turns its stroke to one through the host, which a
## peer takes; the mask carries it where that stroke lies, stone painted after takes it, and an undo, a redo and a save
## follow it. A later stroke's style takes the ground it covers most.
func _stone_takes_a_style() -> void:
	var r := FloraTool.MAX_RADIUS * 0.4
	var stamps := PackedVector4Array([Vector4(30, 30, r, r * 2.0), Vector4(31.5, 30, r, r * 2.0)])
	_check(Commands.clean({"op": "ground", "kind": Ground.Kind.STONE, "stamps": stamps}, world.state, false).is_empty(), "stone names its style")
	_check(Commands.clean({"op": "ground", "kind": Ground.Kind.STONE, "stamps": stamps, "style": StoneStyles.STYLES.size()}, world.state, false).is_empty(), "no style past the last")
	world._order({"op": "ground", "kind": Ground.Kind.STONE, "stamps": stamps, "style": 0}, world.me())
	var id := world.seq
	Ground.settle()
	var at := Terrain.ground(30.5, 30)
	var target: Dictionary = main.palette_tool.aim_style(at + Vector3(0, 3, 3), Vector3(0, -3, -3).normalized())
	_check(target.get("restyle") == PaletteTool.Restyle.STONE and target.get("stroke") == id and target.get("count") == StoneStyles.STYLES.size(), "the style tool aimed at painted stone offers its styles: %s" % [target])
	_check(main.palette_tool.aim_style(Terrain.ground(-40, -40) + Vector3(0, 3, 3), Vector3(0, -3, -3).normalized()).is_empty(), "bare meadow has no style")
	for i in StoneStyles.STYLES.size():
		var model := ToolModels.style(PaletteTool.Restyle.STONE, i, false)
		_check(model.get_child_count() == 2, "%s has its miniature" % StoneStyles.STYLES[i].name)
		model.free()
	var relayed := _relayed({"op": "restone", "id": id, "style": 3}, 2)
	_check(relayed.get("style") == 3 and relayed.get("id") == id, "a peer takes the host's style: %s" % relayed)
	_check(Commands.clean({"op": "restone", "id": id + 100, "style": 1}, world.state, false).is_empty(), "only a standing stroke is restyled")
	_turn(target, 3)
	_check(world.state.grounds[id].style == 3 and _style_at(30.5, 30) == 3, "a twist of the wheel turns the stone the fourth style: %d" % _style_at(30.5, 30))
	_check(Ground.style == 3, "stone painted after takes it")
	world._order({"op": "undo"}, world.me())
	_check(world.state.grounds[id].style == 0 and _style_at(30.5, 30) == 0, "an undo puts the first style back")
	world._order({"op": "redo"}, world.me())
	_check(_style_at(30.5, 30) == 3, "a redo brings the fourth again")
	world.restore(world.snapshot())
	Ground.settle()
	_check(world.state.grounds[id].style == 3 and _style_at(30.5, 30) == 3, "a save carries it")
	world._order({"op": "ground", "kind": Ground.Kind.STONE, "stamps": PackedVector4Array([Vector4(33, 30, r, r * 2.0)]), "style": 1}, world.me())
	Ground.settle()
	_check(_style_at(33, 30) == 1 and _style_at(30, 30) == 3, "a later stroke's style takes what it covers most, the first keeps the rest: %d, %d" % [_style_at(33, 30), _style_at(30, 30)])
	Ground.style = 0
	world.restore({"seq": 0, "cmds": []})


func _style_at(x: float, z: float) -> int:
	return Ground._texel(x, z, Ground.laid).b8


func _roof_choices_keep_shape() -> void:
	var picker: PaletteTool = main.palette_tool
	for pitch in [0.0, 2.0]:
		for thatch in [false, true]:
			var data := _wall_data(PackedVector3Array(WallLayout.rectangle(Vector3(-20, 0, 10), Vector3(-13, 0, 10), 5)))
			data.closed = true
			data.roof = {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": pitch, "curve": 0.4, "seed": 3, "chimneys": PackedVector2Array(), "flag": false, "thatch": thatch}
			world._order({"op": "wall", "walls": [data]}, world.me())
			var id := world.seq * Commands.MAX_PIECES
			var wall: Wall = main.tool.find(id)
			var target := picker.style_target(PaletteTool.Restyle.ROOF, wall, Vector3.ZERO)
			_check(target.count == (1 if pitch == 0.0 else 2), "roof offers only coverings for its shape")
			for pick in target.count:
				picker.open(main.rig.right, target)
				var wheel: PaletteTool.Wheel = picker.wheels[main.rig.right]
				for change in wheel.data:
					_check(not change.get("roof", {}).has("pitch") and not change.get("roof", {}).has("curve"), "covering choices never write shape")
				picker.twist(main.rig.right, (pick - wheel.start) * Palette.TWIST_STEP)
				_check(wall.roof.pitch == pitch and wall.roof.curve == 0.4, "preview preserves pitch and curve")
				picker.close(main.rig.right)
				_check(world.state.walls[id].roof.pitch == pitch and world.state.walls[id].roof.curve == 0.4, "committed covering preserves pitch and curve")
			wall.lay_now()
			var colour := picker.aim(wall.roof.frame().mid + Vector3.UP * 10.0, Vector3.DOWN)
			var element := Palette.Element.STONE if pitch == 0.0 else Palette.Element.THATCH
			_check(colour.get("element") == element, "roof colour choices match the rendered covering")
			_turn(colour, 1)
			_check(world.state.walls[id].paint[element] == 1, "roof colour commits the covering's swatch")
			_check(world.state.walls[id].roof.pitch == pitch, "colour keeps the roof shape")
			wall.lay_now()
			var mason := WallTool.Mason.new()
			var start: Vector3 = wall.roof.frame().mid + Vector3.UP * pitch
			main.tool.begin_roof(mason, wall, start)
			main.tool.drag_roof(mason, start + Vector3.UP * (2.0 if pitch == 0.0 else -2.0) / mason.lift_gain)
			main.tool.end_roof(mason)
			_check((world.state.walls[id].roof.pitch == 0.0) == (pitch > 0.0), "grab and vertical pull changes roof shape")
			world.restore({"seq": 0, "cmds": []})
