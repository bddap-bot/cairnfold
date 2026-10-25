extends "res://../tests/support/suite.gd"

## Headless checks that deleting a house takes everything belonging to it, in the scene, the saved garden and on a
## peer, and that undo brings all of it back: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_house_delete.gd

var world: World
var save := ""


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	world = main.world
	# The meadow alone fills much of the frame budget; what is measured here is what goes, not what fits.
	world.bounded = false
	save = OS.get_user_data_dir().path_join("cairnfold-house-delete-%d.garden" % OS.get_process_id())
	world.load_from(save)
	world.restore({"seq": 0, "cmds": []})
	await _settle()
	_every_table_says_what_it_stands_on()
	var bare := _scene()
	var neighbour := await _neighbour()
	var kept := _scene()
	var house := await _house()
	var owned: Dictionary = house.owned
	_covers_every_kind(owned)
	var built := world.digest()
	var before := world.snapshot()
	var sent := []
	world.applied.connect(func(c: Dictionary) -> void: sent.append(c.duplicate(true)))
	world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([house.id])})
	await _settle()
	_none_left(owned, "deleting the house")
	check(_scene() == kept, "the scene is as it was before the house: %s against %s" % [_scene(), kept])
	_neighbour_stands(neighbour)
	world.flush()
	var saved: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(save))
	check(_cmds_naming(saved.cmds, owned).is_empty(), "the saved garden holds none of it: %s" % [_cmds_naming(saved.cmds, owned)])
	var gone := world.digest()
	world.undo()
	await _settle()
	check(world.digest().merged({"seq": 0}, true) == built.merged({"seq": 0}, true), "one undo brings back the house and everything on it")
	world.redo()
	await _settle()
	_none_left(owned, "redoing the delete")
	await _a_sweep_takes_the_house_and_its_things(before, owned)
	await _a_peer_sees_the_same(before, sent[0], gone, owned)
	await _undo_spares_what_another_built_on_it()
	world.restore({"seq": 0, "cmds": []})
	await _settle()
	check(_scene() == bare, "an emptied garden is the bare meadow again")
	DirAccess.remove_absolute(save)
	finish()


## Every table of the garden names what its entries stand on, so a new kind of thing goes with its build by default.
func _every_table_says_what_it_stands_on() -> void:
	var tables := World.blank().keys()
	var named := Commands.STANDS_ON.keys()
	tables.sort()
	named.sort()
	check(tables == named, "Commands.STANDS_ON names every table of the garden: %s against %s" % [named, tables])


## Lets the frame's relaying and the workers finish, every build laid and its ivy grown.
func _settle() -> void:
	await process_frame
	await process_frame
	main.tool._relay_due()
	for w in main.tool.walls:
		w.ivy_age = INF
		w.lay_now()
	for id: int in world.stairs.layouts:
		world.stairs.settle(id)
	await process_frame
	await until(func() -> bool: return main.tool.walls.all(func(w: Wall) -> bool: return w._ivy_task < 0 and not w.laying()), "every wall and its ivy laid")
	world.decorations.sync()


## What the scene shows of the garden's builds: walls, stairs, decorations and their lantern flames, the pieces the
## masonry draws, worn floors and the frame budget's count.
func _scene() -> Dictionary:
	world.decorations.sync()
	return {
		"walls": main.tool.walls.size(),
		"stairs": world.stairs.layouts.size(),
		"decorations": world.decorations.nodes.size(),
		"flames": world.decorations.flames.size(),
		"masonry": Array(main.tool.masonry.counts()),
		"floor marks": world._floor_marks.size(),
		"units": world.units.keys().map(func(k: String) -> String: return "%s %.4f" % [k, world.units[k]]),
	}


func _wall_data(a: Vector3, b: Vector3, depth: float, on: PackedInt32Array, pitch: float) -> Dictionary:
	var points := WallLayout.rectangle(world.terrain.ground(a.x, a.z), world.terrain.ground(b.x, b.z), depth)
	var centre := world.terrain.ground((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
	return wall_data({"points": PackedVector3Array(points), "seed": 3, "closed": true, "on": on, "roof": {"kind": RoofLayout.Kind.GABLE, "center": centre, "radius": depth * 0.5, "pitch": pitch, "curve": 0.0, "seed": 4, "chimneys": PackedVector2Array(), "dormers": PackedVector2Array(), "hatches": PackedVector2Array(), "overhang": RoofLayout.OVERHANG, "deck": RoofLayout.Deck.STONE, "flag": false, "thatch": false}})


func _build(data: Dictionary) -> int:
	world.submit({"op": "wall", "walls": [data]})
	return world.seq * Commands.MAX_PIECES


func _decorate(w: int, mount: String, point: Vector3, s := 0.0, style := DecorationLayout.PRESENT) -> int:
	var cmd := FittingTool.decoration_command({"wall": main.tool.find(w) if w >= 0 else null, "mount": mount, "point": point, "s": s, "side": 1.0, "style": style})
	world.submit(cmd)
	check(world.state.decorations.has(world.seq), "a %s decoration is placed" % mount)
	return world.seq


func _stairs(a: Vector3, b: Vector3) -> int:
	var d := {"a": a, "b": b, "width": 1.2, "sag": 0.0, "rail": "stone", "seed": 7, "paint": Palette.plain()}
	d.on = main.tool.stair_supports(d)
	world.submit({"op": "stairs", "stairs": d})
	check(world.state.stairs.has(world.seq), "stairs are laid")
	return world.seq


## A house next door with its own things, and stairs and a decoration on the ground: none of it goes with the house.
func _neighbour() -> Dictionary:
	var id := _build(_wall_data(Vector3(14, 0, -30), Vector3(20, 0, -30), 4.0, PackedInt32Array(), 1.4))
	await _settle()
	var w := main.tool.find(id)
	var inside := w.massing.rect.get_center()
	var out := {"wall": id, "decorations": [], "stairs": []}
	out.decorations.append(_decorate(id, "floor", Vector3(inside.x, w.layout.floor_y, inside.y)))
	out.decorations.append(_decorate(-1, "ground", world.terrain.ground(4, -24), 0.0, DecorationLayout.STYLES.find({"name": "Standing torch"})))
	out.stairs.append(_stairs(world.terrain.ground(2, -26), world.terrain.ground(2, -26) + Vector3(0, 2, -4)))
	await _settle()
	return out


func _neighbour_stands(n: Dictionary) -> void:
	check(world.state.walls.has(n.wall) and main.tool.find(n.wall) != null, "the house next door stands")
	check(n.decorations.all(func(id: int) -> bool: return world.state.decorations.has(id)), "the next house's and the ground's decorations stay")
	check(n.stairs.all(func(id: int) -> bool: return world.state.stairs.has(id)), "stairs on the ground stay")


## A house with every fitting, an upper storey on it with a flat roof's deck, and a house on that deck, each with its
## furniture, stairs up onto the deck, and the house's foundation dressed: by table, the ids of all of it.
func _house() -> Dictionary:
	var a := Vector3(-6, 0, -30)
	var b := Vector3(0, 0, -30)
	var data := _wall_data(a, b, 5.0, PackedInt32Array(), 1.4)
	data.openings = PackedVector4Array([Vector4(1.5, 1.4, WallLayout.Family.COTTAGE, 1), Vector4(6 + 2.5, 0.0, WallLayout.Family.COTTAGE, 1), WallLayout.archway(12 + 3.0)])
	data.lanterns = PackedVector3Array([Vector3(4.0, 1.8, 1), Vector3(14.0, 1.8, -1)])
	data.flags = PackedFloat32Array([0.5])
	data.finish = WallLayout.Finish.TIMBER
	data.foundation = WallLayout.Foundation.PLASTER
	data.height = 5.4
	data.roof.chimneys = PackedVector2Array([Vector2(1.5, 0.0)])
	data.roof.dormers = PackedVector2Array([Vector2(-1.0, -2.5), Vector2(1.0, 2.5)])
	data.roof.thatch = true
	var house := _build(data)
	var storey_data := _wall_data(a, b, 5.0, PackedInt32Array([house]), 0.0)
	storey_data.roof.deck = RoofLayout.Deck.WOOD
	storey_data.roof.flag = true
	storey_data.lanterns = PackedVector3Array([Vector3(2.0, 1.6, 1)])
	var storey := _build(storey_data)
	await _settle()
	var deck_y: float = main.tool.find(storey).roof.height_at(-3, -31)
	var top_data := _wall_data(Vector3(-5, 0, -31), Vector3(-2, 0, -31), 2.5, PackedInt32Array([storey]), 1.2)
	var top := _build(top_data)
	await _settle()
	var owned := {"walls": [house, storey, top], "decorations": [], "stairs": []}
	var h := main.tool.find(house)
	var inside := h.massing.rect.get_center()
	owned.decorations.append(_decorate(house, "foundation", h.layout.point_at(2.0), 2.0))
	owned.decorations.append(_decorate(house, "floor", Vector3(inside.x, h.layout.floor_y, inside.y)))
	owned.decorations.append(_decorate(storey, "deck", Vector3(-0.8, deck_y, -29.0)))
	var t := main.tool.find(top)
	var top_inside := t.massing.rect.get_center()
	owned.decorations.append(_decorate(top, "floor", Vector3(top_inside.x, t.layout.floor_y, top_inside.y)))
	var foot := world.terrain.ground(-1.0, -24.0)
	var landing := Vector3(-1.0, deck_y, -28.5)
	owned.stairs.append(_stairs(foot, landing))
	check(world.state.stairs[owned.stairs[0]].on == PackedInt32Array([storey]), "stairs onto the deck stand on the storey: %s" % world.state.stairs[owned.stairs[0]].on)
	await _settle()
	return {"id": house, "owned": owned}


## The house carries one of each fitting a wall and a roof hold, ivy, and on every surface it offers a decoration;
## every table that can stand on a build has something standing on it.
func _covers_every_kind(owned: Dictionary) -> void:
	var house: Dictionary = world.state.walls[owned.walls[0]]
	var storey: Dictionary = world.state.walls[owned.walls[1]]
	for k in ["openings", "lanterns", "flags"]:
		check(not house[k].is_empty(), "the house has %s" % k)
	for k in ["chimneys", "dormers"]:
		check(not house.roof[k].is_empty(), "the house's roof has %s" % k)
	check(storey.roof.pitch == 0.0 and storey.roof.flag, "the storey has a flat roof's deck and its flag")
	var mounts := {}
	for id in owned.decorations:
		mounts[world.state.decorations[id].mount] = true
	for m in ["foundation", "floor", "deck"]:
		check(mounts.has(m), "a decoration stands on the house's %s" % m)
	for table: String in Commands.STANDS_ON:
		if not Commands.STANDS_ON[table].is_empty():
			check(not owned.get(table, []).is_empty(), "the house carries something from %s" % table)
	var h := main.tool.find(owned.walls[0])
	check(h._parts[Wall.Part.IVY].size() > 0, "ivy has grown on the house")
	check(not world.decorations.flames.is_empty(), "the house's decorations have flames")


func _none_left(owned: Dictionary, what: String) -> void:
	for table: String in owned:
		for id: int in owned[table]:
			check(not world.state[table].has(id), "after %s, %s %d is gone from the garden" % [what, table, id])
	for id: int in owned.walls:
		check(main.tool.find(id) == null, "after %s, wall %d is gone from the scene" % [what, id])
		check(not world._floor_marks.has(id), "after %s, wall %d's floor mark is gone" % [what, id])
	for id: int in owned.stairs:
		check(not world.stairs.layouts.has(id), "after %s, stairs %d are gone from the scene" % [what, id])
	for table: String in Commands.STANDS_ON:
		var field: String = Commands.STANDS_ON[table]
		for id in world.state[table] if not field.is_empty() else []:
			var on: Variant = world.state[table][id][field]
			for o in (Array(on) if on is PackedInt32Array else [on]):
				check(not o in owned.walls, "after %s, nothing in %s stands on a build that went" % [what, table])


## The commands of `cmds` that put back anything in `owned`.
func _cmds_naming(cmds: Array, owned: Dictionary) -> Array:
	return cmds.filter(func(c: Dictionary) -> bool:
		match c.op:
			"wall":
				return Array(c.ids).any(func(id: int) -> bool: return id in owned.walls)
			"stairs":
				return c.id in owned.stairs
			"decoration":
				return c.id in owned.decorations
		return false)


## One delete stroke across the house, its storey, a lantern on the house on its deck and a chair on its floor takes
## them as one command, though the house's going takes the rest first, and leaves the rest standing as one delete does.
func _a_sweep_takes_the_house_and_its_things(before: Dictionary, owned: Dictionary) -> void:
	world.restore(before)
	await _settle()
	world.submit({"op": "batch", "cmds": [
		{"op": "take", "of": "walls", "ids": PackedInt32Array([owned.walls[0]])},
		{"op": "take", "of": "walls", "ids": PackedInt32Array([owned.walls[1]])},
		{"op": "reshape", "of": "walls", "id": owned.walls[2], "data": {"lanterns": PackedVector3Array()}},
		{"op": "take", "of": "decorations", "ids": PackedInt32Array([owned.decorations[1]])},
	]})
	await _settle()
	_none_left(owned, "a sweep")
	world.undo()
	await _settle()
	check(owned.walls.all(func(id: int) -> bool: return world.state.walls.has(id)) and owned.decorations.all(func(id: int) -> bool: return world.state.decorations.has(id)) and owned.stairs.all(func(id: int) -> bool: return world.state.stairs.has(id)), "undoing the sweep brings all of it back")


## A peer holding the garden as it stood applies the host's delete as sent and shows what the host shows.
func _a_peer_sees_the_same(before: Dictionary, sent: Dictionary, host: Dictionary, owned: Dictionary) -> void:
	world.restore(before)
	await _settle()
	world._commit(sent)
	await _settle()
	_none_left(owned, "a peer applying the host's delete")
	check(world.digest() == host, "the peer's garden matches the host's")


## Another player's chair in my house is building on it: my undo of the house is dropped rather than taking the chair.
func _undo_spares_what_another_built_on_it() -> void:
	world.restore({"seq": 0, "cmds": []})
	await _settle()
	var house := _build(_wall_data(Vector3(-6, 0, -30), Vector3(0, 0, -30), 5.0, PackedInt32Array(), 1.4))
	await _settle()
	var h := main.tool.find(house)
	var inside := h.massing.rect.get_center()
	var chair := FittingTool.decoration_command({"wall": h, "mount": "floor", "point": Vector3(inside.x, h.layout.floor_y, inside.y)})
	world._order(chair, 42)
	var id := world.seq
	world.undo()
	await _settle()
	check(world.state.walls.has(house) and world.state.decorations.has(id), "my undo leaves the house another player furnished, and their chair")
