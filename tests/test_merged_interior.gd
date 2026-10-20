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
	var standing: Dictionary = main.tool.pick_building(origin, Vector3.BACK)
	_check(not standing.is_empty() and standing.point.z > 7.5, "shared pick skips old seams and finds the outer wall")
	var old_wall := Vector3(0, origin.y, 2.5)
	var contact := HandStop.Near.gather(main.tool, main.flora_tool.flora, AABB(old_wall - Vector3.ONE, Vector3.ONE * 2))
	_check(not contact.solid(old_wall), "hand contact also skips the removed wall")
	var roof: RoofLayout = main.tool.walls[0].roof
	var old_roof := Vector3(0, roof.height_at(0, 2), 2)
	var roof_contact := HandStop.Near.gather(main.tool, main.flora_tool.flora, AABB(old_roof - Vector3.ONE, Vector3.ONE * 2))
	_check(not roof_contact.solid(old_roof), "hand contact skips the removed inner roof slope")
	var seam := Driver.new(main, [{"op": "fit", "what": "lantern", "index": 0, "s": 15.5, "y": 1.9, "side": 1}])
	main.add_child(seam)
	await seam.finished
	seam.queue_free()
	var w: Wall = main.tool.walls[0]
	_check(w.layout.lanterns.size() == 2 and w.layout.flames.size() == 1, "merge removes the seam lantern geometry and flame")
	var f := w.layout.frame_at(15.5)
	var at: Vector3 = f.point + Vector3.UP * 1.9 + f.tangent.cross(Vector3.UP) * (WallLayout.THICKNESS * 0.5 + WallLayout.LANTERN_OUT)
	var picked := FittingTool.pick_target(main.tool, at - Vector3.BACK, Vector3.BACK)
	_check(not picked.get("fitting", false), "removed seam lantern has no fitting pick bounds")
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
