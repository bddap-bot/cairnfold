extends "res://../tests/support/suite.gd"


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


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await play([{"op": "budget", "bounded": false}, {"op": "place", "x": 0, "z": 12}, {"op": "house", "at": [0, 0], "size": [7, 5], "seed": 1, "seconds": 0.1}, {"op": "house", "at": [25, 0], "size": [7, 5], "seed": 1, "seconds": 0.1}, {"op": "roof", "index": 1, "pitch": 0.0}])
	await laid()
	await play([{"op": "house", "at": [25, 0], "size": [7, 5], "seed": 1, "seconds": 0.1, "on": true}])
	await laid()
	check(main.tool.walls.size() == 3, "a house stands, and beside it a storey on a storey: %d walls" % main.tool.walls.size())
	if main.tool.walls.size() != 3:
		finish()
		return
	await light_settled(0.5)
	await play([{"op": "layer", "name": "sun", "mode": "off"}, {"op": "layer", "name": "wildlife", "mode": "off"}, {"op": "layer", "name": "shy", "mode": "off"}])
	await play([{"op": "view", "eye": [0, 1.4, 5.0], "at": [0, 3.4, 2.4], "ground": true}])
	var under := await drawn()
	var eaves := _mean(under, Rect2(0, 0.578125, 1, 0.046875))
	var wall := _mean(under, Rect2(0, 0.6875, 1, 0.15625))
	check(eaves < 0.45 * wall, "the eaves seen from under them stay darker than the wall below, as the room's probes keep them: %.4f over %.4f" % [eaves, wall])
	await _sealed_storeys_keep_the_sun_out()
	await _a_lit_window_lights_the_ground_more_than_its_wall()
	finish()


func _sealed_storeys_keep_the_sun_out() -> void:
	await play([{"op": "layer", "name": "sun"}])
	await light_settled(0.4)
	var storey_floor: float = main.tool.walls[2].layout.samples[0].y
	var lit := []
	for at: Vector3 in [Vector3(25, 0, -2.5), Vector3(28.5, 0, 0), Vector3(21.5, 0, -2.5)]:
		await play([{"op": "view", "eye": [25, storey_floor + 2.55, 0], "at": [at.x, storey_floor + 1.55, at.z]}])
		lit.append(_lit(await drawn()))
	check(lit.max() == 0, "no sun reaches an upper storey's walls where they stand on the storey below: %s pixels lit" % [lit])


func _a_lit_window_lights_the_ground_more_than_its_wall() -> void:
	await play([{"op": "fit", "what": "opening", "index": 0, "s": 3.5, "y": 1.7}, {"op": "fit", "what": "lantern", "index": 0, "s": 1.5, "y": 1.6, "side": 1.0}])
	await laid()
	await light_settled(0.0)
	await play([{"op": "view", "eye": [0, 1.6, -8], "at": [0, 1.4, -2.5], "ground": true}])
	var night := await drawn()
	var left := _mean(night, Rect2(0.3125, 0.4375, 0.125, 0.15625))
	var right := _mean(night, Rect2(0.5625, 0.4375, 0.125, 0.15625))
	var ground := _mean(night, Rect2(0.25, 0.6875, 0.5, 0.21875))
	check(ground > 2.0 * maxf(left, right), "a lit window lights the ground before it more than the wall beside it: %.4f under %.4f and %.4f" % [ground, left, right])
