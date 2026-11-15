extends "res://../tests/support/suite.gd"


func _frame() -> Image:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func _mean(image: Image, box: Rect2) -> float:
	var size := Vector2(image.get_size())
	var from := Vector2i((box.position * size).round())
	var to := Vector2i((box.end * size).round())
	var sum := 0.0
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			sum += image.get_pixel(x, y).srgb_to_linear().get_luminance()
	return sum / ((to.x - from.x) * (to.y - from.y))


static func _lit(image: Image) -> int:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if maxf(maxf(c.r, c.g), c.b) > 8.0 / 255.0:
				n += 1
	return n


func _bake() -> void:
	main.look.set_process(true)
	await create_timer(1.0).timeout
	main.look.bounce.finish()
	main.fitting_tool.lamps.finish()
	main.look.interior.finish()
	await create_timer(3.0).timeout
	main.look.set_process(false)


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var terrain: Terrain = main.world.terrain
	await play([{"op": "budget", "bounded": false}, {"op": "place", "x": 0, "z": 12}, {"op": "house", "at": [0, 0], "size": [7, 5], "seed": 1, "seconds": 0.1}, {"op": "house", "at": [25, 0], "size": [7, 5], "seed": 1, "seconds": 0.1}, {"op": "roof", "index": 1, "pitch": 0.0}])
	await laid()
	await play([{"op": "house", "at": [25, 0], "size": [7, 5], "seed": 1, "seconds": 0.1, "on": true}])
	await laid()
	check(main.tool.walls.size() == 3, "a house stands, and beside it a storey on a storey: %d walls" % main.tool.walls.size())
	if main.tool.walls.size() != 3:
		finish()
		return
	main.world.submit({"op": "sky", "time": 0.5})
	await _bake()
	await play([{"op": "layer", "name": "sun", "mode": "off"}, {"op": "layer", "name": "wildlife", "mode": "off"}, {"op": "layer", "name": "shy", "mode": "off"}])
	await play([{"op": "view", "eye": [0, 1.4, 5.0], "at": [0, 3.4, 2.4], "ground": true}])
	var front := _mean(await _frame(), Rect2(0, 0.5625, 1, 0.1875))
	await play([{"op": "view", "eye": [2, 1.5, 6], "at": [0, 3.5, 0], "ground": true}])
	var aslant := _mean(await _frame(), Rect2(0, 0.359375, 1, 0.28125))
	check(front > 0.05 and front < 0.088, "the eaves seen from under them stay as dark as the room's probes keep them: %.4f" % front)
	check(aslant > 0.1 and aslant < 0.16, "and seen aslant: %.4f" % aslant)
	await _sealed_storeys_keep_the_sun_out()
	await _a_lit_window_lights_the_ground_more_than_its_wall()
	finish()


func _sealed_storeys_keep_the_sun_out() -> void:
	main.world.submit({"op": "sky", "time": 0.4})
	await play([{"op": "layer", "name": "sun"}])
	await _bake()
	var floor: float = main.tool.walls[2].layout.samples[0].y
	var lit := []
	for at: Vector3 in [Vector3(25, 0, -2.5), Vector3(28.5, 0, 0), Vector3(21.5, 0, -2.5)]:
		await play([{"op": "view", "eye": [25, floor + 2.55, 0], "at": [at.x, floor + 1.55, at.z]}])
		lit.append(_lit(await _frame()))
	check(lit.max() == 0, "no sun reaches an upper storey's walls where they stand on the storey below: %s pixels lit" % [lit])


func _a_lit_window_lights_the_ground_more_than_its_wall() -> void:
	await play([{"op": "fit", "what": "opening", "index": 0, "s": 3.5, "y": 1.7}, {"op": "fit", "what": "lantern", "index": 0, "s": 1.5, "y": 1.6, "side": 1.0}])
	await laid()
	main.world.submit({"op": "sky", "time": 0.0})
	await _bake()
	await play([{"op": "view", "eye": [0, 1.6, -8], "at": [0, 1.4, -2.5], "ground": true}])
	var night := await _frame()
	var left := _mean(night, Rect2(0.3125, 0.4375, 0.125, 0.15625))
	var right := _mean(night, Rect2(0.5625, 0.4375, 0.125, 0.15625))
	var ground := _mean(night, Rect2(0.25, 0.6875, 0.5, 0.21875))
	check(ground > 2.0 * maxf(left, right), "a lit window lights the ground before it more than the wall beside it: %.4f under %.4f and %.4f" % [ground, left, right])
