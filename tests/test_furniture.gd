extends SceneTree

## Furniture through the one decoration path: indoor pieces on a house's floors, outdoor pieces on a flat roof's deck.
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_furniture.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _node(id: int) -> Node3D:
	main.world.decorations.sync()
	return main.world.decorations.nodes.get(id)


func _place(origin: Vector3, at: Vector3, mount: String, wall: Wall) -> int:
	var aim: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, origin, (at - origin).normalized())
	check(aim.get("what") == "decoration" and aim.get("mount") == mount and aim.get("wall") == wall, "%s aimed at %s" % [mount, at])
	var cmd := FittingTool.decoration_command(aim)
	check(cmd.style in DecorationLayout.options(mount), "%s style drawn from its own table" % mount)
	check(main.world.change_of(cmd).get("fitting", 0.0) > 0.0, "%s piece charged against the budget" % mount)
	var before: Array = main.world.state.decorations.keys()
	check(main.fitting_tool.fit(aim), "%s placed" % mount)
	var added: Array = main.world.state.decorations.keys().filter(func(k): return k not in before)
	check(added.size() == 1, "one %s piece saved" % mount)
	return added[0] if added.size() == 1 else -1


func _run() -> void:
	main.world.bounded = false
	var driver := Driver.new(main, [
		{"op": "house", "at": [0, 0], "size": [7, 5], "seconds": 0.2},
		{"op": "house", "at": [12, 0], "size": [6, 5], "seconds": 0.2, "rise": 0.6},
		{"op": "roof", "index": 1, "pitch": 0.0},
	])
	main.add_child(driver)
	await driver.finished
	driver.queue_free()
	var house: Wall = main.tool.walls[0]
	var decked: Wall = main.tool.walls[1]
	house.lay_now()
	decked.lay_now()

	var chair := _place(Vector3(0.5, 1.6, 1.2), Vector3(1.2, 0.0, -0.6), "floor", house)
	var n := _node(chair)
	check(n != null and absf(n.position.y - house.layout.floors[0]) < 0.01, "indoor piece stands on the floor")
	var deck := _place(Vector3(12.5, 9.0, 0.5), Vector3(12.5, 0.0, 0.5), "deck", decked)
	n = _node(deck)
	check(n != null and absf(n.position.y - decked.roof.height_at(n.position.x, n.position.z)) < 0.01, "outdoor piece stands on the deck")
	check(n != null and Vector2(n.position.x, n.position.z).distance_to(Vector2(12.5, 0.5)) < 0.05, "outdoor piece where it was aimed")
	var pitched: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, Vector3(0.5, 9.0, 0.5), Vector3.DOWN)
	check(pitched.get("what") == "chimney", "a pitched roof still takes a chimney, not furniture")

	var bad: Dictionary = main.world.state.decorations[chair].merged({"op": "decoration", "wall": -1}, true)
	check(Commands.clean(bad, main.world.state, false).is_empty(), "indoor style refused on open ground")

	n = _node(chair)
	var r0 := house.roof.frame()
	var o0: Vector3 = n.position - r0.mid
	var face0: Vector3 = n.transform.basis.z
	var from: Dictionary = WallTool.house_of(main.world.state.walls[house.id])
	var to := from.duplicate()
	to.center += Vector3(2.0, 0.0, 1.0)
	to.yaw += PI * 0.5
	to.rise = 0.9
	main.world.submit({"op": "reshape", "of": "walls", "id": house.id, "data": WallTool.reshape_house(main.world.state.walls[house.id], to)})
	house.lay_now()
	n = _node(chair)
	var r1 := house.roof.frame()
	var o1: Vector3 = n.position - r1.mid if n != null else Vector3.INF
	check(n != null and absf(n.position.y - house.layout.floors[0]) < 0.01 and house.layout.floors[0] > 0.8, "indoor piece rises with its floor")
	check(absf(o0.dot(r0.along) - o1.dot(r1.along)) < 0.05 and absf(o0.dot(r0.across) - o1.dot(r1.across)) < 0.05, "indoor piece moves and turns with its house")
	check(n != null and absf(face0.dot(r0.along) - n.transform.basis.z.dot(r1.along)) < 0.01, "indoor piece keeps its facing in the room")
	main.world.undo()
	house.lay_now()

	var height: float = main.world.state.walls[house.id].height
	main.world.submit({"op": "reshape", "of": "walls", "id": house.id, "data": {"storey_floors": true, "height": 5.1}})
	house.lay_now()
	check(house.layout.floors.size() >= 2, "house floored at a storey")
	var upper := house.layout.floors[1]
	var shelf := _place(Vector3(-1.5, upper + 1.0, 0.8), Vector3(-2.0, upper, -0.4), "floor", house)
	n = _node(shelf)
	check(n != null and absf(n.position.y - upper) < 0.01, "indoor piece stands on the storey it was placed on")
	main.world.submit({"op": "reshape", "of": "walls", "id": house.id, "data": {"storey_floors": false, "height": height}})
	house.lay_now()
	n = _node(shelf)
	check(n != null and absf(n.position.y - house.layout.floors[0]) < 0.01, "an upper piece comes down when its storey goes")

	n = _node(chair)
	var top: Vector3 = (n.transform * (n.get_meta(&"bounds") as AABB)).get_center()
	var eye := top + Vector3(0.0, 1.2, 0.6)
	var style_target: Dictionary = main.palette_tool.aim_style(eye, (top - eye).normalized())
	check(style_target.get("id") == chair and style_target.get("options") == DecorationLayout.options("floor"), "Style on an indoor piece offers the indoor table")
	var picked: Dictionary = main.delete_tool.aim(eye, (top - eye).normalized())
	check(picked.get("decoration") == chair, "delete picks the single indoor piece")
	var walls: int = main.world.state.walls.size()
	main.world.submit(FittingTool.removal(main.world.state, picked))
	check(not main.world.state.decorations.has(chair) and main.world.state.decorations.has(deck) and main.world.state.walls.size() == walls, "deleting one piece keeps the house and the rest")
	main.world.undo()
	check(main.world.state.decorations.has(chair), "undo restores the piece")

	main.world.submit({"op": "reshape", "of": "walls", "id": decked.id, "data": {"roof": {"pitch": 1.5}}})
	decked.lay_now()
	check(_node(deck) == null and main.world.state.decorations.has(deck), "a deck piece stands down while its roof is pitched")
	main.world.undo()
	decked.lay_now()
	check(_node(deck) != null, "and stands again on the flat deck")

	for mount in ["floor", "deck"]:
		for style in DecorationLayout.options(mount):
			var layout := DecorationLayout.new()
			layout.build(style, 0)
			print("furniture cost: %s %s solids=%d flames=%d flowers=%d reserved_quest2_us=%.1f" % [mount, DecorationLayout.STYLES[style].name, layout.parts.size(), layout.flames.size(), layout.flowers.size(), Budget.cost_ms(Budget.decoration(style), Budget.Device.QUEST_2) * 1000.0])
	var saved: Dictionary = main.world.snapshot()
	main.world.restore(saved)
	check(main.world.state.decorations.size() == 3, "save restore keeps furniture")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
