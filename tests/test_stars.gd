extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var previous := 1.0
	for i in 51:
		var time := i / 100.0
		var dawn: float = Daylight.light(time).stars
		check(dawn <= previous, "stars fade out continuously toward day")
		check(is_equal_approx(dawn, Daylight.light(1.0 - time).stars), "dusk reverses the same dawn fade")
		if Daylight.elevation(time) >= 0.0:
			check(dawn == 0.0, "no stars above the daytime horizon")
		previous = dawn
	main.look.set_time(0.0)
	await create_timer(Look.SKY_EVERY * 2).timeout
	var driver := Driver.new(main, [])
	main.add_child(driver)
	driver._layer({"name": "stars", "mode": "off"})
	check(main.look.sky_mat.get_shader_parameter("stars") == 0.0, "paired measurement disables stars alone")
	driver._layer({"name": "stars", "mode": "on"})
	check(main.look.sky_mat.get_shader_parameter("stars") == Daylight.light(0.0).stars, "paired measurement restores the time source")
	var eye := Terrain.ground(0, 12) + Vector3.UP * 0.2
	main.view(eye, eye + Vector3(0, 10, -0.001), false)
	for i in 60:
		await process_frame
	check(main.rig.head.global_position.is_equal_approx(eye), "low head is neither recentered nor pushed")
	check(not main.rig.under, "low head on dry terrain is not underwater")
	check(not main.rig._fade.visible, "lying down does not trigger teleport fade")
	check(main.rig.head.near < 0.2, "near clip stays below the head clearance")
	driver.queue_free()
	finish()
