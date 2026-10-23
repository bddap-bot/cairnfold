extends "res://../tests/support/suite.gd"

## The production wall and gable materials on the same face, with constant grain and light to isolate colour
## encoding. Run with scripts/render.sh demo/gables.json out --script ../tests/test_plaster_material.gd.

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		var w := Wall.new(1, null)
		w.add_roof(RoofLayout.new())
		var raw: Variant = w._gables.material_override.get_shader_parameter("albedo")
		var c := WallLayout.PLASTER
		check(raw is Vector3 and raw == Vector3(c.r, c.g, c.b), "plaster uniform must carry raw RGB like the wall instance buffer")
		w.free()
		finish()
	else:
		run.call_deferred()


func run() -> void:
	root.size = Vector2i(256, 256)
	Terrain.install()
	var im := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 1))
	var vol := ImageTexture3D.new()
	vol.create(Image.FORMAT_RGBA8, 2, 2, 2, false, [im, im])
	RenderingServer.global_shader_parameter_set("bounce_volume", vol)
	RenderingServer.global_shader_parameter_set("lamp_volume", vol)
	RenderingServer.global_shader_parameter_set("bounce_grid", Vector3(-80, 160, 8))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	root.add_child(env)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 3, 4)
	cam.look_at(Vector3(0, 3, 0))
	var w := Wall.new(1, null)
	w.add_roof(RoofLayout.new())

	im = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	im.fill(Color(0.5, 0.5, 0.5))
	var detail := ImageTexture.create_from_image(im)
	var stone := Stones.shared_material()
	stone.set_shader_parameter("detail", detail)
	var plaster := w._gables.material_override as ShaderMaterial
	plaster.set_shader_parameter("detail", detail)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)))
	mm.set_instance_color(0, WallLayout.PLASTER)
	mm.set_instance_custom_data(0, Color(1, 4, 0, 0))
	var wall := MultiMeshInstance3D.new()
	wall.multimesh = mm
	wall.material_override = stone
	root.add_child(wall)
	var g := MeshInstance3D.new()
	g.mesh = mm.mesh
	g.position = Vector3(0, 3, 0)
	g.material_override = plaster
	root.add_child(g)
	var reference := Color.BLACK
	for mode in 2:
		wall.visible = mode == 0
		g.visible = mode != 0
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var pic := root.get_texture().get_image()
		var pixel := pic.get_pixel(128, 128)
		if mode == 0:
			reference = pixel
		else:
			var error := maxf(absf(pixel.r - reference.r), maxf(absf(pixel.g - reference.g), absf(pixel.b - reference.b)))
			print("plaster pixels: wall=", reference, " gable=", pixel, " max channel difference=", error)
			check(error <= 2.0 / 255.0, "identical plaster surfaces must render the same colour")
	w.free()
	finish()
