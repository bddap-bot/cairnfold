extends SceneTree

## Headless checks of the camera tool: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_photo.gd
## The shot itself needs a renderer; demo/photo.json takes photos on the desktop.

var failures := 0


func _initialize() -> void:
	Terrain.install()
	await process_frame
	await _the_screen_shows_the_lens_while_a_hand_holds_the_camera()
	await _the_lens_sees_the_players_own_avatar_and_their_eyes_do_not()
	_the_lens_turns_as_the_hand_turns_roll_included()
	_photos_move_out_of_the_app_without_losing_one()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


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


func _the_lens_sees_the_players_own_avatar_and_their_eyes_do_not() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	rig.wear(Avatar.open(Avatar.built_in(0), Color.RED))
	var meshes := rig.body.find_children("*", "VisualInstance3D", true, false)
	_check(not meshes.is_empty() and meshes.all(func(v: VisualInstance3D) -> bool: return v.layers == Rig.SELF_LAYER), "the player's own avatar is drawn on the camera's layer alone")
	_check(rig.head.cull_mask & Rig.SELF_LAYER == 0, "the player's eyes never see their own avatar")
	await process_frame
	_check(not rig.body.visible, "an avatar nobody photographs is not drawn")
	rig.head.position = Vector3(0.4, 1.6, 0.2)
	rig.right.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.6, 1.3, -0.4))
	rig.right.tool = Hand.Tool.CAMERA
	for i in PhotoTool.PREVIEW_EVERY:
		await process_frame
	var cam: Camera3D = tool._preview.get_child(0)
	_check(rig.body.visible and cam.cull_mask & Rig.SELF_LAYER != 0, "the lens sees the avatar while the camera is held")
	var seen: Vector3 = rig.body.bone("head") * (rig.body._model.get_meta("eyes") as Vector3)
	_check(seen.distance_to(rig.head.global_position) < 0.001, "the avatar's eyes are at the player's head")
	var holding := rig.body.bone("rightHand")
	_check(holding.origin.distance_to(rig.right.global_position) < 0.001, "and its hand holds the camera")
	_check(holding.basis.get_scale().x < 0.01 and rig.body.bone("leftHand").basis.get_scale().x > 0.9, "folded into its wrist, so no finger reaches in front of the lens")
	rig.wear(Avatar.open(Avatar.built_in(1), Color.RED))
	await process_frame
	_check(rig.body.visible and rig.find_children("*", "Avatar", false, false).size() == 1, "a newly worn avatar replaces the last")
	rig.right.tool = Hand.Tool.WALLS
	await process_frame
	_check(not rig.body.visible, "and goes when the camera is put away")
	rig.queue_free()
	tool.queue_free()


func _the_lens_turns_as_the_hand_turns_roll_included() -> void:
	var hand := Node3D.new()
	root.add_child(hand)
	for roll in [-90.0, -20.0, 0.0, 35.0, 90.0]:
		for pitch in [-89.0, -10.0, 0.0, 30.0, 89.0]:
			var b := Basis(Vector3.UP, 0.7) * Basis(Vector3.RIGHT, deg_to_rad(pitch)) * Basis(Vector3.BACK, deg_to_rad(roll))
			hand.global_transform = Transform3D(b, Vector3(1, 1.2, 3))
			var lens := PhotoTool.lens(hand)
			_check(lens.basis.is_equal_approx(b), "the lens turns with the hand at roll %d, pitch %d" % [roll, pitch])
			_check(lens.origin.is_equal_approx(hand.global_transform * (Hand.TOP + ToolModels.CAMERA_LENS)), "the lens sits on the camera at roll %d, pitch %d" % [roll, pitch])
	hand.free()


func _photos_move_out_of_the_app_without_losing_one() -> void:
	_check(Main.player_folder("photos") == PhotoTool.APP_PHOTOS, "off Android, photos stay in user://photos")
	var from := "user://test_photos_from"
	var to := "user://test_photos_to"
	DirAccess.make_dir_recursive_absolute(from)
	DirAccess.make_dir_recursive_absolute(to)
	for n in ["a.png", "b.png", "c.png"]:
		FileAccess.open(from.path_join(n), FileAccess.WRITE).store_string(n.repeat(1000))
	FileAccess.open(to.path_join("c.png"), FileAccess.WRITE).store_string("already here")
	FileAccess.open(from.path_join("d.png"), FileAccess.WRITE).store_string("moved once, its original left behind")
	FileAccess.open(to.path_join("d.png"), FileAccess.WRITE).store_string("moved once, its original left behind")
	FileAccess.open(to.path_join("a.png.part"), FileAccess.WRITE).store_string("a move cut short")
	_check(PhotoTool.move_all(from, to) == 3, "the photos the new folder lacks or already holds whole move")
	_check(FileAccess.get_file_as_string(to.path_join("a.png")) == "a.png".repeat(1000), "a moved photo keeps its bytes")
	_check(FileAccess.get_file_as_string(to.path_join("c.png")) == "already here", "a photo already there is not overwritten")
	_check(not FileAccess.file_exists(to.path_join("a.png.part")), "a move cut short is finished")
	_check(Array(DirAccess.get_files_at(from)) == ["c.png"], "and the one that could not move stays where it was")
	DirAccess.remove_absolute(from.path_join("c.png"))
	_check(PhotoTool.move_all(from, to) == 0 and not DirAccess.dir_exists_absolute(from), "an emptied folder is removed")
	_check(PhotoTool.move_all(from, to) == 0, "and moving from a missing folder moves nothing")
	for n in DirAccess.get_files_at(to):
		DirAccess.remove_absolute(to.path_join(n))
	DirAccess.remove_absolute(to)
