extends SceneTree

## Headless checks of the camera tool: godot4 --headless --path game --script ../tests/test_photo.gd
## The shot itself needs a renderer; demo/photo.json takes photos on the desktop.

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	await _the_screen_shows_the_lens_while_a_hand_holds_the_camera()
	_the_lens_looks_where_the_hand_points_with_a_level_horizon()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _screen_shows(tool: PhotoTool) -> bool:
	return tool._preview != null and ToolModels.camera_screen().albedo_texture == tool._preview.get_texture()


func _the_screen_shows_the_lens_while_a_hand_holds_the_camera() -> void:
	_check(ToolWheel.paths(Hand.TREE).has(Hand.Tool.CAMERA), "the camera is on the wheel")
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	await process_frame
	_check(tool.holders().is_empty() and tool._preview == null and tool._photo == null, "no view is rendered for a camera nobody holds")
	_check(ToolModels.camera_screen().albedo_texture == null, "an unheld camera's screen is dark")
	rig.right.tool = Hand.Tool.CAMERA
	var drawn := 0
	for i in PhotoTool.PREVIEW_EVERY * 4:
		await process_frame
		drawn += int(tool._preview.render_target_update_mode == SubViewport.UPDATE_ONCE)
		tool._preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_check(_screen_shows(tool), "the screen shows the lens's view while the camera is held")
	_check(drawn == 4, "the preview is drawn on one frame in %d: %d of %d" % [PhotoTool.PREVIEW_EVERY, drawn, PhotoTool.PREVIEW_EVERY * 4])
	rig.left.tool = Hand.Tool.CAMERA
	await process_frame
	_check(tool.holders().size() == 2, "both hands can hold a camera")
	rig.right.tool = Hand.Tool.WALLS
	rig.left.picking = true
	await process_frame
	_check(tool.holders().is_empty() and ToolModels.camera_screen().albedo_texture == null, "the screen goes dark while the hand holding it picks from its wheel")
	rig.left.picking = false
	await process_frame
	_check(_screen_shows(tool), "and shows the view again after")
	rig.left.tool = Hand.Tool.FLOWERS
	await process_frame
	_check(ToolModels.camera_screen().albedo_texture == null, "and goes dark when the camera is put away")


func _the_lens_looks_where_the_hand_points_with_a_level_horizon() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	var worst := 0.0
	for roll in [-60.0, -20.0, 0.0, 35.0, 80.0]:
		for pitch in [-50.0, -10.0, 0.0, 30.0]:
			var b := Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.BACK, deg_to_rad(roll))
			hand.global_transform = Transform3D(b, Vector3(1, 1.2, 3))
			var lens := PhotoTool.lens(hand)
			worst = maxf(worst, (-lens.basis.z).angle_to(-b.z))
			_check(absf(lens.basis.x.y) < 1e-4, "the horizon is level at roll %d, pitch %d" % [roll, pitch])
			_check(lens.basis.y.y > 0.0, "the lens is upright at roll %d, pitch %d" % [roll, pitch])
	_check(worst < 1e-4, "the lens looks along the hand's aim, off by %.5f rad" % worst)
	var jump := 0.0
	for roll in [-80.0, -30.0, 0.0, 30.0, 80.0]:
		for side in [-1.0, 1.0]:
			var last := Vector3.ZERO
			for step in 21:
				var pitch: float = side * (70.0 + step)
				hand.global_transform = Transform3D(Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.BACK, deg_to_rad(roll)), Vector3.ZERO)
				var up := PhotoTool.lens(hand).basis.y
				if step > 0:
					jump = maxf(jump, rad_to_deg(up.angle_to(last)))
				last = up
	_check(jump < 30.0, "turned toward straight up or down, the frame turns without a jump, at most %.1f° a degree" % jump)
