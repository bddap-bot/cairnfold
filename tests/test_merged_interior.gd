extends SceneTree

var failures := 0
var main: Node

func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func _run() -> void:
	var steps := Driver.read("res://../demo/merged-interior.json").slice(0, 7)
	var driver := Driver.new(main, steps)
	main.add_child(driver)
	await driver.finished
	driver.queue_free()
	var lamps: Lamps = main.fitting_tool.lamps
	lamps.light(main.tool.walls)
	lamps.finish()
	var light := lamps.at(0.5, 4.5, 1)
	print("merged interior light: ", light)
	_check(light > 0.0, "a placed lantern lights the second building through the removed wall")
	var origin := Terrain.ground(0, -1.5) + Vector3.UP * 1.3
	var direction := Vector3(0, -0.2, 1).normalized()
	main.rig.aim(Transform3D(Basis.looking_at(direction), origin))
	print("merged teleport target: ", main.rig.aim_ground)
	_check(main.rig.aim_ground != null and main.rig.aim_ground.z > 3.0, "teleport crosses the old wall line into the next building")
	var high := Terrain.ground(0, -0.4) + Vector3.UP * 3.3
	main.rig.aim(Transform3D(Basis.looking_at(Vector3(0, -0.3, 1)), high))
	print("merged roof teleport target: ", main.rig.aim_ground)
	_check(main.rig.aim_ground != null and main.rig.aim_ground.z > 3.0, "teleport also crosses the removed inner roof slope")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
