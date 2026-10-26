extends "res://../tests/support/suite.gd"

var terrain: Terrain:
	get:
		return main.world.terrain


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	main.world.bounded = false
	await play([{"op": "house", "at": [0, 0], "size": [8, 6], "seconds": 0.2}])
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	for style in DecorationLayout.standing("ground"):
		var layout := DecorationLayout.new()
		layout.build(style, 53)
		check(not layout.parts.is_empty() and layout.bounds.size.length() > 0.0, "geometry %d" % style)
		print("decoration cost: %s solids=%d triangles=%d flowers=%d flames=%d" % [DecorationLayout.STYLES[style].name, layout.parts.size(), layout.parts.size() * 108 + layout.flames.size() * 14, layout.flowers.size(), layout.flames.size()])
	var stool := DecorationLayout.new()
	stool.build(DecorationLayout.STYLES.map(func(st: Dictionary) -> String: return st.name).find("Stool"), 0)
	for leg: Dictionary in stool.parts.slice(1):
		var x: Transform3D = leg.xform
		var top := x * Vector3(0, 0.5, 0)
		var foot := x * Vector3(0, -0.5, 0)
		check(Vector2(foot.x, foot.z).length() > Vector2(top.x, top.z).length(), "a stool's legs splay out to their feet")
	var present := DecorationLayout.new()
	present.build(DecorationLayout.PRESENT, 0)
	check(present.pictures.size() == 1, "a present carries a picture")
	var wand := ToolModels.build(Hand.Tool.STYLE)
	var pieces: Array[MeshInstance3D] = []
	pieces.assign(wand.find_children("*", "MeshInstance3D", true, false))
	var drawn := ToolModels.picture(Hand.Tool.STYLE).surface_get_arrays(0)
	var reached := {}
	for i: int in drawn[Mesh.ARRAY_INDEX]:
		reached[i] = true
	check(drawn[Mesh.ARRAY_VERTEX].size() == pieces.reduce(func(n: int, m: MeshInstance3D) -> int: return n + m.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 0) and reached.size() == drawn[Mesh.ARRAY_VERTEX].size(), "the picture draws every piece of the wand")
	var tinted := func(m: MeshInstance3D) -> bool:
		var want := (m.material_override as BaseMaterial3D).albedo_color
		return Array(drawn[Mesh.ARRAY_COLOR]).any(func(c: Color) -> bool: return Vector4(c.r - want.r, c.g - want.g, c.b - want.b, 0).length() < 0.01)
	check(pieces.all(tinted), "the picture takes the wand's own colours")
	wand.free()
	for style in 9:
		var f := w.layout.frame_at(0.5 + style * 0.9)
		var side := signf((f.point - w.roof.frame().mid).dot(f.tangent.cross(Vector3.UP)))
		var foundation := style < 7
		var target := {"what": "decoration", "mount": "foundation" if foundation else "ground", "wall": w if foundation else null, "s": 0.5 + style * 0.9, "side": side, "point": f.point if foundation else Vector3(12 + style, 0, 12), "style": style}
		check(main.fitting_tool.fit(target), "place %d" % style)
	main.world.decorations.sync()
	check(main.world.state.decorations.size() == 9, "all styles saved")
	check(main.world.decorations.placed.size() == 9, "all styles rendered")
	check(main.world.decorations._batches.size() == 2, "the house's decorations are one batch, the ground's in one cell another: %d" % main.world.decorations._batches.size())
	var snapshot: Array = main.world.snapshot().cmds
	check(snapshot.filter(func(c): return c.op == "decoration").size() == 9, "snapshot carries styles and seeds")
	for item in main.world.decorations.targets():
		var cmd := FittingTool.removal(main.world.state, item)
		check(cmd.op == "take" and cmd.of == "decorations", "single removal identity")
		var before: Dictionary = main.world.state.decorations[item.decoration].duplicate()
		main.world.submit(cmd)
		check(main.world.state.decorations.size() == 8 and main.world.state.walls.size() == 1, "single deletion preserves house and siblings")
		main.world.undo()
		check(main.world.state.decorations.get(item.decoration) == before, "undo restores exact style and seed")
	var p := Vector3(30, terrain.height_at(30, 30), 30)
	var aim: Dictionary = main.fitting_tool.aim(Hand.Tool.DECORATIONS, p + Vector3.UP * 3, Vector3.DOWN)
	check(aim.get("what") == "decoration" and aim.get("wall") == null, "bare ground accepts decorations")
	var cmd := FittingTool.decoration_command(aim)
	check(cmd.style == DecorationLayout.PRESENT and cmd.mount == "ground", "a present by default on bare ground")
	var bad := cmd.duplicate()
	bad.mount = "floor"
	check(Commands.clean(bad, main.world.state, false, main.world.terrain).is_empty(), "reject a house's mount without its house")
	main.world.decorations.sync()
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
	check(foundation_style.get("options") == DecorationLayout.standing("foundation"), "foundation Style wheel lists every style but the strings")
	var torch: Dictionary = items.filter(func(i): return i.value.style == 7)[0]
	var at: Vector3 = torch.bounds.get_center()
	var eye := at + Vector3(0, 0, 3)
	var picked: Dictionary = main.delete_tool.aim(eye, Vector3.FORWARD)
	check(picked.get("decoration") == torch.decoration, "ground torch shares delete picker")
	var style_target: Dictionary = main.palette_tool.aim_style(eye, Vector3.FORWARD)
	check(style_target.get("options") == DecorationLayout.standing("ground"), "Style wheel lists every style but the strings")
	main.palette_tool.open(main.rig.right, style_target)
	main.palette_tool.wheels[main.rig.right].pick = 8
	main.palette_tool.close(main.rig.right)
	check(main.world.state.decorations[torch.decoration].style == 8, "Style changes only chosen torch to campfire")
	main.world.undo()
	check(main.world.state.decorations[torch.decoration].style == 7, "restyle undo")
	var swept: int = Cues.asked.get(Cues.Act.DELETE_SWEEP, 0)
	var aside := Vector3.FORWARD.rotated(Vector3.UP, 0.6)
	main.delete_tool.press(self, eye, aside)
	main.delete_tool.hold(self, eye, Vector3.FORWARD)
	var alone := [str(torch.decoration), torch.value.lantern]
	check(main.delete_tool._cuts[self].decorations.has(torch.decoration), "a delete sweep takes the ground torch")
	check(Cues.asked.get(Cues.Act.DELETE_SWEEP, 0) > swept and not main.world.decorations._batches[alone].node.visible, "taking it sounds and hides it while the sweep goes on")
	main.world.decorations._stamp.clear()
	main.world.decorations.sync()
	check(not main.world.decorations._batches[alone].node.visible, "it stays hidden when the decorations are laid again mid-sweep")
	check(main.delete_tool.hold(self, eye, Vector3.FORWARD).get("decoration") != torch.decoration, "and the beam passes through it")
	var kept: Dictionary = main.world.snapshot()
	main.world.restore(kept)
	main.world.decorations.sync()
	check(not main.world.decorations._batches.has(alone) and main.world.decorations.placed.has(torch.decoration) and main.delete_tool._cuts.is_empty(), "a garden restored mid-sweep shows the torch again")
	main.delete_tool.press(self, eye, aside)
	main.delete_tool.hold(self, eye, Vector3.FORWARD)
	main.delete_tool.let_go(self)
	check(not main.world.state.decorations.has(torch.decoration) and main.world.state.walls.size() == 1, "delete tool removes only the ground torch")
	main.world.undo()
	main.world.submit({"op": "take", "of": "walls", "ids": PackedInt32Array([w.id])})
	check(main.world.state.decorations.size() == 2, "house deletion removes its attached decorations")
	main.world.undo()
	check(main.world.state.decorations.size() == 9, "house undo restores attached styles")
	var saved: Dictionary = main.world.snapshot()
	main.world.restore(saved)
	check(main.world.state.decorations.size() == 9, "save restore keeps all nine styles")
	await _the_preview_is_what_a_press_places(p)
	await _on_a_build()
	finish()


func _on_a_build() -> void:
	var driver := Driver.new(main, [
		{"op": "house", "at": [30, -30], "size": [9, 7], "seconds": 0.2},
		{"op": "roof", "index": -1, "pitch": 0},
		{"op": "house", "at": [30, -30], "size": [4, 3], "seconds": 0.2, "on": true},
	])
	main.add_child(driver)
	await driver.finished
	driver.queue_free()
	var upper: Wall = main.tool.walls[-1]
	upper.lay_now()
	var f := upper.layout.frame_at(1.5)
	var side := signf((f.point - upper.roof.frame().mid).dot(f.tangent.cross(Vector3.UP)))
	check(main.fitting_tool.fit({"what": "decoration", "mount": "foundation", "wall": upper, "s": 1.5, "side": side, "point": f.point, "style": 5}), "steps at the foot of a house on a deck")
	main.world.decorations.sync()
	var steps: Dictionary = main.world.state.decorations.values().filter(func(d: Dictionary) -> bool: return d.wall == upper.id)[0]
	var x: Transform3D = main.world.decorations.frame(steps)
	check(x.origin.y > f.point.y - 0.5, "a decoration at the foot of a house on a deck stands on the deck, at %.2f under a foot at %.2f" % [x.origin.y, f.point.y])
	check(main.world.decorations.rise(steps) < 0.5, "its steps rise only to the storey's foot, not from the ground: %.2f" % main.world.decorations.rise(steps))


func _the_preview_is_what_a_press_places(p: Vector3) -> void:
	var hand := main.rig.right
	var i := main.rig.hands.find(hand)
	hand.tool = Hand.Tool.DECORATIONS
	hand.global_transform = Transform3D(Basis.looking_at(Vector3(0, -1, -1), Vector3.UP), p + Vector3(0, 1.5, 1.5))
	hand.held_still = true
	await frames(2)
	var shown: Array = main.fitting_tool._ghosts[i].decoration.get_meta(&"shape")
	await frames(10)
	check(main.fitting_tool._ghosts[i].decoration.get_meta(&"shape") == shown, "the preview holds still while aiming")
	var before: Dictionary = main.world.state.decorations.duplicate()
	Buttons.injected["right_hand/trigger_click"] = true
	await frames(2)
	Buttons.injected.erase("right_hand/trigger_click")
	await frames(2)
	await until(func() -> bool: return main.world.idle(), "the press is applied")
	var placed: Array = main.world.state.decorations.keys().filter(func(id: int) -> bool: return not before.has(id))
	check(placed.size() == 1 and main.world.state.decorations[placed[0]].seed == shown[1], "a press places the decoration its preview showed")
