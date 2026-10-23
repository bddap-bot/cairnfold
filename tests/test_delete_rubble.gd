extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	var d := Driver.new(main, [{"op": "wall", "points": [[-8, 0], [8, 0]], "seconds": 0.2}])
	main.add_child(d)
	await d.finished
	d.queue_free()
	var w: Wall = main.tool.walls[0]
	w.lay_now()
	var id := w.id
	var tool: DeleteTool = main.delete_tool
	var at := w.layout.point_at(w.layout.length() * 0.5) + Vector3.UP
	tool.press(self, at + Vector3(-1, 0, 4), Vector3.FORWARD)
	tool.hold(self, at + Vector3(1, 0, 4), Vector3.FORWARD)
	tool.let_go(self)
	w.lay_now()
	check(main.world.state.walls.has(id) and not w.layout.ruins.is_empty(), "standing wall delete retains partial teardown")
	var before: Dictionary = main.world.state.walls[id].duplicate(true)
	var rubble := w.layout.stones.filter(func(st: Dictionary) -> bool: return st.kind == "rubble")
	check(not rubble.is_empty(), "partial teardown makes fallen stones")
	if rubble.is_empty():
		finish()
		return
	var stone: Dictionary = rubble[0]
	var eye: Vector3 = stone.xform.origin + Vector3.UP * 3
	var target := tool.aim(eye, Vector3.DOWN)
	check(target.get("rubble", false) and target.get("wall") == w, "the beam identifies fallen stones and their owner")
	check(tool.target_bounds(target) == w.pick_bounds, "rubble highlights the whole wall")
	await _capture("01-partial", w, eye, false)
	await _capture("02-rubble-highlight", w, eye, true)
	var seq: int = main.world.seq
	tool.press(self, eye, Vector3.DOWN)
	tool.hold(self, at + Vector3(0, 0, 4), Vector3.FORWARD)
	tool.let_go(self)
	check(not main.world.state.walls.has(id), "rubble deletes the whole wall even when held ray moves")
	check(main.world.seq == seq + 1, "rubble removal is one command")
	await _capture("03-removed", null, eye, true)
	main.world.undo()
	check(main.world.state.walls.get(id) == before, "one undo restores the exact ruined wall")
	w = main.tool.find(id)
	w.lay_now()
	var upright := w.layout.point_at(2.0) + Vector3.UP
	var standing := tool.aim(upright + Vector3(0, 0, 4), Vector3.FORWARD)
	check(standing.get("wall") == w and not standing.get("rubble", false), "standing stones on a ruined wall remain a partial target")
	var gap: Vector3 = stone.xform.origin + Vector3.UP * 1.5
	check(w.ray_hit(gap + Vector3(0, 0, 4), Vector3.FORWARD).is_empty(), "the ruined gap does not retain an invisible full-height body")
	main.world.redo()
	check(not main.world.state.walls.has(id), "redo removes the whole wall")
	main.world.undo()
	w = main.tool.find(id)
	w.lay_now()
	tool.press(self, eye, Vector3.DOWN)
	var cmd := {"op": "take", "of": "walls", "ids": PackedInt32Array([id])}
	check(not Commands.clean(cmd, main.world.state, false).is_empty(), "host accepts rubble removal through an existing take")
	main.world._order(cmd, 42)
	await process_frame
	await process_frame
	seq = main.world.seq
	check(tool.hold(self, eye, Vector3.DOWN).is_empty(), "peer removal clears the held hover target")
	tool.let_go(self)
	check(main.world.seq == seq, "peer removal during held delete does not retarget or add a command")
	main.world._order({"op": "undo"}, 42)
	check(main.world.state.walls.get(id) == before, "peer undo restores the exact ruined wall")
	finish()

func _capture(label: String, w: Wall, eye: Vector3, highlight: bool) -> void:
	if OS.get_environment("RUBBLE_CAPTURE").is_empty():
		return
	main.view(Vector3(7, 5, 10), Vector3(0, 1, 0), false)
	main.rig.right.tool = Hand.Tool.DELETE if highlight else Hand.Tool.NONE
	main.rig.right.held_still = true
	main.rig.right.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), eye)
	if w != null:
		w.lay_now()
	for frame in 8:
		await process_frame
	if highlight and w != null:
		check(main.delete_tool._rings[1].visible, "live rubble hover shows whole-wall highlight")
		check(main.rig.right.aiming(), "live rubble hover shows the sight")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("RUBBLE_CAPTURE").path_join(label + ".png"))
