extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	boot_main()
	await process_frame
	await _tour()
	await _stress_wall_walk()
	finish()


func _play(step: Dictionary) -> void:
	var d := Driver.new(main, [step])
	var ran := [false]
	d.finished.connect(func() -> void: ran[0] = true)
	main.add_child(d)
	while not ran[0]:
		await process_frame
	d.queue_free()


## Every teleport in `demo/standing.json` lets go on what was built, never the ground: a full stick stands the player
## on the top surface beneath, and an eased one floats over it.
func _tour() -> void:
	var rig: Rig = main.rig
	var aims := 0
	for step: Dictionary in Driver.read("res://../demo/standing.json"):
		if step.op in ["capture", "quit"]:
			continue
		step.erase("capture")
		await _play(step)
		if step.op != "aim":
			continue
		aims += 1
		var h := rig.head.global_position
		var under: float = rig.floor_under.call(Vector3(h.x, rig.global_position.y + Rig.LIFTED, h.z))
		var ground := Terrain.height_at(h.x, h.z)
		var lift := rig.global_position.y - under
		var what := "aim %d, stick %.2f, at %s" % [aims, step.stick, h]
		check(under > ground + 1.0, "%s: lets go over a build's top %.2f, not the ground %.2f" % [what, under, ground])
		if step.stick >= Rig.FULL_STICK:
			check(absf(lift) < StairLayout.RISE, "%s: stands on it, %.2f over it" % [what, lift])
		else:
			check(lift > Rig.LIFTED, "%s: floats over it, %.2f up" % [what, lift])
	check(aims == 6, "the tour makes six teleports: %d" % aims)


## The stress scene's `standing/*` views look out from a standing player's eyes on the wall walk drawn through the
## roofs village.
func _stress_wall_walk() -> void:
	var steps := Driver.read("res://../demo/stress.json")
	var first := steps.find_custom(func(s: Dictionary) -> bool: return s.get("name", "").begins_with("standing/"))
	check(first >= 0, "the stress scene has standing/* phases")
	if first < 0:
		return
	var village := first
	while steps[village].op != "village":
		village -= 1
	await _play({"op": "clear"})
	await _play(steps[0])
	var views := 0
	for k in range(village, steps.size()):
		var step: Dictionary = steps[k]
		if step.op == "clear":
			break
		if step.op == "capture":
			continue
		await _play(step)
		if step.op != "view" or not main.metrics.info.label.begins_with("standing/"):
			continue
		views += 1
		var eye: Vector3 = main.rig.head.global_position
		var walk: float = main.rig.floor_under.call(eye + Vector3.DOWN * (Rig.EYE - WallLayout.SINK))
		check(walk > Terrain.height_at(eye.x, eye.z) + 4.0 and absf(eye.y - walk - Rig.EYE) < 0.15, "%s looks out from a standing player's eyes on the wall walk: eyes %.2f over %.2f" % [main.metrics.info.label, eye.y, walk])
	check(views == 2, "the stress scene has two standing views: %d" % views)
