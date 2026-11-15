extends "res://../tests/support/suite.gd"


func _frame() -> Image:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func _apart(a: Image, b: Image, by: float) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var d := a.get_pixel(x, y) - b.get_pixel(x, y)
			if maxf(maxf(absf(d.r), absf(d.g)), absf(d.b)) > by:
				n += 1
	return n


static func _ground(image: Image) -> int:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).get_luminance() > 0.05:
				n += 1
	return n


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.world.submit({"op": "sky", "time": 0.35})
	await create_timer(1.0).timeout
	main.look.bounce.finish()
	await create_timer(1.0).timeout
	main.look.set_process(false)
	await play([{"op": "layer", "name": "all", "mode": "off"}, {"op": "layer", "name": "terrain"}, {"op": "layer", "name": "sun"}])
	var terrain: Terrain = main.world.terrain
	await play([{"op": "view", "eye": [30, terrain.height_at(30, 0) + 6.0, 0], "at": [60, terrain.height_at(60, 0), 0]}])
	var baked := await _frame()
	check(_ground(baked) > 1500, "the rim's slopes fill the lower half of the view: %d pixels" % _ground(baked))
	terrain.set_hump(0, -70, -70, 1.0, 0.01)
	var live := await _frame()
	terrain.clear_hump(0)
	var apart := _apart(baked, live, 2.5 / 255.0)
	check(apart == 0, "a live hump far off leaves the ground shaded as its baked normals shade it: %d pixels apart" % apart)
	finish()
