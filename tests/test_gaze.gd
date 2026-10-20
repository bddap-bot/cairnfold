extends SceneTree

## Where a player's eyes look, and how others see it: the tracked gaze or a natural look stands in, steadied, and
## travels to the other players' copies of their avatar:
## godot4 --headless --fixed-fps 60 --path game --script ../tests/test_gaze.gd

var failures := 0
var main: Node


func _initialize() -> void:
	main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	_an_untracked_look_glances_at_the_nearest_face()
	_the_look_is_steady_but_quick()
	await _tracked_eyes_lead_the_look()
	await _the_look_reaches_the_other_players()
	print("tests: %s" % ("FAILED %d" % failures if failures else "ok"))
	Main.quit(self, 1 if failures else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _an_untracked_look_glances_at_the_nearest_face() -> void:
	var head := Transform3D(Basis(Vector3.UP, 0.5), Vector3(2, 1.6, 3))
	var ahead := -head.basis.z
	var near := head.origin + ahead.rotated(Vector3.UP, 0.3) * 1.5 + Vector3.UP * 0.1
	var far := head.origin + ahead.rotated(Vector3.UP, -0.2) * 3.0
	var looked: Vector3 = head.basis * Gaze.glance(head, [far, near])
	_check(looked.is_equal_approx((near - head.origin).normalized()), "an untracked look turns to the nearest face near ahead")
	_check(Gaze.glance(head, [head.origin - ahead * 1.5]).is_equal_approx(Vector3.FORWARD), "but not to one behind")
	_check(Gaze.glance(head, [head.origin + ahead * (Gaze.FACE_NEAR + 1.0)]).is_equal_approx(Vector3.FORWARD), "nor to one far off")
	_check(Gaze.glance(head, []).is_equal_approx(Vector3.FORWARD), "with nobody near, it looks ahead")


## A jump lands within a few frames, but frame-to-frame tracking noise barely moves the look.
func _the_look_is_steady_but_quick() -> void:
	var dt := 1.0 / 90.0
	var to := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(20.0))
	var look := Vector3.FORWARD
	for i in 6:
		look = Gaze.steady(look, to, dt)
	_check(rad_to_deg(look.angle_to(to)) < 2.0, "a 20 degree jump lands within 6 frames (%.1f degrees off)" % rad_to_deg(look.angle_to(to)))
	var wobble := 0.0
	for i in 90:
		var noisy := to.rotated(Vector3.RIGHT, deg_to_rad(0.5 if i % 2 else -0.5))
		look = Gaze.steady(look, noisy, dt)
		if i > 30:
			wobble = maxf(wobble, rad_to_deg(look.angle_to(to)))
	_check(wobble < 0.2, "half a degree of noise moves it less than 0.2 degrees (%.2f)" % wobble)


func _eyes_tracker() -> XRPositionalTracker:
	var t := XRPositionalTracker.new()
	t.type = XRServer.TRACKER_CONTROLLER
	t.name = &"/user/eyes_ext"
	XRServer.add_tracker(t)
	return t


## Tracked eyes lead the look; a blink holds it; tracking gone, the natural look takes over.
func _tracked_eyes_lead_the_look() -> void:
	var rig: Rig = main.rig
	var eyes := _eyes_tracker()
	var gaze_in_head := Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, -0.2)
	eyes.set_pose(&"default", rig.head.transform * Transform3D(gaze_in_head, Vector3.ZERO), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await _frames(20)
	var want := gaze_in_head * Vector3.FORWARD
	_check(rig.gaze.look.angle_to(want) < 0.01, "tracked eyes set the look (%s vs %s)" % [rig.gaze.look, want])
	eyes.invalidate_pose(&"default")
	await _frames(int(Gaze.BLINK * 60.0 * 0.5))
	_check(rig.gaze.look.angle_to(want) < 0.01, "a blink holds it")
	await _frames(60)
	_check(rig.gaze.look.angle_to(Vector3.FORWARD) < 0.01, "lost tracking falls back to looking ahead (%s)" % rig.gaze.look)
	eyes.set_pose(&"default", rig.head.transform * Transform3D(gaze_in_head, Vector3.ZERO), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await _frames(20)
	XRServer.remove_tracker(eyes)


## Two games in one: the joiner's look, as its gaze sets it, turns the eyes of its avatar in the host's garden.
func _the_look_reaches_the_other_players() -> void:
	var rig: Rig = main.rig
	var eyes := _eyes_tracker()
	var gaze_in_head := Basis(Vector3.UP, -0.5) * Basis(Vector3.RIGHT, 0.3)
	eyes.set_pose(&"default", rig.head.transform * Transform3D(gaze_in_head, Vector3.ZERO), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var beacons := 20000 + randi() % 20000
	var sessions: Array[Session] = []
	for i in 2:
		var branch := Node.new()
		root.add_child(branch)
		set_multiplayer(SceneMultiplayer.new(), branch.get_path())
		var s := Session.new(main.world, rig, i, Session.PORT, false, beacons)
		branch.add_child(s)
		sessions.append(s)
	var host := sessions[0]
	var joiner := sessions[1]
	await process_frame
	joiner.join("127.0.0.1", host.port)
	var seen: Avatar = null
	for n in 600:
		if not host.avatars.is_empty() and (host.avatars.values()[0] as Avatar).visible:
			seen = host.avatars.values()[0]
			break
		await process_frame
	_check(seen != null, "the host sees the joiner")
	if seen != null:
		await _frames(30)
		var want := gaze_in_head * Vector3.FORWARD
		_check(seen.look.angle_to(want) < 0.02, "the joiner's avatar looks where the joiner's eyes do (%s vs %s)" % [seen.look, want])
		var eye := seen.bone("leftEye")
		var rest: Transform3D = seen._joints.leftEye.rest
		var face: Vector3 = seen.bone("head").basis * seen._joints.head.rest.basis.inverse() * (seen._model.get_meta("forward") as Vector3)
		var points: Vector3 = eye.basis * rest.basis.inverse() * (seen._model.get_meta("forward") as Vector3)
		var right := seen.eyes.basis.x
		_check(points.dot(right) > face.dot(right) + 0.1 and points.dot(Vector3.UP) > face.dot(Vector3.UP) + 0.1, "and its eyes turn right and up with it")
	for s in sessions:
		s.get_parent().queue_free()
	XRServer.remove_tracker(eyes)
	await _frames(2)
