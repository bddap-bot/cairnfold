extends SceneTree

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


func _run() -> void:
	main.world.bounded = false
	var driver := Driver.new(main, [{"op": "house", "at": [0, 0], "size": [8, 6], "seconds": 0.2}])
	main.add_child(driver)
	await driver.finished
	driver.queue_free()
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	for style in DecorationLayout.STYLES.size():
		var layout := DecorationLayout.new()
		layout.build(style, 53)
		check(not layout.parts.is_empty() and layout.bounds.size.length() > 0.0, "geometry %d" % style)
		print("decoration cost: %s solids=%d triangles=%d flowers=%d flames=%d" % [DecorationLayout.STYLES[style].name, layout.parts.size(), layout.parts.size() * 108 + layout.flames.size() * 14, layout.flowers.size(), layout.flames.size()])
	for style in 9:
		var f := w.layout.frame_at(0.5 + style * 0.9)
		var side := signf((f.point - w.roof.frame().mid).dot(f.tangent.cross(Vector3.UP)))
		var foundation := style < 7
		var target := {"what": "decoration", "mount": "foundation" if foundation else "ground", "wall": w if foundation else null, "s": 0.5 + style * 0.9, "side": side, "point": f.point if foundation else Vector3(12 + style, 0, 12), "style": style}
		check(main.fitting_tool.fit(target), "place %d" % style)
	main.world.decorations.sync()
	check(main.world.state.decorations.size() == 9, "all styles saved")
	check(main.world.decorations.nodes.size() == 9, "all styles rendered")
	var snapshot: Array = main.world.snapshot().cmds
	check(snapshot.filter(func(c): return c.op == "decoration").size() == 9, "snapshot carries styles and seeds")
	for item in main.world.decorations.targets():
		var cmd := FittingTool.removal(main.world.state, item)
		check(cmd.op == "undecoration", "single removal identity")
		var before: Dictionary = main.world.state.decorations[item.decoration].duplicate()
		main.world.submit(cmd)
		check(main.world.state.decorations.size() == 8 and main.world.state.walls.size() == 1, "single deletion preserves house and siblings")
		main.world.undo()
		check(main.world.state.decorations.get(item.decoration) == before, "undo restores exact style and seed")
	var p := Vector3(30, Terrain.height_at(30, 30), 30)
	var aim: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, p + Vector3.UP * 3, Vector3.DOWN)
	check(aim.get("what") == "decoration" and aim.get("wall") == null, "bare ground accepts decorations")
	var cmd := FittingTool.decoration_command(aim)
	check(cmd.style == DecorationLayout.PRESENT and cmd.mount == "ground", "a present by default on bare ground")
	check(cmd == FittingTool.decoration_command(aim), "placement choice stable while aiming")
	var bad := cmd.duplicate()
	bad.mount = "floor"
	check(Commands.clean(bad, main.world.state, false).is_empty(), "reject a house's mount without its house")
	main.world.decorations.sync()
	for item in main.world.decorations.targets():
		var centre: Vector3 = item.bounds.get_center()
		var origin := centre + Vector3(0, 0, 4)
		var near: Dictionary = main.tool.pick_building(origin, (centre - origin).normalized())
		var picked := FittingTool.pick_target(main.tool, origin, (centre - origin).normalized())
		check(picked.get("along", INF) <= near.get("along", INF) + 0.001, "decoration refinement never skips nearer building")
	var items: Array[Dictionary] = main.world.decorations.targets()
	var post: Dictionary = items.filter(func(i): return i.value.style == 6)[0]
	var post_at: Vector3 = post.bounds.get_center()
	var frame := w.layout.frame_at(post.value.s)
	var normal: Vector3 = frame.tangent.cross(Vector3.UP) * post.value.side
	var outside := post_at + normal * 3.0
	check(FittingTool.pick_target(main.tool, outside, -normal).get("decoration") == post.decoration, "foundation fitting picked from outside")
	var blocked := FittingTool.pick_target(main.tool, post_at - normal * 15.0, normal)
	check(not blocked.has("decoration") and blocked.get("wall") == w, "near wall blocks far foundation decoration")
	var above := post_at - normal * 3.0 + Vector3.UP * 10.0
	var down := (post_at - above).normalized()
	check(main.tool.pick_building(above, down).get("surface") == "roof", "occlusion ray crosses the roof")
	var roof_blocked := FittingTool.pick_target(main.tool, above, down)
	check(roof_blocked.get("surface") == "roof", "near roof blocks foundation decoration below")
	var foundation_style: Dictionary = main.palette_tool.aim_style(outside, -normal)
	check(foundation_style.get("options") == range(DecorationLayout.STYLES.size()), "foundation Style wheel lists every style")
	var torch: Dictionary = items.filter(func(i): return i.value.style == 7)[0]
	var at: Vector3 = torch.bounds.get_center()
	var eye := at + Vector3(0, 0, 3)
	var picked: Dictionary = main.delete_tool.aim(eye, Vector3.FORWARD)
	check(picked.get("decoration") == torch.decoration, "ground torch shares delete picker")
	var style_target: Dictionary = main.palette_tool.aim_style(eye, Vector3.FORWARD)
	check(style_target.get("options") == range(DecorationLayout.STYLES.size()), "Style wheel lists every style")
	main.palette_tool.open(main.rig.right, style_target)
	main.palette_tool.wheels[main.rig.right].pick = 8
	main.palette_tool.close(main.rig.right)
	check(main.world.state.decorations[torch.decoration].style == 8, "Style changes only chosen torch to campfire")
	main.world.undo()
	check(main.world.state.decorations[torch.decoration].style == 7, "restyle undo")
	main.delete_tool.press(self, eye, Vector3.FORWARD)
	main.delete_tool.let_go(self)
	check(not main.world.state.decorations.has(torch.decoration) and main.world.state.walls.size() == 1, "delete tool removes only the ground torch")
	main.world.undo()
	main.world.submit({"op": "unwall", "ids": PackedInt32Array([w.id])})
	check(main.world.state.decorations.size() == 2, "house deletion removes its attached decorations")
	main.world.undo()
	check(main.world.state.decorations.size() == 9, "house undo restores attached styles")
	var saved: Dictionary = main.world.snapshot()
	main.world.restore(saved)
	check(main.world.state.decorations.size() == 9, "save restore keeps all nine styles")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
