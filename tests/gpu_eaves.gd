extends "res://../tests/support/suite.gd"


func _band(from: float, to: float) -> float:
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var sum := 0.0
	var rows := range(roundi(from * image.get_height()), roundi(to * image.get_height()))
	for y: int in rows:
		for x in image.get_width():
			sum += image.get_pixel(x, y).srgb_to_linear().get_luminance()
	return sum / (rows.size() * image.get_width())


func _run() -> void:
	root.mesh_lod_threshold = 0.0
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await play([{"op": "place", "x": 0, "z": 12}, {"op": "house", "at": [0, 0], "size": [7, 5], "seed": 1, "seconds": 0.1}])
	main.world.submit({"op": "sky", "time": 0.5})
	await create_timer(1.0).timeout
	main.look.bounce.finish()
	main.fitting_tool.lamps.finish()
	main.look.interior.finish()
	await create_timer(3.0).timeout
	main.look.set_process(false)
	await play([{"op": "layer", "name": "sun", "mode": "off"}, {"op": "layer", "name": "wildlife", "mode": "off"}, {"op": "layer", "name": "shy", "mode": "off"}])
	await play([{"op": "view", "eye": [0, 1.4, 5.0], "at": [0, 3.4, 2.4], "ground": true}])
	var front := await _band(0.5625, 0.75)
	await play([{"op": "view", "eye": [2, 1.5, 6], "at": [0, 3.5, 0], "ground": true}])
	var aslant := await _band(0.359375, 0.640625)
	check(front > 0.05 and front < 0.088, "the eaves seen from under them stay as dark as the room's probes keep them: %.4f" % front)
	check(aslant > 0.1 and aslant < 0.16, "and seen aslant: %.4f" % aslant)
	finish()
