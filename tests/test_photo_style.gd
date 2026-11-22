extends "res://../tests/support/suite.gd"

## The styles' passes need a renderer; tests/gpu_photo_styles.gd draws each and demo/photo.json takes one of each.

var terrain := Terrain.new()


func _initialize() -> void:
	terrain.install()
	await process_frame
	_each_style_has_its_pass()
	await _godots_own_materials_carve_only_while_a_camera_does()
	await _the_other_hand_turns_the_cameras_dial()
	finish()


func _each_style_has_its_pass() -> void:
	var white := Vector3.ONE
	var mono: Basis = PhotoStyle.TONES[PhotoStyle.Kind.MONO]
	var sepia: Basis = PhotoStyle.TONES[PhotoStyle.Kind.SEPIA]
	var cyan: Basis = PhotoStyle.TONES[PhotoStyle.Kind.CYANOTYPE]
	var painted: Basis = PhotoStyle.TONES[PhotoStyle.Kind.PAINTERLY]
	var through := func(tone: Basis, c: Vector3) -> Vector3: return Vector3(tone[0].dot(c), tone[1].dot(c), tone[2].dot(c))
	check(through.call(mono, white).is_equal_approx(white) and through.call(painted, white).is_equal_approx(white), "mono and painterly keep white white")
	var s: Vector3 = through.call(sepia, white)
	var c: Vector3 = through.call(cyan, white)
	check(s.x > s.y and s.y > s.z and c.z > c.y and c.y > c.x, "sepia tints toward brown, cyanotype toward blue: %s, %s" % [s, c])
	for kind: PhotoStyle.Kind in PhotoStyle.Kind.values():
		var made := PhotoStyle.compositor(kind)
		var passes := made != null and made.compositor_effects.size() == 1
		check(passes == (PhotoStyle.TONES[kind] != null), "%s draws a pass over the view only if it has a tone" % PhotoStyle.named(kind))
		check(PhotoStyle.of(PhotoStyle.named(kind)) == kind, "%s is named by its kind" % PhotoStyle.named(kind))
	var strokes: StylePass = PhotoStyle.compositor(PhotoStyle.Kind.PAINTERLY).compositor_effects[0]
	check(strokes.reach > 0.0 and strokes.effect_callback_type == CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT, "painterly lays strokes over the finished view")
	check(Quality.SCULPTURE_LAYER > 0xFFFFF and not (Quality.VIEW_MASK | Quality.PHOTO_MASK) & Quality.SCULPTURE_LAYER, "no node can stand on the sculpture's layer, and no view sees it by default")
	check(PhotoStyle.mask(PhotoStyle.Kind.SCULPTURE, Quality.VIEW_MASK) == Quality.VIEW_MASK | Quality.SCULPTURE_LAYER and PhotoStyle.mask(PhotoStyle.Kind.MONO, Quality.VIEW_MASK | Quality.SCULPTURE_LAYER) == Quality.VIEW_MASK, "the sculpture alone carves its view white")
	var cam := Camera3D.new()
	PhotoStyle.dress(cam, PhotoStyle.Kind.SEPIA, Quality.VIEW_MASK)
	var kept := cam.compositor
	PhotoStyle.dress(cam, PhotoStyle.Kind.SEPIA, Quality.PHOTO_MASK)
	check(kept != null and cam.compositor == kept and cam.cull_mask == Quality.PHOTO_MASK, "a camera keeps its pass while its style stays")
	PhotoStyle.dress(cam, PhotoStyle.Kind.SCULPTURE, Quality.VIEW_MASK)
	check(cam.compositor == null and cam.cull_mask & Quality.SCULPTURE_LAYER, "and drops it for the sculpture")
	cam.free()


func _godots_own_materials_carve_only_while_a_camera_does() -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = BoxMesh.new()
	var mat := StandardMaterial3D.new()
	piece.material_override = mat
	PhotoStyle.carve(piece)
	check(mat.next_pass == null, "a Godot material draws no white pass while no camera carves")
	var carver := Camera3D.new()
	root.add_child(carver)
	PhotoStyle.dress(carver, PhotoStyle.Kind.SCULPTURE, Quality.VIEW_MASK)
	check(mat.next_pass is ShaderMaterial, "and takes one while a camera does")
	PhotoStyle.dress(carver, PhotoStyle.Kind.MONO, Quality.VIEW_MASK)
	check(mat.next_pass == null, "dropping it when that camera turns to another style")
	PhotoStyle.dress(carver, PhotoStyle.Kind.SCULPTURE, Quality.VIEW_MASK)
	carver.queue_free()
	await process_frame
	check(mat.next_pass == null, "or is freed")
	piece.free()


func _preview_style(tool: PhotoTool, hand: Hand) -> int:
	var cam: Camera3D = tool._previews[hand].get_child(0)
	return cam.get_meta(&"style", PhotoStyle.Kind.PLAIN)


func _the_other_hand_turns_the_cameras_dial() -> void:
	var rig := Rig.new(terrain)
	root.add_child(rig)
	var tool := PhotoTool.new(rig)
	root.add_child(tool)
	rig.right.tool = Hand.Tool.CAMERA
	rig.right.held_still = true
	rig.left.held_still = true
	rig.right.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.2, 1.2, -0.3))
	rig.left.global_transform = Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.0, -0.2))
	for i in PhotoTool.PREVIEW_EVERY + 1:
		await process_frame
	var grip := Controls.key("grab", rig.left.tracker)
	Buttons.injected[grip] = true
	await frames(2)
	check(tool._dial == null, "a grip out of the camera's reach turns no dial")
	Buttons.injected.erase(grip)
	await frames(2)
	rig.left.global_position = tool.body(rig.right) + Vector3(-0.05, 0.0, 0.0)
	Buttons.injected[grip] = true
	await frames(2)
	check(tool._dial != null and tool._dial.choices.size() == PhotoStyle.Kind.size() and tool._dial.pick == PhotoStyle.Kind.PLAIN, "the other hand's grip at the camera opens a dial of every style, on the one it has")
	check(tool._dial.choices.all(func(n: Node3D) -> bool: return (n as VisualInstance3D).layers == Quality.EYES_LAYER), "which no lens sees")
	check(rig.left.taken(), "and holds the hand, so its grip moves nothing else")
	var from := rig.left.global_basis
	for f in 6:
		rig.left.global_basis = Basis(-from.z, deg_to_rad(Dial.step(PhotoStyle.Kind.size()) * (f + 1) / 6.0)) * from
		await process_frame
	check(tool.style == PhotoStyle.Kind.PAINTERLY and not tool.over_view, "a twist of one step turns it on to painterly, the lens alone")
	for i in PhotoTool.PREVIEW_EVERY + 1:
		await process_frame
	check(_preview_style(tool, rig.right) == PhotoStyle.Kind.PAINTERLY and rig.head.compositor == null, "the screen shows it live; the eyes do not")
	rig.left.global_position = tool.body(rig.right) + Vector3.UP * (PhotoTool.OVER_VIEW + 0.02)
	await frames(2)
	check(tool.over_view and rig.head.compositor != null, "raised over the camera, the style lies on the whole view")
	Buttons.injected.erase(grip)
	await frames(2)
	check(tool._dial == null and tool.style == PhotoStyle.Kind.PAINTERLY and tool.over_view and rig.head.compositor != null, "and stays there once let go")
	rig.right.tool = Hand.Tool.WALLS
	await frames(2)
	check(tool.over_view and rig.head.compositor != null, "while building with the camera put away")
	rig.right.tool = Hand.Tool.CAMERA
	await frames(2)
	rig.left.global_position = tool.body(rig.right)
	Buttons.injected[grip] = true
	await frames(2)
	check(tool._dial != null and not tool.over_view and rig.head.compositor == null, "a grip level with the camera takes it off the view")
	from = rig.left.global_basis
	for f in 6:
		rig.left.global_basis = Basis(-from.z, deg_to_rad(Dial.step(PhotoStyle.Kind.size()) * (f + 1) / 6.0)) * from
		await process_frame
	check(tool.style == PhotoStyle.Kind.SCULPTURE, "the next step is the sculpture")
	rig.left.global_position = tool.body(rig.right) + Vector3.UP * (PhotoTool.OVER_VIEW + 0.02)
	await frames(2)
	check(rig.head.cull_mask & Quality.SCULPTURE_LAYER, "which carves the whole view white when raised")
	rig.right.tool = Hand.Tool.WALLS
	await frames(2)
	check(tool._dial == null, "putting the camera away closes its dial")
	Buttons.injected.erase(grip)
	tool.wear(PhotoStyle.Kind.PLAIN, false)
	check(not rig.head.cull_mask & Quality.SCULPTURE_LAYER and rig.head.compositor == null, "and plain takes it all off")
	tool.queue_free()
	rig.queue_free()
	await frames(2)
