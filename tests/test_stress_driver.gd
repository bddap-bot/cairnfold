extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await process_frame
	var driver := Driver.new(main, [])
	main.add_child(driver)
	await _avatar_ready(driver)
	await _charcoal_from_tray()
	main.world.bounded = false
	await driver._stair_field({})
	check(not main.world.bounded, "the bounded stair fixture restores the unbounded stress workload")
	await driver._bare({})
	await driver._clear({})
	var before: int = main.tool.walls.size()
	await driver._house({"at": [-4, -3], "size": [5, 4], "rise": 1.5, "finish": "plaster", "seconds": 0.3})
	await driver._standing()
	check(main.tool.walls.size() == before + 1, "the following foundation fixture is actually built")
	var step := {"from": [-4, 0.7, 2], "at": [-4, 0.7, -3]}
	var target: Dictionary = main.palette_tool.aim_style(driver._dial_from(step), driver._dial_dir(step))
	check(target.get("restyle") == PaletteTool.Restyle.FOUNDATION, "the stress style ray hits the foundation")
	finish()


func _avatar_ready(driver: Driver) -> void:
	var done := [false]
	_wait_for_avatar(driver, done)
	await frames(2)
	check(not done[0], "a missing folder avatar keeps the driver waiting")
	main.session.files["fixture.vrm"] = {"scene": null, "key": "fixture-key"}
	await frames(2)
	check(not done[0], "a pending import keeps the driver waiting")
	main.session.files["fixture.vrm"].scene = PackedScene.new()
	await frames(2)
	check(not done[0], "a loaded avatar must also be worn before measurement")
	main.session.worn_key = "fixture-key"
	await until(func() -> bool: return done[0], "the selected imported avatar releases the driver")
	main.session.files.erase("fixture.vrm")
	main.session.worn_key = ""


func _wait_for_avatar(driver: Driver, done: Array) -> void:
	await driver._until({"files": ["fixture.vrm"], "wearing": "fixture.vrm", "seconds": 30})
	done[0] = true


func _charcoal_from_tray() -> void:
	await play([
		{"op": "place", "x": 0, "z": 6},
		{"op": "easel", "x": 0, "z": 3},
		{"op": "take", "what": "thin_stick"},
		{"op": "holds", "what": "thin_stick"},
		{"op": "brush", "points": [[0.6, 0.3, 0.8], [0.9, 0.35, 0.8]], "seconds": 0.3},
	])
	main.world.flush()
	var strokes: Array = main.world.state.easels.values()[-1].strokes
	check(strokes.size() == 1 and Brushwork.count(strokes[0]) >= 2,
		"the long stick clears the sheet coming off the tray and lays its first stroke")
