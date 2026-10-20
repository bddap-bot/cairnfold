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
	await _the_selfie_camera_looks_back_at_its_holder()
	_player_data_lives_outside_the_app()
	_a_photo_is_drawn_whole_and_the_headset_as_the_ladder_allows()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _screen_shows(tool: PhotoTool, hand: Hand) -> bool:
	return tool._previews.has(hand) and PhotoTool.screen(hand, hand.tool).albedo_texture == tool._previews[hand].get_texture()


func _dark(hand: Hand) -> bool:
	return PhotoTool.CAMERAS.all(func(t: Hand.Tool) -> bool: return PhotoTool.screen(hand, t).albedo_texture == null)


func _the_screen_shows_the_lens_while_a_hand_holds_the_camera() -> void:
	_check(ToolWheel.paths(Hand.TREE).has(Hand.Tool.CAMERA), "the camera is on the wheel")
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	await process_frame
	_check(tool.holders().is_empty() and tool._previews.is_empty() and tool._photo == null, "no view is rendered for a camera nobody holds")
	_check(_dark(rig.right) and _dark(rig.left), "an unheld camera's screen is dark")
	rig.right.tool = Hand.Tool.CAMERA
	var drawn := 0
	for i in PhotoTool.PREVIEW_EVERY * 4:
		await process_frame
		drawn += int(tool._previews[rig.right].render_target_update_mode == SubViewport.UPDATE_ONCE)
		tool._previews[rig.right].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_check(_screen_shows(tool, rig.right), "the screen shows the lens's view while the camera is held")
	_check(drawn == 4, "the preview is drawn on one frame in %d: %d of %d" % [PhotoTool.PREVIEW_EVERY, drawn, PhotoTool.PREVIEW_EVERY * 4])
	_the_lens_sees_as_far_as_the_eye(rig, tool)
	rig.left.tool = Hand.Tool.CAMERA
	rig.left.position = Vector3(-0.3, 1.2, -0.3)
	rig.right.position = Vector3(0.3, 1.2, -0.3)
	rig.right.rotation = Vector3(0, PI * 0.5, 0)
	var drawn_on := {rig.left: [], rig.right: []}
	for i in PhotoTool.PREVIEW_EVERY * 2:
		await process_frame
		for h in drawn_on:
			if tool._previews[h].render_target_update_mode == SubViewport.UPDATE_ONCE:
				drawn_on[h].append(i)
			tool._previews[h].render_target_update_mode = SubViewport.UPDATE_DISABLED
	_check(tool.holders().size() == 2, "both hands can hold a camera")
	_check(_screen_shows(tool, rig.left) and _screen_shows(tool, rig.right) and PhotoTool.screen(rig.left, Hand.Tool.CAMERA) != PhotoTool.screen(rig.right, Hand.Tool.CAMERA), "each camera's screen shows its own preview")
	_check(tool._previews[rig.left].get_texture() != tool._previews[rig.right].get_texture(), "and the two previews are two textures")
	var left_cam: Camera3D = tool._previews[rig.left].get_child(0)
	var right_cam: Camera3D = tool._previews[rig.right].get_child(0)
	_check(left_cam.global_transform.is_equal_approx(PhotoTool.lens(rig.left)) and right_cam.global_transform.is_equal_approx(PhotoTool.lens(rig.right)), "each drawn from its own lens")
	_check(drawn_on[rig.left].size() == 2 and drawn_on[rig.right].size() == 2 and drawn_on[rig.left].all(func(f: int) -> bool: return not f in drawn_on[rig.right]), "on frames of their own: %s" % [drawn_on])
	rig.right.tool = Hand.Tool.WALLS
	await process_frame
	_check(_dark(rig.right) and _screen_shows(tool, rig.left), "putting one camera away darkens its screen alone")
	rig.left.picking = true
	await process_frame
	_check(tool.holders().is_empty() and _dark(rig.left), "the screen goes dark while the hand holding it picks from its wheel")
	rig.left.picking = false
	await process_frame
	_check(_screen_shows(tool, rig.left), "and shows the view again after")
	rig.left.tool = Hand.Tool.FLOWERS
	await process_frame
	_check(_dark(rig.left), "and goes dark when the camera is put away")


func _the_lens_sees_as_far_as_the_eye(rig: Rig, tool: PhotoTool) -> void:
	var at := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	rig.head.global_transform = at
	var photo := tool._viewport(PhotoTool.PHOTO_SIZE, Viewport.MSAA_4X)
	var far := 0.0
	for d in range(10, 2000, 10):
		if rig.head.is_position_in_frustum(at * Vector3(0, 0, -d)):
			far = d
	_check(far > 100.0, "the eye sees past the meadow: %d m" % far)
	for lens: SubViewport in [tool._previews[rig.right], photo]:
		var cam: Camera3D = lens.get_child(0)
		cam.global_transform = at
		var dropped := []
		for d in range(10, int(far) + 1, 10):
			if not cam.is_position_in_frustum(at * Vector3(0, 0, -d)):
				dropped.append(d)
		_check(dropped.is_empty(), "the %s shows what the eye sees out to %d m; it drops %s m" % [lens.size, far, dropped])
	photo.queue_free()


func _the_lens_sees_the_players_own_avatar_and_their_eyes_do_not() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	rig.wear(Avatar.open(Avatar.built_in(0), Color.RED))
	var meshes := rig.body.find_children("*", "VisualInstance3D", true, false)
	_check(not meshes.is_empty() and meshes.all(func(v: VisualInstance3D) -> bool: return v.layers == Rig.SELF_LAYER), "the player's own avatar is drawn on the camera's layer alone")
	_check(rig.head.cull_mask & Rig.SELF_LAYER == 0, "the player's eyes never see their own avatar")
	var icons := rig.right.find_children("*", "VisualInstance3D", true, false).filter(func(v: VisualInstance3D) -> bool: return v.layers & Rig.WHEEL_LAYER)
	_check(not icons.is_empty() and rig.head.cull_mask & Rig.WHEEL_LAYER != 0 and Rig.WHEEL_LAYER & Rig.SELF_LAYER == 0, "while they still see the tool wheel, which has a layer of its own")
	var wheel_light: DirectionalLight3D = rig.right.find_children("*", "DirectionalLight3D", true, false)[0]
	_check(wheel_light.light_cull_mask & Rig.SELF_LAYER == 0, "and whose light never lights their avatar")
	rig.head.position = Vector3(0.4, 1.6, 0.2)
	rig.right.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.6, 1.3, -0.4))
	rig.right.tool = Hand.Tool.CAMERA
	for i in PhotoTool.PREVIEW_EVERY:
		await process_frame
	var cam: Camera3D = tool._previews[rig.right].get_child(0)
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


func _the_selfie_camera_looks_back_at_its_holder() -> void:
	var paths := ToolWheel.paths(Hand.TREE)
	_check(paths[Hand.Tool.SELFIE].size() == 3 and paths[Hand.Tool.SELFIE].slice(0, -1) == paths[Hand.Tool.CAMERA].slice(0, -1), "the selfie camera opens from the camera's own entry on the wheel: %s, %s" % [paths[Hand.Tool.SELFIE], paths[Hand.Tool.CAMERA]])
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	rig.wear(Avatar.open(Avatar.built_in(0), Color.RED))
	rig.head.position = Vector3(0, 1.6, 0)
	rig.right.transform = Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0.15, 1.5, -0.55))
	rig.right.tool = Hand.Tool.SELFIE
	for i in PhotoTool.PREVIEW_EVERY:
		await process_frame
	var lens := PhotoTool.lens(rig.right)
	var to_head := (rig.head.global_position - lens.origin).normalized()
	_check(to_head.dot(-lens.basis.z) > 0.8, "held out, its lens looks back at the holder's head: %.2f" % to_head.dot(-lens.basis.z))
	_check(lens.basis.y.dot(rig.right.global_basis.y) > 0.999, "its view is upright as the camera is")
	var cam: Camera3D = tool._previews[rig.right].get_child(0)
	_check(_screen_shows(tool, rig.right) and cam.global_transform.is_equal_approx(lens), "its screen shows what its lens sees")
	_check(rig.body.visible and cam.cull_mask & Rig.SELF_LAYER != 0 and cam.is_position_in_frustum(rig.body.bone("head").origin), "which is the holder's own avatar, head and all")
	var near := []
	for v: VisualInstance3D in rig.find_children("*", "VisualInstance3D", true, false):
		if v.is_visible_in_tree() and v.layers & cam.cull_mask and not rig.body.is_ancestor_of(v):
			var a := v.get_aabb()
			for c in 8:
				if cam.is_position_in_frustum(v.global_transform * a.get_endpoint(c)):
					near.append(v.name)
					break
	_check(near.is_empty(), "nothing on the controller lies in the lens's view: %s" % [near])
	var screen := PhotoTool.screen(rig.right, Hand.Tool.SELFIE)
	_check(screen.uv1_scale.x == -1.0 and screen.uv1_offset.x == 1.0, "shown as a mirror would")
	rig.right.tool = Hand.Tool.CAMERA
	await process_frame
	screen = PhotoTool.screen(rig.right, Hand.Tool.CAMERA)
	_check(_screen_shows(tool, rig.right) and screen.uv1_scale == Vector3.ONE and screen.uv1_offset == Vector3.ZERO, "and the camera's own screen is not mirrored")
	rig.queue_free()
	tool.queue_free()


func _player_data_lives_outside_the_app() -> void:
	_check(Main.photos_folder() == "user://photos" and Main.photos_folder(false) == "user://photos" and Main.player_path("garden.save") == "user://garden.save", "off Android, photos and the garden stay in user data")
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES, true)
	_check(pictures.is_absolute_path() and Main.photos_folder(true) == pictures.path_join("Nestcombe"), "on Android, photos go to Nestcombe in the shared Pictures folder: %s" % Main.photos_folder(true))

func _a_photo_is_drawn_whole_and_the_headset_as_the_ladder_allows() -> void:
	var rig := Rig.new()
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	var vp := tool.photo_viewport()
	_check(vp.size == Vector2i(3200, 2400) and vp.msaa_3d == Viewport.MSAA_8X, "a photo is 3200x2400 at 8x MSAA: %s, %d" % [vp.size, vp.msaa_3d])
	_check(vp.mesh_lod_threshold == 0.0 and vp.anisotropic_filtering_level == Viewport.ANISOTROPY_16X, "a photo draws every mesh whole and filters textures 16x")
	_check(Quality.PHOTO_MASK & Quality.FULL_LAYER and not Quality.PHOTO_MASK & Quality.LADDER_LAYER and Quality.PHOTO_MASK & Rig.SELF_LAYER, "a photo sees the whole garden, not the ladder's cut of it, and the player's own avatar")
	_check(rig.head.cull_mask & Quality.LADDER_LAYER and not rig.head.cull_mask & Quality.FULL_LAYER, "the headset sees the ladder's cut and not the whole")
	_check(Quality.VIEW_MASK & Quality.LADDER_LAYER and not Quality.VIEW_MASK & Quality.FULL_LAYER and tool._view_viewport().msaa_3d == tool.get_viewport().msaa_3d, "a view capture is drawn as the eyes see it")
	var flora := Flora.new()
	root.add_child(flora)
	flora.blob_detail = Quality.ladder[-1].blob_detail
	tool.flora = flora
	var undo := tool.draw_finest()
	_check(flora.blob_detail == Quality.ladder[0].blob_detail, "a photo's frame draws the finest blobs")
	undo.call()
	_check(flora.blob_detail == Quality.ladder[-1].blob_detail, "and puts the headset's back after")
	_check(flora.grass_mat.get_shader_parameter(&"full_layer") == Quality.FULL_LAYER and flora.flower_mat.get_shader_parameter(&"full_layer") == Quality.FULL_LAYER, "grass and flowers grow to every distance for a photo")
	var ivy: ShaderMaterial = Wall.kinds()[Wall.Part.IVY].material
	_check(ivy.get_shader_parameter(&"full_layer") == Quality.FULL_LAYER, "and so does ivy")
	var parent := Node3D.new()
	root.add_child(parent)
	var look := Look.build(parent)
	var sun := look.photo_sun
	_check(look.sun.layers == Quality.LADDER_LAYER and sun.layers == Quality.FULL_LAYER, "a photo is lit by its own sun, the headset by the other")
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and sun.directional_shadow_max_distance >= Terrain.SIZE * sqrt(2.0), "a photo's shadows reach the garden's far corner in four splits: %.0f m" % sun.directional_shadow_max_distance)
	look.set_time(0.9)
	_check(sun.global_basis.is_equal_approx(look.sun.global_basis) and sun.light_color == look.sun.light_color and sun.light_energy == look.sun.light_energy, "and it stands and shines as the sun does")
	_check(PhotoTool.settings().shadow_atlas == PhotoTool.PHOTO_SHADOWS and PhotoTool.PHOTO_SHADOWS >= 8192, "a photo's frame draws shadows into an 8192 atlas")
	var glade := Masonry.new(Wall.kinds())
	root.add_child(glade)
	var parts: Array[Dictionary] = []
	for k in Wall.kinds().size():
		var buf := PackedFloat32Array()
		buf.resize(Wall.kinds()[k].stride())
		Wall.kinds()[k].write(buf, 0, Transform3D(Basis(), Vector3(1, 0, 1)))
		parts.append(Masonry.split(buf, Wall.kinds()[k]))
	glade.place(1, parts)
	for k in [Wall.Part.STONE, Wall.Part.IVY]:
		var chunk: Masonry.Chunk = glade._chunks[Vector3i(0, 0, k)]
		_check(chunk.full != null and chunk.full.multimesh == chunk.instance.multimesh and chunk.full.layers == Quality.FULL_LAYER and chunk.full.visibility_range_end == 0.0, "a photo draws part %d whole at every distance" % k)
		_check(chunk.instance.layers == Quality.LADDER_LAYER and chunk.instance.visibility_range_end > 0.0, "the headset draws part %d as the ladder allows" % k)
	_check(glade._chunks[Vector3i(0, 0, Wall.Part.STONE_SHADOW)].full == null, "what is drawn whole anyway has no second instance")
	for n in [tool, flora, parent, glade, rig]:
		n.queue_free()
