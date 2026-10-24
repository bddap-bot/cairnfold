extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await process_frame
	var driver := Driver.new(main, [])
	main.add_child(driver)
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
