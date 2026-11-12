extends "res://../tests/support/suite.gd"

## A half see-through black piece of an animated avatar mesh lets through half the light of what stands behind it, as a
## blend in linear light does. Needs a renderer, so scripts/test.sh runs it on the desktop one:
## godot4 --path game --xr-mode off --script ../tests/gpu_sheer.gd

const SIZE := 64
const BEHIND := Color(0.8, 0.8, 0.8)


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(SIZE, SIZE)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = env
	view.add_child(world)
	var eye := Camera3D.new()
	eye.projection = Camera3D.PROJECTION_ORTHOGONAL
	eye.size = 1.0
	eye.position = Vector3(0, 0, 3)
	eye.cull_mask = Quality.VIEW_MASK
	view.add_child(eye)
	var wall := MeshInstance3D.new()
	wall.mesh = QuadMesh.new()
	(wall.mesh as QuadMesh).size = Vector2(4, 4)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = BEHIND
	wall.material_override = lit
	wall.layers = Quality.VIEW_MASK
	view.add_child(wall)
	var start := Time.get_ticks_msec()
	var bare := await _shot(view)
	while bare < 0.1 and Time.get_ticks_msec() - start < HANG * 1000:
		bare = await _shot(view)
	lit.albedo_color = (BEHIND.srgb_to_linear() * 0.5).linear_to_srgb()
	var half := await _shot(view)
	lit.albedo_color = BEHIND
	var sheer := StandardMaterial3D.new()
	sheer.albedo_color = Color(0, 0, 0, 0.5)
	sheer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var piece := MeshInstance3D.new()
	piece.mesh = ArrayMesh.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4)
	(piece.mesh as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, quad.get_mesh_arrays())
	piece.mesh.surface_set_material(0, sheer)
	piece.position.z = 1.0
	piece.layers = Quality.VIEW_MASK
	var model := Node3D.new()
	view.add_child(model)
	model.add_child(piece)
	var player := ExpressionPlayer.new(model)
	model.add_child(player)
	player._material(piece)
	var shader := (piece.get_surface_override_material(0) as ShaderMaterial).shader.resource_path.get_file()
	check(shader == "expression_blended.gdshader", "the piece draws through the blended expression shader: %s" % shader)
	start = Time.get_ticks_msec()
	var through := await _shot(view)
	while absf(through - bare) < 0.01 and Time.get_ticks_msec() - start < HANG * 1000:
		through = await _shot(view)
	print("bare %.3f, half its light %.3f, through the piece %.3f" % [bare, half, through])
	check(bare - half > 0.1, "the wall at half its light reads darker than the wall: %.3f, %.3f" % [half, bare])
	check(absf(through - half) < 0.02, "a half see-through black piece shows the wall at half its light: %.3f against %.3f" % [through, half])
	view.queue_free()
	finish()


## The mean red at the middle of the view three frames on, once a change has reached a drawn frame.
func _shot(view: SubViewport) -> float:
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var sum := 0.0
	var n := 0
	for y in range(SIZE * 3 / 8, SIZE * 5 / 8):
		for x in range(SIZE * 3 / 8, SIZE * 5 / 8):
			sum += image.get_pixel(x, y).r
			n += 1
	return sum / n
