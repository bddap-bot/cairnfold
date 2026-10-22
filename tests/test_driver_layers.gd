extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var driver := Driver.new(main, [])
	var original: Array[bool] = []
	for step: Quality.Step in Quality.ladder:
		original.append(step.shadows)
	main.quality.pin = 0
	await process_frame
	driver._layer({"name": "shadows", "mode": "off"})
	await process_frame
	check(not main.look.sun.shadow_enabled, "the governor respects the shadow diagnostic at full detail")
	driver._layer({"name": "shadows", "mode": "off"})
	main.quality.pin = 15
	await process_frame
	driver._layer({"name": "shadows", "mode": "on"})
	await process_frame
	check(not main.look.sun.shadow_enabled, "restoring at a shadowless step keeps that step shadowless")
	for i in Quality.ladder.size():
		check(Quality.ladder[i].shadows == original[i], "diagnostics restore every step's original shadow setting")
	main.quality.pin = 0
	await process_frame
	check(main.look.sun.shadow_enabled, "full-detail shadows return after the diagnostic")
	driver._layer({"name": "masonry", "mode": "off"})
	check(not main.tool.masonry.visible, "settled masonry is hidden")
	driver._layer({"name": "masonry", "mode": "on"})
	check(main.tool.masonry.visible, "settled masonry returns")
	main.tool.masonry.visible = false
	driver._layer({"name": "masonry", "mode": "off"})
	driver._layer({"name": "masonry", "mode": "on"})
	check(not main.tool.masonry.visible, "an already hidden layer stays hidden")
	main.tool.masonry.visible = true
	driver.free()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
