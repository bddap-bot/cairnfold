extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	for kind in [Beast.Kind.DEER, Beast.Kind.FOX]:
		await _feeding(kind)
		await _live(kind)
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, why: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", why)


func _feeding(kind: Beast.Kind) -> void:
	var animal := Beast.new(kind, 1.0, 0.0)
	root.add_child(animal)
	var dish := Dish.new()
	root.add_child(dish)
	dish.visible = true
	await process_frame
	animal.set_process(false)
	animal.neck.active = false
	animal.neck.offer = dish
	animal.neck.amount = 1.0
	animal.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animal.player.play(Beast.EAT_CLIP)
	animal.player.advance(2.0)
	var s := animal.neck.get_skeleton()
	var worst := 0.0
	var clearance := INF
	for height in ([0.4, 0.8, 1.05] if kind == Beast.Kind.DEER else [0.25, 0.4, 0.5]):
		dish.position = Vector3(0, height, 0)
		animal.position = Vector3(0, 0, Hand.TOP.z + animal.neck.stand_off(animal, dish))
		for frame in 120:
			dish.position.x = sin(frame * 0.05) * 0.02
			animal.player.seek(frame / 60.0, true)
			var body := s.get_bone_pose(s.find_bone("Torso3"))
			var ear := s.get_bone_pose(s.find_bone("Ear1.L"))
			animal.neck._process_modification()
			worst = maxf(worst, animal.neck.error)
			clearance = minf(clearance, dish.to_local(animal.neck.mouth).y - Hand.TOP.y)
			_check(s.get_bone_pose(s.find_bone("Torso3")).is_equal_approx(body), "body keeps its clip")
			_check(s.get_bone_pose(s.find_bone("Ear1.L")).is_equal_approx(ear), "ear keeps its clip")
			for i in animal.neck.chain.size():
				var bone := animal.neck.chain[i]
				var rest := s.get_bone_rest(bone).basis.get_rotation_quaternion()
				_check(rest.angle_to(s.get_bone_pose_rotation(bone)) <= NeckAim.LIMITS[i] + 0.002, "neck stays within its joint limits")
	print("neck: kind %d, moving hand over three heights, worst error %.5f m, palm clearance %.5f m" % [kind, worst, clearance])
	_check(worst < NeckAim.CONTACT, "muzzle stays at food across the clip and a drifting hand")
	_check(clearance > 0.01, "muzzle stays above the palm")
	dish.position.y = 3.0
	_check(not animal.neck.reachable(animal, dish, 0.0), "a high hand is unreachable")
	dish.position.y = 0.4
	dish.rotation.z = PI
	_check(not animal.neck.reachable(animal, dish, 0.0), "an overturned hand is not approached through its palm")
	animal.free()
	dish.free()
	await process_frame


func _live(kind: Beast.Kind) -> void:
	var a := Beast.new(kind, 1.0, 0.0)
	root.add_child(a)
	var h := Dish.new()
	root.add_child(h)
	h.visible = true
	h.position.y = 0.8 if kind == Beast.Kind.DEER else 0.4
	a.position.z = Hand.TOP.z + a.neck.stand_off(a, h)
	a.hand = h
	a.eat(h.position.y, 0.0)
	for frame in 180:
		h.position.x = sin(frame * 0.04) * 0.02
		await process_frame
		if frame > 30:
			_check(a.neck.touching(h), "live modifier keeps contact after the authored clip evaluates")
	a.hand = null
	for frame in 30:
		await process_frame
	_check(a.neck.amount == 0.0, "neck blends fully out after the offer ends")
	a.free()
	h.free()
	await process_frame
