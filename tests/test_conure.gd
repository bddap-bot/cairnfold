extends "res://../tests/support/suite.gd"


func _initialize() -> void:
	await process_frame
	for fps in [30, 72, 90]:
		_events_follow_motion(fps)
	_gaze_eases()
	finish()


func _events_follow_motion(fps: int) -> void:
	var bird := Conure.new(0.0, 0)
	root.add_child(bird)
	var events: Array[int] = []
	bird.animation_event.connect(func(act: Cues.Act) -> void: events.append(act))
	bird.mode = Conure.PECK
	for i in fps * 3:
		bird.animate(1.0 / fps)
	check(events.count(Cues.Act.HAND_PECK) == 2, "two visible peck contacts in 3 s at %d Hz" % fps)
	check(is_equal_approx(float(bird.get_instance_shader_parameter("animation_time")), bird.animation_time), "renderer uses the event clock")
	bird.mode = Conure.IDLE
	bird.animation_time = 0.0
	events.clear()
	for i in fps * 14:
		bird.animate(1.0 / fps)
	check(events.count(Cues.Act.HAND_FLIT) == 1, "one simultaneous tail shake/wing flit burst in 14 s")
	check(not events.has(Cues.Act.HAND_PECK), "idle bird never pecks")
	bird.mode = Conure.FLY
	events.clear()
	for i in fps * 14:
		bird.animate(1.0 / fps)
	check(events.is_empty(), "flight never emits perched animation events")
	for act in [Cues.Act.HAND_PERCH, Cues.Act.HAND_PECK, Cues.Act.HAND_FLIT, Cues.Act.HAND_HOP, Cues.Act.HAND_PREEN, Cues.Act.HAND_LOOK]:
		var pulse: Array = Cues.TABLE[act].feel
		check(pulse[0] <= 0.025 and pulse[1] <= 0.012 and pulse[2] == 1 and not Cues.TABLE[act].has("every"), "each motion has a subtle single pulse with no timer")
	bird.free()


func _gaze_eases() -> void:
	for fps in [30, 72, 90]:
		var bird := Conure.new(0.0, 0)
		bird._gaze = Vector3(-1, 0, 1)
		var target := Conure.NECK + Vector3(-sin(1.0), 0, -cos(1.0))
		bird.looking = target
		bird.look(1.0 / fps)
		check(bird._gaze.x > -1 and bird._gaze.x < 0.5, "head turns without snapping at %d Hz" % fps)
		for i in int(0.15 * fps):
			bird.looking = target
			bird.look(1.0 / fps)
		check(bird._gaze.x > 0.9, "quick bird-like turn settles within 0.17 s")
		bird.free()
