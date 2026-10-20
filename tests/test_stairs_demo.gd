extends SceneTree

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## The demo's teleport onto the bridge must land there for any head pose an unworn headset settles in: its aim once
## grazed the deck's far edge, so a millimetre of head tracking decided between the deck and the grass 16 m beyond.
func _run() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var steps := Driver.read("res://../demo/stairs.json").filter(func(s: Dictionary) -> bool: return s.op != "capture")
	var at := steps.find_custom(func(s: Dictionary) -> bool: return s.op == "aim")
	var aim: Dictionary = steps[at]
	aim.erase("capture")
	var d := Driver.new(main, steps.slice(0, at))
	main.add_child(d)
	await d.finished
	d.queue_free()
	var rig: Rig = main.rig
	var head: Transform3D = rig.head.global_transform
	for pitch in [-0.3, 0.0, 0.3]:
		for yaw in [-0.3, 0.0, 0.3]:
			var tilted := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(head.basis.x, deg_to_rad(pitch)) * head.basis, head.origin)
			rig.aim(Driver.aim_pose(tilted, aim.dir))
			check(rig.aim_ground != null and rig.aim_ground.y > 2.0, "head turned %s° up, %s° left: the ray lands on the bridge, not %s" % [pitch, yaw, rig.aim_ground])
	rig.hide_markers()
	d = Driver.new(main, [aim])
	main.add_child(d)
	await d.finished
	check(rig.global_position.y > 2.0 and absf(rig.head.global_position.z - -0.5) < 0.6, "the demo's teleport stands on the bridge: %s" % rig.head.global_position)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)
