extends "res://../tests/support/suite.gd"

## Headless checks of the style tool's plaster faces, tree species and painted stone's and boulders' styles, through the host as a player's turn of the
## wheel goes: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_style.gd

var world: World


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	await process_frame
	world = main.world
	_roof_choices_keep_shape()
	_species_differ()
	_faces_turn_to_plaster()
	_foundations_turn_to_plaster()
	_floors_take_a_style()
	_faces_cut_no_opening()
	_timber_faces()
	_towers_keep_stone()
	_trees_take_a_species()
	_meadow_trees_take_a_species()
	_trees_grow_by_the_grip()
	_meadow_trees_grow()
	_stone_takes_a_style()
	_boulders_take_a_stone_style()
	finish()


## A cleaned command as the host would send it on, checked again as a peer checks it.
func _relayed(cmd: Dictionary, by: int) -> Dictionary:
	var hosted := Commands.clean(cmd, world.state, false)
	hosted.seq = world.seq + 1
	hosted.by = by
	return Commands.clean(hosted, world.state, true)


func _turn(target: Dictionary, steps: int) -> void:
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, target)
	picker.twist(main.rig.right, Palette.twist_step(target.count) * steps)
	picker.close(main.rig.right)


## Each species stands apart from the others in the shape of its crown and in its leaves.
func _species_differ() -> void:
	var looks := []
	for species in FloraLayout.Species.values():
		var t := FloraLayout.tree(Vector3.ZERO, 5, species)
		check(t.blobs.size() == FloraLayout.BLOBS, "every species grows BLOBS blobs")
		var box := AABB(t.blobs[0][0].origin, Vector3.ZERO)
		var green := Color(0, 0, 0)
		for b in t.blobs:
			box = box.merge(b[0] * AABB(-Vector3.ONE * 0.5, Vector3.ONE))
			green += b[1] / t.blobs.size()
		check(box.position.y > 0.5, "%s: its foliage stands off the ground" % FloraLayout.Species.keys()[species])
		looks.append([box.size.y / box.size.x, green, box.size.y])
	for a in looks.size():
		for b in range(a + 1, looks.size()):
			var shape: float = absf(looks[a][0] - looks[b][0]) + absf(looks[a][2] - looks[b][2]) * 0.2
			var hue := Vector3(looks[a][1].r - looks[b][1].r, looks[a][1].g - looks[b][1].g, looks[a][1].b - looks[b][1].b).length()
			check(shape > 0.25 and hue > 0.05, "%s and %s differ in silhouette (%.2f) and leaf colour (%.2f)" % [FloraLayout.Species.keys()[a], FloraLayout.Species.keys()[b], shape, hue])


## The style tool turns a stone face to plaster through the host, which a peer takes, an undo puts back, a redo
## brings again and a save carries; the walls laid after are plaster too.
func _faces_turn_to_plaster() -> void:
	world._order({"op": "wall", "walls": [_wall_data(PackedVector3Array([Terrain.ground(-30, 20), Terrain.ground(-24, 20)]))]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var target: Dictionary = main.palette_tool.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO)
	check(target.count == PaletteTool.FACES.size(), "an open wall's face offers every finish")
	var relayed := _relayed({"op": "reshape", "of": "walls", "id": id, "data": {"finish": WallLayout.Finish.PLASTER}}, 2)
	check(relayed.get("data", {}).get("finish") == WallLayout.Finish.PLASTER, "a peer takes the host's turn of a face to plaster: %s" % relayed)
	_turn(target, 1)
	check(world.state.walls[id].finish == WallLayout.Finish.PLASTER and main.tool.find(id).layout.finish == WallLayout.Finish.PLASTER, "a twist of the style tool turns the face to plaster")
	main.tool.find(id).lay_now()
	check(main.tool.find(id).layout.stones.any(func(s): return s.kind == "plaster"), "and it is laid in plaster panels")
	check(main.tool.finish == WallLayout.Finish.PLASTER, "walls laid after are plaster")
	world._order({"op": "undo"}, world.me())
	check(world.state.walls[id].finish == WallLayout.Finish.BARE and main.tool.find(id).layout.finish == WallLayout.Finish.BARE, "an undo puts the stone back")
	world._order({"op": "redo"}, world.me())
	check(world.state.walls[id].finish == WallLayout.Finish.PLASTER, "a redo brings the plaster again")
	world.restore(world.snapshot())
	check(main.tool.find(id).layout.finish == WallLayout.Finish.PLASTER, "a save carries it")
	_turn(main.palette_tool.style_target(PaletteTool.Restyle.FACE, main.tool.find(id), Vector3.ZERO), -1)
	check(world.state.walls[id].finish == WallLayout.Finish.BARE and main.tool.finish == WallLayout.Finish.BARE, "a twist back turns it, and the walls after, to stone")
	world.restore({"seq": 0, "cmds": []})


func _foundations_turn_to_plaster() -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-4, 0), Terrain.ground(4, 0), 6.0)))
	d.closed = true
	d.rise = 1.5
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(0, 0), "radius": 3.0, "pitch": 2.0, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, world.me())
	var id := world.seq * Commands.MAX_PIECES
	var w: Wall = main.tool.find(id)
	w.lay_now()
	var f := w.layout.frame_at(2.0)
	var out: Vector3 = f.tangent.cross(Vector3.UP)
	var origin: Vector3 = f.point + Vector3.DOWN * 0.6 + out * 2.0
	var target: Dictionary = main.palette_tool.aim_style(origin, -out)
	check(target.get("restyle") == PaletteTool.Restyle.FOUNDATION and target.get("count") == WallLayout.Foundation.size(), "a house's foundation offers stone, plaster, pillars and posts: %s" % target)
	_turn(target, WallLayout.Foundation.PLASTER)
	w.lay_now()
	check(w.layout.stones.any(func(st): return st.kind == "plaster" and st.y < 0.0), "the foundation wheel lays plaster below the foot")
	check(w.layout.finish == WallLayout.Finish.BARE, "styling a foundation leaves the upper wall stone")
	check(main.tool.finish == WallLayout.Finish.BARE, "foundation style leaves the next wall's face unchanged")
	check(w.layout.stones.filter(func(st): return st.kind == "plaster" and st.y < 0.0).all(func(st): return st.color == WallLayout.PLASTER), "foundation panels share the wall plaster colour")
	check(main.palette_tool.aim(origin, -out).get("element") == Palette.Element.PLASTER, "the colour tool recognises the foundation's plaster")
	var relayed := _relayed({"op": "reshape", "of": "walls", "id": id, "data": {"foundation": WallLayout.Foundation.STONE}}, 2)
	check(relayed.get("data", {}).get("foundation") == WallLayout.Foundation.STONE, "foundation style survives host and peer validation")
	world._order({"op": "undo"}, world.me())
	w.lay_now()
	check(w.layout.foundation == WallLayout.Foundation.STONE and w.layout.stones.any(func(st): return st.kind == "block" and st.y < 0.0), "undo restores stone foundation courses")
	world._order({"op": "redo"}, world.me())
	world.restore(world.snapshot())
	w = main.tool.find(id)
	w.lay_now()
	check(w.layout.foundation == WallLayout.Foundation.PLASTER and w.layout.finish == WallLayout.Finish.BARE, "redo and save preserve foundation style independently")
	world._order({"op": "reshape", "of": "walls", "id": id, "data": {"finish": WallLayout.Finish.PLASTER}}, world.me())
	w.lay_now()
	_turn(main.palette_tool.aim_style(origin, -out), -1)
	w.lay_now()
	check(w.layout.foundation == WallLayout.Foundation.STONE and w.layout.finish == WallLayout.Finish.PLASTER, "turning the foundation back to stone keeps the wall plastered")
	_turn(main.palette_tool.aim_style(origin, -out), WallLayout.Foundation.POSTS)
	w.lay_now()
	check(world.state.walls[id].foundation == WallLayout.Foundation.POSTS and w.layout.stones.any(func(st): return st.kind == "post" and st.y < 0.0), "turned to posts, the raised house stands on timber posts")
	check(main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, -out).get("mount") != "foundation", "nothing is set at a stilted foundation, with no face to back it")
	check(main.tool.foundation == WallLayout.Foundation.POSTS, "houses laid after stand on posts once raised")
	world._order({"op": "undo"}, world.me())
	w.lay_now()
	check(world.state.walls[id].foundation == WallLayout.Foundation.STONE and not w.layout.stones.any(func(st): return st.kind == "post"), "an undo stands it back on its plinth")
	main.tool.foundation = WallLayout.Foundation.STONE

	world.restore({"seq": 0, "cmds": []})


## The style tool aimed at a floor offers flags or planks: turned, a peer takes it, an undo puts it back, a save as
## written to disk carries it, and houses laid after take it. The floor and the walls never move each other.
func _floors_take_a_style() -> void:
	var d := _wall_data(PackedVector3Array(WallLayout.rectangle(Terrain.ground(-14, 24), Terrain.ground(-10, 24), 4.0)))
	d.closed = true
	d.height = 2.6
	d.roof = {"kind": RoofLayout.Kind.GABLE, "center": Terrain.ground(-12, 24), "radius": 2.0, "pitch": 2.0, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}
	world._order({"op": "wall", "walls": [d]}, 1)
	var id := world.seq * Commands.MAX_PIECES
	var w: Wall = main.tool.find(id)
	w.lay_now()
	var inside := Vector3(-12.3, w.layout.floor_y + 1.6, 24.2)
	var down := Vector3(0.1, -1, -0.1).normalized()
	var target: Dictionary = main.palette_tool.aim_style(inside, down)
	check(target.get("restyle") == PaletteTool.Restyle.FLOOR and target.get("count") == 2, "a house's floor offers flags and planks: %s" % target)
	check(main.palette_tool.aim_style(inside, Vector3(1, -0.1, 0).normalized()).get("restyle") == PaletteTool.Restyle.FACE, "the wall beside the floor still takes its own style")
	var relayed := _relayed({"op": "reshape", "of": "walls", "id": id, "data": {"planks": true}}, 2)
	check(relayed.get("data", {}).get("planks") == true, "a peer takes the host's turn of a floor to planks: %s" % relayed)
	_turn(target, PaletteTool.Floor.PLANKS)
	w.lay_now()
	var floor_kinds := func(of: Wall) -> Array: return of.layout.stones.filter(func(st): return st.kind in ["flagstone", "plank"]).map(func(st): return st.kind)
	check(world.state.walls[id].planks and floor_kinds.call(w).all(func(k): return k == "plank"), "a twist of the style tool boards the floor")
	check(world.state.walls[id].finish == WallLayout.Finish.BARE and world.state.walls[id].foundation == WallLayout.Foundation.STONE, "boarding the floor leaves the walls stone")
	check(main.tool.planks and main.tool.finish == WallLayout.Finish.BARE, "houses laid after are boarded, their walls still stone")
	world._order({"op": "undo"}, world.me())
	w.lay_now()
	check(not world.state.walls[id].planks and floor_kinds.call(w).all(func(k): return k == "flagstone"), "an undo puts the flags back")
	world._order({"op": "redo"}, world.me())
	check(world.restore_whole(bytes_to_var(var_to_bytes(world.snapshot()))), "the garden as saved to disk loads")
	w = main.tool.find(id)
	w.lay_now()
	check(w.layout.planks and floor_kinds.call(w).all(func(k): return k == "plank"), "a save carries the boarded floor")
	world._order({"op": "reshape", "of": "walls", "id": id, "data": {"finish": WallLayout.Finish.PLASTER}}, world.me())
	w.lay_now()
	check(w.layout.planks and w.layout.finish == WallLayout.Finish.PLASTER, "plastering the walls keeps the floor boarded")
	_turn(main.palette_tool.aim_style(inside, down), -1)
	w.lay_now()
	check(not w.layout.planks and w.layout.finish == WallLayout.Finish.PLASTER, "turning the floor back to flags keeps the walls plastered")
	check(not main.tool.planks, "and houses laid after are flagged again")
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
	check(world.state.walls.size() == 2, "an open wall and a house stand")
	for id: int in world.state.walls:
		var before := PackedVector4Array(world.state.walls[id].openings)
		var wall: Wall = main.tool.find(id)
		for at in [0.5, 2.0, 5.0]:
			var target := picker.style_target(PaletteTool.Restyle.FACE, wall, wall.layout.point_at(at))
			for pick in target.count:
				picker.open(main.rig.right, target)
				picker.twist(main.rig.right, (pick - picker.wheels[main.rig.right].start) * Palette.twist_step(target.count))
				check(PackedVector4Array(wall.layout.openings) == before, "face %d shown at %.1f m keeps the arches: %s" % [pick, at, wall.layout.openings])
				picker.close(main.rig.right)
				check(PackedVector4Array(world.state.walls[id].openings) == before, "face %d sent at %.1f m keeps the arches: %s" % [pick, at, world.state.walls[id].openings])
	world.restore({"seq": 0, "cmds": []})


func _wall_data(points: PackedVector3Array) -> Dictionary:
	return wall_data({"points": points, "seed": 3})


## A planted tree grows an oak; the style tool aimed at it offers each species and turns it to one through the host,
## which a peer takes; an undo, a redo and a save follow it, and its slots are laid as that species.
func _trees_take_a_species() -> void:
	var flora: Flora = main.flora_tool.flora
	var at := Terrain.ground(-6, 18)
	world._order({"op": "plant", "kind": "tree", "seed": 7, "at": at}, world.me())
	var g := world.seq
	var trunk: Flora.Plant = flora.groups[g][0]
	check(flora.species_of(trunk) == FloraLayout.Species.OAK, "a planted tree is an oak")
	var crown: Vector3 = flora.groups[g][1].xform.origin + Vector3.UP * Terrain.base_at(at.x, at.z)
	var target: Dictionary = main.palette_tool.aim_style(crown + Vector3(0, 1, 8), (crown - (crown + Vector3(0, 1, 8))).normalized())
	check(target.get("restyle") == PaletteTool.Restyle.TREE and target.get("tree") == trunk and target.count == FloraLayout.Species.size(), "the style tool aimed at a tree offers its species: %s" % [target.get("restyle")])
	var models := ToolModels.style(PaletteTool.Restyle.TREE, FloraLayout.Species.FIR, WallLayout.Finish.BARE)
	check(models.get_child_count() == 2, "each species has its miniature")
	models.free()
	var relayed := _relayed({"op": "tree", "group": g, "index": 0, "species": FloraLayout.Species.BIRCH}, 2)
	check(relayed.get("species") == FloraLayout.Species.BIRCH and relayed.get("group") == g, "a peer takes the host's species: %s" % relayed)
	check(Commands.clean({"op": "tree", "group": g, "index": 1, "species": 1}, world.state, false).is_empty(), "only a tree's trunk names it")
	check(Commands.clean({"op": "tree", "group": g, "index": 0, "species": FloraLayout.Species.size()}, world.state, false).is_empty(), "no species past the last")
	var oak_top: float = flora.groups[g][1].xform.origin.y
	_turn(target, FloraLayout.Species.POPLAR)
	check(world.state.groups[g].species.get(0) == FloraLayout.Species.POPLAR and flora.species_of(trunk) == FloraLayout.Species.POPLAR, "a twist of the wheel turns the tree a poplar")
	check(flora.groups[g][-1].xform.origin.y > oak_top + 1.0, "and it grows tall as one")
	check(flora.trunks.size() == flora.trunks.kept + 1, "in the slots it held")
	world._order({"op": "undo"}, world.me())
	check(flora.species_of(trunk) == FloraLayout.Species.OAK and world.state.groups[g].species.is_empty(), "an undo makes it an oak again")
	check(is_equal_approx(flora.groups[g][1].xform.origin.y, oak_top), "the same oak")
	world._order({"op": "redo"}, world.me())
	check(flora.species_of(trunk) == FloraLayout.Species.POPLAR, "a redo makes it a poplar again")
	var picture := var_to_str(world.digest())
	world.restore(world.snapshot())
	check(var_to_str(world.digest()) == picture and flora.species_of(flora.groups[g][0]) == FloraLayout.Species.POPLAR, "a save carries it")
	world.restore({"seq": 0, "cmds": []})


## The meadow's own trees take a species as planted ones do, and go back to oaks with a swapped garden.
func _meadow_trees_take_a_species() -> void:
	var flora: Flora = main.flora_tool.flora
	var i: int = flora.meadow_trees()[3]
	var trunk: Flora.Plant = flora.groups[0][i]
	world._order({"op": "tree", "group": 0, "index": i, "species": FloraLayout.Species.BEECH}, 2)
	check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "a meadow tree turns a copper beech")
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	check(flora.species_of(trunk) == FloraLayout.Species.OAK, "an empty garden has it an oak again")
	world.restore(snap)
	check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "and its save a beech")
	world._order({"op": "tree", "group": 0, "index": i, "species": FloraLayout.Species.FIR}, 2)
	world._order({"op": "undo"}, 2)
	check(flora.species_of(trunk) == FloraLayout.Species.BEECH, "an undo goes back one species")
	world.restore({"seq": 0, "cmds": []})


## Two grips on a planted tree spread grow it and closed shrink it, by their span, within FloraLayout.SCALES, through the
## host, which a peer takes; one hand raised alone grows nothing; what it strikes, its shade and its share of the
## budget grow with it; an undo, a redo, a species and a snapshot keep it.
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
	var other := tool.mason(main.rig.left)
	var grip := at + Vector3.UP * top * 0.8
	var hand := grip + Vector3.BACK * 2.0
	tool.begin_grow(m, trunk, Transform3D(Basis(), hand), grip)
	check(tool.busy(main.rig.right), "a grip on a tree holds it")
	m.sizing.follow.call(m, Transform3D(Basis(), hand + Vector3.UP * 1.5))
	check(flora.scale_of(trunk) == 1.0, "one hand raised alone grows nothing")
	m.sizing.follow.call(m, Transform3D(Basis(), hand))
	m.hand.global_position = hand
	other.hand.global_position = hand + Vector3.LEFT
	tool.begin_grow(other, trunk, Transform3D(Basis(), hand + Vector3.LEFT), grip)
	tool.drag_pair(other, hand + Vector3.RIGHT * 0.25, hand + Vector3.LEFT * 1.25)
	var grown := flora.scale_of(trunk)
	check(is_equal_approx(grown, 1.5) and absf(flora.top_of(trunk) - top * 1.5) < 0.3, "two hands spread to half again their span grow it half again: %.2f, top %.2f from %.2f" % [grown, flora.top_of(trunk), top])
	check(world.state.groups[g].scale.is_empty(), "shown here alone while held")
	tool.end_grow(other)
	check(m.partner == null and is_equal_approx(flora.scale_of(trunk), grown), "letting one go leaves the other holding it as sized")
	tool.end_grow(m)
	check(world.state.groups[g].scale.get(0) == grown and is_equal_approx(flora.scale_of(trunk), grown) and not world.state.groups[g].places.has(0), "letting go sends its size, and no place for a tree not carried")
	check(is_equal_approx(world.units.tree, trees), "a resized tree keeps its measured per-tree charge: %.2f" % (world.units.tree - trees))
	check(flora.shade_of(flora.groups[g]).basis.get_scale().is_equal_approx(shade * grown), "its shade grows with it")
	var high := at + Vector3(0, top * grown * 0.9, 6)
	check(not flora.solid_hit(high, Vector3.FORWARD, 12.0).is_empty(), "and what strikes it, high on its new crown")
	var relayed := _relayed({"op": "tree", "group": g, "index": 0, "scale": 2.5}, 2)
	check(relayed.get("scale") == 2.5 and not relayed.has("species"), "a peer takes the host's scale: %s" % relayed)
	for bad in [FloraLayout.SCALES.x - 0.01, FloraLayout.SCALES.y + 0.01, 2, NAN]:
		check(Commands.clean({"op": "tree", "group": g, "index": 0, "scale": bad}, world.state, false).is_empty(), "no scale %s" % bad)
	check(Commands.clean({"op": "tree", "group": g, "index": 0}, world.state, false).is_empty(), "a tree command changes something")
	tool.begin_grow(m, trunk, Transform3D(Basis(), hand), grip)
	tool.begin_grow(other, trunk, Transform3D(Basis(), hand + Vector3.LEFT), grip)
	tool.drag_pair(other, hand, hand + Vector3.LEFT * 0.01)
	tool.end_grow(other)
	tool.end_grow(m)
	check(is_equal_approx(flora.scale_of(trunk), FloraLayout.SCALES.x), "closed all the way it shrinks to the least")
	world._order({"op": "undo"}, world.me())
	check(is_equal_approx(flora.scale_of(trunk), grown), "an undo grows it back")
	world._order({"op": "undo"}, world.me())
	check(flora.scale_of(trunk) == 1.0 and world.state.groups[g].scale.is_empty() and is_equal_approx(flora.top_of(trunk), top), "and another to the tree it was planted")
	check(is_equal_approx(world.units.tree, trees), "costing what it did")
	world._order({"op": "redo"}, world.me())
	check(is_equal_approx(flora.scale_of(trunk), grown), "a redo grows it again")
	var crown: Vector3 = flora.groups[g][1].xform.origin + Vector3.UP * Terrain.base_at(at.x, at.z)
	_turn(main.palette_tool.aim_style(crown + Vector3(0, 1, 12), (crown - (crown + Vector3(0, 1, 12))).normalized()), FloraLayout.Species.FIR)
	check(flora.species_of(trunk) == FloraLayout.Species.FIR and is_equal_approx(flora.scale_of(trunk), grown), "a new species keeps its size")
	var picture := var_to_str(world.digest())
	world.restore(world.snapshot())
	trunk = flora.groups[g][0]
	check(var_to_str(world.digest()) == picture and is_equal_approx(flora.scale_of(trunk), grown) and flora.species_of(trunk) == FloraLayout.Species.FIR, "a snapshot carries both")
	world.restore({"seq": 0, "cmds": []})


## The meadow's own trees grow as planted ones do, and go back to their size with a swapped garden.
func _meadow_trees_grow() -> void:
	var flora: Flora = main.flora_tool.flora
	var trunk: Flora.Plant = flora.groups[0][flora.meadow_trees()[2]]
	var top := flora.top_of(trunk)
	world._order({"op": "tree", "group": 0, "index": trunk.index, "scale": 2.0}, 2)
	check(is_equal_approx(flora.top_of(trunk), top * 2.0), "a meadow tree grows twice as tall")
	var snap := world.snapshot()
	world.restore({"seq": 0, "cmds": []})
	check(flora.scale_of(trunk) == 1.0 and is_equal_approx(flora.top_of(trunk), top), "an empty garden has it as it grew")
	world.restore(snap)
	check(flora.scale_of(trunk) == 2.0, "and its snapshot grown")
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
	check(target.count == PaletteTool.FACES.size(), "a house's face wheel offers every finish")
	var timber: int = target.options.find(PaletteTool.FACES.find(Vector2(WallLayout.Finish.TIMBER, 0.0)))
	_turn(target, timber)
	check(world.state.walls[id].finish == WallLayout.Finish.TIMBER, "face wheel commits timber")
	wall.lay_now()
	check(wall.layout.stones.any(func(p): return p.kind == "timber"), "selected timber face is rendered")
	world._order({"op": "undo"}, world.me())
	check(world.state.walls[id].finish == WallLayout.Finish.BARE, "undo restores stone")
	world._order({"op": "redo"}, world.me())
	check(world.state.walls[id].finish == WallLayout.Finish.TIMBER, "redo restores the selected timber face")
	world.restore(world.snapshot())
	check(world.state.walls[id].finish == WallLayout.Finish.TIMBER, "save retains the pattern")
	wall = main.tool.find(id)
	_turn(picker.style_target(PaletteTool.Restyle.FACE, wall, Vector3.ZERO), 1 - timber)
	wall.lay_now()
	check(world.state.walls[id].finish == WallLayout.Finish.PLASTER and world.state.walls[id].wear == 0.0, "plain plaster remains selectable on houses")
	check(wall.layout.stones.all(func(p): return p.kind != "timber"), "plain plaster has no framing")
	world.restore({"seq": 0, "cmds": []})


func _towers_keep_stone() -> void:
	main.tool.finish = WallLayout.Finish.PLASTER
	main.tool.deck = RoofLayout.Deck.STONE
	var tower: Wall = main.tool.new_house(WallTool.stance(Terrain.ground(-20, 10), 0.0, true))
	check(tower.layout.finish == WallLayout.Finish.BARE, "new towers use stone even after choosing plaster on a house")
	var data: Dictionary = tower.data()
	var built: Array[Wall] = [tower]
	main.tool.build(built)
	world.restore({"seq": 0, "cmds": []})
	data.finish = WallLayout.Finish.PLASTER
	var snap := {"seq": 2, "cmds": [
		{"op": "wall", "walls": [data], "ids": PackedInt32Array([Commands.MAX_PIECES]), "seq": 1, "by": 1},
		{"op": "reshape", "of": "walls", "id": Commands.MAX_PIECES, "data": {"finish": WallLayout.Finish.PLASTER}, "seq": 2, "by": 1},
	]}
	check(world.restore(snap) == 2, "a saved plaster tower and its style edit both load")
	var id := Commands.MAX_PIECES
	var wall: Wall = main.tool.find(id)
	check(world.state.walls[id].finish == WallLayout.Finish.BARE and wall.layout.finish == WallLayout.Finish.BARE, "saved plaster towers take the default stone")
	var picker: PaletteTool = main.palette_tool
	for style in [WallTool.RoofStyle.PITCHED, WallTool.RoofStyle.THATCHED, WallTool.RoofStyle.FLAT]:
		if style == WallTool.RoofStyle.FLAT:
			wall.lay_now()
			main.tool.take_build(wall)
			var flat: Dictionary = main.tool.held_at.duplicate()
			flat.pitch = 0.0
			main.tool.stand_build(flat)
			main.tool.end_build()
		else:
			world._order({"op": "reshape", "of": "walls", "id": id, "data": WallTool.restyle_roof(world.state.walls[id], style)}, 1)
		check(WallTool.roof_style(world.state.walls[id]) == style, "tower takes the tested roof style")
		wall.lay_now()
		check(not wall.layout.stones.any(func(s): return s.kind == "plaster"), "tower geometry has no plaster panels")
		var target := picker.style_target(PaletteTool.Restyle.FACE, wall, Vector3.ZERO)
		check(target.count == 1, "every tower roof style offers only stone walls")
		_turn(target, 1)
		check(world.state.walls[id].finish == WallLayout.Finish.BARE, "turning the tower face wheel keeps stone")
	world.restore({"seq": 0, "cmds": []})


## Painted stone aimed at offers every style in StoneStyles' table and turns its stroke to one through the host, which a
## peer takes; the mask carries it where that stroke lies, stone painted after takes it, and an undo, a redo and a save
## follow it. A later stroke's style takes the ground it covers most.
func _stone_takes_a_style() -> void:
	var r := FloraTool.MAX_RADIUS * 0.4
	var stamps := PackedVector4Array([Vector4(30, 30, r, r * 2.0), Vector4(31.5, 30, r, r * 2.0)])
	check(Commands.clean({"op": "ground", "kind": Ground.Kind.STONE, "stamps": stamps}, world.state, false).is_empty(), "stone names its style")
	check(Commands.clean({"op": "ground", "kind": Ground.Kind.STONE, "stamps": stamps, "style": StoneStyles.STYLES.size()}, world.state, false).is_empty(), "no style past the last")
	world._order({"op": "ground", "kind": Ground.Kind.STONE, "stamps": stamps, "style": 0}, world.me())
	var id := world.seq
	Ground.settle()
	var at := Terrain.ground(30.5, 30)
	var target: Dictionary = main.palette_tool.aim_style(at + Vector3(0, 3, 3), Vector3(0, -3, -3).normalized())
	check(target.get("restyle") == PaletteTool.Restyle.STONE and target.get("stroke") == id and target.get("count") == StoneStyles.STYLES.size(), "the style tool aimed at painted stone offers its styles: %s" % [target])
	check(main.palette_tool.aim_style(Terrain.ground(-40, -40) + Vector3(0, 3, 3), Vector3(0, -3, -3).normalized()).is_empty(), "bare meadow has no style")
	for i in StoneStyles.STYLES.size():
		var model := ToolModels.style(PaletteTool.Restyle.STONE, i, WallLayout.Finish.BARE)
		check(model.get_child_count() == 2, "%s has its miniature" % StoneStyles.STYLES[i].name)
		model.free()
	var relayed := _relayed({"op": "restone", "id": id, "style": 1}, 2)
	check(relayed.get("style") == 1 and relayed.get("id") == id, "a peer takes the host's style: %s" % relayed)
	check(Commands.clean({"op": "restone", "id": id + 100, "style": 1}, world.state, false).is_empty(), "only a standing stroke is restyled")
	_turn(target, 1)
	check(world.state.grounds[id].style == 1 and _style_at(30.5, 30) == 1, "a twist of the wheel turns the stone the second style: %d" % _style_at(30.5, 30))
	check(Ground.style == 1, "stone painted after takes it")
	world._order({"op": "undo"}, world.me())
	check(world.state.grounds[id].style == 0 and _style_at(30.5, 30) == 0, "an undo puts the first style back")
	world._order({"op": "redo"}, world.me())
	check(_style_at(30.5, 30) == 1, "a redo brings the second again")
	world.restore(world.snapshot())
	Ground.settle()
	check(world.state.grounds[id].style == 1 and _style_at(30.5, 30) == 1, "a save carries it")
	world._order({"op": "ground", "kind": Ground.Kind.STONE, "stamps": PackedVector4Array([Vector4(33, 30, r, r * 2.0)]), "style": 0}, world.me())
	Ground.settle()
	check(_style_at(33, 30) == 0 and _style_at(30, 30) == 1, "a later stroke's style takes what it covers most, the first keeps the rest: %d, %d" % [_style_at(33, 30), _style_at(30, 30)])
	Ground.style = 0
	world.restore({"seq": 0, "cmds": []})


## A boulder aimed at offers the same stone styles as painted stone, before the ground under it, and takes one as a
## `reshape` through the host, which a peer takes; its meshes draw in it, boulders set down after take it, and an undo
## and a save follow it.
func _boulders_take_a_stone_style() -> void:
	var at := Terrain.ground(-50, 30)
	var plain := {"op": "boulder", "at": at, "turn": Quaternion.IDENTITY, "sink": 0.0, "seed": 5, "scale": 1.0, "paint": Palette.plain()}
	check(Commands.clean(plain, world.state, false).is_empty(), "a boulder names its style")
	check(Commands.clean(plain.merged({"style": StoneStyles.STYLES.size()}), world.state, false).is_empty(), "no boulder style past the last")
	world._order(plain.merged({"style": 0}), world.me())
	var id := world.seq
	var target: Dictionary = main.palette_tool.aim_style(at + Vector3(0, 4, 4), Vector3(0, -4, -4).normalized())
	check(target.get("restyle") == PaletteTool.Restyle.STONE and target.get("of") == "boulders" and target.get("id") == id and target.get("count") == StoneStyles.STYLES.size(), "the style tool aimed at a boulder offers the stone styles: %s" % [target])
	var picker: PaletteTool = main.palette_tool
	picker.open(main.rig.right, target)
	var mesh: MultiMesh
	for i in StoneStyles.STYLES.size():
		var model := picker.wheels[main.rig.right].choices[i].get_child(0).get_child(0) as MultiMeshInstance3D
		check(model != null, "a boulder wheel entry is a solid boulder, not painted ground")
		if model != null:
			check(model.material_override == main.boulders.find(id).near.material_override, "wheel and placed boulder share the stone material")
			check(model.get_instance_shader_parameter("stone_style") == i, "each boulder shows its own style")
			check(mesh == null or mesh == model.multimesh, "boulder choices share their geometry")
			mesh = model.multimesh
	picker.close(main.rig.right)
	var relayed := _relayed({"op": "reshape", "of": "boulders", "id": id, "data": {"style": 1}}, 2)
	check(relayed.get("data", {}).get("style") == 1, "a peer takes the host's boulder style: %s" % relayed)
	check(Commands.clean({"op": "reshape", "of": "boulders", "id": id, "data": {"style": -1}}, world.state, false).is_empty(), "no boulder style before the first")
	_turn(target, 1)
	var b: Boulders.Boulder = main.boulders.find(id)
	check(world.state.boulders[id].style == 1 and b.near.get_instance_shader_parameter("stone_style") == 1 and b.far.get_instance_shader_parameter("stone_style") == 1, "a twist of the wheel draws the boulder in the second style")
	check(Ground.style == 1, "boulders set down and stone painted after take it")
	main.flora_tool.place_boulder(Terrain.ground(-46, 30), null, 6)
	check(world.state.boulders[world.seq].style == 1, "a boulder set down after is in it")
	world._order({"op": "undo"}, world.me())
	world._order({"op": "undo"}, world.me())
	check(world.state.boulders[id].style == 0 and main.boulders.find(id).near.get_instance_shader_parameter("stone_style") == 0, "an undo puts the first style back")
	world._order({"op": "redo"}, world.me())
	world.restore(world.snapshot())
	check(world.state.boulders[id].style == 1 and main.boulders.find(id).near.get_instance_shader_parameter("stone_style") == 1, "a save carries it")
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
			data.roof = {"kind": RoofLayout.Kind.GABLE, "center": Vector3.ZERO, "radius": 2.0, "pitch": pitch, "curve": 0.4, "seed": 3, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": thatch}
			world._order({"op": "wall", "walls": [data]}, world.me())
			var id := world.seq * Commands.MAX_PIECES
			var wall: Wall = main.tool.find(id)
			var target := picker.style_target(PaletteTool.Restyle.ROOF, wall, Vector3.ZERO)
			check(target.count == 2 and target.options == WallTool.roof_options(pitch), "roof offers only coverings for its shape")
			for pick in target.count:
				picker.open(main.rig.right, target)
				var wheel: PaletteTool.Wheel = picker.wheels[main.rig.right]
				for change in wheel.data:
					check(not change.get("roof", {}).has("pitch") and not change.get("roof", {}).has("curve"), "covering choices never write shape")
				picker.twist(main.rig.right, (pick - wheel.start) * Palette.TWIST_STEP)
				check(wall.roof.pitch == pitch and wall.roof.curve == 0.4, "preview preserves pitch and curve")
				picker.close(main.rig.right)
				check(world.state.walls[id].roof.pitch == pitch and world.state.walls[id].roof.curve == 0.4, "committed covering preserves pitch and curve")
			wall.lay_now()
			var colour := picker.aim(wall.roof.frame().mid + Vector3.UP * 10.0, Vector3.DOWN)
			var boarded: bool = world.state.walls[id].roof.deck == RoofLayout.Deck.WOOD
			var element := (Palette.Element.WOOD if boarded else Palette.Element.STONE) if pitch == 0.0 else Palette.Element.THATCH
			check(colour.get("element") == element, "roof colour choices match the rendered covering")
			_turn(colour, 1)
			check(world.state.walls[id].paint[element] == 1, "roof colour commits the covering's swatch")
			check(world.state.walls[id].roof.pitch == pitch, "colour keeps the roof shape")
			wall.lay_now()
			main.tool.take_build(wall)
			var hands: Array[Transform3D] = [Transform3D(Basis(), Vector3(0, 1, 0)), Transform3D(Basis(), Vector3(0, 2, 0) if pitch == 0.0 else Vector3(0, 3, 0))]
			var drawn: Array[Transform3D] = [hands[0], Transform3D(Basis(), Vector3(0, 4, 0) if pitch == 0.0 else Vector3(0, 1, 0))]
			main.tool.stand_build(WallTool.bend(main.tool.held_at, hands, drawn, 1.0))
			main.tool.end_build()
			check((world.state.walls[id].roof.pitch == 0.0) == (pitch > 0.0), "two hands drawn apart or together upright change the roof's shape")
			world.restore({"seq": 0, "cmds": []})
