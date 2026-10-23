extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	# Fixture geometry exceeds capacity; test_budget covers the shared limit.
	main.world.bounded = false
	await play([{"op": "house", "at": [0, 0], "size": [6, 5], "seconds": 0.2}])
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	var f := w.layout.frame_at(2)
	var out: Vector3 = f.tangent.cross(Vector3.UP)
	var side := signf((f.point - w.roof.frame().mid).dot(out))
	out *= side
	var first := Vector3(2, 1.6, side)
	var other := Vector3(4, 1.6, side)
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"lanterns": PackedVector3Array([first, other])}})
	w.lay_now()
	var at: Vector3 = f.point + Vector3.UP * 1.6
	var eye: Vector3 = at + out * 3.0
	var id := w.id
	var tool: DeleteTool = main.delete_tool
	var target := tool.aim(eye, -out)
	check(not tool.aim(at - out * 12.0, out).has("fitting"), "the house body occludes the lamp on its far side")
	check(target.has("fitting"), "delete identifies the lamp rather than its house")
	await _capture("lamp-highlight", eye, -out, at)
	var body_eye: Vector3 = w.layout.frame_at(5).point + Vector3.UP * 1.6 + out * 3.0
	var body := tool.aim(body_eye, -out)
	check(body.get("wall") == w and not body.has("fitting"), "bare house body selects the house")
	check(tool.target_bounds(body).size.length() > tool.target_bounds(target).size.length() * 5, "hover extent distinguishes house from lamp")
	await _capture("house-highlight", body_eye, -out, at)
	tool.press(self, eye, -out)
	for i in 3:
		tool.hold(self, body_eye, -out)
	tool.let_go(self)
	await process_frame
	check(main.world.state.walls.has(id), "deleting a lamp leaves its house standing")
	if main.world.state.walls.has(id):
		check(main.world.state.walls[id].lanterns == PackedVector3Array([other]), "only the aimed lamp is deleted")
	if not main.world.state.walls.has(id):
		print("tests: FAILED %d" % failures)
		Main.quit(self, 1)
		return
	main.world.undo()
	w = main.tool.find(id)
	w.lay_now()
	check(w.layout.lanterns.size() == 2, "one undo restores the lamp")
	main.world.redo()
	w.lay_now()
	check(w.layout.lanterns == [other], "redo removes only that lamp")
	main.world.undo()
	w.lay_now()
	# A peer's delete travels through host validation and the same replicated reshape.
	var before: Dictionary = main.world.state.walls[id].duplicate(true)
	var cmd := FittingTool.removal(main.world.state, target)
	var accepted := Commands.clean(cmd, main.world.state, false)
	check(not accepted.is_empty(), "host accepts the single-fitting command")
	tool.press(self, eye, -out)
	main.world._order(cmd, 42)
	var seq: int = main.world.seq
	tool.let_go(self)
	check(main.world.seq == seq, "a peer taking the selected lamp does not retarget the held delete")
	w.lay_now()
	check(w.layout.lanterns == [other], "peer deletion changes one lamp")
	main.world._order({"op": "undo"}, 42)
	w.lay_now()
	check(main.world.state.walls[id] == before, "peer undo restores the exact house and fittings")
	tool.press(self, eye + Vector3.UP * 20, Vector3.UP)
	tool._stroke(tool._cuts[self], eye, -out)
	var other_eye: Vector3 = w.layout.frame_at(4).point + Vector3.UP * 1.6 + out * 3
	tool._stroke(tool._cuts[self], other_eye, -out)
	tool.let_go(self)
	w.lay_now()
	check(w.layout.lanterns.is_empty(), "a stroke combines two fitting removals on the same house")
	main.world.undo()
	w.lay_now()
	check(main.world.state.walls[id] == before, "one undo restores a multi-fitting stroke")
	await _other_fittings(w)
	tool.press(self, body_eye, -out)
	tool.let_go(self)
	check(not main.world.state.walls.has(id), "a body hit still removes the house")
	finish()


func _capture(name: String, eye: Vector3, dir: Vector3, at: Vector3) -> void:
	var hand: Hand = main.rig.right
	hand.tool = Hand.Tool.DELETE
	hand.held_still = true
	main.view(at - dir * 8.0 + Vector3.UP * 2.0, at, false)
	hand.global_transform = Transform3D(Basis.looking_at(dir), eye)
	for i in 6:
		await process_frame
	check(main.delete_tool._rings[1].visible, "live delete hover shows " + name)
	if not OS.get_environment("DELETE_CAPTURE").is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("DELETE_CAPTURE").path_join(name + ".png"))
	hand.tool = Hand.Tool.WALLS


func _other_fittings(w: Wall) -> void:
	main.world.submit({"op": "reshape", "of": "walls", "id": w.id, "data": {"openings": PackedVector4Array([Vector4(8, 1.5, 0, 1)]), "roof": {"chimneys": PackedVector2Array([Vector2(0, 1)])}}})
	w.lay_now()
	await _takes_kind(w, "opening")
	await _takes_kind(w, "chimney")
	await play([{"op": "wall", "points": [[-10, -8], [-2, -8]], "seconds": 0.2}])
	var wall: Wall = main.tool.walls[-1]
	main.world.submit({"op": "reshape", "of": "walls", "id": wall.id, "data": {"flags": PackedFloat32Array([2]), "openings": PackedVector4Array([5].map(WallLayout.archway))}})
	wall.lay_now()
	await _takes_kind(wall, "flag")
	await _takes_kind(wall, "opening")
	await play([{"op": "house", "at": [10, 6], "size": [4, 4], "round": true, "seconds": 0.2}])
	var tower: Wall = main.tool.walls[-1]
	main.world.submit({"op": "reshape", "of": "walls", "id": tower.id, "data": {"roof": {"flag": true}}})
	tower.lay_now()
	await _takes_kind(tower, "tower_flag")
	var flag: Dictionary = FittingTool.targets(tower).filter(func(t: Dictionary) -> bool: return t.what == "tower_flag")[0]
	var centre: Vector3 = flag.bounds.get_center()
	var origin := centre - Vector3.UP * 0.5
	check(main.delete_tool.aim(origin, Vector3.UP).get("what") == "tower_flag", "an upward ray hits the tower flag")
	check(not main.delete_tool.charge(self, origin, Vector3.UP, 0.1), "aiming upward at a fitting does not charge a garden wipe")
	main.delete_tool.cancel(self)
	main.world.submit({"op": "reshape", "of": "walls", "id": tower.id, "data": {"roof": {"thatch": true}}})
	tower.lay_now()
	var finial: Dictionary = tower.roof.tiles.filter(func(t: Dictionary) -> bool: return t.kind == "finial")[0]
	var pole_top: Vector3 = tower.transform * finial.xform.origin
	flag = FittingTool.targets(tower).filter(func(t: Dictionary) -> bool: return t.what == "tower_flag")[0]
	check(flag.bounds.has_point(pole_top), "a thatched tower's flag is picked round its pole's top at %s: %s" % [pole_top, flag.bounds])
	var pole: Dictionary = tower.roof.tiles.filter(func(t: Dictionary) -> bool: return t.kind == "pole")[0]
	var foot: Vector3 = pole.xform * Vector3(0, -0.5, 0)
	main.world.submit({"op": "reshape", "of": "walls", "id": tower.id, "data": {"roof": {"flag": false}}})
	tower.lay_now()
	var ghost: Dictionary = main.fitting_tool.ghost_of(flag, pole_top + Vector3(0, 0, 3), Vector3.FORWARD, pole_top)
	check(ghost.get("xform", Transform3D()).origin.distance_to(foot) < 0.05, "a thatched tower's flag ghost stands where its pole does: %s for %s" % [ghost.get("xform", Transform3D()).origin, foot])


func _takes_kind(w: Wall, kind: String) -> void:
	var items := FittingTool.targets(w).filter(func(t: Dictionary) -> bool: return t.what == kind)
	check(not items.is_empty(), "fixture has " + kind)
	if items.is_empty():
		return
	var item: Dictionary = items[0]
	var centre: Vector3 = item.bounds.get_center()
	var tool: DeleteTool = main.delete_tool
	var ray := Vector3.ZERO
	var origin := Vector3.ZERO
	for outward in [Vector3.UP, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var eye: Vector3 = centre + outward * 4.0
		var hit := tool.aim(eye, -outward)
		if hit.get("what") == kind and hit.get("wall") == w:
			ray = -outward
			origin = eye
			break
	check(ray != Vector3.ZERO, "a ray selects " + kind)
	if ray == Vector3.ZERO:
		return
	var before: Dictionary = main.world.state.walls[w.id].duplicate(true)
	var placement: Dictionary = main.fitting_tool.aim(Hand.Tool.WINDOWS if kind == "opening" else Hand.Tool.DECORATIONS, origin, ray)
	check(placement.get("what") == kind and placement.get("fitting", false), "placement and delete share " + kind + " identity")
	tool.press(self, origin, ray)
	tool.hold(self, origin, ray)
	tool.let_go(self)
	w.lay_now()
	check(FittingTool.targets(w).filter(func(t: Dictionary) -> bool: return t.what == kind).size() == items.size() - 1, "delete removes only " + kind)
	check(main.world.state.walls.has(w.id), kind + " leaves its wall")
	main.world.undo()
	w.lay_now()
	check(main.world.state.walls[w.id] == before, "undo restores exact state for " + kind)
