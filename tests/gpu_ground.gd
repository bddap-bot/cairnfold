extends "res://../tests/support/suite.gd"


static func _ground_share(image: Image) -> float:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).get_luminance() > 0.05:
				n += 1
	return float(n) / (image.get_width() * image.get_height())


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.rig.stature.add(Rig.EYE, 3600.0)
	main.world.submit({"op": "sky", "time": 0.35, "pace": 0.0})
	await until(func() -> bool: return main.look._sky_time == 0.35, "the sky is painted for the hour")
	main.look.bounce.finish()
	main.look.set_process(false)
	await play([{"op": "layer", "name": "all", "mode": "off"}, {"op": "layer", "name": "terrain"}, {"op": "layer", "name": "sun"}])
	var terrain: Terrain = main.world.terrain
	await play([{"op": "view", "eye": [30, terrain.height_at(30, 0) + 6.0, 0], "at": [60, terrain.height_at(60, 0), 0]}])
	var baked := await drawn()
	check(_ground_share(baked) > 0.35, "the rim's slopes fill the lower half of the view: %.2f of it" % _ground_share(baked))
	terrain.set_hump(0, -70, -70, 1.0, 0.01)
	var live := await drawn()
	terrain.clear_hump(0)
	var apart := pixels_apart(baked, live, 2.5 / 255.0)
	check(apart == 0, "a live hump far off leaves the ground shaded as its baked normals shade it: %d pixels apart" % apart)
	await _far_grass_paints_the_clumps_it_replaces(terrain)
	finish()


func _far_grass_paints_the_clumps_it_replaces(terrain: Terrain) -> void:
	main.look.env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var flora: Flora = main.flora_tool.flora
	for mat: ShaderMaterial in flora.ground_mats:
		mat.set_shader_parameter(&"lod_begin", 0.0)
		mat.set_shader_parameter(&"lod_band", 0.001)
		mat.set_shader_parameter(&"survivors", 0.0)
	await play([{"op": "view", "eye": [0, terrain.height_at(0, 8) + 4.0, 8], "at": [0, terrain.height_at(0, -8), -8]}])
	var cover := flora.grass.cover
	var held := cover.image.duplicate() as Image
	cover.image.fill(Color(0, 0, 0, 0))
	cover.texture.update(cover.image)
	var bare := await drawn()
	await play([{"op": "flora_far", "mode": "off"}])
	var unpainted := await drawn()
	await play([{"op": "flora_far", "mode": "on"}])
	check(_ground_share(bare) > 0.45, "the meadow fills the view: %.2f of it" % _ground_share(bare))
	check(pixels_apart(bare, unpainted, 0.0) == 0, "ground under no clump is painted as ground with no far grass")
	cover.image.fill(FloraCover.look(Color.WHITE, Color(0, 0.5, 0)))
	cover.texture.update(cover.image)
	var neutral := _median_linear_ratio(bare, await drawn())
	check(_near(neutral, 1.0, 0.01), "clumps of the meadow's own tone paint it unchanged: %s" % neutral)
	cover.image.fill(FloraCover.look(Color(0.6, 0.6, 0.6), Color(0, 0.5, 0)))
	cover.texture.update(cover.image)
	var shaded := _median_linear_ratio(bare, await drawn())
	check(_near(shaded, 0.6, 0.02), "clumps shaded to 0.6 paint the meadow 0.6 as bright: %s" % shaded)
	cover.image.copy_from(held)
	cover.texture.update(cover.image)


static func _near(c: Color, to: float, by: float) -> bool:
	return absf(c.r - to) < by and absf(c.g - to) < by and absf(c.b - to) < by


static func _median_linear_ratio(under: Image, over: Image) -> Color:
	var channels: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for y in under.get_height():
		for x in under.get_width():
			var a := under.get_pixel(x, y).srgb_to_linear()
			var b := over.get_pixel(x, y).srgb_to_linear()
			if a.get_luminance() > 0.02:
				for k in 3:
					channels[k].append(b[k] / a[k])
	return Color(Quality.median(channels[0]), Quality.median(channels[1]), Quality.median(channels[2]))
