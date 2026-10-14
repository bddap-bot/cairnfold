extends SceneTree

## Headless checks of the camera tool: godot4 --headless --path game --script ../tests/test_photo.gd
## The shot itself needs a renderer; demo/photo.json takes photos on the desktop.

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	await _the_screen_rides_the_hand_holding_the_camera()
	_the_lens_looks_where_the_hand_points_with_a_level_horizon()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	quit(1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _the_screen_rides_the_hand_holding_the_camera() -> void:
	_check(Hand.MENU.has(Hand.Tool.CAMERA), "the camera is in the ring")
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	await process_frame
	_check(tool.holder() == null and not tool._screen.visible, "no screen while no hand holds the camera")
	rig.right.tool = Hand.Tool.CAMERA
	await process_frame
	_check(tool.holder() == rig.right and tool._screen.get_parent() == rig.right and tool._screen.visible, "the screen shows on the hand holding the camera")
	_check(tool._preview.render_target_update_mode != SubViewport.UPDATE_ALWAYS, "the preview never redraws every frame")
	rig.right.tool = Hand.Tool.WALLS
	rig.left.tool = Hand.Tool.CAMERA
	await process_frame
	_check(tool._screen.get_parent() == rig.left and tool._screen.visible, "and moves to the other hand when it takes the camera")
	rig.left.picking = true
	await process_frame
	_check(not tool._screen.visible, "and hides while that hand picks from its ring")
	rig.left.picking = false
	rig.left.tool = Hand.Tool.FLOWERS
	await process_frame
	_check(not tool._screen.visible, "and goes when the camera is put away")


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
	hand.global_transform = Transform3D(Basis(), Vector3.ZERO)
	_check(PhotoTool.lens(hand).origin.z < PhotoTool.SCREEN_AT.z, "the lens sits in front of the screen")
