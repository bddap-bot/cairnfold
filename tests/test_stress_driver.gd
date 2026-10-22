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
	main.add_child(driver)
	main.world.bounded = false
	await driver._stair_field({})
	check(not main.world.bounded, "the bounded stair fixture restores the unbounded stress workload")
	await driver._bare({})
	await driver._clear({})
	var before: int = main.tool.walls.size()
	await driver._house({"at": [-4, -3], "size": [5, 4], "rise": 1.5, "plaster": true, "timber_style": -1, "seconds": 0.3})
	await driver._standing()
	check(main.tool.walls.size() == before + 1, "the following foundation fixture is actually built")
	var step := {"from": [-4, 0.7, 2], "at": [-4, 0.7, -3]}
	var target: Dictionary = main.palette_tool.aim_style(driver._dial_from(step), driver._dial_dir(step))
	check(target.get("restyle") == PaletteTool.Restyle.FACE, "the stress style ray hits the foundation face")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
