extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
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
	driver._layer({"name": "boulders", "mode": "off"})
	check(not main.boulders.visible, "boulders are hidden")
	driver._layer({"name": "boulders", "mode": "on"})
	check(main.boulders.visible, "boulders return")
	driver._layer({"name": "all", "mode": "off"})
	driver._layer({"name": "all", "mode": "on"})
	check(main.boulders.visible and main.tool.masonry.visible, "every layer, ivy and moss among them, returns")
	driver.free()
	finish()
