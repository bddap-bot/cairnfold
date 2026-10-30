extends SceneTree

## The sun stays out of a sealed house: looking up at its gable from inside at noon, with every light but the sun's
## direct light taken away, the view is black, and stays black with the sun's shadows off, as the ladder's lowest steps
## draw it (Interior). The shadow depth bias let the sun through onto the gable and wall tops just under the roof until
## the roof cast its shadow pulled toward the light (roof_shadow.gdshader). Shadows are drawn only on the desktop
## renderer, so scripts/test.sh runs this there.

var failures := 0
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _steps(s: Array) -> void:
	var d := Driver.new(main, s)
	main.add_child(d)
	await d.finished
	d.queue_free()


func _mean() -> float:
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			sum += img.get_pixel(x, y).get_luminance()
	return sum / (img.get_width() * img.get_height()) * 255.0


func _run() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await _steps([{"op": "place", "x": 0, "z": 12}, {"op": "house", "at": [0, 0], "size": [7, 5], "seconds": 0.1}])
	main.world.submit({"op": "sky", "time": 0.5})
	await create_timer(1.0).timeout
	main.look.bounce.finish()
	main.fitting_tool.lamps.finish()
	await create_timer(3.0).timeout
	main.look.set_process(false)
	RenderingServer.global_shader_parameter_set("lamp_light", Vector3.ZERO)
	RenderingServer.global_shader_parameter_set("bounce_light", Vector3.ZERO)
	main.look.env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	main.look.env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	main.look.env.fog_enabled = false
	await _steps([{"op": "view", "eye": [-6, 1.8, 7], "at": [0, 1.2, 0], "ground": true}])
	var outside := await _mean()
	check(outside > 20.0, "the sun lights the house from outside: %.2f" % outside)
	await _steps([{"op": "view", "eye": [-2.2, 1.6, 0], "at": [2, 2.6, 0], "ground": true}])
	var inside := await _mean()
	check(inside < 0.5, "no sun reaches under the sealed roof: %.3f" % inside)
	await _steps([{"op": "layer", "name": "shadows", "mode": "off"}, {"op": "view", "eye": [-2.2, 1.6, 0], "at": [2, 2.6, 0], "ground": true}])
	var unshadowed := await _mean()
	check(unshadowed < 0.5, "nor with the sun's shadows off: %.3f" % unshadowed)
	await _steps([{"op": "view", "eye": [-6, 1.8, 7], "at": [0, 1.2, 0], "ground": true}])
	var outside_unshadowed := await _mean()
	check(outside_unshadowed > 20.0, "while it still lights the house from outside: %.2f" % outside_unshadowed)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
