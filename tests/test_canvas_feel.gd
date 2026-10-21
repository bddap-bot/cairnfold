extends SceneTree

var failures := 0

func _initialize() -> void:
	var brush := Cues.CanvasFeel.new()
	check(brush.step(false, true, 0.1, 0.0, 0.0, false, 0.01).x > 0.0, "brush first touch ticks even stationary")
	check(brush.step(false, true, 0.4, 0.2, 0.002, false, 0.01) == Vector2.ZERO, "light brush stroke has no buzz")
	check(brush.step(false, true, 1.0, 0.0, 0.0, true, 0.01).x > 0.0, "stationary hard press begins feedback")
	check(brush.step(false, true, 1.0, 0.0, 0.0, true, 0.03).x > 0.0, "stationary hard press renews feedback")
	check(brush.step(false, true, 0.2, 0.0, 0.0, false, 0.01) == Vector2.ZERO and not brush.hard, "easing pressure ends hard feedback")
	check(brush.step(false, false, 0.0, 0.0, 0.0, false, 0.01) == Vector2.ZERO, "leaving is silent")
	check(brush.step(false, true, 0.1, 0.0, 0.0, false, 0.01).x > 0.0, "retouch ticks")
	var charcoal := Cues.CanvasFeel.new()
	check(charcoal.step(true, true, 1.0, 0.0, 0.0, true, 0.01) == Vector2.ZERO, "stationary charcoal is silent even pressed hard")
	var light := charcoal.step(true, true, 0.1, 0.1, 0.002, false, 0.01)
	var heavy := charcoal.step(true, true, 0.9, 0.1, 0.002, false, 0.01)
	check(heavy.x > light.x and light.x > 0.0, "friction amplitude follows pressure")
	var counts := []
	for travel in [0.0003, 0.0012]:
		var texture := Cues.CanvasFeel.new()
		var count := 0
		for i in 100:
			if texture.step(true, true, 0.5, travel / 0.01, travel, false, 0.01).x > 0.0:
				count += 1
		counts.append(count)
	check(counts[1] > counts[0] * 3, "four times drag speed crosses four times as many teeth")
	await audio_stops()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

func audio_stops() -> void:
	var cues := Cues.new()
	root.add_child(cues)
	var hand := XRController3D.new()
	root.add_child(hand)
	await process_frame
	Cues.canvas_contact(hand, Vector3.ZERO, true, true, 0.8, 0.2, 0.003, false)
	var contact: Dictionary = cues._canvas[hand.get_instance_id()]
	check(contact.voices.any(func(v: AudioStreamPlayer3D) -> bool: return v.playing), "moving charcoal plays")
	Cues.canvas_contact(hand, Vector3.ZERO, true, true, 0.8, 0.0, 0.0, false)
	check(contact.voices.all(func(v: AudioStreamPlayer3D) -> bool: return not v.playing), "stationary charcoal stops all grains")
	Cues.canvas_contact(hand, Vector3.ZERO, false, true, 1.0, 0.2, 0.003, true)
	check(contact.voices.all(func(v: AudioStreamPlayer3D) -> bool: return not v.playing), "brush remains silent even hard and moving")
	Cues.canvas_contact(hand, Vector3.ZERO, true, true, 0.8, 0.2, 0.003, false)
	Cues.canvas_leave(hand)
	check(contact.voices.all(func(v: AudioStreamPlayer3D) -> bool: return not v.playing), "lifting stops grains immediately")
	hand.queue_free()
	cues.queue_free()
	await process_frame
