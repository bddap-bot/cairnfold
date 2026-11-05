extends "res://../tests/support/suite.gd"

## A converted avatar's flat material is lit alike on its side toward the light and its side away, and no brighter
## than its cap however strong the light; a lit one is shaded by angle. Needs a renderer, so scripts/test.sh runs it on
## the desktop one: godot4 --path game --xr-mode off --script ../tests/gpu_avatar_lighting.gd

const SIZE := 96


func _initialize() -> void:
	_run.call_deferred()


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
	eye.size = 2.4
	eye.position = Vector3(0, 0, 3)
	eye.cull_mask = Quality.VIEW_MASK
	view.add_child(eye)
	var sun := DirectionalLight3D.new()
	sun.basis = Basis.looking_at(Vector3.LEFT)
	view.add_child(sun)
	for name: String in ["sky_zenith", "sky_horizon"]:
		RenderingServer.global_shader_parameter_set(name, Vector3.ONE)
	RenderingServer.global_shader_parameter_set(&"sun_toward", Vector3.RIGHT)
	var shots := {}
	for model: String in ["flat", "lit"]:
		var avatar := _ball(model)
		view.add_child(avatar)
		for light: Vector2 in [Vector2(0.5, 0.0), Vector2(3.0, 0.0), Vector2(0.3, 0.2), Vector2(3.0, 0.2)]:
			sun.light_energy = light.x
			RenderingServer.global_shader_parameter_set(&"sun_light", Vector3.ONE * light.x)
			RenderingServer.global_shader_parameter_set(&"sky_ambient", light.y)
			env.ambient_light_color = Color.WHITE * light.y
			shots["%s %s" % [model, light]] = await _sides(view)
		avatar.queue_free()
	print(shots)
	var flat_dim: Vector2 = shots["flat (0.5, 0.0)"]
	var flat_bright: Vector2 = shots["flat (3.0, 0.0)"]
	var flat_ambient: Vector2 = shots["flat (0.3, 0.2)"]
	var flat_both: Vector2 = shots["flat (3.0, 0.2)"]
	var lit: Vector2 = shots["lit (0.5, 0.0)"]
	check(absf(flat_dim.x - 0.5) < 0.04 and absf(flat_dim.x - flat_dim.y) < 0.03, "a flat material is lit by the whole light of 0.5 toward the light and away: %s" % flat_dim)
	check(absf(flat_bright.x - 0.8) < 0.06 and absf(flat_bright.x - flat_bright.y) < 0.03, "a flat material in light past its cap of 0.8 is lit at the cap: %s" % flat_bright)
	check(absf(flat_ambient.x - 0.5) < 0.04 and absf(flat_ambient.x - flat_ambient.y) < 0.03, "a flat material takes light 0.3 and ambient 0.2 whole, either side: %s" % flat_ambient)
	check(absf(flat_both.x - 0.8) < 0.06 and absf(flat_both.x - flat_both.y) < 0.03, "a flat material in light and ambient past its cap is lit at the cap: %s" % flat_both)
	check(lit.x > lit.y + 0.2, "a lit material is shaded by angle: %s" % lit)
	view.queue_free()
	finish()


## A white ball whose looks light its one material `model`, capped at 0.8, as the avatar runtime opens it.
func _ball(model: String) -> Node3D:
	var ball := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Ball"
	var sphere := SphereMesh.new()
	sphere.radial_segments = 48
	sphere.rings = 24
	var picture := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	picture.fill(Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(picture)
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays(), [], {}, mat)
	var index := Image.create_empty(4, 4, false, Image.FORMAT_L8)
	index.fill(Color8(1, 1, 1))
	var light := {"model": model, "cap": 0.8} if model == "flat" else {"model": model}
	var looks := {"index": Marshalls.raw_to_base64(index.save_png_to_buffer()), "materials": [{"lighting": light}]}
	Avatar._flat_lit(looks, [im])
	mesh.mesh = im.get_mesh()
	ball.add_child(mesh)
	ball.set_meta("expressions", {"looks": looks})
	ball.add_child(ExpressionPlayer.new(ball))
	return ball


## The ball's mean linear red on its side toward the light and on its side away, once its pipeline has compiled.
func _sides(view: SubViewport) -> Vector2:
	var start := Time.get_ticks_msec()
	var sides := Vector2.ZERO
	while Time.get_ticks_msec() - start < HANG * 1000:
		await process_frame
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		sides = Vector2(_mean(image, SIZE * 5 / 8), _mean(image, SIZE * 3 / 8))
		if sides.x + sides.y > 0.0:
			return sides
	return sides


static func _mean(image: Image, x: int) -> float:
	var sum := 0.0
	var n := 0
	for y in range(SIZE * 7 / 16, SIZE * 9 / 16):
		for dx in range(-3, 4):
			sum += image.get_pixel(x + dx, y).srgb_to_linear().r
			n += 1
	return sum / n
