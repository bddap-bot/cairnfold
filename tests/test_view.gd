extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	await process_frame
	var main = load("res://src/main.gd").new()
	main.metrics = Metrics.new("")
	main.metrics.info.xr = true
	main.rig = Rig.new(Terrain.new())
	root.add_child(main.rig)
	for eye in [Vector3(8, 6, 11), Vector3(8, 1.65, 13)]:
		main.rig.place(Vector3.ZERO, 3.0)
		main.view(eye, Vector3(0, 1, 0), false)
		var pose: Transform3D = main.rig.head.global_transform
		for i in 360:
			main.rig._process(1.0 / 72.0)
		check(main.rig.head.global_transform.is_equal_approx(pose), "scripted view drifts from %s to %s" % [eye, main.rig.head.global_position])
	main.rig.free()
	main.metrics.free()
	main.free()
	finish()
