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
		main.view(eye, Vector3(0, 1, 0))
		var pose: Transform3D = main.rig.head.global_transform
		for i in 360:
			main.rig._process(1.0 / 72.0)
		check(main.rig.head.global_transform.is_equal_approx(pose), "scripted view drifts from %s to %s" % [eye, main.rig.head.global_position])
	await _a_view_holds_through_a_refit(main)
	_metrics_name_the_head_off_its_view(main)
	main.rig.free()
	main.metrics.free()
	main.free()
	finish()


## A new avatar refits the wearer behind a fade, as a teleport is set down behind one; a scripted view taken during
## that fade is where the head stands once it lands.
func _a_view_holds_through_a_refit(main) -> void:
	var rig: Rig = main.rig
	var tall := Avatar.read(FileAccess.get_file_as_bytes(avatar_file("crimsom-1.0.vrm")))
	rig.wear(Avatar.open(Avatar.built_in(0), Color.WHITE))
	rig.set_process(true)
	await until(func() -> bool: return rig._pending == null and rig._fade_t < 0.0, "the first avatar settles")
	rig.wear(Avatar.open(tall, Color.WHITE))
	await until(func() -> bool: return rig._pending != null, "a new avatar of another height fades the view")
	var eye := Vector3(0, 1.2, 0)
	main.view(eye, Vector3(0, 0.9, 4))
	await until(func() -> bool: return rig._fade_t < 0.0, "the refit lands")
	await process_frame
	var landed: Vector3 = rig.head.global_position
	check(Vector2(landed.x, landed.z).distance_to(Vector2(eye.x, eye.z)) < 0.001 and absf(landed.y - eye.y) < 0.1, "a view taken during the fade holds: the head at %s" % landed)
	rig.set_process(false)
	rig.teleport(Vector3(3, 0, 3), 0.0)
	check(rig.view_eye == null, "a teleport leaves no view to measure against")
	main.view(eye, Vector3(0, 0.9, 4))


## A second of the metrics carries the furthest the head stood that second from where the last view put it.
func _metrics_name_the_head_off_its_view(main) -> void:
	var m := Metrics.new(OS.get_cache_dir().path_join("cairnfold-test-view-%d.json" % OS.get_process_id()))
	m.info = {"refresh_hz": 72.0, "label": "-"}
	m.head = main.rig.head
	m.view_off = func() -> Variant: return null if main.rig.view_eye == null else main.rig.head.global_position.distance_to(main.rig.view_eye)
	var now := [m._last_tick]
	m.clock = func() -> int: return now[0]
	var frame := func() -> void:
		now[0] += 13900
		m._process(0.0139)
	var second := func() -> float:
		m._acc = 1.0
		frame.call()
		m._finish_row()
		return m._seconds[-1].get("view_off_m", -1.0)
	frame.call()
	var off: float = second.call()
	check(is_zero_approx(off), "a head where its view put it is 0 m off: %s" % off)
	main.rig.global_position += Vector3(0, -1.04, 0)
	frame.call()
	main.rig.global_position += Vector3(0, 1.04, 0)
	off = second.call()
	check(absf(off - 1.04) < 0.01, "a head that dropped to the grass for a frame of its second is 1.04 m off: %s" % off)
	main.rig.view_eye = null
	off = second.call()
	check(off == -1.0, "with no view to hold it to, a second names none: %s" % off)
	m.free()
