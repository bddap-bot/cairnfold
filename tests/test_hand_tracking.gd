extends "res://../tests/support/suite.gd"

## A hand the runtime reports joints for is played by them only when they are the hand's own, and its pinch reads as the
## trigger: godot4 --headless --fixed-fps 60 --path game --script ../tests/test_hand_tracking.gd


func _initialize() -> void:
	boot_main()
	_run.call_deferred()


func _run() -> void:
	await frames(3)
	var right: Hand = main.rig.right
	var controller := XRControllerTracker.new()
	controller.name = right.tracker
	controller.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(controller)
	var joints := XRHandTracker.new()
	joints.name = "/user/hand_tracker/right"
	joints.hand = XRPositionalTracker.TRACKER_HAND_RIGHT
	XRServer.add_tracker(joints)
	var palm := Transform3D(Basis.IDENTITY, Vector3(0.2, 1.3, -0.3))
	var pressed := Buttons.new(right).watch(["tool"])

	_shape(joints, palm, "index", XRHandTracker.HAND_TRACKING_SOURCE_CONTROLLER)
	await frames(2)
	check(not right.bare, "joints a controller drives leave the hand on its controller")

	_shape(joints, palm, "", XRHandTracker.HAND_TRACKING_SOURCE_UNKNOWN)
	controller.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(2)
	check(not right.bare, "joints of unknown source, with the controller posed, leave the hand on its controller")
	controller.invalidate_pose("aim")
	await frames(2)
	check(right.bare, "joints of unknown source with no controller pose play the hand")

	_shape(joints, palm, "", XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED)
	controller.set_pose("aim", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	await frames(2)
	check(right.bare, "the hand's own joints play it even with a controller posed")
	check(right.global_position.is_equal_approx(main.rig.global_transform * palm.origin), "a bare hand stands at its palm: %s" % right.global_position)
	check(not pressed.held("tool"), "an open hand holds no trigger")
	_shape(joints, palm, "index", XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED)
	await frames(1)
	check(pressed.held("tool") and right.gesture == "index", "thumb to index holds the trigger: %s" % right.gesture)
	_shape(joints, palm, "fist", XRHandTracker.HAND_TRACKING_SOURCE_UNOBSTRUCTED)
	await frames(1)
	check(right.gesture == "fist" and not pressed.held("tool"), "a fist, its thumb on the index, is a grip, not the trigger: %s" % right.gesture)

	await _stick_reads_the_palm(right)

	joints.has_tracking_data = false
	await frames(2)
	check(not right.bare, "a hand lost hands back to the controller")
	XRServer.remove_tracker(joints)
	XRServer.remove_tracker(controller)
	finish()


## A little pinch pushed sideways flicks the stick that way even with the arm stretched, so a reaching hand is thrown
## far: the stick reads the hand's own move, not the thrown hand's.
func _stick_reads_the_palm(right: Hand) -> void:
	right.tool = Hand.Tool.NONE
	var head: Transform3D = main.rig.head.global_transform
	var at := head * Lessons.frame({"at": Vector3(0.45, -0.3, -0.5), "aim": Vector3(0, -0.3, -1), "roll": 0.0})
	for f in 30:
		Hand.injected_joints[right.tracker] = HandShape.make(at, false, "")
		await frames(1)
	check(right.global_position.distance_to(at.origin) > 0.5, "the stretched hand is thrown out: %.2f m" % right.global_position.distance_to(at.origin))
	var flicked := false
	for f in 30:
		Hand.injected_joints[right.tracker] = HandShape.pressing(at, false, "primary_right", head.basis, clampf(f / 10.0 - 1.0, 0.0, 1.0))
		await frames(1)
		flicked = flicked or right.flick == "primary_right"
	check(flicked, "thumb to little pushed right flicks the stick right with the arm stretched: %s %s" % [right.stick(), right.flick])
	Hand.injected_joints.clear()
	await frames(2)


func _shape(t: XRHandTracker, palm: Transform3D, gesture: String, source: XRHandTracker.HandTrackingSource) -> void:
	var made := HandShape.make(palm, false, gesture)
	for j in made.size():
		t.set_hand_joint_transform(j, made[j])
		t.set_hand_joint_flags(j, XRHandTracker.HAND_JOINT_FLAG_POSITION_VALID | XRHandTracker.HAND_JOINT_FLAG_ORIENTATION_VALID)
	t.hand_tracking_source = source
	t.has_tracking_data = true
